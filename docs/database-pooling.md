# Veritabanı Bağlantı Havuzu (İşlem-Güvenli)

Bu belge, MERGEN Bilge'nin **opsiyonel, işlem-güvenli (transaction-safe)
veritabanı bağlantı havuzu** katmanını açıklar. Katman `R/helpers_db_pool.R`
içindedir ve `pool` paketi üzerine kurulur.

İlgili dosyalar:

- Havuz katmanı: `R/helpers_db_pool.R`
- Doğrudan bağlantı/serbest bırakma/worker bağlantısı: `R/helpers_db_connection.R`
- Encoding sözleşmesi: `R/helpers_db_encoding.R`
- İşlem yazımı (migrasyon edilen site): `R/helpers_db_chat_mutations.R::save_message_to_db()`
- Yaşam döngüsü: `app.R` (`onStart` → `init_db_pool_once`, `onStop` → `close_db_pool_once`)
- Testler: `tests/testthat/test-db-pool-behavior.R`,
  `tests/scripts/soak_interactive_lane.R`

---

## 1. Neden havuz?

Havuzlama olmadan `get_connection()` **her çağrıda** yeni bir doğrudan ODBC
bağlantısı açar ve kapatır. Mesaj sonlandırma (`finalize_stream_message()`) tek
bir bitmiş mesaj için ana Shiny event loop'unda bir DİZİ senkron DB işlemi
çalıştırır (`ensure_chat_ready`, `log_ai_usage`, `save_message_to_db`,
`update_message_reasoning_content`, `saved_chats_data$refresh`). Eşzamanlılık
altında bu bağlan/kapan döngüleri tek thread'de serileşir.

Havuz, bağlantıları yeniden kullanarak bu bağlantı kurma/kapatma maliyetini
azaltır.

---

## 2. İşlem-güvenlik sözleşmesi (KRİTİK)

`save_message_to_db()` çok-ifadeli bir işlem çalıştırır
(`dbBegin`/`dbGetQuery`/`dbCommit`, `MessageOrder` için `UPDLOCK/HOLDLOCK`).

**Naif bir global `pool::dbPool` GÜVENSİZDİR:** bir `Pool` nesnesi üzerinde her
ifade FARKLI bir bağlantıya checkout edilebilir, dolayısıyla `dbBegin(pool)`
işlemi ifadeler arasında tutamaz. Eski kod yalnızca `pool` her zaman `NULL`
olduğu için doğruydu.

Bu katman bunu şöyle çözer:

- **Okuma yolları** havuz nesnesini güvenle kullanabilir (`dbGetQuery(pool, ...)`
  tek-ifade; havuz checkout/return'ü kendi yapar). `init_db_pool_once()` havuz
  nesnesini `.GlobalEnv$pool`'a yazar ve değiştirilmemiş `get_connection()` bunu
  döndürür.
- **İşlem yolları** havuz nesnesini ASLA bağlantı gibi kullanmaz.
  `db_acquire_tx_connection()` gerçek bir bağlantıyı `pool::poolCheckout()` ile
  ödünç alır; işlem bittiğinde (commit/rollback SONRASI) `pool::poolReturn()` ile
  iade eder. `save_message_to_db()` bu yolu kullanır ve rollback'i **iadeden
  önce** çalıştırır (`on.exit(..., after = FALSE)`), böylece açık işlemle havuza
  dönüş engellenir.
- `worker_save_assistant_response()` ayrı süreçte (future worker) çalışır; orada
  havuz yoktur, bu yüzden doğrudan `worker_db_connect()` kullanmaya devam eder.

---

## 3. Genel API

| Fonksiyon | Görev |
|-----------|-------|
| `is_db_pool_enabled()` | `MERGEN_DB_POOL_ENABLED` (env) → `mergen.db.pool_enabled` (option) → `FALSE`. |
| `db_pool_config()` | Boyut/idle/validation yapılandırması (korumacı varsayılanlar). |
| `init_db_pool_once(target, factory, force)` | Havuzu BİR KEZ kurar (kapalıysa no-op; `force` ile zorlanır; `factory` testlerde SQLite havuzu enjekte eder). Başarısızlık boot'u kırmaz. |
| `close_db_pool_once(target)` | Havuzu/havuzları temiz kapatır; `.GlobalEnv$pool`'u temizler. |
| `db_pool_get(target)` / `db_pool_is_active(target)` | Aktif havuz nesnesi / aktiflik. |
| `with_db_connection(fn, target)` | Salt-okunur: ödünç al → `fn(conn)` → her durumda iade. |
| `with_db_transaction(fn, target)` | İşlem: gerçek checkout → `dbBegin` → `fn(conn)` → `dbCommit`; hatada rollback + yeniden fırlat; her durumda iade. |
| `db_acquire_tx_connection(target)` / `db_release_tx_connection(ci)` | İşlem-güvenli edinme/iade (havuz yoksa doğrudan bağlantıya düşer). |
| `db_pool_status_snapshot()` | Secret-safe durum: enabled, config, free/taken, checkout/return/leak, tx sayaçları. Ham DSN/secret İÇERMEZ. |

---

## 4. Yapılandırma (ortam değişkenleri)

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `MERGEN_DB_POOL_ENABLED` | `FALSE` | Havuzu açar. Kapalıyken davranış birebir eski doğrudan-bağlantı yoludur. |
| `MERGEN_DB_POOL_MIN_SIZE` | `1` | Minimum havuz boyutu. |
| `MERGEN_DB_POOL_MAX_SIZE` | `8` | Maksimum havuz boyutu. |
| `MERGEN_DB_POOL_IDLE_TIMEOUT` | `600` | Boşta bağlantı zaman aşımı (sn). |
| `MERGEN_DB_POOL_VALIDATION_INTERVAL` | `60` | Bağlantı doğrulama aralığı (sn). |

Varsayılanlar bilinçli olarak korumacıdır (tek Shiny süreci + SQL Server için
makul). Encoding sözleşmesi havuzda da korunur: `init_db_pool_once()` üretim
ODBC havuzunu `encoding = .DEFAULT_DB_CLIENT_ENCODING`,
`name_encoding = .DEFAULT_DB_NAME_ENCODING` ile kurar; yani
`DB_CLIENT_ENCODING=WINDOWS-1254` / `DB_NAME_ENCODING=WINDOWS-1254` Türkçe
ayarları havuzlu bağlantılara da uygulanır.

---

## 5. Test ve kanıt

- **Offline davranış testi:** `tests/testthat/test-db-pool-behavior.R` gerçek
  RSQLite arka ucuna karşı enable/disable, init/close once, `with_db_connection`
  ödünç/iade (sızıntı yok), `with_db_transaction` commit/rollback, işlem yalıtımı,
  Türkçe/UTF-8 round-trip, gerçek-checkout (havuz nesnesi değil) ve secret-safe
  snapshot sözleşmelerini doğrular.
- **Etkileşimli soak kanıtı:** `tests/scripts/soak_interactive_lane.R` havuzu
  tekrar yük altında çalıştırır ve `soak_evidence.json`'a checkout==return,
  `outstanding_checkouts=0`, commit/rollback sayaçları ve oturumlar-arası izolasyon
  kanıtı yazar. Bkz. [`operational-soak-gate.md`](operational-soak-gate.md).

Bu testler **gerçek SQLite** kullanır; üretim **SQL Server T-SQL** davranışını ve
at-rest Türkçe encoding'i kanıtlamaz.

---

## 6. Windows VM / SQL Server doğrulaması (yapılması gereken)

Havuz bulutta/offline test edilmiştir; üretim VM'de SQL Server'a karşı henüz
doğrulanmamıştır. VM'de açmadan önce:

1. `.Renviron`'da `MERGEN_DB_POOL_ENABLED=TRUE` ayarlayın ve tam R sürecini
   yeniden başlatın (tarayıcı yenileme yeterli değildir).
2. `DB_CLIENT_ENCODING=WINDOWS-1254` ve `DB_NAME_ENCODING=WINDOWS-1254`
   ayarlarının korunduğunu teyit edin.
3. `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` ile
   `tests/scripts/run_vm_encoding_preflight_real.R` çalıştırın; transactional
   yeni-yazım probe'unun rollback ettiğini doğrulayın.
4. SSMS'te en yeni `MB_Messages`/`MB_Chats` satırlarının Türkçe açısından temiz
   olduğunu (mojibake yok) teyit edin.
5. Canlı uygulamaya attach soak sınır koşumunu (24/26/28 kullanıcı) havuz
   açık/kapalı olarak yeniden ölçüp gerçek-sohbet kapasite farkını gözlemleyin.

Bu adımlar geçene kadar havuzu üretimde kalıcı açmayın.
