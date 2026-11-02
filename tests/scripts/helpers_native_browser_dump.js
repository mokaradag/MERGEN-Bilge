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
    let inspector = null;
    trace.dumpComplete = false;
    trace.stoppedAfterDump = false;

    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      clearTimeout(cleanupTimer);
      trace.renderedStatus = nativeDumpStatus(stdout);
      if (error && inspector) inspector.kill('SIGKILL');
      if (error) reject(error); else resolve(stdout);
    };
    const boundCleanup = () => {
      if (cleanupTimer) return;
      cleanupTimer = setTimeout(() => {
        if (treeKiller) treeKiller.kill('SIGKILL');
        if (inspector) inspector.kill('SIGKILL');
        child.kill('SIGKILL');
        child.stdout.destroy();
        child.stderr.destroy();
        child.unref();
        finish(new Error('Native browser ' + trace.label + ' cleanup timed out' +
          (trace.cleanupPhase ? ' [' + trace.cleanupPhase + ']' : '')));
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
        let pending = null;
        let inspectorClosed = false;
        let inspectorFailure = null;
        let closedInspector = Promise.resolve();
        let data = '';
        const inspectionError = () => new Error('Native browser process inspection failed');
        const failInspection = error => {
          inspectorFailure = inspectorFailure || error;
          if (pending) { const request = pending; pending = null; request.reject(inspectorFailure); }
        };
        // Tek denetleyici, soğuk PowerShell başlatmalarını aynı temizlik bütçesine sığdırır.
        const request = command => new Promise((resolveRequest, rejectRequest) => {
          if (!inspector) {
            const script = "$ErrorActionPreference='Stop'; try { while ($null -ne ($line=[Console]::ReadLine())) { " +
              "$command=ConvertFrom-Json -InputObject $line; if ($command.action -eq 'snapshot') { " +
              "$result=@{rows=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,CreationDate | ForEach-Object { [pscustomobject]@{pid=[int64]$_.ProcessId;parent=[int64]$_.ParentProcessId;created=$(if ($null -eq $_.CreationDate) {''} else {$_.CreationDate.ToUniversalTime().Ticks.ToString()})} })} " +
              "} elseif ($command.action -eq 'stop') { foreach($target in $command.rows) { " +
              "$p=Get-Process -Id $target.pid -ErrorAction SilentlyContinue; if ($null -eq $p) {continue}; try { " +
              "$null=$p.Handle; $identity=Get-CimInstance Win32_Process -Filter ('ProcessId='+$target.pid) -Property CreationDate; " +
              "if (!$p.HasExited -and $null -ne $identity -and $identity.CreationDate.ToUniversalTime().Ticks.ToString() -eq $target.created) {$p.Kill(); $p.WaitForExit()} " +
              "} finally {$p.Dispose()} }; $result=@{stopped=$false} } else {exit 3}; " +
              "Write-Output (ConvertTo-Json -Compress -Depth 4 -InputObject $result); [Console]::Out.Flush() }; exit 0 } catch {exit 3}";
            inspector = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script],
              { cwd, windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
            closedInspector = new Promise(resolveClose => inspector.on('close', code => {
              inspectorClosed = true;
              if (code !== 0 || pending) failInspection(inspectionError());
              resolveClose();
            }));
            inspector.on('error', () => failInspection(inspectionError()));
            inspector.stdin.on('error', () => failInspection(inspectionError()));
            inspector.stdout.on('data', chunk => {
              if (Buffer.byteLength(data) + chunk.length > 1048576) {
                failInspection(new Error('Native browser process inspection exceeded its limit'));
                inspector.kill('SIGKILL');
                return;
              }
              data += chunk.toString('utf8');
              const end = data.indexOf('\n');
              if (end < 0) return;
              try {
                if (!pending || data.slice(end + 1).trim()) throw inspectionError();
                const result = JSON.parse(data.slice(0, end));
                data = '';
                const current = pending; pending = null;
                current.resolve(result);
              } catch (_) { failInspection(inspectionError()); inspector.kill('SIGKILL'); }
            });
          }
          if (inspectorFailure || inspectorClosed) return rejectRequest(inspectorFailure || inspectionError());
          pending = { resolve: resolveRequest, reject: rejectRequest };
          trace.cleanupPhase = command.action;
          inspector.stdin.write(JSON.stringify(command) + '\n');
        });
        const snapshot = async () => {
          const result = await request({ action: 'snapshot' });
          const rows = result && result.rows;
          if (!Array.isArray(rows) || rows.length > 8192 || !rows.every(row => row &&
              Number.isSafeInteger(row.pid) && row.pid >= 0 && Number.isSafeInteger(row.parent) && row.parent >= 0 &&
              typeof row.created === 'string' && (row.created === '' || /^[0-9]+$/.test(row.created))) ||
              new Set(rows.map(row => row.pid)).size !== rows.length) throw inspectionError();
          return rows;
        };
        const killTree = () => new Promise(resolveStop => {
          trace.cleanupPhase = 'taskkill';
          treeKiller = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'],
            { windowsHide: true, stdio: 'ignore' });
          treeKiller.on('error', error => resolveStop({ error }));
          treeKiller.on('close', code => resolveStop({ stopped: code === 0,
            killFailed: code !== 0, killIssued: true }));
        });
        const stopOrphans = async rows => {
          try {
            const result = await request({ action: 'stop', rows });
            if (!result || result.stopped !== false) throw inspectionError();
            return { stopped: false };
          } catch (error) { return { error }; }
        };
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
        })().then(async result => {
          trace.cleanupPhase = 'inspector-close';
          try {
            if (inspector && !inspectorClosed) inspector.stdin.end();
            await closedInspector;
          } catch (error) {
            if (inspector) inspector.kill('SIGKILL');
            await closedInspector;
            inspectorFailure = inspectorFailure || error;
          }
          inspector = null;
          if (!result.error && !inspectorFailure && child.exitCode === null && child.signalCode === null) {
            trace.cleanupPhase = 'root-close';
          }
          return result.error ? result : inspectorFailure ? { error: inspectorFailure } : result;
        }).catch(error => ({ error }));
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
