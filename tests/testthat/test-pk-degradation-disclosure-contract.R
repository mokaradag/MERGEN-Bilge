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

# YORUM SATIRLARI TARAMADAN ÇIKARILIR.
#
# Bu dosyadaki POZİTİF kaynak taramaları ham metni okuyordu; bir refaktör
# gerçek çağrıyı silip AÇIKLAYICI YORUMU bıraktığında iddialar yine geçiyor,
# TTS köken sözleşmesi "başarılı" raporlanırken alt bilgi seslendirilebiliyordu.
.pk_deg_code_text <- function(path) {
  ham <- readBin(path, what = "raw", n = file.info(path)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  satirlar <- strsplit(gsub("\r\n", "\n", metin, fixed = TRUE), "\n", fixed = TRUE)[[1]]
  # Yalnizca TAM SATIR yorumlari atilir; satir sonu yorumlari kodu da tasir.
  paste(satirlar[!grepl("^[[:space:]]*#", satirlar)], collapse = "\n")
}

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

  # İZOLE YÜKLEME: taban dosya manifest sırasına göre AÇIKÇA önce gelir.
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters_base.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters.R"),
         encoding = "UTF-8", local = env)

  env
}

.pk_deg_call <- function(env, prompt = "Radar projesinde kimler var?", stop_check = NULL,
                         data_context = data.frame(ProjeAdi = "X", stringsAsFactors = FALSE)) {
  env$extract_filter_criteria_from_prompt(
    user_prompt = prompt,
    data_context = data_context,
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

test_that("kısa ve çok satırlı GEÇERLİ JSON yanıtı malformed sayılmaz", {
  # GERİLEME KORUMASI: eskiden `nchar(ai_text) < 50` kapısı, tamamen geçerli
  # kısa yanıtları ayrıştırma bile yapmadan `malformed` yapıyordu; v2'de bu
  # statü REDde dönüştüğü için meşru bir sayım isteği reddediliyordu.
  kisa <- '{"filters":[],"aggregation":"count"}'
  expect_lt(nchar(kisa), 50L)
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json(kisa)))$status,
    "ok_no_filter"
  )

  # Çok satırlı (pretty-print) JSON — istem örneğinin kendi biçimi — yapısal
  # kapıda düşmemelidir.
  cok_satirli <- "{\n  \"filters\": [],\n  \"aggregation\": \"count\"\n}"
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json(cok_satirli)))$status,
    "ok_no_filter"
  )

  # ŞEMA KAPISI KORUNUR: tanınan hiçbir alan taşımayan nesne hâlâ malformed.
  expect_identical(
    .pk_deg_call(.pk_deg_env(function(...) .pk_deg_json('{"beklenmeyen":1}')))$status,
    "malformed"
  )
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

  # `Durum` sütunu fikstürde 0/1 KODLUDUR: durum kısayolu (aktif -> "1")
  # yalnızca değerin GERÇEKTEN mantıksal/ikili olduğu sütunlarda uygulanır
  # (bkz. test-pk-filter-stabilization-behavior.R "durum kisayolu YALNIZCA
  # ikili sutunda uygulanir"). Metin bir `Durum` sütununda yeniden yazım tam
  # eşleşmeyi SIFIR satıra düşürürdü; buradaki sözleşme kısayolun KORUNDUĞUdur.
  sonuc <- .pk_deg_call(env, data_context = data.frame(
    ProjeAdi = "X", Durum = c(1, 0), stringsAsFactors = FALSE
  ))

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
  txt <- .pk_deg_code_text(path)

  expect_true(grepl("pk_filter_status_is_degraded", txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_degradations_from_filter_status", txt, fixed = TRUE, useBytes = TRUE))
  # Gözlem çağrıları hem boş sonuç hem başarı dalında bulunmalı.
  expect_true(grepl("outcome = \"BosSonuc\"", txt, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("outcome = \"Basarili\"", txt, fixed = TRUE, useBytes = TRUE))
})

test_that("nihai yanıt sonlandırma noktaları alt bilgiyi iliştirir", {
  # Alt bilgi R'ye aittir; modele yazdırılmaz. Üç sonlandırma dikişinin de
  # dekorasyona ULAŞTIĞI doğrulanır.
  #
  # SAHİPLİK SINIRI DEĞİŞTİ (PR #705 incelemesi): sohbet ve akış dikişleri
  # `pk_provenance_decorate()`i ARTIK DOĞRUDAN çağırmaz. Doğrulama TEK sınırdan
  # (`R/helpers_pk_provenance_peek.R`) geçer: `mergen_pk_validated_texts()` /
  # `mergen_pk_stream_validated_text()` ekrana giden `display`, seslendirmeye
  # giden alt-bilgisiz `tts` gövdesini ve `validated` bayrağını BİRLİKTE üretir.
  # İki dikişin ayrı ayrı dekore etmesi, `block` kipinde kararın İKİ KEZ
  # sorulmasına ve ikinci sorguda bekleyen kayıt zaten tüketildiği için ham
  # düzyazının teslim edilmesine yol açıyordu.
  #
  # Muhafız bu yüzden dikişin dekoratöre giden YOLUNU arar; sınırın kendisinde
  # gerçek çağrı ayrıca doğrulanır.
  root <- resolve_repo_root_for_tests()

  .pkd_kod_satirlari <- function(rel) {
    path <- file.path(root, rel)
    raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
    txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
    # YORUM SATIRLARI KANIT SAYILMAZ: `grepl("pk_provenance_decorate", ...)` bir
    # Türkçe yorumla da eşleşir. Gerçek çağrı kaldırılıp yalnızca yorum
    # bırakılırsa muhafız yeşil kalırken alt bilgi HİÇ eklenmezdi.
    satirlar <- strsplit(gsub("\r\n?", "\n", txt), "\n", fixed = TRUE)[[1]]
    satirlar[!grepl("^\\s*#", satirlar, useBytes = TRUE)]
  }

  # `helpers_chat_runtime.R` ARTIK DOĞRUDAN DEKORE ETMEZ: benzetimli akış
  # sonlandırması, gerçek akış hattıyla AYNI kapalı-başarısız sınırı kullanan
  # `pk_stream_display_text()` üzerinden geçer. Sınırın kendisi aşağıda
  # `helpers_pk_provenance_peek.R` içinde ayrıca doğrulanır; delegasyon
  # zinciri bu yüzden ZAYIFLAMAZ.
  seams <- list(
    "R/server_handler_true_streaming.R" = "mergen_pk_stream_validated_text(",
    "R/server_llm_response_handlers.R"  = "mergen_pk_validated_texts(",
    "R/helpers_chat_runtime.R"          = "pk_stream_display_text("
  )

  for (rel in names(seams)) {
    kod <- .pkd_kod_satirlari(rel)
    expect_true(
      any(grepl(seams[[rel]], kod, fixed = TRUE, useBytes = TRUE)),
      info = sprintf("%s alt bilgi sınırına ULAŞMALIDIR (%s).", rel, seams[[rel]])
    )
  }

  # DELEGASYON GERÇEKTEN DOĞRULANMIŞ METNE ULAŞIR: `pk_stream_display_text()`
  # yalnızca bir sarmalayıcı olsaydı, `helpers_chat_runtime.R` iddiası
  # anlamsız kalırdı.
  peek_kod <- .pkd_kod_satirlari("R/helpers_pk_provenance_peek.R")
  expect_true(
    any(grepl("pk_stream_display_text <- function", peek_kod,
              fixed = TRUE, useBytes = TRUE)),
    info = "pk_stream_display_text() koken sinirinda TANIMLI olmalidir."
  )
  expect_true(
    any(grepl("mergen_pk_stream_validated_text(", peek_kod,
              fixed = TRUE, useBytes = TRUE)),
    info = "pk_stream_display_text() dogrulanmis metin sinirina ULASMALIDIR."
  )

  # SINIRIN KENDİSİ GERÇEKTEN DEKORE EDER: yukarıdaki delegasyon iddiaları,
  # `pk_provenance_decorate()` sınırdan da kaldırılırsa anlamsız kalırdı.
  sinir_kod <- .pkd_kod_satirlari("R/helpers_pk_provenance_peek.R")
  expect_true(
    any(grepl("pk_provenance_decorate(", sinir_kod, fixed = TRUE, useBytes = TRUE)),
    info = "R/helpers_pk_provenance_peek.R dekoratörü ÇAĞIRMALIDIR."
  )
  for (fn in c("mergen_pk_validated_texts", "mergen_pk_stream_validated_text")) {
    expect_true(
      any(grepl(paste0(fn, " <- function"), sinir_kod, fixed = TRUE, useBytes = TRUE)),
      info = sprintf("R/helpers_pk_provenance_peek.R `%s()` TANIMLAMALIDIR.", fn)
    )
  }

  # TTS yolunda İKİ kural birden geçerlidir:
  #   1) Alt bilgi (kaynakça/ek) SESLENDİRİLMEZ.
  #   2) `block` kipinde DOĞRULANMAMIŞ düzyazı da seslendirilmez; söylenen ses
  #      geri alınamaz. Bu yüzden motor artık ham `full_response` ile değil,
  #      doğrulanmış ve alt bilgisi ayrılmış `tts_metni` ile çağrılır.
  path <- file.path(root, "R", "helpers_chat_runtime.R")
  txt <- .pk_deg_code_text(path)

  expect_true(
    grepl("tts_engine(tts_metni, tts_voice)", txt, fixed = TRUE, useBytes = TRUE),
    info = "TTS motoru ham full_response ile ÇAĞRILMAMALIDIR."
  )
  expect_false(
    grepl("tts_engine(full_response, tts_voice)", txt, fixed = TRUE, useBytes = TRUE),
    info = "Ham full_response TTS'e verilmemelidir (block kipinde doğrulanmamış olabilir)."
  )
  # SAHİPLİK SINIRI: `block` kipi tespiti ve alt bilgi ayırma kararı
  # `mergen_pk_block_mode_texts()` içindedir (`helpers_pk_provenance_peek.R`);
  # `helpers_chat_runtime.R` yalnızca SONUCU uygular. Karar bu yüzden yeni
  # sahibinde aranır — çalışma zamanı kodu geri taşınmaz.
  expect_true(
    grepl("mergen_pk_block_mode_texts", txt, fixed = TRUE, useBytes = TRUE),
    info = "chat runtime block-kipi metinlerini yardımcıdan almalıdır."
  )

  peek_path <- file.path(root, "R", "helpers_pk_provenance_peek.R")
  peek_txt <- .pk_deg_code_text(peek_path)

  expect_true(
    grepl("pk_provenance_blocks_streaming", peek_txt, fixed = TRUE, useBytes = TRUE),
    info = "block kipi TTS'ten ÖNCE tespit edilmelidir."
  )
  expect_true(
    grepl("endsWith(dekore, alt_bilgi)", peek_txt, fixed = TRUE, useBytes = TRUE),
    info = "Alt bilgi seslendirilecek metinden AYRILMALIDIR."
  )

  # DAVRANIŞ: yardımcı gerçekten alt bilgiyi seslendirmeden ayırır.
  ortam <- new.env(parent = globalenv())
  assign("%||%", function(a, b) if (is.null(a)) b else a, envir = ortam)
  source(peek_path, encoding = "UTF-8", local = ortam)
  ortam$pk_provenance_blocks_streaming <- function(session, request_id = NULL) TRUE
  ortam$pk_provenance_peek <- function(session, request_id = NULL) list(footer = "\n\nKAYNAKCA")
  ortam$pk_provenance_decorate <- function(text, session, request_id = NULL) {
    paste0("DOGRULANMIS GOVDE", "\n\nKAYNAKCA")
  }

  metinler <- ortam$mergen_pk_block_mode_texts("HAM GOVDE", NULL, request_id = "req-1")
  expect_identical(metinler$display, "DOGRULANMIS GOVDE\n\nKAYNAKCA")
  expect_identical(metinler$tts, "DOGRULANMIS GOVDE")
})
