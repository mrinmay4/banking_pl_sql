export const money = (n) =>
  new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR' }).format(n ?? 0);
export const dt = (s) => (s ? new Date(s).toLocaleString('en-IN') : '');

export function Msg({ m }) {
  return m ? <div className={`msg ${m.type}`}>{m.text}</div> : null;
}
export const ok = (text) => ({ type: 'ok', text });
export const bad = (e) => ({ type: 'err', text: e.message || String(e) });

export function Badge({ children }) {
  return <span className={`badge ${String(children).toLowerCase()}`}>{children}</span>;
}
