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
