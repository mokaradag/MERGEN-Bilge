# Windows VM Evidence Gate — Son Doğrulama Durumu

Bu belge, MERGEN Bilge'nin en son **başarılı Windows VM evidence gate** koşumunu ve bu koşumun neyi kanıtlayıp neyi kanıtlamadığını kaydeder. Çalıştırma prosedürü ve sorun giderme için kanonik kaynak [`../RUNBOOK.md`](../RUNBOOK.md) olmaya devam eder.

## Son başarılı koşum

- **Tarih:** 17 Ekim 2026
- **Profil (istenen/etkin):** `<auto>/vm`
- **Komut:** `Rscript --vanilla tests/scripts/run_vm_evidence_gate.R`
- **Sonuç:** `Toplam: 13 passed, 0 failed, 0 skipped`
- **Artifact dizini:** `artifacts/vm-evidence/20261017-061049`
- **Makine-okunur kanıt:** `artifacts/vm-evidence/20261017-061049/evidence.json`
- **Browser external-app URL:** `http://127.0.0.1:28081`
- **Browser smoke zorlaması:** `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true`
- **Kayıt kaynağı:** 17 Ekim 2026 tarihli Windows VM konsol çıktısı ve operatör ekran görüntüsü

Koşum sonunda `OK: VM kanit kapisi basariyla tamamlandi.` mesajı alınmıştır. Ekran görüntüsü çalıştırılan Git commit SHA'sını göstermediğinden bu kayıt belirli bir commit'e atfedilmez. Bu yeniden doğrulama, normal RStudio `testthat` koşumundan ayrı olarak evidence gate'in dosya-izole çocuk `Rscript.exe` zincirinin de Windows VM üzerinde uçtan uca tamamlandığını gösterir.

## Geçen 13 adım

| Adım | Sonuç | Koşum süresi |
|---|---|---:|
| `env_config` | PASSED | 0.0 sn |
| `parse_sanity` | PASSED | 12.3 sn |
| `app_boot_smoke` | PASSED | 59.8 sn |
| `full_testthat` | PASSED | 4159.8 sn |
| `maintainability_report` | PASSED | 9.8 sn |
| `frontend_ratchet` | PASSED | 491.8 sn |
| `seam_doctor` | PASSED | 1.2 sn |
| `source_manifest_contracts` | PASSED | 8.2 sn |
| `ui_asset_manifest_contracts` | PASSED | 6.6 sn |
| `browser_ux_smoke` | PASSED | 171.3 sn |
| `vm_preflight_real` | PASSED | 73.2 sn |
| `db_encoding_preflight` | PASSED | 59.2 sn |
| `renv_status` | PASSED | 0.0 sn |

Süreler, 17 Ekim 2026 tarihli operatör ekran görüntüsünde görülen yaklaşık koşum süreleridir; başka VM koşumlarında değişebilir.

## Browser UX smoke koşumu

Son başarılı gate, zaten çalışan uygulamaya external-app modunda bağlandı:

```powershell
Remove-Item Env:\MERGEN_EVIDENCE_STEPS -ErrorAction SilentlyContinue
$env:MERGEN_BROWSER_UX_BASE_URL = "http://127.0.0.1:28081"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"
& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
```

`MERGEN_BROWSER_UX_BASE_URL` çalışmakta olan uygulamanın gerçek yerel URL'siyle eşleşmelidir. 17 Ekim 2026 koşumunda uygulama `28081` portunda çalışıyordu. Profil ayrıca zorlanmadı; gate çıktısında istenen/etkin profil `<auto>/vm` olarak raporlandı.

## Bu koşum neyi kanıtlar?

Aynı Windows VM koşumunda aşağıdaki kapıların başarısız veya atlanmış adım olmadan tamamlandığını kanıtlar:

- kaynakların parse edilebilmesi ve uygulama boot smoke,
- tam dosya-izole `testthat` suite'i ve Windows çocuk `Rscript.exe` koşumu,
- maintainability ve frontend ratchet kontrolleri,
- seam doctor ile kaynak ve UI varlık sözleşmeleri,
- zorunlu gerçek browser UX smoke,
- gerçek VM preflight,
- DB encoding preflight,
- `renv` durum kontrolü.

Bu sonuç, daha önce yalnızca evidence gate'in izole çocuk süreçlerinde görülen Windows/locale kaynaklı `exit=1033` sonlanmalarının son koşumda tekrarlanmadığını da operasyonel olarak doğrular; testlerin güvenlik veya doğruluk beklentileri gevşetilmeden gate tamamlanmıştır.

## Bu koşum neyi tek başına kanıtlamaz?

Bu evidence gate sonucu aşağıdaki alanların otomatik kanıtı değildir:

- uzun süreli gerçek kullanıcı yükü veya kapasite sınırı,
- gerçek upstream LLM throughput'u,
- uzun süreli browser/websocket eşzamanlılığı,
- bütün kırılgan kullanıcı akışlarının manuel QA'sı,
- geçmişte oluşmuş legacy mojibake satırlarının temizlenmiş olması,
- ayrı soak, post-deploy veya saha kabul testlerinin başarıyla tamamlanmış olması.

Yük ve dayanıklılık kanıtı için [`operational-soak-gate.md`](operational-soak-gate.md), operasyonel çalışma adımları için [`../RUNBOOK.md`](../RUNBOOK.md) izlenmelidir.

## Kanıt disiplini

`artifacts/vm-evidence/<timestamp>/evidence.json` yerel/on-prem doğrulama artifact'ıdır. Dokümantasyonda artifact yolu ve sonucu kaydedilebilir; gerçek secret, API anahtarı, token, parola, DSN veya özel endpoint değeri repoya eklenmez. Yeni bir tam VM evidence gate koşumu `13 passed, 0 failed, 0 skipped` ile başarıyla tamamlandığında bu belge güncellenmeli; README ve RUNBOOK içindeki son başarılı koşum referansları da bu kanonik kayıtla uyumlu tutulmalıdır.
