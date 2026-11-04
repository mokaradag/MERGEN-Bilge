const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const { spawn } = require('node:child_process');
const { PassThrough, Writable } = require('node:stream');
const { nativeDumpStatus, completeNativeDump, runNativeBrowserDump } = require('./helpers_native_browser_dump');

const page = status => '<html><body><div id="status">' + status + '</div></body></html>\n';
const traceFor = label => ({ label, stdoutBytes: 0, stderrBytes: 0,
  timedOut: false, exitSeen: false, closeSeen: false, exitBeforeTimeout: false });
const run = (code, trace, timeoutMs = 10000) => runNativeBrowserDump(process.execPath,
  ['-e', code], { cwd: os.tmpdir(), timeoutMs, trace });

async function windowsJobCase({ code = 0, hang = false, exited = false, complete = true } = {}) {
  const child = Object.assign(new EventEmitter(), { pid: 123, exitCode: null, signalCode: null,
    stdout: new PassThrough(), stderr: new PassThrough(), kill() {}, unref() {} });
  let stopped = false;
  let config;
  const close = () => {
    child.exitCode = code;
    child.emit('exit', code, null);
    child.emit('close', code, null);
  };
  child.stdin = new Writable({ write(chunk, encoding, done) {
    const value = chunk.toString().trim();
    if (!config) config = JSON.parse(value);
    else {
      assert.equal(value, 'stop');
      stopped = true;
      if (!hang) setImmediate(close);
    }
    done();
  } });
  const sandbox = { module: { exports: {} }, __dirname, process: { platform: 'win32' }, Buffer,
    setTimeout, clearTimeout, require(id) {
      if (id !== 'node:child_process') return require(id);
      return { spawn(command, args, options) {
        assert.equal(command, 'powershell.exe', 'PID ile taskkill kullanılmamalı');
        assert.ok(args.at(-1).includes('MergenBrowserJob'));
        assert.ok(args.includes('-Command'));
        setImmediate(() => {
          assert.equal(config.executable, 'edge');
          assert.deepEqual(config.args, ['unicode-\u011f', 'space and "quote"', 'tail\\']);
          assert.equal(config.cleanupMs, 100);
          child.stdout.write(complete ? page('UX_SMOKE_DONE:PASS') : '<html><body>partial');
          if (exited) close();
        });
        return child;
      } };
    } };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'helpers_native_browser_dump.js'), 'utf8'), sandbox);
  const trace = traceFor('windows-job');
  const result = sandbox.module.exports.runNativeBrowserDump('edge', ['unicode-\u011f', 'space and "quote"', 'tail\\'],
    { cwd: os.tmpdir(), timeoutMs: 100, cleanupMs: 100, adapterCleanupMs: 100, trace });
  return { result, trace, stopped: () => stopped };
}

async function profileCleanupCase(failure, diagnose = false) {
  const primary = new Error('browser failure');
  const cleanup = new Error('profile removal failed');
  const logs = [];
  const server = Object.assign(new EventEmitter(), { listen(port, host, done) { done(); },
    address: () => ({ port: 1 }), closeAllConnections() {}, close(done) { done(); } });
  const mockProcess = { platform: 'win32', exitCode: 0 };
  const source = fs.readFileSync(path.join(__dirname, 'ux_smoke_startup_timing_regressions.js'), 'utf8');
  const timing = vm.runInNewContext(source.slice(0, source.lastIndexOf('\n(async () => {')) + '\nnativeTiming;', {
    __dirname, Buffer, process: mockProcess, setTimeout: setImmediate, clearTimeout: clearImmediate,
    console: { log: message => logs.push(message) },
    require(id) {
      if (id === 'node:http') return { createServer: () => server };
      if (id === 'node:fs') return { ...fs, mkdtempSync: () => 'mock-profile', mkdirSync() {},
        rmSync() { throw cleanup; } };
      if (id === './helpers_native_browser_dump') return { nativeDumpStatus,
        async runNativeBrowserDump(browser, args, { trace }) {
          if (failure === 'browser') throw primary;
          if (failure === 'assertion') return page('unexpected');
          if (trace.label === 'delayed-welcome') {
            const socket = Object.assign(new EventEmitter(), { write() {}, end() {}, destroy() {} });
            server.emit('upgrade', { headers: { 'sec-websocket-key': 'fixture' } }, socket);
            await new Promise(setImmediate);
          }
          return page(trace.label === 'missing-welcome' ? 'UX_SMOKE_DONE:FAIL 1' : 'UX_SMOKE_DONE:PASS');
        } };
      return require(id);
    }
  });
  if (failure === 'browser') await assert.rejects(timing('edge', diagnose), error => error === primary);
  else if (failure === 'assertion') await assert.rejects(timing('edge', diagnose), /unexpected/);
  else if (diagnose) await timing('edge', diagnose);
  else await assert.rejects(timing('edge'), error => error === cleanup);
  assert.equal(logs.includes('BROWSER_PROBE_PROFILE_CLEANUP_FAILED'), !!failure || diagnose);
}

(async () => {
  // Job kapanışı başarısızsa tam PASS DOM'u kabul edilmez.
  for (const code of [1, 7, 124, 125]) {
    await assert.rejects((await windowsJobCase({ code })).result, /failed:/);
  }
  await (await windowsJobCase()).result;
  await (await windowsJobCase({ exited: true })).result;
  await assert.rejects((await windowsJobCase({ hang: true })).result, /cleanup timed out/);
  await assert.rejects((await windowsJobCase({ complete: false })).result, /timed out/);
  for (const failure of ['browser', 'assertion', null]) await profileCleanupCase(failure);
  await profileCleanupCase('browser', true);
  await profileCleanupCase(null, true);

  // VM'deki durum: tam sonuç çıktıktan sonra tarayıcı süreci açık kalır.
  for (const status of ['UX_SMOKE_DONE:FAIL 1', 'UX_SMOKE_DONE:PASS']) {
    const trace = traceFor(status);
    const output = await run('process.stdout.write(' + JSON.stringify(page(status)) + '); setInterval(() => {}, 1000);', trace);
    assert.equal(nativeDumpStatus(output), status);
    assert.equal(trace.dumpComplete, true);
    assert.equal(trace.stoppedAfterDump, true);
    assert.equal(trace.timedOut, false);
    assert.equal(trace.exitSeen, true);
    assert.equal(trace.closeSeen, true);
  }

  // Tarayıcı kökü kapanınca geçici profile yazan alt süreç de durmalı.
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-tree-'));
  const heartbeat = path.join(profile, 'heartbeat');
  const writer = 'const fs=require("node:fs");let n=0;' +
    'const beat=()=>fs.writeFileSync(' + JSON.stringify(heartbeat) + ',String(++n));' +
    'beat();process.send("ready");setInterval(beat,10);';
  const parent = 'const {spawn}=require("node:child_process");' +
    'const writer=spawn(process.execPath,["-e",' + JSON.stringify(writer) + '],' +
    '{stdio:["ignore","ignore","ignore","ipc"]});' +
    'writer.once("message",()=>process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + '));' +
    'setInterval(()=>{},1000);';
  const unrelated = spawn(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { stdio: 'ignore' });
  try {
    const naturalExit = parent.replace('process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + ')',
      'process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + ',()=>process.exit(0))');
    assert.notEqual(naturalExit, parent, 'doğal kök çıkışı ayrı bir olay sırası olmalı');
    const intermediate = 'const {spawn}=require("node:child_process");' +
      'const child=spawn(process.execPath,["-e",' + JSON.stringify(writer) + '],' +
      '{stdio:["ignore","ignore","ignore","ipc"]});' +
      'child.once("message",()=>process.send("ready",()=>process.exit(0)));';
    const orphanGrandchild = naturalExit.replace(JSON.stringify(writer), JSON.stringify(intermediate));
    for (const code of [parent, naturalExit, orphanGrandchild]) {
      const trace = traceFor('tree');
      await run(code, trace);
      if (process.platform === 'win32' && code === naturalExit) assert.equal(trace.exitCode, 0);
      assert.equal(unrelated.exitCode, null, 'job dışındaki süreç korunmalı');
      const before = fs.readFileSync(heartbeat, 'utf8');
      await new Promise(resolve => setTimeout(resolve, 200));
      assert.equal(fs.readFileSync(heartbeat, 'utf8'), before, 'alt süreç profil yazmayı sürdürmemeli');
    }
  } finally {
    unrelated.kill('SIGKILL');
    await new Promise(resolve => unrelated.once('close', resolve));
    fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }

  const partial = traceFor('partial');
  await assert.rejects(run('process.stdout.write(\'<html><body><div id="status">UX_SMOKE_DONE:PASS</div>\'); setInterval(() => {}, 1000);',
    partial, 1500), /timed out/);
  assert.equal(partial.dumpComplete, false);
  assert.equal(partial.timedOut, true);

  const crashed = traceFor('crashed');
  await assert.rejects(run('process.stdout.write("broken"); process.exit(7);', crashed), /failed: 7/);
  const incomplete = traceFor('incomplete');
  await assert.rejects(run('process.stdout.write("<html><body>incomplete");', incomplete), /incomplete DOM/);

  const literal = traceFor('literal');
  const source = '<html><body><div id="status">loading</div><script>const marker="UX_SMOKE_DONE:PASS";</script></body></html>\n';
  const output = await run('process.stdout.write(' + JSON.stringify(source) + ');', literal);
  assert.equal(nativeDumpStatus(output), 'loading');
  assert.equal(completeNativeDump('<div id="status">UX_SMOKE_DONE:PASS</div>'), false);
  console.log('native browser dump regressions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
