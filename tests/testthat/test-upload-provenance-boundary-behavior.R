# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-provenance-boundary-behavior.R
# Açıklama: Tarayıcı yükleme kaynağı güvenlik sınırı. İstemci yalnızca Shiny'nin
#           bu oturuma verdiği yükleme nesnesini işaret edebilir; sunucuda
#           okunabilir herhangi bir dosya yolunu (geçici dizin altında olsa da)
#           alım hattına sokamaz. Meşru yüklemeler Shiny'nin GERÇEK yükleme
#           işlemiyle (uploadInit/uploadEnd katmanı) üretilir; böylece
#           Windows geçici yol/kısa ad davranışı da aynı kodla sınanır.
# ==============================================================================

.provenans_env <- local({
  env <- NULL
  function() {
    if (!is.null(env)) return(env)
    env <<- new.env(parent = globalenv())
    sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_file_ingestion_sources.R"),
               envir = env, keep.source = FALSE)
    env
  }
})

# Shiny'nin kendi yükleme işlemi: sunucunun oturuma verdiği iş kimliği ve düzen.
.shiny_yukleme <- function(ad, icerik) {
  baglam <- shiny:::FileUploadContext$new()
  is_kimligi <- baglam$createUploadOperation(list(list(name = ad, size = length(icerik), type = "text/plain")))
  islem <- baglam$getUploadOperation(is_kimligi)
  islem$fileBegin()
  islem$fileChunk(icerik)
  islem$fileEnd()
  df <- islem$finish()
  withr::defer(unlink(dirname(df$datapath), recursive = TRUE), envir = parent.frame())
  df
}

test_that("Shiny'nin verdiği yükleme kabul edilir; Türkçe ad korunur", {
  env <- .provenans_env()
  ad <- paste0("T", intToUtf8(c(0x00FC, 0x0072, 0x006B, 0x00E7, 0x0065)), " rapor.txt")
  df <- .shiny_yukleme(ad, charToRaw("veri\n"))
  sonuc <- env$file_ingestion_shiny_uploads(df)
  expect_identical(sonuc$rejected, 0L)
  expect_identical(nrow(sonuc$uploads), 1L)
  expect_identical(sonuc$uploads$name, ad)
  expect_identical(sonuc$uploads$datapath, df$datapath)
})

test_that("istemcinin uydurduğu liste biçimli yükleme reddedilir", {
  env <- .provenans_env()
  hedef <- withr::local_tempfile(fileext = ".txt")
  writeLines("gizli", hedef)
  for (sahte in list(
    list(name = "a.txt", datapath = hedef, size = 5, type = "text/plain"),
    list(list(name = "a.txt", datapath = hedef, size = 5, type = "text/plain")),
    hedef
  )) {
    sonuc <- env$file_ingestion_shiny_uploads(sahte)
    expect_identical(nrow(sonuc$uploads), 0L)
    expect_gte(sonuc$rejected, 1L)
  }
  expect_identical(env$file_ingestion_shiny_uploads(NULL)$rejected, 0L)
})

test_that("data.frame olsa da Shiny yükleme düzeninde olmayan yol reddedilir", {
  env <- .provenans_env()
  gercek <- .shiny_yukleme("iyi.txt", charToRaw("iyi"))

  # Geçici dizin altındaki başka bir dosya (ör. başka bir işin önbelleği).
  baska <- withr::local_tempfile(fileext = ".txt")
  writeLines("baska kullanici", baska)
  # Uygulama dizinindeki dosya (geçici dizin dışı).
  disarida <- file.path(resolve_repo_root_for_tests(), "app.R")
  # Shiny düzenine benzer ama farklı kökte.
  sahte_kok <- withr::local_tempdir()
  sahte_is <- file.path(sahte_kok, "0123456789abcdef01234567")
  dir.create(sahte_is)
  sahte_dosya <- file.path(sahte_is, "0.txt")
  writeLines("x", sahte_dosya)
  # Yol geçişi ve var olmayan dosya.
  gecis <- file.path(dirname(gercek$datapath), "..", "..", "0.txt")
  yok <- file.path(dirname(gercek$datapath), "9.txt")

  yollar <- c(gercek$datapath, baska, disarida, sahte_dosya, gecis, yok, NA_character_, "")
  df <- data.frame(name = paste0("f", seq_along(yollar), ".txt"), size = 1, type = "text/plain",
                   datapath = yollar, stringsAsFactors = FALSE)
  sonuc <- env$file_ingestion_shiny_uploads(df)
  expect_identical(sonuc$uploads$datapath, gercek$datapath)
  expect_identical(sonuc$rejected, length(yollar) - 1L)

  # Eksik sütun: tüm değer reddedilir.
  eksik <- env$file_ingestion_shiny_uploads(gercek[, c("name", "datapath")])
  expect_identical(nrow(eksik$uploads), 0L)
  expect_identical(eksik$rejected, 1L)
})

test_that("Shiny iş dizinindeki sembolik bağ dışarıyı gösteremez", {
  env <- .provenans_env()
  gercek <- .shiny_yukleme("iyi.txt", charToRaw("iyi"))
  hedef <- file.path(resolve_repo_root_for_tests(), "app.R")
  bag <- file.path(dirname(gercek$datapath), "1.txt")
  olustu <- suppressWarnings(tryCatch(file.symlink(hedef, bag), error = function(e) FALSE))
  # Windows'ta sembolik bağ ayrıcalık ister; ayrıcalık yoksa bu saldırı da yoktur.
  skip_if_not(isTRUE(olustu), "Bu ortamda sembolik bağ oluşturulamıyor")
  df <- gercek
  df$datapath <- bag
  expect_identical(nrow(env$file_ingestion_shiny_uploads(df)$uploads), 0L)
})

test_that("iş dizini adını taşıyan bağlantı noktası (junction/symlink) dışarıyı gösteremez", {
  env <- .provenans_env()
  dis <- withr::local_tempdir(tmpdir = dirname(tempdir()))  # yükleme kökü dışında
  writeBin(charToRaw("dis"), file.path(dis, "0.txt"))
  is_adi <- file.path(tempdir(), paste(rep("ab", 12), collapse = ""))
  withr::defer(unlink(is_adi, recursive = FALSE))
  olustu <- suppressWarnings(tryCatch(
    if (.Platform$OS.type == "windows") Sys.junction(dis, is_adi) else file.symlink(dis, is_adi),
    error = function(e) FALSE))
  skip_if_not(isTRUE(olustu) && file.exists(file.path(is_adi, "0.txt")), "Bağlantı noktası oluşturulamıyor")
  df <- data.frame(name = "x.txt", size = 3, type = "text/plain",
                   datapath = file.path(is_adi, "0.txt"), stringsAsFactors = FALSE)
  sonuc <- env$file_ingestion_shiny_uploads(df)
  expect_identical(nrow(sonuc$uploads), 0L)
  expect_identical(sonuc$rejected, 1L)
})

test_that("iki yükleme girişi de kaynak kapısından geçer", {
  oku <- function(yol) paste(readLines(file.path(resolve_repo_root_for_tests(), yol),
                                       encoding = "UTF-8", warn = FALSE), collapse = "\n")
  sohbet <- oku("R/server_observers_chat_input.R")
  dm <- oku("R/module_file_manager.R")
  expect_match(sohbet, "file_ingestion_session_uploads(input$file_upload, session)", fixed = TRUE)
  expect_match(sohbet, "uploads_df             = yuklemeler", fixed = TRUE)
  expect_match(dm, "files_df <- file_ingestion_session_uploads(input$bulk_upload, session)", fixed = TRUE)
  expect_false(grepl("uploads_df\\s*=\\s*input\\$file_upload", sohbet, perl = TRUE))
  expect_false(grepl("files_df <- input$bulk_upload", dm, fixed = TRUE))
})

test_that("gözlemci yardımcısı reddedilen satırı bildirir ve yalnızca Shiny kaynaklı satırı döndürür", {
  env <- .provenans_env()
  bildirimler <- character(0)
  env$showToast <- function(session, message, type = "info", ...) bildirimler <<- c(bildirimler, type)
  withr::defer(rm("showToast", envir = env))
  gercek <- .shiny_yukleme("iyi.txt", charToRaw("iyi"))
  sahte <- gercek
  sahte$datapath <- file.path(resolve_repo_root_for_tests(), "app.R")
  sonuc <- env$file_ingestion_session_uploads(rbind(gercek, sahte), session = NULL)
  expect_identical(sonuc$datapath, gercek$datapath)
  expect_identical(bildirimler, "error")
  expect_identical(nrow(env$file_ingestion_session_uploads(list(name = "a", datapath = "app.R"), NULL)), 0L)
})
