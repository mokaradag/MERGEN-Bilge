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

function load(pathname, search) {
  const writes = [];
  const store = new Map([['mergen_current_chat', 'kullanıcı sohbeti'], ['mergen_settings', '{}']]);
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
    addEventListener: () => {},
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {}
  });
  context.window = context;
  vm.runInContext(harness, context, { filename: 'ux-smoke.html' });
  return { nodes, writes, store, click: () => (listeners['start-smoke:click'] || []).forEach(fn => fn()) };
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
for (const pathname of ['/smoke/ux-smoke.html', '/bilge/smoke/ux-smoke.html',
                        '/base/nested/__mergen_ux_' + 'a1'.repeat(24) + '/ux-smoke.html']) {
  const page = load(pathname, '?autostart=1&fullQuickActions=1');
  const targetCode = harness.slice(harness.indexOf('function targetUrl()'), harness.indexOf('async function waitForFrameAccessible'));
  const target = new URL(vm.runInNewContext('(' + targetCode.trim() + ')()', { window: { location: { href: 'https://mergen.test' + pathname + '?autostart=1#ignored' } }, URL, Date }));
  assert.equal(target.origin, 'https://mergen.test');
  assert.equal(target.pathname, new URL('../', 'https://mergen.test' + pathname).pathname);
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

console.log('ux smoke start gate regressions passed');
