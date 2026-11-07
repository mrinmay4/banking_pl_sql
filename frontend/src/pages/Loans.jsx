import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useAuth } from '../auth.jsx';
import { money, dt, Msg, ok, bad, Badge } from '../ui.jsx';

export default function Loans() {
  const { user } = useAuth();
  const isCust = user.role === 'CUSTOMER';
  const isOfficer = ['LOAN_OFFICER', 'ADMIN'].includes(user.role);

  const [loans, setLoans] = useState([]);
  const [accs, setAccs] = useState([]);
  const [m, setM] = useState(null);
  const [track, setTrack] = useState(null);
  const [quote, setQuote] = useState(null);
  const [f, setF] = useState({ accountNo: '', loanType: 'PERSONAL', principal: 100000, months: 12 });

  const load = () => api('/loans').then(setLoans).catch((e) => setM(bad(e)));

  useEffect(() => {
    load();
    if (isCust) api('/accounts').then((a) => { setAccs(a); if (a[0]) setF((x) => ({ ...x, accountNo: a[0].account_no })); });
  }, []);

  useEffect(() => {
    if (!isCust) return;
    const t = setTimeout(() => {
      api(`/loans/quote?type=${f.loanType}&principal=${f.principal}&months=${f.months}`)
        .then(setQuote).catch(() => setQuote(null));
    }, 300);
    return () => clearTimeout(t);
  }, [f.loanType, f.principal, f.months]);

  const act = async (fn, text) => {
    try { await fn(); setM(ok(text)); load(); } catch (e) { setM(bad(e)); }
  };
  const post = (path, body) => api(path, { method: 'POST', body });

  return (
    <>
      <h1>{isCust ? 'My loans' : 'Loan applications'}</h1>
      <Msg m={m} />

      {isCust && (
        <form className="card narrow" onSubmit={(e) => { e.preventDefault(); act(() => post('/loans', f), 'Application submitted'); }}>
          <h3>Apply for a loan</h3>
          <label>Credit to account
            <select value={f.accountNo} onChange={(e) => setF({ ...f, accountNo: e.target.value })}>
              {accs.map((a) => <option key={a.account_no} value={a.account_no}>{a.account_no}</option>)}
            </select>
          </label>
          <label>Loan type
            <select value={f.loanType} onChange={(e) => setF({ ...f, loanType: e.target.value })}>
              {['PERSONAL', 'HOME', 'CAR', 'EDUCATION'].map((t) => <option key={t}>{t}</option>)}
            </select>
          </label>
          <label>Amount (₹10,000 – ₹50,00,000)
            <input type="number" value={f.principal} onChange={(e) => setF({ ...f, principal: e.target.value })} />
          </label>
          <label>Tenure (months, 6 – 360)
            <input type="number" value={f.months} onChange={(e) => setF({ ...f, months: e.target.value })} />
          </label>
          {quote && <p className="quote">Rate {quote.rate}% p.a. · EMI <b>{money(quote.emi)}</b> · Total payable {money(quote.total)}</p>}
          <button>Submit application</button>
        </form>
      )}

      <div className="card">
        <table>
          <thead><tr><th>ID</th><th>Customer</th><th>Type</th><th className="r">Amount</th><th className="r">EMI</th><th>Paid</th><th className="r">Outstanding</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>
            {loans.map((l) => (
              <tr key={l.loan_id}>
                <td>{l.loan_id}</td><td>{l.full_name}</td><td>{l.loan_type}</td>
                <td className="r">{money(l.principal)}</td><td className="r">{money(l.emi)}</td>
                <td>{l.emis_paid}/{l.tenure_months}</td><td className="r">{money(l.outstanding)}</td>
                <td><Badge>{l.status}</Badge></td>
                <td className="actions">
                  <button className="ghost" onClick={() => api(`/loans/${l.loan_id}/tracking`).then((rows) => setTrack({ id: l.loan_id, rows })).catch((e) => setM(bad(e)))}>Track</button>
                  {isCust && l.status === 'DISBURSED' && (
                    <button onClick={() => act(() => post(`/loans/${l.loan_id}/repay`), 'EMI paid')}>Pay EMI</button>
                  )}
                  {isOfficer && l.status === 'APPLIED' && (<>
                    <button onClick={() => act(() => post(`/loans/${l.loan_id}/approve`, { remarks: 'Approved' }), 'Loan approved and disbursed')}>Approve</button>
                    <button className="danger" onClick={() => {
                      const reason = prompt('Reason for rejection?');
                      if (reason) act(() => post(`/loans/${l.loan_id}/reject`, { remarks: reason }), 'Loan rejected');
                    }}>Reject</button>
                  </>)}
                </td>
              </tr>
            ))}
            {!loans.length && <tr><td colSpan="9" className="muted">No loans</td></tr>}
          </tbody>
        </table>
      </div>

      {track && (
        <div className="card">
          <div className="row between"><h3>Loan #{track.id} timeline</h3><button className="ghost" onClick={() => setTrack(null)}>Close</button></div>
          <ul className="timeline">
            {track.rows.map((t, i) => (
              <li key={i}><Badge>{t.status}</Badge> {dt(t.changed_on)} · {t.changed_by} {t.remarks && <span className="muted">— {t.remarks}</span>}</li>
            ))}
          </ul>
        </div>
      )}
    </>
  );
}
