import { Router } from 'express';
import { run, query, miniStatement, outNum, outStr } from '../db.js';
import { ah, auth, roles, num, assertAccountAccess } from '../middleware.js';

const r = Router();
r.use(auth);

// ---- accounts ----
r.get('/accounts', ah(async (req, res) => {
  const mine = req.user.role === 'CUSTOMER';
  const rows = await query(
    `SELECT account_no, customer_id, full_name, bank_name, account_type, balance, status
       FROM v_account_summary ${mine ? 'WHERE customer_id = :cid' : ''}
      ORDER BY account_no FETCH FIRST 200 ROWS ONLY`,
    mine ? { cid: req.user.customerId } : {});
  res.json(rows);
}));

r.get('/accounts/:no/balance', ah(async (req, res) => {
  const no = num(req.params.no, 'Account');
  await assertAccountAccess(req.user, no);
  const out = await run('BEGIN :b := bank_pkg.get_balance(:a); END;', { b: outNum, a: no });
  res.json({ balance: out.outBinds.b });
}));

r.get('/accounts/:no/statement', ah(async (req, res) => {
  const no = num(req.params.no, 'Account');
  await assertAccountAccess(req.user, no);
  res.json(await miniStatement(no, Math.min(Number(req.query.count) || 10, 50)));
}));

// ---- teller desk ----
r.get('/customers', roles('TELLER', 'ADMIN'), ah(async (req, res) => {
  res.json(await query('SELECT customer_id, full_name, email, phone, status FROM customers ORDER BY customer_id'));
}));

r.post('/customers', roles('TELLER', 'ADMIN'), ah(async (req, res) => {
  const { name, dob, email, phone, kycId, address } = req.body || {};
  const out = await run(
    `BEGIN bank_pkg.create_customer(:n, TO_DATE(:d,'YYYY-MM-DD'), :e, :p, :k, :a, :id); END;`,
    { n: name, d: dob, e: email, p: phone, k: kycId, a: address || null, id: outNum });
  res.status(201).json({ customerId: out.outBinds.id });
}));

r.post('/accounts', roles('TELLER', 'ADMIN'), ah(async (req, res) => {
  const { customerId, type, initialDeposit, bankId } = req.body || {};
  const out = await run(
    'BEGIN bank_pkg.open_account(:c, :t, :d, :acc, :b); END;',
    { c: num(customerId, 'Customer'), t: type, d: num(initialDeposit ?? 0, 'Initial deposit'),
      acc: outNum, b: bankId ? num(bankId, 'Bank') : 1 });
  res.status(201).json({ accountNo: out.outBinds.acc });
}));

r.post('/accounts/:no/deposit', roles('TELLER', 'ADMIN'), ah(async (req, res) => {
  await run('BEGIN bank_pkg.deposit(:a, :m); END;',
    { a: num(req.params.no, 'Account'), m: num(req.body?.amount, 'Amount') });
  res.json({ ok: true });
}));

r.post('/accounts/:no/withdraw', roles('TELLER', 'ADMIN'), ah(async (req, res) => {
  await run('BEGIN bank_pkg.withdraw(:a, :m); END;',
    { a: num(req.params.no, 'Account'), m: num(req.body?.amount, 'Amount') });
  res.json({ ok: true });
}));

// ---- fund transfer (same or different bank) ----
r.post('/transfers', ah(async (req, res) => {
  const { from, to, amount, remarks } = req.body || {};
  const f = num(from, 'From account');
  const t = num(to, 'To account');
  const a = num(amount, 'Amount');
  await assertAccountAccess(req.user, f);
  const out = await run('BEGIN bank_pkg.transfer(:f, :t, :a, :rm, :ref); END;',
    { f, t, a, rm: remarks || null, ref: outStr });
  res.status(201).json({ ref: out.outBinds.ref });
}));

// ---- admin ----
r.post('/admin/interest', roles('ADMIN'), ah(async (req, res) => {
  const month = req.body?.month || null; // 'YYYY-MM'
  await run(`BEGIN bank_pkg.calculate_interest(NVL(TO_DATE(:m,'YYYY-MM'), TRUNC(SYSDATE,'MM'))); END;`, { m: month });
  res.json({ ok: true });
}));

r.get('/admin/interest-runs', roles('ADMIN'), ah(async (req, res) => {
  res.json(await query('SELECT run_month, accounts_paid, total_interest, run_on FROM interest_runs ORDER BY run_month DESC'));
}));

r.get('/admin/audit', roles('ADMIN'), ah(async (req, res) => {
  res.json(await query(
    `SELECT audit_id, table_name, action, key_value, new_value, changed_by, changed_at
       FROM audit_log ORDER BY audit_id DESC FETCH FIRST 100 ROWS ONLY`));
}));

export default r;
