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
.deepQueryEnv <- function(v2_packets = FALSE) {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # Faz 1: derin mod artik ANA YOL ile ayni salt-okunur SQL kapisini ve kapali
  # basarisiz RLS/gercek-sutun kapisini kullanir; yalitilmis ortam da yuklemeli.
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Faz 6 (D16): SQL kaynagi/yurutmesi ve iptal/son tarih aritmetigi kendi sahip
  # dosyalarina tasindi; izole ortam GERCEK sahipleri yukler.
  for (yardimci in c("helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R",
                     "helpers_pk_sql_local_temp_batch.R", "helpers_pk_query_meta_schema.R",
                     "helpers_pk_query_meta_access.R", "helpers_pk_rls.R",
                     "helpers_pk_config.R", "helpers_pk_async_cancel.R",
                     "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R", "helpers_pk_sql_connection.R",
                     "helpers_deep_analysis_sql.R", "helpers_deep_analysis_reconcile.R",
                     "helpers_pk_query_selection_deep.R",
                     "helpers_deep_analysis_phase6.R",
                     "helpers_deep_analysis_selector.R")) {
    source(file.path(kok, "R", yardimci), encoding = "UTF-8", local = env)
  }
  source(file.path(kok, "R", "helpers_deep_analysis.R"), encoding = "UTF-8", local = env)

  # VM/app oturumunda global v2 motoru açık olsa bile legacy orkestrasyon testleri
  # v1 yolundan sapmamalı. v2 testleri sorgudaki `pk_engine_v2=TRUE` ile açıktır.
  env$pk_engine_is_v2 <- function(...) FALSE

  # v2 regresyonları gerçek paket/fact sahiplerini yükler. Legacy özet
  # implementation'ı yeniden taklit edilmez; üretim ile aynı helper'lar çağrılır.
  if (isTRUE(v2_packets)) {
    for (yardimci in c("helpers_pk_text_turkish.R", "helpers_pk_prompt_budget.R",
                       "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R", "helpers_pk_packet_keys.R", "helpers_pk_analysis_packet.R",
                       "helpers_pk_packet_render.R", "helpers_pk_answer_compose.R",
                       "helpers_pk_numeric_provenance.R",
                       "helpers_pk_numeric_provenance_claims.R")) {
      source(file.path(kok, "R", yardimci), encoding = "UTF-8", local = env)
    }
  }

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
  # Tam test paketinde daha önce yüklenmiş global bounded executor bu testin
  # özet stub'ını başka yürütme bağlamına taşımamalı; burada çağrı senkron ve yereldir.
  env$pk_async_bounded_fs <- function(fn, deadline_at = NULL) {
    list(ok = TRUE, value = fn())
  }
  env$convert_date_columns <- function(df, cols) df
  env$apply_rls_to_data <- function(df, rls_info, cols) df
  env$generate_statistical_summary <- function(df, ...) {
    list(row_count = nrow(df), summary_text = "ÖZET", preview_data = utils::head(df, 5))
  }
  env
}

.detailCfg <- list(preview_rows = 10)

.deepV2Query <- function() {
  list(
    id = "q_deep_v2_sentetik",
    name = "v2 Sentetik Analiz",
    description = "Ağırlıklı ilerleme ve en güncel maliyet",
    sql = "SELECT * FROM sentetik",
    relevance_score = 93,
    disable_ai_filters = TRUE,
    pk_engine_v2 = TRUE,
    date_columns = "Snapshot",
    meta = list(
      grain = "row",
      grain_columns = "RowId",
      default_measures = c("Progress", "Cost"),
      default_group_by = character(0),
      column_meta = list(
        Project = list(role = "dimension", label = "Proje"),
        Progress = list(
          role = "measure", label = "İlerleme", unit = "%", decimals = 1L,
          additive = FALSE, aggregate = "weighted_mean", weight_by = "Weight",
          percent_scale = "fraction", capability = "progress.weighted"
        ),
        Weight = list(
          role = "measure", label = "Ağırlık", decimals = 0L,
          additive = TRUE, aggregate = "sum", capability = "progress.weight"
        ),
        Snapshot = list(role = "date", label = "Dönem"),
        RowId = list(role = "id", label = "Kayıt"),
        Cost = list(
          role = "measure", label = "Maliyet", unit = "TL", decimals = 0L,
          additive = FALSE, aggregate = "latest", latest_by = "Snapshot",
          latest_tie_by = "RowId", capability = "cost.latest"
        )
      )
    )
  )
}

.deepV2Data <- function() {
  data.frame(
    Project = c("A", "B", "C"),
    Progress = c(0.2, 0.8, 0.5),
    Weight = c(1, 3, 2),
    Snapshot = as.Date(c("2026-01-01", "2026-03-01", "2026-02-01")),
    RowId = c("r1", "r2", "r3"),
    Cost = c(100, 250, 150),
    stringsAsFactors = FALSE
  )
}

test_that("execute_single_deep_query durdurma talebinde TİPLİ HALT döner (bağlantı kurmadan)", {
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
  # PR #703: erken Durdur artık `NULL` DEĞİL TİPLİ halt döndürür. `NULL`, halt
  # SON seçilen sorguda gerçekleştiğinde dış döngüde durumu KAYBEDİYOR ve kısmi
  # sonuç "tam analiz" gibi sunuluyordu.
  expect_true(env$pk_deep_is_halt_result(res))
  expect_identical(res$pk_halt_status, "cancelled")
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

test_that("v2 Deep Thinking legacy özet yerine gerçek kanonik packet/fact hattını kullanır", {
  env <- .deepQueryEnv(v2_packets = TRUE)
  veri <- .deepV2Data()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = veri, rows = nrow(veri), error = NA_character_)
  }
  # Seçim köprüsündeki gerçek durumu taklit et: global motor görünümü FALSE,
  # fakat seçilmiş sorgu istek-yerel `pk_engine_v2=TRUE` işaretini taşır.
  env$pk_engine_is_v2 <- function(...) FALSE
  env$generate_statistical_summary <- function(...) {
    stop("v2 Deep Thinking legacy generate_statistical_summary çağırmamalı")
  }

  res <- env$execute_single_deep_query(
    query = .deepV2Query(), user_prompt = "ilerleme ve son maliyet",
    session = NULL, rls_info = list(), detail_config = .detailCfg
  )

  expect_true(res$success)
  expect_identical(res$pk_engine_mode, "v2")
  expect_true(is.list(res$pk_packet))
  expect_true(length(res$pk_facts) > 0L)
  expect_true(grepl("[fact:", res$pk_packet_text, fixed = TRUE))
  expect_null(res$summary_text)
  expect_identical(res$query_id, "q_deep_v2_sentetik")
  expect_identical(res$query_meta, .deepV2Query()$meta)
  expect_identical(res$data, veri)
})

test_that("v2 Deep Thinking weighted/non-additive, latest ve yüzde ölçeğini kanonik korur", {
  env <- .deepQueryEnv(v2_packets = TRUE)
  veri <- .deepV2Data()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = veri, rows = nrow(veri), error = NA_character_)
  }
  env$generate_statistical_summary <- function(...) stop("legacy özet çağrıldı")

  res <- env$execute_single_deep_query(
    query = .deepV2Query(), user_prompt = "özetle",
    session = NULL, rls_info = list(), detail_config = .detailCfg
  )
  expect_true(res$success)

  fact <- function(column, aggregation) {
    x <- Filter(function(f) is.list(f) && identical(f$column, column) &&
                  identical(f$aggregation, aggregation), res$pk_facts)
    if (length(x)) x[[1]] else NULL
  }

  weighted <- fact("Progress", "weighted_mean")
  expect_true(is.list(weighted))
  expect_identical(weighted$status, "ok")
  expect_equal(weighted$value, 60)
  expect_identical(weighted$unit, "%")
  expect_true(grepl("60", weighted$display, fixed = TRUE))
  expect_true(grepl("%", weighted$display, fixed = TRUE))

  # Non-additive Progress için düz toplam/ortalama yetkili sayısal olgu olamaz.
  progress_sum <- fact("Progress", "sum")
  progress_mean <- fact("Progress", "mean")
  expect_true(is.null(progress_sum) || is.null(progress_sum$value))
  expect_true(is.null(progress_mean) || is.null(progress_mean$value))

  latest <- fact("Cost", "latest")
  expect_true(is.list(latest))
  expect_identical(latest$status, "ok")
  expect_equal(latest$value, 250)
  expect_identical(latest$unit, "TL")
})

test_that("v2 Deep Thinking fact registry halüsinasyon sayıyı provenance block modunda engeller", {
  env <- .deepQueryEnv(v2_packets = TRUE)
  veri <- .deepV2Data()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = veri, rows = nrow(veri), error = NA_character_)
  }
  env$generate_statistical_summary <- function(...) stop("legacy özet çağrıldı")

  res <- env$execute_single_deep_query(
    query = .deepV2Query(), user_prompt = "özetle",
    session = NULL, rls_info = list(), detail_config = .detailCfg
  )
  expect_true(res$success)

  weighted <- Filter(function(f) is.list(f) && identical(f$column, "Progress") &&
                       identical(f$aggregation, "weighted_mean"), res$pk_facts)[[1]]
  model_text <- sprintf("İlerleme %%99,0 [fact:%s].", weighted$fact_id)
  checked <- env$pk_numeric_provenance_apply(
    model_text, res$pk_facts, mode = "block", fallback_text = res$pk_fallback_text
  )

  expect_true(checked$blocked)
  expect_true(any(vapply(checked$mismatches,
                         function(x) identical(x$reason, "value_mismatch"), logical(1))))
  expect_false(grepl("99,0", checked$text, fixed = TRUE))
  expect_true(grepl("R tarafından hesaplanmıştır", checked$text, fixed = TRUE))
})

test_that("v2 Deep Thinking paket kurulumu deadline olursa typed halt döner", {
  # SINIFLANDIRMA sınanır, EŞLEME değil.
  #
  # `pk_async_bounded_fs()` sınırlı fonksiyonun içindeki HER hatada
  # `ok = FALSE` döndürür. Yalnızca `list(ok = FALSE, value = NULL)` döndüren
  # bir vekil kullanılırsa, üretim kodu ALAKASIZ bir paket kurulum çökmesini
  # `deadline` diye raporlasa bile bu iddia GEÇERDİ. Bu yüzden vekil bütçe
  # sentinelini TAŞIR ve ayrıca bütçe DIŞI bir hatanın son tarih SAYILMADIĞI
  # ikinci bir durum eklenir.
  env <- .deepQueryEnv(v2_packets = TRUE)
  veri <- .deepV2Data()
  env$pk_deep_execute_sql <- function(conn, sql_text, ...) {
    list(status = "ok", data = veri, rows = nrow(veri), error = NA_character_)
  }
  env$generate_statistical_summary <- function(...) stop("legacy özet çağrıldı")

  env$pk_async_bounded_fs <- function(fn, deadline_at = NULL) {
    list(ok = FALSE, value = NULL, error = "budget_exhausted")
  }
  res <- env$execute_single_deep_query(
    query = .deepV2Query(), user_prompt = "özetle",
    session = NULL, rls_info = list(), detail_config = .detailCfg
  )
  expect_true(env$pk_deep_is_halt_result(res))
  expect_identical(res$pk_halt_status, "deadline")

  # BÜTÇE DIŞI hata: son tarih halt'i DEĞİL, gerçek hata sonucu döner.
  env$pk_async_bounded_fs <- function(fn, deadline_at = NULL) {
    list(ok = FALSE, value = NULL, error = "paket kurulumunda beklenmeyen hata")
  }
  hatali <- env$execute_single_deep_query(
    query = .deepV2Query(), user_prompt = "özetle",
    session = NULL, rls_info = list(), detail_config = .detailCfg
  )
  expect_false(isTRUE(env$pk_deep_is_halt_result(hatali)))
  expect_false(isTRUE(hatali$success))
  # TİP VE İÇERİK AÇIKÇA DENETLENİR: `as.character(NULL)[1]` `NA_character_`
  # üretir ve `nzchar()` varsayılan `keepNA = FALSE` ile `NA` için `TRUE`
  # döner; yani `error_msg` alanı HİÇ olmayan bir başarısız sonuç da bu
  # iddiayı geçiyor, test kullanıcının mesaj aldığını YANLIŞ raporluyordu.
  expect_true(is.character(hatali$error_msg) && length(hatali$error_msg) == 1L &&
                !is.na(hatali$error_msg) && nzchar(hatali$error_msg))
})

test_that("sınırlı çalıştırma sınıflandırıcısı bütçeyi GERÇEK hatadan ayırır", {
  env <- .deepQueryEnv(v2_packets = TRUE)

  expect_null(env$pk_deep_bounded_deadline_reason(list(ok = TRUE, value = 1)))
  expect_identical(
    env$pk_deep_bounded_deadline_reason(list(ok = FALSE, error = "budget_exhausted")),
    "deadline"
  )
  expect_identical(
    env$pk_deep_bounded_deadline_reason(
      list(ok = FALSE, error = "reached elapsed time limit")
    ),
    "deadline"
  )
  expect_null(env$pk_deep_bounded_deadline_reason(list(ok = FALSE, error = "baska hata")))

  # Hata alanı YOKSA son tarihin GERÇEKTEN dolup dolmadığına bakılır.
  expect_identical(
    env$pk_deep_bounded_deadline_reason(list(ok = FALSE),
                                        deadline_at = Sys.time() - 5),
    "deadline"
  )
  expect_null(env$pk_deep_bounded_deadline_reason(list(ok = FALSE),
                                                  deadline_at = Sys.time() + 600))
})