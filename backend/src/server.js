import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { initPool } from './db.js';
import { errorHandler } from './middleware.js';
import authRoutes from './routes/auth.js';
import bankingRoutes from './routes/banking.js';
import loanRoutes from './routes/loans.js';
import supportRoutes from './routes/support.js';

if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET is not set (see .env.example)');

const app = express();
app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || 'http://localhost:5173' }));
app.use(express.json({ limit: '100kb' }));

app.use('/api/auth', rateLimit({ windowMs: 15 * 60 * 1000, max: 50 }), authRoutes);
app.use('/api', bankingRoutes);
app.use('/api', loanRoutes);
app.use('/api', supportRoutes);
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));

// Serve the built React app in production (frontend: npm run build)
const dist = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../frontend/dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist));
  app.get(/^\/(?!api).*/, (req, res) => res.sendFile(path.join(dist, 'index.html')));
}

app.use(errorHandler);

const port = process.env.PORT || 4000;
initPool()
  .then(() => app.listen(port, () => console.log(`API running on http://localhost:${port}`)))
  .catch((e) => { console.error('Could not connect to Oracle:', e.message); process.exit(1); });
