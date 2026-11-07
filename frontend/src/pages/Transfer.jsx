import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { money, Msg, ok, bad } from '../ui.jsx';

export default function Transfer() {
  const [accs, setAccs] = useState([]);
  const [f, setF] = useState({ from: '', to: '', amount: '', remarks: '' });
  const [m, setM] = useState(null);

  const load = () => api('/accounts').then((a) => {
    setAccs(a);
    setF((x) => ({ ...x, from: x.from || a[0]?.account_no || '' }));
  }).catch((e) => setM(bad(e)));
  useEffect(() => { load(); }, []);

  const submit = async (e) => {
    e.preventDefault();
    try {
      const r = await api('/transfers', { method: 'POST', body: { ...f } });
      setM(ok(`Transfer successful. Reference: ${r.ref}`));
      setF((x) => ({ ...x, to: '', amount: '', remarks: '' }));
      load();
    } catch (err) { setM(bad(err)); }
  };

  return (
    <>
      <h1>Transfer funds</h1>
      <Msg m={m} />
      <form className="card narrow" onSubmit={submit}>
        <label>From account
          <select value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })}>
            {accs.map((a) => <option key={a.account_no} value={a.account_no}>{a.account_no} · {money(a.balance)}</option>)}
          </select>
        </label>
        <label>To account number
          <input value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} placeholder="e.g. 1000100002" required />
        </label>
        <label>Amount (₹)
          <input type="number" min="0.01" step="0.01" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} required />
        </label>
        <label>Remarks (optional)
          <input value={f.remarks} onChange={(e) => setF({ ...f, remarks: e.target.value })} />
        </label>
        <p className="muted small">Same-bank transfers are free. Transfers to another bank carry a fee of ₹2.50 – ₹15 depending on the amount.</p>
        <button>Send money</button>
      </form>
    </>
  );
}
