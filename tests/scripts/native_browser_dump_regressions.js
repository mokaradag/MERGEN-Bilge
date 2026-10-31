const assert = require('node:assert/strict');
const os = require('node:os');
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
