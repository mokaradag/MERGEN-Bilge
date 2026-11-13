// İyimser (bekleyen) istem balonu davranış regresyonları: gerçek
// www/js/chat_pending_message.js + input_handlers.js küçük bir sahte DOM/jQuery
// üzerinde çalıştırılır. Sahte MutationObserver, üretim gözlemcisinin kayıtlı
// hedefine ve seçeneklerine (childList/subtree) UYAR: yanlış düğümü izleyen ya
// da childList olmadan kurulan bir gözlemci bu testlerde bildirim almaz.
// Tarayıcıdaki gibi kayıtlar DOM değişikliği yığını bittikten sonra mikro
// görevde toplu teslim edilir; doğrulamalar teslimi bekler (await teslim()).
// Doğrulananlar: anında çizim, çift gönderim engeli, kimlik tabanlı kabul
// (metin eşleşmesi karar vermez), asıl balondan önce gelen kabul, ret ve
// taslağın korunması, gezinmede metnin kaybolmaması, bağlantı kopmasında
// sonucu gelmemiş istemin (aynı metinli balon olsa da) geri yüklenmesi,
// kabulün canlı bölgede duyurulması, gecikmeli asıl balonda kabul edilmiş
// istemin kaybolmaması, erişilebilir düğme durumu.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const pendingSource = fs.readFileSync(path.resolve(__dirname, '../../www/js/chat_pending_message.js'), 'utf8');
const source = fs.readFileSync(path.resolve(__dirname, '../../www/js/input_handlers.js'), 'utf8');

// --- Seçeneklere uyan sahte MutationObserver --------------------------------
const observers = [];
function isInside(node, root) { let p = node; while (p) { if (p === root) return true; p = p.parentNode; } return false; }
function notify(parent, added, removed) {
  observers.forEach(o => {
    if (!o.options || o.options.childList !== true) return;
    if (!(parent === o.target || (o.options.subtree === true && isInside(parent, o.target)))) return;
    o.kuyruk.push({ type: 'childList', target: parent, addedNodes: added, removedNodes: removed });
    if (o.kuyruk.length === 1) queueMicrotask(() => { const kayitlar = o.kuyruk.splice(0); o.cb(kayitlar); });
  });
}
// Mikro görev kuyruğu boşalana dek bekler (gözlemci teslimi tamamlanır).
const teslim = () => new Promise(r => setImmediate(r));

// --- Küçük sahte DOM --------------------------------------------------------
function el(tag, attrs = {}) {
  const node = {
    tagName: tag.toUpperCase(), children: [], parentNode: null, attrs: Object.assign({}, attrs),
    style: {}, textContent: '', value: '', addEventListener() {},
    get id() { return this.attrs.id || ''; }, set id(v) { this.attrs.id = v; },
    get className() { return this.attrs.class || ''; }, set className(v) { this.attrs.class = v; },
    classList: null,
    appendChild(c) { c.parentNode = this; this.children.push(c); notify(this, [c], []); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); c.parentNode = null; notify(this, [], [c]); return c; },
    remove() { if (this.parentNode) this.parentNode.removeChild(this); },
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    hasAttribute(k) { return k in this.attrs; },
    removeAttribute(k) { delete this.attrs[k]; },
    querySelector(s) { return all(this, s)[0] || null; },
    querySelectorAll(s) { return all(this, s); },
    matches(s) { return s.split(',').some(p => matchSimple(this, p.trim().split(/\s+/).pop())); },
    closest(s) { let n = this; while (n) { if (n.matches && n.matches(s)) return n; n = n.parentNode; } return null; },
    cloneNode() { const c = el(tag, this.attrs); c.textContent = this.textContent; this.children.forEach(k => c.appendChild(k.cloneNode(true))); return c; }
  };
  node.classList = {
    contains: x => node.className.split(/\s+/).includes(x),
    add: x => { if (!node.classList.contains(x)) node.className = (node.className + ' ' + x).trim(); },
    remove: x => { node.className = node.className.split(/\s+/).filter(c => c && c !== x).join(' '); },
    toggle: (x, on) => (on ? node.classList.add(x) : node.classList.remove(x))
  };
  return node;
}
function matchSimple(n, s) {
  if (!n.attrs) return false;
  const re = /([#.]?[\w-]+)|\[([\w-]+)\]/g; let m; let ok = true;
  while ((m = re.exec(s))) {
    if (m[2]) ok = ok && (m[2] in n.attrs);
    else if (m[1][0] === '#') ok = ok && n.id === m[1].slice(1);
    else if (m[1][0] === '.') ok = ok && n.classList.contains(m[1].slice(1));
    else ok = ok && n.tagName === m[1].toUpperCase();
  }
  return ok;
}
function descendants(root) { const out = []; (function walk(n) { n.children.forEach(c => { out.push(c); walk(c); }); })(root); return out; }
function all(root, selector) {
  return descendants(root).filter(n => selector.split(',').some(part => {
    const chain = part.trim().split(/\s+/); if (!matchSimple(n, chain[chain.length - 1])) return false;
    let p = n.parentNode;
    for (let i = chain.length - 2; i >= 0; i--) { while (p && !matchSimple(p, chain[i])) p = p.parentNode; if (!p) return false; p = p.parentNode; }
    return true;
  }));
}

const body = el('body');
const chat = body.appendChild(el('div', { id: 'chat_content_container', class: 'chat-container' }));
const welcome = body.appendChild(el('div', { id: 'welcome_fullscreen_container', class: 'welcome-fullscreen-wrapper' }));
welcome.appendChild(el('div', { class: 'welcome-card' }));
const input = body.appendChild(el('textarea', { id: 'user_input', class: 'chat-input' }));
const btn = body.appendChild(el('button', { id: 'send_stop_btn', title: 'Gönder', 'aria-label': 'Mesajı gönder' }));
btn.appendChild(el('i', { class: 'fa-solid fa-paper-plane' }));
body.appendChild(el('div', { id: 'file_prompt_indicator_ui' }));

const captureClick = [];
const document = {
  body, readyState: 'complete',
  getElementById: id => all(body, '#' + id)[0] || null,
  querySelector: s => all(body, s)[0] || null,
  querySelectorAll: s => all(body, s),
  createElement: tag => el(tag),
  addEventListener: (name, fn, capture) => { if (name === 'click' && capture) captureClick.push(fn); }
};

// --- Küçük sahte jQuery ------------------------------------------------------
const handlers = {};
function $(target) {
  if (typeof target === 'function') { target(); return; }
  const nodes = target === document ? [document] : (typeof target === 'string' ? document.querySelectorAll(target) : (target ? [target] : []));
  const w = {
    length: nodes.length, 0: nodes[0],
    ready: fn => fn(),
    on: (evt, sel, fn) => { (handlers[evt + '|' + (typeof sel === 'string' ? sel : '')] ||= []).push(fn || sel); return w; },
    hasClass: c => nodes.some(n => n.classList && n.classList.contains(c)),
    addClass: c => { nodes.forEach(n => n.classList.add(c)); return w; },
    removeClass: c => { nodes.forEach(n => n.classList.remove(c)); return w; },
    toggleClass: (c, on) => { nodes.forEach(n => n.classList.toggle(c, on)); return w; },
    attr: (k, v) => { if (v === undefined) return nodes[0] && nodes[0].getAttribute(k); nodes.forEach(n => (v === null ? n.removeAttribute(k) : n.setAttribute(k, v))); return w; },
    find: s => $(nodes[0] ? nodes[0].querySelector(s) : null),
    children: () => ({ length: nodes[0] ? nodes[0].children.length : 0 }),
    val: v => { if (v === undefined) return nodes[0] ? nodes[0].value : ''; nodes.forEach(n => { n.value = v; }); return w; },
    focus: () => w, show: () => { nodes.forEach(n => { n.style.display = ''; }); return w; },
    hide: () => { nodes.forEach(n => { n.style.display = 'none'; }); return w; }
  };
  return w;
}
function trigger(evt, sel, target, extra = {}) {
  const e = Object.assign({ key: '', shiftKey: false, target, preventDefault() { this.prevented = true; } }, extra);
  (handlers[evt + '|' + sel] || []).forEach(fn => fn.call(target, e));
  return e;
}

const sent = [];
const shinyHandlers = {};
const timers = [];
const context = vm.createContext({
  $, jQuery: $, document, console, Date, Math, atob: s => Buffer.from(s, 'base64').toString('binary'),
  setTimeout: fn => { timers.push(fn); return timers.length; },
  clearTimeout: id => { if (id) timers[id - 1] = null; },
  TextDecoder, Uint8Array,
  MutationObserver: function (cb) { this.observe = (target, options) => observers.push({ cb, target, options, kuyruk: [] }); },
  Shiny: { setInputValue: (name, value) => sent.push({ name, value }), addCustomMessageHandler: (n, fn) => { shinyHandlers[n] = fn; } }
});
context.window = context;
vm.runInContext(pendingSource, context, { filename: 'chat_pending_message.js' });
vm.runInContext(source, context, { filename: 'input_handlers.js' });

function serverBubble(id, text) {
  const w = el('div', { id: 'message_wrapper_' + id });
  const b = w.appendChild(el('div', { class: 'message-bubble animate-fadeIn' }));
  const u = b.appendChild(el('div', { class: 'user-message' }));
  u.appendChild(el('div', { class: 'message-header' })).appendChild(el('div', { class: 'message-time' }));
  u.appendChild(el('div', { class: 'message-content', 'data-copy-b64': Buffer.from(text, 'utf8').toString('base64') }));
  chat.appendChild(w); // gözlemci yalnızca kayıtlı seçenekleri uygunsa bildirim alır
  return w;
}
const pending = () => all(chat, '.mergen-bekleyen-istem');
const visibleUserBubbles = () => all(chat, '.user-message').filter(n => {
  let p = n; while (p && p !== chat) { if (p.style && p.style.display === 'none') return false; p = p.parentNode; } return true;
});
const enter = text => { input.value = text; trigger('keyup', '#user_input, .chat-input, textarea[name="user_input"]', input, { key: 'Enter' }); };
const sendClick = text => { input.value = text; trigger('click', '#send_stop_btn', btn); };
const lastId = () => sent[sent.length - 1].value.client_id;
const result = (id, durum, mesajId) => shinyHandlers.mergenIstemSonucu(Object.assign({ client_id: id, durum }, mesajId ? { mesaj_id: mesajId } : {}));
const liveText = () => { const n = all(body, '.mergen-istem-canli-bolge')[0]; return n ? n.textContent : ''; };

(async () => {
// 0) Üretim gözlemcisi sohbet kabını childList + subtree ile izler.
assert.equal(observers.length, 1);
assert.equal(observers[0].target, chat);
assert.equal(observers[0].options.childList, true);
assert.equal(observers[0].options.subtree, true);

// 0b) Canlı bölge ilk gönderimden ÖNCE (boş) hazırdır; aynı görevde oluşturulup doldurulmaz.
assert.equal(all(body, '.mergen-istem-canli-bolge').length, 1, 'canlı bölge modül yüklenirken oluşturulmalı');
assert.equal(liveText(), '');

// 1) Enter: balon anında, istemci kimliğiyle gönderim; düğme erişilebilir bekleme durumunda.
enter('Merhaba dünya, çğış?');
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'send_prompt_from_js');
const id1 = sent[0].value.client_id;
assert.match(id1, /^[A-Za-z0-9_-]{1,64}$/);
assert.equal(pending().length, 1, 'bekleyen balon hemen çizilmeli');
assert.equal(pending()[0].querySelector('.message-content').textContent, 'Merhaba dünya, çğış?');
assert.equal(pending()[0].querySelector('.message-bubble').style.animation, 'none', 'bekleyen balon solma animasyonuyla gizlenmemeli');
assert.ok(welcome.classList.contains('hidden'), 'karşılama ekranı iyimser olarak gizlenmeli');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'));
assert.equal(btn.querySelector('i').className, 'fa-solid fa-spinner fa-spin', 'bekleme sırasında işlevsiz Durdur simgesi gösterilmemeli');
assert.equal(btn.getAttribute('aria-label'), 'İstem gönderiliyor');
assert.equal(btn.getAttribute('aria-disabled'), 'true');
assert.equal(liveText(), 'İstem gönderiliyor…', 'canlı bölge gönderimi duyurmalı');
assert.equal(input.value, '');

// 2) Bekleme sırasında ikinci gönderim engellenir; düğme tıklaması (durdurma modunda bile) yutulur.
enter('ikinci');
assert.equal(sent.length, 1, 'bekleyen istem varken ikinci istem gönderilmemeli');
assert.equal(input.value, 'ikinci', 'engellenen metin kaybolmamalı');
btn.classList.add('stop-mode');
let propagationStopped = false;
captureClick.forEach(fn => fn({ target: btn.querySelector('i'), preventDefault() {}, stopPropagation() { propagationStopped = true; } }));
assert.ok(propagationStopped, 'kabul bildirimi gelmeden Durdur tıklaması sunucuya gitmemeli');
btn.classList.remove('stop-mode');
input.value = '';

// 3) Asıl balon: bekleyen balon aynı geri çağrıda gizlenir (çift balon yok), karar kimlikle verilir.
const asil = serverBubble('901', 'Merhaba dünya, çğış?');
await teslim();
assert.equal(visibleUserBubbles().length, 1, 'çift kullanıcı balonu görünmemeli');
assert.ok(!asil.querySelector('.message-bubble').classList.contains('animate-fadeIn'), 'asıl balon solmadan görünmeli');
assert.equal(asil.querySelector('.message-bubble').style.animation, 'none');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), 'metin eşleşmesi tek başına isteği sonuçlandırmamalı');
result(id1, 'kabul', '901');
assert.equal(pending().length, 0, 'kabulde bekleyen balon kaldırılmalı');
assert.equal(liveText(), 'İstem gönderildi.', 'kabulde canlı bölge "gönderiliyor" durumunda kalmamalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'));
assert.equal(btn.querySelector('i').className, 'fa-solid fa-paper-plane');
assert.equal(btn.getAttribute('aria-label'), 'Mesajı gönder', 'erişilebilir ad geri gelmeli');
assert.equal(btn.getAttribute('title'), 'Gönder');
assert.equal(btn.getAttribute('aria-disabled'), null);

// 4) Ret: balon kalkar, metin girdiye geri yüklenir.
sendClick('reddedilecek istem');
assert.equal(sent.length, 2);
assert.equal(pending().length, 1);
result(lastId(), 'ret');
assert.equal(pending().length, 0);
assert.equal(input.value, 'reddedilecek istem');
assert.equal(btn.querySelector('i').className, 'fa-solid fa-paper-plane');
assert.match(liveText(), /gönderilemedi/);

// 5) Bekleme sırasında yazılan taslak varken ret: iki metin de korunur.
sendClick('ilk istem');
input.value = 'yeni taslak';
result(lastId(), 'ret');
assert.equal(input.value, 'ilk istem\nyeni taslak', 'reddedilen istem ve taslak birlikte korunmalı');
input.value = '';
// 5b) Reddedilen istem taslağın alt dizesi olsa da yutulmaz (istem "a", taslak "taslak").
sendClick('a');
input.value = 'taslak';
result(lastId(), 'ret');
assert.equal(input.value, 'a\ntaslak', 'alt dize eşleşmesi reddedilen istemi kaybettirmemeli');
input.value = '';

// 6) Kabul asıl balondan ÖNCE gelirse bekleyen balon görünür kalır; balon gelince kalkar.
sendClick('erken kabul');
const idErken = lastId();
result(idErken, 'kabul', '902');
assert.equal(pending().length, 1, 'asıl balon gelmeden bekleyen balon kaybolmamalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'kabulden sonra gönderim kilidi kalkmalı');
const asil902 = serverBubble('902', 'erken kabul');
await teslim();
assert.equal(pending().length, 0, 'kimlikli asıl balon gelince bekleyen balon kalkmalı');
assert.equal(asil902.querySelector('.message-bubble').style.animation, 'none');

// 7) Aynı metinli İLGİSİZ balon isteği sonuçlandırmaz; kabul doğru kimliği bekler.
sendClick('aynı metin');
const idAyni = lastId();
serverBubble('903', 'aynı metin');
await teslim();
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), 'ilgisiz balon kilidi açmamalı');
result(idAyni, 'kabul', '904');
assert.equal(pending().length, 1);
assert.equal(pending()[0].style.display, '', 'yanlış eşleşmede bekleyen balon yeniden görünmeli');
serverBubble('904', 'aynı metin');
await teslim();
assert.equal(pending().length, 0);

// 8) İlgisiz aynı metinli balondan sonra ret: metin yine geri yüklenir.
sendClick('tekrar');
serverBubble('905', 'tekrar');
await teslim();
result(lastId(), 'ret');
assert.equal(input.value, 'tekrar', 'ilgisiz balon reddedilen metni yutmamalı');
input.value = '';

// 9) Bağlantı kopması: sonucu gelmemiş istem geri yüklenir ve belirsizlik bildirilir.
sendClick('bağlantı kopacak');
(handlers['shiny:disconnected|'] || []).forEach(fn => fn());
assert.equal(pending().length, 0);
assert.equal(input.value, 'bağlantı kopacak');
assert.match(liveText(), /doğrulanamadı/);
input.value = '';
// 9b) Aynı metinli (ilgisiz olabilecek) balon kabul kanıtı değildir: sonuç
// gelmeden bağlantı koparsa istem yine kaybolmaz.
sendClick('ilgisiz balon sonrası kopma');
serverBubble('906', 'ilgisiz balon sonrası kopma');
await teslim();
(handlers['shiny:disconnected|'] || []).forEach(fn => fn());
assert.equal(pending().length, 0);
assert.equal(input.value, 'ilgisiz balon sonrası kopma', 'metin eşleşmesi bağlantı kopmasında istemi yutmamalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'));
input.value = '';

// 10) Kap başka bir akışla temizlenirse (Yeni Söyleşi) kilit kalkar ama geç gelen ret metni kaybettirmez.
sendClick('yanıtsız kalacak');
const idAyrilan = lastId();
assert.equal(pending().length, 1);
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'temizlenen kapta bekleme durumu kalmamalı');
assert.equal(input.value, '');
input.value = 'yeni söyleşide ilk istem';
const oncekiGonderim = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, oncekiGonderim + 1, 'kap temizlendikten sonra gönderim kilitlenmemeli');
result(idAyrilan, 'ret');
assert.equal(input.value, 'yanıtsız kalacak', 'gezinmeden sonra gelen ret metni geri yüklemeli');
assert.ok(welcome.classList.contains('hidden') || welcome.children.length === 0, 'gezinmeden sonra karşılama geri getirilmemeli');
result(lastId(), 'ret');
input.value = '';

// 11) Kabul edilen istemin asıl balonu gecikirse istem kaybolmaz: süre sonunda
// "gönderiliyor" durumundan çıkar, görünür kalır; asıl balon gelince kalkar.
sendClick('balonsuz kabul');
result(lastId(), 'kabul', '999');
assert.equal(pending().length, 1);
timers.splice(0).forEach(fn => fn && fn());
assert.equal(pending().length, 1, 'kabul edilmiş istem asıl balon gelmeden kaldırılmamalı');
assert.equal(pending()[0].getAttribute('aria-busy'), null, 'süre sonunda meşgul durumu kalkmalı');
assert.equal(pending()[0].querySelector('.message-time').textContent, '');
serverBubble('999', 'balonsuz kabul');
await teslim();
assert.equal(pending().length, 0, 'asıl balon gelince bekleyen balon kalkmalı');

// 11b) Bağlantı açıkken sonuç hiç gelmezse (kayıp olay) gönderim sonsuza dek
// kilitli kalmaz: süre sonunda kilit kalkar, metin belirsizlik bildirimiyle geri
// yüklenir ve istem OTOMATİK yeniden gönderilmez.
sendClick('kayıp olay');
const idKayip = lastId();
const kayipOncesi = sent.length;
timers.splice(0).forEach(fn => fn && fn());
assert.equal(pending().length, 0, 'zaman aşımında bekleyen balon kalkmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'zaman aşımında gönderim kilidi kalkmalı');
assert.equal(input.value, 'kayıp olay', 'zaman aşımında metin geri yüklenmeli');
assert.match(liveText(), /doğrulanamadı/);
assert.equal(sent.length, kayipOncesi, 'belirsiz istem otomatik yeniden gönderilmemeli');
// Geç gelen kabul: asıl balon gelmeden geri yüklenen istem girdiden kalkmaz
// (istem hiçbir anda görünmez olmaz); kimlikli asıl balon gelince kalkar.
result(idKayip, 'kabul', '1001');
assert.equal(input.value, 'kayıp olay', 'asıl balon yokken geç kabul girdideki istemi kaldırmamalı');
assert.equal(liveText(), 'Gecikmeli istem iletildi.');
serverBubble('1000', 'kayıp olay');   // aynı metinli ilgisiz balon karar vermez
await teslim();
assert.equal(input.value, 'kayıp olay', 'metin eşleşmesi geç kabulü uzlaştırmamalı');
serverBubble('1001', 'kayıp olay');
await teslim();
assert.equal(input.value, '', 'kimlikli asıl balon gelince geri yüklenen istem kalkmalı (ikinci gönderim olmaz)');
// Asıl balon geç kabulden ÖNCE DOM'daysa istem hemen kalkar.
sendClick('önce balon');
const idOnce = lastId();
timers.splice(0).forEach(fn => fn && fn());
assert.equal(input.value, 'önce balon');
serverBubble('1010', 'önce balon');
await teslim();
result(idOnce, 'kabul', '1010');
assert.equal(input.value, '', 'asıl balon varken geç kabul istemi hemen kaldırmalı');
// Taslak B varken zaman aşımı "A\nB" geri yükler; geç kabulde yalnızca A kalkar.
sendClick('istem A');
const idTaslak = lastId();
input.value = 'taslak B';
timers.splice(0).forEach(fn => fn && fn());
assert.equal(input.value, 'istem A\ntaslak B');
result(idTaslak, 'kabul', '1011');
assert.equal(input.value, 'istem A\ntaslak B', 'asıl balon gelmeden taslakla birlikte istem korunmalı');
serverBubble('1011', 'istem A');
await teslim();
assert.equal(input.value, 'taslak B', 'geç kabul yalnızca kabul edilen istemi kaldırmalı, taslağı korumalı');
// Geri yüklemeden sonra taslak düzenlenmişse (önek aynen duruyor) düzenleme korunur.
input.value = '';
sendClick('istem C');
const idDuzen = lastId();
input.value = 'taslak D';
timers.splice(0).forEach(fn => fn && fn());
input.value = 'istem C\ntaslak D ve ek';
result(idDuzen, 'kabul', '1012');
serverBubble('1012', 'istem C');
await teslim();
assert.equal(input.value, 'taslak D ve ek', 'taslağın sonraki düzenlemeleri korunmalı');
input.value = '';
// Kullanıcı istemi değiştirdiyse geç kabul girdiye dokunmaz; geç ret de metni çoğaltmaz.
sendClick('kayıp iki');
const idKayip2 = lastId();
timers.splice(0).forEach(fn => fn && fn());
input.value = 'kayıp iki düzenlendi';
result(idKayip2, 'kabul', '1002');
serverBubble('1002', 'kayıp iki');
await teslim();
assert.equal(input.value, 'kayıp iki düzenlendi', 'değiştirilmiş taslak korunmalı');
sendClick('kayıp üç');
const idKayip3 = lastId();
timers.splice(0).forEach(fn => fn && fn());
result(idKayip3, 'ret');
assert.equal(input.value, 'kayıp üç', 'geç ret metni ikinci kez eklememeli');
input.value = '';

// 11c) Ayrılmış eski istem (A) tamamlanınca hâlâ gönderilen yeni istemin (B)
// durumu "gönderildi" diye duyurulmaz.
sendClick('eski istem A');
const idA = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('yeni istem B');
const idB = lastId();
result(idA, 'kabul', '1003');
assert.equal(liveText(), 'İstem gönderiliyor…', 'B beklerken A kabulü durumu değiştirmemeli');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'));
result(idB, 'kabul', '1004');
assert.equal(liveText(), 'İstem gönderildi.');
timers.splice(0);
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();

// 12) Boş istem gönderilmez.
input.value = '   ';
const once = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, once);

console.log('chat_pending_bubble_regressions: OK');
})().catch(e => { console.error(e); process.exit(1); });
