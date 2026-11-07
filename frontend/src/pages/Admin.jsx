import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { money, dt, Msg, ok, bad } from '../ui.jsx';

export default function Admin() {
  const [runs, setRuns] = useState([]);
  const [audit, setAudit] = useState([]);
  const [month, setMonth] = useState('');
  const [m, setM] = useState(null);

  const load = () => {
    api('/admin/interest-runs').then(setRuns).catch((e) => setM(bad(e)));
    api('/admin/audit').then(setAudit).catch((e) => setM(bad(e)));
  };
  useEffect(load, []);

  const run = async () => {
    try { await api('/admin/interest', { method: 'POST', body: { month: month || null } }); setM(ok('Interest posted to all active savings accounts')); load(); }
    catch (e) { setM(bad(e)); }
  };

  return (
    <>
      <h1>Admin</h1>
      <Msg m={m} />
      <div className="card">
        <h3>Monthly interest batch</h3>
        <div className="row">
          <input type="month" value={month} onChange={(e) => setMonth(e.target.value)} />
          <button onClick={run}>Run interest calculation</button>
        </div>
        <p className="muted small">Leave month empty for the current month. Each month can only be posted once.</p>
        <table>
          <thead><tr><th>Month</th><th>Accounts paid</th><th className="r">Total interest</th><th>Run at</th></tr></thead>
          <tbody>
            {runs.map((r, i) => (
              <tr key={i}><td>{new Date(r.run_month).toLocaleDateString('en-IN', { month: 'long', year: 'numeric' })}</td>
                <td>{r.accounts_paid}</td><td className="r">{money(r.total_interest)}</td><td>{dt(r.run_on)}</td></tr>
            ))}
            {!runs.length && <tr><td colSpan="4" className="muted">No runs yet</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Audit log (latest 100)</h3>
        <table>
          <thead><tr><th>#</th><th>Table</th><th>Action</th><th>Key</th><th>Detail</th><th>By</th><th>When</th></tr></thead>
          <tbody>
            {audit.map((a) => (
              <tr key={a.audit_id}><td>{a.audit_id}</td><td>{a.table_name}</td><td>{a.action}</td><td>{a.key_value}</td>
                <td className="small">{a.new_value}</td><td>{a.changed_by}</td><td>{dt(a.changed_at)}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
