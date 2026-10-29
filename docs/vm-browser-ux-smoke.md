# Windows VM browser UX smoke

Bu akış, SSO/Keycloak'ın yalnız onaylı dış uygulama adresinde çalıştığı Windows VM için gerçek browser UX smoke doğrulamasıdır. Browser-facing URL ile Shiny dinleme adresi bilinçli olarak ayrıdır: Shiny güvenlik için loopback'te kalır; tarayıcı ise normal reverse-proxy/SSO origin'ini kullanır.

Gerçek hostname veya kurum içi URL repoya yazılmaz; `MERGEN_BROWSER_UX_BASE_URL` yalnız VM PowerShell oturumunda verilir.

## Güvenlik sınırı

UX smoke harness `tests/smoke/` altında kalır ve normal `www/` statik ağacına taşınmaz. `/smoke/` varsayılan kapalıdır ve PR #731'in loopback kuralı korunur:

- `MERGEN_ENABLE_UX_SMOKE=true` gerekir.
- Shiny `127.0.0.1` üzerinde dinler.
- SSO, JWT/state doğrulaması veya tarayıcı güvenliği kapatılmaz.
- Test bitince uygulama normal ayarlarla yeniden başlatılır.

## Window 1 — 8009 uygulamasını smoke-enabled loopback olarak başlatın

Normal 8009 uygulamasını durdurun ve aynı portta geçici smoke-enabled instance'ı başlatın:

```powershell
$repo = "U:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
Set-Location $repo

$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) { $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" }
if (!(Test-Path $rscript)) { throw "R 4.6.0 Rscript.exe bulunamadi." }

& $rscript -e "if (file.exists('.Renviron')) readRenviron('.Renviron'); Sys.setenv(MERGEN_RUN_APP='false', MERGEN_DISABLE_FUTURES='true', MERGEN_HOST='127.0.0.1', TZ='UTC'); source('app.R', encoding='UTF-8'); Sys.setenv(MERGEN_ENABLE_UX_SMOKE='true'); run_mergen_app(host='127.0.0.1', port=8009L, launch.browser=FALSE, quiet=FALSE)"
```

Bayrağın `source('app.R')` sonrasında verilmesi kasıtlıdır; başlangıç yapılandırmasının geçici smoke opt-in'ini geri yazmasını önler.

Reverse proxy'nin normal dış uygulama yolunu bu aynı `127.0.0.1:8009` instance'ına yönlendirmesi gerekir. Böylece Shiny loopback'te kalırken tarayıcı ve Keycloak yalnız onaylı dış origin'i görür.

## Window 2 — gerçek URL'yi yalnız çalışma ortamında girin

Gerçek uygulama URL'sini source code, test, belge veya commit içine yazmayın:

```powershell
$env:MERGEN_BROWSER_UX_BASE_URL = Read-Host "Approved MERGEN base URL"
```

Değer, kullanıcının normalde SSO ile açtığı tam base URL olmalıdır. Alt yol varsa dahil edilir. Örnek biçim yalnız şemayı göstermek içindir: `https://app.example.invalid/base`.

Önce bu runtime URL altında smoke sayfasının ulaşıldığını doğrulayabilirsiniz:

```powershell
Invoke-WebRequest -UseBasicParsing ($env:MERGEN_BROWSER_UX_BASE_URL.TrimEnd('/') + '/smoke/ux-smoke.html')
```

404 alınırsa Window 1'in smoke-enabled instance olduğunu ve reverse proxy'nin `/smoke/` yolunu aynı 8009 instance'ına ilettiğini doğrulayın.

## SSO için ayrı Edge profili hazırlayın

```powershell
$smokeProfile = Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmoke"
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (!(Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
if (!(Test-Path $edge)) { throw "Microsoft Edge bulunamadi." }

& $edge "--user-data-dir=$smokeProfile" --no-first-run --no-default-browser-check $env:MERGEN_BROWSER_UX_BASE_URL
```

Açılan ayrı profilde normal SSO girişini tamamlayın ve uygulamanın aynı onaylı URL'ye döndüğünü doğrulayın. Sonra bu profile ait tüm Edge pencerelerini kapatın. Profil yalnız smoke içindir; repoya veya artifact'a koymayın.

## Yalnız browser UX smoke — hızlı kontrol

```powershell
$repo = "U:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
Set-Location $repo

$rscript = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
if (!(Test-Path $rscript)) { $rscript = "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" }
if (!(Test-Path $rscript)) { throw "R 4.6.0 Rscript.exe bulunamadi." }

$env:MERGEN_BROWSER_UX_BASE_URL = Read-Host "Approved MERGEN base URL"
$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmoke"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"

& $rscript --vanilla tests/scripts/ai_browser_ux_smoke.R --require-browser
Write-Host "Browser UX smoke exit code: $LASTEXITCODE"
```

Başarılı koşum `OK: rendered #status is UX_SMOKE_DONE:PASS.` ve çıkış kodu `0` üretir.

Koşucu gerçek base URL'yi çalışma sırasında kullanır ancak console/DOM/stderr artifact metinlerinde `<MERGEN_BROWSER_UX_BASE_URL>` olarak redakte eder.

## Tam VM evidence gate

Aynı Window 1 açıkken ve hazırlanmış Edge profilinin pencereleri kapalıyken:

```powershell
$env:MERGEN_BROWSER_UX_BASE_URL = Read-Host "Approved MERGEN base URL"
$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmoke"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"

& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
```

Test bittikten sonra Window 1'i durdurun ve uygulamayı `MERGEN_ENABLE_UX_SMOKE` olmadan normal biçimde yeniden başlatın.
