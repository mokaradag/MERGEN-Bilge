// Gerçek ready callback'i Shiny'nin tek argüman sözleşmesiyle tamamlanmalıdır.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../../www/js/shiny_message_handlers.js'), 'utf8');
const handlers = new Map();
const storage = new Map([['mergen_current_chat', 'önceki sohbet']]);
const sent = [];
const jq = () => new Proxy({}, { get: (_, key) => key === 'ready' ? fn => fn() : () => jq() });
const context = vm.createContext({
  $: jq, jQuery: jq, console, Date,
  document: { getElementById: () => null, querySelector: () => null, querySelectorAll: () => [] },
  localStorage: {
    getItem: key => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: key => storage.delete(key)
  },
  setTimeout: () => 0,
  Shiny: {
    addCustomMessageHandler(name, handler) {
      assert.equal(typeof handler, 'function', name);
      assert.equal(handler.length, 1, name + ': Shiny handler must take one argument');
      handlers.set(name, handler);
    },
    setInputValue: (name, payload) => sent.push({ name, payload })
  }
});
context.window = context;
vm.runInContext(source, context, { filename: 'shiny_message_handlers.js' });
assert.ok(handlers.has('clearCurrentChat'));
handlers.get('clearCurrentChat')({});
assert.equal(storage.get('mergen_current_chat'), undefined);
assert.equal(typeof context._handleQuickAction, 'function', 'ready callback quick-action kaydına ulaşmalı');
const attrs = new Map([['data-action-id', 'resource-analysis'], ['data-action-model', 'test-model']]);
context._handleQuickAction({
  disabled: false,
  getAttribute: key => attrs.get(key),
  setAttribute: (key, value) => attrs.set(key, value),
  removeAttribute: key => attrs.delete(key)
});
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'quick_template');
assert.equal(sent[0].payload.action_id, 'resource-analysis');
console.log('shiny message handler contract regressions passed');

// Gerçek giriş işleyicisi, harness yakalaması sırasında DB/LLM sınırına ulaşmaz.
const smokeHtml = fs.readFileSync(path.resolve(__dirname, '../smoke/ux-smoke.html'), 'utf8').replace(/\r\n/g, '\n');
const inputSource = fs.readFileSync(path.resolve(__dirname, '../../www/js/input_handlers.js'), 'utf8');
const chatFunctions = smokeHtml.slice(smokeHtml.indexOf('  async function testChatInput(app)'), smokeHtml.indexOf('  async function testStreamingLifecycle(app)'));
const savedFunction = smokeHtml.slice(smokeHtml.indexOf('  async function testSavedChatRestore(app)'), smokeHtml.indexOf('  async function testReasoning(app)'));
const eventFunction = smokeHtml.slice(smokeHtml.indexOf('function eventCount('), smokeHtml.indexOf('function isSsoEnabled('));

async function testPromptIsolation() {
  const listeners = [];
  const history = ['operatörün gerçek mesajı'];
  let llmCalls = 0;
  const classes = new Set();
  const send = { classList: { add: x => classes.add(x), remove: x => classes.delete(x) }, click() {
    listeners.filter(x => x.event === 'click' && x.selector === '#send_stop_btn').forEach(x => x.fn.call(send, {}));
  } };
  const input = { value: '', matches: () => true, dispatchEvent(e) {
    listeners.filter(x => x.event === e.type && x.selector && x.selector.includes('#user_input')).forEach(x => x.fn.call(input, e));
  } };
  const doc = { querySelector: selector => selector === '#user_input' ? input : selector === '#send_stop_btn' ? send : null };
  const original = (name, payload) => { if (name === 'send_prompt_from_js') { history.push(payload.text); llmCalls++; } };
  const c = vm.createContext({
    document: doc, console, setTimeout: () => 0, shinyEvents: [],
    Shiny: { setInputValue: original }, isNearBottom: true,
    Event: class { constructor(type, options) { this.type = type; Object.assign(this, options); } preventDefault() { this.defaultPrevented = true; } },
    assert: (ok, label) => assert.ok(ok, label), wait: async () => {},
    $(target) { return {
      0: input, length: 1, ready: fn => fn(),
      on: (event, selector, fn) => listeners.push({ event, selector: typeof selector === 'string' ? selector : null, fn: fn || selector }),
      hasClass: name => classes.has(name), children: () => ({ length: 0 }),
      val(value) { if (value !== undefined) input.value = value; return input.value; }, focus() {}
    }; }
  });
  c.window = c;
  c.KeyboardEvent = c.Event;
  vm.runInContext(inputSource, c);
  vm.runInContext(eventFunction + chatFunctions, c);
  await c.testChatInput({ win: c, doc });
  assert.deepEqual(history, ['operatörün gerçek mesajı'], 'smoke gerçek geçmişi değiştirmemeli');
  assert.equal(llmCalls, 0, 'smoke gerçek LLM/analiz çağırmamalı');
  assert.equal(c.Shiny.setInputValue, original);
  c.wait = async () => { throw new Error('bekleme hatası'); };
  await assert.rejects(c.testChatInput({ win: c, doc }), /bekleme hatası/);
  assert.equal(c.Shiny.setInputValue, original, 'hata sonrası gerçek giriş işleyicisi geri gelmeli');
  c.Shiny.setInputValue('send_prompt_from_js', { text: 'gerçek gönderim' });
  assert.equal(llmCalls, 1, 'harness dışında normal gönderim çalışmalı');
}

async function testSavedRestore(mode) {
  const storage = new Map([['mergen_current_chat', JSON.stringify({ v: 2, owner: 'server-owner', messages: [{ type: 'ai', content: 'tanıtım' }] })]]);
  let bubble = { textContent: 'tanıtım' };
  const labels = [];
  const win = {
    localStorage: { getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value) },
    mergenTTS: { queue: [], isPlaying: false, currentAudio: null },
    Shiny: { setInputValue(name, payload) {
      c.shinyEvents.push({ name, value: payload });
      if (mode === 'reject' || !payload || payload.owner !== 'server-owner' || !Array.isArray(payload.messages)) {
        storage.delete('mergen_current_chat'); return;
      }
      if (mode === 'accept') bubble = { textContent: payload.messages[0].content };
    } }
  };
  const doc = {
    getElementById: id => id === 'new_chat_btn' ? { click() { bubble = null; storage.delete('mergen_current_chat'); } } : null,
    querySelector: () => bubble
  };
  const c = vm.createContext({
    shinyEvents: [], Date, JSON, assert: (ok, label) => { assert.ok(ok, label); labels.push(label); },
    wait: async () => {}, fail: label => assert.fail(label),
    waitFor: async (condition, label) => assert.ok(condition(), label)
  });
  vm.runInContext(eventFunction + savedFunction, c);
  if (mode === 'accept') {
    await c.testSavedChatRestore({ win, doc });
    assert.ok(labels.includes('kayıtlı sohbet yüklenince tarihsel TTS autoplay başlamaz'));
    const saved = JSON.parse(storage.get('mergen_current_chat'));
    assert.equal(saved.v, 2);
    assert.equal(saved.owner, 'server-owner');
    assert.equal(bubble.textContent, saved.messages[0].content);
  } else {
    await assert.rejects(c.testSavedChatRestore({ win, doc }), /tarihsel mesajı gerçekten geri yüklendi/);
    assert.ok(!labels.includes('kayıtlı sohbet yüklenince tarihsel TTS autoplay başlamaz'), 'reddedilen veya işlenmeyen kayıt PASS olmamalı');
  }
}

(async () => {
  await testPromptIsolation();
  for (const mode of ['accept', 'reject', 'ignored']) await testSavedRestore(mode);
  console.log('authenticated smoke and saved chat regressions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
