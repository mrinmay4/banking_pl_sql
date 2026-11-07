# Banking Transaction Management System (Full Stack)

**React (Vite)** frontend · **Node.js + Express** API · **Oracle PL/SQL** business logic

All money logic (debit, credit, transfers, loans, interest, support tickets) lives in the Oracle package `BANK_PKG`. The Node API only authenticates users, checks roles and ownership, and calls the package. Overdraft and ledger rules are also enforced by database triggers.

```
banking-app/
├── database/   01_banking_system.sql (schema, triggers, BANK_PKG, demo data), 02_app_users.sql
├── backend/    Express API (JWT auth, role checks, oracledb)
└── frontend/   React single-page app
```

## Requirements
Node.js 18+, Oracle Database 12c+ (Oracle XE is fine). No Oracle Instant Client is needed (node-oracledb 6 thin mode).

## Setup

### 1. Database (Oracle XE via Docker, optional)
```bash
docker run -d --name oracle-xe -p 1521:1521 -e ORACLE_PASSWORD=oracle gvenzl/oracle-xe:21-slim
```
Connect as `system` / `oracle` to `localhost:1521/XEPDB1` and create the schema user:
```sql
CREATE USER bank IDENTIFIED BY bank123 QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE VIEW,
      CREATE PROCEDURE, CREATE TRIGGER TO bank;
```
Then connect as `bank` and run, in order:
```
@database/01_banking_system.sql
@database/02_app_users.sql
```
Script 01 also creates the demo customers (Arjun, Meera, Rohan) with accounts and transactions.

### 2. Backend
```bash
cd backend
cp .env.example .env        # edit DB_* and set a long random JWT_SECRET
npm install
npm run seed                # creates login users (password: Password@123)
npm run dev                 # http://localhost:4000
```

### 3. Frontend
```bash
cd frontend
npm install
npm run dev                 # http://localhost:5173 (proxies /api to :4000)
```
For production, run `npm run build` in `frontend`; the backend then serves `frontend/dist` itself.

## Demo logins (password `Password@123`)
| Username | Role | Can do |
|---|---|---|
| arjun, meera, rohan | Customer | View own accounts, statements, transfer, apply for / repay loans, support chat |
| teller | Teller | Create customers, open accounts, deposit / withdraw, answer tickets |
| officer | Loan officer | Approve / reject loans, answer tickets |
| admin | Admin | Everything, plus monthly interest batch and audit log |

## API overview
| Method | Path | Role |
|---|---|---|
| POST | /api/auth/login | public |
| GET | /api/accounts, /accounts/:no/balance, /accounts/:no/statement?count= | all (customers: own only) |
| POST | /api/transfers | customer (own source account), staff |
| POST | /api/customers, /accounts, /accounts/:no/deposit, /accounts/:no/withdraw | teller, admin |
| GET | /api/loans, /loans/quote, /loans/:id/tracking | all (customers: own only) |
| POST | /api/loans | customer |
| POST | /api/loans/:id/approve, /reject | loan officer, admin |
| POST | /api/loans/:id/repay | customer (own), teller, admin |
| GET/POST | /api/tickets, /tickets/:id/messages, /reply, /close | all (customers: own only) |
| POST/GET | /api/admin/interest, /admin/interest-runs, /admin/audit | admin |

Oracle `ORA-20xxx` errors from the package (insufficient funds, invalid amount, and so on) are returned as clean `400 { error }` messages and shown in the UI.

## Notes
- Loan interest rates are set per product on the server (Home 8.5%, Car 9.5%, Education 9.0%, Personal 11.5%). Customers cannot choose their own rate.
- The JWT is kept in `localStorage` for simplicity. For production, use httpOnly cookies and HTTPS.
- This is a learning/portfolio project and has not been security-audited.
