import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../db.js';
import { ah, httpError } from '../middleware.js';

const r = Router();

r.post('/login', ah(async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) throw httpError(400, 'Username and password are required');

  const [u] = await query(
    `SELECT u.user_id, u.username, u.password_hash, u.role, u.customer_id, c.full_name
       FROM app_users u LEFT JOIN customers c ON c.customer_id = u.customer_id
      WHERE u.username = :u`, { u: String(username).toLowerCase() });

  if (!u || !(await bcrypt.compare(String(password), u.password_hash))) {
    throw httpError(401, 'Invalid username or password');
  }
  const user = { id: u.user_id, username: u.username, role: u.role,
                 customerId: u.customer_id, fullName: u.full_name || u.username };
  const token = jwt.sign(user, process.env.JWT_SECRET, { expiresIn: '8h' });
  res.json({ token, user });
}));

export default r;
