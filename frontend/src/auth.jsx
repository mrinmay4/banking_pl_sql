import { createContext, useContext, useState } from 'react';
import { api } from './api.js';

const Ctx = createContext(null);
export const useAuth = () => useContext(Ctx);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => {
    try { return JSON.parse(localStorage.getItem('user')); } catch { return null; }
  });

  const login = async (username, password) => {
    const d = await api('/auth/login', { method: 'POST', body: { username, password } });
    localStorage.setItem('token', d.token);
    localStorage.setItem('user', JSON.stringify(d.user));
    setUser(d.user);
  };
  const logout = () => { localStorage.clear(); setUser(null); };

  return <Ctx.Provider value={{ user, login, logout }}>{children}</Ctx.Provider>;
}
