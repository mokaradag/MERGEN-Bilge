const { spawn } = require('node:child_process');

function nativeDumpStatus(dom) {
  return dom.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1] || '';
}

function completeNativeDump(dom) {
  return /<html[\s>]/.test(dom) && /<\/body>\s*<\/html>\s*$/.test(dom);
}

function runNativeBrowserDump(browser, args, { cwd, timeoutMs, trace, cleanupMs = 5000 }) {
  return new Promise((resolve, reject) => {
    const child = spawn(browser, args, { cwd, windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let settled = false;
    let stoppedAfterDump = false;
    let cleanupTimer = null;
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
        finish(new Error('Native browser ' + trace.label + ' cleanup timed out'));
      }, cleanupMs);
    };
    const deadline = setTimeout(() => {
      trace.timedOut = true;
      child.kill('SIGKILL');
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
      // DOM tamamlandı; yalnız bu geçici profile ait başlatılan süreç durdurulur.
      if (child.exitCode === null && child.signalCode === null) {
        stoppedAfterDump = child.kill('SIGKILL');
        trace.stoppedAfterDump = stoppedAfterDump;
      } else {
        child.stdout.destroy();
        child.stderr.destroy();
      }
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
    child.on('close', (code, signal) => {
      trace.closeSeen = true;
      if (trace.timedOut) return finish(new Error('Native browser ' + trace.label + ' timed out after ' + timeoutMs + 'ms'));
      const ownedStop = stoppedAfterDump && code === null && signal === 'SIGKILL';
      if (code !== 0 && !ownedStop) return finish(new Error('Native browser ' + trace.label + ' failed: ' + (signal || code)));
      if (!trace.dumpComplete) return finish(new Error('Native browser ' + trace.label + ' returned an incomplete DOM'));
      finish();
    });
  });
}

module.exports = { nativeDumpStatus, completeNativeDump, runNativeBrowserDump };
