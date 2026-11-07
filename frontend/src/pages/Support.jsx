import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useAuth } from '../auth.jsx';
import { dt, Msg, ok, bad, Badge } from '../ui.jsx';

export default function Support() {
  const { user } = useAuth();
  const isCust = user.role === 'CUSTOMER';
  const [tickets, setTickets] = useState([]);
  const [sel, setSel] = useState(null);
  const [msgs, setMsgs] = useState([]);
  const [text, setText] = useState('');
  const [nt, setNt] = useState({ subject: '', message: '' });
  const [m, setM] = useState(null);

  const loadTickets = () => api('/tickets').then(setTickets).catch((e) => setM(bad(e)));
  const open = (t) => { setSel(t); api(`/tickets/${t.ticket_id}/messages`).then(setMsgs).catch((e) => setM(bad(e))); };
  useEffect(() => { loadTickets(); }, []);

  const post = async (path, body, after) => {
    try { await api(path, { method: 'POST', body }); after?.(); } catch (e) { setM(bad(e)); }
  };

  return (
    <>
      <h1>Customer support</h1>
      <Msg m={m} />
      <div className="split">
        <div>
          {isCust && (
            <form className="card" onSubmit={(e) => {
              e.preventDefault();
              post('/tickets', nt, () => { setNt({ subject: '', message: '' }); setM(ok('Ticket created')); loadTickets(); });
            }}>
              <h3>New ticket</h3>
              <input placeholder="Subject" value={nt.subject} onChange={(e) => setNt({ ...nt, subject: e.target.value })} required />
              <textarea placeholder="How can we help?" value={nt.message} onChange={(e) => setNt({ ...nt, message: e.target.value })} required />
              <button>Send</button>
            </form>
          )}
          <div className="card list">
            {tickets.map((t) => (
              <div key={t.ticket_id} className={`item ${sel?.ticket_id === t.ticket_id ? 'active' : ''}`} onClick={() => open(t)}>
                <b>#{t.ticket_id} {t.subject}</b>
                <div className="muted small">{t.full_name} · <Badge>{t.status}</Badge></div>
              </div>
            ))}
            {!tickets.length && <p className="muted">No tickets</p>}
          </div>
        </div>

        <div className="card chat">
          {!sel ? <p className="muted">Select a ticket to view the conversation</p> : (<>
            <div className="row between"><h3>#{sel.ticket_id} {sel.subject}</h3>
              {sel.status !== 'CLOSED' && <button className="ghost" onClick={() => post(`/tickets/${sel.ticket_id}/close`, null, () => { setSel({ ...sel, status: 'CLOSED' }); loadTickets(); })}>Close ticket</button>}
            </div>
            <div className="bubbles">
              {msgs.map((x) => (
                <div key={x.msg_id} className={`bubble ${x.sender_type.toLowerCase()}`}>
                  <small>{x.sender_type} · {dt(x.sent_at)}</small>
                  <div>{x.message}</div>
                </div>
              ))}
            </div>
            {sel.status !== 'CLOSED' && (
              <form className="row" onSubmit={(e) => {
                e.preventDefault();
                post(`/tickets/${sel.ticket_id}/reply`, { message: text }, () => { setText(''); open(sel); loadTickets(); });
              }}>
                <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a reply…" required />
                <button>Send</button>
              </form>
            )}
          </>)}
        </div>
      </div>
    </>
  );
}
