const { spawn } = require('node:child_process');

function nativeDumpStatus(dom) {
  return dom.match(/<div id="status"[^>]*>([^<]*)<\/div>/)?.[1] || '';
}

function completeNativeDump(dom) {
  return /<html[\s>]/.test(dom) && /<\/body>\s*<\/html>\s*$/.test(dom);
}

function windowsOwnedProcesses(rows, seeds) {
  const byParent = new Map();
  for (const row of rows) {
    if (!byParent.has(row.parent)) byParent.set(row.parent, []);
    byParent.get(row.parent).push(row.pid);
  }
  const ids = new Set(seeds);
  const queue = Array.from(ids);
  for (let i = 0; i < queue.length; i++) {
    for (const pid of byParent.get(queue[i]) || []) {
      if (!ids.has(pid)) { ids.add(pid); queue.push(pid); }
    }
  }
  return rows.filter(row => ids.has(row.pid));
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
      } else {
        // Kimlik anlık görüntüsü PID yeniden kullanımını ayırır; yol/komut okunmaz.
        const snapshot = () => new Promise((resolveSnapshot, rejectSnapshot) => {
          const script = "$ErrorActionPreference='Stop'; ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,CreationDate | ForEach-Object { [pscustomobject]@{pid=[int64]$_.ProcessId;parent=[int64]$_.ParentProcessId;created=$(if ($null -eq $_.CreationDate) {''} else {$_.CreationDate.ToUniversalTime().Ticks.ToString()})} })";
          const probe = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script],
            { cwd, windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
          treeKiller = probe;
          let data = '';
          probe.stdout.on('data', chunk => {
            if (Buffer.byteLength(data) + chunk.length > 1048576) {
              probe.kill('SIGKILL');
              rejectSnapshot(new Error('Native browser process inspection exceeded its limit'));
            } else data += chunk.toString('utf8');
          });
          probe.on('error', () => rejectSnapshot(new Error('Native browser process inspection failed')));
          probe.on('close', code => {
            try {
              if (code !== 0) throw new Error();
              const rows = JSON.parse(data);
              if (!Array.isArray(rows) || rows.length > 8192 || !rows.every(row => row &&
                  Number.isSafeInteger(row.pid) && row.pid >= 0 && Number.isSafeInteger(row.parent) && row.parent >= 0 &&
                  typeof row.created === 'string' && (row.created === '' || /^[0-9]+$/.test(row.created)))) throw new Error();
              if (new Set(rows.map(row => row.pid)).size !== rows.length) throw new Error();
              resolveSnapshot(rows);
            } catch (_) { rejectSnapshot(new Error('Native browser process inspection failed')); }
          });
        });
        const killTree = () => new Promise(resolveStop => {
          treeKiller = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'],
            { windowsHide: true, stdio: 'ignore' });
          treeKiller.on('error', error => resolveStop({ error }));
          treeKiller.on('close', code => resolveStop({ stopped: code === 0,
            killFailed: code !== 0, killIssued: true }));
        });
        const stopOrphans = rows => new Promise(resolveStop => {
          // Acik surec taniticisi, kimlik kontrolu ile sonlandirma arasinda PID devrini onler.
          const identities = rows.map(row => '@{pid=' + row.pid + ';created="' + row.created + '"}').join(',');
          const script = "$ErrorActionPreference='Stop'; $targets=@(" + identities + "); foreach($target in $targets) { " +
            "$p=Get-Process -Id $target.pid -ErrorAction SilentlyContinue; if ($null -eq $p) {continue}; try { " +
            "$null=$p.Handle; if (!$p.HasExited -and $p.StartTime.ToUniversalTime().Ticks.ToString() -eq $target.created) {$p.Kill()} " +
            "} finally {$p.Dispose()} }";
          treeKiller = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script],
            { windowsHide: true, stdio: 'ignore' });
          treeKiller.on('error', error => resolveStop({ error }));
          treeKiller.on('close', code => resolveStop(code === 0 ? { stopped: false } :
            { error: new Error('Native browser orphan cleanup failed') }));
        });
        treeStop = (async () => {
          try {
            const before = windowsOwnedProcesses(await snapshot(), [child.pid]);
            if (settled) return {};
            if (!before.every(row => row.created)) throw new Error('Native browser process ownership could not be verified');
            const stillAlive = child.exitCode === null && child.signalCode === null;
            if (!stillAlive && before.some(row => row.pid === child.pid)) {
              throw new Error('Native browser process ownership could not be verified');
            }
            if (stillAlive && !before.some(row => row.pid === child.pid)) {
              throw new Error('Native browser process ownership could not be verified');
            }
            if (!stillAlive && before.length === 0) return { stopped: false, verified: true };
            const result = stillAlive ? await killTree() : await stopOrphans(before);
            if (result.error) return result;
            // Basarili taskkill dahil her sonlandirmada tum agac yeniden dogrulanir.
            const known = new Map(before.map(row => [row.pid, row.created]));
            let after = windowsOwnedProcesses(await snapshot(), [child.pid, ...known.keys()]);
            const survivors = after.filter(row => known.get(row.pid) === row.created && row.created);
            if (stillAlive && survivors.length) {
              const orphans = await stopOrphans(survivors);
              if (orphans.error) return orphans;
              after = windowsOwnedProcesses(await snapshot(), [child.pid, ...known.keys()]);
            }
            if (after.some(row => !known.has(row.pid) || known.get(row.pid) === row.created || !row.created)) {
              return { error: new Error('Native browser ' + trace.label + ' tree cleanup failed') };
            }
            return { ...result, verified: true };
          } catch (error) {
            return { error };
          }
        })().catch(error => ({ error }));
        treeStop.then(result => {
          if (!result.error || settled) return;
          // ChildProcess kendi Windows taniticisini kullanir; dogrulanmamis PID agaci oldurulmez.
          child.kill('SIGKILL');
          child.stdout.destroy();
          child.stderr.destroy();
          child.unref();
          finish(result.error);
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
      // Kök çıkışı tek başına alt süreçlerin kapandığını kanıtlamaz.
      const killedRoot = windows && trace.dumpComplete && cleanup.killIssued &&
        (cleanup.stopped || cleanup.verified) && code === 1 && !signal;
      if (cleanup.killFailed && (!cleanup.verified || (code !== 0 && !killedRoot))) return finish(new Error('Native browser ' + trace.label + ' tree cleanup failed'));
      const ownedStop = killedRoot || (stoppedAfterDump && (windows ? code === 1 && !signal : code === null && signal === 'SIGKILL'));
      trace.stoppedAfterDump = !!ownedStop;
      if (code !== 0 && !ownedStop) return finish(new Error('Native browser ' + trace.label + ' failed: ' + (signal || code)));
      if (!trace.dumpComplete) return finish(new Error('Native browser ' + trace.label + ' returned an incomplete DOM'));
      finish();
    });
  });
}

module.exports = { nativeDumpStatus, completeNativeDump, runNativeBrowserDump };
