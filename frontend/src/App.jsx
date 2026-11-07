import { BrowserRouter, Routes, Route, Navigate, NavLink } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth.jsx';
import Login from './pages/Login.jsx';
import Accounts from './pages/Accounts.jsx';
import Statement from './pages/Statement.jsx';
import Transfer from './pages/Transfer.jsx';
import Loans from './pages/Loans.jsx';
import Support from './pages/Support.jsx';
import Desk from './pages/Desk.jsx';
import Admin from './pages/Admin.jsx';

const ALL = ['CUSTOMER', 'TELLER', 'LOAN_OFFICER', 'ADMIN'];
const PAGES = [
  { path: '/accounts', label: 'Accounts',    el: <Accounts />, roles: ['CUSTOMER', 'TELLER', 'ADMIN'] },
  { path: '/transfer', label: 'Transfer',    el: <Transfer />, roles: ['CUSTOMER'] },
  { path: '/loans',    label: 'Loans',       el: <Loans />,    roles: ['CUSTOMER', 'LOAN_OFFICER', 'ADMIN'] },
  { path: '/support',  label: 'Support',     el: <Support />,  roles: ALL },
  { path: '/desk',     label: 'Teller Desk', el: <Desk />,     roles: ['TELLER', 'ADMIN'] },
  { path: '/admin',    label: 'Admin',       el: <Admin />,    roles: ['ADMIN'] },
];

function Shell() {
  const { user, logout } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  const pages = PAGES.filter((p) => p.roles.includes(user.role));

  return (
    <div className="app">
      <header>
        <div className="brand">🏦 First National Bank</div>
        <nav>
          {pages.map((p) => <NavLink key={p.path} to={p.path}>{p.label}</NavLink>)}
        </nav>
        <div className="who">
          <span>{user.fullName} <small>({user.role.replace('_', ' ')})</small></span>
          <button className="ghost" onClick={logout}>Log out</button>
        </div>
      </header>
      <main>
        <Routes>
          {pages.map((p) => <Route key={p.path} path={p.path} element={p.el} />)}
          <Route path="/statement/:no" element={<Statement />} />
          <Route path="*" element={<Navigate to={pages[0].path} replace />} />
        </Routes>
      </main>
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/*" element={<Shell />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
