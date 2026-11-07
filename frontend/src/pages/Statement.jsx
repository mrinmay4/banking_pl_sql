import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../api.js';
import { money, Msg, bad } from '../ui.jsx';

export default function Statement() {
  const { no } = useParams();
  const [count, setCount] = useState(10);
  const [rows, setRows] = useState([]);
  const [bal, setBal] = useState(null);
  const [m, setM] = useState(null);

  useEffect(() => {
    Promise.all([api(`/accounts/${no}/balance`), api(`/accounts/${no}/statement?count=${count}`)])
      .then(([b, s]) => { setBal(b.balance); setRows(s); setM(null); })
      .catch((e) => setM(bad(e)));
  }, [no, count]);

  return (
    <>
      <p><Link to="/accounts">← Accounts</Link></p>
      <h1>Mini statement · {no}</h1>
      <Msg m={m} />
      <div className="card">
        <div className="row between">
          <div>Available balance <h2>{money(bal)}</h2></div>
          <label>Show last
            <select value={count} onChange={(e) => setCount(Number(e.target.value))}>
              {[5, 10, 20, 50].map((n) => <option key={n}>{n}</option>)}
            </select>
          </label>
        </div>
        <table>
          <thead><tr><th>Date</th><th>Type</th><th>Description</th><th className="r">Amount</th><th className="r">Balance</th></tr></thead>
          <tbody>
            {rows.map((t) => (
              <tr key={t.txn_id}>
                <td>{t.txn_time}</td><td>{t.txn_type}</td><td>{t.description}</td>
                <td className={`r ${t.dr_cr === 'D' ? 'neg' : 'pos'}`}>{t.dr_cr === 'D' ? '−' : '+'}{money(t.amount)}</td>
                <td className="r">{money(t.balance_after)}</td>
              </tr>
            ))}
            {!rows.length && <tr><td colSpan="5" className="muted">No transactions yet</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
