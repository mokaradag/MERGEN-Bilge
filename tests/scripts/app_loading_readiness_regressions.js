// Açılış katmanı hazır-olma regresyonları: gerçek www/js/app_loading.js küçük
// bir sahte DOM ve sanal zamanlayıcılarla çalıştırılır. Her senaryo TAZE bir
// katman (ayrı VM bağlamı, DOM, zamanlayıcılar) kurar: önceki senaryonun
// aşaması/zamanlayıcısı sonrakinin sonucunu gizleyemez.
// Doğrulananlar: kısmen hazır sonuçta hazır aşaması önce niteliksiz "Hazır"
// göstermez; Söyleşi Yönetimi kısmi etiketi tamamlanma sözü vermez; şerit
// seçimi çözülünce kuyruğa alınan kapanış çalışır ve hazır-olma geri çekilirse
// iptal edilir; bekleme etiketi koşulu kalkınca nötr etikete döner; kapanış
// sürerken gelen toparlanma ve geri çekilme görünen durumu doğru günceller.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const kaynak = fs.readFileSync(path.resolve(__dirname, '../../www/js/app_loading.js'), 'utf8');

// Zengin Deneyim'in zorunlu kontrol noktaları (R/module_boot_readiness.R ile aynı).
const ZENGIN = ['auth_ready', 'saved_chats_preview_ready', 'file_index_ready', 'character_media_ready',
                'welcome_client_ready', 'management_pages_ready'];
const yonetimHaric = ZENGIN.filter(k => k !== 'management_pages_ready');

function yeniKatman() {
  let saat = 0;
  let sayac = 0;
  const zamanlayicilar = new Map();
  const zamanla = (fn, ms, tekrar) => {
    const id = ++sayac;
    zamanlayicilar.set(id, { fn, bitis: saat + (ms || 0), aralik: tekrar ? (ms || 1) : 0, sifirGecikme: !tekrar && !ms });
    return id;
  };
  const ilerlet = ms => {
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
  };
  const dugum = () => {
    const siniflar = new Set();
    return {
      textContent: '', style: {},
      classList: { add: c => siniflar.add(c), remove: c => siniflar.delete(c), contains: c => siniflar.has(c) },
      querySelector: () => null
    };
  };
  const durumMetni = dugum();
  const katman = dugum();
  katman.querySelector = sec => (sec === '.alo-status-text' ? durumMetni : null);
  const belge = {
    readyState: 'complete', documentElement: dugum(),
    getElementById: id => (id === 'app-loading-overlay' ? katman : null),
    addEventListener: () => {}
  };
  const shinyIsleyiciler = {};
  const durum = { seritCozuldu: null, kapiBirakma: 0 };
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
      whenResolved: fn => { durum.seritCozuldu = fn; }
    },
    MergenBootShellGate: { release: () => { durum.kapiBirakma += 1; } },
    Shiny: { addCustomMessageHandler: (ad, fn) => { shinyIsleyiciler[ad] = fn; } }
  };
  const baglam = vm.createContext({
    window: pencere, document: belge, Date: { now: () => saat }, JSON, Math, String, Number, Array,
    localStorage: { getItem: () => null }, console
  });
  Object.assign(baglam, pencere);
  vm.runInContext(kaynak, baglam, { filename: 'app_loading.js' });
  ilerlet(100);
  return {
    serit, durum, durumMetni, katman, ilerlet,
    kontrol: msg => shinyIsleyiciler.bootReadinessCheckpoint(msg),
    kapandi: () => katman.classList.contains('alo-complete'),
    gizlendi: () => katman.style.display === 'none',
    // Test eşitleme noktası: hemen çalışacak (0 ms) kapanış kuyrukta mı?
    sifirGecikmeliKuyrukta: () => [...zamanlayicilar.values()].some(z => z.sifirGecikme && z.bitis <= saat)
  };
}

const hazir = (k, kismen) => k.kontrol({ key: 'management_pages_ready', ready: true, kismen: kismen || [],
                                         required_done: ZENGIN, required_total: ZENGIN.length });
// Sunucunun kimlik kaybında yayımladığı toplu kontrol noktası: Söyleşi Yönetimi
// kısmen, kimlik ön koşulu (auth_ready) artık tamamlanmamış.
const kimlikKaybi = k => k.kontrol({ key: 'management_pages_ready', ready: false, kismen: ['management_pages_ready'],
                                     detail: { degraded: true, identity: false },
                                     required_done: ZENGIN.filter(x => x !== 'auth_ready' && x !== 'management_pages_ready'),
                                     required_total: ZENGIN.length });

// 1) Yalnızca Söyleşi Yönetimi eksikken bekleme etiketi gösterilir; kimlik
// kaybıyla koşul kalkınca tamamlanmış aşamanın etiketi değil nötr etiket görünür.
{
  const k = yeniKatman();
  k.kontrol({ key: 'welcome_client_ready', required_done: yonetimHaric, required_total: ZENGIN.length });
  k.ilerlet(300);
  assert.equal(k.durumMetni.textContent, 'Söyleşi Yönetimi verisi hazırlanıyor');
  kimlikKaybi(k);
  k.ilerlet(400);
  assert.equal(k.durumMetni.textContent, 'Hazırlık sürüyor', 'koşul kalkınca nötr bekleme etiketi gösterilmeli');
  assert.equal(k.kapandi(), false);
}

// 2) İlk geçişte kısmen hazır (taze katman, aşama hazırın altında): 200 ms'lik
// etiket zamanlayıcısından önce de sonra da niteliksiz "Hazır" görünmez.
{
  const k = yeniKatman();
  k.serit.secimGerekli = true;   // kapanış ertelenir; yalnızca etiket sınanır
  hazir(k, ['management_pages_ready']);
  assert.notEqual(k.durumMetni.textContent, 'Hazır', '200 ms dolmadan Hazır görünmemeli');
  k.ilerlet(190);
  assert.notEqual(k.durumMetni.textContent, 'Hazır');
  k.ilerlet(20);
  assert.equal(k.durumMetni.textContent, 'Kısmen hazır — Söyleşi Yönetimi verisi henüz tamamlanmadı');
  for (let t = 0; t < 400; t += 20) {
    k.ilerlet(20);
    assert.notEqual(k.durumMetni.textContent, 'Hazır', 'kısmen hazırda niteliksiz Hazır görünmemeli');
  }
  assert.doesNotMatch(k.durumMetni.textContent, /tamamlanacak/);
  assert.equal(k.kapandi(), false, 'şerit seçimi beklenirken kapanmamalı');
}

// 3) Hazır-olma 200 ms'lik etiket zamanlayıcısı dolmadan geri çekilir: bekleyen
// "Hazır" etiketi yazılmaz.
{
  const k = yeniKatman();
  k.serit.secimGerekli = true;
  hazir(k);
  k.ilerlet(100);
  kimlikKaybi(k);
  k.ilerlet(400);
  assert.notEqual(k.durumMetni.textContent, 'Hazır', 'geri çekilen hazır-olmada Hazır yazılmamalı');
  assert.equal(k.durumMetni.textContent, 'Hazırlık sürüyor');
  assert.equal(k.kapandi(), false);
  // Geri çekilmeden sonra önce yalnız Söyleşi Yönetimi eksik, sonra ikinci geri
  // çekilme: "Hazır" geri yazılmaz.
  k.kontrol({ key: 'auth_ready', ready: false, required_done: yonetimHaric, required_total: ZENGIN.length });
  assert.equal(k.durumMetni.textContent, 'Söyleşi Yönetimi verisi hazırlanıyor');
  kimlikKaybi(k);
  k.ilerlet(400);
  assert.notEqual(k.durumMetni.textContent, 'Hazır', 'ikinci geri çekilmede Hazır geri yazılmamalı');
  assert.equal(k.kapandi(), false);
}

// 4) Denetim: hazır-olma şerit seçimi beklerken gelir; ertelenmiş kapanış
// (260 ms) dolduktan sonra şerit çözülür ve YENİ kontrol noktası olmadan katman kapanır.
{
  const k = yeniKatman();
  k.serit.secimGerekli = true;
  hazir(k);
  k.ilerlet(300);
  assert.equal(k.kapandi(), false, 'şerit seçimi çözülmeden kapanmamalı');
  k.serit.secimGerekli = false;
  k.durum.seritCozuldu();
  assert.ok(k.sifirGecikmeliKuyrukta(), 'şerit çözülünce kapanış kuyruğa alınmalı');
  k.ilerlet(20);
  assert.equal(k.kapandi(), true, 'şerit çözülünce kuyruktaki kapanış çalışmalı');
  assert.equal(k.durumMetni.textContent, 'Hazır');
  k.ilerlet(15000);
  assert.ok(k.gizlendi(), 'katman erime sonunda gizlenmeli');
  assert.ok(k.durum.kapiBirakma >= 1, 'kabuk kapısı bırakılmalı');
}

// 5) Aynı kurulum: şerit çözülüp kapanış kuyruğa alındıktan SONRA hazır-olma geri
// çekilir; o kuyruktaki kapanış iptal edilir ve görünen etiket hazır değildir.
{
  const k = yeniKatman();
  k.serit.secimGerekli = true;
  hazir(k, ['management_pages_ready']);
  k.ilerlet(300);
  k.serit.secimGerekli = false;
  k.durum.seritCozuldu();
  assert.ok(k.sifirGecikmeliKuyrukta(), 'geri çekilmeden önce kapanış kuyrukta olmalı');
  kimlikKaybi(k);
  k.ilerlet(1000);
  assert.equal(k.kapandi(), false, 'geri çekilen hazır-olma kuyruktaki kapanışı iptal etmeli');
  assert.equal(k.durumMetni.textContent, 'Hazırlık sürüyor', 'görünen kısmen hazır etiketi geri çekilmede kalkmalı');
}

// 6) Kısmen hazır kapanış yolu: katman kısmen hazırken kapanır ve nitelikli
// etiketi korur.
{
  const k = yeniKatman();
  hazir(k, ['management_pages_ready']);
  k.ilerlet(300);
  assert.equal(k.kapandi(), true, 'kısmen hazırda da katman kapanmalı');
  assert.equal(k.durumMetni.textContent, 'Kısmen hazır — Söyleşi Yönetimi verisi henüz tamamlanmadı');
  k.ilerlet(15000);
  assert.ok(k.gizlendi());
  assert.equal(k.durumMetni.textContent, 'Kısmen hazır — Söyleşi Yönetimi verisi henüz tamamlanmadı');
}

// 7) Kapanış sürerken (kapı bırakılmadan) gelen toparlanma görünen etiketi
// "Hazır" yapar; animasyon yeniden başlamaz ve katman kapanır.
{
  const k = yeniKatman();
  hazir(k, ['management_pages_ready']);
  k.ilerlet(280);
  assert.equal(k.kapandi(), true);
  assert.equal(k.durum.kapiBirakma, 0, 'kapanış henüz kapıyı bırakmamış olmalı');
  hazir(k);
  assert.equal(k.durumMetni.textContent, 'Hazır', 'kapanıştaki toparlanma etiketi güncellemeli');
  assert.equal(k.kapandi(), true);
  k.ilerlet(15000);
  assert.ok(k.gizlendi());
  assert.ok(k.durum.kapiBirakma >= 1, 'kapanış tamamlanıp kapıyı bırakmalı');
}

// 8) Kapanış sürerken (kapı bırakılmadan) geri çekilme tamamlanmayı iptal eder:
// katman açık kalır, "Hazır" görünmez; sonraki geçerli hazır kapanışı yeniden başlatır.
{
  const k = yeniKatman();
  hazir(k);
  k.ilerlet(280);
  assert.equal(k.kapandi(), true);
  assert.equal(k.durum.kapiBirakma, 0);
  kimlikKaybi(k);
  assert.equal(k.kapandi(), false, 'geri çekilme kapanışı iptal etmeli');
  assert.notEqual(k.durumMetni.textContent, 'Hazır');
  k.ilerlet(15000);
  assert.ok(!k.gizlendi(), 'iptal edilen kapanışta katman gizlenmemeli');
  assert.equal(k.durum.kapiBirakma, 0, 'iptal edilen kapanış kapıyı bırakmamalı');
  hazir(k);
  k.ilerlet(300);
  assert.equal(k.kapandi(), true, 'yeniden hazır kapanışı başlatmalı');
  assert.equal(k.durumMetni.textContent, 'Hazır');
  k.ilerlet(15000);
  assert.ok(k.gizlendi(), 'yeniden başlayan kapanış tamamlanmalı');
  assert.ok(k.durum.kapiBirakma >= 1);
}

// 9) Kapanış iptal edildikten sonra hazır-olma hiç geri gelmezse katman kalıcı
// olarak açık kalmaz: durma gözcüsü (ilerleme yoksa) son çare kapanışını yapar.
{
  const k = yeniKatman();
  hazir(k);
  k.ilerlet(280);
  assert.equal(k.kapandi(), true);
  kimlikKaybi(k);
  assert.equal(k.kapandi(), false);
  k.ilerlet(60000);
  assert.ok(k.gizlendi(), 'hazır-olma geri gelmese de gözcü katmanı kapatmalı');
}

console.log('app_loading_readiness_regressions: OK');
