import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { Msg, ok, bad } from '../ui.jsx';

export default function Desk() {
  const [customers, setCustomers] = useState([]);
  const [m, setM] = useState(null);
  const [c, setC] = useState({ name: '', dob: '', email: '', phone: '', kycId: '', address: '' });
  const [a, setA] = useState({ customerId: '', type: 'SAVINGS', initialDeposit: 1000, bankId: 1 });
  const [t, setT] = useState({ accountNo: '', amount: '' });

  const load = () => api('/customers').then((r) => {
    setCustomers(r);
    setA((x) => ({ ...x, customerId: x.customerId || r[0]?.customer_id || '' }));
  }).catch((e) => setM(bad(e)));
  useEffect(() => { load(); }, []);

  const go = async (fn, text, after) => {
    try { const r = await fn(); setM(ok(typeof text === 'function' ? text(r) : text)); after?.(); }
    catch (e) { setM(bad(e)); }
  };
  const post = (p, body) => api(p, { method: 'POST', body });

  return (
    <>
      <h1>Teller desk</h1>
      <Msg m={m} />
      <div className="grid3">
        <form className="card" onSubmit={(e) => { e.preventDefault(); go(() => post('/customers', c), (r) => `Customer created (ID ${r.customerId})`, load); }}>
          <h3>1. New customer</h3>
          <input placeholder="Full name" value={c.name} onChange={(e) => setC({ ...c, name: e.target.value })} required />
          <input type="date" value={c.dob} onChange={(e) => setC({ ...c, dob: e.target.value })} required />
          <input type="email" placeholder="Email" value={c.email} onChange={(e) => setC({ ...c, email: e.target.value })} required />
          <input placeholder="Phone" value={c.phone} onChange={(e) => setC({ ...c, phone: e.target.value })} required />
          <input placeholder="KYC ID" value={c.kycId} onChange={(e) => setC({ ...c, kycId: e.target.value })} required />
          <input placeholder="Address" value={c.address} onChange={(e) => setC({ ...c, address: e.target.value })} />
          <button>Create customer</button>
        </form>

        <form className="card" onSubmit={(e) => { e.preventDefault(); go(() => post('/accounts', a), (r) => `Account opened: ${r.accountNo}`); }}>
          <h3>2. Open account</h3>
          <select value={a.customerId} onChange={(e) => setA({ ...a, customerId: e.target.value })}>
            {customers.map((x) => <option key={x.customer_id} value={x.customer_id}>{x.customer_id} · {x.full_name}</option>)}
          </select>
          <select value={a.type} onChange={(e) => setA({ ...a, type: e.target.value })}>
            <option>SAVINGS</option><option>CURRENT</option>
          </select>
          <input type="number" placeholder="Initial deposit" value={a.initialDeposit} onChange={(e) => setA({ ...a, initialDeposit: e.target.value })} />
          <select value={a.bankId} onChange={(e) => setA({ ...a, bankId: e.target.value })}>
            <option value="1">First National Bank (home)</option><option value="2">Metro Bank</option><option value="3">Union Trust Bank</option>
          </select>
          <button>Open account</button>
        </form>

        <form className="card" onSubmit={(e) => e.preventDefault()}>
          <h3>3. Cash counter</h3>
          <input placeholder="Account number" value={t.accountNo} onChange={(e) => setT({ ...t, accountNo: e.target.value })} required />
          <input type="number" min="0.01" step="0.01" placeholder="Amount" value={t.amount} onChange={(e) => setT({ ...t, amount: e.target.value })} required />
          <div className="row">
            <button type="button" onClick={() => go(() => post(`/accounts/${t.accountNo}/deposit`, { amount: t.amount }), 'Deposit successful')}>Deposit</button>
            <button type="button" className="danger" onClick={() => go(() => post(`/accounts/${t.accountNo}/withdraw`, { amount: t.amount }), 'Withdrawal successful')}>Withdraw</button>
          </div>
        </form>
      </div>
    </>
  );
}
