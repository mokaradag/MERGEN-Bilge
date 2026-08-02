# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-degradation-disclosure-contract.R
# Açıklama: Faz 0 tipli filtre adaptörü ve bozulma bildirimi sözleşmesi.
#           Tamamen çevrimdışı ve belirlenimcidir: gerçek LLM, DB, tarayıcı,
#           ağ veya gizli değer GEREKMEZ; LLM çağrısı yerel bir vekil ile
#           taklit edilir.
#
# Çözülen kör nokta (D9):
#   Bugün zaman aşımı, hata, bozuk yanıt ve "gerçekten filtre gerekmiyordu"
#   durumlarının HEPSİ `list(filters = list(), aggregation = NULL)` döndürüyor.
#   Kullanıcı tek bir proje sorduğunda uç nokta yavaşsa araç, 4.000 projenin
#   tamamını hiç söylemeden analiz edebiliyor.
#
# Kapsanan sözleşmeler:
#   - `no_filter`, `timeout` ve `error` BİRBİRİNDEN AYRI tipli durumlar üretir.
#   - Bozuk/çözümlenemeyen yanıt ayrı bir `malformed` durumu üretir.
#   - Zaman aşımı KULLANICININ GÖRDÜĞÜ yanıta çıkar, yalnızca logda kalmaz.
#   - Gözlem amaçlıdır: `filters`/`aggregation` şekli ve içeriği DEĞİŞMEZ
#     (v1 motorunun filtre kararı korunur).
# ==============================================================================

# Filtre yardımcısını izole bir ortama yükleyip LLM/kimlik bağımlılıklarını
# yerel vekillerle karşılar.
.pk_deg_env <- function(llm_fn) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$summarize_columns_for_ai <- function(...) "SUTUN OZETI"
  env$api_config <- list(local_models = c("sahte-model"))
  env$resolve_local_llm_credentials <- function(...) list(default_api_key = "")
  env$call_local_llm <- llm_fn

  source(file.path(repo_root, "R", "helpers_pk_analysis_filters.R"),
         encoding = "UTF-8", local = env)

  env
}

.pk_deg_call <- function(env, prompt = "Radar projesinde kimler var?", stop_check = NULL) {
  env$extract_filter_criteria_from_prompt(
    user_prompt = prompt,
    data_context = data.frame(ProjeAdi = "X", stringsAsFactors = FALSE),
    available_columns = "ProjeAdi",
    conn = NULL,
    session = NULL,
    stop_check = stop_check
  )
}

.pk_deg_json <- function(x) list(content = x)

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(repo_root, "R", "helpers_pk_provenance.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("meşru 'filtre gerekmiyordu' sonucu ok_no_filter üretir", {
  env <- .pk_deg_env(function(...) {
    .pk_deg_json('{"filters": [], "filter_expression": null, "aggregation": "count", "group_column": null}')
  })

  sonuc <- .pk_deg_call(env)

  expect_identical(sonuc$status, "ok_no_filter")
  expect_length(sonuc$filters, 0L)
})

test_that("geçerli filtre üreten yanıt ok_filtered üretir", {
  env <- .pk_deg_env(function(...) {
    .pk_deg_json(paste0(
      '{"filters": [{"column":"ProjeAdi","value":"Radar","operation":"contains"}],',
      ' "filter_expression": null, "aggregation": "list", "group_column": null}'
    ))
  })

  sonuc <- .pk_deg_call(env)

  expect_identical(sonuc$status, "ok_filtered")
  expect_length(sonuc$filters, 1L)
  expect_identical(sonuc$filters[[1]]$column, "ProjeAdi")
})

test_that("zaman aşımı ok_no_filter'dan AYRI bir durum üretir", {
  env <- .pk_deg_env(function(...) stop("Timeout was reached: [endpoint] operation timed out"))

  sonuc <- .pk_deg_call(env)

  expect_identical(sonuc$status, "timeout")
  # Kritik ayrım: boş filtre listesi aynı ama durum FARKLI.
  expect_length(sonuc$filters, 0L)
})

test_that("genel hata zaman aşımından AYRI bir durum üretir", {
  env <- .pk_deg_env(function(...) stop("connection refused by upstream"))

  sonuc <- .pk_deg_call(env)

  expect_identical(sonuc$status, "error")
  expect_length(sonuc$filters, 0L)
})

test_that("üç durum (no_filter / timeout / error) birbirinden AYRIDIR", {
  no_filter <- .pk_deg_call(.pk_deg_env(function(...) {
    .pk_deg_json('{"filters": [], "filter_expression": null, "aggregation": null, "group_column": null}')
  }))$status
  timeout <- .pk_deg_call(.pk_deg_env(function(...) stop("Timeout was reached")))$status
  error <- .pk_deg_call(.pk_deg_env(function(...) stop("beklenmeyen arıza")))$status

  expect_equal(length(unique(c(no_filter, timeout, error))), 3L)
  expect_setequal(c(no_filter, timeout, error), c("ok_no_filter", "timeout", "error"))
})

test_that("bozuk/çözümlenemeyen yanıtlar malformed üretir", {
  # JSON değil
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json(strrep("duz metin ", 20)))) $status,
    "malformed"
  )
  # Çok kısa
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json("{}")))$status,
    "malformed"
  )
  # Bozuk JSON
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json(paste0('{"filters": [ {"column": ', strrep("x", 60)))))$status,
    "malformed"
  )
  # Boş içerik
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) list(content = NULL)))$status,
    "malformed"
  )
})

test_that("kullanıcı durdurması ayrı bir durum üretir ve bozulma sayılmaz", {
  env <- .pk_deg_env(function(...) .pk_deg_json('{"filters": [], "aggregation": null}'))

  sonuc <- .pk_deg_call(env, stop_check = function() TRUE)

  expect_identical(sonuc$status, "stopped")
  expect_false(pk_filter_status_is_degraded("stopped"))
})

test_that("adaptör gözlem amaçlıdır: filters/aggregation sözleşmesi değişmez", {
  # v1 motorunun hangi filtreyi uyguladığı DEĞİŞMEMELİDİR; yalnızca yanına
  # `status` eklenir.
  env <- .pk_deg_env(function(...) {
    .pk_deg_json(paste0(
      '{"filters": [{"column":"Durum","value":"aktif","operation":"exact_match"}],',
      ' "filter_expression": "(A == 1)", "aggregation": "group_by", "group_column": "Departman"}'
    ))
  })

  sonuc <- .pk_deg_call(env)

  expect_identical(sonuc$aggregation, "group_by")
  expect_identical(sonuc$group_column, "Departman")
  expect_identical(sonuc$filter_expression, "(A == 1)")
  # Alan-değeri normalizasyonu (aktif -> "1") korunmuş olmalı.
  expect_identical(sonuc$filters[[1]]$value, "1")

  # Boş sonuç şekli de korunur: filters listesi, aggregation adı mevcut.
  bos <- .pk_deg_call(.pk_deg_env(function(...) stop("Timeout was reached")))
  expect_true(is.list(bos$filters))
  expect_true("aggregation" %in% names(bos))
  expect_null(bos$aggregation)
})

test_that("zaman aşımı KULLANICININ GÖRDÜĞÜ yanıta çıkar", {
  # Yalnızca logda kalması yeterli değildir (plan §1 sonucu).
  status <- .pk_deg_call(.pk_deg_env(function(...) stop("Timeout was reached")))$status

  bozulmalar <- pk_degradations_from_filter_status(status)
  expect_length(bozulmalar, 1L)
  expect_identical(bozulmalar[[1]]$code, "filter_timeout")

  footer <- pk_build_provenance_footer(list(
    query_id = "q042", query_name = "Aktivite Rol Atamaları",
    filter_status = status, filters = list(),
    authorized_rows = 4000L, filtered_rows = 4000L,
    degradations = bozulmalar
  ))

  session <- list(userData = new.env(parent = emptyenv()))
  pk_provenance_clear(session, request_id = "req-1")
  pk_provenance_stash(session, footer, request_id = "req-1")

  kullanici_yaniti <- pk_provenance_decorate(
    "Toplam 4.000 proje incelendi.", session, request_id = "req-1"
  )

  expect_true(grepl("zaman aşımına", kullanici_yaniti, fixed = TRUE))
  expect_true(grepl("UYGULANAMADI", kullanici_yaniti, fixed = TRUE))
})

test_that("modül boş sonuç dalında bozulma nedenini kullanıcıya bildirir", {
  # Bozulma varken boş sonucu sessizce "veri yok" gibi sunmak yanıltıcıdır.
  # Kaynak taraması Windows/VM güvenliği için bayt-güvenli okunur.
  path <- file.path(resolve_repo_root_for_tests(), "R", "module_proje_kaynak_analizi.R")
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")

  expect_true(grepl("pk_filter_status_is_degraded", txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_degradations_from_filter_status", txt, fixed = TRUE, useBytes = TRUE))
  # Gözlem çağrıları hem boş sonuç hem başarı dalında bulunmalı.
  expect_true(grepl("outcome = \"BosSonuc\"", txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("outcome = \"Basarili\"", txt, fixed = TRUE, useBytes = TRUE))
})

test_that("nihai yanıt sonlandırma noktaları alt bilgiyi iliştirir", {
  # Alt bilgi R'ye aittir; modele yazdırılmaz. Üç sonlandırma dikişinin de
  # dekoratörü çağırdığı doğrulanır.
  root <- resolve_repo_root_for_tests()
  seams <- c(
    "R/server_handler_true_streaming.R",
    "R/server_llm_response_handlers.R",
    "R/helpers_chat_runtime.R"
  )

  for (rel in seams) {
    path <- file.path(root, rel)
    raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")

    expect_true(
      grepl("pk_provenance_decorate", txt, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s alt bilgiyi iliştirmelidir.", rel)
    )
  }

  # TTS yolunda alt bilgi SESLENDİRİLMEMELİDİR: dekoratör, tts_engine
  # çağrısından sonra gelen final_text üzerinde çalışır.
  path <- file.path(root, "R", "helpers_chat_runtime.R")
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")

  expect_true(
    regexpr("pk_provenance_decorate", txt, fixed = TRUE, useBytes = TRUE) <
      regexpr("tts_engine(full_response, tts_voice)", txt, fixed = TRUE, useBytes = TRUE),
    info = "Dekoratör, TTS'e giden full_response'u DEĞİŞTİRMEMELİDİR."
  )
})
