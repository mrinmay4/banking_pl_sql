import { Router } from 'express';
import { run, query, outNum } from '../db.js';
import { ah, auth, roles, num, httpError, assertTicketAccess } from '../middleware.js';

const r = Router();
r.use(auth);

r.get('/tickets', ah(async (req, res) => {
  const mine = req.user.role === 'CUSTOMER';
  res.json(await query(
    `SELECT t.ticket_id, c.full_name, t.subject, t.status, t.created_at
       FROM support_tickets t JOIN customers c ON c.customer_id = t.customer_id
      ${mine ? 'WHERE t.customer_id = :cid' : ''} ORDER BY t.ticket_id DESC`,
    mine ? { cid: req.user.customerId } : {}));
}));

r.post('/tickets', roles('CUSTOMER'), ah(async (req, res) => {
  const { subject, message } = req.body || {};
  const out = await run('BEGIN bank_pkg.raise_ticket(:c, :s, :m, :id); END;',
    { c: req.user.customerId, s: subject, m: message, id: outNum });
  res.status(201).json({ ticketId: out.outBinds.id });
}));

r.get('/tickets/:id/messages', ah(async (req, res) => {
  const id = num(req.params.id, 'Ticket');
  await assertTicketAccess(req.user, id);
  res.json(await query(
    'SELECT msg_id, sender_type, message, sent_at FROM support_messages WHERE ticket_id = :id ORDER BY msg_id', { id }));
}));

r.post('/tickets/:id/reply', ah(async (req, res) => {
  const id = num(req.params.id, 'Ticket');
  await assertTicketAccess(req.user, id);
  if (!req.body?.message) throw httpError(400, 'Message is required');
  const sender = req.user.role === 'CUSTOMER' ? 'CUSTOMER' : 'AGENT';
  await run('BEGIN bank_pkg.reply_ticket(:id, :s, :m); END;', { id, s: sender, m: req.body.message });
  res.status(201).json({ ok: true });
}));

r.post('/tickets/:id/close', ah(async (req, res) => {
  const id = num(req.params.id, 'Ticket');
  await assertTicketAccess(req.user, id);
  await run('BEGIN bank_pkg.close_ticket(:id); END;', { id });
  res.json({ ok: true });
}));

export default r;
