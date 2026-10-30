// tests/scripts/ux_smoke_start_gate_regressions.js
// UX smoke harness'ı sayfa yüklemesiyle gerçek uygulama eylemi başlatmaz:
// iframe uygulamaya yönlenmez, localStorage değişmez. Yalnızca bakımcı
// "başlat" düğmesine basınca ya da otomasyon ?autostart=1 verince başlar;
// /img/smoke/ takma yolundan hiç çalışmaz.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');

// Harness'ın tek satır içi betiği, sabit açılış/kapanış işaretleri arasından
// kesilir (kendi dosyamız; HTML ayrıştırma/filtreleme yapılmaz).
const html = fs.readFileSync(path.join(root, 'tests/smoke/ux-smoke.html'), 'utf8').replace(/\r\n/g, '\n');
const OPEN = '<script>\n';
const CLOSE = '\n</script>';
const start = html.indexOf(OPEN);
assert.ok(start >= 0, 'satır içi harness betiği bulunamadı');
assert.equal(html.indexOf(OPEN, start + 1), -1, 'tek satır içi harness betiği beklenir');
const end = html.indexOf(CLOSE, start);
assert.ok(end > start, 'harness betiği kapanışı bulunamadı');
const harness = html.slice(start + OPEN.length, end);

function load(pathname, search, initialStorage) {
  const writes = [];
  const store = new Map(initialStorage || [['mergen_current_chat', 'kullanıcı sohbeti'], ['mergen_settings', '{}']]);
  const listeners = {};
  function el(id) {
    return {
      id, textContent: '', className: '', disabled: true, srcSet: [], onload: null,
      set src(v) { this.srcSet.push(v); }, get src() { return this.srcSet[this.srcSet.length - 1] || ''; },
      addEventListener(name, fn) { (listeners[id + ':' + name] = listeners[id + ':' + name] || []).push(fn); },
      appendChild() {}, scrollTop: 0, scrollHeight: 0
    };
  }
  const nodes = { status: el('status'), log: el('log'), 'app-frame': el('app-frame'), 'start-smoke': el('start-smoke') };
  const context = vm.createContext({
    console: { log() {}, warn() {}, error() {} }, JSON, Date, Math, Promise, URL, URLSearchParams,
    document: { getElementById: id => nodes[id] || null, createElement: () => el('x') },
    localStorage: {
      getItem: k => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => { writes.push(['set', k]); store.set(k, String(v)); },
      removeItem: k => { writes.push(['remove', k]); store.delete(k); }
    },
    location: { href: 'https://mergen.test' + pathname + (search || ''), pathname, search: search || '', hash: '' },
    addEventListener: (name, fn) => { listeners[name] = fn; },
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {}
  });
  context.window = context;
  // Yalnız test bağlamına erişim; üretim harness'ına yeni dış API eklenmez.
  const instrumented = harness.replace('var QUICK_ACTION_EXPECTATIONS = {',
    'window.storageContract = { prepareFreshAppStorage, restoreSmokeStorage, failures }; var QUICK_ACTION_EXPECTATIONS = {');
  vm.runInContext(instrumented, context, { filename: 'ux-smoke.html' });
  return { nodes, writes, store, context, listeners, click: () => (listeners['start-smoke:click'] || []).forEach(fn => fn()) };
}

// 1) Kapılı yol, parametresiz: hiçbir eylem yok; düğme etkin.
let p = load('/bilge/smoke/ux-smoke.html', '');
assert.deepEqual(p.writes, [], 'sayfa yüklemesi localStorage değiştirmemeli');
assert.deepEqual(p.nodes['app-frame'].srcSet, [], 'iframe uygulamaya yönlenmemeli');
assert.equal(p.store.get('mergen_current_chat'), 'kullanıcı sohbeti');
assert.equal(p.nodes['start-smoke'].disabled, false);
assert.match(p.nodes.status.textContent, /başlatmak için düğmeye basın/);

// Açık başlatma: düğme koşuyu başlatır.
p.click();
assert.ok(p.writes.length > 0, 'başlatma sonrası smoke hazırlığı çalışmalı');
assert.equal(p.nodes['start-smoke'].disabled, true);

// 2) Otomasyon koşucusu açıkça ?autostart=1 verir.
p = load('/bilge/smoke/ux-smoke.html', '?autostart=1');
assert.ok(p.writes.length > 0);

// Koken ve alt yol korunur; smoke sorgusu iframe'e gitmez.
for (const [pathname, expectedRoot] of [
  ['/smoke/ux-smoke.html', '/'],
  ['/bilge/smoke/ux-smoke.html', '/bilge/'],
  ['/base/nested/__mergen_ux_' + 'a1'.repeat(24) + '/ux-smoke.html', '/base/nested/']
]) {
  const page = load(pathname, '?autostart=1&fullQuickActions=1');
  const targetCode = harness.slice(harness.indexOf('function targetUrl()'), harness.indexOf('async function waitForFrameAccessible'));
  const target = new URL(vm.runInNewContext('(' + targetCode.trim() + ')()', { window: { location: { href: 'https://mergen.test' + pathname + '?autostart=1#ignored' } }, URL, Date }));
  assert.equal(target.origin, 'https://mergen.test');
  assert.equal(target.pathname, expectedRoot);
  assert.equal(target.search, '');
  assert.match(target.hash, /^#ux_smoke_target=/);
}

// 3) /img takma yolundan (harf varyantları dahil) hiç çalışmaz.
for (const [yol, search] of [['/bilge/img/smoke/ux-smoke.html', ''], ['/bilge/img/smoke/ux-smoke.html', '?autostart=1'],
                             ['/bilge/IMG/Smoke/UX-SMOKE.HTML', '?autostart=1']]) {
  p = load(yol, search);
  p.click();
  assert.deepEqual(p.writes, []);
  assert.deepEqual(p.nodes['app-frame'].srcSet, []);
  assert.match(p.nodes.status.textContent, /kapılı \/smoke\/ yolundan/);
}

// 4) Başka sorgu parametreleri (ör. fullQuickActions) başlatma sayılmaz.
p = load('/smoke/ux-smoke.html', '?fullQuickActions=1&autostart=0');
assert.deepEqual(p.writes, []);

// Kalıcı profil: eski sohbet/şerit tercihinden bağımsız welcome, sonra tam iade.
for (const initial of [[], [
  ['mergen_settings', JSON.stringify({ skip_intro: false, startup_lane: 'fast_lane', custom: 'tercih' })],
  ['mergen_current_chat', 'önceki sohbet'], ['mergen_active_tab', 'history'],
  ['mergen_bilge_jwt_token', 'synthetic-sso-sentinel'], ['unrelated', 'koru']
]]) {
  p = load('/smoke/ux-smoke.html', '', initial);
  const snapshot = new Map(p.store);
  p.context.storageContract.prepareFreshAppStorage();
  const settings = JSON.parse(p.store.get('mergen_settings'));
  assert.equal(settings.skip_intro, true);
  assert.equal(settings.startup_lane, 'rich_lane');
  assert.equal(p.store.has('mergen_current_chat'), false);
  p.store.set('mergen_current_chat', 'smoke sohbeti');
  p.store.set('mergen_active_tab', 'claude_code_sessions');
  let active = true;
  let lateWrite;
  p.nodes['app-frame'].parentNode = { removeChild(frame) {
    active = false;
    frame.parentNode = null;
    // İframe yok edilmeden önceki son lifecycle yazısı da iade edilmelidir.
    p.store.set('mergen_settings', 'gecikmiş smoke ayarı');
    lateWrite = () => { if (active) p.store.set('mergen_current_chat', 'gecikmiş sohbet'); };
  } };
  p.context.storageContract.restoreSmokeStorage();
  assert.equal(active, false, 'iade canlı iframe yazarını önce durdurmalı');
  lateWrite();
  assert.deepEqual(p.store, snapshot, 'kullanıcı kaydı ve ilgisiz SSO/diğer anahtarlar korunmalı');
  p.store.set('mergen_settings', 'smoke bittikten sonraki kullanıcı değişikliği');
  p.listeners.beforeunload();
  assert.equal(p.store.get('mergen_settings'), 'smoke bittikten sonraki kullanıcı değişikliği');
}

// Okuma/iade hataları gizli PASS üretemez ve özgün veriyi bozamaz.
p = load('/smoke/ux-smoke.html', '');
p.context.localStorage.getItem = () => { throw new Error('blocked storage'); };
assert.throws(() => p.context.storageContract.prepareFreshAppStorage(), /başlangıç durumu okunamadı/);
assert.deepEqual(p.writes, []);
p = load('/smoke/ux-smoke.html', '');
p.context.storageContract.prepareFreshAppStorage();
p.context.localStorage.setItem = () => { throw new Error('blocked restore'); };
p.context.storageContract.restoreSmokeStorage();
assert.ok(p.context.storageContract.failures.some(message => message.includes('geri yükleme başarısız')),
          'iade hatası PASS yerine koşunun failure listesine girmeli');

// Her anahtar hem set hem remove hatasında denenir; hata ancak tüm denemelerden sonra bildirilir.
for (const existing of [false, true]) {
  for (const broken of [0, 1, 2]) {
    const keys = ['mergen_settings', 'mergen_current_chat', 'mergen_active_tab'];
    const initial = existing ? keys.map(key => [key, key === 'mergen_settings' ? '{"custom":true}' : 'original:' + key]) : [];
    const page = load('/smoke/ux-smoke.html', '', initial);
    page.context.storageContract.prepareFreshAppStorage();
    keys.forEach(key => page.store.set(key, 'smoke'));
    const attempts = [];
    const storage = page.context.localStorage;
    for (const method of ['setItem', 'removeItem']) {
      const original = storage[method];
      storage[method] = (key, ...args) => {
        assert.equal(page.context.storageContract.failures.length, 0, 'hata tüm denemelerden sonra bildirilir');
        attempts.push(key);
        if (key === keys[broken]) throw new Error('blocked:' + key);
        return original(key, ...args);
      };
    }
    page.context.storageContract.restoreSmokeStorage();
    assert.deepEqual(attempts, keys);
    keys.forEach((key, index) => {
      assert.equal(page.store.get(key), index === broken ? 'smoke' : new Map(initial).get(key));
    });
    assert.equal(page.context.storageContract.failures.length, 1);
    assert.match(page.context.storageContract.failures[0], new RegExp(keys[broken]));
    storage.setItem = (key, value) => page.store.set(key, value);
    storage.removeItem = key => page.store.delete(key);
    page.listeners.beforeunload(); // Kaydedilen başlangıç verisi hata sonrası yeniden denenebilir.
    assert.deepEqual(page.store, new Map(initial));
  }
}
const failed = load('/smoke/ux-smoke.html', '', []);
failed.context.storageContract.prepareFreshAppStorage();
const attempted = [];
failed.context.localStorage.removeItem = key => { attempted.push(key); throw new Error('blocked'); };
failed.context.storageContract.restoreSmokeStorage();
assert.equal(attempted.length, 3);
assert.equal(failed.context.storageContract.failures.length, 1);
for (const key of attempted) assert.ok(failed.context.storageContract.failures[0].includes(key));

console.log('ux smoke start gate regressions passed');
