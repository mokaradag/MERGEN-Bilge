# Windows VM Evidence Gate — Son Doğrulama Durumu

Bu belge, MERGEN Bilge'nin en son **başarılı Windows VM evidence gate** koşumunu ve bu koşumun neyi kanıtlayıp neyi kanıtlamadığını kaydeder. Çalıştırma prosedürü ve sorun giderme için kanonik kaynak [`../RUNBOOK.md`](../RUNBOOK.md) olmaya devam eder.

## Son başarılı koşum

- **Tarih:** 18 Ağustos 2026
- **Profil:** `vm/vm`
- **Komut:** `Rscript --vanilla tests/scripts/run_vm_evidence_gate.R`
- **Sonuç:** `Toplam: 13 passed, 0 failed, 0 skipped`
- **Artifact dizini:** `artifacts/vm-evidence/20260818-163559`
- **Makine-okunur kanıt:** `artifacts/vm-evidence/20260818-163559/evidence.json`
- **Browser external-app URL:** `http://127.0.0.1:8009`
- **Browser smoke zorlaması:** `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true`
- **Browser virtual-time bütçesi:** `MERGEN_BROWSER_UX_VIRTUAL_TIME_MS=180000`
- **Kayıt kaynağı:** 18 Ağustos 2026 tarihli Windows VM konsol çıktısı ve operatör ekran görüntüsü

Koşum sonunda `OK: VM kanit kapisi basariyla tamamlandi.` mesajı alınmıştır.

## Geçen 13 adım

| Adım | Sonuç | Koşum süresi |
|---|---|---:|
| `env_config` | PASSED | 0.0 sn |
| `parse_sanity` | PASSED | 13.2 sn |
| `app_boot_smoke` | PASSED | 36.5 sn |
| `full_testthat` | PASSED | 511.3 sn |
| `maintainability_report` | PASSED | 15.8 sn |
| `frontend_ratchet` | PASSED | 1016.1 sn |
| `seam_doctor` | PASSED | 1.3 sn |
| `source_manifest_contracts` | PASSED | 10.7 sn |
| `ui_asset_manifest_contracts` | PASSED | 11.2 sn |
| `browser_ux_smoke` | PASSED | 234.0 sn |
| `vm_preflight_real` | PASSED | 74.5 sn |
| `db_encoding_preflight` | PASSED | 47.7 sn |
| `renv_status` | PASSED | 0.0 sn |

Süreler, 18 Ağustos 2026 tarihli konsol çıktısında görülen koşum süreleridir; başka VM koşumlarında değişebilir.

## Browser UX smoke koşumu

Son başarılı gate, zaten çalışan uygulamaya external-app modunda bağlandı:

```powershell
$env:MERGEN_EVIDENCE_PROFILE = "vm"
$env:MERGEN_BROWSER_UX_BASE_URL = "http://127.0.0.1:8009"
$env:MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"
$env:MERGEN_BROWSER_UX_VIRTUAL_TIME_MS = "180000"
& $rscript --vanilla tests/scripts/run_vm_evidence_gate.R
```

`MERGEN_BROWSER_UX_BASE_URL` çalışmakta olan uygulamanın gerçek yerel URL'siyle eşleşmelidir. 18 Ağustos 2026 koşumunda uygulama `8009` portunda çalışıyordu. Yavaş VM için browser UX virtual-time bütçesi `180000` ms olarak ayarlanmıştı.

## Bu koşum neyi kanıtlar?

Aynı Windows VM koşumunda aşağıdaki kapıların başarısız veya atlanmış adım olmadan tamamlandığını kanıtlar:

- kaynakların parse edilebilmesi ve uygulama boot smoke,
- tam izole `testthat` suite'i,
- maintainability ve frontend ratchet kontrolleri,
- seam doctor ile kaynak ve UI varlık sözleşmeleri,
- zorunlu gerçek browser UX smoke,
- gerçek VM preflight,
- DB encoding preflight,
- `renv` durum kontrolü.

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

`artifacts/vm-evidence/<timestamp>/evidence.json` yerel/on-prem doğrulama artifact'ıdır. Dokümantasyonda artifact yolu ve sonucu kaydedilebilir; gerçek secret, API anahtarı, token, parola, DSN veya özel endpoint değeri repoya eklenmez. Yeni bir tam VM evidence gate koşumu `13 passed, 0 failed, 0 skipped` ile başarıyla tamamlandığında bu belge, README ve RUNBOOK içindeki **son başarılı koşum** bilgileri birlikte güncellenmelidir.
