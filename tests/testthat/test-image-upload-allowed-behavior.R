# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-upload-allowed-behavior.R
# Açıklama: Görsel dosya yükleme sözleşmesi davranışsal testleri.
#           - fm_image_extensions / fm_normal_allowed_extensions görselleri içerir
#           - validate_uploaded_file görseli kabul, desteklenmeyeni (zip) reddeder
#             (kalıcı klasöre kopyalanmadan önce; saved-but-hidden sızıntısı yok)
#           - readFileContentToString görsel için ham bayt yerine açık Türkçe not
#             döndürür (vision yok, ikili içerik metin olarak okunmaz)
#           Gerçek DB/LLM/ağ/tarayıcı GEREKMEZ.
# ==============================================================================

.image_upload_policy_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_policy.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("fm_image_extensions yaygın görsel uzantılarını döndürür", {
  env <- .image_upload_policy_env()
  imgs <- env$fm_image_extensions()
  for (e in c("jpg", "jpeg", "png", "gif", "webp", "bmp", "svg")) {
    testthat::expect_true(e %in% imgs, info = e)
  }
})

testthat::test_that("fm_normal_allowed_extensions görselleri ve mevcut belge türlerini içerir", {
  env <- .image_upload_policy_env()
  exts <- env$fm_normal_allowed_extensions()
  # Görseller artık izinli
  testthat::expect_true("png" %in% exts)
  testthat::expect_true("jpeg" %in% exts)
  # Mevcut belge türleri korunur
  for (e in c("txt", "pdf", "docx", "xlsx", "csv")) {
    testthat::expect_true(e %in% exts, info = e)
  }
  # Desteklenmeyen ikili türler hâlâ listede değil
  testthat::expect_false("zip" %in% exts)
  testthat::expect_false("exe" %in% exts)
})

testthat::test_that("validate_uploaded_file görseli kabul, zip'i izin-listesi diye reddeder", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_policy.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_upload_validator.R"),
         encoding = "UTF-8", local = env)

  exts <- env$fm_normal_allowed_extensions()

  png <- tempfile(fileext = ".png"); writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), png)
  zip <- tempfile(fileext = ".zip"); writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04)), zip)
  on.exit(unlink(c(png, zip)), add = TRUE)

  v_png <- env$validate_uploaded_file(path = png, filename = "manzara.png",
                                      max_size_mb = 25, allowed_ext = exts)
  v_zip <- env$validate_uploaded_file(path = zip, filename = "arsiv.zip",
                                      max_size_mb = 25, allowed_ext = exts)

  testthat::expect_true(isTRUE(v_png$ok))
  testthat::expect_false(isTRUE(v_zip$ok))
  testthat::expect_identical(v_zip$code, "ext_not_allowed")
})

testthat::test_that("readFileContentToString görsel için ikili yerine açık Türkçe not döndürür", {
  env <- new.env(parent = globalenv())
  for (f in c("utils_common.R", "utils_text_encoding.R", "utils_excel_reader.R", "helpers_files.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", f), encoding = "UTF-8", local = env)
  }
  # readFileContentToString'un yol yardımcıları izole koşumda taklit edilir.
  env$path_exists_relaxed <- function(p) file.exists(p)
  env$resolve_readable_path <- function(p) p

  for (ext in c("png", "jpeg", "gif", "svg")) {
    tmp <- tempfile(fileext = paste0(".", ext))
    writeBin(as.raw(c(0x00, 0x01, 0x02)), tmp)
    note <- env$readFileContentToString(list(name = paste0("gorsel.", ext), datapath = tmp, size = 3))
    testthat::expect_true(grepl("Görsel dosya", note, fixed = TRUE), info = ext)
    # Ham ikili bayt sızmamalı: not düz Türkçe metin olmalı.
    testthat::expect_true(grepl("analiz edilmemektedir", note, fixed = TRUE), info = ext)
    unlink(tmp)
  }
})
