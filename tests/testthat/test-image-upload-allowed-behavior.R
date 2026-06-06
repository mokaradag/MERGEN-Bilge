# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-upload-allowed-behavior.R
# Aciklama: Gorsel dosya yukleme sozlesmesi davranissal testleri.
#           - fm_image_extensions / fm_normal_allowed_extensions gorselleri icerir
#           - validate_uploaded_file gorseli kabul, desteklenmeyeni (zip) reddeder
#             (kalici klasore kopyalanmadan once; saved-but-hidden sizintisi yok)
#           - readFileContentToString gorsel icin ham ikili bayt degil temiz metin
#             dondurur (ikili icerik metin olarak okunmaz; copa/NUL sizmaz)
#           Gercek DB/LLM/ag/tarayici GEREKMEZ.
# ==============================================================================

.image_upload_policy_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_policy.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("fm_image_extensions yaygin gorsel uzantilarini dondurur", {
  env <- .image_upload_policy_env()
  imgs <- env$fm_image_extensions()
  for (e in c("jpg", "jpeg", "png", "gif", "webp", "bmp", "svg")) {
    testthat::expect_true(e %in% imgs, info = e)
  }
})

testthat::test_that("fm_normal_allowed_extensions gorselleri ve mevcut belge turlerini icerir", {
  env <- .image_upload_policy_env()
  exts <- env$fm_normal_allowed_extensions()
  # Gorseller artik izinli
  testthat::expect_true("png" %in% exts)
  testthat::expect_true("jpeg" %in% exts)
  # Mevcut belge turleri korunur
  for (e in c("txt", "pdf", "docx", "xlsx", "csv")) {
    testthat::expect_true(e %in% exts, info = e)
  }
  # Desteklenmeyen ikili turler hala listede degil
  testthat::expect_false("zip" %in% exts)
  testthat::expect_false("exe" %in% exts)
})

testthat::test_that("validate_uploaded_file gorseli kabul, zip'i izin-listesi diye reddeder", {
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

testthat::test_that("readFileContentToString gorsel icin ikili bayt degil temiz metin dondurur", {
  env <- new.env(parent = globalenv())
  for (f in c("utils_common.R", "utils_text_encoding.R", "utils_excel_reader.R", "helpers_files.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", f), encoding = "UTF-8", local = env)
  }
  # readFileContentToString yol yardimcilari izole kosumda taklit edilir.
  env$path_exists_relaxed <- function(p) file.exists(p)
  env$resolve_readable_path <- function(p) p

  for (ext in c("png", "jpeg", "gif", "svg")) {
    tmp <- tempfile(fileext = paste0(".", ext))
    # Gercek ikili baytlar yaz; metin olarak okunsaydi cop/NUL uretirdi.
    writeBin(as.raw(c(0x00, 0x01, 0xff, 0x89, 0x50)), tmp)
    note <- env$readFileContentToString(list(name = paste0("gorsel.", ext), datapath = tmp, size = 5))
    # Sonuc tek bir karakter dizisi olmali.
    testthat::expect_true(is.character(note) && length(note) == 1L, info = ext)
    # ASIL sozlesme: yazdigimiz ham ikili baytlar (0x00/0x01) nota SIZMAMALI.
    # (Windows/Turkce locale'de iconv/Turkce-grepl kirilgan oldugu icin yalnizca
    # bayt-tabanli "ikili sizinti yok" kontrolu yapilir.)
    note_bytes <- charToRaw(note)
    testthat::expect_false(any(note_bytes == as.raw(0x00)), info = ext)
    testthat::expect_false(any(note_bytes == as.raw(0x01)), info = ext)
    unlink(tmp)
  }
})
