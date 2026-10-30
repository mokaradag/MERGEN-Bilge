// Aynı oturumdaki sohbetten gerçek Yeni Söyleşi eylemine, sonra sekme dönüşüne.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../smoke/ux-smoke-probes.js'), 'utf8');

// File Manager sentetik listesinin de gerçek probe içinde çalıştığı küçük DOM.
class Element {
  constructor() { this.children = []; this.attrs = {}; this.offsetWidth = 1; }
  appendChild(child) { child.parentNode = this; this.children.push(child); }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); child.parentNode = null; }
  setAttribute(key, value) { this.attrs[key] = value; }
  getAttribute(key) { return this.attrs[key] || null; }
  set textContent(value) { this.text = value; }
  get textContent() { return (this.text || '') + this.children.map(child => child.textContent).join(''); }
  querySelector(selector) {
    for (const child of this.children) {
      if (((selector === 'input.attach-checkbox' || selector === '.attach-checkbox') && child.className === 'attach-checkbox') ||
          (selector[0] === '.' && child.className === selector.slice(1)) ||
          (selector[0] === '#' && child.id === selector.slice(1))) return child;
      const found = child.querySelector(selector);
      if (found) return found;
    }
    return null;
  }
}

async function runCase(initialWelcome, brokenReset = false, replaceOnReturn = false) {
  const state = { showWelcome: initialWelcome, active: 'chat', pending: null, resetCount: 0 };
  let welcome = initialWelcome ? new Element() : null;
  let video = { initCount: 1, destroyCount: 0, isInitialized: initialWelcome, hasContainer: initialWelcome };
  const body = new Element();
  const labels = [];
  const actions = [];
  const pane = name => ({
    id: 'shiny-tab-' + name, textContent: name === 'chat' ? '' : 'Bilge Yolaç', innerHTML: '',
    classList: { contains: value => value === 'active' && state.active === name },
    get offsetWidth() { return state.active === name ? 1 : 0; }
  });
  const chat = pane('chat');
  const yolac = pane('claude_code');
  const doc = {
    body, createElement: () => new Element(),
    getElementById: id => id === 'new_chat_btn' ? { click() {
      actions.push('new_chat');
      state.resetCount++;
      // Sunucu yanıtı aynı click yığınında değil, sonraki flush'ta gelir.
      state.pending = () => {
        if (brokenReset) return;
        state.showWelcome = true;
        welcome = new Element();
        video = { initCount: 2, destroyCount: 1, isInitialized: true, hasContainer: true };
      };
    } } : body.querySelector('#' + id),
    querySelector(selector) {
      const anchor = selector.match(/data-value='([^']+)'/);
      if (anchor) return { click() {
        const tab = anchor[1]; actions.push(tab); state.active = tab;
        // Üretim sözleşmesi: sekme değiştirmek show_welcome değerini açmaz.
        if (tab === 'chat' && state.showWelcome && replaceOnReturn) {
          welcome = new Element(); video.initCount++; video.destroyCount++;
        }
        if (welcome) welcome.offsetWidth = state.active === 'chat' ? 1 : 0;
      } };
      if (selector === '.modern-welcome-root') return state.showWelcome ? welcome : null;
      if (selector === '#chat_content_container .message-bubble') return state.showWelcome ? null : {};
      if (selector === '.claude-code-container' || selector === '#shiny-tab-claude_code') return yolac;
      if (selector === '#shiny-tab-chat.active') return state.active === 'chat' ? chat : null;
      if (selector === '#shiny-tab-claude_code.active') return state.active === 'claude_code' ? yolac : null;
      return null;
    },
    querySelectorAll: () => []
  };
  const win = {
    document: doc, location: { hash: '' }, localStorage: { getItem: () => '{}' },
    MergenWelcomeVideoSmoke: { getState: () => ({ ...video }) }
  };
  const context = vm.createContext({ window: win });
  vm.runInContext(source, context);
  await win.MergenUxSmokeProbes.runNavigationAndFileManagerSmoke({ win, doc }, {
    assert: (condition, label) => { assert.ok(condition, label); labels.push(label); },
    pass: label => labels.push(label), wait: async () => {},
    waitFor: async (condition, label) => {
      if (state.pending) { state.pending(); state.pending = null; }
      assert.ok(condition(), label); labels.push(label); return true;
    }
  });
  assert.deepEqual(actions, ['new_chat', 'claude_code', 'chat']);
  assert.equal(state.resetCount, 1);
  assert.equal(state.showWelcome, true);
  assert.ok(labels.includes('Ana Söyleşi dönüşü welcome video gereksiz destroy etmez'));
  assert.ok(labels.includes('Ana Söyleşi dönüşü welcome video gereksiz reinit etmez'));
  assert.ok(labels.includes('File Manager synthetic refresh sonrası Türkçe adı korur'));
}

(async () => {
  await runCase(false); // VM: quick-action/sohbet probe'larından sonra welcome yok.
  await runCase(true); // Eski/gizli welcome DOM'u da yeni flush yerine kabul edilmez.
  await assert.rejects(runCase(false, true), /Yeni Söyleşi welcome hazır/);
  await assert.rejects(runCase(true, true), /Yeni Söyleşi welcome hazır/);
  await assert.rejects(runCase(false, false, true), /welcome dönüşü/);
  console.log('ux smoke navigation regressions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
