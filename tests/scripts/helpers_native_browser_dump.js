const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

function nativeDumpStatus(dom) {
  return dom.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1] || '';
}

function completeNativeDump(dom) {
  return /<html[\s>]/.test(dom) && /<\/body>\s*<\/html>\s*$/.test(dom);
}

function runNativeBrowserDump(browser, args, { cwd, timeoutMs, trace, cleanupMs = 5000, adapterCleanupMs = 5000 }) {
  return new Promise((resolve, reject) => {
    const windows = process.platform === 'win32';
    const child = windows
      ? spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
        fs.readFileSync(path.join(__dirname, 'run_owned_browser.ps1'), 'utf8')],
        { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] })
      : spawn(browser, args, { cwd, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    if (windows) {
      child.stdin.on('error', () => {});
      child.stdin.write(JSON.stringify({ executable: browser, args, cwd, timeoutMs,
        cleanupMs: adapterCleanupMs, jobSource: path.join(__dirname, 'helpers_browser_job.cs') }) + '\n');
    }
    let stdout = '';
    let settled = false;
    let stoppedAfterDump = false;
    let cleanupTimer = null;
    let treeStop = null;
    trace.dumpComplete = false;
    trace.stoppedAfterDump = false;

    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      clearTimeout(cleanupTimer);
      trace.renderedStatus = nativeDumpStatus(stdout);
      if (error) reject(error); else resolve(stdout);
    };
    const boundCleanup = () => {
      if (cleanupTimer) return;
      cleanupTimer = setTimeout(() => {
        child.kill('SIGKILL');
        child.stdout.destroy();
        child.stderr.destroy();
        child.unref();
        finish(new Error('Native browser ' + trace.label + ' cleanup timed out' +
          (trace.cleanupPhase ? ' [' + trace.cleanupPhase + ']' : '')));
      // Windows denetleyicisi adaptorun kendi dogrulama butcesini kesmez.
      }, windows ? adapterCleanupMs + cleanupMs : cleanupMs);
    };
    const stopOwnedTree = () => {
      if (treeStop) return treeStop;
      const alive = child.exitCode === null && child.signalCode === null;
      if (!windows) {
        // Ayrı süreç grubu yalnız bu fixture'ın tarayıcı ağacını kapsar.
        try {
          process.kill(-child.pid, 'SIGKILL');
          treeStop = Promise.resolve({ stopped: alive });
        } catch (error) {
          treeStop = Promise.resolve(error.code === 'ESRCH' ? { stopped: false } : { error });
        }
      } else {
        // Windows agaci PID yerine baslangictan beri tutulan job taniticisiyla kapanir.
        child.stdin.write('stop\n');
        treeStop = Promise.resolve({ stopped: alive });
      }
      return treeStop;
    };
    const deadline = setTimeout(() => {
      trace.timedOut = true;
      stopOwnedTree();
      child.stdout.destroy();
      child.stderr.destroy();
      boundCleanup();
    }, timeoutMs);

    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      stdout += chunk;
      trace.stdoutBytes += Buffer.byteLength(chunk);
      if (trace.timedOut || trace.dumpComplete || !completeNativeDump(stdout)) return;
      trace.dumpComplete = true;
      clearTimeout(deadline);
      boundCleanup();
      // Tam DOM'dan sonra profil yazan alt süreçler de kapatılır.
      stopOwnedTree().then(result => {
        stoppedAfterDump = !!result.stopped;
        trace.stoppedAfterDump = stoppedAfterDump;
      });
    });
    // Ham stderr veya profil yolu çıktıya taşınmaz.
    child.stderr.on('data', chunk => { trace.stderrBytes += chunk.length; });
    child.on('exit', code => {
      trace.exitSeen = true;
      trace.exitCode = code;
      trace.exitBeforeTimeout = !trace.timedOut;
      // Tam DOM alındıktan sonra alt süreçlerin açık boruları işi bekletemez.
      if (trace.dumpComplete) { child.stdout.destroy(); child.stderr.destroy(); }
    });
    child.on('error', error => finish(error));
    child.on('close', async (code, signal) => {
      trace.closeSeen = true;
      const cleanup = treeStop ? await treeStop : {};
      if (trace.timedOut) return finish(new Error('Native browser ' + trace.label + ' timed out after ' + timeoutMs + 'ms'));
      if (cleanup.error) return finish(cleanup.error);
      // Windows wrapper ancak job bosaldiktan sonra exit 0 verir.
      const ownedStop = stoppedAfterDump && !windows && code === null && signal === 'SIGKILL';
      trace.stoppedAfterDump = windows ? stoppedAfterDump && code === 0 : !!ownedStop;
      if (code !== 0 && !ownedStop) return finish(new Error('Native browser ' + trace.label + ' failed: ' + (signal || code)));
      if (!trace.dumpComplete) return finish(new Error('Native browser ' + trace.label + ' returned an incomplete DOM'));
      finish();
    });
  });
}

module.exports = { nativeDumpStatus, completeNativeDump, runNativeBrowserDump };
