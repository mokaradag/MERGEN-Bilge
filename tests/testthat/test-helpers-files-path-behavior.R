# ================================================================================
# Dosya Yolu: tests/testthat/test-helpers-files-path-behavior.R
# Açıklama: R/helpers_files_path.R yol/UNC/karşılaştırma yardımcılarının
#           DAVRANIŞSAL testleri. Mevcut test-helpers-files-path-contract.R
#           yalnızca kaynak-düzenini ve tek bir temel yolu doğrular; burada
#           KAPSANMAYAN kenar/sınır davranışları test edilir:
#             - resolve_readable_path (NULL/boş/var olmayan)
#             - path_exists_relaxed (fs olmadan, slash varyantı)
#             - normalize_for_path_compare (//?/UNC, //?/, çoklu slash, küçük harf)
#             - is_under_mcp_base (taban yok, doğrudan altında, user_<id> kovası,
#               kardeş önek, eşitlik, ortam fallback) -> davranışsal olarak HİÇ
#               test edilmiyordu.
#           fs paketine bağımlı OLMADAN, yalnızca gerçek geçici dosyalar ve base R.
# ================================================================================

.helperspath_source_once <- function() {
  if (exists("is_under_mcp_base", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("normalize_for_path_compare", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_files_path.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# resolve_readable_path
# ------------------------------------------------------------------------------
testthat::test_that("resolve_readable_path NULL/boş girdiyi olduğu gibi döndürür", {
  .helperspath_source_once()
  testthat::expect_null(resolve_readable_path(NULL))
  testthat::expect_identical(resolve_readable_path(""), "")
})

testthat::test_that("resolve_readable_path var olan dosyayı aynen, var olmayanı girdiyle döndürür", {
  .helperspath_source_once()
  tf <- tempfile(fileext = ".txt")
  writeLines("x", tf)
  on.exit(unlink(tf), add = TRUE)

  testthat::expect_identical(resolve_readable_path(tf), tf)
  testthat::expect_identical(resolve_readable_path("/no/such/path"), "/no/such/path")
})

# ------------------------------------------------------------------------------
# path_exists_relaxed (fs olmadan)
# ------------------------------------------------------------------------------
testthat::test_that("path_exists_relaxed NULL/boş için FALSE, var olan dosya ve slash varyantı için TRUE döner", {
  .helperspath_source_once()
  testthat::expect_false(path_exists_relaxed(NULL))
  testthat::expect_false(path_exists_relaxed(""))
  testthat::expect_false(path_exists_relaxed("/no/such/path"))

  tf <- tempfile(fileext = ".txt")
  writeLines("Türkçe: çğıöşü", tf, useBytes = TRUE)
  on.exit(unlink(tf), add = TRUE)

  testthat::expect_true(path_exists_relaxed(tf))
  testthat::expect_true(path_exists_relaxed(gsub("\\\\", "/", tf, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# normalize_for_path_compare
# ------------------------------------------------------------------------------
testthat::test_that("normalize_for_path_compare NULL/boş için '' ve vektörde ilk öğeyi alır", {
  .helperspath_source_once()
  testthat::expect_identical(normalize_for_path_compare(NULL), "")
  testthat::expect_identical(normalize_for_path_compare(""), "")
  testthat::expect_identical(normalize_for_path_compare(character(0)), "")
  # Vektör verilirse ilk öğe işlenir ve küçük harfe çevrilir
  testthat::expect_identical(normalize_for_path_compare(c("/A/B", "/C")), "/a/b")
})

testthat::test_that("normalize_for_path_compare UNC önekleri, çoklu slash ve büyük harfi normalize eder", {
  .helperspath_source_once()
  # //?/UNC öneki -> // (ardından çoklu slash tekilleşir)
  testthat::expect_identical(
    normalize_for_path_compare("//?/UNC/server/share/x"),
    "/server/share/x"
  )
  # //?/ öneki + sürücü harfi -> C:/...
  testthat::expect_identical(
    normalize_for_path_compare("//?/C:/Temp/X"),
    "c:/temp/x"
  )
  # Çoklu slash tek slash'a iner
  testthat::expect_identical(normalize_for_path_compare("/a//b///c"), "/a/b/c")
  # ASCII büyük harf küçük harfe iner
  testthat::expect_identical(normalize_for_path_compare("/Data/FILE.CSV"), "/data/file.csv")
})

testthat::test_that("normalize_for_path_compare tek ters-slash ve UNC ayraçlarını normalize eder", {
  .helperspath_source_once()
  testthat::expect_identical(normalize_for_path_compare("a\\b\\c"), "a/b/c")
  testthat::expect_identical(normalize_for_path_compare("\\\\srv\\share"), "/srv/share")
})

# ------------------------------------------------------------------------------
# is_under_mcp_base (davranışsal olarak ilk kez kapsanıyor)
# ------------------------------------------------------------------------------
testthat::test_that("is_under_mcp_base taban yapılandırılmamışsa FALSE döner", {
  .helperspath_source_once()
  withr::local_options(mergen.mcp_base_dir = "")
  withr::with_envvar(c(MCP_FILES_BASE = ""), {
    testthat::expect_false(is_under_mcp_base("/data/mcp/file.xlsx"))
  })
})

testthat::test_that("is_under_mcp_base doğrudan taban altını, user_<id> kovasını ve eşitliği tanır", {
  .helperspath_source_once()
  withr::local_options(mergen.mcp_base_dir = "/data/mcp")
  withr::with_envvar(c(MCP_FILES_BASE = ""), {
    testthat::expect_true(is_under_mcp_base("/data/mcp/file.xlsx"))
    testthat::expect_true(is_under_mcp_base("/data/mcp/user_42/veri.xlsx"))
    testthat::expect_true(is_under_mcp_base("/data/mcp"))
  })
})

testthat::test_that("is_under_mcp_base kardeş önek ve taban dışı yolları reddeder", {
  .helperspath_source_once()
  withr::local_options(mergen.mcp_base_dir = "/data/mcp")
  withr::with_envvar(c(MCP_FILES_BASE = ""), {
    # Aynı önekli kardeş dizin taban altı SAYILMAZ
    testthat::expect_false(is_under_mcp_base("/data/mcp_other/file.xlsx"))
    testthat::expect_false(is_under_mcp_base("/other/place/x.xlsx"))
  })
})

testthat::test_that("is_under_mcp_base Türkçe taban/yolu ve MCP_FILES_BASE ortam fallback'ini onurlar", {
  .helperspath_source_once()
  # Türkçe taban altındaki Türkçe yol taban içi sayılır
  withr::local_options(mergen.mcp_base_dir = "/veri/Çalışma")
  withr::with_envvar(c(MCP_FILES_BASE = ""), {
    testthat::expect_true(is_under_mcp_base("/veri/Çalışma/Ömer.xlsx"))
  })

  # Opsiyon boşsa MCP_FILES_BASE ortam değişkeni kullanılır
  withr::local_options(mergen.mcp_base_dir = "")
  withr::with_envvar(c(MCP_FILES_BASE = "/envbase"), {
    testthat::expect_true(is_under_mcp_base("/envbase/f.xlsx"))
    testthat::expect_false(is_under_mcp_base("/disarisi/f.xlsx"))
  })
})
