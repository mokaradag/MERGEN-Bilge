# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-path-normalize-behavior.R
# Açıklama: R/utils_path_helpers.R içindeki normalize_mcp_path fonksiyonunun
#           DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu). Windows VM /
#           UNC ağ paylaşımı yolları kritik bir sınırdır: ters slash'lı UNC
#           (\\server\share\...) forward-slash UNC'ye çevrilmeli ve tekrar eden
#           baştaki host/share çifti tekilleştirilmelidir. Bu testler yalnızca
#           DETERMİNİSTİK UNC dalını ve boş/NULL kenarını kapsar; normalizePath'e
#           bağlı UNC-olmayan dal sadece var-olan geçici dizinle yoklanır.
#           Saf string mantığı; fs/ağ/Shiny GEREKMEZ.
# ==============================================================================

.mcppath_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "utils_text_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_mcp_path",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "utils_path_helpers.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

testthat::test_that("normalize_mcp_path NULL/boş girdide boş dize döner", {
  .mcppath_source_once()
  testthat::expect_identical(normalize_mcp_path(NULL), "")
  testthat::expect_identical(normalize_mcp_path(""), "")
})

testthat::test_that("normalize_mcp_path forward-slash UNC tekrarını tekilleştirir", {
  .mcppath_source_once()
  # Tekrar eden host/share çifti tekilleşir.
  testthat::expect_identical(
    normalize_mcp_path("//rehisds/gruplar/rehisds/gruplar/alt"),
    "//rehisds/gruplar/alt"
  )
  # Tekrar yoksa UNC olduğu gibi korunur.
  testthat::expect_identical(
    normalize_mcp_path("//rehisds/gruplar/alt"),
    "//rehisds/gruplar/alt"
  )
})

testthat::test_that("normalize_mcp_path ters-slash UNC'yi forward-slash UNC'ye çevirir", {
  .mcppath_source_once()
  # \\rehisds\gruplar\alt (R literalinde her ters slash iki kez yazılır).
  testthat::expect_identical(
    normalize_mcp_path("\\\\rehisds\\gruplar\\alt"),
    "//rehisds/gruplar/alt"
  )
  # Ters-slash UNC + tekrar eden çift -> hem çevrim hem tekilleştirme.
  testthat::expect_identical(
    normalize_mcp_path("\\\\rehisds\\gruplar\\rehisds\\gruplar\\alt"),
    "//rehisds/gruplar/alt"
  )
})

testthat::test_that("normalize_mcp_path UNC-olmayan var-olan dizini çözer", {
  .mcppath_source_once()
  d <- file.path(tempdir(), "mcp_path_norm_dir")
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  donen <- normalize_mcp_path(d)
  testthat::expect_true(nzchar(donen))
  testthat::expect_true(dir.exists(donen))
  # UNC'ye dönüşmemeli.
  testthat::expect_false(grepl("^//", donen))
})
