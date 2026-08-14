# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-security-summary-contract.R
# Açıklama: Proje/Kaynak Analizi RLS/özet helper extraction ve SSO readiness
#           sözleşmelerini doğrular. Canlı DB veya Shiny app başlatmaz.
# ==============================================================================

.pk_read_repo_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.pk_extract_safe_source_paths <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

.pk_count_file_functions <- function(text) {
  # Maintainability contract for extracted helper files should count public /
  # top-level assigned helper functions, not local anonymous callbacks inside
  # lapply/vapply or nested implementation details.
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]

  hits <- grepl(
    "^[[:alnum:]_\\.]+\\s*<-\\s*function\\s*\\(",
    lines,
    perl = TRUE,
    useBytes = TRUE
  )

  sum(hits)
}

.pk_load_security_summary_helper <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  helper_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0L) {
      return(y)
    }
    if (length(x) == 1L && is.na(x)) {
      return(y)
    }
    x
  }

  source(
    file.path(repo_root, "R", "helpers_pk_analysis_core.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  # Faz 1: apply_rls_to_data karari artik saf pk_rls_plan() katmanindan gelir.
  source(
    file.path(repo_root, "R", "helpers_pk_rls.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_pk_analysis_security_summary.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  # Faz 1: generate_statistical_summary ayri dosyaya tasindi (400 satir butcesi).
  source(
    file.path(repo_root, "R", "helpers_pk_statistical_summary.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("Proje/Kaynak Analizi security-summary helper manifest içinde doğru sırada yüklenir", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_pk_analysis_core.R",
      "R/helpers_pk_analysis_security_summary.R",
      "R/helpers_pk_analysis_filters.R"
    ),
    label = "PK analysis core/security/filters source sırası bozulmuş:"
  )

  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_pk_analysis_security_summary.R",
      "R/module_proje_kaynak_analizi.R"
    ),
    label = "PK security-summary/module source sırası bozulmuş:"
  )
})

test_that("Proje/Kaynak Analizi helper extraction maintainability kazanımı korunur", {
  module_text <- .pk_read_repo_text("R/module_proje_kaynak_analizi.R")
  helper_text <- .pk_read_repo_text("R/helpers_pk_analysis_security_summary.R")

  module_lines <- length(strsplit(module_text, "\n", fixed = TRUE)[[1]])
  helper_lines <- length(strsplit(helper_text, "\n", fixed = TRUE)[[1]])
  helper_functions <- .pk_count_file_functions(helper_text)

  expect_true(
    module_lines <= 799L,
    info = sprintf(
      "R/module_proje_kaynak_analizi.R RLS/özet extraction sonrası 800 satır altı kalmalıdır: %d > 799.",
      module_lines
    )
  )

  expect_true(
    helper_lines <= 400L,
    info = sprintf(
      "R/helpers_pk_analysis_security_summary.R küçük helper dosyası olarak kalmalıdır: %d > 400.",
      helper_lines
    )
  )

  # PR #703: 5 -> 6. Eklenen tek fonksiyon `pk_rls_halt_message()`; TİPLİ
  # RLS durdurma/son tarih sonucunun "kullanıcı kaydı bulunamadı" YETKİ
  # hatasından ayrılmasını sağlar ve iki çağıran (tekil + derin yol) tarafından
  # paylaşılır.
  #
  # PR #705 stabilizasyonu: 6 -> 7. Eklenen tek fonksiyon
  # `.pk_rls_scope_codes()`; izin tablosundaki `NA`/boş kodların
  # `paste(collapse = ",")` yüzünden SIRADAN `"NA"` metnine dönüşüp GERÇEK bir
  # kapsam kodu gibi davranmasını engeller ve PY/EPS dallarının İKİSİ
  # tarafından paylaşılır. Dosya hâlâ küçük bir yardımcıdır.
  expect_true(
    helper_functions <= 7L,
    info = sprintf(
      "R/helpers_pk_analysis_security_summary.R fonksiyon sayısı kontrollü kalmalıdır: %d > 7.",
      helper_functions
    )
  )
})

test_that("resolve_pk_analysis_username SSO hazır değilken Unknown ile RLS'e düşmez", {
  helper_env <- .pk_load_security_summary_helper()

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$sso_active <- TRUE
  session$userData$auth_initialized <- FALSE

  result <- helper_env$resolve_pk_analysis_username(session)

  expect_false(result$ready)
  expect_equal(result$username, "Unknown")
  expect_equal(result$reason, "auth_not_ready")

  session$userData$auth_initialized <- TRUE
  session$userData$system_username <- "deneme.kullanici"

  result_ready <- helper_env$resolve_pk_analysis_username(session)

  expect_true(result_ready$ready)
  expect_equal(result_ready$username, "deneme.kullanici")
  expect_null(result_ready$reason)
})

test_that("apply_rls_to_data rol ve kolon sözleşmesini korur", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    MasrafYeri = c("A", "B", "A"),
    ProjeKodu = c("P1", "P2", "P3"),
    EPSKodu = c("E1", "E1", "E2"),
    Deger = c(10, 20, 30),
    stringsAsFactors = FALSE
  )

  rls_cols <- list(
    masraf_yeri_col = "MasrafYeri",
    proje_kodu_col = "ProjeKodu",
    eps_kodu_col = "EPSKodu"
  )

  admin_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(Yetki = "ADMIN"),
    rls_cols = rls_cols
  )

  expect_equal(nrow(admin_data), 3L)

  py_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(
      Yetki = "PY",
      allowed_depts = "A",
      allowed_projects = "P3"
    ),
    rls_cols = rls_cols
  )

  expect_equal(nrow(py_data), 1L)
  expect_equal(py_data$ProjeKodu, "P3")

  eps_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(
      Yetki = "KY-P",
      allowed_depts = NULL,
      allowed_eps = "E1"
    ),
    rls_cols = rls_cols
  )

  expect_equal(nrow(eps_data), 2L)
  expect_true(all(eps_data$EPSKodu == "E1"))
})

# Faz 1 / D6 / D6b: Davranis BILEREK degisti. Eskiden beyan edilen RLS sutunu
# sonucta yoksa predikat SESSIZCE atlaniyor ve kullanici TUM satirlari
# goruyordu; kapsam cozulemedigi (izin sorgusu hatasi) veya bos oldugu (izin
# tablosunda satir yok) durumlarda da ayni sey oluyordu. Kapsam SILINMEDI,
# yeni dogru davranisi iddia edecek sekilde genisletildi.
test_that("apply_rls_to_data eksik RLS sutununda kapali basarisiz olur (D6)", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    ProjeKodu = c("P1", "P2"),
    Deger = c(1, 2),
    stringsAsFactors = FALSE
  )

  # Beyan edilen sutun sonuc kumesinde YOK.
  expect_error(
    helper_env$apply_rls_to_data(
      sample_data,
      user_info = list(
        Yetki = "PY",
        allowed_projects = "P1",
        scope_state_projects = "available"
      ),
      rls_cols = list(proje_kodu_col = "OlmayanSutun")
    ),
    class = "pk_rls_error"
  )
})

test_that("apply_rls_to_data cozulemeyen kapsamda durur, bos kapsamda sifir satir dondurur (D6b)", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    ProjeKodu = c("P1", "P2"),
    Deger = c(1, 2),
    stringsAsFactors = FALSE
  )
  rls_cols <- list(proje_kodu_col = "ProjeKodu")

  # Izin sorgusu hata verdi -> kapsam COZULEMEDI -> DURDUR.
  expect_error(
    helper_env$apply_rls_to_data(
      sample_data,
      user_info = list(
        Yetki = "PY",
        allowed_projects = NULL,
        scope_state_projects = "unavailable"
      ),
      rls_cols = rls_cols
    ),
    class = "pk_rls_error"
  )

  # Kullanici izin tablosunda YOK -> kapsam BOS -> SIFIR satir (tum satirlar degil).
  bos_kapsam <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(
      Yetki = "PY",
      allowed_projects = NULL,
      scope_state_projects = "empty"
    ),
    rls_cols = rls_cols
  )
  expect_equal(nrow(bos_kapsam), 0L)

  # Durum alani hic tasinmayan eski cagri yolu da GUVENLI tarafa duser.
  expect_error(
    helper_env$apply_rls_to_data(
      sample_data,
      user_info = list(Yetki = "PY", allowed_projects = NULL),
      rls_cols = rls_cols
    ),
    class = "pk_rls_error"
  )
})

test_that("apply_rls_to_data NA Yetki degerinde hata vermek yerine kapali basarisiz olur", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(ProjeKodu = "P1", stringsAsFactors = FALSE)

  expect_error(
    helper_env$apply_rls_to_data(
      sample_data,
      user_info = list(Yetki = NA_character_),
      rls_cols = list(proje_kodu_col = "ProjeKodu")
    ),
    class = "pk_rls_error"
  )
})

test_that("generate_statistical_summary filtre ve pre-aggregated uyarılarını korur", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    Proje = c("Alfa", "Beta", "Alfa"),
    Saat = c(10, 20, 30),
    ToplamSaat = c(100, 100, 100),
    Tarih = as.Date(c("2024-01-01", "2024-01-02", "2024-01-03")),
    stringsAsFactors = FALSE
  )

  result <- helper_env$generate_statistical_summary(
    sample_data,
    rls_total_rows = 5,
    user_filter_applied = TRUE,
    pre_aggregated_columns = "ToplamSaat"
  )

  expect_equal(result$row_count, 3L)
  expect_equal(nrow(result$preview_data), 3L)
  expect_true(grepl("FİLTRELEME UYARISI", result$summary_text, fixed = TRUE))
  expect_true(grepl("ÖNCEDEN TOPLULAŞTIRILMIŞ SÜTUN UYARISI", result$summary_text, fixed = TRUE))
  expect_true(grepl("SAYISAL SUTUNLAR OZETI", result$summary_text, fixed = TRUE))
})
test_that("RLS veritabani hatasi KULLANICI BULUNAMADI olarak raporlanmaz", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_analysis_security_summary.R"),
         encoding = "UTF-8", local = env)

  # KUSUR: SON TARIH/IPTAL disindaki HER hata (baglanti kopmasi, ODBC/surucu
  # hatasi, SQL hatasi) bos bir cerceveye indirgeniyor, bir sonraki dal da
  # bunu "Kullanici DC01 tablosunda bulunamadi" diye raporluyordu. Yani gecici
  # bir DC01 kesintisi HER kullaniciya YANLIS bir yetki teshisiyle erisimi
  # kapatiyordu.
  env$.pk_rls_bounded_query <- function(...) stop("ODBC: baglanti kesildi")
  sonuc <- env$get_user_rls_info("sentetik_kullanici", NULL)

  expect_false(isTRUE(sonuc$authorized))          # KAPALI BASARISIZ korunur
  expect_true(isTRUE(sonuc$db_error))             # ama TESHIS dogrudur
  expect_false(isTRUE(sonuc$halted))
  expect_false(grepl("bulunamadı", sonuc$reason, fixed = TRUE))
  # Ham surucu/SQL metni kullaniciya SIZDIRILMAZ.
  expect_false(grepl("ODBC", sonuc$reason, fixed = TRUE))

  # GERCEKTEN bos sonuc hala "kullanici bulunamadi" demektir.
  env$.pk_rls_bounded_query <- function(...) data.frame()
  bos <- env$get_user_rls_info("sentetik_kullanici", NULL)
  expect_false(isTRUE(bos$authorized))
  expect_false(isTRUE(bos$db_error))
  expect_true(grepl("bulunamadı", bos$reason, fixed = TRUE))

  # SON TARIH/IPTAL hala TIPLI kalir (db_error DEGILDIR).
  env$.pk_rls_bounded_query <- function(...) stop("islem durduruldu")
  durdu <- env$get_user_rls_info("sentetik_kullanici", NULL)
  expect_true(isTRUE(durdu$halted))
  expect_false(isTRUE(durdu$db_error))
})
