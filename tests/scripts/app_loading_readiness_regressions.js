// Açılış katmanı hazır-olma regresyonları: gerçek www/js/app_loading.js küçük
// bir sahte DOM ve sanal zamanlayıcılarla çalıştırılır.
// Doğrulananlar: kısmen hazır sonuçta hazır aşaması önce niteliksiz "Hazır"
// göstermez; Söyleşi Yönetimi kısmi etiketi tamamlanma sözü vermez; şerit
// seçimi çözülünce kuyruğa alınan kapanış, hazır-olma geri çekilirse iptal
// edilir; Söyleşi Yönetimi bekleme etiketi koşulu kalkınca güncel aşamaya döner.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const kaynak = fs.readFileSync(path.resolve(__dirname, '../../www/js/app_loading.js'), 'utf8');

// --- Sanal saat ---------------------------------------------------------------
let saat = 0;
let sayac = 0;
const zamanlayicilar = new Map();
function zamanla(fn, ms, tekrar) {
  const id = ++sayac;
  zamanlayicilar.set(id, { fn, bitis: saat + (ms || 0), aralik: tekrar ? (ms || 1) : 0 });
  return id;
}
function ilerlet(ms) {
  const hedef = saat + ms;
  for (;;) {
    let enErken = null;
    for (const [id, z] of zamanlayicilar) if (z.bitis <= hedef && (!enErken || z.bitis < enErken[1].bitis)) enErken = [id, z];
    if (!enErken) break;
    const [id, z] = enErken;
    saat = z.bitis;
    if (z.aralik) z.bitis += z.aralik; else zamanlayicilar.delete(id);
    z.fn();
  }
  saat = hedef;
}

// --- Küçük sahte DOM ----------------------------------------------------------
function dugum() {
  const siniflar = new Set();
  return {
    textContent: '', style: {},
    classList: { add: c => siniflar.add(c), remove: c => siniflar.delete(c), contains: c => siniflar.has(c) },
    querySelector: () => null
  };
}
const durumMetni = dugum();
const katman = dugum();
katman.querySelector = sec => (sec === '.alo-status-text' ? durumMetni : null);
const belge = {
  readyState: 'complete',
  documentElement: dugum(),
  getElementById: id => (id === 'app-loading-overlay' ? katman : null),
  addEventListener: () => {}
};
const shinyIsleyiciler = {};
let seritCozuldu = null;
const serit = { hizli: false, secimAcik: false, secimGerekli: false };
const pencere = {
  setTimeout: (fn, ms) => zamanla(fn, ms, false),
  clearTimeout: id => zamanlayicilar.delete(id),
  setInterval: (fn, ms) => zamanla(fn, ms, true),
  clearInterval: id => zamanlayicilar.delete(id),
  requestAnimationFrame: fn => zamanla(fn, 16, false),
  cancelAnimationFrame: id => zamanlayicilar.delete(id),
  getComputedStyle: () => ({ display: 'none' }),
  MergenStartupLane: {
    isFast: () => serit.hizli,
    isSelectorOpen: () => serit.secimAcik,
    needsSelection: () => serit.secimGerekli,
    whenResolved: fn => { seritCozuldu = fn; }
  },
  Shiny: { addCustomMessageHandler: (ad, fn) => { shinyIsleyiciler[ad] = fn; } }
};
const baglam = vm.createContext({
  window: pencere, document: belge, Date: { now: () => saat }, JSON, Math, String, Number, Array,
  localStorage: { getItem: () => null }, console
});
Object.assign(baglam, pencere);
vm.runInContext(kaynak, baglam, { filename: 'app_loading.js' });
ilerlet(100);

const kontrol = msg => shinyIsleyiciler.bootReadinessCheckpoint(msg);
const kapandi = () => katman.classList.contains('alo-complete');

// 1) Söyleşi Yönetimi dışında her şey tamamken bekleme etiketi gösterilir; koşul
// kalkınca (ör. kimlik kaybı) etiket güncel aşamaya döner.
kontrol({ key: 'auth_ready', required_done: ['connect', 'auth_ready'], required_total: 3 });
ilerlet(300);
assert.equal(durumMetni.textContent, 'Söyleşi Yönetimi verisi hazırlanıyor');
kontrol({ key: 'auth_ready', required_done: ['connect'], required_total: 3 });
assert.equal(durumMetni.textContent, 'Kimlik doğrulandı', 'koşul kalkınca bekleme etiketi değişmeli');

// 2) Kısmen hazır: hazır aşaması hiçbir anda niteliksiz "Hazır" göstermez ve
// Söyleşi Yönetimi etiketi sayfa açılışında tamamlanma sözü vermez.
// Şerit seçimi bekleniyor: kapanış seçim çözülene dek ertelenir.
serit.secimGerekli = true;
kontrol({ key: 'management_pages_ready', ready: true, kismen: ['management_pages_ready'],
          required_done: ['connect', 'auth_ready', 'management_pages_ready'], required_total: 3 });
for (let t = 0; t < 400; t += 20) {
  ilerlet(20);
  assert.notEqual(durumMetni.textContent, 'Hazır', 'kısmen hazırda niteliksiz Hazır görünmemeli');
}
assert.equal(durumMetni.textContent, 'Kısmen hazır — Söyleşi Yönetimi verisi henüz tamamlanmadı');
assert.doesNotMatch(durumMetni.textContent, /tamamlanacak/);
assert.equal(kapandi(), false, 'şerit seçimi beklenirken kapanmamalı');

// 3) Şerit çözüldü (kapanış kuyruğa alındı) ama aynı turda hazır-olma geri
// çekildi: kuyruktaki kapanış iptal edilir, katman açık kalır.
serit.secimGerekli = false;
seritCozuldu();
kontrol({ key: 'auth_ready', ready: false, required_done: ['connect'], required_total: 3 });
ilerlet(1000);
assert.equal(kapandi(), false, 'geri çekilen hazır-olma kuyruktaki kapanışı iptal etmeli');

// 4) Tam hazır: etiket "Hazır" ve katman kapanır.
kontrol({ key: 'management_pages_ready', ready: true, kismen: [],
          required_done: ['connect', 'auth_ready', 'management_pages_ready'], required_total: 3 });
ilerlet(1000);
assert.equal(kapandi(), true);
assert.equal(durumMetni.textContent, 'Hazır');

console.log('app_loading_readiness_regressions: OK');
