# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-runtime-source-dir-behavior.R
# Açıklama: R/helpers_claude_code_runtime_resolver.R resolve_claude_runtime_source_dir()
#           davranış testleri. Boş/NA girdi, relaxed çözücünün öncelik kazanması,
#           gerçek var olan dizinin aday yoldan çözülmesi ve var olmayan yol için
#           boş dize dönmesi doğrulanır. Bağımlı yardımcılar (normalize_mcp_path,
#           path_exists_relaxed, cc_resolve_existing_dir_relaxed) deterministik
#           biçimde stub'lanır; gerçek UNC/Windows/ağ erişimi GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

.rtdir_env <- function(relaxed_value = "") {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Relaxed çözücüyü kontrol et: boş dönerse aday yol mantığına düşülür.
  env$cc_resolve_existing_dir_relaxed <- function(x) relaxed_value
  # Yol normalizasyonu ve varlık kontrolü deterministik olsun.
  env$normalize_mcp_path <- function(p, must_exist = FALSE) as.character(p)[1]
  env$path_exists_relaxed <- function(p) isTRUE(dir.exists(p))
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_runtime_resolver.R"),
    encoding = "UTF-8", local = env
  )
  env
}

test_that("boş, NA ve NULL workdir için boş dize döner", {
  env <- .rtdir_env()
  expect_identical(env$resolve_claude_runtime_source_dir(""), "")
  expect_identical(env$resolve_claude_runtime_source_dir(NA_character_), "")
  expect_identical(env$resolve_claude_runtime_source_dir(NULL), "")
})

test_that("relaxed çözücü GERÇEK dizin dönerse o değer öncelik kazanır", {
  d <- file.path(tempdir(), paste0("rtdir_relaxed_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  env <- .rtdir_env(relaxed_value = d)
  expect_identical(env$resolve_claude_runtime_source_dir("/herhangi/girdi"), d)
})

# Regresyon: birincil relaxed sonuç DİZİN olarak doğrulanmıyordu. Paylaşılan
# çözümleyici bir DOSYA yolunu kabul edebiliyor ve erken dönüş aşağıdaki dizin
# denetimini atlıyordu; dosya yolu runtime çalışma dizini olarak kullanılırdı.
test_that("relaxed çözücü DOSYA dönerse kabul edilmez", {
  f <- tempfile(fileext = ".txt")
  writeLines("x", f)
  on.exit(unlink(f), add = TRUE)

  env <- .rtdir_env(relaxed_value = f)
  expect_identical(env$resolve_claude_runtime_source_dir("/herhangi/girdi"), "")
})

test_that("gerçek var olan dizin aday yoldan çözülür", {
  env <- .rtdir_env(relaxed_value = "")  # relaxed boş -> aday yola düş
  d <- file.path(tempdir(), paste0("rtdir_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  out <- env$resolve_claude_runtime_source_dir(d)
  expect_identical(out, d)
})

test_that("var olmayan yol için boş dize döner", {
  env <- .rtdir_env(relaxed_value = "")
  yok <- file.path(tempdir(), paste0("yok_rtdir_", as.integer(runif(1, 1e6, 9e6))))
  expect_identical(env$resolve_claude_runtime_source_dir(yok), "")
})

test_that("dosya yolu kaynak dizin olarak kabul edilmez", {
  env <- .rtdir_env()
  # path_exists_relaxed dosyalar için de TRUE dönebilir; kaynak DİZİN çözümü
  # bir dosyayı dizin gibi kabul etmemelidir.
  env$path_exists_relaxed <- function(p) TRUE

  gecici <- withr::local_tempdir()
  dosya <- file.path(gecici, "rapor.txt")
  writeLines("icerik", dosya)

  expect_identical(env$resolve_claude_runtime_source_dir(dosya), "")

  # Gerçek dizin hâlâ çözülebilir olmalıdır.
  expect_identical(
    gsub("\\\\", "/", env$resolve_claude_runtime_source_dir(gecici)),
    gsub("\\\\", "/", gecici)
  )
})
