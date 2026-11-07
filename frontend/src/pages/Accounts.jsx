import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api.js';
import { money, Msg, bad, Badge } from '../ui.jsx';

export default function Accounts() {
  const [rows, setRows] = useState([]);
  const [m, setM] = useState(null);

  useEffect(() => { api('/accounts').then(setRows).catch((e) => setM(bad(e))); }, []);

  return (
    <>
      <h1>Accounts</h1>
      <Msg m={m} />
      <div className="card">
        <table>
          <thead><tr><th>Account no.</th><th>Holder</th><th>Bank</th><th>Type</th><th className="r">Balance</th><th>Status</th><th></th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.account_no}>
                <td>{r.account_no}</td><td>{r.full_name}</td><td>{r.bank_name}</td><td>{r.account_type}</td>
                <td className="r"><b>{money(r.balance)}</b></td>
                <td><Badge>{r.status}</Badge></td>
                <td><Link to={`/statement/${r.account_no}`}>Statement</Link></td>
              </tr>
            ))}
            {!rows.length && <tr><td colSpan="7" className="muted">No accounts found</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
