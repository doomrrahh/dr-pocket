// Dr. Pocket — local diabetes monitor. Zero deps.
// Providers: carelink (Medtronic) and demo. Data is stored locally in data/db.json.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const ENV = path.join(ROOT, '.env');
for (const l of (fs.existsSync(ENV) ? fs.readFileSync(ENV, 'utf8') : '').split(/\r?\n/)) {
  const m = l.match(/^\s*(\w+)\s*=\s*(.*?)\s*$/); if (m && !(m[1] in process.env)) process.env[m[1]] = m[2];
}
const cfg = {
  provider: (process.env.PROVIDER || 'demo').toLowerCase(),
  port: +process.env.PORT || 1337,
  low: +process.env.LOW || 70, high: +process.env.HIGH || 180,
  cl: { token: process.env.CARELINK_TOKEN || '', patient: process.env.CARELINK_PATIENT || '', country: (process.env.CARELINK_COUNTRY || 'us').toLowerCase() },
};
const setEnv = (k, v) => {
  const lines = (fs.existsSync(ENV) ? fs.readFileSync(ENV, 'utf8') : '').split(/\r?\n/);
  const i = lines.findIndex(l => l.startsWith(k + '='));
  if (i >= 0) lines[i] = `${k}=${v}`; else lines.push(`${k}=${v}`);
  fs.writeFileSync(ENV, lines.filter((l, n) => l || n < lines.length - 1).join('\n'));
  process.env[k] = v;
};

const DB = path.join(ROOT, 'data', 'db.json');
fs.mkdirSync(path.dirname(DB), { recursive: true });
const db = fs.existsSync(DB) ? JSON.parse(fs.readFileSync(DB, 'utf8')) : { entries: [], treatments: [] };
db.treatments ||= []; db.entries ||= [];
const save = () => fs.writeFileSync(DB, JSON.stringify(db));
let lastSync = null, lastError = null, device = {};

const addEntries = rows => {
  const have = new Set(db.entries.map(e => e.date));
  let n = 0;
  for (const r of rows) {
    if (!r.sgv || have.has(r.date)) continue;
    have.add(r.date); n++;
    db.entries.push({ _id: 'e' + r.date, type: 'sgv', sgv: r.sgv, date: r.date, dateString: new Date(r.date).toISOString(), direction: r.direction || 'Flat', device: r.device || cfg.provider });
  }
  if (n) { db.entries.sort((a, b) => b.date - a.date); save(); }
  return n;
};

/* ---------------- CareLink (Medtronic) ----------------
   Auth follows the CareLink Connect Android app: a normal Auth0 login (the captcha is
   solved once, by a human, in a real browser) returns an authorization code, which we
   trade for an access + refresh token pair. From then on we refresh silently — no captcha.
   Flow cribbed from github.com/ondrej1024/carelink-python-client.                      */
const CL_TREND = { NONE: 'Flat', UP: 'SingleUp', UP_UP: 'DoubleUp', DOUBLE_UP: 'DoubleUp', UP_TRIPLE: 'DoubleUp',
  DOWN: 'SingleDown', DOWN_DOWN: 'DoubleDown', DOUBLE_DOWN: 'DoubleDown', DOWN_TRIPLE: 'DoubleDown' };
const DISCOVERY = 'https://clcloud.minimed.eu/connect/carepartner/v13/discover/android/3.6';
const UA = 'Dalvik/2.1.0 (Linux; U; Android 10; Nexus 5X Build/QQ3A.200805.001)';
const SSO = { US: 'https://carelink.minimed.com/configs/v1/carepartner_auth0_us_sso_config_v1.json',
  EU: 'https://carelink.minimed.eu/configs/v1/carepartner_auth0_eu_sso_config_v1.json' };
const TOKENS = path.join(ROOT, 'data', 'tokens.json');
const b64u = b => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
const jwt = t => { try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64').toString()); } catch { return {}; } };

let tok = fs.existsSync(TOKENS) ? JSON.parse(fs.readFileSync(TOKENS, 'utf8')) : null;
const saveTok = () => fs.writeFileSync(TOKENS, JSON.stringify(tok, null, 1));
let pkce = null, ssoCache = {}, conf = null;

const ssoConfig = async region => ssoCache[region] ||= await fetch(SSO[region] || SSO.US, { headers: { Accept: 'application/json' } }).then(r => r.json());
const tokenUrl = sso => `https://${sso.server.hostname}${sso.server.port === 443 ? '' : ':' + sso.server.port}${sso.server.prefix || ''}${sso.system_endpoints.token_endpoint_path}`;

async function clAuthorizeUrl(region = 'US') {
  const sso = await ssoConfig(region);
  const verifier = b64u(crypto.randomBytes(32));
  pkce = { verifier, region, state: b64u(crypto.randomBytes(8)) };
  const p = new URLSearchParams({ client_id: sso.client.client_id, response_type: 'code', scope: sso.client.scope,
    redirect_uri: sso.client.redirect_uri, audience: sso.client.audience, state: pkce.state,
    code_challenge: b64u(crypto.createHash('sha256').update(verifier).digest()), code_challenge_method: 'S256' });
  return `https://${sso.server.hostname}${sso.system_endpoints.authorization_endpoint_path}?${p}`;
}
async function clExchange(codeOrUrl) {
  if (!pkce) throw new Error('Start the sign-in from the dashboard first');
  let code = String(codeOrUrl).trim();
  if (code.includes('?') || code.includes('code=')) code = new URLSearchParams(code.split('?').pop()).get('code') || code;
  const sso = await ssoConfig(pkce.region);
  const body = new URLSearchParams({ grant_type: 'authorization_code', client_id: sso.client.client_id,
    code, redirect_uri: sso.client.redirect_uri, code_verifier: pkce.verifier });
  if (sso.client.client_secret) body.set('client_secret', sso.client.client_secret);
  const r = await fetch(tokenUrl(sso), { method: 'POST', body, headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': UA } });
  const t = await r.text();
  if (!r.ok) throw new Error(`Token exchange ${r.status}: ${(JSON.parse(t || '{}').error_description || t).slice(0, 140)}`);
  const d = JSON.parse(t);
  if (!d.refresh_token) throw new Error('No refresh token returned — the code may have been used already');
  tok = { ...d, region: pkce.region, client_id: sso.client.client_id };
  pkce = null; saveTok(); conf = null;
  return tok;
}
async function clRefresh() {
  const sso = await ssoConfig(tok.region);
  const body = new URLSearchParams({ grant_type: 'refresh_token', client_id: tok.client_id, refresh_token: tok.refresh_token });
  if (sso.client.client_secret) body.set('client_secret', sso.client.client_secret);
  const headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': UA };
  if (tok['mag-identifier']) headers['mag-identifier'] = tok['mag-identifier'];
  const r = await fetch(tokenUrl(sso), { method: 'POST', body, headers });
  if (!r.ok) { tok = null; fs.rmSync(TOKENS, { force: true }); throw new Error('Session expired — sign in to CareLink again'); }
  const d = await r.json();
  tok = { ...tok, ...d }; saveTok();
}
async function clConfig() {
  if (conf) return conf;
  const country = (jwt(tok.access_token).token_details?.country || cfg.cl.country || 'us').toUpperCase();
  const disc = await fetch(DISCOVERY, { headers: { Accept: 'application/json' } }).then(r => r.json());
  const region = disc.supportedCountries.map(c => c[country]?.region).find(Boolean);
  if (!region) throw new Error(`CareLink has no region for country ${country}`);
  conf = disc.CP.find(c => c.region === region);
  if (!conf) throw new Error(`No CareLink endpoints for region ${region}`);
  return conf;
}
async function clJson(url, opt = {}) {
  const headers = { Authorization: 'Bearer ' + tok.access_token, 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': UA };
  if (tok['mag-identifier']) headers['mag-identifier'] = tok['mag-identifier'];
  const r = await fetch(url, { ...opt, headers: { ...headers, ...opt.headers } });
  const t = await r.text();
  if (r.status === 401 || r.status === 403) { const e = new Error('unauthorized'); e.auth = 1; throw e; }
  if (!r.ok) throw new Error(`CareLink ${r.status}: ${t.replace(/\s+/g, ' ').slice(0, 140)}`);
  return t ? JSON.parse(t) : null;
}
async function carelink() {
  if (!tok) throw new Error('Not signed in to CareLink');
  const exp = jwt(tok.access_token).exp;
  if (!exp || exp * 1000 - Date.now() < 6e5) await clRefresh();
  try { return await clFetch(); }
  catch (e) { if (!e.auth) throw e; await clRefresh(); return clFetch(); }
}
async function clFetch() {
  const c = await clConfig();
  const me = await clJson(c.baseUrlCareLink + '/users/me');
  const carer = ['CARE_PARTNER', 'CARE_PARTNER_OUS'].includes(me.role);
  let patientId = cfg.cl.patient || null;
  if (carer && !patientId) {
    const links = await clJson(c.baseUrlCareLink + '/links/patients').catch(() => null);
    patientId = links?.[0]?.username;
  }
  const payload = carer ? { username: me.username, role: 'carepartner', patientId } : { username: me.username, role: 'patient' };
  const d = await clJson(c.baseUrlCumulus + '/display/message', { method: 'POST', body: JSON.stringify(payload) });
  const day = d.lastSGDateTime ? new Date(d.lastSGDateTime) : new Date();
  const at = s => {
    if (!s) return null;
    if (s.datetime) return Date.parse(s.datetime);
    if (s.timestamp) return Date.parse(s.timestamp);
    return null;
  };
  const rows = (d.sgs || []).filter(s => s.sg > 0).map(s => ({ sgv: s.sg, date: at(s), direction: CL_TREND[d.lastSGTrend] || 'Flat', device: 'carelink' })).filter(r => r.date);
  if (d.lastSG?.sg > 0 && at(d.lastSG)) rows.push({ sgv: d.lastSG.sg, date: at(d.lastSG), direction: CL_TREND[d.lastSGTrend] || 'Flat', device: 'carelink' });
  device = { pumpBattery: d.medicalDeviceBatteryLevelPercent ?? d.pumpBatteryLevelPercent, reservoir: d.reservoirRemainingUnits,
    activeInsulin: d.activeInsulin?.amount, sensorHours: d.sensorDurationHours, lastAlarm: d.lastAlarm?.messageId, updated: +day };
  return rows;
}

/* ---------------- Demo ---------------- */
function demo() {
  const now = Date.now(), last = db.entries[0]?.date || now - 24 * 36e5;
  const rows = []; let v = db.entries[0]?.sgv || 120;
  for (let t = last + 3e5; t <= now; t += 3e5) {
    const h = new Date(t).getHours();
    v += Math.sin(t / 27e5) * 4 + (h > 7 && h < 9 ? 5 : 0) + (Math.random() - 0.5) * 7 + (125 - v) * 0.04;
    v = Math.max(55, Math.min(270, v));
    rows.push({ sgv: Math.round(v), date: t, direction: 'Flat', device: 'demo' });
  }
  for (let i = 1; i < rows.length; i++) {
    const d = rows[i].sgv - rows[i - 1].sgv;
    rows[i].direction = d > 8 ? 'DoubleUp' : d > 3 ? 'SingleUp' : d > 1 ? 'FortyFiveUp' : d < -8 ? 'DoubleDown' : d < -3 ? 'SingleDown' : d < -1 ? 'FortyFiveDown' : 'Flat';
  }
  device = { demo: true };
  return rows;
}

async function sync() {
  try {
    const rows = cfg.provider === 'carelink' ? await carelink() : demo();
    addEntries(rows);
    lastSync = Date.now(); lastError = null;
  } catch (e) { lastError = e.message; console.error('[sync]', e.message); }
}

/* ---------------- HTTP ---------------- */
const json = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
const body = req => new Promise(r => { let d = ''; req.on('data', c => d += c); req.on('end', () => { try { r(JSON.parse(d || '{}')); } catch { r({}); } }); });

http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x'), q = u.searchParams;
  try {
    if (/^\/api\/v1\/entries(\/sgv)?(\.json)?$/.test(u.pathname) && req.method === 'GET')
      return json(res, 200, db.entries.filter(e => e.date >= (+q.get('since') || 0)).slice(0, +q.get('count') || 288));

    if (/^\/api\/v1\/treatments(\.json)?$/.test(u.pathname)) {
      if (req.method === 'POST') {
        const t = await body(req), date = t.created_at ? Date.parse(t.created_at) : Date.now();
        const rec = { _id: 't' + date + Math.random().toString(36).slice(2, 6), eventType: t.eventType || 'Note',
          insulin: t.insulin ? +t.insulin : undefined, carbs: t.carbs ? +t.carbs : undefined, notes: t.notes || '',
          created_at: new Date(date).toISOString(), date };
        db.treatments.push(rec); db.treatments.sort((a, b) => b.date - a.date); save();
        return json(res, 201, rec);
      }
      if (req.method === 'DELETE') { db.treatments = db.treatments.filter(t => t._id !== q.get('id')); save(); return json(res, 200, { ok: 1 }); }
      return json(res, 200, db.treatments.filter(t => t.date >= (+q.get('since') || 0)).slice(0, +q.get('count') || 500));
    }

    if (u.pathname === '/api/status' || u.pathname === '/api/v1/status.json')
      return json(res, 200, { name: 'Dr. Pocket', provider: cfg.provider, signedIn: !!tok, lastSync, lastError, device,
        thresholds: { low: cfg.low, high: cfg.high }, count: db.entries.length });

    if (u.pathname === '/api/sync' && req.method === 'POST') { await sync(); return json(res, 200, { lastSync, lastError }); }

    if (u.pathname === '/api/carelink/authorize')
      return json(res, 200, { url: await clAuthorizeUrl((q.get('region') || 'US').toUpperCase()) });

    if (u.pathname === '/api/carelink/callback' && req.method === 'POST') {
      const b = await body(req);
      try {
        await clExchange(b.code || b.url || '');
        if (cfg.provider !== 'carelink') { cfg.provider = 'carelink'; setEnv('PROVIDER', 'carelink'); }
        await sync();
        return json(res, 200, { ok: !lastError, lastError });
      } catch (e) { return json(res, 400, { error: e.message }); }
    }

    if (u.pathname === '/api/carelink/logout' && req.method === 'POST') {
      tok = null; fs.rmSync(TOKENS, { force: true }); conf = null;
      cfg.provider = 'demo'; setEnv('PROVIDER', 'demo');
      return json(res, 200, { ok: 1 });
    }

    if (u.pathname === '/api/provider' && req.method === 'POST') {
      const b = await body(req);
      if (!['carelink', 'demo'].includes(b.provider)) return json(res, 400, { error: 'bad provider' });
      cfg.provider = b.provider; setEnv('PROVIDER', b.provider);
      await sync(); return json(res, 200, { provider: cfg.provider, lastSync, lastError });
    }

    if (u.pathname === '/api/reset' && req.method === 'POST') { db.entries = []; save(); return json(res, 200, { ok: 1 }); }

    if (u.pathname === '/api/export') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Disposition': 'attachment; filename=drpocket.json' });
      return res.end(JSON.stringify(db, null, 1));
    }

    const rel = path.normalize(decodeURIComponent(u.pathname === '/' ? '/index.html' : u.pathname)).replace(/^[\\/]+/, '');
    const f = path.join(ROOT, 'public', rel);
    if (f.startsWith(path.join(ROOT, 'public')) && fs.existsSync(f) && fs.statSync(f).isFile()) {
      const type = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[path.extname(f)] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': type });
      return fs.createReadStream(f).pipe(res);
    }
    json(res, 404, { error: 'not found' });
  } catch (e) { json(res, 500, { error: e.message }); }
}).listen(cfg.port, '127.0.0.1', () => console.log(`Dr. Pocket (${cfg.provider}) → http://localhost:${cfg.port}`));

sync();
setInterval(sync, 5 * 60 * 1000);
