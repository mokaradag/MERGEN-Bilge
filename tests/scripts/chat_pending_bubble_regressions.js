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
const inputListeners = [];
const beforeinputListeners = [];
// Kullanıcı yazması: değer değişir, imleç düzenlemenin sonunda kalır ve
// tarayıcıdaki gibi 'input' olayı yayılır (imleç verilmezse metnin sonundadır).
// girdiTuru verilirse olayın inputType alanı olur (ör. 'historyUndo').
const userType = (text, imlec, girdiTuru) => {
  input.value = text;
  input.selectionEnd = imlec === undefined ? text.length : imlec;
  inputListeners.forEach(fn => fn({ target: input, inputType: girdiTuru }));
};
// Seçim yapıp (beforeinput) seçimin yerine metin yapıştırma.
const seciliYapistir = (bas, son, metin) => {
  const eski = input.value;
  input.selectionStart = bas;
  input.selectionEnd = son;
  beforeinputListeners.forEach(fn => fn({ target: input }));
  userType(eski.slice(0, bas) + metin + eski.slice(son), bas + metin.length);
};
const document = {
  body, readyState: 'complete',
  getElementById: id => all(body, '#' + id)[0] || null,
  querySelector: s => all(body, s)[0] || null,
  querySelectorAll: s => all(body, s),
  createElement: tag => el(tag),
  addEventListener: (name, fn, capture) => {
    if (name === 'click' && capture) captureClick.push(fn);
    if (name === 'input') inputListeners.push(fn);
    if (name === 'beforeinput') beforeinputListeners.push(fn);
  }
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
// Sanal saat: zamanlayıcılar benzersiz kimlikle tutulur (kimlik yeniden
// kullanılmaz; eski kimliğin iptali yeni zamanlayıcıyı etkilemez). Süresi
// dolanlar bitiş sırasıyla çalışır ve her geri çağrıdan HEMEN önce hâlâ kayıtlı
// mı denetlenir: boşaltma sırasında başka bir geri çağrının iptal ettiği
// zamanlayıcı çalışmaz (tarayıcıdaki gibi).
const timers = new Map();
let sonrakiZamanlayici = 1;
let saat = 0;
const suresiDolanlariCalistir = sinir => {
  const sira = [...timers.entries()].filter(([, t]) => t.bitis <= sinir)
    .sort((a, b) => (a[1].bitis - b[1].bitis) || (a[0] - b[0]));
  for (const [id] of sira) {
    const t = timers.get(id);
    if (!t) continue;
    timers.delete(id);
    t.fn();
  }
};
const ilerlet = ms => { saat += ms; suresiDolanlariCalistir(saat); };
// Bekleyen tüm zamanlayıcıları (yalnızca o anda kayıtlı olanları) çalıştırır.
const tumZamanlayicilariCalistir = () => suresiDolanlariCalistir(Infinity);
// Bekleyen zamanlayıcıları çalıştırmadan atar.
const zamanlayicilariAt = () => timers.clear();
const context = vm.createContext({
  $, jQuery: $, document, console, Date, Math, atob: s => Buffer.from(s, 'base64').toString('binary'),
  setTimeout: (fn, ms) => { const id = sonrakiZamanlayici++; timers.set(id, { fn, bitis: saat + (ms || 0) }); return id; },
  clearTimeout: id => { timers.delete(id); },
  TextDecoder, Uint8Array,
  MutationObserver: function (cb) { this.observe = (target, options) => observers.push({ cb, target, options, kuyruk: [] }); },
  // Gerçek Shiny gibi: işleyici tam bir parametre bildirmezse kayıt hata verir.
  Shiny: { setInputValue: (name, value) => sent.push({ name, value }), addCustomMessageHandler: (n, fn) => {
    if (typeof fn !== 'function' || fn.length !== 1) throw new Error('handler must be a function that takes one argument: ' + n);
    shinyHandlers[n] = fn;
  } }
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
// Görünür bekleyen balonlar (zaman aşımındaki gizli görünüm çapası hariç).
const gorunurBekleyen = () => pending().filter(n => n.style.display !== 'none');
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
assert.equal(sent[0].value.text, 'Merhaba dünya, çğış?', 'Enter yazılan istemi göndermeli');
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
assert.ok(isInside(visibleUserBubbles()[0], asil), 'görünen tek balon sunucunun asıl balonu olmalı');
assert.ok(!asil.querySelector('.message-bubble').classList.contains('animate-fadeIn'), 'asıl balon solmadan görünmeli');
assert.equal(asil.querySelector('.message-bubble').style.animation, 'none');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), 'metin eşleşmesi tek başına isteği sonuçlandırmamalı');
result(id1, 'kabul', '901');
assert.equal(pending().length, 0, 'kabulde bekleyen balon kaldırılmalı');
assert.equal(visibleUserBubbles().length, 1);
assert.ok(isInside(visibleUserBubbles()[0], asil), 'kabulden sonra istem asıl balonda görünür kalmalı');
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
assert.equal(gorunurBekleyen().length, 1, 'asıl balon gelmeden kabul edilmiş balon GÖRÜNÜR kalmalı');
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
assert.equal(gorunurBekleyen().length, 1, 'yanlış eşleşmede bekleyen balon yeniden görünmeli');
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
ilerlet(3999);
assert.equal(pending()[0].getAttribute('aria-busy'), 'true', '4 sn dolmadan meşgul durumu sürmeli');
ilerlet(1);
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
// Süre dolmadan (59,999 sn) istem bekler; tam 60 sn'de zaman aşımı olur.
ilerlet(59999);
assert.equal(pending().length, 1, 'sonuç süresi dolmadan bekleyen balon kalmalı');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), 'süre dolmadan gönderim kilitli kalmalı');
assert.equal(input.value, '', 'süre dolmadan metin geri yüklenmemeli');
ilerlet(1);
zamanlayicilariAt();
assert.equal(gorunurBekleyen().length, 0, 'zaman aşımında bekleyen balon görünmemeli');
assert.equal(pending().length, 1, 'zaman aşımında gizli görünüm çapası kapta kalmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'zaman aşımında gönderim kilidi kalkmalı');
assert.equal(input.value, 'kayıp olay', 'zaman aşımında metin geri yüklenmeli');
assert.match(liveText(), /doğrulanamadı/);
assert.equal(sent.length, kayipOncesi, 'belirsiz istem otomatik yeniden gönderilmemeli');
// Geç gelen kabul: onaylanan istem girdiden HEMEN kalkar (yeni istek
// kimliğiyle yeniden gönderilemez); görünüm değişmediği için asıl balon
// gelene dek kabul edilmiş balon olarak görünür kalır.
result(idKayip, 'kabul', '1001');
assert.equal(input.value, '', 'geç kabul onaylanan istemi girdiden hemen kaldırmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'geç kabul gönderimi kilitlememeli');
assert.equal(liveText(), 'Gecikmeli istem iletildi.');
assert.equal(gorunurBekleyen().length, 1, 'onaylanan istem asıl balon gelene dek görünür kalmalı');
assert.equal(gorunurBekleyen()[0].getAttribute('aria-busy'), null, 'kabul edilmiş balon meşgul görünmemeli');
serverBubble('1000', 'kayıp olay');   // aynı metinli ilgisiz balon karar vermez
await teslim();
assert.equal(gorunurBekleyen().length, 1, 'metin eşleşmesi kabul edilmiş balonu kaldırmamalı');
serverBubble('1001', 'kayıp olay');
await teslim();
assert.equal(pending().length, 0, 'kimlikli asıl balon gelince kabul edilmiş balon kalkmalı');
assert.equal(input.value, '', 'asıl balon geldikten sonra girdi boş kalmalı (ikinci gönderim olmaz)');
// Asıl balon geç kabulden ÖNCE DOM'daysa istem hemen kalkar.
sendClick('önce balon');
const idOnce = lastId();
tumZamanlayicilariCalistir();
assert.equal(input.value, 'önce balon');
serverBubble('1010', 'önce balon');
await teslim();
result(idOnce, 'kabul', '1010');
assert.equal(input.value, '', 'asıl balon varken geç kabul istemi hemen kaldırmalı');
// Taslak B varken zaman aşımı "A\nB" geri yükler; geç kabulde yalnızca A
// (asıl balonu beklemeden) kalkar, taslak gönderilebilir kalır.
sendClick('istem A');
const idTaslak = lastId();
input.value = 'taslak B';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'istem A\ntaslak B');
result(idTaslak, 'kabul', '1011');
assert.equal(input.value, 'taslak B', 'geç kabul yalnızca kabul edilen istemi kaldırmalı, taslağı korumalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'taslak gönderilebilir kalmalı');
serverBubble('1011', 'istem A');
await teslim();
assert.equal(input.value, 'taslak B', 'asıl balon geldikten sonra da taslak aynen kalmalı');
// Geri yüklemeden sonra taslak düzenlenmişse (önek aynen duruyor) düzenleme korunur.
input.value = '';
sendClick('istem C');
const idDuzen = lastId();
input.value = 'taslak D';
tumZamanlayicilariCalistir();
userType('istem C\ntaslak D ve ek');
result(idDuzen, 'kabul', '1012');
serverBubble('1012', 'istem C');
await teslim();
assert.equal(input.value, 'taslak D ve ek', 'taslağın sonraki düzenlemeleri korunmalı');
input.value = '';
// Kullanıcı istemi değiştirdiyse geç kabul girdiye dokunmaz; geç ret de metni çoğaltmaz.
sendClick('kayıp iki');
const idKayip2 = lastId();
tumZamanlayicilariCalistir();
input.value = 'kayıp iki düzenlendi';
result(idKayip2, 'kabul', '1002');
serverBubble('1002', 'kayıp iki');
await teslim();
assert.equal(input.value, 'kayıp iki düzenlendi', 'değiştirilmiş taslak korunmalı');
sendClick('kayıp üç');
const idKayip3 = lastId();
tumZamanlayicilariCalistir();
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
zamanlayicilariAt();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();

// 11d) Örtüşen geri yüklemeler bağımsız uzlaştırılır: ayrılan A ve sonraki B,
// taslak D varken zaman aşımına uğrar ("B\nA\nD"). A'nın asıl balonu önce gelse
// de yalnızca A'nın iç bölümü kalkar; B de kalkınca yalnızca taslak D kalır.
input.value = '';
sendClick('örtüşen A');
const idOrtusenA = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('örtüşen B');
const idOrtusenB = lastId();
input.value = 'taslak D';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'örtüşen B\nörtüşen A\ntaslak D');
result(idOrtusenA, 'kabul', '1020');
serverBubble('1020', 'örtüşen A');
await teslim();
assert.equal(input.value, 'örtüşen B\ntaslak D', 'yalnızca kabul edilen iç bölüm kalkmalı; B ve taslak korunmalı');
result(idOrtusenB, 'kabul', '1021');
serverBubble('1021', 'örtüşen B');
await teslim();
assert.equal(input.value, 'taslak D', 'kabul edilen örtüşen istemler girdide kalmamalı, taslak korunmalı');
zamanlayicilariAt();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
input.value = '';

// 11e) Aynı metinli iki istem (A ayrıldı, B aynı metinle gönderildi) boş taslakta
// zaman aşımına uğrar: her istem kendi bölümünü alır ("X\nX"); metin eşitliği
// ortak sahiplik sayılmaz. A'nın geç kabulü yalnızca kendi bölümünü kaldırır;
// B geç "ret" alırsa metni yeniden gönderilebilir kalır.
const ayniMetinIkiIstem = async (taslak) => {
  input.value = '';
  sendClick('aynı metin');
  const a = lastId();
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
  sendClick('aynı metin');
  const b = lastId();
  if (taslak) input.value = taslak;
  tumZamanlayicilariCalistir();
  assert.equal(input.value, 'aynı metin\naynı metin' + (taslak ? '\n' + taslak : ''), 'özdeş istemler ayrı bölümlerle geri yüklenmeli');
  return [a, b];
};
const temizle = async () => {
  zamanlayicilariAt();
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
  input.value = '';
};
let [idAyniA, idAyniB] = await ayniMetinIkiIstem();
result(idAyniA, 'kabul', '1030');
serverBubble('1030', 'aynı metin');
await teslim();
assert.equal(input.value, 'aynı metin', "A'nın kabulü B'nin bölümünü silmemeli");
result(idAyniB, 'ret');
assert.equal(input.value, 'aynı metin', 'geç ret alan B yeniden gönderilebilir kalmalı');
await temizle();
// Ters sıra: önce B geç ret alır (sahipliğini korur), sonra A kabul edilir.
[idAyniA, idAyniB] = await ayniMetinIkiIstem();
result(idAyniB, 'ret');
result(idAyniA, 'kabul', '1033');
serverBubble('1033', 'aynı metin');
await teslim();
assert.equal(input.value, 'aynı metin', "reddedilen B'nin metni A'nın kabulünde kaybolmamalı");
await temizle();
// İkisi de kabul edilirse her bölüm kendi kabulünde kalkar.
[idAyniA, idAyniB] = await ayniMetinIkiIstem();
result(idAyniA, 'kabul', '1031');
serverBubble('1031', 'aynı metin');
await teslim();
result(idAyniB, 'kabul', '1032');
serverBubble('1032', 'aynı metin');
await teslim();
assert.equal(input.value, '', 'iki kabulden sonra geri yüklemeler girdide kalmamalı');
await temizle();
// Taslak D ile özdeş iki istem ("X\nX\nD"): A kabul -> "X\nD", B kabul -> "D".
[idAyniA, idAyniB] = await ayniMetinIkiIstem('taslak D');
result(idAyniA, 'kabul', '1034');
serverBubble('1034', 'aynı metin');
await teslim();
assert.equal(input.value, 'aynı metin\ntaslak D', "A'nın kabulü yalnızca kendi bölümünü kaldırmalı");
result(idAyniB, 'kabul', '1035');
serverBubble('1035', 'aynı metin');
await teslim();
assert.equal(input.value, 'taslak D', 'kabul edilen özdeş istemler kalkmalı, taslak korunmalı');
await temizle();

// 11e2) Bağımsız yazılmış özdeş taslak sahiplenilmez: A gönderilir, kullanıcı
// aynı metni yeniden yazar, A zaman aşımına uğrar; geç kabul taslağı silmez.
sendClick('özdeş taslak');
const idOzdes = lastId();
input.value = 'özdeş taslak';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'özdeş taslak', 'özdeş taslak yinelenmemeli');
result(idOzdes, 'kabul', '1036');
serverBubble('1036', 'özdeş taslak');
await teslim();
assert.equal(input.value, 'özdeş taslak', 'bağımsız yazılmış taslak geç kabulde silinmemeli');
await temizle();

// 11e3) "B\nA\nD" iken A kabul edilip B geç ret alır (her iki sırada da):
// yalnızca kabul edilen A kalkar; B ve taslak D kalır, B yeniden gönderilirse A
// tekrar gitmez.
const ortusenIkiIstem = async () => {
  sendClick('sıra A');
  const a = lastId();
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
  sendClick('sıra B');
  const b = lastId();
  input.value = 'taslak D';
  tumZamanlayicilariCalistir();
  assert.equal(input.value, 'sıra B\nsıra A\ntaslak D');
  return [a, b];
};
let [idSiraA, idSiraB] = await ortusenIkiIstem();
result(idSiraA, 'kabul', '1037');
serverBubble('1037', 'sıra A');
await teslim();
result(idSiraB, 'ret');
assert.equal(input.value, 'sıra B\ntaslak D', 'kabul sonra ret: yalnızca A kalkmalı');
// Yeniden gönderim dokunulmamış girdiyi gönderir: A tekrar gitmez.
const yenidenGonder = () => {
  const once = sent.length;
  trigger('click', '#send_stop_btn', btn);
  assert.equal(sent.length, once + 1, 'yeniden gönderim tek istek göndermeli');
  assert.equal(sent[sent.length - 1].value.text, 'sıra B\ntaslak D', 'yeniden gönderim yalnızca B ve taslağı taşımalı');
  result(lastId(), 'ret');
};
yenidenGonder();
await temizle();
[idSiraA, idSiraB] = await ortusenIkiIstem();
result(idSiraB, 'ret');
result(idSiraA, 'kabul', '1038');
serverBubble('1038', 'sıra A');
await teslim();
assert.equal(input.value, 'sıra B\ntaslak D', 'ret sonra kabul: yalnızca A kalkmalı');
yenidenGonder();
await temizle();

// 11e4) Kullanıcı geri yüklenen bölümü silip aynı metni yeniden yazarsa
// sahiplik düşmüştür: geç kabul yeniden yazılan metne dokunmaz.
sendClick('silinip yazılan');
const idSilinen = lastId();
tumZamanlayicilariCalistir();
userType('');
userType('silinip yazılan');
result(idSilinen, 'kabul', '1039');
serverBubble('1039', 'silinip yazılan');
await teslim();
assert.equal(input.value, 'silinip yazılan', 'yeniden yazılan metin sahiplenilmemeli');
await temizle();

// 11f) Geri yüklenen metin yeniden gönderilip yeni taslak yazıldıysa geç kabul
// yeni taslağa dokunmaz (geri yükleme önceki gönderim nesline aittir).
sendClick('istem E');
const idNesil = lastId();
input.value = 'eski';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'istem E\neski');
sendClick(input.value);                // geri yüklenen metin gönderimle tüketilir
const idTuketen = lastId();
input.value = 'istem E\nyeni';
result(idNesil, 'kabul', '1040');
serverBubble('1040', 'istem E');
await teslim();
assert.equal(input.value, 'istem E\nyeni', 'tüketilmiş geri yükleme yeni taslağı değiştirmemeli');
result(idTuketen, 'kabul', '1041');
zamanlayicilariAt();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
input.value = '';

// 11g) Oturum sahibi değişince önceki sahibin bekleyen istemi metni geri
// yüklenmeden düşer, kilit kalkar; girdi KAPALI-BAŞARISIZ olarak tümüyle
// temizlenir (önceki kimlikle yazılmış taslak dahil) ve sonradan gelen sonuç
// girdiye bir şey yazmaz.
assert.equal(typeof shinyHandlers.mergenBekleyenIstemSifirla, 'function');
sendClick('A sahibinin istemi');
const idSahipA = lastId();
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(pending().length, 0, 'sahip değişince bekleyen balon kalkmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'sahip değişince gönderim kilidi kalkmalı');
tumZamanlayicilariCalistir();
assert.equal(input.value, '', 'önceki sahibin istemi zaman aşımında geri yüklenmemeli');
result(idSahipA, 'ret');
assert.equal(input.value, '', 'önceki sahibin geç reddi metni geri yüklememeli');
sendClick('A zaman aşımı');
const idSahipA2 = lastId();
input.value = 'B taslağı';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'A zaman aşımı\nB taslağı');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'sahip değişince girdi (geri yükleme ve taslak) tümüyle temizlenmeli');
input.value = 'yeni sahip taslağı';
result(idSahipA2, 'kabul', '1050');
serverBubble('1050', 'A zaman aşımı');
await teslim();
assert.equal(input.value, 'yeni sahip taslağı', 'önceki sahibin geç kabulü yeni sahibin girdisine dokunmamalı');
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
input.value = '';
// 11h) Doğrudan ret ve bağlantı kopmasıyla geri yüklenen metin sahip
// sıfırlamasında girdiden kalkar (girdi tümüyle temizlenir).
sendClick('A reddedilen');
const idSahipRet = lastId();
input.value = 'taslak';
result(idSahipRet, 'ret');
assert.equal(input.value, 'A reddedilen\ntaslak');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'reddedilen istem ve taslak sahip değişince kalkmalı');
sendClick('A kopan');
input.value = 'taslak';
(handlers['shiny:disconnected|'] || []).forEach(fn => fn());
assert.equal(input.value, 'A kopan\ntaslak');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'kopma sonrası geri yüklenen istem sahip değişince kalkmalı');
sendClick('A yalnız ret');
const idYalnizRet = lastId();
result(idYalnizRet, 'ret');
assert.equal(input.value, 'A yalnız ret');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'reddedilen istemin geri yüklenen metni sahip değişince kalkmalı');
zamanlayicilariAt();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
input.value = '';


// 11i) Özdeş iki bölümden ÜSTTEKİ (B) silinir: kalan bölüm A'ya aittir; A'nın
// geç kabulü yalnızca taslağı bırakır. Alttaki (A) silinirse A kabulü dokunmaz.
[idAyniA, idAyniB] = await ayniMetinIkiIstem('taslak D');
userType('aynı metin\ntaslak D', 0);
result(idAyniA, 'kabul', '1060');
serverBubble('1060', 'aynı metin');
await teslim();
assert.equal(input.value, 'taslak D', "üstteki özdeş bölüm silinince A'nın kabulü yalnızca taslağı bırakmalı");
result(idAyniB, 'ret');
assert.equal(input.value, 'taslak D');
await temizle();
[idAyniA, idAyniB] = await ayniMetinIkiIstem('taslak D');
userType('aynı metin\ntaslak D', 'aynı metin\n'.length);
result(idAyniA, 'kabul', '1061');
serverBubble('1061', 'aynı metin');
await teslim();
assert.equal(input.value, 'aynı metin\ntaslak D', "silinen A'nın kabulü B'nin bölümünü kaldırmamalı");
result(idAyniB, 'kabul', '1062');
serverBubble('1062', 'aynı metin');
await teslim();
assert.equal(input.value, 'taslak D');
await temizle();

// 11j) Boş girdiye geri yüklenen istemin altına ayrı satırda taslak eklenir:
// istemin sahipliği korunur, geç kabulde yalnızca taslak kalır.
sendClick('son bölüm');
const idSonBolum = lastId();
tumZamanlayicilariCalistir();
assert.equal(input.value, 'son bölüm');
userType('son bölüm\n');
userType('son bölüm\ntaslak');
result(idSonBolum, 'kabul', '1063');
serverBubble('1063', 'son bölüm');
await teslim();
assert.equal(input.value, 'taslak', 'ayrı satırdaki taslak kabul edilen istemi girdide bırakmamalı');
await temizle();

// 11k) Escape girdiyi temizlerse sahiplik düşer: aynı metin yapıştırılsa da geç
// kabul yeni taslağı silmez.
sendClick('escape istemi');
const idEscape = lastId();
tumZamanlayicilariCalistir();
assert.equal(input.value, 'escape istemi');
trigger('keyup', '#user_input, .chat-input, textarea[name="user_input"]', input, { key: 'Escape' });
assert.equal(input.value, '');
userType('escape istemi');
result(idEscape, 'kabul', '1064');
serverBubble('1064', 'escape istemi');
await teslim();
assert.equal(input.value, 'escape istemi', 'Escape sonrası yapıştırılan özdeş taslak silinmemeli');
await temizle();

// 11l) Kullanıcının düzenlediği geri yükleme bölümü de sahip sıfırlamasında kalkar.
sendClick('gizli istem');
const idGizli = lastId();
input.value = 'taslak';
result(idGizli, 'ret');
assert.equal(input.value, 'gizli istem\ntaslak');
userType('gizli istem düzeltildi\ntaslak', 'gizli istem düzeltildi'.length);
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'düzenlenmiş önceki sahip istemi sahip değişince kalkmalı');
await temizle();

// 11m) 16'dan fazla geri yükleme bölümü: hiçbirinin sahipliği düşmez, sahip
// sıfırlaması hepsini kaldırır.
const cokluKimlikler = [];
for (let i = 1; i <= 17; i++) {
  sendClick('çoklu ret ' + i);
  cokluKimlikler.push(lastId());
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
}
input.value = 'taslak';
cokluKimlikler.forEach(id => result(id, 'ret'));
assert.equal(input.value.split('\n').length, 18);
assert.ok(input.value.startsWith('çoklu ret 17\n') && input.value.endsWith('çoklu ret 1\ntaslak'));
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'en eski geri yükleme de sahip değişince kalkmalı');
await temizle();

// 11n) Ayrılmış eski istem (A) reddedilirken yeni istem (B) gönderiliyorsa
// bildirim önceki isteme ait olduğunu söyler ve B'nin gönderim durumu sürer.
sendClick('eski ret A');
const idEskiRet = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('yeni B');
const idYeniB = lastId();
result(idEskiRet, 'ret');
assert.match(liveText(), /^Önceki istem: /);
assert.match(liveText(), /Yeni istem gönderiliyor…$/);
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), "B'nin gönderim kilidi sürmeli");
result(idYeniB, 'ret');
assert.equal(liveText(), 'İstem gönderilemedi; metin giriş alanına geri yüklendi.', 'tek bekleyen istemde olağan bildirim korunmalı');
await temizle();

// 11o) Yalnız dosya istemi (metin yok) reddedilir: "metin geri yüklendi"
// denmez; ek temizlendiyse yeniden eklenmesi istenir.
const ekAlani = all(body, '#file_prompt_indicator_ui')[0];
ekAlani.appendChild(el('div', { class: 'file-chip' }));
input.value = '';
trigger('click', '#send_stop_btn', btn);
const idDosya = lastId();
assert.equal(sent[sent.length - 1].value.text, '');
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
result(idDosya, 'ret');
assert.equal(input.value, '');
assert.doesNotMatch(liveText(), /metin giriş alanına geri yüklendi/);
assert.match(liveText(), /dosyayı yeniden ekleyip/);
await temizle();

// 11p) 10 zaman aşımına uğramış istemin tümü girdide dururken ilkinin ilişkisi
// düşmez; geç kabul gelince ilk istem (asıl balonu beklemeden) girdiden kalkar.
// Görünüm her istemden sonra değiştiği için kabul edilmiş balon çizilmez.
const zaKimlikler = [];
for (let i = 1; i <= 10; i++) {
  sendClick('za istem ' + i);
  zaKimlikler.push(lastId());
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
}
ilerlet(60000);
// Satırlar birebir karşılaştırılır ("za istem 1" alt dizesi "za istem 10" ile karışmaz).
const zaSatirlari = n => Array.from({ length: n }, (_, i) => 'za istem ' + (10 - i));
assert.deepEqual(input.value.split('\n'), zaSatirlari(10), 'on zaman aşımı metni girdide birebir olmalı');
result(zaKimlikler[0], 'kabul', 'msg_za_1');
assert.deepEqual(input.value.split('\n'), zaSatirlari(9), 'yalnızca ilk istem geç kabulle kaldırılmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'geç kabul gönderimi kilitlememeli');
assert.equal(gorunurBekleyen().length, 0, 'değişen görünüme kabul edilmiş balon çizilmemeli');
await temizle();

// 11q) Tüm girdi seçilip (beforeinput) değiştirildiğinde eski geri yükleme
// sahipliği düşer: geç kabul yeni taslağı silmez (metin eşitliği sahiplik
// kanıtı değildir). Sahip sıfırlaması ise kapalı-başarısızdır: girdiyi tümüyle temizler.
sendClick('eski A');
const idTamDegisim = lastId();
result(idTamDegisim, 'ret');
assert.equal(input.value, 'eski A');
input.selectionStart = 0;
input.selectionEnd = input.value.length;
beforeinputListeners.forEach(fn => fn({ target: input }));
userType('yeni yapıştırılan taslak');
result(idTamDegisim, 'kabul', 'msg_tam_degisim');
assert.equal(input.value, 'yeni yapıştırılan taslak', 'tüm girdi değişimi sonrası yeni taslak geç kabulde korunmalı');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'sahip sıfırlaması girdiyi tümüyle temizlemeli');
assert.equal(liveText(), '', 'sahip sıfırlamasında canlı bölge temizlenmeli');
await temizle();
sendClick('eski B');
const idEskiB = lastId();
ilerlet(60000);
input.selectionStart = 0;
input.selectionEnd = input.value.length;
beforeinputListeners.forEach(fn => fn({ target: input }));
userType('eski B\nyeni yapıştırılan taslak');
result(idEskiB, 'kabul', 'msg_eski_b');
assert.equal(input.value, 'eski B\nyeni yapıştırılan taslak', 'bağımsız yazılan özdeş metin geç kabulde korunmalı');
await temizle();

// 11r) Yalnız dosya isteminde başka bir dosya seçiliyse eski dosya seçiliymiş
// gibi duyurulmaz; doğrulama istenir. Aynı adlı yeni dosyada da doğrulama istenir.
const chipA = el('div', { class: 'file-chip' });
chipA.textContent = 'A.pdf';
ekAlani.appendChild(chipA);
input.value = '';
trigger('click', '#send_stop_btn', btn);
const idDosyaDegisti = lastId();
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
const chipB = el('div', { class: 'file-chip' });
chipB.textContent = 'B.pdf';
ekAlani.appendChild(chipB);
result(idDosyaDegisti, 'ret');
assert.match(liveText(), /değişmiş olabilir/);
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
const chipA2 = el('div', { class: 'file-chip' });
chipA2.textContent = 'A.pdf';
ekAlani.appendChild(chipA2);
input.value = '';
trigger('click', '#send_stop_btn', btn);
const idAyniAd = lastId();
// İstek başladıktan sonra aynı adlı YENİ bir dosya seçilir.
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
const chipA3 = el('div', { class: 'file-chip' });
chipA3.textContent = 'A.pdf';
ekAlani.appendChild(chipA3);
result(idAyniAd, 'ret');
assert.match(liveText(), /kontrol edip tekrar deneyin/, 'aynı dosya adı özgün dosya kanıtı sayılmamalı');
assert.doesNotMatch(liveText(), /hâlâ seçili/);
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
await temizle();

// 11s) Ayırıcı sınırının her iki yanına yeni satır eklendiğinde ilgisiz taslak
// geri yüklenen isteme katılmaz; geç kabul B\nD bırakır.
for (const senaryo of ['sonra', 'once']) {
  for (const temizlemeTuru of ['gecKabul']) {
    sendClick('A');
    const idSinir = lastId();
    userType('D');
    ilerlet(60000);
    assert.equal(input.value, 'A\nD');
    if (senaryo === 'sonra') {
      // A'dan hemen sonra (imleç 1 -> 3) \nB yapıştırılır -> A\nB\nD
      userType('A\nB\nD', 3);
    } else {
      // \n sonrasına, D'den önce (imleç 2 -> 4) B\n yapıştırılır -> A\nB\nD
      userType('A\nB\nD', 4);
    }
    if (temizlemeTuru === 'gecKabul') {
      result(idSinir, 'kabul', 'msg_sinir_' + senaryo);
      const dugum = el('div', { id: 'message_wrapper_msg_sinir_' + senaryo });
      chat.appendChild(dugum);
      await teslim();
    } else {
      shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
    }
    assert.equal(input.value, 'B\nD', senaryo + '/' + temizlemeTuru + ' sonrasında B\\nD kalmalı');
    await temizle();
  }
}

// 11t) Geç kabul kilit üretmez ve onaylanan istem metni sonraki gönderime
// karışmaz: asıl balon hiç gelmese de (süre dolsa da) yeni gönderim yalnızca
// taslağı taşır. Düzenlenmiş bölüm kullanıcının taslağı olarak kalır.
sendClick('onaylanan A');
const idOnayA = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'onaylanan A\nD');
result(idOnayA, 'kabul', 'msg_onay_a');
assert.equal(input.value, 'D', 'onaylanan istem girdiden hemen kalkmalı');
ilerlet(4000);
const onayOncesi = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, onayOncesi + 1, 'taslak gönderilebilmeli');
assert.equal(sent[sent.length - 1].value.text, 'D', 'onaylanan istem yeni gönderime karışmamalı');
result(lastId(), 'kabul', 'msg_onay_d');
await temizle();

sendClick('düzenlenecek istem');
const idDuzenKabul = lastId();
ilerlet(60000);
userType('düzenlenecek istem düzenlendi');
result(idDuzenKabul, 'kabul', 'msg_duzen_kabul');
assert.equal(input.value, 'düzenlenecek istem düzenlendi', 'düzenlenmiş bölüm kullanıcının taslağı olarak kalmalı');
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'));
await temizle();

// 11u) Tüm girdi değişiminden sonra Geri Al ile dönen (artık izlenmeyen)
// önceki sahip istemi de sahip sıfırlamasında girdiden kalkar (girdi tümüyle
// temizlenir) ve sıfırlamadan sonra Geri Al/Yinele engellenir.
sendClick('gizli A istemi');
const idGeriAl = lastId();
result(idGeriAl, 'ret');
assert.equal(input.value, 'gizli A istemi');
input.selectionStart = 0;
input.selectionEnd = input.value.length;
beforeinputListeners.forEach(fn => fn({ target: input }));
userType('yeni metin');
userType('gizli A istemi', undefined, 'historyUndo');   // Geri Al
userType('gizli A istemi\nB taslağı');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'Geri Al ile dönen önceki sahip istemi sıfırlamada kalkmalı');
for (const tur of ['historyUndo', 'historyRedo']) {
  let engellendi = false;
  beforeinputListeners.forEach(fn => fn({ target: input, inputType: tur, preventDefault: () => { engellendi = true; } }));
  assert.ok(engellendi, tur + ' sahip değişiminden sonra engellenmeli (yerel geçmiş önceki metni taşır)');
}
let yazimEngellendi = false;
beforeinputListeners.forEach(fn => fn({ target: input, inputType: 'insertText', preventDefault: () => { yazimEngellendi = true; } }));
assert.ok(!yazimEngellendi, 'olağan yazım engellenmemeli');
await temizle();

// 11v) Seçili bölümün üzerine yapıştırma seçime göre konumlanır: geri
// yüklenen A seçilip "A\nB\n" yapıştırılırsa yeni A sahiplenilmez; geç kabul
// yapıştırılan metni silmez. Aynı metnin seçim üzerine yapıştırılması da
// (değer değişmese bile) sahipliği düşürür.
sendClick('A');
const idSecim = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'A\nD');
seciliYapistir(0, 2, 'A\nB\n');
assert.equal(input.value, 'A\nB\nD');
result(idSecim, 'kabul', 'msg_secim');
assert.equal(input.value, 'A\nB\nD', 'seçimle değiştirilen bölümün yeni metni geç kabulde silinmemeli');
await temizle();

sendClick('aynı yapıştırma');
const idAyniYapistir = lastId();
ilerlet(60000);
assert.equal(input.value, 'aynı yapıştırma');
seciliYapistir(0, input.value.length, 'aynı yapıştırma');
result(idAyniYapistir, 'kabul', 'msg_ayni_yapistir');
assert.equal(input.value, 'aynı yapıştırma', 'tüm seçim üzerine aynı metin yapıştırma sahipliği düşürmeli');
await temizle();

// 11v2) Seçim geri yüklenen bölümü TAMAMEN kapsayıp taslağa taşarsa yazılan
// metin sahiplenilmez: geç kabul yazılanı silmez.
for (const temizleme of ['gecKabul']) {
  sendClick('A');
  const idTasan = lastId();
  userType('DX');
  ilerlet(60000);
  assert.equal(input.value, 'A\nDX');
  seciliYapistir(0, 3, 'B');                 // "A\nD" seçilip B yazılır -> "BX"
  assert.equal(input.value, 'BX');
  result(idTasan, 'kabul', 'msg_tasan');
  assert.equal(input.value, 'BX', temizleme + ': taşan seçimle yazılan metin korunmalı');
  await temizle();
}

// 11w) Silinen bölüm yalnızca Geri Al ile aynı konuma dönerse sahipliği geri
// gelir: geç kabul onu kaldırır (yeniden gönderilmez). Elle yeniden yazılan
// aynı metin sahiplenilmez.
sendClick('A geri al');
const idGeriAl2 = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'A geri al\nD');
userType('D', 0);                                   // A ve ayırıcı silinir
userType('A geri al\nD', 9, 'historyUndo');        // Geri Al
result(idGeriAl2, 'kabul', 'msg_geri_al2');
assert.equal(input.value, 'D', 'Geri Al ile dönen onaylanmış istem girdiden kalkmalı');
await temizle();

sendClick('A elle');
const idElle = lastId();
userType('D');
ilerlet(60000);
userType('D', 0);
userType('A elle\nD', 6);                           // bağımsız yeniden yazım
result(idElle, 'kabul', 'msg_elle');
assert.equal(input.value, 'A elle\nD', 'elle yeniden yazılan metin sahiplenilmemeli');
await temizle();

// 11x) Teslim edilmeden eklenip kaldırılan kimlikli düğüm kabul edilmiş
// balonu kaldırmaz; bağlı balon gelince kalkar.
sendClick('kopuk düğüm');
const idKopuk = lastId();
result(idKopuk, 'kabul', 'msg_kopuk');
assert.equal(gorunurBekleyen().length, 1);
// Tam bir asıl balon eklenip teslimden önce kaldırılır (tek fark bağlı olmaması).
const kopuk = serverBubble('msg_kopuk', 'kopuk düğüm');
chat.removeChild(kopuk);
await teslim();
assert.equal(gorunurBekleyen().length, 1, 'kopmuş eşleşme kabul edilmiş balonu kaldırmamalı');
serverBubble('msg_kopuk', 'kopuk düğüm');
await teslim();
assert.equal(pending().length, 0, 'bağlı asıl balon gelince kabul edilmiş balon kalkmalı');
await temizle();

// 11y) Metin + dosya istemi reddedildiğinde ek kaldırıldıysa/değiştiyse
// duyuru bunu söyler; yalnız metin isteminde ek uyarısı yoktur.
const chipM = el('div', { class: 'file-chip' });
chipM.textContent = 'M.pdf';
ekAlani.appendChild(chipM);
sendClick('dosyalı metin');
const idDosyaliMetin = lastId();
ekAlani.children.slice().forEach(c => ekAlani.removeChild(c));
result(idDosyaliMetin, 'ret');
assert.equal(input.value, 'dosyalı metin');
assert.match(liveText(), /artık seçili değil/, 'kaldırılan ek duyurulmalı');
await temizle();
sendClick('yalnız metin');
result(lastId(), 'ret');
assert.doesNotMatch(liveText(), /dosya/, 'yalnız metin isteminde ek uyarısı olmamalı');
await temizle();

// 11z) Sahip sıfırlaması yeni nesli bildirir; sonraki istemler bu nesli taşır.
assert.equal(sent[sent.length - 1].value.sahip_nesli >= 0, true);
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti', nesil: 7 });
sendClick('yeni sahip istemi');
assert.equal(sent[sent.length - 1].value.sahip_nesli, 7, 'istem güncel sahip neslini taşımalı');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti', nesil: 3 });
const ikinciOncesi = sent.length;
sendClick('ikinci istem');
assert.equal(sent.length, ikinciOncesi + 1, 'ikinci tıklama yeni bir istem göndermeli');
assert.equal(sent[sent.length - 1].value.sahip_nesli, 7, 'nesil geriye gitmemeli');
result(lastId(), 'kabul', 'msg_ikinci_istem');
await temizle();

// 11aa) Kilit açılırken sunucunun bu arada koyduğu düğme etiketi ezilmez.
sendClick('etiket');
const idEtiket = lastId();
btn.setAttribute('title', 'Sunucu etiketi');
btn.setAttribute('aria-label', 'Sunucu erişilebilir adı');
result(idEtiket, 'ret');
assert.equal(btn.getAttribute('title'), 'Sunucu etiketi', 'sunucunun etiketi korunmalı');
assert.equal(btn.getAttribute('aria-label'), 'Sunucu erişilebilir adı');
btn.setAttribute('title', 'Gönder');
btn.setAttribute('aria-label', 'Mesajı gönder');
await temizle();

// 13a) Geç kabul yalnızca izlenen bölümü kaldırır: kabul edilen "a" taslak
// "taslak" içindeki "a" harflerini silmez (alt dize sahiplik değildir).
sendClick('a');
const idAltDize = lastId();
input.value = 'taslak';
ilerlet(60000);
assert.equal(input.value, 'a\ntaslak');
result(idAltDize, 'kabul', 'msg_alt_dize');
assert.equal(input.value, 'taslak', 'geç kabul ilgisiz taslağı bozmamalı');
await temizle();
sendClick('merhaba');
const idOnek = lastId();
ilerlet(60000);
userType('merhaba\nmerhaba dünya');
result(idOnek, 'kabul', 'msg_onek');
assert.equal(input.value, 'merhaba dünya', 'bağımsız yazılan önekli metin korunmalı');
await temizle();

// 13b) Aynı kullanıcının yetki değişimi uçuştaki istemi ret gibi geri yükler,
// açıkça bildirir; taslak ve İZLENEN önceki geri yüklemeler korunur, yeni nesil
// uygulanır. Önceki istem (A) görünüm değişiminde ayrılır, yeni istem (B)
// beklerken reddedilir; A'nın izlenen bölümü yetki sıfırlamasında silinmez.
sendClick('önceki ret');
const idOncekiRet = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('uçuştaki istem');
const idYetki = lastId();
result(idOncekiRet, 'ret');
assert.equal(input.value, 'önceki ret');
userType('önceki ret\ntaslak Y');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'yetki_degisti', nesil: 9 });
assert.equal(input.value, 'uçuştaki istem\nönceki ret\ntaslak Y', 'yetki değişiminde uçuştaki istem geri yüklenmeli, önceki geri yükleme ve taslak korunmalı');
assert.equal(pending().length, 0);
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'yetki değişiminde kilit kalkmalı');
assert.match(liveText(), /yetkileri güncellendi/, 'yetki değişimi açıkça bildirilmeli');
result(idYetki, 'ret');
assert.equal(input.value, 'uçuştaki istem\nönceki ret\ntaslak Y', 'eski neslin geç reddi girdiyi değiştirmemeli');
const yetkiOncesi = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, yetkiOncesi + 1);
assert.equal(sent[sent.length - 1].value.sahip_nesli, 9, 'yeni nesil sonraki isteme uygulanmalı');
assert.equal(sent[sent.length - 1].value.text, 'uçuştaki istem\nönceki ret\ntaslak Y', 'iki istem ve taslak yeniden denenebilmeli');
await temizle();

// 13c) Teslimden önce eklenip kaldırılan özdeş metinli düğüm bekleyen balonu
// gizlemez; bağlı eşleşme sonradan kaldırılırsa bekleyen balon yeniden görünür.
sendClick('kopukDugum eşleşme');
const idKopukEsleme = lastId();
const kopukDugum = serverBubble('kopuk_1', 'kopukDugum eşleşme');
chat.removeChild(kopukDugum);
await teslim();
assert.equal(gorunurBekleyen().length, 1, 'kopukDugum eşleşme bekleyen balonu gizlememeli');
const bagliDugum = serverBubble('kopuk_2', 'kopukDugum eşleşme');
await teslim();
assert.equal(gorunurBekleyen().length, 0, 'bağlı eşleşme çift balonu önlemeli');
chat.removeChild(bagliDugum);
await teslim();
assert.equal(gorunurBekleyen().length, 1, 'eşleşme kaptan ayrılınca bekleyen balon yeniden görünmeli');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'), 'sonuç gelene dek kilit sürmeli');
result(idKopukEsleme, 'ret');
await temizle();

// 13d) Zaman aşımı karşılamayı geri getirdikten sonra gelen geç kabul, asıl
// balon zaten kaptaysa söyleşi kabını yeniden gösterir.
welcome.classList.remove('hidden');
chat.style.display = '';
sendClick('karşılama geç kabul');
const idKarsilama = lastId();
assert.ok(welcome.classList.contains('hidden'));
ilerlet(60000);
assert.ok(!welcome.classList.contains('hidden'), 'zaman aşımı karşılamayı geri getirmeli');
assert.equal(chat.style.display, 'none');
serverBubble('msg_karsilama', 'karşılama geç kabul');
await teslim();
result(idKarsilama, 'kabul', 'msg_karsilama');
assert.ok(welcome.classList.contains('hidden'), 'geç kabulde karşılama gizlenmeli');
assert.notEqual(chat.style.display, 'none', 'geç kabulde söyleşi kabı görünmeli');
await temizle();

// 13e) Geç kabulden SONRA Geri Al ile dönen kabul edilmiş bölüm hemen kalkar;
// taslak D yeniden gönderime kabul edilmiş istemi katmaz.
sendClick('A geri al sonra');
const idGeriAlSonra = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'A geri al sonra\nD');
userType('D', 0);
result(idGeriAlSonra, 'kabul', 'msg_geri_al_sonra');
assert.equal(input.value, 'D');
userType('A geri al sonra\nD', 'A geri al sonra\n'.length, 'historyUndo');
assert.equal(input.value, 'D', 'Geri Al ile dönen kabul edilmiş istem kaldırılmalı');
const geriAlOncesi = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, geriAlOncesi + 1);
assert.equal(sent[sent.length - 1].value.text, 'D', 'kabul edilmiş istem yeniden gönderilmemeli');
result(lastId(), 'kabul', 'msg_geri_al_d');
await temizle();

// 13f) Ayırıcıyı aşan düzenleme iki bölümü çakıştırırsa her karakter tek isteğe
// ait kalır: geç kabul diğer isteğin karakterini silmez.
input.value = '';
sendClick('cde');
const idCde = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('abc');
const idAbc = lastId();
input.value = 'D';
tumZamanlayicilariCalistir();
assert.equal(input.value, 'abc\ncde\nD');
seciliYapistir(2, 5, 'c');
assert.equal(input.value, 'abcde\nD');
result(idAbc, 'kabul', 'msg_cakisma_abc');
assert.equal(input.value, 'abcde\nD', 'çakışan bölümün geç kabulü diğer isteğin karakterini silmemeli');
result(idCde, 'kabul', 'msg_cakisma_cde');
assert.equal(input.value, 'abcde\nD');
shinyHandlers.mergenBekleyenIstemSifirla({ neden: 'sahip_degisti' });
assert.equal(input.value, '', 'sahip sıfırlaması çakışan bölümleri de (girdiyi tümüyle) kaldırmalı');
await temizle();

// 14a) İlgisiz Geri Al, silinmiş bölümün metni aynı konumda dursa da sahipliği
// geri vermez: sahiplik yalnızca girdi silmeden önceki değere birebir dönerse gelir.
sendClick('A');
const idIlgisiz = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'A\nD');
userType('D', 0);                                  // A ve ayırıcı silinir
userType('A\nD yeni');                             // bağımsız yazım: aynı konumda "A"
userType('A\nD ye', 6, 'historyUndo');            // ilgisiz Geri Al: "A" aynı konumda ama değer farklı
result(idIlgisiz, 'kabul', 'msg_ilgisiz_geri_al');
assert.equal(input.value, 'A\nD ye', 'ilgisiz Geri Al bağımsız yazılan metni sahiplendirmemeli');
await temizle();

// 14a2) Silinen bölüm bağımsız olarak yeniden yapıştırılır, sonra eklenen "x"
// Geri Al ile kaldırılır: girdi silme öncesi değere birebir dönse de geri alınan
// düzenleme silme değildir; bağımsız metin sahiplenilmez ve geç kabul onu silmez.
sendClick('A');
const idYapistir = lastId();
userType('D');
ilerlet(60000);
assert.equal(input.value, 'A\nD');
userType('D', 0);                                   // A ve ayırıcı silinir
userType('A\nD', 2);                               // aynı metin bağımsız yapıştırılır
userType('A\nDx');                                 // sona "x" eklenir
userType('A\nD', 3, 'historyUndo');               // yalnızca "x" geri alınır
result(idYapistir, 'kabul', 'msg_yapistir_geri_al');
assert.equal(input.value, 'A\nD', 'sonraki düzenlemenin geri alınması bağımsız metni sahiplendirmemeli');
await temizle();

// 14a3) Denetim: silmeden sonra yazılan "x" ve ardından silmenin kendisi Geri Al
// ile geri alınırsa sahiplik geri gelir; geç kabul onaylanmış istemi kaldırır.
sendClick('A');
const idIkiAdim = lastId();
userType('D');
ilerlet(60000);
userType('D', 0);                                   // A silinir
userType('Dx');                                     // "x" yazılır
userType('D', 1, 'historyUndo');                    // "x" geri alınır
userType('A\nD', 2, 'historyUndo');               // silme geri alınır
result(idIkiAdim, 'kabul', 'msg_iki_adim');
assert.equal(input.value, 'D', 'silmenin kendisi geri alınınca kabul edilmiş istem kaldırılmalı');
await temizle();

// 14b) Tek düzenleme sekizden fazla bölümü silse de doğrudan Geri Al hepsinin
// sahipliğini geri getirir; geç kabuller onları kaldırır (yeniden gönderilmez).
const topluKimlikler = [];
for (let i = 1; i <= 10; i++) {
  sendClick('toplu ' + i);
  topluKimlikler.push(lastId());
  chat.children.slice().forEach(c => chat.removeChild(c));
  await teslim();
}
input.value = 'taslak';
ilerlet(60000);
const topluOnce = input.value;
assert.equal(topluOnce.split('\n').length, 11);
input.selectionStart = 0;
input.selectionEnd = topluOnce.length - 'taslak'.length;
beforeinputListeners.forEach(fn => fn({ target: input }));
userType('taslak', 0);                              // on bölüm tek seçimle silinir
userType(topluOnce, topluOnce.length - 'taslak'.length, 'historyUndo');
topluKimlikler.forEach((id, i) => result(id, 'kabul', 'msg_toplu_' + i));
assert.equal(input.value, 'taslak', 'Geri Al ile dönen tüm kabul edilmiş bölümler kaldırılmalı');
await temizle();

// 14c) Gizli zaman aşımı çapası karşılamanın geri gelmesini engellemez: yalnız
// görünür içerik etkin söyleşi sayılır.
welcome.classList.remove('hidden');
chat.style.display = '';
sendClick('çapa A');
const idCapaA = lastId();
ilerlet(60000);
assert.ok(!welcome.classList.contains('hidden'), 'ilk zaman aşımı karşılamayı geri getirmeli');
input.value = '';
sendClick('çapa B');
assert.ok(welcome.classList.contains('hidden'));
ilerlet(60000);
assert.ok(!welcome.classList.contains('hidden'), "A'nın gizli çapası B'nin zaman aşımında karşılamayı engellememeli");
input.value = '';
sendClick('çapa C');
result(lastId(), 'ret');
assert.ok(!welcome.classList.contains('hidden'), 'ret de gizli çapalara rağmen karşılamayı geri getirmeli');
// Görünür mesaj varken karşılama geri gelmez.
input.value = '';
const gorunurMesaj = serverBubble('msg_gorunur', 'görünür');
await teslim();
sendClick('çapa D');
result(lastId(), 'ret');
assert.ok(welcome.classList.contains('hidden'), 'görünür mesaj varken karşılama geri gelmemeli');
chat.removeChild(gorunurMesaj);
result(idCapaA, 'ret');
welcome.classList.add('hidden');
chat.style.display = '';
await temizle();

// 14d) Kesilen son bölümün önündeki satır sonu başka bir bölüme aitse korunur.
sendClick('B');
const idSonB = lastId();
chat.children.slice().forEach(c => chat.removeChild(c));
await teslim();
sendClick('A');
const idOnA = lastId();
ilerlet(60000);
assert.equal(input.value, 'A\nB');
userType('A\n\nB', 2);                            // A'nın sonuna satır sonu eklenir (A'ya katılır)
userType('A\n\nB', 2);
result(idSonB, 'kabul', 'msg_son_b');
assert.equal(input.value, 'A\n', "B kesilirken A'ya ait satır sonu silinmemeli");
result(idOnA, 'ret');
await temizle();

// 14e) Yalnızca boşlukta farklı olan reddedilen istem taslağa yutulmaz; birebir
// aynı bağımsız taslakta ise yinelenmez.
sendClick('  girintili\tistem  ');
const idBosluk = lastId();
input.value = 'girintili\tistem';
result(idBosluk, 'ret');
assert.equal(input.value, '  girintili\tistem  \ngirintili\tistem', 'boşluk farkı olan istem geri yüklenmeli');
await temizle();
sendClick('aynı taslak');
const idAyniTaslak = lastId();
input.value = 'aynı taslak';
result(idAyniTaslak, 'ret');
assert.equal(input.value, 'aynı taslak', 'birebir aynı bağımsız taslak yinelenmemeli');
await temizle();

// 12) Boş istem gönderilmez.
input.value = '   ';
const once = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, once);

console.log('chat_pending_bubble_regressions: OK');
})().catch(e => { console.error(e); process.exit(1); });
