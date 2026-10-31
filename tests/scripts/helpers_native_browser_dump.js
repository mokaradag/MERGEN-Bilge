const { spawn } = require('node:child_process');

function nativeDumpStatus(dom) {
  return dom.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1] || '';
}

function completeNativeDump(dom) {
  return /<html[\s>]/.test(dom) && /<\/body>\s*<\/html>\s*$/.test(dom);
}

function runNativeBrowserDump(browser, args, { cwd, timeoutMs, trace, cleanupMs = 5000 }) {
  return new Promise((resolve, reject) => {
    const windows = process.platform === 'win32';
    const child = spawn(browser, args, { cwd, windowsHide: true, detached: !windows,
      stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let settled = false;
    let stoppedAfterDump = false;
    let cleanupTimer = null;
    let treeStop = null;
    let treeKiller = null;
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
        if (treeKiller) treeKiller.kill('SIGKILL');
        child.kill('SIGKILL');
        child.stdout.destroy();
        child.stderr.destroy();
        child.unref();
        finish(new Error('Native browser ' + trace.label + ' cleanup timed out'));
      }, cleanupMs);
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
      } else if (!alive) {
        treeStop = Promise.resolve({ stopped: false });
      } else {
        // Görüntü adına göre değil, yalnız başlatılan PID'nin ağacına göre durdur.
        treeStop = new Promise(resolveStop => {
          treeKiller = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'],
            { windowsHide: true, stdio: 'ignore' });
          treeKiller.on('error', error => resolveStop({ error }));
          treeKiller.on('close', code => resolveStop({ stopped: code === 0,
            killFailed: code !== 0 }));
        });
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
      // taskkill yarışında doğal, başarılı çıkış da kabul edilir.
      if (cleanup.killFailed && code !== 0) return finish(new Error('Native browser ' + trace.label + ' tree cleanup failed'));
      const ownedStop = stoppedAfterDump && (windows ? code === 1 && !signal : code === null && signal === 'SIGKILL');
      if (code !== 0 && !ownedStop) return finish(new Error('Native browser ' + trace.label + ' failed: ' + (signal || code)));
      if (!trace.dumpComplete) return finish(new Error('Native browser ' + trace.label + ' returned an incomplete DOM'));
      finish();
    });
  });
}

module.exports = { nativeDumpStatus, completeNativeDump, runNativeBrowserDump };
