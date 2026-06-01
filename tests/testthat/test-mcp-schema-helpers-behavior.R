# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-schema-helpers-behavior.R
# Açıklama: R/helpers_mcp_schema_helpers.R içindeki saf şema/eşleştirme/normalize
#           yardımcılarının DAVRANIŞSAL testleri. Bu dosyanın hiç davranış testi
#           yoktu. Gerçek üretim fonksiyonları çağrılır:
#             - normalize_chart_type (TR/EN alias eşlemesi, box->hist)
#             - normalize_args (file_name/column/sql eş adları)
#             - find_matching_column (tam/kısmi/Türkçe-normalize/ortak desen)
#             - find_columns_by_context (çoklu terim eşleştirme)
#             - prettify_column_name (alt çizgi/camelCase/ön ek çevirisi)
#             - prettify_result_colnames (sütun adı güzelleştirme)
#           extract_mcp_file_schema dosya okuma (readxl/data.table) gerektirdiği
#           için KAPSAM DIŞIDIR.
#           Shiny/DB/ağ GEREKMEZ. helpers_mcp_tools yalnızca %||% gerektirir;
#           global bağ test sırasında izole edilip sonunda geri yüklenir.
# ==============================================================================

# Temiz bir helpers_mcp_tools ortamı kurar, şema yardımcılarını yükler ve test
# bitince önceki global bağı geri yükler. Dönen değer stub ortamıdır.
.mcpschema_install <- function() {
  root <- resolve_repo_root_for_tests()

  had <- exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) else NULL

  env <- new.env(parent = globalenv())
  assign("helpers_mcp_tools", env, envir = globalenv())

  source(
    file.path(root, "R", "helpers_mcp_schema_helpers.R"),
    encoding = "UTF-8", local = globalenv()
  )

  withr::defer(
    {
      if (had) {
        assign("helpers_mcp_tools", old, envir = globalenv())
      } else if (exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
        rm("helpers_mcp_tools", envir = globalenv())
      }
    },
    envir = parent.frame()
  )

  get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
}

# ------------------------------------------------------------------------------
# normalize_chart_type
# ------------------------------------------------------------------------------
testthat::test_that("normalize_chart_type TR/EN alias'larını kanonik tipe eşler", {
  h <- .mcpschema_install()
  eslesmeler <- list(
    line = c("line", "trend", "zaman serisi", "Çizgi Grafiği", "time series"),
    scatter = c("scatter", "saçılım", "scatter plot"),
    area = c("area", "alan", "alan grafiği"),
    pareto = c("pareto", "pareto grafiği"),
    bar = c("bar", "column", "çubuk", "Sütun Grafiği"),
    pie = c("pie", "pasta"),
    donut = c("donut", "doughnut", "halka"),
    hist = c("histogram", "dağılım", "box", "boxplot")
  )
  for (kanonik in names(eslesmeler)) {
    for (girdi in eslesmeler[[kanonik]]) {
      testthat::expect_identical(
        h$normalize_chart_type(girdi), kanonik,
        info = paste(girdi, "->", kanonik)
      )
    }
  }
})

testthat::test_that("normalize_chart_type boşlukları kırpar, küçük harfe çevirir ve bilinmeyeni korur", {
  h <- .mcpschema_install()
  testthat::expect_identical(h$normalize_chart_type("  LINE  "), "line")
  # Bilinmeyen tip küçük harfe inip aynen döner
  testthat::expect_identical(h$normalize_chart_type("Bilinmeyen"), "bilinmeyen")
  # NULL -> "" (varsayılan)
  testthat::expect_identical(h$normalize_chart_type(NULL), "")
  testthat::expect_identical(h$normalize_chart_type(""), "")
})

# ------------------------------------------------------------------------------
# normalize_args
# ------------------------------------------------------------------------------
testthat::test_that("normalize_args eş adları file_name/column/sql alanlarına çözer", {
  h <- .mcpschema_install()
  out <- h$normalize_args(list(filename = "x.xlsx", col = "Ad", query = "SELECT 1"))
  testthat::expect_identical(out$file_name, "x.xlsx")
  testthat::expect_identical(out$column, "Ad")
  testthat::expect_identical(out$sql, "SELECT 1")

  # Türkçe eş adlar: dosya/kolon/sorgu
  out_tr <- h$normalize_args(list(dosya = "d.csv", kolon = "K", sorgu = "Q"))
  testthat::expect_identical(out_tr$file_name, "d.csv")
  testthat::expect_identical(out_tr$column, "K")
  testthat::expect_identical(out_tr$sql, "Q")
})

testthat::test_that("normalize_args açık alanları korur ve liste-olmayan girdiyi boş listeye çevirir", {
  h <- .mcpschema_install()
  out <- h$normalize_args(list(file_name = "explicit", column = "C", sql = "S"))
  testthat::expect_identical(out$file_name, "explicit")
  testthat::expect_identical(out$column, "C")
  testthat::expect_identical(out$sql, "S")

  # Liste değilse boş listeye düşer; eş ad kaynağı olmadığı için file_name NULL
  out_nonlist <- h$normalize_args("liste degil")
  testthat::expect_null(out_nonlist$file_name)
  testthat::expect_null(out_nonlist$column)
  testthat::expect_null(out_nonlist$sql)
})

# ------------------------------------------------------------------------------
# find_matching_column
# ------------------------------------------------------------------------------
testthat::test_that("find_matching_column tam/kısmi eşleşmeyi çözer ve NULL/boş kenarlarını korur", {
  h <- .mcpschema_install()
  cols <- c("Department", "Salary", "EmployeeName", "HireDate", "PerfScore")

  # Tam eşleşme (büyük/küçük harf duyarsız)
  testthat::expect_identical(h$find_matching_column("salary", cols), "Salary")
  # Kısmi eşleşme (sütun arama terimini içerir)
  testthat::expect_identical(h$find_matching_column("name", cols), "EmployeeName")

  # Kenar durumlar
  testthat::expect_null(h$find_matching_column(NULL, cols))
  testthat::expect_null(h$find_matching_column("", cols))
  testthat::expect_null(h$find_matching_column("x", character(0)))
  testthat::expect_null(h$find_matching_column("zzzqqq", cols))
})

testthat::test_that("find_matching_column Türkçe normalize ve ortak TR-EN desenleriyle eşleştirir", {
  h <- .mcpschema_install()
  cols <- c("Department", "Salary", "EmployeeName", "HireDate", "PerfScore")

  # Türkçe terimler ortak desenlerle hedef sütuna eşlenir
  testthat::expect_identical(h$find_matching_column("maas", cols), "Salary")
  testthat::expect_identical(h$find_matching_column("bölüm", cols), "Department")
  testthat::expect_identical(h$find_matching_column("performans", cols), "PerfScore")

  # Alt çizgi/Türkçe normalize ile eşleşme
  cols_tr <- c("calisan_adi", "departman", "maas_tl")
  testthat::expect_identical(h$find_matching_column("calisanadi", cols_tr), "calisan_adi")
})

# ------------------------------------------------------------------------------
# find_columns_by_context
# ------------------------------------------------------------------------------
testthat::test_that("find_columns_by_context her terim için eşleşen sütunu döndürür", {
  h <- .mcpschema_install()
  df <- data.frame(
    Department = 1, Salary = 2, EmployeeName = "a",
    stringsAsFactors = FALSE
  )
  out <- h$find_columns_by_context(df, c("maas", "isim"))
  testthat::expect_identical(out[["maas"]], "Salary")
  testthat::expect_identical(out[["isim"]], "EmployeeName")
})

testthat::test_that("find_columns_by_context data.frame-olmayan/boş terimde boş liste döner", {
  h <- .mcpschema_install()
  df <- data.frame(A = 1, stringsAsFactors = FALSE)
  testthat::expect_identical(h$find_columns_by_context(NULL, c("x")), list())
  testthat::expect_identical(h$find_columns_by_context(df, character(0)), list())
})

# ------------------------------------------------------------------------------
# prettify_column_name
# ------------------------------------------------------------------------------
testthat::test_that("prettify_column_name toplama ön eklerini Türkçeye çevirir", {
  h <- .mcpschema_install()
  testthat::expect_identical(h$prettify_column_name("avg_salary"), "Ortalama salary")
  testthat::expect_identical(h$prettify_column_name("sum_total"), "Toplam total")
  testthat::expect_identical(h$prettify_column_name("count_id"), "Adet id")
  testthat::expect_identical(h$prettify_column_name("max_value"), "Maksimum value")
  testthat::expect_identical(h$prettify_column_name("min_score"), "Minimum score")
})

testthat::test_that("prettify_column_name alt çizgiyi boşluğa, camelCase'i ayrık kelimeye çevirir", {
  h <- .mcpschema_install()
  testthat::expect_identical(h$prettify_column_name("employee_name"), "employee name")
  testthat::expect_identical(h$prettify_column_name("HireDate"), "Hire Date")
  testthat::expect_identical(h$prettify_column_name("plain"), "plain")
})

testthat::test_that("prettify_column_name NULL/boş için boş dize döner", {
  h <- .mcpschema_install()
  testthat::expect_identical(h$prettify_column_name(NULL), "")
  testthat::expect_identical(h$prettify_column_name(character(0)), "")
  testthat::expect_identical(h$prettify_column_name(""), "")
})

testthat::test_that("prettify_column_name sarmalayıcı temizliği asimetriktir (mevcut sınırlama)", {
  h <- .mcpschema_install()
  # Karakterizasyon: regex sınıfı POSIX modunda baştaki tırnak/parantezi siler,
  # ancak sondaki backtick/köşeli parantez (yalnızca '...]' deseninde silindiği
  # için) korunur. Bu mevcut davranıştır, düzeltme değildir.
  testthat::expect_identical(h$prettify_column_name("`Quoted`"), "Quoted`")
  testthat::expect_identical(h$prettify_column_name("[Bracket]"), "Bracket]")
})

# ------------------------------------------------------------------------------
# prettify_result_colnames
# ------------------------------------------------------------------------------
testthat::test_that("prettify_result_colnames tüm sütun adlarını güzelleştirir, df-olmayanı korur", {
  h <- .mcpschema_install()
  df <- data.frame(x = 1, y = 2)
  names(df) <- c("avg_x", "count_y")
  out <- h$prettify_result_colnames(df)
  testthat::expect_identical(names(out), c("Ortalama x", "Adet y"))
  # İçerik değişmez
  testthat::expect_identical(out[[1]], 1)
  testthat::expect_identical(out[[2]], 2)

  # data.frame değilse aynen döner
  liste <- list(a = 1, b = "x")
  testthat::expect_identical(h$prettify_result_colnames(liste), liste)
})
