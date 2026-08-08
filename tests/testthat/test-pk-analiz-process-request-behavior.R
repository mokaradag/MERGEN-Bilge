# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analiz-process-request-behavior.R
# Açıklama: module_proje_kaynak_analizi.R içindeki pk_analiz_process_request ve
#           find_best_query_with_ai davranışını doğrular.
#
#           pk_analiz_process_request: Proje/Kaynak Analizi akışının orkestratörü.
#           Deterministik erken-dönüş + güvenlik dalları doğrulanır:
#             - başlangıç durdurma talebi,
#             - SSO kimliği hazır değil (DB'ye gitmeden döner — kimlik sınırı),
#             - RLS yetki reddi,
#             - RLS sonrası durdurma,
#             - sorgu eşleşmesi bulunamadı,
#             - sorgu seçimi sonrası durdurma,
#             - SQL yapılandırma hataları (boş SQL / eksik dosya / yol algılama /
#               geçersiz SQL),
#             - YASAKLI SQL komutu reddi (DELETE/DROP/TRUNCATE/ALTER) — Faz 5
#               güvenlik kapsaması.
#
#           find_best_query_with_ai: LLM JSON match_id'sini kütüphane sorgusuna
#           eşler; aralık dışı/null/geçersiz JSON -> NULL.
#
#           Modül kaynak-zamanı helper-guard döngüsü içerir; gerekli yardımcılar
#           env'e önceden stub'lanır ki guard dosya kaynaklamayı atlasın. Gerçek
#           DB/LLM/ağ yoktur; çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: module_proje_kaynak_analizi.R'yi yalıtılmış ortama yükler. Modülün
# kaynak-zamanı guard döngüsü (pk_required_helpers) exists(...,inherits=TRUE) ile
# yardımcıları arar; env'e önceden boş stub koyarak dosya kaynaklamayı önleriz.
.pkAnalizEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()

  # Türkçe yorum: guard'ın aradığı 15 yardımcı adı için yer-tutucu stub'lar
  guard_fns <- c(
    "summarize_columns_for_ai", "normalize_sql_server_identifiers",
    "resolve_pk_analysis_username", "get_user_rls_info", "apply_rls_to_data",
    "generate_statistical_summary", "extract_filter_criteria_from_prompt",
    "apply_smart_filters", "pk_init_query_score_table", "pk_score_query_relevance",
    "pk_compute_heuristic_query_scores", "print_score_table",
    # Faz 5 seçim zinciri de guard listesindedir; stub'lanmazsa modül tüm
    # zinciri kaynaklamayı dener ve izole ortamda göreli yol çözülemez.
    "pk_select_query_v2", "pk_select_run", "pk_select_decide"
  )
  for (fn in guard_fns) assign(fn, function(...) NULL, envir = env)

  # Faz 1: modul artik salt-okunur SQL kapisini, ODBC redaksiyonunu, kapali
  # basarisiz RLS/gercek-sutun kapisini ve saf istem/yuk kuruculari tuketir.
  for (yardimci in c("helpers_pk_config.R", "helpers_pk_safe_errors.R",
                     "helpers_pk_sql_readonly.R", "helpers_pk_query_meta_schema.R",
                     "helpers_pk_query_meta_access.R", "helpers_pk_rls.R",
                     "helpers_pk_prompt_budget.R", "helpers_pk_analysis_prompts.R")) {
    source(file.path(kok, "R", yardimci), encoding = "UTF-8", local = env)
  }

  # v1 AI seçicisi (`find_best_query_with_ai`) bakım borcu ratchet'i için
  # modülden ÇIKARILDI; davranışı BİREBİR aynıdır ve bu dosya onu da test eder.
  source(file.path(kok, "R", "helpers_pk_analysis_ai_selector.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_proje_kaynak_analizi.R"), encoding = "UTF-8", local = env)

  env$cat <- function(...) invisible(NULL)
  env$query_library <- list()
  env$DB_TARGETS <- list(PRIMARY = "primary")
  env$get_connection <- function(target = "primary") list(conn = "sahte-baglanti")
  env$release_connection <- function(x) invisible(NULL)
  env$execute_pk_sql_unicode <- function(conn, sql) data.frame(x = 1L)
  env$normalize_pk_dataframe_utf8 <- function(df) df
  # Türkçe yorum: varsayılan hazır kimlik + yetkili RLS; testler gerektikçe ezer
  env$resolve_pk_analysis_username <- function(session) list(ready = TRUE, username = "kullanici1")
  env$get_user_rls_info <- function(username, conn) list(authorized = TRUE, rls_filter = "")
  env$select_smart_query <- function(prompt, library, chat_history, ...) NULL
  env
}

.pkSession <- function() list(userData = list(system_username = "kullanici1"))

# ---------------------------------------------------------------------------
# pk_analiz_process_request
# ---------------------------------------------------------------------------

test_that("pk_analiz_process_request başlangıç durdurma talebinde iptal mesajı döner", {
  env <- .pkAnalizEnv()
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() TRUE)
  expect_true(grepl("İşlem Durduruldu", res, fixed = TRUE))
})

test_that("pk_analiz_process_request SSO kimliği hazır değilse DB'ye gitmeden uyarı döner", {
  env <- .pkAnalizEnv()
  cagrildi <- new.env(parent = emptyenv()); cagrildi$db <- FALSE
  env$get_connection <- function(target = "primary") { cagrildi$db <- TRUE; list(conn = "x") }
  env$resolve_pk_analysis_username <- function(session) list(ready = FALSE, reason = "sso_pending")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("Kimlik Doğrulama Hazırlanıyor", res, fixed = TRUE))
  # Türkçe yorum: kimlik hazır değilken DB bağlantısı AÇILMAMALI
  expect_false(cagrildi$db)
})

test_that("pk_analiz_process_request yetkisiz kullanıcıya yetki hatası döner", {
  env <- .pkAnalizEnv()
  env$get_user_rls_info <- function(username, conn) list(authorized = FALSE)
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("Yetki Hatası", res, fixed = TRUE))
  expect_true(grepl("DC01_user_base", res, fixed = TRUE))
})

test_that("pk_analiz_process_request RLS sonrası durdurma talebinde iptal eder", {
  env <- .pkAnalizEnv()
  sayac <- new.env(parent = emptyenv()); sayac$n <- 0L
  stop_check <- function() { sayac$n <- sayac$n + 1L; sayac$n >= 2L }
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = stop_check)
  expect_true(grepl("İşlem Durduruldu", res, fixed = TRUE))
})

test_that("pk_analiz_process_request uygun sorgu yoksa bilgilendirici mesaj döner", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) NULL
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("analiz kütüphanesinde bulunamadı", res, fixed = TRUE))
})

test_that("pk_analiz_process_request sorgu seçiminden sonra durdurma talebinde iptal eder", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "SELECT 1 FROM t")
  sayac <- new.env(parent = emptyenv()); sayac$n <- 0L
  # Türkçe yorum: 1=giriş, 2=RLS sonrası, 3=sorgu seçimi sonrası -> 3'te durdur
  stop_check <- function() { sayac$n <- sayac$n + 1L; sayac$n >= 3L }
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = stop_check)
  expect_true(grepl("İşlem Durduruldu", res, fixed = TRUE))
})

test_that("pk_analiz_process_request boş SQL için yapılandırma hatası döner", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("Yapılandırma Hatası", res, fixed = TRUE))
  expect_true(grepl("SQL kodu bulunamadı", res, fixed = TRUE))
})

test_that("pk_analiz_process_request boş SQL + sql_file için startup yükleme hatası döner", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "", sql_file = "q.sql")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("Yapılandırma Hatası", res, fixed = TRUE))
  expect_true(grepl("startup sırasında yüklenmemiş", res, fixed = TRUE))
})

test_that("pk_analiz_process_request SQL içinde dosya yolu algılarsa sistem hatası döner", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "C:\\sorgular\\q.sql")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("dosya yolu algılandı", res, fixed = TRUE))
})

test_that("pk_analiz_process_request geçersiz/kısa SQL için sistem hatası döner", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "merhaba")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)
  expect_true(grepl("Geçersiz SQL sorgusu", res, fixed = TRUE))
})

test_that("pk_analiz_process_request yasakli SQL komutunu reddeder (D23 salt-okunur kapisi)", {
  env <- .pkAnalizEnv()
  # Türkçe yorum: geçerli görünen ama DELETE içeren çok ifadeli SQL reddedilir.
  cagrildi <- new.env(parent = emptyenv()); cagrildi$exec <- FALSE
  env$execute_pk_sql_unicode <- function(conn, sql) { cagrildi$exec <- TRUE; data.frame(x = 1L) }
  env$select_smart_query <- function(...) list(id = 1L, name = "S",
                                               sql = "SELECT * FROM tablo; DELETE FROM tablo")
  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)

  # Faz 1 / D23 + D22: Davranis BILEREK degisti. Eskiden kara liste bir stop()
  # firlatiyor, bu da tryCatch tarafindan "Veritabani Hatasi: ... Guvenlik
  # ihlali ..." seklinde HAM mesajla kullaniciya donuyordu. Artik kapi
  # baglantidan ONCE reddeder ve genel guvenlik mesaji doner; ham SQL/hata
  # metni sohbete SIZMAZ.
  expect_true(grepl("Güvenlik Kontrolü", res, fixed = TRUE))
  expect_false(grepl("DELETE", res, fixed = TRUE))
  expect_false(grepl("Veritabanı Hatası", res, fixed = TRUE))
  # Türkçe yorum: yasaklı komut yüzünden gerçek SQL ÇALIŞTIRILMAMALI
  expect_false(cagrildi$exec)
})

test_that("pk_analiz_process_request ham ODBC hatasini sohbete gommez (D22)", {
  env <- .pkAnalizEnv()
  env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "SELECT * FROM tablo")
  env$execute_pk_sql_unicode <- function(conn, sql) {
    stop("nanodbc/nanodbc.cpp:1655: 42S02: [Microsoft][ODBC Driver]Invalid object name 'GizliTablo'.")
  }

  res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)

  expect_true(grepl("Veritabanı Hatası", res, fixed = TRUE))
  for (sizinti in c("nanodbc", "42S02", "ODBC", "GizliTablo")) {
    expect_false(grepl(sizinti, res, fixed = TRUE), info = sizinti)
  }
})

test_that("altyapi tanilamasi GIBI GORUNMEYEN SQL hatasi da kullanici mesajina donusur", {
  # Redaksiyon bilerek gecirgendir: kendi urettigimiz Turkce mesajlar oldugu
  # gibi doner (bkz. test-pk-safe-error-redaction-contract.R). Modul ise SQL
  # yurutmesinden donen degerin veri mi hata mi oldugunu ORTAK ISARETTEN anlar.
  # Isaret dusunce hata metni sonuc kumesi sanilyor ve akis apply_rls_to_data
  # icinde ham bir R hatasiyla ("argument is of length zero") cokuyordu.
  # execute_pk_sql_unicode()'un kendi ilk kontrolu tam olarak boyle bir mesaj
  # firlatir; bu yol sentetik degil, gercek bir uretim yoludur.
  for (ham in c("Bos SQL metni gonderilemez.",
                "could not find function \"normalize_db_params\"")) {
    env <- .pkAnalizEnv()
    env$select_smart_query <- function(...) list(id = 1L, name = "S", sql = "SELECT * FROM tablo")
    env$execute_pk_sql_unicode <- function(conn, sql) stop(ham, call. = FALSE)
    env$apply_rls_to_data <- function(data, user_info, rls_cols) {
      # Hata metni buraya ULASMAMALIDIR; ulasirsa nrow(NULL) uzerinden coker.
      stop("apply_rls_to_data hata metniyle cagrildi", call. = FALSE)
    }

    res <- env$pk_analiz_process_request("soru", list(), .pkSession(), stop_check = function() FALSE)

    expect_true(is.character(res), info = ham)
    expect_length(res, 1L)
    # Kullaniciya donen metin ortak isareti TASIR.
    expect_true(startsWith(res, "\U000026A0\U0000FE0F"), info = ham)
    expect_true(grepl("Veritabanı Hatası", res, fixed = TRUE), info = ham)
  }
})

# ---------------------------------------------------------------------------
# find_best_query_with_ai
# ---------------------------------------------------------------------------

test_that("find_best_query_with_ai geçerli match_id'yi kütüphane sorgusuna eşler", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) {
    list(content = '{"match_id": 2, "confidence": 88, "reason": "ilgili"}')
  }
  lib <- list(
    list(name = "Sorgu A", description = "ilk"),
    list(name = "Sorgu B", description = "ikinci")
  )
  res <- env$find_best_query_with_ai("soru", lib, .pkSession())
  expect_false(is.null(res))
  expect_identical(res$name, "Sorgu B")
  expect_identical(res$relevance_score, 88)
  expect_identical(res$selection_method, "ai")
  expect_identical(res$.matched_idx, 2L)
})

test_that("find_best_query_with_ai null match_id için NULL döner", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) list(content = '{"match_id": null, "confidence": 0}')
  lib <- list(list(name = "Sorgu A", description = "ilk"))
  expect_null(env$find_best_query_with_ai("soru", lib, .pkSession()))
})

test_that("find_best_query_with_ai aralık dışı match_id için NULL döner", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) list(content = '{"match_id": 99, "confidence": 90}')
  lib <- list(list(name = "Sorgu A", description = "ilk"))
  expect_null(env$find_best_query_with_ai("soru", lib, .pkSession()))
})

test_that("find_best_query_with_ai ```json çitini temizler ve eşler", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) {
    "```json\n{\"match_id\": 1, \"confidence\": 70, \"reason\": \"x\"}\n```"
  }
  lib <- list(list(name = "Sorgu A", description = "ilk"))
  res <- env$find_best_query_with_ai("soru", lib, .pkSession())
  expect_false(is.null(res))
  expect_identical(res$.matched_idx, 1L)
})

test_that("find_best_query_with_ai geçersiz JSON için NULL döner (hata yakalanır)", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) list(content = "bu json değil")
  lib <- list(list(name = "Sorgu A", description = "ilk"))
  expect_null(env$find_best_query_with_ai("soru", lib, .pkSession()))
})

test_that("find_best_query_with_ai LLM NULL dönerse NULL döner", {
  env <- .pkAnalizEnv()
  withr::local_options(mergen.filter_model = "m1")
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "k")
  env$call_local_llm <- function(messages, opts) NULL
  lib <- list(list(name = "Sorgu A", description = "ilk"))
  expect_null(env$find_best_query_with_ai("soru", lib, .pkSession()))
})
