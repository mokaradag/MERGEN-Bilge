# Windows VM Evidence Gate — Son Doğrulama Durumu

Bu belge, MERGEN Bilge'nin en son **başarılı Windows VM evidence gate** koşumunu ve bu koşumun neyi kanıtlayıp neyi kanıtlamadığını kaydeder. Çalıştırma prosedürü ve sorun giderme için kanonik kaynak [`../RUNBOOK.md`](../RUNBOOK.md) olmaya devam eder.

## Son başarılı koşum

- **Tarih:** 4 Kasım 2026
- **Profil (istenen/etkin):** `vm/vm`
- **Komut:** `run_vm_evidence_gate.R --full` (VM profili ve aynı R oturumu açıkça seçilerek)
- **Sonuç:** `Toplam: 13 passed, 0 failed, 0 skipped`
- **Artifact dizini:** `artifacts/vm-evidence/20261104-152408`
- **Makine-okunur kanıt:** `artifacts/vm-evidence/20261104-152408/evidence.json`
- **Browser UX topolojisi:** normal **0.0.0.0:8009** uygulama topolojisi + onaylı reverse-proxy/SSO origin + ayrı Edge profili
- **Kayıt kaynağı:** 4 Kasım 2026 tarihli, uygulamayı çalıştıran Windows VM'nin konsol çıktısı ve operatör ekran görüntüsü

Koşum sonunda `OK: VM kanıt kapısı başarıyla tamamlandı.` mesajı alınmıştır. Ekran görüntüsü çalıştırılan Git commit SHA'sını göstermediğinden bu kayıt belirli bir commit'e atfedilmez. Bu tarihli operasyonel kanıt, yalnız 4 Kasım'da çalıştırılan kodda browser UX smoke dahil 13 zorunlu adımın aynı Windows VM koşumunda başarısız veya atlanmış adım olmadan tamamlandığını gösterir. Sonraki commit'lerin veya güncel HEAD'in aynı kod olduğunu kanıtlamaz; commit'e atfedilebilir yeni kanıt için VM koşumu tekrarlanmalıdır. Koşum öncesinde beklenen tam Git HEAD doğrulanmalı, Window 1 uygulama başlangıcı ve gate başlangıcı temiz checkout üzerinde yapılmalı, koşum sonunda aynı SHA ve temiz ağaç yeniden doğrulanmalıdır. Yeni artifact içinde `git.sha` beklenen tam SHA olmalı, `git.dirty` `false`, `git.commit_attributed` `true` olmalı; `git.before` ve `git.after` aynı temiz checkout kimliğini doğrulamalıdır. `--full` bu koşulları sağlayamazsa başarısız olur. `git.commit_attributed` yalnız `--full` ve doğrulanmış temiz/eşleşen checkout birlikteyken `true` olur; filtreli/geliştirici koşumlarında `false` kalır. Filtreli/geliştirici koşumunda `overall_status = "passed"` tek başına commit atfı değildir; Git inceleme hatası da temiz checkout sayılmaz.

**Kaynak ZIP koşumu:** `.git` içermeyen GitHub kaynak ZIP'i desteklenen VM test girdisidir. Bu durumda Git çalıştırılmaz; `--full` dahil tüm adımlar normal biçimde koşar ve sonuç yalnız adımların kendi PASS/FAIL durumuna bağlıdır. `vm` profilinin `renv_status` adımı açılmış ağaçta VM'de üretilip onaylanmış `renv.lock` dosyasını yine ister. Artifact `git.metadata_available = false`, `git.commit_attributed = false`, boş `git.sha` taşır; SHA uydurulmaz. Böyle bir PASS, çalışan runtime/browser adımlarının kanıtıdır ama tam Git commit'ine atfedilemez. `.git` varsa yukarıdaki temiz/eşleşen checkout koşulları aynen geçerlidir.

## Kaynak SHA ve üretim kilidi sınırı

Bu GitHub ağacında `renv.lock` yoktur; `RENV_LOCK_STATUS.md`, kilidin ayrı Windows VM üretim deposunda commit edildiğini bildirir. `vm` profilinin `renv_status` adımı gerçek kilidi ister. Kilidi bu checkout'a kopyalamak izlenmeyen/değişmiş dosya üretir ve temiz-checkout kapısını düşürür. Gate ayrıca kullanılan `renv.lock` dosyasının `HEAD` içinde izlendiğini doğrular; yerel exclude/global ignore ile gizlenip `git status` çıktısını temiz gösteren kilit atıf almaz ve Git checkout'undaki `--full` koşumunu `checkout_identity` ile düşürür. Mevcut akış, dışarıdan sağlanan kilidi kaynak SHA korunurken ayrıca tasdik eden bir mekanizma sunmaz. Dolayısıyla kilit içermeyen bu PR SHA'sı için **tam, commit'e atfedilebilir VM PASS elde edilemez**; yalnız koşumu tekrarlamak bu eksikliği gidermez.

Tam VM doğrulaması için onaylı Windows VM üretim checkout'unda hem incelenen düzeltmeler hem de VM'de üretilip gözden geçirilmiş, commit edilmiş `renv.lock` bulunmalıdır. Window 1'i başlatmadan önce `git cat-file -e HEAD:renv.lock`, `git rev-parse HEAD` ve `git status --porcelain` ile kilidin commit'te olduğunu, tam SHA'yı ve temizliği doğrulayın. Sonra iki-pencere prosedürünü ve aşağıdaki tam gate komutunu **aynı checkout'ta** uygulayın. `evidence.json` o üretim commit'inin SHA'sını taşımalıdır; kilit eklenmesi farklı commit oluşturursa bu sonuç PR'ın kilitsiz SHA'sına atfedilemez. İncelenen kaynak SHA ile üretim SHA'sının ilişkisini ve kilidin VM kökenini ayrıca kaydedin; tarihsel 31 Ekim kaydının SHA'sını bu bilgilerden çıkarsamayın.

Kilit Linux/cloud ortamında üretilmez. Kopyalanan kilidi Git exclude/ignore ile gizlemek, temizliği veya `renv_status` adımını gevşetmek desteklenen bir kanıt yöntemi değildir. Kilit üretimi ve commit politikası için [`dependency-locking.md`](dependency-locking.md) ve [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) geçerlidir. Kilitsiz checkout'ta başarılı hızlı browser kontrolü, tam 13 adımlı VM gate sonucu değildir.

## Geçen 13 adım

| Adım | Sonuç | Koşum süresi |
|---|---|---:|
| `browser_ux_smoke` | PASSED | 53.9 sn |
| `env_config` | PASSED | 0.0 sn |
| `parse_sanity` | PASSED | 39.1 sn |
| `app_boot_smoke` | PASSED | 70.6 sn |
| `full_testthat` | PASSED | 6989.0 sn |
| `maintainability_report` | PASSED | 34.2 sn |
| `frontend_ratchet` | PASSED | 566.8 sn |
| `seam_doctor` | PASSED | 0.9 sn |
| `source_manifest_contracts` | PASSED | 9.2 sn |
| `ui_asset_manifest_contracts` | PASSED | 7.1 sn |
| `vm_preflight_real` | PASSED | 112.6 sn |
| `db_encoding_preflight` | PASSED | 83.1 sn |
| `renv_status` | PASSED | 0.0 sn |

Süreler, 4 Kasım 2026 tarihli operatör ekran görüntüsünde görülen koşum süreleridir; başka VM koşumlarında değişebilir.

### Önceki başarılı koşum (tarihsel kayıt)

31 Ekim 2026 koşumu da `vm/vm` profiliyle `13 passed, 0 failed, 0 skipped` sonucunu vermişti: `artifacts/vm-evidence/20261031-121259/evidence.json`. O koşumdaki `browser_ux_smoke` süresi 35.0 sn idi. Bu eski kayıt korunur, ancak en son başarılı koşum 4 Kasım 2026 tarihli kayıttır. Her iki ekran görüntüsünde de Git commit SHA'sı gösterilmediği için bu operasyonel kanıtlar belirli bir PR HEAD'ine atfedilmez.

## Browser UX smoke koşumu

4 Kasım koşumu, o gün çalıştırılan normal-topoloji akışını kullanmıştır: Shiny **0.0.0.0:8009** üzerinde çalışır; browser kanıtı onaylı reverse-proxy/SSO origin üzerinden, repo/artifact ağacı dışında hazırlanmış ayrı Edge profiliyle alınır. Yerel `127.0.0.1:8009` yalnız ön kontroldür; bind gereksinimi değildir.

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

Bu sonuç, 4 Kasım'da çalıştırılan kod için gerçek Windows VM + Keycloak/SSO + Edge akışının başarıyla tamamlandığına dair operasyonel kanıttır. Daha sonraki startup zamanlaması, completion frame ve çocuk süreç seçimi değişiklikleri dahil sonraki commit'ler için yeni VM koşumu gerekir.

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
