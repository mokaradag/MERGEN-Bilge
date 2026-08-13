# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-process-behavior.R
# Açıklama: helpers_deep_analysis.R içindeki pk_deep_analysis_process orkestrasyon
#           davranışını doğrular. Bu fonksiyon Derin Analiz akışını yönetir:
#           durdurma kontrolü -> DB/RLS yetki kontrolü -> çoklu sorgu seçimi (AI)
#           -> başarısız olursa tekil sorgu fallback'i -> her sorguyu çalıştırma
#           -> sonuçları bağlama birleştirme.
#
#           Tüm servis-bağlı yardımcılar (get_connection/get_user_rls_info/
#           find_multiple_queries_with_ai/select_smart_query/execute_single_deep_query/
#           build_deep_analysis_context) env içine stub'lanır; gerçek DB/LLM/ağ
#           yoktur. Çevrimdışı ve deterministik. Yönlendirme, fallback, boş-sonuç,
#           yetki-reddi, durdurma ve kullanıcıya dönen mesajlar doğrulanır.
# ==============================================================================

# Türkçe yorum: helpers_deep_analysis.R'yi yalıtılmış ortama yükler ve servis-bağlı
# bağımlılıkları kontrol edilebilir stub'larla değiştirir.
.deepProcessEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

  # Faz 6: orkestratör artık iptal/son tarih aritmetiğini, yapılandırma
  # çözümleyicisini ve derin uzlaştırma katmanını (D16) kullanır. CLAUDE.md
  # kuralı gereği izole test GERÇEK sahip dosyaları yükler; stub'lanmaz.
  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R", "helpers_pk_sql_connection.R",
                  "helpers_deep_analysis_sql.R", "helpers_deep_analysis_reconcile.R",
                     "helpers_deep_analysis_phase6.R",
                     "helpers_deep_analysis_selector.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  source(file.path(kok, "R", "helpers_deep_analysis.R"), encoding = "UTF-8", local = env)

  # D16 kimlik kapısı: ana yolun çözümleyicisi stub'lanır (SSO/DB yok).
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "kullanici1", reason = "ok")
  }

  env$cat <- function(...) invisible(NULL)
  env$query_library <- list()
  env$get_analysis_detail_config <- function(level) list(instruction = "talimat", id = level)
  env$get_connection <- function() list(conn = "sahte-baglanti")
  env$release_connection <- function(x) invisible(NULL)
  # Türkçe yorum: varsayılan yetkili kullanıcı; testler gerektikçe ezer
  env$get_user_rls_info <- function(username, conn) list(authorized = TRUE, rls_filter = "")
  env$find_multiple_queries_with_ai <- function(user_prompt, library, session, max_queries = 5, ...) {
    list(list(id = 1L, name = "Sorgu A"))
  }
  env$select_smart_query <- function(prompt, library, chat_history, ...) NULL
  env$execute_single_deep_query <- function(query, user_prompt, session, rls_info, detail_config, stop_check = NULL, chat_history = NULL) {
    list(query_name = query$name, success = TRUE, row_count = 3L)
  }
  env$build_deep_analysis_context <- function(query_results, user_prompt, detail_config) {
    "BIRLESIK-BAGLAM"
  }
  env
}

.deepSession <- function() list(userData = list(system_username = "kullanici1"))

test_that("pk_deep_analysis_process başlangıçta durdurma talebinde iptal mesajı döner", {
  env <- .deepProcessEnv()
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() TRUE
  )
  expect_true(grepl("İşlem Durduruldu", res, fixed = TRUE))
  expect_true(grepl("iptal", res))
})

test_that("pk_deep_analysis_process yetkisiz kullanıcıya yetki hatası döner", {
  env <- .deepProcessEnv()
  env$get_user_rls_info <- function(username, conn) list(authorized = FALSE)
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_true(grepl("Yetki Hatası", res, fixed = TRUE))
  expect_true(grepl("kullanıcı kaydınız bulunamadı", res, fixed = TRUE))
})

test_that("pk_deep_analysis_process RLS sonrası durdurma talebinde iptal mesajı döner", {
  env <- .deepProcessEnv()
  # Türkçe yorum: ilk çağrı FALSE (giriş), ikinci çağrı TRUE (RLS sonrası)
  sayac <- new.env(parent = emptyenv()); sayac$n <- 0L
  stop_check <- function() { sayac$n <- sayac$n + 1L; sayac$n >= 2L }
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = stop_check
  )
  expect_true(grepl("İşlem Durduruldu", res, fixed = TRUE))
})

test_that("pk_deep_analysis_process çoklu sorgu seçip bağlamı oluşturur", {
  env <- .deepProcessEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$find_multiple_queries_with_ai <- function(user_prompt, library, session, max_queries = 5, ...) {
    list(list(id = 1L, name = "Sorgu A"), list(id = 2L, name = "Sorgu B"))
  }
  env$build_deep_analysis_context <- function(query_results, user_prompt, detail_config) {
    yakalanan$results <- query_results
    "BAGLAM-COKLU"
  }
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_identical(res, "BAGLAM-COKLU")
  # Türkçe yorum: iki sorgu çalıştırılmış ve bağlama geçirilmiş olmalı
  expect_length(yakalanan$results, 2L)
  expect_true(all(vapply(yakalanan$results, function(r) isTRUE(r$success), logical(1))))
})

test_that("pk_deep_analysis_process çoklu seçim başarısızsa tekil sorgu fallback'i kullanır", {
  env <- .deepProcessEnv()
  env$find_multiple_queries_with_ai <- function(...) NULL
  env$select_smart_query <- function(prompt, library, chat_history, ...) list(id = 9L, name = "Tekil Sorgu")
  yakalanan <- new.env(parent = emptyenv())
  env$execute_single_deep_query <- function(query, ...) {
    yakalanan$query_name <- query$name
    list(query_name = query$name, success = TRUE)
  }
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_identical(res, "BIRLESIK-BAGLAM")
  expect_identical(yakalanan$query_name, "Tekil Sorgu")
})

test_that("pk_deep_analysis_process hiç sorgu bulunamazsa kullanıcıya bilgilendirici mesaj döner", {
  env <- .deepProcessEnv()
  env$find_multiple_queries_with_ai <- function(...) NULL
  env$select_smart_query <- function(...) NULL
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_true(grepl("analiz kütüphanesinde bulunamadı", res, fixed = TRUE))
})

test_that("pk_deep_analysis_process hiçbir sorgu çalıştırılamazsa hata mesajı döner", {
  env <- .deepProcessEnv()
  # Türkçe yorum: execute NULL döndürür -> query_results boş kalır
  env$execute_single_deep_query <- function(...) NULL
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_true(grepl("Hiçbir sorgu çalıştırılamadı", res, fixed = TRUE))
})

test_that("pk_deep_analysis_process sorgu hatasını yakalar ve başarısız sonuç olarak bağlama taşır", {
  env <- .deepProcessEnv()
  yakalanan <- new.env(parent = emptyenv())
  env$execute_single_deep_query <- function(...) stop("sorgu çöktü")
  env$build_deep_analysis_context <- function(query_results, user_prompt, detail_config) {
    yakalanan$results <- query_results
    "BAGLAM-HATALI"
  }
  res <- env$pk_deep_analysis_process(
    "soru", list(), .deepSession(),
    detail_level = "standart", stop_check = function() FALSE
  )
  expect_identical(res, "BAGLAM-HATALI")
  # Türkçe yorum: hata yakalanıp success=FALSE sonuç olarak eklenmiş olmalı
  expect_length(yakalanan$results, 1L)
  expect_false(isTRUE(yakalanan$results[[1]]$success))
  expect_true(grepl("sorgu çöktü", yakalanan$results[[1]]$error_msg, fixed = TRUE))
})
