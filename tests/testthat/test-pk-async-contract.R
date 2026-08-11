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
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker.R",
    "R/helpers_deep_analysis_reconcile.R",
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
    "R/helpers_pk_result_size.R",
    "R/helpers_pk_cache.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_async_bootstrap.R",
    "R/helpers_pk_async_request.R",
    "R/helpers_pk_async_worker.R"
  ))

  # Uzlaştırma katmanı bağlam kurucudan ve orkestratörden ÖNCE yüklenmelidir.
  expect_source_manifest_order_for_tests(c(
    "R/helpers_deep_analysis_reconcile.R",
    "R/helpers_deep_analysis_context.R",
    "R/helpers_deep_analysis.R"
  ))

  # Gönderim işleyicisi send_message'dan ÖNCE yüklenmelidir (o buna delege eder).
  expect_source_manifest_order_for_tests(c(
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
  # Oturum kapanışı işçiyi durdurur (geri çağrıyı atmak YETMEZ).
  expect_true(.pk_async_has(metin, "onSessionEnded"))
  expect_true(.pk_async_has(metin, "pk_cancel_token_signal("))
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
  istek <- .pk_async_read_bytes(file.path(.pk_async_repo(), "R/helpers_pk_async_request.R"))

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
  istek <- .pk_async_read_bytes(file.path(kok, "R/helpers_pk_async_request.R"))

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
  expect_true(.pk_async_has(derin, "deep_query_ceiling <- pk_deep_max_queries()"))
  expect_true(.pk_async_has(derin, "max_queries = deep_query_ceiling"))
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

  # Ölçülen taban çizgisi + küçük baş boşluk. GLOBAL tavan (800 satır /
  # 25 fonksiyon) ihlal edilmemelidir; bu yüzden hiçbir bütçe 24'ü aşmaz.
  butceler <- list(
    "R/helpers_pk_async_cancel.R" = c(290L, 24L),
    "R/helpers_pk_result_size.R" = c(345L, 10L),
    "R/helpers_pk_cache.R" = c(355L, 19L),
    "R/helpers_pk_sql_execute.R" = c(215L, 17L),
    "R/helpers_pk_async_bootstrap.R" = c(255L, 16L),
    "R/helpers_pk_async_request.R" = c(305L, 21L),
    "R/helpers_pk_async_worker.R" = c(190L, 17L),
    "R/helpers_deep_analysis_reconcile.R" = c(375L, 24L),
    "R/helpers_pk_async_apply.R" = c(195L, 14L),
    "R/server_handler_pk_async.R" = c(220L, 19L)
  )

  for (dosya in names(butceler)) {
    satir <- rapor[rapor$file == dosya, , drop = FALSE]
    expect_equal(nrow(satir), 1L, info = dosya)
    expect_lte(satir$lines[1], butceler[[dosya]][1],
               label = sprintf("%s satir", dosya))
    expect_lte(satir$functions[1], butceler[[dosya]][2],
               label = sprintf("%s fonksiyon", dosya))
  }
})
