import { Router } from 'express';
import { run, query, outNum } from '../db.js';
import { ah, auth, roles, num, httpError, assertLoanAccess } from '../middleware.js';

const r = Router();
r.use(auth);

// Interest rate is set by the bank per product, never by the customer
const RATES = { HOME: 8.5, CAR: 9.5, EDUCATION: 9.0, PERSONAL: 11.5 };

r.get('/loans/quote', ah(async (req, res) => {
  const type = String(req.query.type || '').toUpperCase();
  if (!RATES[type]) throw httpError(400, 'Unknown loan type');
  const p = num(req.query.principal, 'Principal');
  const m = num(req.query.months, 'Tenure');
  const out = await run('BEGIN :e := bank_pkg.calc_emi(:p, :r, :m); END;', { e: outNum, p, r: RATES[type], m });
  res.json({ rate: RATES[type], emi: out.outBinds.e, total: out.outBinds.e * m });
}));

r.get('/loans', ah(async (req, res) => {
  const mine = req.user.role === 'CUSTOMER';
  res.json(await query(
    `SELECT l.loan_id, c.full_name, l.account_no, l.loan_type, l.principal, l.annual_rate,
            l.tenure_months, l.emi, l.emis_paid, l.outstanding, l.status, l.applied_on
       FROM loans l JOIN customers c ON c.customer_id = l.customer_id
      ${mine ? 'WHERE l.customer_id = :cid' : ''} ORDER BY l.loan_id DESC`,
    mine ? { cid: req.user.customerId } : {}));
}));

r.post('/loans', roles('CUSTOMER'), ah(async (req, res) => {
  const { accountNo, loanType, principal, months } = req.body || {};
  const type = String(loanType || '').toUpperCase();
  if (!RATES[type]) throw httpError(400, 'Unknown loan type');
  const out = await run('BEGIN bank_pkg.apply_loan(:c, :a, :t, :p, :r, :m, :id); END;', {
    c: req.user.customerId, a: num(accountNo, 'Account'), t: type,
    p: num(principal, 'Amount'), r: RATES[type], m: num(months, 'Tenure'), id: outNum });
  res.status(201).json({ loanId: out.outBinds.id });
}));

r.get('/loans/:id/tracking', ah(async (req, res) => {
  const id = num(req.params.id, 'Loan');
  await assertLoanAccess(req.user, id);
  res.json(await query(
    'SELECT status, changed_by, changed_on, remarks FROM loan_tracking WHERE loan_id = :id ORDER BY track_id', { id }));
}));

r.post('/loans/:id/approve', roles('LOAN_OFFICER', 'ADMIN'), ah(async (req, res) => {
  await run('BEGIN bank_pkg.approve_loan(:id, :o, :rm); END;',
    { id: num(req.params.id, 'Loan'), o: req.user.username, rm: req.body?.remarks || null });
  res.json({ ok: true });
}));

r.post('/loans/:id/reject', roles('LOAN_OFFICER', 'ADMIN'), ah(async (req, res) => {
  await run('BEGIN bank_pkg.reject_loan(:id, :o, :rm); END;',
    { id: num(req.params.id, 'Loan'), o: req.user.username, rm: req.body?.remarks || null });
  res.json({ ok: true });
}));

r.post('/loans/:id/repay', roles('CUSTOMER', 'TELLER', 'ADMIN'), ah(async (req, res) => {
  const id = num(req.params.id, 'Loan');
  await assertLoanAccess(req.user, id);
  await run('BEGIN bank_pkg.repay_emi(:id); END;', { id });
  res.json({ ok: true });
}));

export default r;
