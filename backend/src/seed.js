import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { initPool, run } from './db.js';

const PASSWORD = 'Password@123';
const users = [
  { u: 'admin',   role: 'ADMIN',        email: null },
  { u: 'teller',  role: 'TELLER',       email: null },
  { u: 'officer', role: 'LOAN_OFFICER', email: null },
  { u: 'arjun',   role: 'CUSTOMER',     email: 'arjun@example.com' },
  { u: 'meera',   role: 'CUSTOMER',     email: 'meera@example.com' },
  { u: 'rohan',   role: 'CUSTOMER',     email: 'rohan@example.com' },
];

await initPool();
await run('DELETE FROM app_users');
const hash = await bcrypt.hash(PASSWORD, 10);
for (const x of users) {
  await run(
    `INSERT INTO app_users (user_id, username, password_hash, role, customer_id)
     VALUES (seq_user.NEXTVAL, :u, :h, :r, (SELECT customer_id FROM customers WHERE email = :e))`,
    { u: x.u, h: hash, r: x.role, e: x.email });
  console.log(`created ${x.role.padEnd(12)} ${x.u}`);
}
console.log(`\nAll passwords: ${PASSWORD}`);
process.exit(0);
