# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-execute-query-behavior.R
# Açıklama: helpers_deep_analysis.R içindeki execute_single_deep_query davranışını
#           doğrular (Derin Düşünme modu tekil sorgu motoru). Erken-dönüş ve
#           güvenlik dalları kapsanır: durdurma talebi, DB bağlantısı yok, boş
#           SQL, tehlikeli SQL (DROP/DELETE/TRUNCATE/ALTER) reddi, boş sonuç ve
#           başarılı orkestrasyon. get_connection/release_connection env'e,
#           SQL yürütme sınırı (Faz 6: pk_deep_execute_sql) env'e stub edilir;
#           gerçek DB yok. Sınırlı getirimin KENDİSİ ayrı dosyada test edilir
#           (test-pk-sql-execute-bounded-behavior.R).
#           Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_deep_analysis.R'yi yalıtılmış ortama yükler ve erken-dönüş
# dalları için en az bağımlılığı (get_connection/release_connection) env'e koyar.
.deepQueryEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # Faz 1: derin mod artik ANA YOL ile ayni salt-okunur SQL kapisini ve kapali
  # basarisiz RLS/gercek-sutun kapisini kullanir; yalitilmis ortam da yuklemeli.
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  # Faz 6 (D16): SQL kaynagi/yurutmesi ve iptal/son tarih aritmetigi kendi sahip
  # dosyalarina tasindi; izole ortam GERCEK sahipleri yukler.
  for (yardimci in c("helpers_pk_sql_readonly.R", "helpers_pk_query_meta_schema.R",
                     "helpers_pk_query_meta_access.R", "helpers_pk_rls.R",
                     "helpers_pk_config.R", "helpers_pk_async_cancel.R",
                     "helpers_pk_exec_context.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R",
                     "helpers_deep_analysis_reconcile.R",
                     "helpers_deep_analysis_phase6.R",
                     "helpers_deep_analysis_selector.R")) {
    source(file.path(kok, "R", yardimci), encoding = "UTF-8", local = env)
  }
  source(file.path(kok, "R", "helpers_deep_analysis.R"), encoding = "UTF-8", local = env)
  # Varsayılan: geçerli bir bağlantı listesi döndüren stub
  env$.release_calls <- 0L
  env$get_connection <- function(target = "primary") list(conn = "FAKE_CONN", target = target)
  env$release_connection <- function(conn_list) {
    env$.release_calls <- env$.release_calls + 1L
    invisible(TRUE)
  }
  # Başarı yolu yardımcıları (erken dönüşlerde çağrılmaz; başarı testinde stub)
  # Faz 6: burada ORKESTRASYON test edilir, bu yuzden YURUTME SINIRI stub'lanir.
  env$.sql_exec_calls <- 0L
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    env$.sql_exec_calls <- env$.sql_exec_calls + 1L
    list(status = "ok", data = data.frame(), rows = 0L, error = NA_character_)
  }
  env$convert_date_columns <- function(df, cols) df
  env$apply_rls_to_data <- function(df, rls_info, cols) df
  env$generate_statistical_summary <- function(df, ...) {
    list(row_count = nrow(df), summary_text = "ÖZET", preview_data = utils::head(df, 5))
  }
  env
}

.detailCfg <- list(preview_rows = 10)

test_that("execute_single_deep_query durdurma talebinde NULL döner (bağlantı kurmadan)", {
  env <- .deepQueryEnv()
  baglandi <- FALSE
  env$get_connection <- function(target = "primary") { baglandi <<- TRUE; list(conn = "X") }

  res <- env$execute_single_deep_query(
    query = list(name = "Q1", sql = "SELECT 1"),
    user_prompt = "soru",
    session = NULL,
    rls_info = list(),
    detail_config = .detailCfg,
    stop_check = function() TRUE
  )
  expect_null(res)
  # Türkçe yorum: durdurma en başta olduğu için DB bağlantısı hiç kurulmamalı
  expect_false(baglandi)
})

test_that("execute_single_deep_query DB bağlantısı kurulamazsa hata döndürür", {
  env <- .deepQueryEnv()
  env$get_connection <- function(target = "primary") NULL

  res <- env$execute_single_deep_query(
    query = list(name = "Bağlantısız", sql = "SELECT 1"),
    user_prompt = "soru", session = NULL, rls_info = list(),
    detail_config = .detailCfg
  )
  expect_false(res$success)
  expect_identical(res$query_name, "Bağlantısız")
  expect_true(grepl("bağlantısı kurulamadı", res$error_msg))
})

test_that("execute_single_deep_query boş SQL için hata döndürür", {
  env <- .deepQueryEnv()
  res <- env$execute_single_deep_query(
    query = list(name = "BoşSQL"),  # ne sql ne sql_file
    user_prompt = "soru", session = NULL, rls_info = list(),
    detail_config = .detailCfg
  )
  expect_false(res$success)
  expect_true(grepl("SQL kodu bulunamadı", res$error_msg))
  # Türkçe yorum: bağlantı açıldıysa serbest bırakılmalı (on.exit)
  expect_gte(env$.release_calls, 1L)
})

test_that("execute_single_deep_query tehlikeli SQL'i (DROP/DELETE/TRUNCATE/ALTER) reddeder", {
  for (kotu in c(
    "DROP TABLE musteriler",
    "DELETE FROM siparisler WHERE 1=1",
    "TRUNCATE TABLE log",
    "ALTER TABLE x ADD c INT",
    "select * from t; drop table t"   # küçük harf + noktalı virgül
  )) {
    env <- .deepQueryEnv()
    # Türkçe yorum: SQL yürütmeye ASLA ulaşılmamalı (güvenlik dalı önce reddetmeli)
    db_called <- FALSE
    env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
      db_called <<- TRUE
      list(status = "ok", data = data.frame(), rows = 0L, error = NA_character_)
    }
    res <- env$execute_single_deep_query(
      query = list(name = "Tehlike", sql = kotu),
      user_prompt = "soru", session = NULL, rls_info = list(),
      detail_config = .detailCfg
    )
    expect_false(res$success)
    # Faz 1 / D23: mesaj BILEREK daha ozgul hale geldi; kapi artik bir kara
    # liste degil, ifade farkinda salt-okunur siniflandiricisidir.
    expect_identical(res$error_msg, "Güvenlik ihlali: sorgu salt-okunur olarak doğrulanamadı.")
    expect_false(db_called)
  }
})

test_that("execute_single_deep_query boş sorgu sonucunda hata döndürür", {
  env <- .deepQueryEnv()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = data.frame(), rows = 0L, error = NA_character_)  # 0 satır
  }
  res <- env$execute_single_deep_query(
    query = list(name = "BoşSonuç", sql = "SELECT * FROM t WHERE 1=0"),
    user_prompt = "soru", session = NULL, rls_info = list(),
    detail_config = .detailCfg
  )
  expect_false(res$success)
  expect_true(grepl("Sorgu sonucu boş", res$error_msg))
})

test_that("execute_single_deep_query RLS sonrası boş veride yetki hatası döndürür", {
  env <- .deepQueryEnv()
  # Türkçe yorum: RLS uygulaması tüm satırları kaldırınca yetki hatası beklenir
  env$apply_rls_to_data <- function(df, rls_info, cols) df[0, , drop = FALSE]
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = data.frame(a = 1:3), rows = 3L, error = NA_character_)
  }
  res <- env$execute_single_deep_query(
    query = list(name = "YetkiYok", sql = "SELECT * FROM t"),
    user_prompt = "soru", session = NULL, rls_info = list(rol = "kisitli"),
    detail_config = .detailCfg
  )
  expect_false(res$success)
  expect_true(grepl("Yetki dahilinde veri bulunamadı", res$error_msg))
})

test_that("execute_single_deep_query başarılı orkestrasyonda özet + önizleme döndürür", {
  env <- .deepQueryEnv()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(
      status = "ok",
      data = data.frame(ad = c("a", "b", "c"), tutar = c(10, 20, 30)),
      rows = 3L, error = NA_character_
    )
  }
  res <- env$execute_single_deep_query(
    query = list(
      name = "Satış Analizi",
      sql = "SELECT ad, tutar FROM satislar",
      description = "Aylık satış",
      relevance_score = 88,
      disable_ai_filters = TRUE   # AI filtre çağrısını atla (deterministik)
    ),
    user_prompt = "satışları göster", session = NULL, rls_info = list(),
    detail_config = .detailCfg
  )
  expect_true(res$success)
  expect_identical(res$query_name, "Satış Analizi")
  expect_identical(res$query_desc, "Aylık satış")
  expect_equal(res$row_count, 3L)
  expect_identical(res$summary_text, "ÖZET")
  expect_equal(res$relevance, 88)
  # Türkçe yorum: önizleme JSON geçerli olmalı ve veri satırı içermeli
  expect_true(grepl("ad", res$preview_json, fixed = TRUE))
  parsed <- jsonlite::fromJSON(res$preview_json)
  expect_equal(nrow(parsed), 3L)
})
