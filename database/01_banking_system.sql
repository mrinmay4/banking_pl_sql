/* =====================================================================
   BANKING TRANSACTION MANAGEMENT SYSTEM  -  Oracle PL/SQL (11g / 12c+)
   ---------------------------------------------------------------------
   Run in SQL*Plus / SQL Developer as a normal schema user:
       @banking_system.sql
   The script is re-runnable: it drops its own objects first.

   Sections
     1. Cleanup
     2. Sequences
     3. Tables
     4. Triggers (overdraft guard, logging, immutability, loan tracking)
     5. Views
     6. Package BANK_PKG (spec + body)
     7. Seed data (banks)
     8. Demo / test script
     9. Role-based access (run as DBA - commented)
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

/* ---------------------------------------------------------------------
   1. CLEANUP
   --------------------------------------------------------------------- */
BEGIN
  BEGIN EXECUTE IMMEDIATE 'DROP PACKAGE bank_pkg'; EXCEPTION WHEN OTHERS THEN NULL; END;
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('SUPPORT_MESSAGES','SUPPORT_TICKETS','LOAN_TRACKING','LOANS',
                                  'TRANSACTIONS','ACCOUNTS','CUSTOMERS','BANKS',
                                  'AUDIT_LOG','INTEREST_RUNS')
             ORDER BY CASE table_name
                        WHEN 'SUPPORT_MESSAGES' THEN 1 WHEN 'SUPPORT_TICKETS' THEN 2
                        WHEN 'LOAN_TRACKING' THEN 3 WHEN 'LOANS' THEN 4
                        WHEN 'TRANSACTIONS' THEN 5 WHEN 'ACCOUNTS' THEN 6
                        WHEN 'CUSTOMERS' THEN 7 WHEN 'BANKS' THEN 8 ELSE 9 END) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE 'SEQ\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
END;
/

/* ---------------------------------------------------------------------
   2. SEQUENCES
   --------------------------------------------------------------------- */
CREATE SEQUENCE seq_customer START WITH 1001       INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_account  START WITH 1000100001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_txn      START WITH 100001     INCREMENT BY 1 CACHE 50;
CREATE SEQUENCE seq_transfer START WITH 1          INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_loan     START WITH 5001       INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_track    START WITH 1          INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_ticket   START WITH 9001       INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_msg      START WITH 1          INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_audit    START WITH 1          INCREMENT BY 1 CACHE 50;

/* ---------------------------------------------------------------------
   3. TABLES
   --------------------------------------------------------------------- */
CREATE TABLE banks (
  bank_id      NUMBER(4)    PRIMARY KEY,
  bank_name    VARCHAR2(60) NOT NULL,
  ifsc_prefix  VARCHAR2(4)  NOT NULL UNIQUE,
  is_home      CHAR(1)      DEFAULT 'N' NOT NULL CHECK (is_home IN ('Y','N'))
);

CREATE TABLE customers (
  customer_id  NUMBER(10)    PRIMARY KEY,
  full_name    VARCHAR2(100) NOT NULL,
  dob          DATE          NOT NULL,
  email        VARCHAR2(120) NOT NULL UNIQUE,
  phone        VARCHAR2(15)  NOT NULL UNIQUE,
  kyc_id       VARCHAR2(20)  NOT NULL UNIQUE,
  address      VARCHAR2(250),
  status       VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL
               CHECK (status IN ('ACTIVE','BLOCKED')),
  created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE accounts (
  account_no     NUMBER(12)   PRIMARY KEY,
  customer_id    NUMBER(10)   NOT NULL REFERENCES customers (customer_id),
  bank_id        NUMBER(4)    NOT NULL REFERENCES banks (bank_id),
  account_type   VARCHAR2(10) NOT NULL CHECK (account_type IN ('SAVINGS','CURRENT')),
  balance        NUMBER(15,2) DEFAULT 0 NOT NULL,
  min_balance    NUMBER(15,2) DEFAULT 0 NOT NULL,
  interest_rate  NUMBER(5,2)  DEFAULT 0 NOT NULL,
  status         VARCHAR2(10) DEFAULT 'ACTIVE' NOT NULL
                 CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
  opened_on      DATE         DEFAULT SYSDATE NOT NULL
);
CREATE INDEX ix_accounts_customer ON accounts (customer_id);
CREATE INDEX ix_accounts_bank     ON accounts (bank_id);

CREATE TABLE transactions (
  txn_id            NUMBER(14)    PRIMARY KEY,
  account_no        NUMBER(12)    NOT NULL REFERENCES accounts (account_no),
  txn_type          VARCHAR2(20)  NOT NULL
                    CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER_OUT','TRANSFER_IN',
                                        'INTEREST','FEE','LOAN_DISBURSAL','LOAN_REPAYMENT')),
  dr_cr             CHAR(1)       NOT NULL CHECK (dr_cr IN ('D','C')),
  amount            NUMBER(15,2)  NOT NULL CHECK (amount > 0),
  balance_after     NUMBER(15,2)  NOT NULL,
  txn_time          TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  transfer_ref      VARCHAR2(40),
  counterparty_acc  NUMBER(12),
  description       VARCHAR2(200)
);
CREATE INDEX ix_txn_acc_time ON transactions (account_no, txn_time);
CREATE INDEX ix_txn_ref      ON transactions (transfer_ref);

CREATE TABLE loans (
  loan_id        NUMBER(10)   PRIMARY KEY,
  customer_id    NUMBER(10)   NOT NULL REFERENCES customers (customer_id),
  account_no     NUMBER(12)   NOT NULL REFERENCES accounts (account_no),
  loan_type      VARCHAR2(12) NOT NULL CHECK (loan_type IN ('HOME','CAR','PERSONAL','EDUCATION')),
  principal      NUMBER(15,2) NOT NULL CHECK (principal > 0),
  annual_rate    NUMBER(5,2)  NOT NULL CHECK (annual_rate >= 0),
  tenure_months  NUMBER(3)    NOT NULL CHECK (tenure_months > 0),
  emi            NUMBER(15,2) NOT NULL,
  outstanding    NUMBER(15,2) DEFAULT 0 NOT NULL,
  emis_paid      NUMBER(3)    DEFAULT 0 NOT NULL,
  status         VARCHAR2(12) DEFAULT 'APPLIED' NOT NULL
                 CHECK (status IN ('APPLIED','APPROVED','REJECTED','DISBURSED','CLOSED')),
  applied_on     DATE         DEFAULT SYSDATE NOT NULL,
  decided_on     DATE,
  decided_by     VARCHAR2(30),
  remarks        VARCHAR2(250)
);
CREATE INDEX ix_loans_customer ON loans (customer_id);

CREATE TABLE loan_tracking (
  track_id    NUMBER(12)   PRIMARY KEY,
  loan_id     NUMBER(10)   NOT NULL REFERENCES loans (loan_id),
  status      VARCHAR2(12) NOT NULL,
  changed_by  VARCHAR2(30),
  changed_on  TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  remarks     VARCHAR2(250)
);

CREATE TABLE support_tickets (
  ticket_id    NUMBER(10)    PRIMARY KEY,
  customer_id  NUMBER(10)    NOT NULL REFERENCES customers (customer_id),
  subject      VARCHAR2(150) NOT NULL,
  status       VARCHAR2(10)  DEFAULT 'OPEN' NOT NULL
               CHECK (status IN ('OPEN','ANSWERED','CLOSED')),
  created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  closed_at    TIMESTAMP
);

CREATE TABLE support_messages (
  msg_id       NUMBER(12)    PRIMARY KEY,
  ticket_id    NUMBER(10)    NOT NULL REFERENCES support_tickets (ticket_id),
  sender_type  VARCHAR2(10)  NOT NULL CHECK (sender_type IN ('CUSTOMER','AGENT','BOT')),
  message      VARCHAR2(1000) NOT NULL,
  sent_at      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE audit_log (
  audit_id    NUMBER(14)    PRIMARY KEY,
  table_name  VARCHAR2(30)  NOT NULL,
  action      VARCHAR2(10)  NOT NULL,
  key_value   VARCHAR2(40),
  old_value   VARCHAR2(400),
  new_value   VARCHAR2(400),
  changed_by  VARCHAR2(30)  DEFAULT USER,
  changed_at  TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE interest_runs (
  run_month       DATE         PRIMARY KEY,
  accounts_paid   NUMBER(8)    NOT NULL,
  total_interest  NUMBER(15,2) NOT NULL,
  run_on          TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL
);

/* ---------------------------------------------------------------------
   4. TRIGGERS
   --------------------------------------------------------------------- */

-- 4.1 Overdraft + frozen-account guard (last line of defence at DB level)
CREATE OR REPLACE TRIGGER trg_accounts_guard
BEFORE UPDATE OF balance ON accounts
FOR EACH ROW
BEGIN
  IF :NEW.balance <> :OLD.balance AND :OLD.status <> 'ACTIVE' THEN
    RAISE_APPLICATION_ERROR(-20004,
      'Account ' || :OLD.account_no || ' is ' || :OLD.status || ' - balance cannot change');
  END IF;

  IF :NEW.balance < :OLD.balance AND :NEW.balance < :NEW.min_balance THEN
    RAISE_APPLICATION_ERROR(-20001,
      'Insufficient funds: account ' || :OLD.account_no ||
      ' cannot go below minimum balance of ' || :NEW.min_balance);
  END IF;
END;
/

-- 4.2 Audit every balance / status change on accounts
CREATE OR REPLACE TRIGGER trg_accounts_audit
AFTER UPDATE OF balance, status ON accounts
FOR EACH ROW
BEGIN
  INSERT INTO audit_log (audit_id, table_name, action, key_value, old_value, new_value)
  VALUES (seq_audit.NEXTVAL, 'ACCOUNTS', 'UPDATE', TO_CHAR(:OLD.account_no),
          'balance=' || :OLD.balance || ';status=' || :OLD.status,
          'balance=' || :NEW.balance || ';status=' || :NEW.status);
END;
/

-- 4.3 Assign transaction id automatically
CREATE OR REPLACE TRIGGER trg_txn_bi
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
  :NEW.txn_id := seq_txn.NEXTVAL;
END;
/

-- 4.4 Automatically log every transaction
CREATE OR REPLACE TRIGGER trg_txn_audit
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
  INSERT INTO audit_log (audit_id, table_name, action, key_value, new_value)
  VALUES (seq_audit.NEXTVAL, 'TRANSACTIONS', 'INSERT', TO_CHAR(:NEW.txn_id),
          :NEW.txn_type || ' ' || :NEW.dr_cr || ' ' || :NEW.amount ||
          ' acc=' || :NEW.account_no || ' bal=' || :NEW.balance_after);
END;
/

-- 4.5 Ledger is immutable: no updates / deletes on transactions
CREATE OR REPLACE TRIGGER trg_txn_immutable
BEFORE UPDATE OR DELETE ON transactions
BEGIN
  RAISE_APPLICATION_ERROR(-20010, 'Transactions are immutable and cannot be changed or deleted');
END;
/

-- 4.6 Loan status tracking (approval workflow history)
CREATE OR REPLACE TRIGGER trg_loans_track
AFTER INSERT OR UPDATE OF status ON loans
FOR EACH ROW
BEGIN
  INSERT INTO loan_tracking (track_id, loan_id, status, changed_by, remarks)
  VALUES (seq_track.NEXTVAL, :NEW.loan_id, :NEW.status,
          NVL(:NEW.decided_by, USER), :NEW.remarks);
END;
/

/* ---------------------------------------------------------------------
   5. VIEWS
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_account_summary AS
SELECT a.account_no, c.customer_id, c.full_name, b.bank_name, a.account_type,
       a.balance, a.status, a.opened_on
  FROM accounts a
  JOIN customers c ON c.customer_id = a.customer_id
  JOIN banks b     ON b.bank_id     = a.bank_id;

CREATE OR REPLACE VIEW v_loan_status AS
SELECT l.loan_id, c.full_name, l.loan_type, l.principal, l.annual_rate,
       l.tenure_months, l.emi, l.emis_paid, l.outstanding, l.status, l.applied_on, l.decided_on
  FROM loans l JOIN customers c ON c.customer_id = l.customer_id;

/* ---------------------------------------------------------------------
   6. PACKAGE BANK_PKG
   --------------------------------------------------------------------- */
CREATE OR REPLACE PACKAGE bank_pkg AS
  ---------------- user-defined exceptions ----------------
  e_insufficient_funds EXCEPTION;  PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
  e_invalid_amount     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_invalid_amount,     -20002);
  e_account_not_found  EXCEPTION;  PRAGMA EXCEPTION_INIT(e_account_not_found,  -20003);
  e_account_inactive   EXCEPTION;  PRAGMA EXCEPTION_INIT(e_account_inactive,   -20004);
  e_same_account       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_same_account,       -20005);
  e_loan_state         EXCEPTION;  PRAGMA EXCEPTION_INIT(e_loan_state,         -20006);
  e_customer_error     EXCEPTION;  PRAGMA EXCEPTION_INIT(e_customer_error,     -20007);
  e_loan_params        EXCEPTION;  PRAGMA EXCEPTION_INIT(e_loan_params,        -20008);
  e_ticket_error       EXCEPTION;  PRAGMA EXCEPTION_INIT(e_ticket_error,       -20009);
  e_interest_done      EXCEPTION;  PRAGMA EXCEPTION_INIT(e_interest_done,      -20011);

  c_home_bank CONSTANT NUMBER := 1;

  ---------------- Module 1: onboarding ----------------
  PROCEDURE create_customer (p_name VARCHAR2, p_dob DATE, p_email VARCHAR2, p_phone VARCHAR2,
                             p_kyc_id VARCHAR2, p_address VARCHAR2,
                             p_customer_id OUT NUMBER);

  PROCEDURE open_account (p_customer_id NUMBER, p_account_type VARCHAR2,
                          p_initial_deposit NUMBER, p_account_no OUT NUMBER,
                          p_bank_id NUMBER DEFAULT 1);

  ---------------- core transactions ----------------
  PROCEDURE deposit  (p_account_no NUMBER, p_amount NUMBER, p_description VARCHAR2 DEFAULT 'Cash deposit');
  PROCEDURE withdraw (p_account_no NUMBER, p_amount NUMBER, p_description VARCHAR2 DEFAULT 'Cash withdrawal');
  FUNCTION  get_balance (p_account_no NUMBER) RETURN NUMBER;

  ---------------- Module 2: fund transfer ----------------
  FUNCTION  calc_transfer_fee (p_amount NUMBER) RETURN NUMBER;
  PROCEDURE transfer (p_from_acc NUMBER, p_to_acc NUMBER, p_amount NUMBER,
                      p_remarks VARCHAR2 DEFAULT NULL, p_transfer_ref OUT VARCHAR2);

  ---------------- Module 3: statements ----------------
  PROCEDURE mini_statement (p_account_no NUMBER, p_count NUMBER DEFAULT 5,
                            p_result OUT SYS_REFCURSOR);

  ---------------- Module 4: loans ----------------
  FUNCTION  calc_emi (p_principal NUMBER, p_annual_rate NUMBER, p_months NUMBER) RETURN NUMBER;
  PROCEDURE apply_loan  (p_customer_id NUMBER, p_account_no NUMBER, p_loan_type VARCHAR2,
                         p_principal NUMBER, p_annual_rate NUMBER, p_tenure_months NUMBER,
                         p_loan_id OUT NUMBER);
  PROCEDURE approve_loan (p_loan_id NUMBER, p_officer VARCHAR2, p_remarks VARCHAR2 DEFAULT NULL);
  PROCEDURE reject_loan  (p_loan_id NUMBER, p_officer VARCHAR2, p_remarks VARCHAR2);
  PROCEDURE repay_emi    (p_loan_id NUMBER);

  ---------------- interest (cursor based batch) ----------------
  PROCEDURE calculate_interest (p_run_month DATE DEFAULT TRUNC(SYSDATE, 'MM'));

  ---------------- customer support chat ----------------
  PROCEDURE raise_ticket (p_customer_id NUMBER, p_subject VARCHAR2, p_message VARCHAR2,
                          p_ticket_id OUT NUMBER);
  PROCEDURE reply_ticket (p_ticket_id NUMBER, p_sender_type VARCHAR2, p_message VARCHAR2);
  PROCEDURE close_ticket (p_ticket_id NUMBER);
END bank_pkg;
/

CREATE OR REPLACE PACKAGE BODY bank_pkg AS

  /* ================= private helpers ================= */

  PROCEDURE check_amount (p_amount NUMBER) IS
  BEGIN
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> ROUND(p_amount, 2) THEN
      RAISE_APPLICATION_ERROR(-20002,
        'Invalid amount: must be positive with at most 2 decimal places');
    END IF;
  END check_amount;

  FUNCTION get_account (p_account_no NUMBER, p_lock BOOLEAN DEFAULT FALSE)
    RETURN accounts%ROWTYPE IS
    v_acc accounts%ROWTYPE;
  BEGIN
    IF p_lock THEN
      SELECT * INTO v_acc FROM accounts WHERE account_no = p_account_no FOR UPDATE;
    ELSE
      SELECT * INTO v_acc FROM accounts WHERE account_no = p_account_no;
    END IF;
    RETURN v_acc;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20003, 'Account ' || p_account_no || ' not found');
  END get_account;

  PROCEDURE assert_active (p_acc accounts%ROWTYPE) IS
  BEGIN
    IF p_acc.status <> 'ACTIVE' THEN
      RAISE_APPLICATION_ERROR(-20004,
        'Account ' || p_acc.account_no || ' is ' || p_acc.status);
    END IF;
  END assert_active;

  -- Single place that changes a balance and writes the ledger entry
  PROCEDURE post_txn (p_account_no NUMBER, p_type VARCHAR2, p_amount NUMBER,
                      p_dr_cr CHAR, p_ref VARCHAR2, p_counter NUMBER, p_desc VARCHAR2) IS
    v_bal accounts.balance%TYPE;
  BEGIN
    IF p_dr_cr = 'D' THEN
      UPDATE accounts SET balance = balance - p_amount
       WHERE account_no = p_account_no
      RETURNING balance INTO v_bal;
    ELSE
      UPDATE accounts SET balance = balance + p_amount
       WHERE account_no = p_account_no
      RETURNING balance INTO v_bal;
    END IF;

    INSERT INTO transactions (account_no, txn_type, dr_cr, amount, balance_after,
                              transfer_ref, counterparty_acc, description)
    VALUES (p_account_no, p_type, p_dr_cr, p_amount, v_bal, p_ref, p_counter, p_desc);
  END post_txn;

  FUNCTION bot_reply (p_message VARCHAR2) RETURN VARCHAR2 IS
    v_msg VARCHAR2(1000) := LOWER(p_message);
  BEGIN
    IF    INSTR(v_msg, 'balance')  > 0 THEN
      RETURN 'You can view your balance and mini statement under Accounts. An agent will follow up if needed.';
    ELSIF INSTR(v_msg, 'loan')     > 0 THEN
      RETURN 'Loan applications are reviewed by a loan officer. You can track the status under Loans.';
    ELSIF INSTR(v_msg, 'transfer') > 0 THEN
      RETURN 'Same-bank transfers are free. Inter-bank transfers carry a small fee based on the amount.';
    ELSE
      RETURN 'Thanks for contacting us. Your request has been logged and an agent will reply shortly.';
    END IF;
  END bot_reply;

  /* ================= Module 1: onboarding ================= */

  PROCEDURE create_customer (p_name VARCHAR2, p_dob DATE, p_email VARCHAR2, p_phone VARCHAR2,
                             p_kyc_id VARCHAR2, p_address VARCHAR2,
                             p_customer_id OUT NUMBER) IS
  BEGIN
    IF p_name IS NULL OR LENGTH(TRIM(p_name)) < 3 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Customer name is required (min 3 characters)');
    END IF;
    IF p_dob IS NULL OR p_dob > ADD_MONTHS(TRUNC(SYSDATE), -12 * 18) THEN
      RAISE_APPLICATION_ERROR(-20007, 'Customer must be at least 18 years old');
    END IF;
    IF p_email IS NULL OR INSTR(p_email, '@') < 2 OR INSTR(p_email, '.', INSTR(p_email, '@')) = 0 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Invalid e-mail address');
    END IF;
    IF p_phone IS NULL OR NOT REGEXP_LIKE(p_phone, '^[0-9+]{8,15}$') THEN
      RAISE_APPLICATION_ERROR(-20007, 'Invalid phone number');
    END IF;

    INSERT INTO customers (customer_id, full_name, dob, email, phone, kyc_id, address)
    VALUES (seq_customer.NEXTVAL, TRIM(p_name), p_dob, LOWER(p_email), p_phone, p_kyc_id, p_address)
    RETURNING customer_id INTO p_customer_id;
    COMMIT;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20007, 'E-mail, phone or KYC id is already registered');
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END create_customer;

  PROCEDURE open_account (p_customer_id NUMBER, p_account_type VARCHAR2,
                          p_initial_deposit NUMBER, p_account_no OUT NUMBER,
                          p_bank_id NUMBER DEFAULT 1) IS
    v_status    customers.status%TYPE;
    v_type      VARCHAR2(10) := UPPER(p_account_type);
    v_min       NUMBER;
    v_rate      NUMBER;
  BEGIN
    BEGIN
      SELECT status INTO v_status FROM customers WHERE customer_id = p_customer_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20007, 'Customer ' || p_customer_id || ' does not exist');
    END;
    IF v_status <> 'ACTIVE' THEN
      RAISE_APPLICATION_ERROR(-20007, 'Customer is blocked');
    END IF;

    IF v_type = 'SAVINGS' THEN v_min := 500; v_rate := 3.50;
    ELSIF v_type = 'CURRENT' THEN v_min := 0; v_rate := 0;
    ELSE RAISE_APPLICATION_ERROR(-20007, 'Account type must be SAVINGS or CURRENT');
    END IF;

    IF NVL(p_initial_deposit, 0) < v_min THEN
      RAISE_APPLICATION_ERROR(-20002, 'Initial deposit must be at least ' || v_min);
    END IF;

    INSERT INTO accounts (account_no, customer_id, bank_id, account_type, balance, min_balance, interest_rate)
    VALUES (seq_account.NEXTVAL, p_customer_id, p_bank_id, v_type, 0, v_min, v_rate)
    RETURNING account_no INTO p_account_no;

    IF p_initial_deposit > 0 THEN
      check_amount(p_initial_deposit);
      post_txn(p_account_no, 'DEPOSIT', p_initial_deposit, 'C', NULL, NULL, 'Opening deposit');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END open_account;

  /* ================= core transactions ================= */

  PROCEDURE deposit (p_account_no NUMBER, p_amount NUMBER, p_description VARCHAR2 DEFAULT 'Cash deposit') IS
    v_acc accounts%ROWTYPE;
  BEGIN
    check_amount(p_amount);
    v_acc := get_account(p_account_no, TRUE);
    assert_active(v_acc);
    post_txn(p_account_no, 'DEPOSIT', p_amount, 'C', NULL, NULL, p_description);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END deposit;

  PROCEDURE withdraw (p_account_no NUMBER, p_amount NUMBER, p_description VARCHAR2 DEFAULT 'Cash withdrawal') IS
    v_acc accounts%ROWTYPE;
  BEGIN
    check_amount(p_amount);
    v_acc := get_account(p_account_no, TRUE);
    assert_active(v_acc);
    -- overdraft is enforced by trigger TRG_ACCOUNTS_GUARD (raises -20001)
    post_txn(p_account_no, 'WITHDRAWAL', p_amount, 'D', NULL, NULL, p_description);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END withdraw;

  FUNCTION get_balance (p_account_no NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN get_account(p_account_no).balance;
  END get_balance;

  /* ================= Module 2: fund transfer ================= */

  FUNCTION calc_transfer_fee (p_amount NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN CASE
             WHEN p_amount <= 10000  THEN 2.50
             WHEN p_amount <= 100000 THEN 5.00
             ELSE 15.00
           END;
  END calc_transfer_fee;

  PROCEDURE transfer (p_from_acc NUMBER, p_to_acc NUMBER, p_amount NUMBER,
                      p_remarks VARCHAR2 DEFAULT NULL, p_transfer_ref OUT VARCHAR2) IS
    v_from accounts%ROWTYPE;
    v_to   accounts%ROWTYPE;
    v_fee  NUMBER := 0;
    v_ref  VARCHAR2(40);
  BEGIN
    SAVEPOINT sp_transfer;

    check_amount(p_amount);
    IF p_from_acc = p_to_acc THEN
      RAISE_APPLICATION_ERROR(-20005, 'Source and destination account are the same');
    END IF;

    -- Lock both rows in a fixed order (lowest account first) to avoid deadlocks
    FOR r IN (SELECT account_no FROM accounts
               WHERE account_no IN (p_from_acc, p_to_acc)
               ORDER BY account_no FOR UPDATE) LOOP
      NULL;
    END LOOP;

    v_from := get_account(p_from_acc);
    v_to   := get_account(p_to_acc);
    assert_active(v_from);
    assert_active(v_to);

    -- Inter-bank transfers carry a fee
    IF v_from.bank_id <> v_to.bank_id THEN
      v_fee := calc_transfer_fee(p_amount);
    END IF;

    v_ref := 'TRF' || TO_CHAR(SYSDATE, 'YYMMDD') || LPAD(seq_transfer.NEXTVAL, 8, '0');

    post_txn(p_from_acc, 'TRANSFER_OUT', p_amount, 'D', v_ref, p_to_acc,
             NVL(p_remarks, 'Transfer to ' || p_to_acc));
    post_txn(p_to_acc,   'TRANSFER_IN',  p_amount, 'C', v_ref, p_from_acc,
             NVL(p_remarks, 'Transfer from ' || p_from_acc));
    IF v_fee > 0 THEN
      post_txn(p_from_acc, 'FEE', v_fee, 'D', v_ref, NULL, 'Inter-bank transfer fee');
    END IF;

    p_transfer_ref := v_ref;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_transfer;
      p_transfer_ref := NULL;
      RAISE;
  END transfer;

  /* ================= Module 3: statements ================= */

  PROCEDURE mini_statement (p_account_no NUMBER, p_count NUMBER DEFAULT 5,
                            p_result OUT SYS_REFCURSOR) IS
    v_acc accounts%ROWTYPE;
  BEGIN
    v_acc := get_account(p_account_no);   -- validates existence
    OPEN p_result FOR
      SELECT *
        FROM (SELECT txn_id,
                     TO_CHAR(txn_time, 'DD-MON-YYYY HH24:MI') AS txn_time,
                     txn_type, dr_cr, amount, balance_after, description
                FROM transactions
               WHERE account_no = p_account_no
               ORDER BY txn_time DESC, txn_id DESC)
       WHERE ROWNUM <= LEAST(GREATEST(NVL(p_count, 5), 1), 50);
  END mini_statement;

  /* ================= Module 4: loans ================= */

  FUNCTION calc_emi (p_principal NUMBER, p_annual_rate NUMBER, p_months NUMBER) RETURN NUMBER IS
    r NUMBER := p_annual_rate / 12 / 100;
  BEGIN
    IF r = 0 THEN
      RETURN ROUND(p_principal / p_months, 2);
    END IF;
    RETURN ROUND(p_principal * r * POWER(1 + r, p_months) / (POWER(1 + r, p_months) - 1), 2);
  END calc_emi;

  PROCEDURE apply_loan (p_customer_id NUMBER, p_account_no NUMBER, p_loan_type VARCHAR2,
                        p_principal NUMBER, p_annual_rate NUMBER, p_tenure_months NUMBER,
                        p_loan_id OUT NUMBER) IS
    v_acc accounts%ROWTYPE;
    v_emi NUMBER;
  BEGIN
    v_acc := get_account(p_account_no);
    IF v_acc.customer_id <> p_customer_id THEN
      RAISE_APPLICATION_ERROR(-20008, 'Account does not belong to this customer');
    END IF;
    IF p_principal IS NULL OR p_principal NOT BETWEEN 10000 AND 5000000 THEN
      RAISE_APPLICATION_ERROR(-20008, 'Loan amount must be between 10,000 and 5,000,000');
    END IF;
    IF p_tenure_months IS NULL OR p_tenure_months NOT BETWEEN 6 AND 360 THEN
      RAISE_APPLICATION_ERROR(-20008, 'Tenure must be between 6 and 360 months');
    END IF;
    IF p_annual_rate IS NULL OR p_annual_rate NOT BETWEEN 0 AND 40 THEN
      RAISE_APPLICATION_ERROR(-20008, 'Interest rate must be between 0 and 40 percent');
    END IF;

    v_emi := calc_emi(p_principal, p_annual_rate, p_tenure_months);

    INSERT INTO loans (loan_id, customer_id, account_no, loan_type, principal,
                       annual_rate, tenure_months, emi)
    VALUES (seq_loan.NEXTVAL, p_customer_id, p_account_no, UPPER(p_loan_type), p_principal,
            p_annual_rate, p_tenure_months, v_emi)
    RETURNING loan_id INTO p_loan_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END apply_loan;

  PROCEDURE approve_loan (p_loan_id NUMBER, p_officer VARCHAR2, p_remarks VARCHAR2 DEFAULT NULL) IS
    v_loan loans%ROWTYPE;
    v_acc  accounts%ROWTYPE;
  BEGIN
    BEGIN
      SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20006, 'Loan ' || p_loan_id || ' not found');
    END;
    IF v_loan.status <> 'APPLIED' THEN
      RAISE_APPLICATION_ERROR(-20006, 'Only APPLIED loans can be approved (current: ' || v_loan.status || ')');
    END IF;

    UPDATE loans
       SET status = 'APPROVED', decided_on = SYSDATE, decided_by = p_officer,
           remarks = NVL(p_remarks, 'Approved')
     WHERE loan_id = p_loan_id;

    -- disburse into the customer's account
    v_acc := get_account(v_loan.account_no, TRUE);
    assert_active(v_acc);
    post_txn(v_loan.account_no, 'LOAN_DISBURSAL', v_loan.principal, 'C', NULL, NULL,
             'Loan #' || p_loan_id || ' disbursal');

    UPDATE loans
       SET status = 'DISBURSED',
           outstanding = emi * tenure_months,
           remarks = 'Disbursed'
     WHERE loan_id = p_loan_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END approve_loan;

  PROCEDURE reject_loan (p_loan_id NUMBER, p_officer VARCHAR2, p_remarks VARCHAR2) IS
    v_status loans.status%TYPE;
  BEGIN
    BEGIN
      SELECT status INTO v_status FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20006, 'Loan ' || p_loan_id || ' not found');
    END;
    IF v_status <> 'APPLIED' THEN
      RAISE_APPLICATION_ERROR(-20006, 'Only APPLIED loans can be rejected (current: ' || v_status || ')');
    END IF;
    IF p_remarks IS NULL THEN
      RAISE_APPLICATION_ERROR(-20006, 'A rejection reason is required');
    END IF;
    UPDATE loans
       SET status = 'REJECTED', decided_on = SYSDATE, decided_by = p_officer, remarks = p_remarks
     WHERE loan_id = p_loan_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END reject_loan;

  PROCEDURE repay_emi (p_loan_id NUMBER) IS
    v_loan loans%ROWTYPE;
    v_acc  accounts%ROWTYPE;
    v_pay  NUMBER;
  BEGIN
    BEGIN
      SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20006, 'Loan ' || p_loan_id || ' not found');
    END;
    IF v_loan.status <> 'DISBURSED' THEN
      RAISE_APPLICATION_ERROR(-20006, 'Loan is not open for repayment (status: ' || v_loan.status || ')');
    END IF;

    v_pay := LEAST(v_loan.emi, v_loan.outstanding);
    v_acc := get_account(v_loan.account_no, TRUE);
    assert_active(v_acc);
    post_txn(v_loan.account_no, 'LOAN_REPAYMENT', v_pay, 'D', NULL, NULL,
             'EMI ' || (v_loan.emis_paid + 1) || ' for loan #' || p_loan_id);

    UPDATE loans
       SET outstanding = outstanding - v_pay,
           emis_paid   = emis_paid + 1,
           status      = CASE WHEN outstanding - v_pay <= 0 THEN 'CLOSED' ELSE 'DISBURSED' END
     WHERE loan_id = p_loan_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END repay_emi;

  /* ================= interest calculation (cursor) ================= */

  PROCEDURE calculate_interest (p_run_month DATE DEFAULT TRUNC(SYSDATE, 'MM')) IS
    v_month  DATE := TRUNC(p_run_month, 'MM');
    v_exists NUMBER;
    v_int    NUMBER;
    v_count  PLS_INTEGER := 0;
    v_total  NUMBER := 0;

    CURSOR c_savings IS
      SELECT account_no, balance, interest_rate
        FROM accounts
       WHERE account_type = 'SAVINGS' AND status = 'ACTIVE' AND balance > 0
         FOR UPDATE;
  BEGIN
    SELECT COUNT(*) INTO v_exists FROM interest_runs WHERE run_month = v_month;
    IF v_exists > 0 THEN
      RAISE_APPLICATION_ERROR(-20011,
        'Interest for ' || TO_CHAR(v_month, 'MON-YYYY') || ' has already been posted');
    END IF;

    FOR r IN c_savings LOOP
      v_int := ROUND(r.balance * r.interest_rate / 100 / 12, 2);
      IF v_int > 0 THEN
        post_txn(r.account_no, 'INTEREST', v_int, 'C', NULL, NULL,
                 'Interest for ' || TO_CHAR(v_month, 'MON-YYYY'));
        v_count := v_count + 1;
        v_total := v_total + v_int;
      END IF;
    END LOOP;

    INSERT INTO interest_runs (run_month, accounts_paid, total_interest)
    VALUES (v_month, v_count, v_total);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Interest posted to ' || v_count || ' accounts, total = ' || v_total);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END calculate_interest;

  /* ================= customer support chat ================= */

  PROCEDURE raise_ticket (p_customer_id NUMBER, p_subject VARCHAR2, p_message VARCHAR2,
                          p_ticket_id OUT NUMBER) IS
    v_dummy NUMBER;
  BEGIN
    BEGIN
      SELECT 1 INTO v_dummy FROM customers WHERE customer_id = p_customer_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20009, 'Customer ' || p_customer_id || ' does not exist');
    END;
    IF p_subject IS NULL OR p_message IS NULL THEN
      RAISE_APPLICATION_ERROR(-20009, 'Subject and message are required');
    END IF;

    INSERT INTO support_tickets (ticket_id, customer_id, subject)
    VALUES (seq_ticket.NEXTVAL, p_customer_id, p_subject)
    RETURNING ticket_id INTO p_ticket_id;

    INSERT INTO support_messages (msg_id, ticket_id, sender_type, message)
    VALUES (seq_msg.NEXTVAL, p_ticket_id, 'CUSTOMER', p_message);

    INSERT INTO support_messages (msg_id, ticket_id, sender_type, message)
    VALUES (seq_msg.NEXTVAL, p_ticket_id, 'BOT', bot_reply(p_message));
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END raise_ticket;

  PROCEDURE reply_ticket (p_ticket_id NUMBER, p_sender_type VARCHAR2, p_message VARCHAR2) IS
    v_status support_tickets.status%TYPE;
    v_sender VARCHAR2(10) := UPPER(p_sender_type);
  BEGIN
    BEGIN
      SELECT status INTO v_status FROM support_tickets WHERE ticket_id = p_ticket_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20009, 'Ticket ' || p_ticket_id || ' not found');
    END;
    IF v_status = 'CLOSED' THEN
      RAISE_APPLICATION_ERROR(-20009, 'Ticket is closed');
    END IF;
    IF v_sender NOT IN ('CUSTOMER', 'AGENT') THEN
      RAISE_APPLICATION_ERROR(-20009, 'Sender must be CUSTOMER or AGENT');
    END IF;

    INSERT INTO support_messages (msg_id, ticket_id, sender_type, message)
    VALUES (seq_msg.NEXTVAL, p_ticket_id, v_sender, p_message);

    UPDATE support_tickets
       SET status = CASE WHEN v_sender = 'AGENT' THEN 'ANSWERED' ELSE 'OPEN' END
     WHERE ticket_id = p_ticket_id;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END reply_ticket;

  PROCEDURE close_ticket (p_ticket_id NUMBER) IS
  BEGIN
    UPDATE support_tickets
       SET status = 'CLOSED', closed_at = SYSTIMESTAMP
     WHERE ticket_id = p_ticket_id AND status <> 'CLOSED';
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20009, 'Ticket not found or already closed');
    END IF;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END close_ticket;

END bank_pkg;
/

SHOW ERRORS

/* ---------------------------------------------------------------------
   7. SEED DATA
   --------------------------------------------------------------------- */
INSERT INTO banks VALUES (1, 'First National Bank (Home)', 'FNBK', 'Y');
INSERT INTO banks VALUES (2, 'Metro Bank',                 'METR', 'N');
INSERT INTO banks VALUES (3, 'Union Trust Bank',           'UNTR', 'N');
COMMIT;

/* ---------------------------------------------------------------------
   8. DEMO / TEST SCRIPT
   --------------------------------------------------------------------- */
DECLARE
  v_c1 NUMBER; v_c2 NUMBER; v_c3 NUMBER;
  v_a1 NUMBER; v_a2 NUMBER; v_a3 NUMBER;     -- a3 lives in another bank
  v_ref VARCHAR2(40);
  v_loan NUMBER;
  v_tkt  NUMBER;

  PROCEDURE say (p VARCHAR2) IS BEGIN DBMS_OUTPUT.PUT_LINE(p); END;

  PROCEDURE show_statement (p_acc NUMBER) IS
    v_rc   SYS_REFCURSOR;
    v_id   transactions.txn_id%TYPE;
    v_time VARCHAR2(30);
    v_type VARCHAR2(20);
    v_dc   CHAR(1);
    v_amt  NUMBER;
    v_bal  NUMBER;
    v_desc VARCHAR2(200);
  BEGIN
    say('--- Mini statement for ' || p_acc || ' ---');
    bank_pkg.mini_statement(p_acc, 6, v_rc);
    LOOP
      FETCH v_rc INTO v_id, v_time, v_type, v_dc, v_amt, v_bal, v_desc;
      EXIT WHEN v_rc%NOTFOUND;
      say(RPAD(v_time, 18) || RPAD(v_type, 16) || v_dc || ' ' ||
          LPAD(TO_CHAR(v_amt, 'FM999,999,990.00'), 14) ||
          LPAD(TO_CHAR(v_bal, 'FM999,999,990.00'), 16) || '  ' || v_desc);
    END LOOP;
    CLOSE v_rc;
  END show_statement;
BEGIN
  say('=== 1. Onboarding ===');
  bank_pkg.create_customer('Arjun Sen',   DATE '1990-04-12', 'arjun@example.com', '9830011111', 'KYC-A-1001', 'Kolkata', v_c1);
  bank_pkg.create_customer('Meera Das',   DATE '1994-09-30', 'meera@example.com', '9830022222', 'KYC-A-1002', 'Howrah',  v_c2);
  bank_pkg.create_customer('Rohan Gupta', DATE '1988-01-05', 'rohan@example.com', '9830033333', 'KYC-A-1003', 'Delhi',   v_c3);
  bank_pkg.open_account(v_c1, 'SAVINGS', 50000, v_a1);
  bank_pkg.open_account(v_c2, 'SAVINGS', 10000, v_a2);
  bank_pkg.open_account(v_c3, 'CURRENT',  5000, v_a3, 2);   -- account at Metro Bank
  say('Accounts: ' || v_a1 || ', ' || v_a2 || ', ' || v_a3);

  say('=== 2. Deposit / withdraw ===');
  bank_pkg.deposit(v_a1, 2500);
  bank_pkg.withdraw(v_a1, 1000);
  say('Balance a1 = ' || bank_pkg.get_balance(v_a1));

  say('=== 3. Same-bank transfer (no fee) ===');
  bank_pkg.transfer(v_a1, v_a2, 5000, 'Rent', v_ref);
  say('Ref ' || v_ref);

  say('=== 4. Inter-bank transfer (fee applies) ===');
  bank_pkg.transfer(v_a1, v_a3, 20000, 'Supplier payment', v_ref);
  say('Ref ' || v_ref);

  say('=== 5. Exception handling tests ===');
  BEGIN
    bank_pkg.withdraw(v_a2, 999999);
  EXCEPTION WHEN bank_pkg.e_insufficient_funds THEN say('OK overdraft blocked: ' || SQLERRM);
  END;
  BEGIN
    bank_pkg.deposit(v_a2, -50);
  EXCEPTION WHEN bank_pkg.e_invalid_amount THEN say('OK invalid amount: ' || SQLERRM);
  END;
  BEGIN
    bank_pkg.transfer(v_a2, v_a2, 100, NULL, v_ref);
  EXCEPTION WHEN bank_pkg.e_same_account THEN say('OK same account: ' || SQLERRM);
  END;
  BEGIN
    bank_pkg.withdraw(999, 100);
  EXCEPTION WHEN bank_pkg.e_account_not_found THEN say('OK unknown account: ' || SQLERRM);
  END;
  BEGIN
    bank_pkg.create_customer('Minor Kid', SYSDATE - 365*10, 'kid@example.com', '9830044444', 'KYC-X', NULL, v_c3);
  EXCEPTION WHEN bank_pkg.e_customer_error THEN say('OK age rule: ' || SQLERRM);
  END;
  BEGIN
    UPDATE transactions SET amount = 1 WHERE ROWNUM = 1;
  EXCEPTION WHEN OTHERS THEN say('OK ledger immutable: ' || SQLERRM);
  END;

  say('=== 6. Loan workflow ===');
  bank_pkg.apply_loan(v_c2, v_a2, 'PERSONAL', 100000, 11.5, 12, v_loan);
  say('Loan ' || v_loan || ' EMI = ' || bank_pkg.calc_emi(100000, 11.5, 12));
  bank_pkg.approve_loan(v_loan, 'OFFICER01', 'Good credit history');
  bank_pkg.repay_emi(v_loan);
  bank_pkg.repay_emi(v_loan);

  say('=== 7. Monthly interest batch ===');
  bank_pkg.calculate_interest;
  BEGIN
    bank_pkg.calculate_interest;
  EXCEPTION WHEN bank_pkg.e_interest_done THEN say('OK duplicate run blocked: ' || SQLERRM);
  END;

  say('=== 8. Support chat ===');
  bank_pkg.raise_ticket(v_c2, 'Loan query', 'When will my loan EMI be debited?', v_tkt);
  bank_pkg.reply_ticket(v_tkt, 'AGENT', 'EMI is auto-debited on the 5th of every month.');
  bank_pkg.close_ticket(v_tkt);

  show_statement(v_a1);
  show_statement(v_a2);
END;
/

-- Inspect results
SELECT * FROM v_account_summary ORDER BY account_no;
SELECT * FROM v_loan_status;
SELECT loan_id, status, changed_by, TO_CHAR(changed_on,'HH24:MI:SS') changed_on, remarks
  FROM loan_tracking ORDER BY track_id;
SELECT ticket_id, sender_type, message FROM support_messages ORDER BY msg_id;
SELECT table_name, action, key_value, new_value FROM audit_log WHERE ROWNUM <= 10 ORDER BY audit_id;

/* ---------------------------------------------------------------------
   9. ROLE-BASED ACCESS  (run as DBA / user with CREATE ROLE, then
      uncomment). Customers never touch tables directly - only package.
   ---------------------------------------------------------------------
-- CREATE ROLE bank_customer;
-- CREATE ROLE bank_teller;
-- CREATE ROLE bank_loan_officer;
-- CREATE ROLE bank_admin;
--
-- GRANT EXECUTE ON bank_pkg TO bank_customer, bank_teller, bank_loan_officer, bank_admin;
-- GRANT SELECT  ON v_account_summary TO bank_teller, bank_admin;
-- GRANT SELECT  ON v_loan_status     TO bank_loan_officer, bank_admin;
-- GRANT SELECT  ON audit_log         TO bank_admin;
-- GRANT SELECT  ON transactions      TO bank_admin;
--
-- Typical usage rules to enforce in the application layer:
--   customer     : get_balance, mini_statement, transfer (own accounts), apply_loan, raise_ticket
--   teller       : deposit, withdraw, open_account, create_customer
--   loan officer : approve_loan, reject_loan
--   admin        : calculate_interest, audit review
   --------------------------------------------------------------------- */
