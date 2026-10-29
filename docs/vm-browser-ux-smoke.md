# Windows VM browser UX smoke

Shiny normal topolojide **0.0.0.0:8009** üzerinde kalır; Edge, kullanıcıların normalde kullandığı onaylı reverse-proxy/SSO URL'sine gider. Yerel `127.0.0.1:8009` yalnız ön kontroldür, bind zorunluluğu değildir. SSO, JWT/state, Keycloak ve tarayıcı güvenlik ayarları değişmez.

Harness `tests/smoke/` altında kalır. Normal başlatmada hiçbir smoke yolu açılmaz. Ağda yalnız `MERGEN_ENABLE_UX_SMOKE=true`, `MERGEN_ALLOW_NETWORK_UX_SMOKE=true` ve `MERGEN_UX_SMOKE_PATH` birlikte geçerliyken kaynak kaydedilir. Önek tam olarak `__mergen_ux_` + 48 küçük hex karakteridir; koşucu bunu işletim sisteminin güvenli rastgele kaynağından 24 bayt (192 bit) ile üretir. Sabit `/smoke/` yalnız loopback yerel test uyumluluğudur. Rastgele yol yetkilendirme yerine geçmez: uygulamanın mevcut SSO/oturumu ve yetkileri kullanılmaya devam eder.

**Yaşam süresi:** Window 2 ortamı çalışan Window 1 sürecini değiştiremez. Bu nedenle normal uygulamayı durdurup aşağıdaki geçici smoke başlatmasını aynı `0.0.0.0:8009` üzerinde yapın. Koşucu `source('app.R')` sonrasında opt-in değerlerini uygular; `.Renviron` dosyasına hiçbir şey yazmaz. Önek yalnız kullanıcıya ait `%LOCALAPPDATA%\MERGEN\BrowserUxSmokeRun\prefix` dosyasında paylaşılır; URL veya kimlik bilgisi içermez. Aynı Windows hesabını kullanın. Süreç sona erince HTTP yolu kaybolur; normal çıkış/Ctrl+C yerel dosyayı da temizler. Zorla öldürmede kalan dizini, o smoke sürecinin durduğunu doğruladıktan sonra silin. Her yeni `--start-app` yeni önek üretir. Tek başlatma boyunca hızlı smoke ve tam gate aynı öneki kullanabilir.

## Window 1 — geçici smoke uygulaması

Normal 8009 uygulamasını kendi konsolundan/normal işletim yöntemiyle durdurun. Mevcut proxy/SSO yapılandırmasını değiştirmeyin.

```powershell
Set-Location "<repo>"
$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) {
    $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe"
}
if (!(Test-Path $rscript)) { throw "Rscript.exe bulunamadi." }
& $rscript --vanilla tests/scripts/run_vm_browser_ux_smoke.R --start-app
```

Bu komut ön planda bekler; uygulama **0.0.0.0:8009** dinler. Window 1'i test süresince açık bırakın. Test başlatmadan uygulamanın boot işlemini bitirmesini bekleyin.

## Window 2 — SSO için ayrı Edge profili

Gerçek hostname/URL repoya veya artifact'a yazılmaz. Her zaman çalışma anında alın; belge/test örneği yalnız `https://app.example.invalid/base` biçimindedir. Alt yol varsa base URL'ye ekleyin; sorgu/fragment eklemeyin.

```powershell
Set-Location "<repo>"
$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) {
    $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe"
}
$env:MERGEN_BROWSER_UX_BASE_URL = Read-Host "Approved MERGEN base URL"
$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmoke"
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (!(Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
if (!(Test-Path $edge)) { throw "Microsoft Edge bulunamadi." }
$env:MERGEN_BROWSER_BIN = $edge
& $edge "--user-data-dir=$env:MERGEN_BROWSER_UX_PROFILE_DIR" --no-first-run --no-default-browser-check $env:MERGEN_BROWSER_UX_BASE_URL
```

Ayrı profilde normal SSO girişini tamamlayın ve uygulamanın açıldığını doğrulayın. Sonra **bu profile ait bütün Edge pencerelerini kapatın**. Profil repo/artifact dışında kalmalıdır. Token/cookie okunmaz, kopyalanmaz veya enjekte edilmez. Oturum geçerliyse bu hazırlığı her seferinde tekrarlamak gerekmez; SSO sayfasında kalan smoke başarısızdır.

## Yalnız browser UX smoke — hızlı kontrol

Aynı Window 2'de:

```powershell
& $rscript --vanilla tests/scripts/run_vm_browser_ux_smoke.R
if ($LASTEXITCODE -ne 0) { throw "Browser UX smoke FAILED" }
```

Bu komut yalnız browser UX smoke çalıştırır. Yerel ön kontrol `http://127.0.0.1:8009/<per-run-prefix>/ux-smoke.html` üzerindedir; headless Edge ise onaylı runtime base URL + aynı önek + `/ux-smoke.html?autostart=1` kullanır. Proxy mevcut base altındaki rastgele kaynak yolunu aynı 8009 uygulamasına iletmelidir. HTTP 200, harness kaynağı, SSO yönlendirmesi veya exit 0 kanıt değildir. Başarı yalnız **`OK: rendered #status is UX_SMOKE_DONE:PASS.`** ile bildirilir. URL'ler/önek DOM ve stderr artifact'larında redakte edilir.

## Tam VM evidence gate

Window 1 açıkken, aynı Window 2'de:

```powershell
Remove-Item Env:MERGEN_EVIDENCE_STEPS -ErrorAction SilentlyContinue
$env:MERGEN_EVIDENCE_PROFILE = "vm"
& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
if ($LASTEXITCODE -ne 0) { throw "VM evidence gate FAILED" }
```

`MERGEN_BROWSER_UX_BASE_URL` ayarlıysa gate mevcut `browser_ux_smoke` adımında VM sarmalayıcısını kullanır ve browser zorunludur. Normal 13 adım korunur; tam kanıt için **13 passed, 0 failed, 0 skipped** gerekir. URL ayarlı değilse generic/cloud koşucu davranışı korunur.

## Normal moda dönüş

Window 1'de **Ctrl+C** ile geçici uygulamayı durdurun. Ardından normal launcher'ı kullanın; örneğin aynı repo kökünde:

```powershell
Remove-Item Env:MERGEN_ENABLE_UX_SMOKE,Env:MERGEN_ALLOW_NETWORK_UX_SMOKE,Env:MERGEN_UX_SMOKE_PATH -ErrorAction SilentlyContinue
& $rscript --vanilla run_mergen_prod.R
```

Normal `.Renviron` yapılandırması `MERGEN_HOST=0.0.0.0`, `MERGEN_PORT=8009` olarak kalır; smoke opt-in/önek değerlerini `.Renviron` içine **eklemeyin**. Window 2'de çalışma URL'sini/profil seçimini temizleyin (hazırlanmış profil silinmez):

```powershell
Remove-Item Env:MERGEN_BROWSER_UX_BASE_URL,Env:MERGEN_BROWSER_UX_PROFILE_DIR,Env:MERGEN_BROWSER_BIN,Env:MERGEN_EVIDENCE_PROFILE -ErrorAction SilentlyContinue
```

Zorla sonlandırma sonrası eski handshake varsa ve Window 1 artık çalışmıyorsa yalnız `Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmokeRun"` dizinini silin; hazırlanan `BrowserUxSmoke` profilini silmeyin.
