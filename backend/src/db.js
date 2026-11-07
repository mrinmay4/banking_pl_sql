import oracledb from 'oracledb';

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

export const outNum = { dir: oracledb.BIND_OUT, type: oracledb.NUMBER };
export const outStr = { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 100 };

let pool;
export async function initPool() {
  pool = await oracledb.createPool({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectString: process.env.DB_CONNECT,
    poolMin: 1,
    poolMax: 10,
  });
}

const lc = (row) => Object.fromEntries(Object.entries(row).map(([k, v]) => [k.toLowerCase(), v]));

// Run any statement. BANK_PKG procedures commit internally.
export async function run(sql, binds = {}) {
  const conn = await pool.getConnection();
  try {
    return await conn.execute(sql, binds, { autoCommit: true });
  } finally {
    await conn.close();
  }
}

export async function query(sql, binds = {}) {
  const r = await run(sql, binds);
  return (r.rows || []).map(lc);
}

// BANK_PKG.MINI_STATEMENT returns a REF CURSOR; read it on the same connection
export async function miniStatement(accountNo, count) {
  const conn = await pool.getConnection();
  try {
    const r = await conn.execute(
      'BEGIN bank_pkg.mini_statement(:acc, :cnt, :rc); END;',
      { acc: accountNo, cnt: count, rc: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR } }
    );
    const rs = r.outBinds.rc;
    const rows = await rs.getRows(100);
    await rs.close();
    return rows.map(lc);
  } finally {
    await conn.close();
  }
}
