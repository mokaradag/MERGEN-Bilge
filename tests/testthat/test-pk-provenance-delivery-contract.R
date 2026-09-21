# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-provenance-delivery-contract.R
# Açıklama: Köken alt bilgisi teslim sözleşmeleri:
#           derin analiz telemetrisi/kökeni, doğrudan yanıt dekorasyonu ve
#           TTS yükünden köken alt bilgisinin çıkarılması.
# ==============================================================================

.pk_p2_read_source <- function(rel_path) {
  path <- file.path(resolve_repo_root_for_tests(), rel_path)
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  metin <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
  # SATIR SONLARI NORMALLEŞTİRİLİR (CLAUDE.md "CRLF corollary").
  # `.gitattributes` yalnızca TEK bir dosyada `eol=lf` zorlar; Windows CI
  # checkout'u (core.autocrlf) diğer kaynakları CRLF olarak yazar. Bu durumda
  # `strsplit(metin, "\n")` her satırın sonunda bir `\r` bırakır ve aşağıdaki
  # üretim bloğu `parse()` edilirken "unexpected invalid token" ile düşerdi;
  # çok satırlı `fixed = TRUE` eşleşmeleri de sessizce kaçırılırdı.
  metin <- gsub("\r\n", "\n", metin, fixed = TRUE)
  gsub("\r", "\n", metin, fixed = TRUE)
}

test_that("doğrudan AI yanıtları mesaj sınırında bekleyen köken alt bilgisini tüketir", {
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜ ÖNCE KURULUR (bkz. bu dosyanın diğer bloğu): sourced
  # çalışma zamanı `%||%` çağırır ve yalnız `globalenv()` zincirini görür;
  # testthat yardımcı ortamındaki tanım o zincirde DEĞİLDİR.
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  captured <- new.env(parent = emptyenv())
  # Dekorasyon artik ISTEK KIMLIGI ile cagrilir; sahte de bunu kabul etmelidir.
  env$pk_provenance_current_request_id <- function(session) "req_test_1"
  env$pk_provenance_decorate <- function(content, session, request_id = NULL) {
    captured$request_id <- request_id
    paste0(content, "|KOKEN")
  }
  env$chat_add_message <- function(...) {
    args <- list(...)
    captured$content <- args$content
    args
  }

  runtime <- env$serverInitChatRuntime(
    session = list(),
    values = list(),
    settings_data = list(),
    output = list(),
    resolve_current_user_id = function() 7L,
    stop_generation = function() FALSE
  )

  runtime$add_message("Boş sonuç", "ai")
  expect_identical(captured$content, "Boş sonuç|KOKEN")
  # Kimliksiz tuketim, gec biten bir yanitin DAHA YENI bir istegin kaydini
  # almasina yol aciyordu; sinir artik etkin istek kimligini gecirir.
  expect_identical(captured$request_id, "req_test_1")

  runtime$add_message("Kullanıcı metni", "user")
  expect_identical(captured$content, "Kullanıcı metni")
})

test_that("derin analiz her sorguyu gözlemler ve tek birleşik köken alt bilgisi saklar", {
  testthat::skip_if_not_installed("withr")
  # Bu sözleşme v1'in `find_multiple_queries_with_ai` çoklu seçim yolunu
  # doğrular. `test_dir()` ortak test ortamında v2 seçicisi daha önce yüklenmiş
  # olabilir; VM'deki motor ayarı bu izole v1 sözleşmesini değiştirmemelidir.
  withr::local_envvar(c(MERGEN_PK_ENGINE = "v1"))

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Faz 6 (D16): kimlik kapısı, son tarih aritmetiği, sınırlı SQL yürütme ve
  # gözlem/alt bilgi FABRİKASI ayrı sahip dosyalarındadır; izole test GERÇEK
  # sahipleri yükler (CLAUDE.md davranış-testi kuralı).
  for (yardimci in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                     "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R", "helpers_pk_sql_connection.R",
                     "helpers_deep_analysis_sql.R", "helpers_deep_analysis_connection.R",
                     "helpers_deep_analysis_reconcile.R",
                     "helpers_pk_query_selection_deep.R",
                     "helpers_deep_analysis_phase6.R",
                     "helpers_deep_analysis_selector.R",
                     "helpers_deep_analysis.R")) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", yardimci),
      encoding = "UTF-8", local = env
    )
  }

  # D16 kimlik kapısı: ana yolun çözümleyicisi stub'lanır (SSO/DB yok).
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "kullanici1", reason = "ok")
  }

  env$cat <- function(...) invisible(NULL)
  env$query_library <- list()
  env$get_analysis_detail_config <- function(level) list(id = level)
  env$get_connection <- function(...) list(conn = "PRIMARY")
  env$release_connection <- function(...) invisible(TRUE)
  env$get_user_rls_info <- function(username, conn) list(authorized = TRUE)
  env$find_multiple_queries_with_ai <- function(...) {
    list(
      list(id = "q1", name = "Sorgu Bir"),
      list(id = "q2", name = "Sorgu İki")
    )
  }
  env$select_smart_query <- function(...) NULL
  env$execute_single_deep_query <- function(query, ...) {
    list(
      query_name = query$name,
      success = TRUE,
      row_count = 3L,
      pk_observation = list(
        query_id = query$id,
        query_name = query$name,
        filter_status = "disabled",
        filters = list(),
        pre_rls_rows = 4L,
        authorized_rows = 3L,
        filtered_rows = 3L,
        outcome = "Basarili"
      )
    )
  }
  env$build_deep_analysis_context <- function(...) "BIRLESIK-BAGLAM"
  env$pk_provenance_current_request_id <- function(session) "req-deep"

  env$.observed <- list()
  env$pk_analysis_observe <- function(session, conn, info) {
    env$.observed[[length(env$.observed) + 1L]] <- info
    paste0(
      "\n\n---\n**Analiz Kaynağı**\n",
      "- **Sorgu:** ", info$query_id, " · ", info$query_name, "\n"
    )
  }
  env$.stashed <- NULL
  env$pk_provenance_stash <- function(session, footer, request_id = NULL, ...) {
    env$.stashed <- list(footer = footer, request_id = request_id)
    invisible(TRUE)
  }

  result <- env$pk_deep_analysis_process(
    "iki sorguyu karşılaştır",
    list(),
    list(userData = list(system_username = "kullanici")),
    detail_level = "standart",
    stop_check = function() FALSE
  )

  expect_identical(result, "BIRLESIK-BAGLAM")
  expect_length(env$.observed, 2L)
  expect_true(all(vapply(env$.observed, function(x) isTRUE(x$deep_thinking), logical(1))))
  expect_identical(vapply(env$.observed, function(x) x$query_id, character(1)), c("q1", "q2"))
  expect_true(grepl("Analiz Kaynağı (Derin Analiz)", env$.stashed$footer, fixed = TRUE))
  expect_true(grepl("Sorgu Bir", env$.stashed$footer, fixed = TRUE))
  expect_true(grepl("Sorgu İki", env$.stashed$footer, fixed = TRUE))
  expect_identical(env$.stashed$request_id, "req-deep")
})

test_that("TTS köken alt bilgisi sınırını sentezden önce kaldırır", {
  txt <- .pk_p2_read_source("R/server_tts_handlers.R")

  marker_pos <- regexpr("provenance_marker <-", txt, fixed = TRUE, useBytes = TRUE)
  buffered_tts_pos <- regexpr("synthesize_speech(current_text", txt, fixed = TRUE, useBytes = TRUE)
  streaming_tts_pos <- regexpr("mergen_speech_pcm_stream_start(session, persona_id, full_text", txt,
                                fixed = TRUE, useBytes = TRUE)

  expect_gt(marker_pos, 0L)
  expect_gt(buffered_tts_pos, marker_pos)
  expect_gt(streaming_tts_pos, marker_pos)
  # SON eslesme kullanilir: yanit govdesi isaretcinin kendisini tasiyabilir
  # (model onceki bir yaniti alintilar), `regexpr()` ILK eslesmede kesip
  # gercek cevabi da atardi.
  expect_true(grepl("substr(full_text, 1L, max(eslesmeler) - 1L)", txt,
                    fixed = TRUE, useBytes = TRUE))
  # NOT: `gregexpr(...)` metni `regexpr(...)` alt dizgesini ICERIR; olumsuz
  # denetim bu yuzden ATAMA sekline sabitlenir (eski kod `<- regexpr(` idi).
  expect_false(grepl("<- regexpr(provenance_marker", txt, fixed = TRUE, useBytes = TRUE))

  # KAYNAK OFSETİ SIRALAMASI YÜKÜN KENDİSİNİ KANITLAMAZ. Yukarıdaki denetim
  # yalnızca `provenance_marker <-` metninin sentez çağrılarından ÖNCE geçtiğini
  # gösterir; kırpmanın AYNI `full_text` üzerinde, AYNI dalda ve sentez
  # öncesinde çalıştığını göstermez. Üretimin KENDİ kırpma bloğu sentetik bir
  # metin üzerinde çalıştırılır ve DÖNEN yük denetlenir.
  satirlar <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  bas <- grep("^\\s*provenance_marker <- ", satirlar, perl = TRUE)[1]
  expect_false(is.na(bas))
  # Blok, PARANTEZ DENGESİ sağlanana kadar okunur; sabit satır sayısı
  # kırpma bloğunun şekli değişince sessizce yanlış kod çalıştırırdı.
  son <- NA_integer_
  for (i in seq(bas, min(length(satirlar), bas + 30L))) {
    aday <- paste(satirlar[bas:i], collapse = "\n")
    if (!grepl("substr(full_text", aday, fixed = TRUE)) next
    if (!inherits(tryCatch(parse(text = aday), error = function(e) e), "error")) {
      son <- i
      break
    }
  }
  expect_false(is.na(son))
  blok <- paste(satirlar[bas:son], collapse = "\n")
  expect_true(grepl("substr(full_text", blok, fixed = TRUE))

  ortam <- new.env(parent = globalenv())  # `baseenv()` DEĞİL: çıkarılan üretim bloğu ileride `%||%` ya da base dışı bir yardımcı kullanırsa test, kapsadığını iddia ettiği gerilemeyi değil KOŞUM ORTAMINI raporlardı.
  ortam$full_text <- paste0(
    "Görünür cevap gövdesi.",
    "\n\n---\n**Analiz Kaynağı (Proje ve Kaynak Analizi)**\n",
    "Sorgu: Sentetik | Satır: 12\n"
  )
  eval(parse(text = blok), envir = ortam)

  expect_identical(ortam$full_text, "Görünür cevap gövdesi.")
  expect_false(grepl("Analiz Kaynağı", ortam$full_text, fixed = TRUE))

  # İşaretçi YOKKEN metin AYNEN korunur (kırpma yalnız işaretçide çalışır).
  ortam2 <- new.env(parent = globalenv())  # `baseenv()` DEĞİL: çıkarılan üretim bloğu ileride `%||%` ya da base dışı bir yardımcı kullanırsa test, kapsadığını iddia ettiği gerilemeyi değil KOŞUM ORTAMINI raporlardı.
  ortam2$full_text <- "Isaretci tasimayan duz cevap."
  eval(parse(text = blok), envir = ortam2)
  expect_identical(ortam2$full_text, "Isaretci tasimayan duz cevap.")

  # ISARETCI GOVDEDE DE GECIYORSA SON eslesmeden kirpilir; aksi halde
  # seslendirme, alintilanan isaretcinin ARDINDAKI gercek cevabi da atardi.
  ortam3 <- new.env(parent = globalenv())  # `baseenv()` DEĞİL: çıkarılan üretim bloğu ileride `%||%` ya da base dışı bir yardımcı kullanırsa test, kapsadığını iddia ettiği gerilemeyi değil KOŞUM ORTAMINI raporlardı.
  ortam3$full_text <- paste0(
    "Onceki yanit alintisi.",
    "\n\n---\n**Analiz Kaynağı (Proje ve Kaynak Analizi)**\nSorgu: Eski\n",
    "\n\nGercek yeni cevap govdesi.",
    "\n\n---\n**Analiz Kaynağı (Proje ve Kaynak Analizi)**\nSorgu: Yeni\n"
  )
  eval(parse(text = blok), envir = ortam3)
  expect_true(grepl("Gercek yeni cevap govdesi.", ortam3$full_text, fixed = TRUE))
  expect_false(endsWith(ortam3$full_text, "Sorgu: Yeni\n"))
})
test_that("KIMLIKSIZ kayit YAZILMAZ (sahiplik denetimi uygulanamaz)", {
  # GERİLEME: `request_id = NULL` saklanınca `pk_provenance_take()` sahiplik
  # denetimi HİÇ çalışmıyordu (denetim yalnızca `pending$request_id` doluyken
  # uygulanır). Kimliğini kaybeden bir üretim yolu, BAŞKA bir istek etkinken
  # bekleyen kaydı EZEBİLİYOR ve yanlış yanıt alt bilgiyi/olguları/eki
  # tüketebiliyordu.
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_provenance.R"),
         encoding = "UTF-8", local = env)
  oturum <- list(userData = new.env(parent = emptyenv()))

  # Aktif istek kimliği YOK: kayıt reddedilir.
  expect_false(isTRUE(env$pk_provenance_stash(oturum, "alt bilgi")))
  expect_null(env$pk_provenance_take(oturum))

  # Aktif kimlik VARSA kimliksiz çağrı da o kimliğe YAZILIR (üretim yolu).
  env$pk_provenance_clear(oturum, request_id = "r1")
  expect_true(isTRUE(env$pk_provenance_stash(oturum, "alt bilgi")))

  # Sahiplik denetimi ARTIK uygulanabilir: yanlış kimlik kaydı tüketemez.
  expect_null(env$pk_provenance_take(oturum, request_id = "r2"))
  expect_identical(env$pk_provenance_take(oturum, request_id = "r1"), "alt bilgi")
})

# ==============================================================================
# §5.11 — AYNI RENDER EDİLMİŞ YANIT: akış / akış-dışı / kalıcılık / TTS
# ==============================================================================
#
# Olgu yuvaları çözümlendikten sonra ortaya çıkan metin TEK bir gerçektir.
# Gerçek akış sonlandırması, benzetilmiş akış sonlandırması, kalıcılaştırılan
# mesaj ve TTS yükü AYNI gövdeyi kullanmak zorundadır; aksi hâlde kullanıcı
# ekranda bir şey görüp başka bir şey duyabilir ya da kayıtlı söyleşide ham
# iç jetonlar kalabilir.

.pk_delivery_render_env <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  for (dosya in c("helpers_pk_config.R", "helpers_pk_fact_reference.R",
                  "helpers_pk_fact_reference_scan.R", "helpers_pk_precision.R",
                  "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_provenance.R", "helpers_pk_provenance_peek.R",
                  "helpers_pk_numeric_provenance.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.pk_delivery_stash <- function(env, oturum, kip, olgu, alt_bilgi) {
  env$pk_provenance_clear(oturum, request_id = "req-render")
  env$pk_provenance_stash(
    oturum, alt_bilgi, request_id = "req-render", facts = list(olgu),
    fallback_text = "**Hesaplanan değerler**\n- Kalan iscilik (sum): 18.420,5 saat",
    query_id = "q_render", mode = kip
  )
}

test_that("akis, akis-disi, kalicilik ve TTS AYNI render edilmis govdeyi kullanir", {
  env <- .pk_delivery_render_env()
  olgu <- env$pk_fact_record("measure", "KalanIscilik", "sum", 18420.5,
                             list(label = "Kalan iscilik", unit = "saat", decimals = 1L,
                                  capability = "labor.remaining_hours"))
  alt_bilgi <- "\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** q_render\n"
  model_metni <- paste0("Kalan is yuku ", env$pk_fact_reference_token(olgu$fact_id),
                        " duzeyindedir.")
  beklenen_govde <- "Kalan is yuku 18.420,5 saat duzeyindedir."

  # 1) GERÇEK AKIŞ sonlandırması.
  oturum <- list(userData = new.env(parent = emptyenv()))
  .pk_delivery_stash(env, oturum, "log", olgu, alt_bilgi)
  akis <- NULL
  utils::capture.output(
    akis <- env$mergen_pk_stream_validated_text(model_metni, oturum, "req-render",
                                                block_mode = FALSE),
    type = "output"
  )

  # 2) AKIŞ DIŞI / doğrudan yanıt yolu.
  oturum2 <- list(userData = new.env(parent = emptyenv()))
  .pk_delivery_stash(env, oturum2, "log", olgu, alt_bilgi)
  dogrudan <- NULL
  utils::capture.output(
    dogrudan <- env$mergen_pk_validated_texts(model_metni, oturum2,
                                              request_id = "req-render"),
    type = "output"
  )

  # 3) BENZETİLMİŞ akış sonlandırması (kalıcılaştırılan metin bu yoldan gelir).
  oturum3 <- list(userData = new.env(parent = emptyenv()))
  .pk_delivery_stash(env, oturum3, "log", olgu, alt_bilgi)
  benzetim <- NULL
  utils::capture.output(
    benzetim <- env$pk_stream_display_text(model_metni, oturum3, "req-render",
                                           block_mode = FALSE),
    type = "output"
  )

  # EKRANA giden metin ÜÇ yolda da aynıdır ve alt bilgiyi taşır.
  expect_identical(akis$display, dogrudan$display)
  expect_identical(akis$display, benzetim)
  expect_identical(akis$display, paste0(beklenen_govde, alt_bilgi))

  # TTS gövdesi alt bilgisiz AYNI gövdedir.
  expect_identical(akis$tts, beklenen_govde)
  expect_identical(dogrudan$tts, beklenen_govde)

  # İÇ SÖZ DİZİMİ HİÇBİR YOLDA SIZMAZ.
  for (metin in c(akis$display, akis$tts, dogrudan$display, dogrudan$tts, benzetim)) {
    expect_false(grepl("{{", metin, fixed = TRUE))
    expect_false(grepl("fact:", metin, fixed = TRUE))
  }
  expect_true(akis$validated)
})

test_that("log kipinde bozuk referans yaniti BASTIRMAZ ve tum yollar ayni kalir", {
  env <- .pk_delivery_render_env()
  olgu <- env$pk_fact_record("measure", "KalanIscilik", "sum", 18420.5,
                             list(label = "Kalan iscilik", unit = "saat", decimals = 1L,
                                  capability = "labor.remaining_hours"))
  alt_bilgi <- "\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** q_render\n"
  model_metni <- paste0(
    "Genel gorunum baskiya isaret ediyor. Kalan is yuku ",
    env$pk_fact_reference_token(olgu$fact_id),
    " duzeyindedir. Sonuc {{fact:uydurma.sum.overall.ffffff}} olarak olculdu."
  )

  oturum <- list(userData = new.env(parent = emptyenv()))
  .pk_delivery_stash(env, oturum, "log", olgu, alt_bilgi)
  akis <- NULL
  utils::capture.output(
    akis <- env$mergen_pk_stream_validated_text(model_metni, oturum, "req-render",
                                                block_mode = FALSE),
    type = "output"
  )

  # Kullanıcı yanıtı ALIR; "Yanıt doğrulanamadı" ile DEĞİŞTİRİLMEZ.
  expect_true(grepl("Genel gorunum baskiya isaret ediyor", akis$display, fixed = TRUE))
  expect_true(grepl("18.420,5 saat", akis$display, fixed = TRUE))
  expect_false(grepl("Yanıt doğrulanamadı", akis$display))
  expect_false(grepl("Hesaplanan değerler", akis$display, fixed = TRUE))
  # Çözülemeyen iddia HİÇBİR değer basmaz.
  expect_false(grepl("uydurma", akis$display, fixed = TRUE))
  expect_true(grepl("değer yok", akis$display))
})

test_that("block kipinde ekran ve TTS AYNI ayiklanmis govdeyi alir", {
  env <- .pk_delivery_render_env()
  olgu <- env$pk_fact_record("measure", "KalanIscilik", "sum", 18420.5,
                             list(label = "Kalan iscilik", unit = "saat", decimals = 1L,
                                  capability = "labor.remaining_hours"))
  alt_bilgi <- "\n\n---\n**Analiz Kaynağı**\n- **Sorgu:** q_render\n"
  model_metni <- paste0(
    "Kalan is yuku ", env$pk_fact_reference_token(olgu$fact_id), " duzeyindedir. ",
    "Ayrica 99.999 saat harcandi."
  )

  oturum <- list(userData = new.env(parent = emptyenv()))
  .pk_delivery_stash(env, oturum, "block", olgu, alt_bilgi)
  expect_true(env$pk_provenance_blocks_streaming(oturum, request_id = "req-render"))

  metinler <- NULL
  utils::capture.output(
    metinler <- env$mergen_pk_block_mode_texts(model_metni, oturum,
                                               request_id = "req-render"),
    type = "output"
  )

  # Sorunlu cümle AYIKLANIR, geçerli cümle KORUNUR.
  expect_true(grepl("18.420,5 saat", metinler$display, fixed = TRUE))
  expect_false(grepl("99.999", metinler$display, fixed = TRUE))
  # TTS, ekranda kalan alt bilgiyi TAŞIMAZ ama AYNI gövdedir.
  expect_identical(metinler$display, paste0(metinler$tts, alt_bilgi))
  expect_false(grepl("{{", metinler$tts, fixed = TRUE))
})
