# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-contract.R
# Açıklama: Faz 6 (§5.10) — MİMARİ SÖZLEŞME testleri (statik). Davranış testleri
#           ayrı dosyalardadır; burada offline olarak çalıştırılamayan yapısal
#           sınırlar dondurulur.
#
# Dosya taramaları Windows VM güvenliği için BAYT-GÜVENLİ okuyucu deseniyle
# yapılır (readBin + iconv(sub = "byte") + grepl(useBytes = TRUE)); Türkçe
# yorumlu dosyalarda düz `readLines(encoding = "UTF-8")` VM'de `invalid UTF-8`
# ile kırılır (CLAUDE.md renv/tarama kuralı).
# ==============================================================================

.pk_async_read_bytes <- function(path) {
  ham <- readBin(path, what = "raw", n = file.info(path)$size %||% 0L)
  iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.pk_async_has <- function(text, needle) {
  isTRUE(grepl(needle, text, fixed = TRUE, useBytes = TRUE))
}

.pk_async_repo <- function() resolve_repo_root_for_tests()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

test_that("Faz 6 dosyaları var ve manifestte DOĞRU SIRADA yer alır", {
  kok <- .pk_async_repo()

  faz6 <- c(
    "R/helpers_pk_async_cancel.R",
    "R/helpers_pk_exec_context.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_snapshot_validate.R",
    "R/helpers_pk_async_snapshot.R",
    "R/helpers_pk_async_probe.R",
    "R/helpers_pk_async_plan.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_async_worker.R",
    "R/helpers_pk_worker_observers.R",
    "R/helpers_pk_worker_direct_exit.R",
    "R/helpers_deep_analysis_sql.R",
    "R/helpers_deep_analysis_reconcile.R",
    "R/helpers_deep_analysis_phase6.R",
    "R/helpers_pk_async_session_registry.R",
    "R/helpers_pk_async_lifecycle.R",
    "R/helpers_pk_async_apply.R",
    "R/server_handler_pk_async.R"
  )
  for (dosya in faz6) {
    expect_true(file.exists(file.path(kok, dosya)), info = dosya)
  }

  expect_source_manifest_contains_for_tests(faz6)

  # Bağımlılık sırası: iptal/son tarih -> boyut -> tavan -> önbellek ->
  # sınırlı SQL -> istek anlık görüntüsü -> işçi.
  expect_source_manifest_order_for_tests(c(
    "R/helpers_pk_config.R",
    "R/helpers_pk_async_cancel.R",
    "R/helpers_pk_exec_context.R",
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_snapshot_validate.R",
    "R/helpers_pk_async_snapshot.R",
    "R/helpers_pk_async_probe.R",
    "R/helpers_pk_async_plan.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_async_worker.R"
  ))

  # Uzlaştırma katmanı bağlam kurucudan ve orkestratörden ÖNCE yüklenmelidir.
  expect_source_manifest_order_for_tests(c(
    "R/helpers_deep_analysis_sql.R",
    "R/helpers_deep_analysis_reconcile.R",
    "R/helpers_deep_analysis_context.R",
    "R/helpers_deep_analysis.R"
  ))

  # Gönderim işleyicisi send_message'dan ÖNCE yüklenmelidir (o buna delege eder).
  expect_source_manifest_order_for_tests(c(
    "R/helpers_pk_async_session_registry.R",
    "R/helpers_pk_async_lifecycle.R",
    "R/helpers_pk_async_apply.R",
    "R/server_handler_pk_async.R",
    "R/server_send_message.R"
  ))
})

test_that("gönderim explicit-mode kullanır ve auto taramaya DÜŞMEZ", {
  metin <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/server_handler_pk_async.R"))

  expect_true(.pk_async_has(metin, 'dependency_mode = "explicit"'))
  expect_false(.pk_async_has(metin, 'dependency_mode = "auto"'))
  # Ham `promises::future_promise()` KULLANILMAZ (CLAUDE.md 8A): izleme +
  # bağımlılık taşıma sözleşmesi tracked_future_promise üzerindendir.
  # (Alt dize kontrolü YAPILMAZ: "future_promise(" zaten
  # "tracked_future_promise(" içinde geçer.)
  expect_false(.pk_async_has(metin, "promises::future_promise("))
  expect_true(.pk_async_has(metin, "tracked_future_promise("))
  expect_true(.pk_async_has(metin, "pk_async_worker_globals()"))
})

test_that("gönderim katmanı geri çağrılarda istek-kimliği koruması ve isolate kullanır", {
  metin <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/server_handler_pk_async.R"))

  expect_true(.pk_async_has(metin, "pk_async_should_apply("))
  # Promise/later geri çağrıları reaktif BAĞLAM içinde DEĞİLDİR (Ortak Oturum
  # dersi): çıplak reactiveVal okuması patlar.
  expect_true(.pk_async_has(metin, "shiny::isolate(ctx$active_request_id())"))
  expect_true(.pk_async_has(metin, "shiny::isolate(ctx$stop_generation())"))
  # Oturum yazımları YALNIZCA koruma geçtikten sonra uygulanır.
  expect_true(.pk_async_has(metin, "pk_async_apply_session_writes("))
  # Oturum kapanışı işçiyi durdurur (geri çağrıyı atmak YETMEZ). Kanca artık
  # OTURUM BAŞINA TEKTİR ve kayıt defterindedir: istek başına bir kapanış
  # kaydetmek, tamamlanan HER isteğin gönderim çerçevesini oturum ömrü boyunca
  # canlı tutuyordu (bellek istek sayısıyla doğrusal büyüyordu).
  expect_true(.pk_async_has(metin, "mergen_pk_register_active_request("))
  expect_true(.pk_async_has(metin, "mergen_pk_session_open("))
  kayit_defteri <- .pk_async_read_bytes(
    file.path(.pk_async_repo(), "R/helpers_pk_async_session_registry.R")
  )
  expect_true(.pk_async_has(kayit_defteri, "onSessionEnded"))
  expect_true(.pk_async_has(kayit_defteri, "pk_cancel_token_signal("))
})

test_that("send_message PK yolunu DELEGE eder ve devam kapanışı TEK gövdedir", {
  metin <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/server_send_message.R"))

  expect_true(.pk_async_has(metin, "mergen_pk_analysis_execute("))
  expect_true(.pk_async_has(metin, "run_llm_request_stage <- function("))
  expect_true(.pk_async_has(metin, "continue_fn = run_llm_request_stage"))
  # `deferred` dalı HEMEN döner; aksi hâlde LLM iki kez tetiklenirdi.
  expect_true(.pk_async_has(metin, '"deferred"'))

  # Eski satır içi blok GERİ GELMEMELİDİR: iki ayrı uygulama, MERGEN_PK_ASYNC
  # açıldığında sessiz davranış farkı üretirdi.
  expect_false(.pk_async_has(metin, "analiz_result <- tryCatch("))
})

test_that("durdur gözlemcisi iptali İŞÇİYE ulaştırır", {
  metin <- .pk_async_read_bytes(
    file.path(.pk_async_repo(), "R/server_observers_chat_input.R")
  )

  expect_true(.pk_async_has(metin, "mergen_pk_signal_cancel("))
  # Jeton, aktif istek kimliği DEĞİŞTİRİLMEDEN ÖNCE işaretlenmelidir; sonra
  # işaretlenirse doğru dosya adı kaybolur.
  jeton_yeri <- regexpr("mergen_pk_signal_cancel(", metin, fixed = TRUE, useBytes = TRUE)
  kimlik_yeri <- regexpr('active_request_id(paste0("cancelled_', metin, fixed = TRUE, useBytes = TRUE)
  expect_true(jeton_yeri > 0)
  expect_true(kimlik_yeri > 0)
  expect_true(jeton_yeri < kimlik_yeri)
})

test_that("işçi kendi bağlantısını açar; ana süreç bağlantısı TAŞINMAZ", {
  isci <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_async_worker.R"))
  # Anlık görüntü DOĞRULAMASI ayrı dosyaya taşındı (ratchet bölünmesi); test
  # runtime kodunu geri taşımak yerine YENİ SAHİBİ doğrular.
  istek <- paste(
    .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_async_snapshot_validate.R")),
    .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_async_snapshot.R")),
    sep = "\n"
  )

  # İşçi boru hattını çağırır; boru hattı `get_connection()`/`on.exit` ile
  # bağlantıyı İŞÇİDE açar ve bırakır.
  expect_true(.pk_async_has(isci, "pk_analiz_process_request("))
  expect_true(.pk_async_has(isci, "pk_deep_analysis_process("))

  # Anlık görüntü sözleşmesi: yasaklı sınıflar açıkça listelenir ve doğrulanır.
  expect_true(.pk_async_has(istek, "DBIConnection"))
  expect_true(.pk_async_has(istek, "ShinySession"))
  expect_true(.pk_async_has(istek, "reactivevalues"))
  expect_true(.pk_async_has(istek, "pk_async_validate_request"))
})

test_that("Faz 6 yapılandırma anahtarları KAYITLI ve .Renviron.example'da belgelenmiş", {
  kok <- .pk_async_repo()
  cfg_env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_pk_config.R"), encoding = "UTF-8", local = cfg_env)

  anahtarlar <- c(
    "MERGEN_PK_ASYNC", "MERGEN_PK_SQL_TIMEOUT_SEC", "MERGEN_PK_ANALYSIS_DEADLINE_SEC",
    "MERGEN_PK_CACHE_MAX_ENTRIES", "MERGEN_PK_CACHE_MAX_MB",
    "MERGEN_PK_CACHE_MAX_ENTRY_MB", "MERGEN_PK_CACHE_TTL_SEC",
    "MERGEN_PK_DEEP_MAX_QUERIES", "MERGEN_PK_MAX_RESULT_MB",
    "MERGEN_PK_RESULT_OVERHEAD_FACTOR", "MERGEN_PK_FETCH_CHUNK_ROWS"
  )
  for (anahtar in anahtarlar) {
    expect_true(anahtar %in% names(cfg_env$pk_config_spec), info = anahtar)
  }

  # §9 varsayılanları.
  expect_false(cfg_env$pk_config_spec$MERGEN_PK_ASYNC$default)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_SQL_TIMEOUT_SEC$default, 120L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_ANALYSIS_DEADLINE_SEC$default, 300L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_CACHE_MAX_ENTRIES$default, 50L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_CACHE_MAX_MB$default, 512L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_CACHE_MAX_ENTRY_MB$default, 128L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_CACHE_TTL_SEC$default, 300L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_DEEP_MAX_QUERIES$default, 5L)
  expect_equal(cfg_env$pk_config_spec$MERGEN_PK_MAX_RESULT_MB$default, 512L)

  renv <- .pk_async_read_bytes(file.path(kok, ".Renviron.example"))
  for (anahtar in anahtarlar) {
    expect_true(.pk_async_has(renv, anahtar), info = anahtar)
  }
})

test_that("MERGEN_PK_ASYNC, MERGEN_PK_ENGINE'den BAĞIMSIZ bir kill switch'tir", {
  kok <- .pk_async_repo()
  istek <- paste(
    .pk_async_read_bytes(file.path(kok, "R/helpers_pk_async_plan.R")),
    .pk_async_read_bytes(file.path(kok, "R/helpers_pk_async_request.R")),
    sep = "\n"
  )

  # Asenkron uygunluk kararı motor bayrağını OKUMAZ.
  expect_true(.pk_async_has(istek, 'pk_config_resolve("MERGEN_PK_ASYNC"'))
  expect_false(.pk_async_has(istek, 'pk_config_resolve("MERGEN_PK_ENGINE"'))
})

test_that("D16 sapmaları KAPATILDI: derin mod ana yolun kapılarını kullanır", {
  derin <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_deep_analysis.R"))

  # (1) Kimlik: ham atama GERİ GELMEZ (yorum içindeki alıntı sayılmaz; bu yüzden
  # ATAMA biçimi aranır).
  expect_false(.pk_async_has(
    derin, 'username <- session$userData$system_username'
  ))
  expect_true(.pk_async_has(derin, "identity_state <- pk_deep_resolve_username(session)"))
  expect_true(.pk_async_has(derin, "username <- identity_state$username"))

  # (2) SQL kaynağı: istek anında dosya yeniden okuma GERİ GELMEZ.
  expect_true(.pk_async_has(derin, "pk_deep_query_sql_text("))
  expect_false(.pk_async_has(derin, 'iconv(list(raw_content), from = "UTF-16LE"'))

  # (3) SQL yürütme: düz dbGetQuery GERİ GELMEZ; ana yolla aynı sınır kullanılır.
  expect_false(.pk_async_has(derin, "DBI::dbGetQuery(conn, trimws(sql_query_text))"))
  expect_true(.pk_async_has(derin, "pk_deep_execute_sql("))

  # (4) Sıralı-küme tavanı yapılandırmadan gelir: ÇAĞRI yerinde sabit 5 kalmaz.
  # (v1 seçicisinin fonksiyon imzasındaki varsayılan korunur; çağıran her zaman
  # açıkça geçirir.)
  # Seçim aşamasındaki tavan/bütçe kararı ratchet nedeniyle
  # `pk_deep_select_multi_queries()` içine taşındı (helpers_deep_analysis_phase6.R);
  # orkestratör kesin tavanı metadata bilindikten SONRA uygular.
  expect_true(.pk_async_has(derin, "pk_deep_select_multi_queries("))
  expect_true(.pk_async_has(derin, "deep_query_ceiling <- pk_deep_max_queries(birincil_meta)"))
  expect_false(.pk_async_has(derin, "session, max_queries = 5)"))

  # (5) Sorgular ARASINDA son tarih/iptal kapısı.
  expect_true(.pk_async_has(derin, "pk_async_stage_gate("))

  # (6) Paket uzlaştırma + çapraz aritmetik yasağı.
  expect_true(.pk_async_has(derin, "pk_deep_reconcile_packets("))

  # (7) Sonuç önbelleği BAĞLANMIŞTIR ve anahtar yetki imzası taşır; isabet
  # gerçek-sütun doğrulaması/RLS kapılarını ATLAMAZ (ikisi de isabetten SONRA
  # çalışmaya devam eder).
  expect_true(.pk_async_has(derin, "pk_query_result_cache_key(query, rls_info"))
  gate_yeri <- regexpr("pk_meta_actual_column_gate(", derin, fixed = TRUE, useBytes = TRUE)
  rls_yeri <- regexpr("apply_rls_to_data(", derin, fixed = TRUE, useBytes = TRUE)
  cache_yeri <- regexpr("pk_query_result_cache_key(", derin, fixed = TRUE, useBytes = TRUE)
  expect_true(cache_yeri > 0 && gate_yeri > cache_yeri && rls_yeri > cache_yeri)
})

test_that("çapraz sorgu aritmetiği kısıtı istem bağlamına YAZILIR", {
  baglam <- .pk_async_read_bytes(
    file.path(.pk_async_repo(), "R/helpers_deep_analysis_context.R")
  )
  expect_true(.pk_async_has(baglam, "PAKET SINIRI"))
  expect_true(.pk_async_has(baglam, "pk_cross_query_instruction"))
})

test_that("işçi bootstrap DONMUŞ bölüm listesi UI/modül/gözlemci içermez", {
  istek <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_async_bootstrap.R"))

  # Bölüm listesi dosya listesi DEĞİL bölüm listesi olarak dondurulur; böylece
  # bir bölüme yeni yardımcı eklendiğinde işçi otomatik alır (sürüklenme yok).
  expect_true(.pk_async_has(istek, "pk_async_worker_manifest_sections"))
  expect_true(.pk_async_has(istek, '"analysis_helpers"'))
  expect_true(.pk_async_has(istek, '"llm_pipeline"'))
  expect_false(.pk_async_has(istek, '"module_chat"'))
  expect_false(.pk_async_has(istek, '"server_observers"'))
  expect_false(.pk_async_has(istek, '"config_ui_assets"'))
})

test_that("önbellek anahtarı YETKİ KAPSAMINI zorunlu tutar", {
  onbellek <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_cache.R"))

  expect_true(.pk_async_has(onbellek, "rls_signature"))
  expect_true(.pk_async_has(onbellek, "__no_scope__"))
  expect_true(.pk_async_has(onbellek, "pk_cache_rls_signature"))
  # Tek giriş tavanı: aşan giriş HİÇ alınmaz.
  expect_true(.pk_async_has(onbellek, "entry_too_large"))
})

test_that("Faz 6 dosyaları bakım ratchet bütçelerine uyar", {
  kok <- .pk_async_repo()
  eski_wd <- getwd()
  on.exit(setwd(eski_wd), add = TRUE)
  setwd(kok)

  rapor_env <- new.env(parent = globalenv())
  rapor <- source("tests/scripts/maintainability_report.R",
                  encoding = "UTF-8", local = rapor_env)$value

  # İnceleme düzeltmeleri sonrası ÖLÇÜLEN taban çizgisi + küçük baş boşluk.
  #
  # TEK OTORİTE: küresel tavanlar `tests/testthat/test-maintainability-ratchet.R`
  # dosyasında UYGULANIR (bu blok onları KOPYALAMAZ; iki farklı rakam yazmak
  # okuyucuyu hangi sınıra uyulacağı konusunda belirsiz bırakıyordu). Buradaki
  # bütçeler yalnızca DOSYA BAZLIdır ve küresel tavanın ALTINDA kalır.
  # Sınıra dayanan yerler BÖLÜNEREK çözüldü: anlık görüntü doğrulaması, işçi
  # SQL köprüsü, ana-süreç yaşam döngüsü, derin Faz 6 kurulumu ve v1 çoklu
  # seçici ayrı dosyalardadır.
  # PR #703 İNCELEME GÜNCELLEMESİ: aşağıdaki bütçeler, incelemede talep edilen
  # GÜVENLİK mantığı eklendikten sonra ÖLÇÜLEN yeni taban çizgisidir (kapalı
  # başarısız yapılandırma anlık görüntüsü, sürücü tanımlayıcı sondası, tek
  # yönlü async kill switch, doğrulanmış oturum yazımları, sınırlı bootstrap
  # G/Ç, agregat DB admisyonu, artefakt kapsamı). Tavanlar TAM olarak ölçülen
  # değere çekilmiştir: sonraki bir büyüme yine BAŞARISIZ olur.
  #
  # KÜRESEL ratchet DEĞİŞMEMİŞTİR (rakamlar için tek kaynak:
  # `tests/testthat/test-maintainability-ratchet.R`) ve bu dosyaların hiçbiri
  # ona yaklaşmamaktadır.
  butceler <- list(
    # BILINCLI GUNCELLEME (PR incelemesi): 295 -> 298 satir (OLCULEN). Bayat
    # jeton supurucusundeki SABITLEME artik YAS SINIRLIDIR: terminal yol bu
    # surecte hic calismazsa (isci cokmesi, `pk_cancel_token_clear()` atlanan
    # oturum yikimi) anahtar surec omru boyunca kaliyor, `.flag` dosyasi HIC
    # toplanmiyor ve kayit sinirsiz buyuyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 298 -> 308 satir (OLCULEN).
    # ETKIN bir istegin jetonu artik HICBIR yasta bayat sayilmaz. `yas * 4`
    # penceresinden sonra kaydi ve dosyayi silmek, IPTAL EDILMIS ama hala ETKIN
    # bir istekte iptal SINYALINI yok ediyordu: ODBC/LLM/yerel kodda bloklanmis
    # bir isci o pencereden sonra `pk_async_stage_gate()`e ulastiginda hicbir
    # durdurma isareti gormeden analizi SONUNA KADAR calistiriyordu.
    # Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_cancel.R" = c(308L, 24L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 135 -> 151 satir, 11 -> 12
    # fonksiyon (OLCULEN). `pk_active_stage_halt_status()` eklendi: kapinin
    # boole cevabi kullanici Durdur'u ile son tarih asimini TEK degere
    # indirgiyor, cagiran tipli bir durum URETEMIYORDU. Ham `timeout` dondurmek
    # oturum secim durumunu siler, ham `cancelled` ise kullanicinin durdurmadigi
    # bir asimi "siz iptal ettiniz" diye raporlardi.
    "R/helpers_pk_exec_context.R" = c(151L, 12L),
    "R/helpers_pk_cancel_http.R" = c(109L, 10L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): 245 -> 259 satir (OLCULEN).
    # `sql_variant` HER ZAMAN SINIRSIZ LOB listesinden CIKARILDI: ODBC tip kodu
    # -98'in KANITLI 8016 baytlik ust siniri vardir. Sinirsiz saymak, tamamen
    # olculebilir bir sonucu gereksiz yere reddediyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 P2 takibi): 259 -> 263 satir (OLCULEN).
    # `[[` yerine `[` kullanilir: adlandirilmis atomik vektorde OLMAYAN bir ad
    # `[[` ile "subscript out of bounds" firlatir; desteklenmeyen bir ODBC tip
    # kodu bu yuzden `__unknown__` dalina HIC ulasamiyor ve planlayici tek-satir
    # getirmeye dusmek yerine ABORT ediyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 263 -> 270 satir (OLCULEN).
    # `system_type_name` NA geldiginde siniflandirma ARTIK durmaz: NA yalnizca
    # "bilinmeyen tip" demektir ve sutun muhafazakar sekilde `character` /
    # `dimension` olarak isaretlenir. Eskiden tek bir NA tum sonuc semasini
    # dusuruyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 270 -> 301 satir (OLCULEN).
    # Iki neden: (a) surucu ustveri alan adlari ve tanimlayici tip adlari artik
    # `pk_ascii_lower()` ile katlanir -- `tolower()` Turkce yerelde `I` -> `i`
    # yapmaz ve `NVARCHAR` gibi tipler eslesmiyordu; (b) Unicode (nchar/nvarchar)
    # tanimlayici genislikleri UTF-8 icin x2 olceklenir. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR incelemesi): Unicode ODBC kodlari (-8/-9)
    # karakter basina 4 BAYT sayilir; diger iki genislik yolu ile ayni
    # sozlesme. OLCULEN taban 301 -> 321 (fonksiyon sayisi ARTMADI).
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 321 -> 333 satir (OLCULEN).
    # Betimleyici sorgusu artik `error_type` de secer ve HATA SATIRI sutun
    # metadata'si sanilmaz; aksi halde betimlenemeyen bir toplu ifade
    # `__unproven__` siniflandirilip sonuc HIC veri cekilmeden reddediliyordu.
    # Fonksiyon sayisi AYNI.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 333 -> 342 satır (ÖLÇÜLEN).
    # `.pk_sql_metadata_field()` artık ADAY SIRASINI önceliklendirir; `precision`
    # alanını `column_size`/`max_length` ÖNCESİNDE bildiren bir DBI arka ucunda
    # sayısal hassasiyet karakter uzunluğu sanılıyordu. Fonksiyon sayısı AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 342 -> 356 satir (OLCULEN).
    # `hierarchyid` SINIRSIZ LOB listesinden CIKARILDI: SQL Server'da tek bir
    # degerin KANITLI 892 baytlik ust siniri vardir. Sinirsiz saymak,
    # `pk_sql_plan_chunk_rows()` uzerinden analizi tek satir bile cekilmeden
    # `too_large` ile reddediyordu (`sql_variant` ile AYNI hata sinifi).
    # Fonksiyon sayisi AYNI.
    "R/helpers_pk_result_columns.R" = c(356L, 8L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): 551 -> 592 satir (OLCULEN). Iki
    # neden: (a) `sql_variant` icin KANITLI 8016 bayt ust siniri; (b) R nesne
    # tabani (karakter 56 / atomik 8 bayt/eleman) tahmine EKLENDI -- eskiden
    # yalnizca surucu genisligi sayiliyor, cok sutunlu dar sonuclarda gercek
    # bellek AYAK IZI ciddi sekilde EKSIK tahmin ediliyordu. Fonksiyon AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 592 -> 604 satir (OLCULEN).
    # `metadata_unavailable` artik `refuse = TRUE` dondurur (yalnizca
    # `pk_allow_unbounded_lob()` acikca izin verdiginde gecer): KANITLANMAMIS
    # bir ust sinirla tam materyallestirme yapmak bellek tavanini bypass
    # ediyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 604 -> 617 satir (OLCULEN).
    # BEYAN EDILEN `(max)` isareti de LOB kanitidir; `.pk_result_type_key()`
    # parantezli kismi attigi icin `nvarchar(max)` + `max_length = NA` bildirimi
    # `lob_columns` listesine GIRMIYORDU. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 617 -> 630 satir (OLCULEN).
    # `__unknown__` siniflı sutun ARTIK `__unproven__` gibi KAPALI BASARISIZ
    # olur: tip kodu ne sabit-genislik tablosunda ne LOB listesindedir, bayt
    # orani bilinmedigi icin tek hucre tavani asabilirdi ama dal `dbFetch(n=1)`
    # cagrisini refuse ETMEDEN yetkilendiriyordu. Fonksiyon sayisi AYNI.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 630 -> 635 satır (ÖLÇÜLEN).
    # `unknown_type_code` reddinin `lob_columns` yükü ARTIK gerçek sütun adını
    # taşır: `sutunlar` ADSIZ bir listedir, `names()` NULL döndüğü için eski
    # indeksleme her öge için `NA_character_` üretiyor ve operatör günlüğü
    # sorguyu hangi sütunun engellediğini GÖREMİYORDU. Fonksiyon sayısı AYNI.
    "R/helpers_pk_result_size.R" = c(635L, 19L),
    "R/helpers_pk_cache_key.R" = c(140L, 11L),
    # BILINCLI GUNCELLEME (PR #705): sinirlar artik KAYIP anahtarda da
    # uzlastirilir (kapali onbellek/dusurulmus tavan ANINDA etkilidir).
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 446 -> 456 satir (OLCULEN).
    # Ham SQL onbellek anahtari artik SABIT `.PK_CACHE_RAW_SQL_ENGINE` kullanir;
    # cagiranin `engine` degeri anahtara girdiginde derin analiz ve standart
    # analiz AYNI sorgu icin ayri girdiler yaziyordu. Fonksiyon sayisi AYNI.
    # YEREL SOZLESME KURESEL TAVANI ASAMAZ: kuresel ratchet
    # `actual_max_functions <= 24` iddia eder; burada 26'ya izin vermek yerel
    # testin GECIP kuresel testin DUSMESI demekti.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 456 -> 477 satir (OLCULEN).
    # Sayisal guvenli `coz()` (integer64/tamsayi tasmasi) ve `digest` yoksa
    # calisan parmak izi yedegi eklendi. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 477 -> 505 satir (OLCULEN).
    # DEPO GENELI butceler (`MAX_ENTRIES`/`MAX_MB`) artik sorgu metadata'sini
    # GORMEZ: `.pk_cache_store` surec yereldir ve tek bir sorgunun override'i
    # TUM deponun butcesi haline geliyordu (kucuk deger baska sorgularin
    # girislerini tahliye ediyor, buyuk deger operator tavanini gevsetiyordu).
    # Depo geneli TTL de ayrildi. Fonksiyon sayisi AYNI.
    "R/helpers_pk_cache.R" = c(505L, 24L),
    # BILINCLI GUNCELLEME: tavan 1 satir BAYATTI (olculen 430, tavan 429).
    # Bu sapma, rapor yol eslesmesi bozuk oldugu icin (nrow == 0) uzun sure
    # "NA > 429" bicimindeki hatanin ardinda gorunmez kaldi. Tavan yine TAM
    # olculen degere cekilmistir; sonraki bir buyume yine BASARISIZ olur.
    # Kuresel ratchet (795 satir / 24 fonksiyon) ihlal EDILMEMEKTEDIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme): +5 satir. Sinirli yurutucu artik
    # ACIK `query_meta` parametresi alir; derin analiz per-query yurutme baglami
    # KURMADIGI icin ortuk `pk_active_query_meta()` orada NULL donuyor ve sorgu
    # override'lari (yuk carpani / onayli LOB) OLU kaliyordu. Fonksiyon sayisi
    # DEGISMEDI. Olculen 435.
    # BILINCLI GUNCELLEME (PR #705 inceleme): 435 -> 459 satir (OLCULEN).
    # Getirim ONCESI "ongorulen tepe" kapisi eklendi: `rbind` birlestirmesi
    # sirasinda tepe bellek IKI KATIdir; tavana SIGAN ama birlestirilirken
    # sigmayacak bir sonuc artik tahsisattan ONCE reddedilir. Fonksiyon AYNI.
    # BILINCLI GUNCELLEME (PR #705 P2 takibi): 459 -> 474 satir (OLCULEN).
    # `dbHasCompleted()` tamamlanma denetimi de `bloklayan()` uzerinden gecer:
    # dogrudan cagri, surucu denetimde bloklarsa kalan analiz/ifade butcelerini
    # ATLIYORDU ve asili bir denetim isciyi getirimin kendisi kadar tutar.
    # Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 474 -> 483 satir (OLCULEN).
    # `dbColumnInfo` kapisinda "ok" OLMAYAN HER durum erken doner; eskiden
    # yalnizca `deadline`/`timeout` donuyor, TIPLI `cancelled` sonucu
    # `too_large` olarak yeniden etiketleniyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 483 -> 487 satir (OLCULEN).
    # `dbHasCompleted()` artik SINIRLI cagri altinda okunur; suresiz bloklayan
    # bir surucu cagrisi butceyi asamaz. Fonksiyon sayisi AYNI.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 487 -> 502 satır (ÖLÇÜLEN).
    # (a) TEMİZLİK KAYDI checkout'tan HEMEN SONRA kurulur ve zaman aşımı
    # uygulaması ölümcül değildir: aradaki bir hata havuz yuvasını KALICI
    # sızdırıyordu. (b) Ön getirim projeksiyon kapısı, hemen ardındaki
    # biriktirme kararıyla AYNI eşiği (`tavan_mb / 2`) kullanır.
    # Fonksiyon sayısı AYNI.
    "R/helpers_pk_sql_execute.R" = c(502L, 22L),
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 125 -> 138 satır (ÖLÇÜLEN).
    # `poolReturn()` sonucu artık DENETLENİR; sınırlı çağrı başarısız olursa
    # checkout emekliye ayrılır. Fonksiyon sayısı AYNI.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 138 -> 151 satır (ÖLÇÜLEN).
    # ÖNCEKİ `LOCK_TIMEOUT` değeri OKUNAMADIYSA zaman aşımı HİÇ uygulanmaz;
    # eskiden uygulanıp `applied = TRUE` raporlanıyor, temizlik `dirty = TRUE`
    # döndüğü için o durumdaki HER istek bir havuz bağlantısını yok ediyordu.
    # Fonksiyon sayısı AYNI.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 151 -> 154 satır (ÖLÇÜLEN).
    # `SET LOCK_TIMEOUT` milisaniye çarpımı TAM SAYI TAŞMASINA uğramaz:
    # 2147483 saniyenin üzerinde ifade `SET LOCK_TIMEOUT NA` olarak gidiyor
    # ve kilit bekleme sınırı SESSİZCE uygulanmıyordu. Fonksiyon sayısı AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 154 -> 158 satir (OLCULEN).
    # `.pk_sql_invalidate_connection()` `@return` sozlesmesi, kapatma VE havuz
    # iadesinin BIRLESIK sonucunu tarif edecek sekilde duzeltildi; belge
    # gerceklenen davranisla celisiyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_sql_connection.R" = c(158L, 6L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 372/22 -> 414/24 (OLCULEN).
    # `sql_file` bagimliliklari artik KAYNAK METINDEN cikarilir. Temiz bir PSOCK
    # iscisinde ILK parmak izi bootstrap'tan ONCE hesaplanir ve o an
    # `query_library` HENUZ YOKTUR: eski surum `character(0)` donuyor, sonraki
    # istek dolu kutuphaneyle FARKLI parmak izi uretiyor ve isci DEGISMEMIS bir
    # calisma kopyasinda IKINCI bir tam bootstrap yapiyordu (kaynak yukleme +
    # havuz kurulumu analiz son tarihinin ICINDE tekrarlaniyordu). Fonksiyon
    # sayisi 22 -> 24: bir yardimci + iki `tryCatch` isleyicisi. Kuresel tavan
    # (24) ASILMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 414 -> 451 satir (OLCULEN).
    # (a) `pk_async_worker_commit_env()` artik ATOMIKTIR: dokunulan her baglama
    # once yedeklenir ve KISMI commit GERI ALINIR; eskiden kilitli tek bir
    # baglama `ok = FALSE` uretse de basarili mutasyonlar yerinde kaliyor, isci
    # eski/yeni yardimci KARISIMI tasiyordu. (b) Yedek parmak izi carpimi
    # `numeric` yapildi (~8 MB ustu dosyada tamsayi tasmasi ":NA" uretiyordu).
    # Fonksiyon sayisi AYNI (yeni ust duzey fonksiyon EKLENMEDI).
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 451 -> 455 satir (OLCULEN).
    # `digest`/`openssl` yokken son care parmak izi ARTIK dosya ozetlerinin
    # KENDISINI tasir; `nchar()` ozeti icerigi atiyor ve iki farkli checkout
    # ayni toplam karakter sayisinda CAKISIP isciyi ONCEKI revizyonda
    # birakabiliyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_worker_env.R" = c(455L, 24L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): +5 satir. Admisyon karari artik
    # KURESEL `admission_cap` uzerinden hesaplanir; `cfg$max_size` zaten bir kez
    # bolusturulmus sureç payi oldugu icin ikinci bolusturme mesru bir tavani
    # `fits = FALSE` yapabiliyordu. Fonksiyon sayisi DEGISMEDI. Olculen 360.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 360 -> 368 satir (OLCULEN).
    # Havuz nesnesi `get0("pool", envir = ortam)` ile okunur ve `rm()` ile ADI
    # verilerek kaldirilir; `ortam$pool` zinciri gormedigi ve `rm(pool)` sembolu
    # cagri cercevesinde aradigi icin kapatma yolu sessizce bosa dusuyordu.
    # Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 368 -> 409 satir (OLCULEN).
    # Anlik goruntu artik ORTAM TABANLI havuz girdilerini de tasir
    # (`MERGEN_DB_POOL_ENABLED/FAIL_FAST/MAX_SIZE/MIN_SIZE/IDLE_TIMEOUT`).
    # `db_pool_config()` ve havuz parmak izi bunlari ISCININ KENDI ortamindan
    # okuyor; kalici bir PSOCK iscisi ana surecteki sonraki `Sys.setenv()`
    # cagrilarini GORMEDIGI icin operator tavani dusurse ya da havuzu kapatsa
    # bile isci ESKI havuzu ve eski oturum tavanini omru boyunca koruyordu.
    # `MERGEN_DB_POOL_SHARE_APPLIED` BILEREK tasinmaz (surec rolu).
    # Fonksiyon sayisi ARTMAMISTIR.
    # YEREL SOZLESME KURESEL TAVANI ASAMAZ (bkz. helpers_pk_cache.R notu).
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 409 -> 416 (OLCULEN).
    # (a) `DB_DSN` tasinan havuz girdilerine VE parmak izine eklendi: operator ana
    # surecte DSN degistirdiginde SICAK isci ONCEKI veritabanina bagli havuzu
    # koruyordu. (b) `MERGEN_DB_POOL_SHARE_APPLIED` isareti tavanla BIRLIKTE geri
    # alinir; aksi halde pay penceresi disinda kurulan havuz TOPLAM oturum
    # tavanini asabiliyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_worker_pool.R" = c(416L, 24L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): +10 satir. D11 devralinan varlik
    # baglami hem isci vekiline KURULUR hem de hasat yuvalarina eklenir; aksi
    # halde asenkron takip sorulari onceki turun varlik kisitini kaybediyordu.
    # Fonksiyon sayisi DEGISMEDI. Olculen 514.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 514 -> 517 satir (OLCULEN).
    # Operatore gorunen mesajlar Turkce'ye geri alindi (Kural 2); mantik
    # DEGISMEDI. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 517 -> 537 satir (OLCULEN).
    # (a) PK gozlemci sarmalayicilari ZORUNLU dosya kumesine alindi (eksik
    # dagitimda telemetri/derin gozlemci SESSIZCE kayboluyordu); (b) repo koku
    # ve dosya varlik denetimleri `pk_async_bounded_path_exists()` uzerinden
    # SINIRLANDI (askida UNC/NFS'te isci sabitleniyordu); (c) zorunlu dosya
    # karsilastirmasi `basename()` yerine TAM GORELI yol; (d) cozulemeyen havuz
    # parmak izi artik `NA` bayrak yazmaz. Fonksiyon sayisi AYNI: yeni yardimci
    # AYRI dosyaya (`R/helpers_pk_async_bootstrap_fs.R`) alindi.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 537 -> 549 satir (OLCULEN).
    # Cozulemeyen parmak izi artik TIPLI bir bootstrap hatasidir. `NA`
    # saklandiginda onbellek kosulu bir daha ASLA tutmuyor ve isci HER
    # istekte tum bootstrap dosya kumesini yeniden source ediyordu (sessiz
    # performans cokusu). Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 549 -> 556 satir (OLCULEN).
    # Calisma dizini normallestirmesi ve `setwd()` ARTIK `pk_async_bounded_fs()`
    # butcesinden gecer. Takilmis bir UNC/NFS repo kokunde isci CAGRININ ICINDE
    # bloke oluyordu; asama kapisi yukarida gecildigi icin ne Durdur belirteci
    # ne de mutlak son tarih gozlemleniyor, ana surec izleyicisi kullaniciya
    # yanit verse bile PSOCK iscisi askida kaliyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_bootstrap.R" = c(556L, 24L),
    # Faz 6: bootstrap'in SINIRLI yol-varlik denetimi (ratchet tavani nedeniyle
    # ayri dosya; bkz. dosya basligi).
    "R/helpers_pk_async_bootstrap_fs.R" = c(60L, 6L),
    "R/helpers_pk_async_snapshot_validate.R" = c(135L, 9L),
    # BILINCLI GUNCELLEME (PR #705): D11 devralinan varlik baglami isciye
    # ACIKCA duz veri olarak tasinir (genel dongu list alanlari atliyordu).
    # BILINCLI GUNCELLEME (PR #705 inceleme): +9 satir. Toplama tarafi artik
    # LISTE degerli `pk_entity_prior_context` alanini da okur; okunmadigi icin
    # `.pk_async_plain_user_data()` sanitizasyonu OLU KODDU. Fonksiyon sayisi
    # DEGISMEDI (try() kullanildi). Olculen 288.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): sır taşıma (`pk_async_secret_*`)
    # AYRI `R/helpers_pk_async_secrets.R` dosyasına çıkarıldı; kalan gövde ÖLÇÜLEN.
    "R/helpers_pk_async_snapshot.R" = c(263L, 16L),
    # BİLİNÇLİ GÜNCELLEME (PR #705 kararlılık): yetenek sondası artık
    # `future::value()` ile ana olay döngüsünü BLOKE ETMEZ; `resolved()`
    # sınırlı bir bütçe boyunca yoklanır ve SONUÇSUZ sonda başarı sayılmaz.
    # Tavan yine TAM ölçülen değere çekilmiştir; fonksiyon sayısı ARTMAMIŞTIR.
    # PR #705 takibi: işçi-PID sondası kendi dosyasına AYRILDI (bekleyen
    # future'ı yeniden kullanır, ölçülemeyen sonucu soğuma penceresiyle
    # hatırlar). Plan dosyası 242 -> 190 küçüldü; sonda kendi bütçesini taşır.
    "R/helpers_pk_async_plan.R" = c(190L, 14L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 110 -> 114 satir (OLCULEN).
    # PID sondasi artik BOS isci yuvasi kapisindan gecer; aksi halde teshis
    # sondasi kullanici isine ayrilmis bir isciyi kapabiliyordu. `lazy`
    # BILEREK FALSE kalir (sonda planin GERCEKTEN asenkron oldugunu olcer).
    # Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 114 -> 137 satir, 5 -> 7
    # fonksiyon (OLCULEN). `future >= 1.24.0` surum tabani ACIKCA bildirilir:
    # daha eski bir kurulumda `nbrOfFreeWorkers()` bulunamiyor, sonda
    # "olculemedi" diyor ve asenkron yol SEBEBI GORUNMEDEN devre disi
    # kaliyordu (operator `worker_probe_inconclusive` gorup plani arastiriyordu).
    "R/helpers_pk_async_probe.R" = c(137L, 7L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 295 -> 300 satir (OLCULEN).
    # Isci globals paketine iki bootstrap-ONCESI sembol eklendi:
    # `.pk_async_sql_paths_from_source` ve `.PK_ASYNC_DB_POOL_ENV`.
    # `dependency_mode = "explicit"` tarama YAPMAZ; eksik biri temiz bir PSOCK
    # iscisini "object not found" ile dusurup her istegi SESSIZCE senkron yola
    # indiriyordu. Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 300 -> 303 satir (OLCULEN).
    # `pk_async_bounded_path_exists` isci globals paketine eklendi (bootstrap
    # ONCESI cagrilir). Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_request.R" = c(303L, 16L),
    "R/helpers_pk_async_worker_sql.R" = c(165L, 11L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): 330 -> 355 satir (OLCULEN). Iki
    # GUVENLIK nedeni: (a) LOG sinirinda ODBC BAGLANTI TANIMLAYICILARI da
    # maskelenir (`DSN=`/`UID=`/`Server=` kalici sunucu log'una yazilamaz) ve
    # redaktor HIC yuklenmemisse ham metin LOG'A YAZILMAZ (kapali basarisiz);
    # (b) hata SINIFLANDIRMASI ham metinden, KAYIT redakte metinden yapilir --
    # aksi halde guclenen redaksiyon altyapi imzasini silip gercek bir DB
    # hatasini "genel hata" olarak raporlardi. Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 355 -> 374 satir (OLCULEN).
    # Onceki degeri OLMAYAN baglamalar artik `NULL` ATANMAZ, gercekten KALDIRILIR
    # (`rm()`); `NULL` atamak isci ortaminda var olan ama degeri NULL olan bir
    # sembol biraktigi icin `exists()` kapilari yanlis TRUE donuyordu.
    # Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 374 -> 380 (OLCULEN).
    # `MERGEN_PK_ENGINE` ortam basamagi istek suresince istek anlik goruntusuyle
    # ESITLENIR ve cikista geri yuklenir: `pk_config_resolve()` ortami options'tan
    # ONCE okudugu icin SICAK bir PSOCK iscisindeki BAYAT deger v2 gonderimini v1
    # hattinda kosturuyordu. Ayrica globals sarmalayicisi kendini sarmalamaya
    # karsi isaretlendi (ikinci source'ta ozyineleme). Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_worker.R" = c(380L, 22L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 110/7 -> 130/8 (OLCULEN).
    # Dogrudan-cikis metnini iki sahipten cikaran ORTAK yardimci
    # (`pk_direct_exit_text()`) BURAYA tasindi; `type == "error_message"` artik
    # "Hata" olarak siniflandirilir (eskiden bilinmeyen tip sessizce "Bilinmiyor"
    # oluyor ve DB hatasi tespiti kaciriliyordu). Kopya metin cikarma mantigi
    # `helpers_pk_worker_direct_exit.R` icinden KALDIRILDI.
    # BILINCLI GUNCELLEME (inceleme takibi): 130/8 -> 150/10 (OLCULEN).
    # `PK_DB_FAILURE_PATTERNS` / `PK_DB_FAILURE_EXCEPTION_PATTERNS` sabitleri
    # BURAYA tasindi: isci siniflandiricisi ile ana surecteki
    # `.pk_hook_database_failure_text()` ayri desen listeleri tasidigi icin ayni
    # DB arizasi es zamanli yolda taninip asenkron yolda taninmiyordu.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 150 -> 159 satir (OLCULEN).
    # `error_message` listesi artik DESEN TARAMASINDAN SONRA hataya eslenir:
    # ana surec metni cikarip verdigi icin "Yetkisiz"/"EslesmeYok", isci ise HAM
    # listeyi verdigi icin "Hata" uretiyordu; AYNI yanitin `MB_Analiz_Log`
    # sonucu ASENKRON YONLENDIRMEYE bagliydi. Fonksiyon sayisi AYNI.
    "R/helpers_pk_worker_observers.R" = c(159L, 10L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 145/11 -> 155/12 (OLCULEN).
    # Dogrudan cikis artik CIKARILAN metni `pk_direct_exit_is_db_failure()`
    # fonksiyonuna gecirir; eskiden ham liste gecildigi icin DB hatasi tespiti
    # her zaman FALSE donuyordu.
    # BILINCLI GUNCELLEME (inceleme takibi): 155/12 -> 165/12 (OLCULEN).
    # Metin cikarilamadiginda artik KAPALI BASARISIZ olunur (ham liste
    # siniflandiriciya gecmez) ve olu `durduruldu` dallari kaldirildi.
    "R/helpers_pk_worker_direct_exit.R" = c(165L, 12L),
    "R/helpers_deep_analysis_sql.R" = c(210L, 15L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): 215/15 -> 254/19. Bu bir BOLME'dir,
    # buyume degil: birincil baglantinin idempotent birakicisi ve telemetri icin
    # kisa omurlu baglanti saglayicisi orkestratorden (R/helpers_deep_analysis.R)
    # BURAYA tasindi; orkestrator ayni anda 677/14 -> 649/11'e DUSTU ve kendi
    # butcesi (680/14) DEGISMEDI. Neden: derin analiz birincil baglantiyi TUM
    # analiz boyunca tutuyordu; ana surecteki erken-birakma sarmalayicisi worker
    # bootstrap'ina DAHIL DEGILDIR, bu yuzden eszamanli derin isciler SQL Server
    # oturumlarini tuketebiliyordu. Olculen 254/19.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 254 -> 264 satir (OLCULEN).
    # `stash_deep_footer()` artik `facts` / `fallback_text` / `query_id` / `mode`
    # ADLANDIRILMIS argumanlarini kabul eder; orkestrator bunlari gecerken
    # "unused arguments" hatasi aliyor ve v2 kanonik olgu kaydi provenance
    # yuvasina HIC tasinmiyordu. Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (inceleme takibi): 264/19 -> 275/19 (OLCULEN).
    # Bozuk filtre nedeniyle DUSURULEN paket artik `pk_observation` icine de
    # yazilir; aksi halde ayni paket telemetriye/alt bilgiye BASARILI gidiyordu.
    "R/helpers_deep_analysis_reconcile.R" = c(275L, 19L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 250 -> 260 satir, 19 -> 20
    # fonksiyon (OLCULEN). `pk_deep_halt_status()` eklendi: `stop_check()` iki
    # AYRI nedeni tek boole'de birlestirdigi icin derin yol her durdurmayi ham
    # `"cancelled"` raporluyor, kullanicinin HIC durdurmadigi bir son tarih
    # asimi "siz iptal ettiniz" diye bildiriliyordu (SQL katmani ve kapi-sonrasi
    # dallar tipli durumu zaten koruyordu, yani ayni analizde iki anlatim vardi).
    "R/helpers_deep_analysis_phase6.R" = c(260L, 20L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 205 -> 211 satir (OLCULEN).
    # Bozuk `match_id` / `confidence` alani artik YALNIZCA o girdiyi atlar
    # (eskiden tum LLM yanitini dusuruyordu) ve teshis log'u Turkce metne
    # geri cevrildi. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR incelemesi): eksik `name`/`description`
    # metadata'sinda `vapply(..., character(1))` "values must be length 1" ile
    # dusuyordu; skaler indirgeme eklendi. OLCULEN taban 211 -> 227.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 227 -> 233 satir (OLCULEN).
    # Liste OLMAYAN eslesme kaydi artik atlanir; `m$match_id` atomik vektorde
    # hata verip TUM secimi dusuruyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 233 -> 258 satir,
    # 8 -> 9 fonksiyon (OLCULEN). (a) Hata metinleri artik merkezi
    # redaksiyondan gecer (surucu/DSN metni stdout'a sizabiliyordu);
    # `.deep_guvenli_log()` yardimcisi eklendi. (b) `match_id`, `confidence`
    # ve `reason` icin tekil secicideki atomik/skaler korumalari uygulanir:
    # liste degerli TEK bir kayit TUM secimi dusuruyordu.
    "R/helpers_deep_analysis_selector.R" = c(258L, 9L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 225 -> 235 satir (OLCULEN).
    # `try-error` nesnesi ARTIK gecerli bir jeton sayilmaz ve sifirlama
    # `hooked` yuvasini da temizler; aksi halde oturum-sonu kancasi bir daha
    # HIC kurulamiyordu. Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): surec-yerel ayna deposu AYRI
    # `R/helpers_pk_async_marker_store.R` dosyasina cikarildi; kalan govde OLCULEN.
    # BILINCLI GUNCELLEME (PR incelemesi): 215 -> 219 satir (OLCULEN). (a)
    # `pk_session_state_write()` artik ORTAM sarti uygular: liste bir KOPYADIR
    # ve geri okuma yazimi "kalici" gosteriyordu. (b) `.pk_marker_session_id()`
    # kimlik cozulemedigi durumda BOS DIZE yerine NESNE ADRESI dondurur; `""`
    # donen iki AYRI oturum AYNI isaret alanini paylasiyordu. Fonksiyon AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 219 -> 227 satir, 11 -> 12
    # fonksiyon (OLCULEN). Surec-yerel ayna adresi artik TEMBEL hesaplanir:
    # adres her cagriya kurulurken, `userData` yazilamayan bir oturumda bile
    # gereksiz is yapiliyordu ve FAIL-SAFE isaretlerin (terk edilmis istek,
    # iptal edilmis sahiplik) tasindigi yol gereksizce agirdi.
    "R/helpers_pk_async_request_markers.R" = c(227L, 12L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): +10 satir. Terk edilen istekler
    # kayittan SILINIR; girdi, istek-sahipli `release` kapanisini ve yakaladigi
    # durumu oturum boyunca canli tutuyordu. Fonksiyon sayisi DEGISMEDI.
    # Olculen 218.
    # BILINCLI GUNCELLEME (PR incelemesi): sohbet nesli yazimi YAZ-SONRA-OKU
    # ile dogrulanir (yutulan bir yazim iki kaydedilmemis soylesiyi AYNI
    # kimlige dusuruyordu). OLCULEN taban 218 -> 230.
    # BILINCLI GUNCELLEME (PR incelemesi): oturum KAPANDI isareti artik
    # `pk_session_state_write()` ile DOGRULANIYOR ve yazim yutulursa surec-yerel
    # ayna tasiyor (`.pk_marker_note("closed", ...)`). Yutulmus bir atama
    # `mergen_pk_session_open()` icin oturumu ACIK birakiyordu; gec biten isci
    # geri cagrisi kapanmis oturuma artefakt sunup nihai LLM'i tetikleyebilirdi.
    # BILINCLI GUNCELLEME (PR incelemesi): 240 -> 247 satir / 16 -> 16 fonksiyon
    # (OLCULEN). (a) Oturum sonunda BU OTURUMA ait sabitlemeler birakilir;
    # `pinned` deposu surec-yereldir ve terminal geri cagriya ulasamayan istek
    # anahtari surec omru boyunca kaliyordu. (b) Kalici olmayan bir nesil
    # artisi icin surec-yerel ayna eklendi; yutulan yazim iki AYRI kaydedilmemis
    # sohbeti AYNI kimlige dusuruyordu.
    "R/helpers_pk_async_session_registry.R" = c(247L, 16L),
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 239 -> 250 satir (OLCULEN).
    # Geri yukleyici artik YEREL baglama YOKKEN sarmalayiciyi KALDIRIR; eskiden
    # sinirli yurutucu surec omru boyunca bagli kaliyor ve sonraki senkron
    # istekler TAMAMLANMIS bir istegin `stop_check` kapanisini okuyordu.
    # Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 250 -> 258 satir (OLCULEN).
    # `mergen_pk_force_bounded_sync()` sinirli yurutucuyu artik SARMALAYICININ
    # kurulum cercevesine degil, HAT CEKIRDEGININ ortamina yazar. Eskiden
    # tek-cikis kancasi kuruluyken hedef ortam yanlisti: sinirsiz
    # materyalizasyon kaliyor, parcalama/sonuc-boyutu/Durdur/son tarih kapisi
    # bu yolda HIC uygulanmiyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR incelemesi): 258 -> 260 satir (OLCULEN).
    # `heuristic_score` SUTUN VARLIGI dogrulanir ve senkron-only indeksler
    # `yuzde` uzunluguna gore kirpilir: sutun kaldirilir/yeniden adlandirilirsa
    # `yuzde[senkron_only]` `NA` doner, `kutuphane[[NA_integer_]]` ise TUM PK
    # istegini yakalanmamis bir alt simge hatasiyla dusururdu. Fonksiyon AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 260 -> 266 satir (OLCULEN).
    # `best_idx` artik SINIR DENETIMINDEN gecer: skorlayici bos kutuphanede `0`
    # ya da kutuphane uzunlugunu asan bir indeks dondurdugunde asagi akistaki
    # `library[[indeks]]` erisimi TUM PK istegini yakalanmamis bir alt simge
    # hatasiyla dusururdu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_routing.R" = c(266L, 21L),
    # BILINCLI GUNCELLEME (PR #705 P2 takibi): 232 -> 240 satir (OLCULEN).
    # `mergen_pk_send_snapshot()` anahtar plani alinamadiginda ACIK bir
    # "snapshot_failed" isareti dondurur; `NULL` donmek `%||%` yedegini
    # devreye sokuyor ve ertelenen devam kapanisi anahtari DAKIKALAR SONRA
    # CANLI cozerek tek istegi IKI farkli yapilandirmadan derliyordu.
    # Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 240 -> 255 satir (OLCULEN).
    # (a) Cip gonderim hatasi artik `TRUE` dondurmez (sendCustomMessage yedegi
    # calisir); (b) `pk_export_serve` YOKKEN ek tasiyan sonuc KAPALI BASARISIZ
    # olur; (c) DOSYASIZ ek (refused/failed/empty) URL beklemez ve BASARILI bir
    # analiz artik `export_failed` ile atilmaz. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 255 -> 259 satir (OLCULEN).
    # Oturum yedegi artik `sendCustomMessage()` hatasini BASARI saymaz;
    # kapali websocket icin cipler teslim edilmis kaydediliyordu.
    # BILINCLI GUNCELLEME (PR incelemesi): 259 -> 260 satir (OLCULEN). DOSYASIZ
    # bir ekte `pk_export_serve()` hata firlattiginda TAMAMLANMIS analiz artik
    # `export_failed` ile DEGISTIRILMEZ (URL denetimi bu durumu ZATEN atliyor).
    # Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_lifecycle.R" = c(260L, 17L),
    # BILINCLI GUNCELLEME (PR #705): `pk_stopped` artik tipli `pk_halt_status`
    # tasir; son tarih kullanici iptali gibi raporlanmaz.
    # Tavan 1 satir bayatti (olculen 223); TAM olculen degere cekildi.
    # BILINCLI GUNCELLEME (PR #705 inceleme): +4 satir. Hazirlik artik ISTEGIN
    # ORIJINAL baslangicini alir; `Sys.time()`i yeniden okumak mutlak son tarihi
    # hazirlik suresi kadar ILERI atiyordu. Fonksiyon sayisi DEGISMEDI. Olculen 227.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 227 -> 244 satir (OLCULEN).
    # Iki neden: (a) cift baglam korumasi `&&` yerine `||` kullanir -- tek bir
    # baglam bile hatali oldugunda kapali basarisiz olunur; (b) depo koku
    # cozumu (env + `getwd()` anahtarli) BELLEKLENIR, boylece UNC/NFS uzerinde
    # `dir.exists()`/`normalizePath()` sondalari Shiny olay dongusune dusmez.
    # Fonksiyon sayisi ARTMAMISTIR.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 244 -> 255 satir (OLCULEN).
    # `pk_safe_log_text()` cagrisi ARTIK kendi `tryCatch`i icindedir: satir
    # DISTAKI handler'in ICINDE calistigi icin buradaki hata yakalanmiyor,
    # cagirana yayiliyor ve senkron PK istegi `values$is_sending` ASILI
    # kalacak sekilde dusuyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_async_apply.R" = c(255L, 16L),
    # BILINCLI GUNCELLEME (PR #705 inceleme): 145 -> 163 satir (OLCULEN).
    # URL uretilemediginde artifact artik `status = "failed"` isaretlenir;
    # eskiden kayit basarisizligi SESSIZ kalip disa aktarimi BASARILI
    # gosteriyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 163 -> 173 satir (OLCULEN).
    # Dogrulanmis akis zinciri (Shiny `rookCall()` -> httpuv `bodyFile`)
    # belgelendi. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 173 -> 200 satir (OLCULEN).
    # `registerDataObj` saglamayan bir oturumdaki ERKEN DONUS, `kayit_basarisiz`
    # kapisini ATLIYORDU: artefakt `status = "ok"` + `url = NULL` ile donuyor,
    # kullanici indirilemeyen bir ek karti goruyor ve uretilen dosya temizlik
    # kaydi olmadan diskte KALIYORDU. Ayrica `NA` bir kayit URL'i artik
    # basarili sayilmaz (`nzchar(NA)` TRUE doner). Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 200 -> 203 (OLCULEN).
    # Kayit basarisiz oldugunda artefakt artik dosya TASIMAZ: dosyalar unlink
    # edilir ve `artifact$files` bosaltilir (oturumsuz dal ile AYNI sozlesme);
    # aksi halde baglantisiz dosya girdileri asagi akisa geciyor ve dosyalar
    # oturum sonuna kadar diskte kaliyordu. Fonksiyon sayisi AYNI.
    "R/helpers_pk_export_serve.R" = c(203L, 10L),
    # Tavan 1 satir bayatti (olculen 439); TAM olculen degere cekildi.
    # BILINCLI GUNCELLEME (PR #705 inceleme): +15 satir. Son tarih bekcisi artik
    # promise geri cagrilariyla AYNI istek-kimligi/terk/oturum/sohbet korumasindan
    # gecer; takili bir iscide BASKA bir sohbetin arayuzunu bozabiliyordu.
    # Fonksiyon sayisi DEGISMEDI. Olculen 454.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 454 -> 491 satir / 14 -> 15
    # fonksiyon (OLCULEN).
    # Iki neden: (a) tamamlanma cipi artik `eklenen$id` alir -- eskiden TUM mesaj
    # listesi gecildigi icin cip hedefi cozulemiyordu; (b) iptal jetonu SABIT
    # 300 saniyelik zamanlayiciyla degil, ISCI FUTURE'I YERLESTIGINDE temizlenir
    # (`jeton_yerlesmede_temizle()`; onFulfilled/onRejected/catch): yerli bir
    # cagrida takilan isci, jeton temizlendikten sonra donup asama kapilarini
    # "iptal yok" okuyarak SQL/analiz/disa aktarim isini surdurebiliyordu.
    # Zamanlayici SON CARE olarak TEK SEFERLIK kalir; kendini yeniden kuran bir
    # zincir `later` kuyrugunu saatlerce dolu tutup ayni R oturumundaki
    # Shiny/`testServer` akislarini bloke ediyordu (+1 fonksiyon: ortak kapanis).
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 491 -> 498 satir (OLCULEN).
    # Gonderim durumu temizligi artik `identical(aktif, req_id)` ile korunur:
    # `karar$apply` FALSE olan BAYAT bir geri cagri, DAHA YENI bir istegin
    # gonderim/yazim durumunu sifirliyordu. Fonksiyon sayisi AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 498 -> 500 satir (OLCULEN).
    # (a) SABIT GECIKMELI jeton temizligi KALDIRILDI: yerli bir cagrida
    # bloklanan isci o gecikmeden sonra donup asama kapilarini "iptal yok"
    # okuyabiliyordu. Jeton artik YALNIZCA yerlesme yolunda temizlenir; kayip
    # iscinin jetonunu gonderim girisindeki YAS TABANLI supurucu toplar.
    # (b) Sunulan artifact sahipligi devam yolunda da ACIKCA devredilir
    # ("asili sahip" durumu kalkti). Fonksiyon sayisi 15 -> 14 (bayrak yardimci
    # kapanisi ile birlikte kaldirildi).
    # BILINCLI GUNCELLEME (PR incelemesi): bekci gecikmesi artik SONLULUK
    # denetiminden geciyor. Mutlak son tarih kurulmamisken
    # `mergen_pk_request_deadline_at()` `NA` donuyor, `!is.null(NA)` TRUE
    # oldugu icin bekci `delay = Inf` ile zamanlaniyor ve HIC ATESLENMIYORDU.
    # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 504 -> 517 satır (ÖLÇÜLEN).
    # (a) Jeton temizliği FAIL-SOFT: kaldırılamayan bir `.flag` dosyası
    # `bitir_istek()` içinde fırlatınca `is_sending`/yazıyor sarmalayıcısı
    # HİÇ temizlenmiyor, sohbet oturum sonuna kadar KİLİTLİ kalıyordu.
    # (b) Bayat köken kaydı ARTIK her terminal hata yolunda tüketilir;
    # önceki isteğin otoriter alt bilgisi ilgisiz bir altyapı hatasına
    # iliştiriliyordu. Fonksiyon sayısı AYNI.
    # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 517 -> 541 satir, 14 -> 15
    # fonksiyon (OLCULEN). Iki inceleme duzeltmesi: (a) bayat koken tuketimi
    # `promises::then()` KURULMADAN ONCE yapilir, aksi halde geri cagrinin
    # icinde calisip yeni istegin kaydini tuketebiliyordu; (b) son tarih bekci
    # kopegi adlandirilmis bir govdeye alindi ve `mergen.pk.async.deadline_at`
    # degerini YENIDEN OKUYUP kendini yeniden zamanliyor -- sorgu secimi son
    # tarihi guncelledigi icin dondurulmus bir an yanlis zamanda atesleniyordu.
    "R/server_handler_pk_async.R" = c(541L, 15L)
  )

  for (dosya in names(butceler)) {
    # Yol eslesmesi repo genelindeki sozlesmeyle AYNI: `(^|/)...$` son ek
    # eslesmesi (bkz. tests/testthat/test-maintainability-ratchet.R). Tam
    # esitlik, raporun repo koku onegini ayirmasina bagimlidir; Windows VM'de
    # repo koku UNC + Turkce karakter icerdigi icin bu bagimlilik kirilgandir.
    satir <- rapor[grepl(paste0("(^|/)", gsub("([.])", "\\\\\\1", dosya), "$"),
                         rapor$file, perl = TRUE), , drop = FALSE]
    expect_equal(nrow(satir), 1L, info = dosya)
    expect_lte(satir$lines[1], butceler[[dosya]][1],
               label = sprintf("%s satir", dosya))
    expect_lte(satir$functions[1], butceler[[dosya]][2],
               label = sprintf("%s fonksiyon", dosya))
  }
})
