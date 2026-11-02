const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const { PassThrough, Writable } = require('node:stream');
const { nativeDumpStatus, completeNativeDump, runNativeBrowserDump } = require('./helpers_native_browser_dump');

const page = status => '<html><body><div id="status">' + status + '</div></body></html>\n';
const traceFor = label => ({ label, stdoutBytes: 0, stderrBytes: 0,
  timedOut: false, exitSeen: false, closeSeen: false, exitBeforeTimeout: false });
const run = (code, trace, timeoutMs = 10000) => runNativeBrowserDump(process.execPath,
  ['-e', code], { cwd: os.tmpdir(), timeoutMs, trace });

async function windowsCleanupCase({ killCode = 1, rootCode = 1, signal = null,
  spawnError = false, hang = false, exited = false, complete = true,
  survivor = false, inspectionError = false, malformed = false, overflow = false,
  reused = false, spawnedChild = false, unknownIdentity = false, orphanSurvives = true,
  inspectorCloseCode = 0, emptyResponse = false, inspectorHangClose = false, fragmented = false } = {}) {
  const child = Object.assign(new EventEmitter(), { pid: 123, exitCode: null, signalCode: null,
    stdout: new PassThrough(), stderr: new PassThrough(), kill() {}, unref() {} });
  const closeRoot = () => {
    child.exitCode = rootCode;
    child.signalCode = signal;
    child.emit('exit', rootCode, signal);
    child.emit('close', rootCode, signal);
  };
  let kills = 0;
  let inspections = 0;
  let probes = 0;
  let orphanStopped = false;
  const initial = [
    { pid: 0, parent: 0, created: '' },
    { pid: 123, parent: 10, created: '100' },
    { pid: 456, parent: 123, created: unknownIdentity ? '' : '200' },
    { pid: 789, parent: 456, created: '300' }
  ];
  const spawn = (command, args, options) => {
    if (command === 'powershell.exe') {
      probes++;
      assert.ok(Array.from(args).includes('-NoProfile'));
      assert.deepEqual(Array.from(options.stdio), ['pipe', 'pipe', 'ignore']);
      assert.ok(args.at(-1).includes('$null=$p.Handle'), 'yetim süreç kimliği açık tanıtıcı üzerinden korunmalı');
      assert.ok(args.at(-1).includes('$identity.CreationDate.ToUniversalTime().Ticks.ToString() -eq $target.created'));
      assert.ok(!args.at(-1).includes('StartTime'), 'kimlik ölçümleri aynı CIM hassasiyetini kullanmalı');
      assert.ok(!args.at(-1).includes('CommandLine'), 'süreç sorgusu özel komut satırlarını okumamalı');
      const probe = Object.assign(new EventEmitter(), { stdout: new PassThrough() });
      let closed = false;
      const close = code => { if (!closed) { closed = true; probe.emit('close', code); } };
      const respond = value => {
        const text = JSON.stringify(value) + '\r\n';
        const split = fragmented ? Math.floor(text.length / 2) : text.length;
        probe.stdout.write(text.slice(0, split));
        if (fragmented) setImmediate(() => probe.stdout.write(text.slice(split)));
      };
      probe.kill = () => setImmediate(() => close(1));
      probe.stdin = new Writable({ write(chunk, encoding, done) {
        const request = JSON.parse(chunk.toString());
        setImmediate(() => {
          if (emptyResponse === true) return close(0);
          if (request.action === 'stop') {
            kills++;
            assert.ok(request.rows.length && request.rows.every(row => row.created));
            orphanStopped = !orphanSurvives;
            respond({ stopped: false });
            return;
          }
          assert.equal(request.action, 'snapshot');
          inspections++;
          if (emptyResponse === 'after' && inspections > 1) return close(0);
          if (inspectionError === true || (inspectionError === 'after' && inspections > 1)) return close(1);
          const remaining = survivor ? [initial[survivor === 'grandchild' ? 3 : 2]] : reused ? [{ ...initial[2], created: '999' }] :
            spawnedChild ? [{ pid: 999, parent: 456, created: '400' }] : [];
          const before = exited ? (survivor ? initial.slice(2) : []) : initial;
          const rows = inspections === 1 ? before : orphanStopped ? [] : remaining;
          if (overflow || malformed) probe.stdout.write(overflow ? 'x'.repeat(1048577) : 'invalid\n');
          else respond({ rows });
        });
        done();
      } });
      probe.stdin.on('finish', () => {
        if (!inspectorHangClose) setImmediate(() => close(inspectorCloseCode));
      });
      return probe;
    }
    if (command === 'taskkill.exe') {
      kills++;
      assert.deepEqual(Array.from(args), ['/PID', '123', '/T', '/F']);
      const killer = Object.assign(new EventEmitter(), { kill() {} });
      setImmediate(() => {
        if (spawnError) killer.emit('error', new Error('taskkill spawn failed'));
        killer.emit('close', killCode);
        if (!hang) closeRoot();
      });
      return killer;
    }
    setImmediate(() => {
      if (exited) child.exitCode = rootCode;
      child.stdout.write(complete ? page('UX_SMOKE_DONE:PASS') : '<html><body>partial');
      if (exited) closeRoot();
    });
    return child;
  };
  const sandbox = { module: { exports: {} }, process: { platform: 'win32' }, Buffer,
    setTimeout, clearTimeout, require: () => ({ spawn }) };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'helpers_native_browser_dump.js'), 'utf8'), sandbox);
  const trace = traceFor('windows-race');
  const result = sandbox.module.exports.runNativeBrowserDump('edge', [],
    { cwd: os.tmpdir(), timeoutMs: 100, cleanupMs: 100, trace });
  return { result, trace, kills: () => kills, probes: () => probes, inspections: () => inspections };
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
  // Windows yarışı Linux'ta da gerçek helper olaylarıyla doğrulanır.
  for (const killCode of [0, 1, 128]) {
    const race = await windowsCleanupCase({ killCode });
    assert.equal(nativeDumpStatus(await race.result), 'UX_SMOKE_DONE:PASS');
    assert.equal(race.kills(), 1);
    assert.equal(race.probes(), 1, 'ön ve son inceleme tek denetleyici kullanmalı');
    assert.equal(race.inspections(), 2, 'başarılı taskkill son incelemeyi atlamamalı');
    assert.equal(race.trace.stoppedAfterDump, true);
  }
  // Kök 0 veya 1 ile kapansa da hayatta kalan alt süreç PASS olamaz.
  for (const killCode of [0, 1, 128]) {
    for (const rootCode of [0, 1]) {
      for (const survivor of [true, 'grandchild']) {
        await assert.rejects((await windowsCleanupCase({ killCode, rootCode, survivor })).result, /tree cleanup failed/);
      }
    }
  }
  for (const rootCode of [0, 1]) {
    await assert.rejects((await windowsCleanupCase({ exited: true, rootCode, survivor: true })).result, /tree cleanup failed/);
  }
  await assert.rejects((await windowsCleanupCase({ survivor: 'grandchild' })).result, /tree cleanup failed/);
  await assert.rejects((await windowsCleanupCase({ spawnedChild: true })).result, /tree cleanup failed/);
  for (const options of [{ inspectionError: true }, { inspectionError: 'after' }, { malformed: true }, { unknownIdentity: true }, { overflow: true }]) {
    const failed = await windowsCleanupCase(options);
    await assert.rejects(failed.result, /process (inspection|ownership)/);
    assert.equal(failed.kills(), options.inspectionError === 'after' ? 1 : 0,
      'kimlik incelemesi basarisizsa PID ile sonlandirma yapilmamali');
  }
  const orphaned = await windowsCleanupCase({ exited: true, rootCode: 0, survivor: true });
  await assert.rejects(orphaned.result, /tree cleanup failed/);
  assert.equal(orphaned.kills(), 1, 'kok cikinca bilinen yetimlerin temizligi denenmeli');
  for (const exited of [false, true]) {
    const cleaned = await windowsCleanupCase({ exited, rootCode: exited ? 0 : 1, killCode: 0,
      survivor: true, orphanSurvives: false });
    await cleaned.result;
    assert.equal(cleaned.kills(), exited ? 1 : 2, 'dogrulanan yetim kapaninca ancak son inceleme PASS olmali');
  }
  const reusedPid = await windowsCleanupCase({ reused: true });
  await reusedPid.result;
  assert.equal(reusedPid.trace.stoppedAfterDump, true, 'yeniden kullanılan PID önceki sürecin yaşadığı anlamına gelmez');
  await assert.rejects((await windowsCleanupCase({ inspectorCloseCode: 1 })).result, /process inspection/);
  await assert.rejects((await windowsCleanupCase({ emptyResponse: true })).result, /process inspection/);
  await assert.rejects((await windowsCleanupCase({ emptyResponse: 'after' })).result, /process inspection/);
  await assert.rejects((await windowsCleanupCase({ inspectorHangClose: true })).result, /cleanup timed out \[inspector-close\]/);
  await assert.rejects((await windowsCleanupCase({ spawnError: true, inspectorCloseCode: 1 })).result, /taskkill spawn failed/);
  const fragmented = await windowsCleanupCase({ fragmented: true, survivor: true, orphanSurvives: false });
  await fragmented.result;
  assert.equal(fragmented.probes(), 1, 'parçalı yanıtlar ve yetim temizliği yeni denetleyici başlatmamalı');
  for (const [options, error] of [
    [{ spawnError: true }, /taskkill spawn failed/],
    [{ rootCode: 7 }, /tree cleanup failed/],
    [{ killCode: 0, rootCode: 7 }, /failed: 7/],
    [{ rootCode: null, signal: 'SIGKILL' }, /tree cleanup failed/],
    [{ hang: true }, /cleanup timed out/],
    [{ exited: true }, /failed: 1/],
    [{ complete: false }, /timed out/]
  ]) await assert.rejects((await windowsCleanupCase(options)).result, error);
  const natural = await windowsCleanupCase({ exited: true, rootCode: 0 });
  await natural.result;
  assert.equal(natural.kills(), 0);
  assert.equal(natural.trace.stoppedAfterDump, false);
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
  const pidFile = path.join(profile, 'writer-pid');
  const writer = 'const fs=require("node:fs");let n=0;' +
    'fs.writeFileSync(' + JSON.stringify(pidFile) + ',String(process.pid));' +
    'const beat=()=>fs.writeFileSync(' + JSON.stringify(heartbeat) + ',String(++n));' +
    'beat();process.send("ready");setInterval(beat,10);';
  const parent = 'const {spawn}=require("node:child_process");' +
    'const writer=spawn(process.execPath,["-e",' + JSON.stringify(writer) + '],' +
    '{stdio:["ignore","ignore","ignore","ipc"]});' +
    'writer.once("message",()=>process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + '));' +
    'setInterval(()=>{},1000);';
  try {
    const naturalExit = parent.replace('process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + ')',
      'process.stdout.write(' + JSON.stringify(page('UX_SMOKE_DONE:PASS')) + ',()=>process.exit(0))');
    assert.notEqual(naturalExit, parent, 'dogal kok cikisi ayri bir olay sirasi olmali');
    for (const code of [parent, naturalExit]) {
      const trace = traceFor('tree');
      await run(code, trace);
      if (process.platform === 'win32' && code === naturalExit) assert.equal(trace.exitCode, 0);
      const before = fs.readFileSync(heartbeat, 'utf8');
      await new Promise(resolve => setTimeout(resolve, 200));
      assert.equal(fs.readFileSync(heartbeat, 'utf8'), before, 'alt süreç profil yazmayı sürdürmemeli');
    }
  } finally {
    if (fs.existsSync(pidFile)) {
      try { process.kill(Number(fs.readFileSync(pidFile, 'utf8')), 'SIGKILL'); }
      catch (error) { if (error.code !== 'ESRCH') throw error; }
    }
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
