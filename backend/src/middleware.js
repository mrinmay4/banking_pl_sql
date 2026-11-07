import jwt from 'jsonwebtoken';
import { query } from './db.js';

export const STAFF = ['TELLER', 'LOAN_OFFICER', 'ADMIN'];

export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

export function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

export function num(v, name) {
  const n = Number(v);
  if (v === undefined || v === null || v === '' || !Number.isFinite(n)) {
    throw httpError(400, `${name} must be a number`);
  }
  return n;
}

export function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Not authenticated' });
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'Session expired, please log in again' });
  }
}

export const roles = (...allowed) => (req, res, next) =>
  allowed.includes(req.user.role) ? next() : res.status(403).json({ error: 'Not allowed for your role' });

// ---- ownership checks (customers may only touch their own data) ----
export async function assertAccountAccess(user, accNo) {
  if (user.role !== 'CUSTOMER') return;
  const r = await query('SELECT 1 AS ok FROM accounts WHERE account_no = :a AND customer_id = :c',
    { a: accNo, c: user.customerId });
  if (!r.length) throw httpError(403, 'This account is not yours');
}

export async function assertLoanAccess(user, loanId) {
  if (user.role !== 'CUSTOMER') return;
  const r = await query('SELECT 1 AS ok FROM loans WHERE loan_id = :l AND customer_id = :c',
    { l: loanId, c: user.customerId });
  if (!r.length) throw httpError(403, 'This loan is not yours');
}

export async function assertTicketAccess(user, ticketId) {
  if (user.role !== 'CUSTOMER') return;
  const r = await query('SELECT 1 AS ok FROM support_tickets WHERE ticket_id = :t AND customer_id = :c',
    { t: ticketId, c: user.customerId });
  if (!r.length) throw httpError(403, 'This ticket is not yours');
}

// Maps Oracle ORA-20xxx application errors from BANK_PKG to clean 400 responses
export function errorHandler(err, req, res, next) { // eslint-disable-line no-unused-vars
  const n = err.errorNum;
  if (n >= 20000 && n < 21000) {
    const msg = String(err.message).split('\n')[0].replace(/^ORA-\d+:\s*/, '');
    return res.status(400).json({ error: msg, code: n });
  }
  if (err.status) return res.status(err.status).json({ error: err.message });
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
}
