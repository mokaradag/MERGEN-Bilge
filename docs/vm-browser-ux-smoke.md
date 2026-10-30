# Windows VM browser UX smoke

Shiny normal topolojide **0.0.0.0:8009** üzerinde kalır; Edge, kullanıcıların normalde kullandığı onaylı reverse-proxy/SSO URL'sine gider. Yerel `127.0.0.1:8009` yalnız ön kontroldür, bind zorunluluğu değildir. SSO, JWT/state, Keycloak ve tarayıcı güvenlik ayarları değişmez.

Harness `tests/smoke/` altında kalır. Normal başlatmada hiçbir smoke yolu açılmaz. Ağda yalnız `MERGEN_ENABLE_UX_SMOKE=true`, `MERGEN_ALLOW_NETWORK_UX_SMOKE=true` ve `MERGEN_UX_SMOKE_PATH` birlikte geçerliyken kaynak kaydedilir. Önek tam olarak `__mergen_ux_` + 48 küçük hex karakteridir; koşucu bunu işletim sisteminin güvenli rastgele kaynağından 24 bayt (192 bit) ile üretir. Sabit `/smoke/` yalnız loopback yerel test uyumluluğudur. Rastgele yol yetkilendirme yerine geçmez: uygulamanın mevcut SSO/oturumu ve yetkileri kullanılmaya devam eder.

**Yaşam süresi:** Window 2 ortamı çalışan Window 1 sürecini değiştiremez. Bu nedenle normal uygulamayı durdurup aşağıdaki geçici smoke başlatmasını aynı `0.0.0.0:8009` üzerinde yapın. Koşucu `source('app.R')` sonrasında opt-in değerlerini uygular; `.Renviron` dosyasına hiçbir şey yazmaz. Önek yalnız kullanıcıya ait `%LOCALAPPDATA%\MERGEN\BrowserUxSmokeRun\prefix` dosyasında paylaşılır; URL veya kimlik bilgisi içermez. Aynı Windows hesabını kullanın. Süreç sona erince HTTP yolu kaybolur; normal çıkış/Ctrl+C yerel dosyayı da temizler. Zorla öldürmede kalan dizini, o smoke sürecinin durduğunu doğruladıktan sonra silin. Her yeni `--start-app` yeni önek üretir. Tek başlatma boyunca hızlı smoke ve tam gate aynı öneki kullanabilir.

## Window 1 — geçici smoke uygulaması

Normal 8009 uygulamasını durdurmadan önce aşağıdaki Rscript seçimini doğrulayın. Sonra uygulamayı kendi konsolundan/normal işletim yöntemiyle durdurup `--start-app` komutunu çalıştırın. Mevcut proxy/SSO yapılandırmasını değiştirmeyin.

```powershell
Set-Location "<repo>"
# run_mergen_prod.bat ile aynı seçim: override, en yeni kurulu R, PATH.
$rscript = $env:MERGEN_RSCRIPT
if (!$rscript -or !(Test-Path -LiteralPath $rscript -PathType Leaf)) {
    $rscript = Get-ChildItem 'C:\Program Files\R' -Directory -Filter 'R-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $version = [version]($_.Name -replace '^R-', '')
                $exe = Join-Path $_.FullName 'bin\Rscript.exe'
                if (Test-Path -LiteralPath $exe -PathType Leaf) { [pscustomobject]@{ Version = $version; Path = $exe } }
            } catch {}
        } | Sort-Object Version -Descending | Select-Object -First 1 -ExpandProperty Path
}
if (!$rscript) { $rscript = (Get-Command Rscript.exe -ErrorAction SilentlyContinue).Source }
if (!$rscript) { throw "Rscript.exe bulunamadi." }
& $rscript tests/scripts/run_vm_browser_ux_smoke.R --start-app
```

Komutu repo kökünden, normal launcher gibi `.Renviron` ve `.Rprofile` yüklemesi açık olarak çalıştırın; `--vanilla` / `--no-init-file` kullanmayın. Böylece projenin hazır `renv` kitaplığı ve normal paket yolları korunur. Koşucu ayrıca normal üretim R launcher'ı gibi repo `.Renviron` dosyasını `app.R` öncesinde yükler; `SSO_ENABLED=TRUE` yoksa veya uygulama SSO'yu etkinleştiremezse ağ dinleyicisini açmadan durur. Eksik SSO yapılandırmasını düzeltin; yerel kimlik doğrulamasına geçmeyin.

Bu komut ön planda bekler; uygulama **0.0.0.0:8009** dinler. Window 1'i test süresince açık bırakın. Test başlatmadan uygulamanın boot işlemini bitirmesini bekleyin.

## Window 2 — SSO için ayrı Edge profili

Gerçek hostname/URL repoya veya artifact'a yazılmaz. Her zaman çalışma anında alın; belge/test örneği yalnız `https://app.example.invalid/base` biçimindedir. Alt yol varsa base URL'ye ekleyin; sorgu/fragment eklemeyin. Ağ URL'si HTTPS olmalıdır; HTTP yalnız `localhost` ve `127.0.0.1` yerel testlerinde kabul edilir. IPv6 literal proxy adresleri bu VM prosedürünün desteklenen girdileri değildir.

`MERGEN_BROWSER_UX_BASE_URL`, `MERGEN_BROWSER_UX_PROFILE_DIR` ve `MERGEN_BROWSER_BIN` yalnız Window 2 ortamında tanımlanır; `.Renviron` / `Renviron.site` dosyalarında bunların eski tanımlarını kaldırın. R başlangıcında ortam dosyaları shell değerlerini ezebilir; aksi halde Read-Host ile seçilen origin yerine eski origin test edilir. Normal uygulama/SSO ayarlarını koruyun.

```powershell
Set-Location "<repo>"
# run_mergen_prod.bat ile aynı seçim: override, en yeni kurulu R, PATH.
$rscript = $env:MERGEN_RSCRIPT
if (!$rscript -or !(Test-Path -LiteralPath $rscript -PathType Leaf)) {
    $rscript = Get-ChildItem 'C:\Program Files\R' -Directory -Filter 'R-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $version = [version]($_.Name -replace '^R-', '')
                $exe = Join-Path $_.FullName 'bin\Rscript.exe'
                if (Test-Path -LiteralPath $exe -PathType Leaf) { [pscustomobject]@{ Version = $version; Path = $exe } }
            } catch {}
        } | Sort-Object Version -Descending | Select-Object -First 1 -ExpandProperty Path
}
if (!$rscript) { $rscript = (Get-Command Rscript.exe -ErrorAction SilentlyContinue).Source }
if (!$rscript) { throw "Rscript.exe bulunamadi." }
$env:MERGEN_BROWSER_UX_BASE_URL = Read-Host "Approved MERGEN base URL"
if (([uri]$env:MERGEN_BROWSER_UX_BASE_URL).Scheme -ne 'https') { throw "Network VM profile preparation requires HTTPS." }
$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmoke"
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (!(Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
if (!(Test-Path $edge)) { throw "Microsoft Edge bulunamadi." }
$env:MERGEN_BROWSER_BIN = $edge
& $rscript -e "source('tests/scripts/helpers_browser_ux_profile.R'); ux_smoke_check_edge_policy()"
if ($LASTEXITCODE -ne 0) { throw "Dedicated Edge profile policy check FAILED" }
& $edge "--user-data-dir=$env:MERGEN_BROWSER_UX_PROFILE_DIR" --no-first-run --no-default-browser-check $env:MERGEN_BROWSER_UX_BASE_URL
```

Ayrı profilde normal SSO girişini tamamlayın ve uygulamanın açıldığını doğrulayın. `edge://version` içindeki Profile path değerinin seçilen `BrowserUxSmoke` dizininin altında olduğunu doğrulayın; farklıysa testi durdurun. Zorunlu `UserDataDir` ilkesi varsa koşucu Edge açmadan durur; ilkeyi veya varsayılan profili değiştirmeyin. Sonra **bu profile ait Edge sürecinden tamamen çıkın**: tüm pencereleri ve varsa bildirim alanındaki arka plan Edge oturumunu kapatın. Görev Yöneticisi komut satırı sütununda bu `--user-data-dir` ile çalışan süreç kalmadığını doğrulayın; diğer profillerin süreçlerini sonlandırmayın. Yalnız son pencerenin kapanması, arka plan modu açıkken yeterli değildir. Profil repo/artifact dışında kalmalıdır. Token/cookie okunmaz, kopyalanmaz veya enjekte edilmez. Oturum geçerliyse bu hazırlığı her seferinde tekrarlamak gerekmez; SSO sayfasında kalan smoke başarısızdır.

## Yalnız browser UX smoke — hızlı kontrol

Aynı Window 2'de:

```powershell
& $rscript tests/scripts/run_vm_browser_ux_smoke.R
if ($LASTEXITCODE -ne 0) { throw "Browser UX smoke FAILED" }
```

Bu komut yalnız browser UX smoke çalıştırır. Yerel ön kontrol `http://127.0.0.1:8009/<per-run-prefix>/ux-smoke.html` üzerindedir; headless Edge ise onaylı runtime base URL + aynı önek + `/ux-smoke.html?autostart=1` kullanır. Proxy mevcut base altındaki rastgele kaynak yolunu aynı 8009 uygulamasına iletmelidir. HTTP 200, harness kaynağı, SSO yönlendirmesi veya exit 0 kanıt değildir. Başarı yalnız **`OK: rendered #status is UX_SMOKE_DONE:PASS.`** ile bildirilir. Ham DOM/HTTP gövdesi saklanmaz; DOM artifact'ı yalnız doğrulanmış PASS veya sabit başarısızlık özeti içerir. URL/önek, profil yolu ve runtime sırları tanı çıktılarında redakte edilir.

## Tam VM evidence gate

Window 1 açıkken, aynı Window 2'de:

```powershell
$env:MERGEN_EVIDENCE_PROFILE = "vm"
& $rscript tests/scripts/run_vm_evidence_gate.R --full
if ($LASTEXITCODE -ne 0) { throw "VM evidence gate FAILED" }
```

`MERGEN_BROWSER_UX_BASE_URL` ayarlıysa gate mevcut `browser_ux_smoke` adımında VM sarmalayıcısını kullanır ve browser zorunludur. `--full`, shell veya `.Renviron` içindeki `MERGEN_EVIDENCE_STEPS` filtresini bu koşum için yok sayar; dosya değiştirilmez. Tam mod ayrıca testthat başlangıç/bitiş aralığını yalnız çocuk oturumunda temizler ve File Store roundtrip/kullanıcı izolasyonu kontrollerini zorunlu açar. İstenen browser adımı uzun testlerden önce çalışır; tam gate öncesinde profil oturumu eskimişse normal SSO girişini yenileyip Edge sürecinden tamamen çıkın. Filtreli geliştirici koşumları `--full` olmadan desteklenir. Normal 13 adım korunur; tam kanıt için **13 passed, 0 failed, 0 skipped** gerekir. URL ayarlı değilse generic/cloud koşucu davranışı korunur.

## Normal moda dönüş

Window 1'de **Ctrl+C** ile geçici uygulamayı durdurun. Ardından normal launcher'ı kullanın; örneğin aynı repo kökünde:

```powershell
Remove-Item Env:MERGEN_ENABLE_UX_SMOKE,Env:MERGEN_ALLOW_NETWORK_UX_SMOKE,Env:MERGEN_UX_SMOKE_PATH -ErrorAction SilentlyContinue
& .\run_mergen_prod.bat
```

Normal `.Renviron` yapılandırması `MERGEN_HOST=0.0.0.0`, `MERGEN_PORT=8009` olarak kalır; smoke opt-in/önek değerlerini `.Renviron` içine **eklemeyin**. Window 2'de çalışma URL'sini/profil seçimini temizleyin (hazırlanmış profil silinmez):

```powershell
Remove-Item Env:MERGEN_BROWSER_UX_BASE_URL,Env:MERGEN_BROWSER_UX_PROFILE_DIR,Env:MERGEN_BROWSER_BIN,Env:MERGEN_EVIDENCE_PROFILE -ErrorAction SilentlyContinue
```

Zorla sonlandırma sonrası eski handshake varsa ve Window 1 artık çalışmıyorsa yalnız `Join-Path $env:LOCALAPPDATA "MERGEN\BrowserUxSmokeRun"` dizinini silin; hazırlanan `BrowserUxSmoke` profilini silmeyin.
