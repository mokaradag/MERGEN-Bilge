const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');

function surface() {
  const storage = new Map();
  const events = new Map();
  const messages = new Map();
  const sent = [];
  let timers = [];
  let connected = false;
  function element(attrs = {}) {
    const classes = new Set();
    return {
      style: { setProperty: () => {}, removeProperty: () => {} }, dataset: {}, disabled: false, offsetParent: {},
      classList: { add: (...x) => x.forEach(v => classes.add(v)), remove: (...x) => x.forEach(v => classes.delete(v)),
        contains: x => classes.has(x), toggle: (x, on) => on ? classes.add(x) : classes.delete(x) },
      getAttribute: x => attrs[x], setAttribute: (x, v) => { attrs[x] = v; }, removeAttribute: x => delete attrs[x],
      querySelector: () => null, querySelectorAll: () => [], contains: () => false, focus: () => {}, blur: () => {}
    };
  }
  const overlay = element();
  const cards = ['odak', 'denge'].map(mode => element({ 'data-mode': mode }));
  overlay.querySelectorAll = selector => selector === '.cinematic-mode-card' ? cards : [];
  const nodes = { 'mode-modal-overlay': overlay, 'mode-step-1': element(), 'mode-step-2': element(), 'cinematic-character-step': element() };
  const document = {
    readyState: 'loading', activeElement: null, body: element(),
    addEventListener: () => {}, getElementById: id => nodes[id] || null,
    querySelector: () => null, querySelectorAll: selector => selector === '.cinematic-mode-card' ? cards : [],
    createElement: () => element()
  };
  function jquery(target) {
    return {
      ready: fn => fn(),
      on: (name, selector, fn) => { events.set(name + (typeof selector === 'string' ? ':' + selector : ''), fn || selector); },
      off: name => events.delete(name), attr: name => target.getAttribute(name)
    };
  }
  const localStorage = { getItem: key => storage.get(key) ?? null, setItem: (key, v) => storage.set(key, v), removeItem: key => storage.delete(key) };
  const Shiny = { shinyapp: { isConnected: () => connected }, setInputValue: (id, value) => sent.push({ id, value }),
    addCustomMessageHandler: (id, fn) => messages.set(id, fn) };
  const context = vm.createContext({ document, localStorage, Shiny, console, Date, $: jquery,
    setTimeout: (fn, ms) => { const t = { fn, ms }; timers.push(t); return t; },
    clearTimeout: t => { timers = timers.filter(x => x !== t); }, setInterval: () => 1, clearInterval: () => {},
    requestAnimationFrame: fn => fn(), matchMedia: () => ({ matches: true }) });
  context.window = context;
  context.jQuery = jquery;
  return {
    context, cards, messages, sent, storage, events,
    load: name => vm.runInContext(fs.readFileSync(path.join(root, 'www/js', name), 'utf8'), context),
    tick: () => { const pending = timers; timers = []; pending.forEach(x => x.fn()); },
    connect: () => { connected = true; events.get('shiny:connected.mergenModeRetry')?.(); }
  };
}

// Aynı tercih sürüm artırmaz; bekleyen açık seçim geçerli kalır.
{
  const s = surface();
  s.load('api_key_choice_modal.js');
  const key = 'api_key_onboarding_suppressed.user-a';
  s.storage.set(key, JSON.stringify({ v: '', n: 4 }));
  const remember = s.messages.get('mergenApiKeyChoiceRemember');
  remember({ userTag: 'user-a', source: 'personal', base: 4 });
  assert.equal(JSON.parse(s.storage.get(key)).n, 4);
  remember({ userTag: 'user-a', source: 'default', base: 4 });
  assert.deepEqual(JSON.parse(s.storage.get(key)), { v: 'default', n: 5 });
  remember({ userTag: 'user-a', source: 'clear', base: 4 });
  assert.deepEqual(JSON.parse(s.storage.get(key)), { v: 'default', n: 5 });
}

// Bağlantı geri gelince yalnız son seçim bir kez gönderilir.
{
  const s = surface();
  s.load('explore_cinematic.js');
  const click = s.events.get('click:.cinematic-mode-card');
  s.context.CinematicExplore.openModal();
  click.call(s.cards[0]);
  s.tick();
  assert.equal(s.sent.filter(x => x.id === 'selected_experience_mode').length, 0);
  assert.ok(s.events.has('shiny:connected.mergenModeRetry'));
  s.context.CinematicExplore.openModal();
  click.call(s.cards[1]);
  s.tick();
  s.connect();
  s.connect();
  const selections = s.sent.filter(x => x.id === 'selected_experience_mode');
  assert.equal(selections.length, 1);
  assert.equal(selections[0].value.mode, 'denge');
  assert.equal(s.events.has('shiny:connected.mergenModeRetry'), false);
}
// Bağlantı yokken karakter onayı kilidi bırakılır ve yeniden seçim yapılabilir.
{
  const s = surface();
  s.load('explore_cinematic.js');
  s.load('explore_character_step.js');
  const step = s.context.CinematicCharacterStep;
  step.loadCharactersData([{ id: 'emre' }]);
  step.showCharacterStep();
  s.context.Shiny = undefined;
  step.confirmSelection();
  s.tick();
  s.tick();
  assert.ok(s.events.has('shiny:connected.mergenModeRetry'));
  step.showCharacterStep();
  step.confirmSelection();
  s.tick();
  s.tick();
  assert.equal(step.isActive(), false);
  const sent = [];
  s.context.Shiny = { setInputValue: (id, value) => sent.push({ id, value }) };
  s.connect();
  assert.equal(sent.filter(x => x.id === 'selected_experience_mode').length, 1);
}
console.log('Client state regressions passed');
