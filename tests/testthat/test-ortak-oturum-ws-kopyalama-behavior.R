# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-ws-kopyalama-behavior.R
# Açıklama: Ortak Bilge Yolaç çalışma alanına dosya kopyalama davranış
#           testleri: aşamalı hedef çözümü (hangi aşama başarısız — genel
#           mesaj yok), güvenli/deterministik toplu kopya (doğru sayaçlar:
#           kopyalanan/atlanan/başarısız), ad çakışması, geçersiz hedef ve
#           bildirim metinleri. DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("fs")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists(".oo_db_pos_int", mode = "function", inherits = TRUE)) {
    .oo_db_pos_int <<- function(value) {
      value <- suppressWarnings(as.integer(value %||% NA_integer_)[1])
      if (is.na(value) || value <= 0L) return(NA_integer_)
      value
    }
  }
  if (!exists(".oo_db_log_warn", mode = "function", inherits = TRUE)) {
    .oo_db_log_warn <<- function(...) invisible(NULL)
  }

  # Kök çözümleme + hedef adlandırma + kök-içi denetim gerçek dosyalardan gelir.
  source(file.path(repo_root, "R", "helpers_ortak_oturum_files.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_ortak_oturum_by_calisma_alani.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_ortak_oturum_ws_kopyalama.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("hedef çözümü: özel dizin, paylaşılan klasör ve kök yapılandırma aşamaları ayrışır", {
  d <- withr::local_tempdir()

  # Özel dizin mevcut: "ozel" aşaması.
  ozel <- file.path(d, "proje"); dir.create(ozel)
  withr::local_options(mergen.files_root = file.path(d, "files_root"))
  sonuc <- oo_ws_hedef_cozumle(ozel, 5L)
  expect_identical(sonuc$asama, "ozel")
  expect_identical(sonuc$yol, ozel)

  # Özel dizin yok: paylaşılan oda klasörüne düşer (dosya kökü altında oluşur).
  # ortak_by_calisma_alani modül dosyasında yaşar; izole testte üretim
  # davranışının eşdeğeri otomatik_fn enjeksiyonuyla verilir.
  otomatik_uret <- function(oturum_id) {
    kok <- ortak_oturum_dosya_koku(oturum_id)
    if (is.null(kok)) return(NULL)
    ws <- file.path(kok, "calisma_alani")
    dir.create(ws, showWarnings = FALSE, recursive = TRUE)
    if (dir.exists(ws)) ws else NULL
  }
  sonuc2 <- oo_ws_hedef_cozumle("", 5L, otomatik_fn = otomatik_uret)
  expect_identical(sonuc2$asama, "paylasilan")
  expect_true(dir.exists(sonuc2$yol))

  # Kök yapılandırması tamamen erişilemez: aşama + eyleme dönük Türkçe mesaj.
  eski_files_root <- Sys.getenv("MERGEN_FILES_ROOT", unset = NA)
  eski_uploads <- Sys.getenv("MERGEN_UPLOADS_DIR", unset = NA)
  eski_mcp <- Sys.getenv("MCP_FILES_BASE", unset = NA)
  eski_mcp2 <- Sys.getenv("MERGEN_MCP_BASE_DIR", unset = NA)
  withr::defer({
    for (nm in c("MERGEN_FILES_ROOT", "MERGEN_UPLOADS_DIR", "MCP_FILES_BASE", "MERGEN_MCP_BASE_DIR")) {
      deger <- switch(nm,
        MERGEN_FILES_ROOT = eski_files_root, MERGEN_UPLOADS_DIR = eski_uploads,
        MCP_FILES_BASE = eski_mcp, MERGEN_MCP_BASE_DIR = eski_mcp2
      )
      if (is.na(deger)) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(deger), nm))
    }
  })
  Sys.unsetenv(c("MERGEN_FILES_ROOT", "MERGEN_UPLOADS_DIR", "MCP_FILES_BASE", "MERGEN_MCP_BASE_DIR"))
  withr::local_options(mergen.files_root = NULL)

  # resolve_mcp_base_dir bu izole bağlamda yüklü değil; MERGEN_UPLOADS_DIR
  # global değişkeni de yoksa kök çözülemez.
  sonuc3 <- oo_ws_hedef_cozumle(
    "", 5L,
    etkin_fn = function(kayit_dizini, oturum_id, otomatik_fn = NULL) list(yol = NULL, ozel = FALSE)
  )
  expect_null(sonuc3$yol)
  expect_identical(sonuc3$asama, "kok_yapilandirma")
  expect_true(grepl("MERGEN_FILES_ROOT", sonuc3$hata, fixed = TRUE))

  # Özel dizin yazılı ama erişilemiyor + kök de yok: özel-dizin odaklı mesaj.
  sonuc4 <- oo_ws_hedef_cozumle(
    "C:/olmayan/dizin", 5L,
    etkin_fn = function(kayit_dizini, oturum_id, otomatik_fn = NULL) list(yol = NULL, ozel = FALSE)
  )
  expect_null(sonuc4$yol)
  expect_true(grepl("Özel proje dizini", sonuc4$hata, fixed = TRUE))
})

test_that("toplu kopya: doğru sayaçlar, klasör/eksik atlama ve ad çakışması çözümü", {
  d <- withr::local_tempdir()
  ws <- file.path(d, "calisma_alani"); dir.create(ws)

  kaynak_dizin <- file.path(d, "kaynak"); dir.create(kaynak_dizin)
  a <- file.path(kaynak_dizin, "rapor.txt"); writeLines("içerik bir", a)
  b <- file.path(kaynak_dizin, "veri_özeti.csv"); writeLines("x;y", b)
  klasor <- file.path(kaynak_dizin, "alt"); dir.create(klasor)

  sonuc <- oo_ws_kopyalama_calistir(
    c(a, b, klasor, file.path(kaynak_dizin, "yok.txt")),
    c("rapor.txt", "veri_özeti.csv", "alt", "yok.txt"),
    ws
  )

  expect_identical(sonuc$kopyalanan, 2L)
  expect_identical(sonuc$atlanan, 2L)   # klasör + eksik dosya
  expect_identical(sonuc$basarisiz, 0L)
  expect_true(file.exists(file.path(ws, "rapor.txt")))
  expect_true(file.exists(file.path(ws, "veri_özeti.csv")))

  # Aynı adla ikinci kopya: deterministik sayaçlı ad (_(1)) üretilir; veri ezilmez.
  sonuc2 <- oo_ws_kopyalama_calistir(a, "rapor.txt", ws)
  expect_identical(sonuc2$kopyalanan, 1L)
  expect_true(file.exists(file.path(ws, "rapor_(1).txt")))
  expect_identical(readLines(file.path(ws, "rapor.txt"))[1], "içerik bir")

  # Boş kaynak listesi: hiçbir şey kopyalanmaz, hata da üretilmez.
  bos <- oo_ws_kopyalama_calistir(character(0), character(0), ws)
  expect_identical(bos$kopyalanan, 0L)
  expect_identical(bos$basarisiz, 0L)
})

test_that("geçersiz çalışma alanı ve yazma hatası doğru sayılır", {
  d <- withr::local_tempdir()
  a <- file.path(d, "dosya.txt"); writeLines("x", a)

  # Çalışma alanı boş/çözülemedi: tümü başarısız + açıklayıcı hata.
  sonuc <- oo_ws_kopyalama_calistir(a, "dosya.txt", "")
  expect_identical(sonuc$basarisiz, 1L)
  expect_true(length(sonuc$hatalar) > 0L)

  # Var olmayan çalışma alanına kopya: file.copy başarısız sayılır (yarım
  # kopya kalmaz), sayaç gerçeği söyler.
  sonuc2 <- oo_ws_kopyalama_calistir(a, "dosya.txt", file.path(d, "olmayan_ws"))
  expect_identical(sonuc2$kopyalanan, 0L)
  expect_identical(sonuc2$basarisiz, 1L)
})

test_that("bildirim metinleri sonucu doğru ve Türkçe özetler", {
  tam <- oo_ws_kopyalama_bildirimi(list(kopyalanan = 3L, atlanan = 0L, basarisiz = 0L))
  expect_identical(tam$tur, "message")
  expect_true(grepl("3 dosya paylaşılan çalışma alanına kopyalandı", tam$mesaj, fixed = TRUE))

  kismi <- oo_ws_kopyalama_bildirimi(list(kopyalanan = 2L, atlanan = 0L, basarisiz = 1L))
  expect_identical(kismi$tur, "warning")
  expect_true(grepl("2 dosya kopyalandı; 1 dosya kopyalanamadı", kismi$mesaj, fixed = TRUE))

  hic <- oo_ws_kopyalama_bildirimi(list(kopyalanan = 0L, atlanan = 0L, basarisiz = 2L))
  expect_identical(hic$tur, "error")

  bos <- oo_ws_kopyalama_bildirimi(list(kopyalanan = 0L, atlanan = 1L, basarisiz = 0L))
  expect_identical(bos$tur, "warning")
  expect_true(grepl("uygun dosya bulunamadı", bos$mesaj, fixed = TRUE))
})

test_that("ortak_oturum_dosya_koku erişilemez dosya kökünde MCP tabanına düşer", {
  d <- withr::local_tempdir()

  # Dosya kökü bir DOSYAYA işaret ediyor (dizin oluşturulamaz) -> düşüş.
  bozuk_kok <- file.path(d, "kok_bir_dosya")
  writeLines("x", bozuk_kok)
  withr::local_options(mergen.files_root = file.path(bozuk_kok, "ic"))

  yedek_taban <- file.path(d, "uploads")
  dir.create(yedek_taban)
  eski_uploads_var <- exists("MERGEN_UPLOADS_DIR", inherits = TRUE)
  MERGEN_UPLOADS_DIR <<- yedek_taban
  withr::defer({
    if (!eski_uploads_var) suppressWarnings(rm("MERGEN_UPLOADS_DIR", envir = globalenv()))
  })

  # Test oturumunda dosya deposu yardımcıları yüklüyse düşüş resolve_mcp_base_dir
  # üzerinden gider; izole koşuda MERGEN_UPLOADS_DIR global değişkeni kullanılır.
  beklenen_taban <- if (exists("resolve_mcp_base_dir", mode = "function", inherits = TRUE)) {
    tryCatch(resolve_mcp_base_dir(), error = function(e) yedek_taban)
  } else {
    yedek_taban
  }

  kok <- ortak_oturum_dosya_koku(9L)
  expect_false(is.null(kok))
  expect_true(startsWith(
    normalizePath(kok, winslash = "/"),
    normalizePath(beklenen_taban, winslash = "/")
  ))
  expect_true(dir.exists(kok))
})
