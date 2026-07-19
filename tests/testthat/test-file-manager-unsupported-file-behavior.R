# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-unsupported-file-behavior.R
# Açıklama: Kullanıcının kalıcı klasöründe (mergen_uploads/user_<id>) bulunan
#           DESTEKLENMEYEN uzantılı dosyaların (örn. ajan üretimi .doc)
#           davranışsal sözleşmesi:
#             1) Dosya Yönetimi tablosunda GÖRÜNÜR (gizlenmez),
#             2) durum rozeti "Desteklenmeyen dosya türü" taşır,
#             3) yalnızca indir/sil işlemleri sunulur (önizleme/ekleme yok),
#             4) her girişte yanıltıcı "kaydedilemedi" toast'ı ÜRETİLMEZ,
#             5) içerik ayrıştırma yolu (process_uploaded_file) hiç çağrılmaz.
#           Ayrıca kalıcı dosya envanterinin TEMBEL yüklenme sözleşmesi statik
#           olarak doğrulanır (açılışta tarama yok; page_opened ile tarama).
#           Gerçek DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

.unsupported_fm_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_file_manager_policy.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_manager_table.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_manager_refresh_guard.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_manager_state_runtime.R"), encoding = "UTF-8", local = env)
  env
}

.read_repo_text_unsupported <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)
  raw_data <- readBin(full_path, what = "raw", n = file.info(full_path)$size[1])
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  enc2utf8(txt %||% "")
}

testthat::test_that("desteklenmeyen dosya satırı durum rozeti ve sınırlı işlemlerle üretilir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("htmltools")
  env <- .unsupported_fm_env()

  ns <- shiny::NS("fm")
  satir <- env$fm_build_unsupported_file_table_row(
    file_name = "eski_rapor.doc",
    file_size = 2048,
    file_id = "file_test_1",
    ns = ns
  )

  # Tablo şeması normal satırlarla birebir aynı olmalı (rbind uyumu).
  testthat::expect_identical(names(satir), names(env$fm_empty_files_df()))
  testthat::expect_identical(satir$Dosya_Adi[1], "eski_rapor.doc")

  # Durum rozeti görünür ve Türkçe.
  testthat::expect_true(grepl("Desteklenmeyen dosya türü", satir$Tur[1], fixed = TRUE))

  # İşlemler: indir + sil VAR, önizleme (view) YOK.
  testthat::expect_true(grepl("js-download-btn", satir$Islemler[1], fixed = TRUE))
  testthat::expect_true(grepl('data-action="delete"', satir$Islemler[1], fixed = TRUE))
  testthat::expect_false(grepl('data-action="view"', satir$Islemler[1], fixed = TRUE))

  # Model Bağlamı hücresi ekleme kutusu İÇERMEZ.
  testthat::expect_false(grepl("attach-checkbox", satir$Model_Baglam[1], fixed = TRUE))
  testthat::expect_false(grepl("<input", satir$Model_Baglam[1], fixed = TRUE))
})

testthat::test_that("kalıcı klasör yenilemesi .doc dosyasını görünür ekler; toast/parse yolu çalışmaz", {
  testthat::skip_if_not_installed("shiny")
  env <- .unsupported_fm_env()

  # Geçici kullanıcı klasörü: 1 desteklenen + 1 desteklenmeyen dosya.
  klasor <- file.path(tempdir(), paste0("fm_unsupported_", as.integer(Sys.time())))
  dir.create(klasor, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(klasor, recursive = TRUE, force = TRUE), add = TRUE)

  desteklenen <- file.path(klasor, "notlar.txt")
  desteklenmeyen <- file.path(klasor, "ajan_raporu.doc")
  writeLines("merhaba", desteklenen)
  writeLines("eski word", desteklenmeyen)

  # Stub'lar: SSO kapalı, kullanıcı geçerli, dosya listesi sabit.
  env$SSO_ENABLED <- FALSE
  env$path_exists_relaxed <- function(p) file.exists(p)
  env$mergen_list_user_files <- function(uid) {
    df <- data.frame(
      path = c(desteklenen, desteklenmeyen),
      name = c("notlar.txt", "ajan_raporu.doc"),
      stringsAsFactors = FALSE
    )
    attr(df, "source") <- "test"
    df
  }

  islenen_dosyalar <- character(0)
  toast_sayisi <- 0L
  env$showToast <- function(session, message, type = "info", ...) {
    toast_sayisi <<- toast_sayisi + 1L
    invisible(TRUE)
  }

  # Sahte modül durumu (reaktif bağlam gerekmeden $ erişimli ortam).
  module_values <- new.env(parent = emptyenv())
  module_values$files <- env$fm_empty_files_df()
  module_values$file_contents <- list()
  module_values$files_in_context <- list()

  fake_session <- list(
    userData = new.env(parent = emptyenv()),
    sendCustomMessage = function(...) invisible(TRUE)
  )
  fake_session$userData$current_session_files <- list()

  refresh <- env$fm_create_refresh_from_user_folder(
    session = fake_session,
    ns = shiny::NS("fm"),
    module_values_provider = function() module_values,
    module_user_id_chr = function() "42",
    is_auth_ready = function() TRUE,
    ensure_session_registry = function() invisible(TRUE),
    attach_in_parent = function(...) invisible(TRUE),
    process_uploaded_file_callback = function(finfo) {
      islenen_dosyalar <<- c(islenen_dosyalar, finfo$name)
      fid <- paste0("file_ok_", length(islenen_dosyalar))
      module_values$file_contents[[fid]] <- list(
        name = finfo$name, datapath = finfo$datapath,
        size = finfo$size, id = fid
      )
      module_values$files <- rbind(
        module_values$files,
        env$fm_build_file_table_row(
          file_name = finfo$name, file_size = finfo$size,
          file_info = finfo, file_id = fid, ns = shiny::NS("fm")
        )
      )
      list(id = fid)
    },
    refresh_guard = env$fm_create_refresh_request_guard(),
    fm_debug = function(...) invisible(NULL)
  )

  # cat tanılama çıktısını yut, davranışı doğrula.
  invisible(utils::capture.output(refresh("page_open")))

  # Desteklenen dosya normal işlendi; desteklenmeyen dosya parse yoluna GİRMEDİ.
  testthat::expect_identical(islenen_dosyalar, "notlar.txt")

  # Tabloda İKİ satır var: desteklenmeyen dosya gizlenmedi.
  testthat::expect_identical(nrow(module_values$files), 2L)
  testthat::expect_true("ajan_raporu.doc" %in% module_values$files$Dosya_Adi)

  doc_satiri <- module_values$files[module_values$files$Dosya_Adi == "ajan_raporu.doc", , drop = FALSE]
  testthat::expect_true(grepl("Desteklenmeyen dosya türü", doc_satiri$Tur[1], fixed = TRUE))
  testthat::expect_false(grepl("attach-checkbox", doc_satiri$Model_Baglam[1], fixed = TRUE))

  # Girişte/yenilemede desteklenmeyen dosya için TOAST ÜRETİLMEZ (spam yok).
  testthat::expect_identical(toast_sayisi, 0L)

  # file_contents kaydı sınırlı işlemler (indir/sil) için mevcut ve işaretli.
  doc_kayitlari <- Filter(function(e) identical(e$name, "ajan_raporu.doc"), module_values$file_contents)
  testthat::expect_length(doc_kayitlari, 1L)
  testthat::expect_true(isTRUE(doc_kayitlari[[1]]$unsupported))
})

testthat::test_that("tekrarlanan yenilemeler de desteklenmeyen dosya için toast üretmez", {
  testthat::skip_if_not_installed("shiny")
  env <- .unsupported_fm_env()

  klasor <- file.path(tempdir(), paste0("fm_unsupported2_", as.integer(Sys.time())))
  dir.create(klasor, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(klasor, recursive = TRUE, force = TRUE), add = TRUE)

  desteklenmeyen <- file.path(klasor, "sunum.ppt")
  writeLines("eski sunum", desteklenmeyen)

  env$SSO_ENABLED <- FALSE
  env$path_exists_relaxed <- function(p) file.exists(p)
  env$mergen_list_user_files <- function(uid) {
    df <- data.frame(path = desteklenmeyen, name = "sunum.ppt", stringsAsFactors = FALSE)
    attr(df, "source") <- "test"
    df
  }

  toast_sayisi <- 0L
  env$showToast <- function(...) { toast_sayisi <<- toast_sayisi + 1L; invisible(TRUE) }

  module_values <- new.env(parent = emptyenv())
  module_values$files <- env$fm_empty_files_df()
  module_values$file_contents <- list()
  module_values$files_in_context <- list()

  fake_session <- list(
    userData = new.env(parent = emptyenv()),
    sendCustomMessage = function(...) invisible(TRUE)
  )
  fake_session$userData$current_session_files <- list()

  refresh <- env$fm_create_refresh_from_user_folder(
    session = fake_session,
    ns = shiny::NS("fm"),
    module_values_provider = function() module_values,
    module_user_id_chr = function() "42",
    is_auth_ready = function() TRUE,
    ensure_session_registry = function() invisible(TRUE),
    attach_in_parent = function(...) invisible(TRUE),
    process_uploaded_file_callback = function(finfo) stop("parse yolu çağrılmamalı"),
    refresh_guard = env$fm_create_refresh_request_guard(),
    fm_debug = function(...) invisible(NULL)
  )

  # Üç ardışık "giriş" (yenileme): toast sayısı sıfır kalmalı, satır tek olmalı.
  invisible(utils::capture.output({
    refresh("page_open")
    refresh("manual")
    refresh("manual")
  }))

  testthat::expect_identical(toast_sayisi, 0L)
  testthat::expect_identical(nrow(module_values$files), 1L)
  testthat::expect_true(grepl("Desteklenmeyen dosya türü", module_values$files$Tur[1], fixed = TRUE))
})

testthat::test_that("kalıcı dosya envanteri tembel yükleme sözleşmesi statik olarak korunur", {
  module_txt <- .read_repo_text_unsupported("R/module_file_manager.R")
  nav_txt <- .read_repo_text_unsupported("R/server_observers_navigation.R")
  loading_js <- .read_repo_text_unsupported("www/js/app_loading.js")

  # Açılış tetikleri artık tarama başlatmaz; sayfa açılışı tembel taramayı
  # yükleme örtüsüyle bir tick erteleyen yardımcı üzerinden yapar.
  tablo_runtime_txt <- .read_repo_text_unsupported("R/helpers_file_manager_table_runtime.R")
  testthat::expect_true(grepl("persisted_scan_pending", module_txt, fixed = TRUE))
  testthat::expect_true(grepl("input$page_opened", module_txt, fixed = TRUE))
  testthat::expect_false(grepl('refresh_from_user_folder("initial")', module_txt, fixed = TRUE))
  testthat::expect_true(grepl(
    "fm_baslat_sayfa_acilis_taramasi(session, refresh_from_user_folder)",
    module_txt, fixed = TRUE
  ))
  testthat::expect_true(grepl('refresh_fn("page_open")', tablo_runtime_txt, fixed = TRUE))
  testthat::expect_true(grepl("mb-table-loading", tablo_runtime_txt, fixed = TRUE))
  testthat::expect_true(grepl("deferred = TRUE", module_txt, fixed = TRUE))

  # Navigasyon, Dosya Yönetimi açılışında page_opened olayını gönderir.
  testthat::expect_true(grepl("file_manager_module-page_opened", nav_txt, fixed = TRUE))

  # Açılış ekranı etiketi ertelenmiş envanteri dürüst anlatır.
  testthat::expect_true(grepl("Dosyalar gerektiğinde yüklenecek", loading_js, fixed = TRUE))
  testthat::expect_false(grepl("Dosyalar hazırlanıyor", loading_js, fixed = TRUE))
})

testthat::test_that("görsel galerisi tembel etkinleşme sözleşmesi statik olarak korunur", {
  gallery_txt <- .read_repo_text_unsupported("R/module_image_gallery.R")

  testthat::expect_true(grepl("gallery_activated <- reactiveVal(FALSE)", gallery_txt, fixed = TRUE))
  testthat::expect_true(grepl("gallery_activated(TRUE)", gallery_txt, fixed = TRUE))
  # Gizliyken tam galeri render'ı zorlayan eski satır geri gelmemeli.
  testthat::expect_false(grepl(
    'outputOptions(output, "gallery_content", suspendWhenHidden = FALSE)',
    gallery_txt,
    fixed = TRUE
  ))
})
