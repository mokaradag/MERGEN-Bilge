// İyimser (bekleyen) istem balonu davranış regresyonları: gerçek
// www/js/chat_pending_message.js + input_handlers.js küçük bir sahte DOM/jQuery
// üzerinde çalıştırılır.
// Doğrulananlar: anında çizim, çift gönderim engeli, asıl balon gelince aynı
// mikro görevde kaldırma, ret durumunda metnin geri yüklenmesi, bekleme
// sırasında düğme tıklamasının yutulması ve bağlantı kopmasında temizlik.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const pendingSource = fs.readFileSync(path.resolve(__dirname, '../../www/js/chat_pending_message.js'), 'utf8');
const source = fs.readFileSync(path.resolve(__dirname, '../../www/js/input_handlers.js'), 'utf8');

// --- Küçük sahte DOM --------------------------------------------------------
function el(tag, attrs = {}) {
  const node = {
    tagName: tag.toUpperCase(), children: [], parentNode: null, attrs: Object.assign({}, attrs),
    style: {}, textContent: '', value: '', addEventListener() {},
    get id() { return this.attrs.id || ''; }, set id(v) { this.attrs.id = v; },
    get className() { return this.attrs.class || ''; }, set className(v) { this.attrs.class = v; },
    classList: null,
    appendChild(c) { c.parentNode = this; this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); c.parentNode = null; return c; },
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
const btn = body.appendChild(el('button', { id: 'send_stop_btn' }));
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

const observers = [];
const sent = [];
const shinyHandlers = {};
const context = vm.createContext({
  $, jQuery: $, document, console, setTimeout: () => 0, Date, Math, atob: s => Buffer.from(s, 'base64').toString('binary'),
  TextDecoder, Uint8Array,
  MutationObserver: function (cb) { this.observe = () => observers.push(cb); },
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
  chat.appendChild(w);
  observers.forEach(cb => cb([{ addedNodes: [w] }]));
  return w;
}
const pending = () => all(chat, '.mergen-bekleyen-istem');

// 1) Enter: balon anında, istemci kimliğiyle gönderim, düğme bekleme durumunda.
input.value = 'Merhaba dünya, çğış?';
trigger('keyup', '#user_input, .chat-input, textarea[name="user_input"]', input, { key: 'Enter' });
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'send_prompt_from_js');
const id1 = sent[0].value.client_id;
assert.match(id1, /^[A-Za-z0-9_-]{1,64}$/);
assert.equal(pending().length, 1, 'bekleyen balon hemen çizilmeli');
assert.equal(pending()[0].querySelector('.message-content').textContent, 'Merhaba dünya, çğış?');
assert.equal(pending()[0].querySelector('.message-bubble').style.animation, 'none', 'bekleyen balon solma animasyonuyla gizlenmemeli');
assert.ok(welcome.classList.contains('hidden'), 'karşılama ekranı iyimser olarak gizlenmeli');
assert.ok(btn.classList.contains('mergen-istem-bekliyor'));
assert.equal(btn.querySelector('i').className, 'fa-solid fa-stop');
assert.equal(input.value, '');

// 2) Bekleme sırasında ikinci gönderim engellenir; düğme tıklaması yutulur.
input.value = 'ikinci';
trigger('keyup', '#user_input, .chat-input, textarea[name="user_input"]', input, { key: 'Enter' });
assert.equal(sent.length, 1, 'bekleyen istem varken ikinci istem gönderilmemeli');
assert.equal(input.value, 'ikinci', 'engellenen metin kaybolmamalı');
let propagationStopped = false;
captureClick.forEach(fn => fn({ target: btn.querySelector('i'), preventDefault() {}, stopPropagation() { propagationStopped = true; } }));
assert.ok(propagationStopped, 'bekleme sırasında Durdur tıklaması sunucuya gitmemeli');
input.value = '';

// 3) Sunucunun asıl balonu: bekleyen balon aynı geri çağrıda kalkar, çift balon olmaz.
const asil = serverBubble('901', 'Merhaba dünya, çğış?');
assert.equal(pending().length, 0, 'asıl balon gelince bekleyen balon kaldırılmalı');
assert.equal(all(chat, '.user-message').length, 1, 'çift kullanıcı balonu olmamalı');
assert.ok(!asil.querySelector('.message-bubble').classList.contains('animate-fadeIn'), 'asıl balon solmadan görünmeli');
assert.equal(asil.querySelector('.message-bubble').style.animation, 'none', 'asıl balonun .message-bubble solması da kapatılmalı');
shinyHandlers.mergenIstemSonucu({ client_id: id1, durum: 'kabul' });
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'));

// 4) Ret: balon kalkar, metin girdiye geri yüklenir, düğme eski hâline döner.
input.value = 'reddedilecek istem';
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, 2);
assert.equal(pending().length, 1);
shinyHandlers.mergenIstemSonucu({ client_id: sent[1].value.client_id, durum: 'ret' });
assert.equal(pending().length, 0);
assert.equal(input.value, 'reddedilecek istem');
assert.equal(btn.querySelector('i').className, 'fa-solid fa-paper-plane');

// 5) Bağlantı koparsa bekleyen istem temizlenir ve metin kaybolmaz.
input.value = 'bağlantı kopacak';
trigger('click', '#send_stop_btn', btn);
assert.equal(pending().length, 1);
(handlers['shiny:disconnected|'] || []).forEach(fn => fn());
assert.equal(pending().length, 0);
assert.equal(input.value, 'bağlantı kopacak');

// 6) Kap başka bir akışla temizlenirse (Yeni Söyleşi) bekleyen kayıt düşer ve
//    gönderim kilitli kalmaz (ör. UX smoke send_prompt_from_js'i yakaladığında).
input.value = 'yanıtsız kalacak';
trigger('click', '#send_stop_btn', btn);
assert.equal(pending().length, 1);
const silinen = pending()[0];
chat.removeChild(silinen);
observers.forEach(cb => cb([{ addedNodes: [], removedNodes: [silinen] }]));
assert.ok(!btn.classList.contains('mergen-istem-bekliyor'), 'temizlenen kapta bekleme durumu kalmamalı');
input.value = 'yeni söyleşide ilk istem';
const oncekiGonderim = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, oncekiGonderim + 1, 'kap temizlendikten sonra gönderim kilitlenmemeli');
shinyHandlers.mergenIstemSonucu({ client_id: sent[sent.length - 1].value.client_id, durum: 'ret' });

// 7) Boş istem gönderilmez.
input.value = '   ';
const once = sent.length;
trigger('click', '#send_stop_btn', btn);
assert.equal(sent.length, once);

console.log('chat_pending_bubble_regressions: OK');
