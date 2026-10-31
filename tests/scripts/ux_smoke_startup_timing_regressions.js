// Gerçek harness: Shiny/kabuk hazırken geciken sunucu welcome'u ve load kapısı.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const http = require('node:http');
const crypto = require('node:crypto');
const os = require('node:os');
const { spawn } = require('node:child_process');

const html = fs.readFileSync(path.resolve(__dirname, '../smoke/ux-smoke.html'), 'utf8').replace(/\r\n/g, '\n');
const script = html.slice(html.indexOf('<script>\n') + '<script>\n'.length, html.indexOf('\n</script>'));
const pendingStatus = 'Yükleniyor: fresh welcome';

async function startup(serverReadyAt, sourceScript = script) {
  let now = 0;
  let sequence = 0;
  const timers = [];
  const dependents = [];
  const storage = new Map([['mergen_settings', '{"startup_lane":"fast_lane"}']]);
  const original = new Map(storage);
  const barriers = [];
  const anchors = new Set(['#welcome_fullscreen_container', '#chat_content_container', '#user_input', '#send_stop_btn']);
  const appDoc = {
    body: {}, documentElement: {},
    querySelector(selector) {
      if (anchors.has(selector)) return {};
      if (selector === '.modern-welcome-root' && now >= serverReadyAt) return {};
      return null;
    }
  };
  const appWin = {
    document: appDoc, location: { href: 'https://app.test/bilge/' },
    Shiny: { setInputValue() {} },
    console: { error() {}, warn() {} }, addEventListener() {}
  };
  const nodes = {
    status: { textContent: '' }, log: { appendChild() {} },
    'start-smoke': { disabled: false },
    'app-frame': { contentWindow: appWin, contentDocument: appDoc }
  };
  class TestDate extends Date { static now() { return now; } }
  const context = vm.createContext({
    Date: TestDate, URL, URLSearchParams, console: { log() {} },
    document: {
      getElementById: id => nodes[id],
      body: { appendChild(frame) { barriers.push(frame); } },
      createElement(tag) {
        if (tag !== 'iframe') return {};
        const frame = { blocked: false, removed: false, contentDocument: {
          open() { frame.blocked = true; }, write() {},
          close() { frame.blocked = false; }
        }, remove() { frame.removed = true; } };
        return frame;
      }
    },
    localStorage: {
      getItem: key => storage.has(key) ? storage.get(key) : null,
      setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key)
    },
    location: { href: 'https://app.test/bilge/smoke/ux-smoke.html?autostart=1',
      pathname: '/bilge/smoke/ux-smoke.html', search: '?autostart=1' },
    setTimeout: (fn, ms) => { timers.push({ at: now + ms, id: ++sequence, fn }); return sequence; },
    addEventListener() {}, dependents
  });
  context.window = context;
  // Yalnız bağımlı testler sahte: başlangıç, waitFor, run, iade ve sonuç gerçektir.
  const tests = ['testWelcome', 'testNavigationAndFileManagerSmoke', 'testReasoning',
    'testOneQuickActionOnCurrentWelcome', 'testChatInput', 'testStreamingLifecycle',
    'testMediaAndSavedChat', 'testBilgeYolacSessionsSurface', 'testConsoleNoise'];
  const stubs = tests.map(name => `${name} = function () { dependents.push('${name}'); };`).join('\n');
  vm.runInContext(sourceScript.replace('  function startSmoke(startButton) {', stubs + '\n  function startSmoke(startButton) {'), context);
  assert.equal(nodes.status.textContent, pendingStatus, 'başlangıç etiketi loadFreshApp tarafından hemen güncellenir');
  assert.equal(barriers.length, 1, 'dump-dom için yerel load kapısı kurulmalı');
  assert.equal(barriers[0].hidden, true);
  assert.equal(barriers[0].blocked, true, 'Shiny/kabuk varlığı bitiş değildir');
  assert.equal(dependents.length, 0);
  let settled = false;
  for (let turn = 0; turn < 2000; turn++) {
    // Async fonksiyonların zincirini aynı gerçek saat adımında boşalt.
    for (let i = 0; i < 30; i++) await Promise.resolve();
    if (barriers[0].removed) { settled = true; break; }
    assert.equal(barriers[0].blocked, true, 'sonuç yazılmadan load kapısı açılamaz');
    timers.sort((a, b) => a.at - b.at || a.id - b.id);
    const timer = timers.shift();
    assert.ok(timer, 'başlangıç beklemesi ilerlemeli');
    now = timer.at;
    timer.fn();
  }
  assert.equal(settled, true, 'başlangıç ve hata yolu sınırlı olmalı');
  assert.equal(barriers[0].blocked, false);
  assert.deepEqual(storage, original, 'başarı ve hatada profil tercihleri iade edilir');
  return { status: nodes.status.textContent, dependents, now };
}

function nativeStartupScript(missingWelcome) {
  const begin = script.indexOf('      await testWelcome(app);');
  const end = script.indexOf('      testConsoleNoise();', begin) + '      testConsoleNoise();'.length;
  assert.ok(begin > 0 && end > begin);
  const fixture = script.slice(0, begin) + script.slice(end);
  if (!missingWelcome) return fixture;
  // Negatif örnek de kapıyı korur ve sonlu bir FAIL sonucu üretir.
  const missing = fixture.replace('}, "welcome veya chat görünümü hazır", 60000);',
    '}, "welcome veya chat görünümü hazır", 1000);');
  assert.notEqual(missing, fixture, 'yalnız yerel negatif örneğin bekleme bütçesi değişir');
  return missing;
}

async function nativeTiming(browser, diagnose = false) {
  // Sunucu timer'ı renderer saatinden bağımsızdır; yalnız loopback fixture kullanılır.
  const delay = 5000;
  // Soğuk Edge başlangıcı da VM koşucusunun 165 saniyelik sınırını kullanır.
  const browserTimeout = diagnose ? 20000 : 165000;
  const sockets = new Set();
  const timers = new Set();
  let missingWelcome = false;
  let served = 0;
  let trace = null;
  const fixture = html.replace(script, nativeStartupScript(false));
  const missingFixture = html.replace(script, nativeStartupScript(true));
  const server = http.createServer((req, res) => {
    if (trace) trace.requests++;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    if (req.url.startsWith('/bilge/smoke/ux-smoke.html')) {
      res.end(missingWelcome ? missingFixture : fixture);
    } else if (req.url.startsWith('/bilge/smoke/ux-smoke-probes.js')) {
      res.end('');
    } else if (req.url.startsWith('/bilge/')) {
      if (trace) trace.appRequests++;
      res.end(`<!doctype html><body><div id="welcome_fullscreen_container"></div>
        <div id="chat_content_container"></div><input id="user_input"><button id="send_stop_btn"></button>
        <script>window.Shiny={setInputValue:function(){}};
        var socket=new WebSocket(location.origin.replace('http','ws')+'/ready');
        socket.onmessage=function(){var root=document.createElement('div');
          root.className='modern-welcome-root';document.body.appendChild(root);};</script>`);
    } else { res.statusCode = 404; res.end(); }
  });
  server.on('upgrade', (req, socket) => {
    if (trace) trace.websockets++;
    sockets.add(socket);
    socket.on('error', () => {});
    socket.on('close', () => sockets.delete(socket));
    const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] +
      '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
    // Açık WebSocket veya tamamlanmamış sayfanın dump zamanına güvenilmez.
    if (missingWelcome) { socket.end(Buffer.from([0x88, 0])); return; }
    const timer = setTimeout(() => {
      timers.delete(timer);
      if (!socket.destroyed) {
        served++;
        socket.end(Buffer.from([0x81, 1, 49, 0x88, 0]));
      }
    }, delay);
    timers.add(timer);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-timing-'));
  try {
    const cases = diagnose ? ['node-blank', 'missing-welcome', 'delayed-welcome'] :
      ['missing-welcome', 'delayed-welcome'];
    for (const label of cases) {
      missingWelcome = label === 'missing-welcome';
      const before = served;
      trace = { label, requests: 0, appRequests: 0, websockets: 0,
        stdoutBytes: 0, stderrBytes: 0, exitSeen: false, closeSeen: false,
        exitCode: null, exitBeforeTimeout: false, timedOut: false, renderedStatus: '' };
      if (diagnose) console.log('BROWSER_PROBE_START ' + label);
      const caseProfile = path.join(profile, label);
      trace.uncProfile = caseProfile.startsWith('\\\\') || caseProfile.startsWith('//');
      fs.mkdirSync(caseProfile);
      const args = ['--headless=new', '--disable-gpu', '--disable-dev-shm-usage',
        '--no-first-run', '--no-default-browser-check',
        '--user-data-dir=' + caseProfile, '--dump-dom',
        '--timeout=' + (browserTimeout - 5000),
        label === 'node-blank' ? 'about:blank' :
          `http://127.0.0.1:${server.address().port}/bilge/smoke/ux-smoke.html?autostart=1`];
      if (process.platform === 'linux' && process.getuid() === 0) args.unshift('--no-sandbox');
      const output = await new Promise((resolve, reject) => {
        const child = spawn(browser, args, { cwd: caseProfile, windowsHide: true,
          stdio: ['ignore', 'pipe', 'pipe'] });
        let stdout = '';
        child.stdout.setEncoding('utf8');
        child.stdout.on('data', chunk => { stdout += chunk; trace.stdoutBytes += Buffer.byteLength(chunk); });
        // Ham stderr, DOM veya profil yolu tanı çıktısına taşınmaz.
        child.stderr.on('data', chunk => { trace.stderrBytes += chunk.length; });
        child.on('exit', code => {
          trace.exitSeen = true;
          trace.exitCode = code;
          trace.exitBeforeTimeout = !trace.timedOut;
        });
        let timedOut = false;
        const deadline = setTimeout(() => {
          timedOut = true;
          trace.timedOut = true;
          child.kill();
          // Tanı, çıkmış bir sürecin alt süreçlerinde açık kalan boruyu da sınırlar.
          if (diagnose) { child.stdout.destroy(); child.stderr.destroy(); }
        }, browserTimeout);
        child.on('error', error => { clearTimeout(deadline); reject(error); });
        child.on('close', (code, signal) => {
          clearTimeout(deadline);
          trace.closeSeen = true;
          trace.renderedStatus = stdout.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1] || '';
          trace.readySent = served > before;
          if (diagnose || timedOut || code !== 0) console.log('BROWSER_PROBE_RESULT ' + JSON.stringify(trace));
          if (timedOut) reject(new Error('Native browser ' + label + ' timed out after ' + browserTimeout + 'ms'));
          else if (code !== 0) reject(new Error('Native browser ' + label + ' failed: ' + (signal || code)));
          else resolve(stdout);
        });
      });
      if (label === 'node-blank') {
        assert.match(output, /<html[\s>]/);
        assert.ok(output.includes('</html>'), 'Node başlatması tam boş sayfa DOM döndürmeli');
        continue;
      }
      const status = output.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1];
      assert.equal(status, missingWelcome ? 'UX_SMOKE_DONE:FAIL 1' : 'UX_SMOKE_DONE:PASS');
      if (missingWelcome) assert.equal(served, before, 'welcome yokken PASS üretilemez');
      else assert.ok(served > before, 'PASS gerçek sunucu mesajını beklemeli');
      for (const timer of timers) clearTimeout(timer);
      timers.clear();
      for (const socket of sockets) socket.destroy();
    }
    console.log('native browser startup timing regressions passed');
  } finally {
    for (const timer of timers) clearTimeout(timer);
    for (const socket of sockets) socket.destroy();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    try {
      fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
    } catch (error) {
      if (!diagnose) throw error;
      console.log('BROWSER_PROBE_PROFILE_CLEANUP_FAILED');
      process.exitCode = 1;
    }
  }
}

(async () => {
  const delayed = await startup(3000);
  assert.equal(delayed.status, 'UX_SMOKE_DONE:PASS');
  assert.ok(delayed.now >= 3000, 'sunucunun gerçek welcome mesajı beklenmeli');
  assert.equal(delayed.dependents.length, 9);
  const stranded = await startup(Infinity);
  assert.equal(stranded.status, 'UX_SMOKE_DONE:FAIL 1', 'tek önkoşul hatası tek failure üretmeli');
  assert.deepEqual(stranded.dependents, [], 'welcome yokken navigation/quick-action/null zinciri çalışmamalı');
  assert.ok(stranded.now >= 60000 && stranded.now < 62000, 'aynı sonlu readiness bütçesi korunmalı');
  const nativeMissing = await startup(Infinity, nativeStartupScript(true));
  assert.equal(nativeMissing.status, 'UX_SMOKE_DONE:FAIL 1');
  assert.ok(nativeMissing.now >= 1000 && nativeMissing.now < 3000, 'yerel negatif örnek sonlanmalı');
  const nativeDelayed = await startup(5000, nativeStartupScript(false));
  assert.equal(nativeDelayed.status, 'UX_SMOKE_DONE:PASS');
  assert.ok(nativeDelayed.now >= 5000);
  console.log('ux smoke startup timing regressions passed (Türkçe: ğüşİıöç)');
  const browserArg = process.argv.indexOf('--browser');
  if (browserArg !== -1) await nativeTiming(process.argv[browserArg + 1], process.argv.includes('--diagnose'));
})().catch(error => { console.error(error); process.exitCode = 1; });
