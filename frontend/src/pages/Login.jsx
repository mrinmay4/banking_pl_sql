import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth.jsx';
import { Msg, bad } from '../ui.jsx';

export default function Login() {
  const { user, login } = useAuth();
  const nav = useNavigate();
  const [f, setF] = useState({ username: '', password: '' });
  const [m, setM] = useState(null);
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to="/" replace />;

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    try { await login(f.username, f.password); nav('/'); }
    catch (err) { setM(bad(err)); }
    finally { setBusy(false); }
  };

  return (
    <div className="login">
      <form className="card" onSubmit={submit}>
        <h2>🏦 First National Bank</h2>
        <p className="muted">Sign in to continue</p>
        <Msg m={m} />
        <label>Username
          <input value={f.username} onChange={(e) => setF({ ...f, username: e.target.value })} autoFocus />
        </label>
        <label>Password
          <input type="password" value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} />
        </label>
        <button disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        <p className="muted small">Demo: arjun / meera / rohan (customers), teller, officer, admin — Password@123</p>
      </form>
    </div>
  );
}
