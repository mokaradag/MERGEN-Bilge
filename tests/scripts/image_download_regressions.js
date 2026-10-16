const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function download(source, mime) {
  const clicks = [];
  const revoked = [];
  const toasts = [];
  const blob = { type: mime };
  const context = vm.createContext({
    console: { log() {}, error() {} },
    document: {
      addEventListener() {}, body: { appendChild() {}, removeChild() {} },
      createElement: () => ({ click() { clicks.push({ href: this.href, name: this.download }); } })
    },
    fetch: async url => {
      assert.equal(url, source);
      return { blob: async () => blob };
    },
    URL: {
      createObjectURL: value => { assert.equal(value, blob); return 'blob:fixture'; },
      revokeObjectURL: url => revoked.push(url)
    }
  });
  context.window = context;
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../../www/js/image_tools.js'), 'utf8'), context);
  context.showToast = (...args) => toasts.push(args);
  const image = { src: source };
  context.downloadGeneratedImage({ closest: () => ({ querySelector: () => image }) });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(clicks.length, 1);
  assert.deepEqual(toasts, [['Görsel indiriliyor...', 'success']]);
  assert.deepEqual(revoked, source.startsWith('data:') ? [] : ['blob:fixture']);
  assert.equal(clicks[0].href, source.startsWith('data:') ? source : 'blob:fixture');
  return clicks[0].name;
}

(async () => {
  for (const [mime, extension] of [
    ['image/png', 'png'], ['image/jpeg', 'jpg'], ['image/gif', 'gif'], ['image/webp', 'webp'],
    ['', 'png'], ['application/octet-stream', 'png'], ['image/svg+xml', 'png'],
    ['image/jpeg;charset=utf-8', 'jpg'], ['IMAGE/WEBP', 'webp']
  ]) {
    for (const source of [`data:${mime};base64,AAAA`, 'https://img.local/generated']) {
      const name = await download(source, mime);
      assert.match(name, new RegExp(`^mergen_bilge_.+\\.${extension}$`), `${source}: ${mime}`);
    }
  }
  console.log('Image download regressions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
