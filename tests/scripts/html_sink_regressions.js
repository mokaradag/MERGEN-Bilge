// tests/scripts/html_sink_regressions.js
// Model/kullanıcı metninin tarayıcıda işaretleme olamayacağını doğrular:
// Bilge Yolaç akış metni, destek sohbet yanıtı, destek eki dosya adı ve
// bildirim (toast) mesajı. Gerçek dosyalar node:vm içinde, sahte bir DOM ile
// çalıştırılır; innerHTML'e yazılan her dize etiket/öznitelik taramasından geçer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');

const HOSTILE = [
  '<img src=x onerror="window.__xss=1">',
  '<script>window.__xss=1</script>',
  '<svg/onload=window.__xss=1>',
  '"><iframe srcdoc="<b>x</b>"></iframe>',
  "<a href='javascript:window.__xss=1' onclick=\"window.__xss=1\">t</a>"
];

// Ayrıştırılabilir her etiket bir '<' ile başlamak zorundadır. Kaçışlı metin
// '&lt;' taşır; bu yüzden aşağıdaki tarama, dizeden doğabilecek TÜM öğeleri ve
// olay özniteliklerini görür.
function tags(html) {
  const out = [];
  const re = /<\/?([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>?/g;
  let m;
  while ((m = re.exec(String(html))) !== null) out.push({ name: m[1].toLowerCase(), attrs: m[2] || '' });
  return out;
}

function assertInert(html, allowed, allowedHandlers, label) {
  for (const t of tags(html)) {
    assert.ok(allowed.includes(t.name), label + ': beklenmeyen öğe <' + t.name + '> :: ' + html);
    const handlers = t.attrs.match(/\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi) || [];
    for (const h of handlers) {
      assert.ok(allowedHandlers.includes(h.trim()), label + ': beklenmeyen olay özniteliği ' + h + ' :: ' + html);
    }
    assert.ok(!/javascript:/i.test(t.attrs), label + ': javascript: URL :: ' + html);
  }
}

function element(tag) {
  const classes = new Set();
  const el = {
    tagName: String(tag || 'div').toUpperCase(), children: [], attrs: {}, style: { setProperty() {} },
    listeners: {}, innerHTMLWrites: [], _text: '', title: '', id: '', parentNode: null,
    classList: {
      add: (...x) => x.forEach(v => classes.add(v)), remove: (...x) => x.forEach(v => classes.delete(v)),
      contains: x => classes.has(x)
    },
    get className() { return [...classes].join(' '); },
    set className(v) { classes.clear(); String(v).split(/\s+/).filter(Boolean).forEach(c => classes.add(c)); },
    set innerHTML(v) { this.innerHTMLWrites.push(String(v)); this.children = []; this._text = ''; },
    get innerHTML() { return this.innerHTMLWrites.length ? this.innerHTMLWrites[this.innerHTMLWrites.length - 1] : ''; },
    set textContent(v) { this._text = String(v); this.children = []; },
    get textContent() { return this._text + this.children.map(c => c.textContent).join(''); },
    appendChild(c) { c.parentNode = this; this.children.push(c); return c; },
    insertBefore(c) { return this.appendChild(c); },
    addEventListener(name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); },
    setAttribute(k, v) { this.attrs[k] = String(v); }, getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    removeAttribute(k) { delete this.attrs[k]; }, remove() {},
    querySelector: () => null, querySelectorAll: () => [], closest: () => null
  };
  return el;
}

// textContent ile doldurulan düğümler için HTML kaçışı (yalnızca kaçış fallback'i).
function htmlFromText(el) {
  return el._text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function baseContext(extra) {
  const nodes = {};
  const document = {
    readyState: 'complete', body: element('body'),
    createElement: tag => {
      const el = element(tag);
      // div.textContent -> div.innerHTML kaçış kalıbı gerçek tarayıcıdaki gibi çalışsın.
      Object.defineProperty(el, 'innerHTML', {
        get() { return this.innerHTMLWrites.length ? this.innerHTMLWrites[this.innerHTMLWrites.length - 1] : htmlFromText(this); },
        set(v) { this.innerHTMLWrites.push(String(v)); this.children = []; this._text = ''; }
      });
      return el;
    },
    getElementById: id => nodes[id] || null,
    querySelectorAll: () => [], addEventListener() {}
  };
  const handlers = new Map();
  const context = vm.createContext(Object.assign({
    document, console, Date, Math, JSON, String, Number, Object, Array, RegExp, Set, Map,
    setTimeout: () => 0, clearTimeout() {},
    Shiny: { addCustomMessageHandler: (n, fn) => handlers.set(n, fn), setInputValue() {} },
    navigator: { clipboard: { writeText: () => Promise.resolve() } }
  }, extra || {}));
  context.window = context;
  return { context, nodes, handlers };
}

function load(context, file) {
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
}

// ---------------------------------------------------------------------------
// 1) Bilge Yolaç akış metni (text_delta / text / raw_text / result, çok parça)
// ---------------------------------------------------------------------------
(function claudeCodeStreaming() {
  const CC_TAGS = ['p', 'br', 'strong', 'em', 'code', 'pre', 'h2', 'h3', 'h4'];
  for (const withSharedSafety of [true, false]) {
    const env = baseContext();
    if (withSharedSafety) load(env.context, 'www/js/streaming_markdown_safety.js');
    load(env.context, 'www/js/claude_code_streaming.js');
    const handler = env.handlers.get('cc-stream-chunk');
    assert.equal(typeof handler, 'function');

    function run(chunks) {
      const target = element('div');
      const msg = element('div');
      const body = element('div');
      msg.querySelector = sel => (sel === '.cc-message-body' ? body : null);
      target.querySelector = sel => (sel === '#cc-streaming-msg' ? msg : null);
      target.closest = () => null;
      env.nodes.out = target;
      for (const [chunkType, html] of chunks) handler({ target: 'out', chunkType, html });
      return body;
    }

    for (const hostile of HOSTILE) {
      for (const type of ['text_delta', 'text', 'raw_text', 'result']) {
        const body = run([[type, 'Önce **kalın** ve `kod` ' + hostile + '\n\n```js\n' + hostile + '\n```\nsonra']]);
        assertInert(body.innerHTML, CC_TAGS, [], 'claude ' + type);
        assert.match(body.innerHTML, /<strong>kalın<\/strong>/);
        assert.match(body.innerHTML, /<pre class="cc-code-block"><code>/);
      }
      // Etiket iki parçaya bölünse de birikmiş metin işaretleme olamaz.
      const half = Math.floor(hostile.length / 2);
      const body = run([['text_delta', 'a ' + hostile.slice(0, half)], ['text_delta', hostile.slice(half) + ' b']]);
      for (const html of body.innerHTMLWrites) assertInert(html, CC_TAGS, [], 'claude bölünmüş');
      assert.equal(body.getAttribute('data-raw-text'), 'a ' + hostile + ' b');
    }
    // Normal markdown ve Türkçe metin korunur.
    const ok = run([['text', '# Başlık\nçalışma **şğüıöç** `x<y`']]);
    assert.match(ok.innerHTML, /<h2>Başlık<\/h2>/);
    assert.match(ok.innerHTML, /<strong>şğüıöç<\/strong>/);
    assert.match(ok.innerHTML, /<code>x&lt;y<\/code>/);
  }
})();

// ---------------------------------------------------------------------------
// 2) Destek sohbet yanıtı (bot balonu)
// ---------------------------------------------------------------------------
(function supportChatbot() {
  const BOT_TAGS = ['div', 'span', 'button', 'i', 'pre', 'code', 'h3', 'h4', 'strong', 'em', 'ul', 'li', 'br'];
  const COPY = ['onclick="destekChatbotCopyCode(this)"'];
  for (const withSharedSafety of [true, false]) {
    const env = baseContext();
    if (withSharedSafety) load(env.context, 'www/js/streaming_markdown_safety.js');
    load(env.context, 'www/js/destek_yardim_chatbot.js');
    const container = element('div');
    env.nodes['ns-chatbot_messages'] = container;
    for (const hostile of HOSTILE) {
      const msg = '## Yanıt\n- madde ' + hostile + '\n**kalın** `satır ' + hostile + '`\n```html\n' + hostile + '\n```';
      env.context.destekChatbotMesajEkle('ns-', msg, 'bot');
      const bubble = container.children[container.children.length - 1].children[1];
      assertInert(bubble.innerHTML, BOT_TAGS, COPY, 'destek bot');
      assert.match(bubble.innerHTML, /<strong>kalın<\/strong>/);
      assert.match(bubble.innerHTML, /<h3 class="destek-chat-heading">Yanıt<\/h3>/);
      assert.match(bubble.innerHTML, /<pre class="destek-code-pre"><code>/);
      // Dil etiketi de kaçışlı kalır (ör. ```html).
      assert.match(bubble.innerHTML, /<span class="destek-code-lang">html<\/span>/);
    }
    // Kod bloğundaki satır sonları korunur (kopyalama tam kodu almalı).
    const formatted = env.context.destekChatbotFormatMessage('```r\na <- 1\nb <- 2\n```');
    assert.match(formatted, /a &lt;- 1\nb &lt;- 2/);
  }
})();

// ---------------------------------------------------------------------------
// 3) Destek eki dosya adı listesi
// ---------------------------------------------------------------------------
(function supportAttachmentNames() {
  const env = baseContext({ $: () => ({ on() {}, trigger() {} }) });
  load(env.context, 'www/js/destek_form.js');
  const list = element('div');
  env.nodes['ns-dosya_listesi'] = list;
  const names = HOSTILE.concat(['ad"\'><b onmouseover=alert(1)>.png', 'Türkçe çok uzun dosya adı ile ekran görüntüsü.png']);
  env.context.destekUpdateFileList('ns-', names.map(name => ({ name, size: 2048 })));
  assert.equal(list.children.length, names.length);
  list.children.forEach((item, i) => {
    assert.deepEqual(item.innerHTMLWrites, [], 'öğe innerHTML ile kurulmamalı');
    const nameEl = item.children[1].children[0];
    const expected = names[i].length > 30 ? names[i].substring(0, 27) + '...' : names[i];
    assert.equal(nameEl._text, expected);
    assert.equal(nameEl.className, 'destek-file-item-name');
    assert.equal(item.children[1].children[1]._text, '0.00 MB');
    const btn = item.children[2];
    assert.equal(btn.className, 'destek-file-item-remove');
    assert.equal(btn.listeners.click.length, 1);
  });
  // Kaldır düğmesi doğru 1-tabanlı indeksi gönderir.
  const sent = [];
  env.context.Shiny.setInputValue = (id, value) => sent.push([id, value]);
  list.children[2].children[2].listeners.click[0]();
  assert.deepEqual(sent, [['ns-dosya_sil', 3]]);
})();

// ---------------------------------------------------------------------------
// 4) Bildirim (toast) mesajı
// ---------------------------------------------------------------------------
(function toastMessages() {
  const created = [];
  function jq(arg) {
    if (typeof arg === 'string' && arg.trim().startsWith('<')) {
      const obj = { html: arg, texts: [], classes: [] };
      obj.find = sel => ({ text: v => { obj.texts.push([sel, v]); return obj; } });
      obj.addClass = c => { obj.classes.push(c); return obj; };
      obj.remove = () => obj;
      created.push(obj);
      return obj;
    }
    return { append() {}, remove() {} };
  }
  const env = baseContext({ $: jq });
  env.nodes['toast-container'] = element('div');
  load(env.context, 'www/js/toast.js');
  for (const hostile of HOSTILE) {
    for (const type of ['info', 'error', 'warning', 'success', '"><img src=x onerror=alert(1)>']) {
      env.context.showToast("'" + hostile + "' dosyası işlenemedi", type, 1000);
      const t = created[created.length - 1];
      assert.ok(!t.html.includes(hostile), 'mesaj şablona girmemeli');
      // Tek olay özniteliği şablonun kendi kapatma düğmesidir.
      assertInert(t.html, ['div', 'i', 'span', 'button'], [t.html.match(/onclick="[^"]*"/)[0]], 'toast');
      assert.deepEqual(t.texts, [['.toast-message', "'" + hostile + "' dosyası işlenemedi"]]);
      assert.match(t.html, /class="toast toast-(info|error|warning|success)"/);
      if (type.startsWith('"')) assert.match(t.html, /toast-info/);
    }
  }
})();

console.log('html sink regressions passed');
