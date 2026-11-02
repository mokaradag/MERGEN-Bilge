# Windows VM Evidence Gate — Son Doğrulama Durumu

Bu belge, MERGEN Bilge'nin en son **başarılı Windows VM evidence gate** koşumunu ve bu koşumun neyi kanıtlayıp neyi kanıtlamadığını kaydeder. Çalıştırma prosedürü ve sorun giderme için kanonik kaynak [`../RUNBOOK.md`](../RUNBOOK.md) olmaya devam eder.

## Son başarılı koşum

- **Tarih:** 31 Ekim 2026
- **Profil (istenen/etkin):** `vm/vm`
- **Komut:** `run_vm_evidence_gate.R --full` (VM profili ve aynı R oturumu açıkça seçilerek)
- **Sonuç:** `Toplam: 13 passed, 0 failed, 0 skipped`
- **Artifact dizini:** `artifacts/vm-evidence/20261031-121259`
- **Makine-okunur kanıt:** `artifacts/vm-evidence/20261031-121259/evidence.json`
- **Browser UX topolojisi:** normal **0.0.0.0:8009** uygulama topolojisi + onaylı reverse-proxy/SSO origin + ayrı Edge profili
- **Kayıt kaynağı:** 31 Ekim 2026 tarihli Windows VM konsol çıktısı ve operatör ekran görüntüsü

Koşum sonunda `OK: VM kanıt kapısı başarıyla tamamlandı.` mesajı alınmıştır. Ekran görüntüsü çalıştırılan Git commit SHA'sını göstermediğinden bu kayıt belirli bir commit'e atfedilmez. Bu tarihli operasyonel kanıt, yalnız 31 Ekim'de çalıştırılan kodda browser UX smoke dahil 13 zorunlu adımın aynı Windows VM koşumunda başarısız veya atlanmış adım olmadan tamamlandığını gösterir. Sonraki commit'lerin veya güncel HEAD'in aynı kod olduğunu kanıtlamaz; commit'e atfedilebilir yeni kanıt için VM koşumu tekrarlanmalıdır. Koşum öncesinde beklenen tam Git HEAD doğrulanmalı, Window 1 uygulama başlangıcı ve gate başlangıcı temiz checkout üzerinde yapılmalı, koşum sonunda aynı SHA ve temiz ağaç yeniden doğrulanmalıdır. Yeni artifact içinde `git.sha` beklenen tam SHA olmalı, `git.dirty` `false`, `git.commit_attributed` `true` olmalı; `git.before` ve `git.after` aynı temiz checkout kimliğini doğrulamalıdır. `--full` bu koşulları sağlayamazsa başarısız olur. Filtreli/geliştirici koşumunda `overall_status = "passed"` tek başına commit atfı değildir; Git inceleme hatası da temiz checkout sayılmaz.

## Geçen 13 adım

| Adım | Sonuç | Koşum süresi |
|---|---|---:|
| `browser_ux_smoke` | PASSED | 35.0 sn |
| `env_config` | PASSED | 0.0 sn |
| `parse_sanity` | PASSED | 11.6 sn |
| `app_boot_smoke` | PASSED | 61.1 sn |
| `full_testthat` | PASSED | 4507.9 sn |
| `maintainability_report` | PASSED | 9.7 sn |
| `frontend_ratchet` | PASSED | 488.9 sn |
| `seam_doctor` | PASSED | 0.8 sn |
| `source_manifest_contracts` | PASSED | 8.7 sn |
| `ui_asset_manifest_contracts` | PASSED | 6.7 sn |
| `vm_preflight_real` | PASSED | 79.3 sn |
| `db_encoding_preflight` | PASSED | 59.4 sn |
| `renv_status` | PASSED | 0.0 sn |

Süreler, 31 Ekim 2026 tarihli operatör ekran görüntüsünde görülen koşum süreleridir; başka VM koşumlarında değişebilir.

## Browser UX smoke koşumu

31 Ekim koşumu, o gün çalıştırılan normal-topoloji akışını kullanmıştır: Shiny **0.0.0.0:8009** üzerinde çalışır; browser kanıtı onaylı reverse-proxy/SSO origin üzerinden, repo/artifact ağacı dışında hazırlanmış ayrı Edge profiliyle alınır. Yerel `127.0.0.1:8009` yalnız ön kontroldür; bind gereksinimi değildir.

Gerçek hostname, SSO URL'si, profil yolu, cookie/token veya başka kimlik bilgileri bu belgeye ya da artifact özetine yazılmaz. Güncel hazırlık, çalışma ve temizlik adımları için [VM browser UX smoke](vm-browser-ux-smoke.md) belgesini izleyin.

Tam gate için kanonik komut biçimi:

```powershell
& $rscript -e "Sys.setenv(MERGEN_EVIDENCE_PROFILE='vm', MERGEN_RSCRIPT_BIN=file.path(R.home('bin'), 'Rscript.exe')); source('tests/scripts/run_vm_evidence_gate.R', encoding='UTF-8')" --full
```

`--full`, adım filtresini yok sayar ve 13 adımın tamamında PASS ister. `browser_ux_smoke` yalnız HTTP erişilebilirliği, kaynak literal'i, SSO redirect'i, SKIP veya exit 0 ile geçmez; işlenmiş browser sonucu gerçek PASS olmalıdır.

## Bu koşum neyi kanıtlar?

Aynı Windows VM koşumunda aşağıdaki kapıların başarısız veya atlanmış adım olmadan tamamlandığını kanıtlar:

- kaynakların parse edilebilmesi ve uygulama boot smoke,
- tam dosya-izole `testthat` suite'i ve Windows çocuk `Rscript.exe` koşumu,
- maintainability ve frontend ratchet kontrolleri,
- seam doctor ile kaynak ve UI varlık sözleşmeleri,
- normal **0.0.0.0:8009** + onaylı SSO/reverse-proxy yolu üzerinden zorunlu gerçek browser UX smoke,
- gerçek VM preflight,
- DB encoding preflight,
- `renv` durum kontrolü.

Bu sonuç, 31 Ekim'de çalıştırılan kod için gerçek Windows VM + Keycloak/SSO + Edge akışının başarıyla tamamlandığına dair operasyonel kanıttır. Daha sonraki startup zamanlaması, completion frame ve çocuk süreç seçimi değişiklikleri dahil sonraki commit'ler için yeni VM koşumu gerekir.

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
