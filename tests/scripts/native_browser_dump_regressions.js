const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { nativeDumpStatus, completeNativeDump, runNativeBrowserDump } = require('./helpers_native_browser_dump');

const page = status => '<html><body><div id="status">' + status + '</div></body></html>\n';
const traceFor = label => ({ label, stdoutBytes: 0, stderrBytes: 0,
  timedOut: false, exitSeen: false, closeSeen: false, exitBeforeTimeout: false });
const run = (code, trace, timeoutMs = 10000) => runNativeBrowserDump(process.execPath,
  ['-e', code], { cwd: os.tmpdir(), timeoutMs, trace });

(async () => {
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
    await run(parent, traceFor('tree'));
    const before = fs.readFileSync(heartbeat, 'utf8');
    await new Promise(resolve => setTimeout(resolve, 200));
    assert.equal(fs.readFileSync(heartbeat, 'utf8'), before, 'alt süreç profil yazmayı sürdürmemeli');
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
