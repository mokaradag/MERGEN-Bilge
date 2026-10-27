// tests/scripts/browser_identity_regressions.js
// Tarayıcı kimlik yaşam döngüsü: SSO giriş durumu (state), istenmemiş /
// eşleşmeyen / tekrar oynatılan dönüş, olağan geri dönen kullanıcı, kenar
// çubuğu çıkışı ve hesaba bağlı sohbet kaydı. Aynı tarayıcı profili ortak
// localStorage, her sekme kendi sessionStorage'ı ile simüle edilir.
//
// Kullanım: node browser_identity_regressions.js <preflight.js> <logout_onclick.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const nodeCrypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');

const preflightSource = fs.readFileSync(process.argv[2], 'utf8');
const logoutOnclick = fs.readFileSync(process.argv[3], 'utf8');
const ssoSource = fs.readFileSync(path.join(root, 'www/js/sso_auth.js'), 'utf8');
const handlersSource = fs.readFileSync(path.join(root, 'www/js/shiny_message_handlers.js'), 'utf8');

const SSO_CONFIG = {
  enabled: true, auth_endpoint: 'https://kc.test/auth', client_id: 'mergen-bilge',
  response_type: 'token', scope: 'openid', logout_endpoint: '', overlay_id: 'ov',
  loading_id: 'ld', error_id: 'er', error_msg_id: 'em', ns_prefix: 'sso_module-'
};

function storage() {
  const m = new Map();
  return {
    map: m,
    getItem: k => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: k => m.delete(k)
  };
}

function jwt(sub, expOffset) {
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  return b64({ alg: 'RS256' }) + '.' + b64({ sub, exp: Math.floor(Date.now() / 1000) + expOffset }) + '.imza';
}

// Tek bir sayfa yüklemesi: ön kapı betiği, ardından (yönlendirme yoksa) sso_auth.js.
function visit(profile, tab, hash) {
  const nav = { replaced: null, href: null, historyReplaced: false };
  const sent = [];
  const timers = [];
  const el = () => ({ style: {}, classList: { add() {}, remove() {} }, textContent: '' });
  const location = {
    origin: 'https://mergen.test', pathname: '/bilge/', search: '', hash: hash || '',
    replace: u => { nav.replaced = u; },
    reload: () => { nav.reloaded = true; },
    set href(u) { nav.href = u; }, get href() { return nav.href || ''; }
  };
  const document = {
    readyState: 'complete',
    documentElement: { classList: { add() {}, remove() {} } },
    addEventListener() {},
    getElementById: id => (id === 'sso_module-sso_config_data' ? { textContent: JSON.stringify(SSO_CONFIG) } : el())
  };
  const context = vm.createContext({
    document, location, console: { log() {}, warn() {}, error() {} }, JSON, Math, Date, Array, String, Uint8Array,
    localStorage: profile.local, sessionStorage: tab.session,
    crypto: { getRandomValues: a => nodeCrypto.randomFillSync(a) },
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    history: { replaceState: () => { nav.historyReplaced = true; location.hash = ''; } },
    setTimeout: (fn, ms) => { timers.push(fn); return timers.length; },
    Shiny: {
      setInputValue: (id, v) => sent.push([id, v]),
      addCustomMessageHandler() {}
    }
  });
  context.window = context;
  vm.runInContext(preflightSource, context, { filename: 'preflight.js' });
  if (!nav.replaced) vm.runInContext(ssoSource, context, { filename: 'sso_auth.js' });
  return { nav, sent, context, timers };
}

// vm içinde oluşan nesneler farklı realm prototipi taşır; düz veriye indirgenir.
const plain = x => JSON.parse(JSON.stringify(x));

function stateOf(url) {
  const m = /[?&]state=([^&]+)/.exec(url || '');
  return m ? decodeURIComponent(m[1]) : null;
}

const profile = { local: storage() };

// 1) İlk ziyaret: token yok -> ön kapı Keycloak'a state ile yönlendirir.
const tab = { session: storage() };
let v = visit(profile, tab, '');
assert.ok(v.nav.replaced && v.nav.replaced.startsWith('https://kc.test/auth?'), 'ilk ziyaret yönlendirmeli');
const state1 = stateOf(v.nav.replaced);
assert.match(state1, /^[0-9a-f]{64}$/, 'state 32 bayt kriptografik rastgele olmalı');
assert.equal(tab.session.getItem('mergen_sso_login_state'), state1);

// 2) Eşleşen dönüş: token kabul edilir, state tüketilir, hash temizlenir.
const userA = jwt('A', 3600);
v = visit(profile, tab, '#state=' + state1 + '&session_state=x&access_token=' + userA + '&token_type=Bearer');
assert.equal(v.nav.replaced, null, 'geçerli dönüş yönlendirmemeli');
assert.ok(v.nav.historyReplaced, 'token URL hash\'inden temizlenmeli');
assert.equal(profile.local.getItem('mergen_bilge_jwt_token'), userA);
assert.equal(tab.session.getItem('mergen_sso_login_state'), null, 'state tek kullanımlık olmalı');
assert.deepEqual(v.sent, [['sso_module-sso_jwt_token', userA]]);

// 3) Tekrar oynatılan dönüş (aynı state + saldırgan token'ı): reddedilir,
//    kayıtlı oturum korunur.
const attacker = jwt('SALDIRGAN', 3600);
v = visit(profile, tab, '#state=' + state1 + '&access_token=' + attacker);
assert.equal(profile.local.getItem('mergen_bilge_jwt_token'), userA, 'tekrar oynatma token\'ı değiştirmemeli');
assert.deepEqual(v.sent, [['sso_module-sso_jwt_token', userA]]);
assert.ok(v.nav.historyReplaced);

// 4) İstenmemiş dönüş (bu sekmede bekleyen giriş yok): reddedilir.
const otherTab = { session: storage() };
v = visit(profile, otherTab, '#access_token=' + attacker);
assert.equal(profile.local.getItem('mergen_bilge_jwt_token'), userA);
assert.deepEqual(v.sent, [['sso_module-sso_jwt_token', userA]]);

// 5) Eşleşmeyen state: reddedilir; kayıtlı oturum yoksa yeni giriş başlar.
const freshProfile = { local: storage() };
const freshTab = { session: storage() };
v = visit(freshProfile, freshTab, '');
const realState = stateOf(v.nav.replaced);
v = visit(freshProfile, freshTab, '#state=' + 'f'.repeat(64) + '&access_token=' + attacker);
assert.equal(freshProfile.local.getItem('mergen_bilge_jwt_token'), null, 'eşleşmeyen state token kaydetmemeli');
assert.ok(v.nav.replaced && v.nav.replaced.startsWith('https://kc.test/auth?'), 'yeni giriş başlamalı');
assert.notEqual(stateOf(v.nav.replaced), realState, 'her giriş yeni state almalı');
assert.equal(v.sent.length, 0);
//    State tamamen eksikse de aynı sonuç.
v = visit({ local: storage() }, { session: storage() }, '#access_token=' + attacker);
assert.ok(v.nav.replaced, 'state\'siz dönüş yönlendirmeli');
assert.equal(v.sent.length, 0);

// 6) Olağan geri dönen kullanıcı: kayıtlı geçerli token ile doğrudan açılır.
v = visit(profile, { session: storage() }, '');
assert.equal(v.nav.replaced, null);
assert.deepEqual(v.sent, [['sso_module-sso_jwt_token', userA]]);

// 7) Kenar çubuğu çıkışı: token ve hesaba bağlı sohbet silinir; sonraki
//    ziyaret eski hesapla sessizce açılmaz.
profile.local.setItem('mergen_current_chat', JSON.stringify({ v: 2, owner: 'A', messages: [{ type: 'user', content: 'gizli' }] }));
v = visit(profile, { session: storage() }, '');
vm.runInContext(logoutOnclick, v.context, { filename: 'logout_onclick.js' });
assert.equal(profile.local.getItem('mergen_bilge_jwt_token'), null, 'çıkış token\'ı silmeli');
assert.equal(profile.local.getItem('mergen_current_chat'), null, 'çıkış sohbet kaydını silmeli');
assert.ok(v.sent.some(([id]) => id === 'mergen_sidebar_logout'));
v.timers.forEach(fn => fn());
assert.equal(v.nav.href, 'https://portal.test/cikis');
v = visit(profile, { session: storage() }, '');
assert.ok(v.nav.replaced, 'çıkış sonrası ziyaret yeniden giriş istemeli');
assert.equal(v.sent.length, 0, 'çıkış yapan hesabın token\'ı gönderilmemeli');

// ssoLogout da aynı merkezi temizliği kullanır.
profile.local.setItem('mergen_bilge_jwt_token', userA);
profile.local.setItem('mergen_current_chat', '{}');
v = visit(profile, { session: storage() }, '');
v.context.ssoLogout();
assert.equal(profile.local.getItem('mergen_bilge_jwt_token'), null);
assert.equal(profile.local.getItem('mergen_current_chat'), null);

// 8) Hesaba bağlı sohbet kaydı (istemci tarafı).
function handlers(local) {
  const msgHandlers = new Map();
  const sent = [];
  const timers = [];
  const listeners = {};
  const jq = () => new Proxy({}, { get: (t, k) => (k === 'ready' ? fn => fn() : () => jq()) });
  const context = vm.createContext({
    $: jq, jQuery: jq, console: { log() {}, warn() {}, error() {} }, JSON, Array, String,
    localStorage: local,
    document: { getElementById: () => null, querySelector: () => null, querySelectorAll: () => [] },
    setTimeout: fn => { timers.push(fn); return timers.length; },
    Shiny: { addCustomMessageHandler: (n, fn) => msgHandlers.set(n, fn), setInputValue: (id, v) => sent.push([id, v]) }
  });
  context.window = context;
  context.addEventListener = (n, fn) => { listeners[n] = fn; };
  vm.runInContext(handlersSource, context, { filename: 'shiny_message_handlers.js' });
  return { msgHandlers, sent, timers, run: () => timers.splice(0).forEach(fn => fn()) };
}

const chatProfile = storage();
// Kullanıcı A kaydeder: yalnızca sunucu etiketi + düz alanlar.
let h = handlers(chatProfile);
h.msgHandlers.get('saveCurrentChat')({ owner: 'etiketA', messages: [{ type: 'user', content: 'A gizli', timestamp: '10:00' }] });
let saved = JSON.parse(chatProfile.getItem('mergen_current_chat'));
assert.deepEqual(saved, { v: 2, owner: 'etiketA', messages: [{ type: 'user', content: 'A gizli', timestamp: '10:00' }] });
// Sahipsiz kaydetme isteği yok sayılır.
h.msgHandlers.get('saveCurrentChat')({ messages: [{ type: 'user', content: 'x' }] });
assert.equal(JSON.parse(chatProfile.getItem('mergen_current_chat')).owner, 'etiketA');

// Kullanıcı B aynı profilde açılır: kayıt sunucuya sahip etiketiyle gider;
// sunucu B'nin etiketiyle eşleştirmez ve silme ister.
h = handlers(chatProfile);
h.run();
assert.deepEqual(plain(h.sent), [['load_chat_from_storage', { owner: 'etiketA', messages: saved.messages }]]);
h.msgHandlers.get('clearCurrentChat')({});
assert.equal(chatProfile.getItem('mergen_current_chat'), null, 'sunucu reddi kaydı silmeli');

// Eski (sahipsiz dizi) biçim ve bozuk kayıt hiç gönderilmez, silinir.
for (const legacy of [JSON.stringify([{ id: 'x', type: 'ai', content: '<img src=x onerror=1>', html_content: '<img src=x onerror=1>' }]),
                      JSON.stringify({ v: 2, messages: [{ type: 'user', content: 'x' }] }),
                      JSON.stringify({ v: 2, owner: 'a', messages: [] })]) {
  chatProfile.setItem('mergen_current_chat', legacy);
  h = handlers(chatProfile);
  h.run();
  assert.deepEqual(plain(h.sent), [], 'sahipsiz/eski kayıt gönderilmemeli');
  assert.equal(chatProfile.getItem('mergen_current_chat'), null);
}

// 9) Çıkış sonrası sayfa kapanırken (beforeunload) sohbet yeniden yazılmaz.
(function logoutThenUnload() {
  const local = storage();
  const listeners = {};
  const msgHandlers = new Map();
  const bubble = { classList: { contains: c => c === 'user-message' }, textContent: 'gizli soru',
                   closest: () => ({ id: 'message_wrapper_m1' }) };
  const chat = { querySelectorAll: sel => (sel === '.message-bubble' ? [bubble] : []) };
  const jq = () => new Proxy({}, { get: (t, k) => (k === 'ready' ? fn => fn() : () => jq()) });
  const context = vm.createContext({
    $: jq, jQuery: jq, console: { log() {}, warn() {}, error() {} }, JSON, Math, Date, Array, String, Uint8Array,
    localStorage: local, sessionStorage: storage(),
    location: { origin: 'https://mergen.test', pathname: '/bilge/', search: '', hash: '', replace() {}, reload() {} },
    history: { replaceState() {} }, crypto: { getRandomValues: a => nodeCrypto.randomFillSync(a) },
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    setTimeout: () => 1,
    document: {
      readyState: 'complete', documentElement: { classList: { add() {}, remove() {} } }, addEventListener() {},
      getElementById: id => (id === 'chat_content_container' ? chat
        : id === 'sso_module-sso_config_data' ? { textContent: JSON.stringify(SSO_CONFIG) } : null),
      querySelector: () => null, querySelectorAll: () => []
    },
    Shiny: { addCustomMessageHandler: (n, fn) => msgHandlers.set(n, fn), setInputValue() {} }
  });
  context.window = context;
  context.addEventListener = (n, fn) => { listeners[n] = fn; };
  local.setItem('mergen_bilge_jwt_token', jwt('A', 3600));
  vm.runInContext(ssoSource, context, { filename: 'sso_auth.js' });
  vm.runInContext(handlersSource, context, { filename: 'shiny_message_handlers.js' });
  msgHandlers.get('saveCurrentChat')({ owner: 'etiketA', messages: [{ type: 'user', content: 'gizli soru' }] });

  // Kontrol: çıkış yoksa kapanışta sahibe bağlı kayıt yazılır (mevcut davranış).
  listeners.beforeunload();
  assert.equal(JSON.parse(local.getItem('mergen_current_chat')).owner, 'etiketA');

  vm.runInContext(logoutOnclick, context, { filename: 'logout_onclick.js' });
  listeners.beforeunload();
  assert.equal(local.getItem('mergen_current_chat'), null, 'çıkıştan sonra beforeunload sohbeti geri yazmamalı');
  assert.equal(local.getItem('mergen_bilge_jwt_token'), null);
  msgHandlers.get('saveCurrentChat')({ owner: 'etiketA', messages: [{ type: 'user', content: 'gizli soru' }] });
  assert.equal(local.getItem('mergen_current_chat'), null, 'çıkıştan sonra gelen kayıt isteği yok sayılmalı');
})();

console.log('browser identity regressions passed');
