# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-run-prepare-behavior.R
# Açıklama: Bilge Yolaç bloklamayan çalıştırma hattının davranış sözleşmesi:
#           izole runtime düzeni, klasörün tamamının kopyalanmaması, yalnızca
#           gerekli girdilerin aktarılması, yalnızca değişen çıktıların geri
#           yazılması, yol kaçış korumaları, eşzamanlı doküman destek dizini
#           izolasyonu, stale hazırlık geri çağrısı koruması ve ana Shiny
#           sürecinin bloke olmaması.
#           Çevrimdışı ve deterministiktir; gerçek DB/LLM/CLI/tarayıcı yoktur.
# ==============================================================================

.cc_prepare_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  for (dosya in c(
    "config_claude_code.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_output_sync.R",
    "helpers_claude_code_runtime_resolver.R",
    "helpers_claude_code_runtime_workdir.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Test platformu Windows olmasa da izole runtime dalı sözleşme olarak
  # doğrulanır.
  env$is_problematic_windows_workdir <- function(path) TRUE

  env
}

.cc_prepare_source_dir <- function(dosya_sayisi = 8L) {
  kok <- withr::local_tempdir(.local_envir = parent.frame())

  for (i in seq_len(dosya_sayisi)) {
    writeLines("veri", file.path(kok, sprintf("kaynak%02d.txt", i)), useBytes = TRUE)
  }

  dir.create(file.path(kok, "alt"))
  writeLines("alt", file.path(kok, "alt", "altdosya.txt"), useBytes = TRUE)

  kok
}

.cc_read_prepare_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

# ------------------------------------------------------------------------------
# İZOLE RUNTIME DÜZENİ VE GİRDİ SEÇİMİ
# ------------------------------------------------------------------------------

test_that("büyük klasör sınırsız özyinelemeli file.copy ile kopyalanmaz", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(30L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "buyuk-klasor",
    prompt = "kaynak03.txt dosyasını incele",
    limits = list(auto_select_max_files = 3)
  )

  aktarilan <- list.files(sonuc$layout$input, recursive = TRUE)

  expect_true(isTRUE(sonuc$mirrored))
  expect_equal(aktarilan, "kaynak03.txt")
  expect_lt(length(aktarilan), 30L)
})

test_that("yalnızca gerekli girdi dosyaları runtime input klasörüne kopyalanır", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(6L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "gerekli-girdi",
    prompt = "alt/altdosya.txt içeriğini özetle"
  )

  aktarilan <- list.files(sonuc$layout$input, recursive = TRUE)

  expect_equal(aktarilan, "alt/altdosya.txt")
  expect_equal(sonuc$selection$selection_mode, "prompt")
})

test_that("prompt hiçbir dosyaya işaret etmediğinde otomatik seçim sınırlıdır", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(20L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "otomatik",
    prompt = "bu klasörü genel olarak degerlendir",
    limits = list(auto_select_max_files = 4, max_input_files = 40)
  )

  aktarilan <- list.files(sonuc$layout$input, recursive = TRUE)

  expect_equal(sonuc$selection$selection_mode, "auto")
  expect_equal(length(aktarilan), 4L)
})

test_that("takip eden çağrı kaynak klasörü yeniden aynalamaz", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(5L)

  ilk <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "ilk",
    prompt = "kaynak01.txt incele"
  )

  # Takip eden soruda kaynak klasöre yeni dosyalar eklenir; yalnızca gerekli
  # olan tazelenmelidir.
  for (i in 1:10) {
    writeLines("yeni", file.path(kaynak, sprintf("sonradan%02d.txt", i)), useBytes = TRUE)
  }

  ikinci <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "ikinci",
    existing_runtime_workdir = ilk$runtime_workdir,
    prompt = "kaynak02.txt incele"
  )

  aktarilan <- list.files(ikinci$layout$input, recursive = TRUE)

  expect_true(isTRUE(ikinci$reused))
  expect_identical(ikinci$runtime_workdir, ilk$runtime_workdir)
  expect_true("kaynak02.txt" %in% aktarilan)
  expect_false(any(grepl("^sonradan", aktarilan)))
})

test_that("küçük yerel klasörlerde mevcut davranış korunur", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(3L)

  # Problemli olmayan (yerel, ASCII) yol: izole runtime alanı kurulmaz,
  # Claude doğrudan kaynak dizinde çalışır ve hiçbir kopyalama yapılmaz.
  env$is_problematic_windows_workdir <- function(path) FALSE

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "yerel",
    prompt = "kaynak01.txt incele"
  )

  expect_false(isTRUE(sonuc$mirrored))
  expect_null(sonuc$layout)
  expect_equal(sonuc$runtime_workdir, sonuc$source_workdir)
  expect_false(dir.exists(file.path(kaynak, "input")))
  expect_false(dir.exists(file.path(kaynak, "output")))
})

test_that("Türkçe/Unicode dosya adları girdi aktarımında korunur", {
  env <- .cc_prepare_env()
  kaynak <- withr::local_tempdir()

  turkce <- "Türkçe_çalışma_özeti_İstanbul.txt"
  writeLines("veri", file.path(kaynak, turkce), useBytes = TRUE)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "unicode",
    prompt = paste(turkce, "dosyasını incele")
  )

  aktarilan <- list.files(sonuc$layout$input, recursive = TRUE)

  expect_equal(aktarilan, turkce)
  expect_true(file.exists(file.path(sonuc$layout$input, turkce)))
})

test_that("doküman seçimi sayı ve boyut sınırlarını uygular", {
  env <- .cc_prepare_env()
  kaynak <- withr::local_tempdir()

  dokumanlar <- character(0)
  for (i in 1:6) {
    yol <- file.path(kaynak, sprintf("rapor%02d.pdf", i))
    writeLines("pdf", yol, useBytes = TRUE)
    dokumanlar <- c(dokumanlar, yol)
  }

  buyuk <- file.path(kaynak, "devasa.pdf")
  writeLines(strrep("x", 5000), buyuk, useBytes = TRUE)

  sinirli <- env$cc_select_documents_for_request(
    prompt = "klasördeki dokümanları özetle",
    documents = c(dokumanlar, buyuk),
    limits = list(max_documents = 2, max_document_bytes = 1000)
  )

  expect_length(sinirli$files, 2L)
  expect_true(isTRUE(sinirli$truncated))
  expect_false(buyuk %in% sinirli$files)

  # Promptta adı geçen doküman önceliklidir.
  adresli <- env$cc_select_documents_for_request(
    prompt = "rapor05.pdf dosyasını özetle",
    documents = dokumanlar
  )

  expect_equal(basename(adresli$files), "rapor05.pdf")
  expect_equal(adresli$selection_mode, "prompt")
})

test_that("preflight büyük klasörü sınırlı mod olarak bildirir", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(12L)

  tarama <- env$cc_scan_source_workdir(kaynak)
  karar <- env$cc_evaluate_workdir_preflight(tarama, limits = list(preflight_max_files = 3))

  expect_true(isTRUE(karar$limited))
  expect_false(isTRUE(karar$blocked))
  expect_true(grepl("güvenli çalışma sınırlarını", karar$message, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# ÇIKTI ANLIK GÖRÜNTÜSÜ VE GERİ AKTARIM
# ------------------------------------------------------------------------------

test_that("yalnızca yeni veya değişen çıktı dosyaları geri aktarılır", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(3L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "cikti",
    prompt = "kaynak01.txt incele"
  )

  writeLines("rapor", file.path(sonuc$layout$output, "rapor.txt"), useBytes = TRUE)

  plan <- env$cc_plan_output_sync(
    changed_files = file.path(sonuc$layout$output, "rapor.txt"),
    layout = sonuc$layout,
    source_workdir = kaynak
  )

  sonuclar <- env$cc_apply_output_sync_plan(plan)

  expect_length(plan$items, 1L)
  expect_true(all(vapply(sonuclar, function(x) isTRUE(x$success), logical(1))))
  expect_true(file.exists(file.path(kaynak, "rapor.txt")))

  # Kaynak klasördeki mevcut dosyalar bozulmaz, runtime klasörünün tamamı
  # geri kopyalanmaz.
  expect_false(dir.exists(file.path(kaynak, "input")))
  expect_false(dir.exists(file.path(kaynak, "metadata")))
})

test_that("runtime input düzenlemeleri aktarılır, dahili alanlar aktarılmaz", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(2L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "izole",
    prompt = "kaynak01.txt incele"
  )

  writeLines("meta", file.path(sonuc$layout$metadata, "meta.txt"), useBytes = TRUE)
  writeLines("destek", file.path(sonuc$layout$document_support, "destek.txt"), useBytes = TRUE)

  plan <- env$cc_plan_output_sync(
    changed_files = c(
      file.path(sonuc$layout$metadata, "meta.txt"),
      file.path(sonuc$layout$document_support, "destek.txt"),
      file.path(sonuc$layout$input, "kaynak01.txt")
    ),
    layout = sonuc$layout,
    source_workdir = kaynak
  )

  expect_length(plan$items, 1L)
  expect_identical(plan$items[[1]]$relative_path, "kaynak01.txt")
  expect_equal(length(plan$skipped), 2L)
})

test_that("yol kaçışı ve izinli kök dışı hedefler reddedilir", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(1L)
  disari <- withr::local_tempdir()

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "kacak",
    prompt = "kaynak01.txt incele"
  )

  writeLines("sizinti", file.path(disari, "disarida.txt"), useBytes = TRUE)

  plan <- env$cc_plan_output_sync(
    changed_files = c(
      file.path(sonuc$layout$output, "..", "..", "yukari.txt"),
      file.path(disari, "disarida.txt")
    ),
    layout = sonuc$layout,
    source_workdir = kaynak
  )

  expect_length(plan$items, 0L)
  expect_false(file.exists(file.path(kaynak, "disarida.txt")))
})

test_that("çıktı boyut sınırını aşan dosya aktarılmaz", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(1L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "boyut",
    prompt = "kaynak01.txt incele"
  )

  buyuk <- file.path(sonuc$layout$output, "buyuk.txt")
  writeLines(strrep("x", 4000), buyuk, useBytes = TRUE)

  plan <- env$cc_plan_output_sync(
    changed_files = buyuk,
    layout = sonuc$layout,
    source_workdir = kaynak,
    limits = list(max_output_file_bytes = 100)
  )

  expect_length(plan$items, 0L)
})

test_that("tek dosyanın başarısız aktarımı diğerlerini engellemez", {
  env <- .cc_prepare_env()
  kaynak <- .cc_prepare_source_dir(1L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "kismi",
    prompt = "kaynak01.txt incele"
  )

  iyi <- file.path(sonuc$layout$output, "iyi.txt")
  writeLines("iyi", iyi, useBytes = TRUE)

  plan <- list(
    items = list(
      list(
        source_path = file.path(sonuc$layout$output, "olmayan.txt"),
        dest_path = file.path(kaynak, "olmayan.txt"),
        relative_path = "olmayan.txt",
        size = 0
      ),
      list(
        source_path = iyi,
        dest_path = file.path(kaynak, "iyi.txt"),
        relative_path = "iyi.txt",
        size = 4
      )
    ),
    skipped = character(0),
    total_bytes = 4
  )

  sonuclar <- env$cc_apply_output_sync_plan(plan)

  expect_length(sonuclar, 2L)
  expect_false(isTRUE(sonuclar[[1]]$success))
  expect_true(isTRUE(sonuclar[[2]]$success))
  expect_true(file.exists(file.path(kaynak, "iyi.txt")))
})

test_that("çıktı anlık görüntüsü yalnızca onaylı yazılabilir alanı tarar", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .cc_prepare_env()

  source(
    file.path(repo_root, "R", "helpers_claude_code_workdir_scan.R"),
    encoding = "UTF-8",
    local = env
  )

  kaynak <- .cc_prepare_source_dir(2L)

  sonuc <- env$prepare_claude_runtime_workdir(
    kaynak,
    user_id = 7L,
    runtime_token = "snapshot",
    prompt = "kaynak01.txt incele"
  )

  writeLines("cikti", file.path(sonuc$layout$output, "cikti.txt"), useBytes = TRUE)
  writeLines("meta", file.path(sonuc$layout$metadata, "meta.txt"), useBytes = TRUE)

  anlik <- env$cc_snapshot_run_output_area(
    runtime_workdir = sonuc$runtime_workdir,
    mirrored = TRUE
  )

  yollar <- names(anlik)

  expect_true(any(grepl("/output/cikti.txt$", yollar, perl = TRUE)))
  expect_false(any(grepl("/metadata/", yollar, fixed = TRUE)))
  expect_true(any(grepl("/input/kaynak01.txt$", yollar, perl = TRUE)))
})

# ------------------------------------------------------------------------------
# EŞZAMANLI DOKÜMAN DESTEK DİZİNİ İZOLASYONU
# ------------------------------------------------------------------------------

test_that("eşzamanlı doküman çalıştırmaları ayrı destek dizini kullanır", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$get_claude_code_model_capabilities <- function() list(binary_doc_extensions = "pdf")
  env$resolve_app_root <- function() tempdir()
  env$safe_read_excel_table <- function(...) NULL

  source(
    file.path(repo_root, "R", "helpers_claude_code_document_extractors.R"),
    encoding = "UTF-8",
    local = env
  )

  taban <- withr::local_tempdir()

  birinci <- env$get_claude_code_document_support_dir(
    user_id = 5L, request_id = "run-a", base_dir = taban
  )
  writeLines("a", file.path(birinci, "cikarim.txt"), useBytes = TRUE)

  ikinci <- env$get_claude_code_document_support_dir(
    user_id = 5L, request_id = "run-b", base_dir = taban
  )

  expect_false(identical(birinci, ikinci))

  # İkinci çalıştırma birincinin çıkarımlarını SİLMEMELİDİR.
  expect_true(file.exists(file.path(birinci, "cikarim.txt")))
  expect_true(dir.exists(ikinci))
})

test_that("doküman aday sınırı uzantı filtresinden sonra uygulanır", {
  env <- .cc_prepare_env()
  kaynak <- withr::local_tempdir()
  for (i in seq_len(250L)) writeLines("metin", file.path(kaynak, sprintf("a%03d.txt", i)))
  rapor <- file.path(kaynak, "z-rapor.pdf")
  writeLines("pdf", rapor)

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_document_extractors.R"),
    encoding = "UTF-8", local = env
  )
  bulunan <- env$list_claude_code_binary_documents(kaynak, extensions = "pdf", max_files = 1L)
  expect_identical(normalizePath(bulunan), normalizePath(rapor))
})



test_that("eskiyen doküman destek dizinleri yaşa göre temizlenir", {
  env <- .cc_prepare_env()

  kok <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", "9911"),
    "document_support"
  )

  eski <- file.path(kok, "eski")
  yeni <- file.path(kok, "yeni")
  dir.create(eski, recursive = TRUE, showWarnings = FALSE)
  dir.create(yeni, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dirname(kok), recursive = TRUE, force = TRUE), add = TRUE)

  Sys.setFileTime(eski, Sys.time() - 7200)

  env$cc_cleanup_stale_document_support_dirs(
    user_id = 9911L,
    max_age_sec = 3600,
    keep_paths = yeni
  )

  expect_false(dir.exists(eski))
  expect_true(dir.exists(yeni))
})

test_that("aktif runtime klasörü yaş temizliğinden korunur", {
  env <- .cc_prepare_env()

  kullanici_kok <- env$cc_runtime_user_dir(9912L)
  aktif <- file.path(kullanici_kok, "run_aktif")
  eski <- file.path(kullanici_kok, "run_eski")
  dir.create(aktif, recursive = TRUE, showWarnings = FALSE)
  dir.create(eski, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kullanici_kok, recursive = TRUE, force = TRUE), add = TRUE)

  Sys.setFileTime(aktif, Sys.time() - 7200)
  Sys.setFileTime(eski, Sys.time() - 7200)

  env$cc_cleanup_stale_runtime_dirs(
    user_id = 9912L,
    max_age_sec = 3600,
    keep_paths = aktif
  )

  expect_true(dir.exists(aktif))
  expect_false(dir.exists(eski))
})

# ------------------------------------------------------------------------------
# ASYNC YAŞAM DÖNGÜSÜ VE STALE CALLBACK KORUMASI
# ------------------------------------------------------------------------------

.cc_dispatch_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$cc_log_info <- function(...) invisible(NULL)
  env$cc_log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$CLAUDE_CODE_LIMIT_MESSAGE <- "sinir"
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) default_value

  source(
    file.path(repo_root, "R", "helpers_claude_code_run_lifecycle.R"),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_run_dispatch.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

test_that("başarısız çıktı aktarımları başarılı sonuç sayılmaz", {
  env <- .cc_dispatch_env()
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_run_completion.R"),
    encoding = "UTF-8", local = env
  )
  outputs <- list(sync_results = list(
    list(success = TRUE, dest_path = "iyi.txt"),
    list(success = FALSE, dest_path = "yazilamadi.txt", error = "izin yok")
  ))
  expect_identical(length(env$cc_output_sync_failures(outputs)), 1L)
  completion <- .cc_read_prepare_text("R/helpers_claude_code_run_completion.R")
  expect_true(grepl("cc_report_output_sync_failure\\(ctx, outputs\\)", completion, perl = TRUE))
})



.cc_fake_ctx <- function(env, rv, kayit) {
  list(
    session = list(
      token = "tok",
      sendCustomMessage = function(type, message) {
        kayit$mesajlar <- c(kayit$mesajlar, list(list(type = type, message = message)))
        invisible(TRUE)
      }
    ),
    ns = function(x) paste0("cc-", x),
    rv = rv,
    run_request_id = "req-1",
    finalize_streaming = function(durum_metin, durum_ikon, durum_renk, sure = NULL, request_id = NULL) {
      kayit$finalize <- c(kayit$finalize, list(list(durum = durum_metin, request_id = request_id)))
      rv$is_running <- FALSE
      rv$active_request_id <- NULL
      invisible(TRUE)
    }
  )
}

test_that("hazırlık hatası tutarlı yaşam döngüsü durumunu geri yükler", {
  env <- .cc_dispatch_env()
  kayit <- new.env(parent = emptyenv())
  kayit$mesajlar <- list()
  kayit$finalize <- list()

  rv <- new.env(parent = emptyenv())
  rv$is_running <- TRUE
  rv$active_request_id <- "req-1"

  ctx <- .cc_fake_ctx(env, rv, kayit)

  sonuc <- env$cc_fail_run_preparation(ctx, "Çalışma alanı hazırlanamadı: disk hatası")

  expect_true(isTRUE(sonuc))
  expect_false(isTRUE(rv$is_running))
  expect_null(rv$active_request_id)
  expect_equal(kayit$finalize[[1]]$durum, "Hata")
  expect_equal(kayit$finalize[[1]]$request_id, "req-1")
  expect_true(any(vapply(
    kayit$mesajlar,
    function(m) identical(m$type, "cc-add-message"),
    logical(1)
  )))
})

test_that("stale hazırlık geri çağrısı yeni çalışmayı bozmaz", {
  env <- .cc_dispatch_env()
  kayit <- new.env(parent = emptyenv())
  kayit$mesajlar <- list()
  kayit$finalize <- list()

  rv <- new.env(parent = emptyenv())
  rv$is_running <- TRUE
  # Yeni bir çalışma zaten aktif: eski request'in geri çağrısı gelirse
  # durumu temizlememelidir.
  rv$active_request_id <- "req-2"

  ctx <- .cc_fake_ctx(env, rv, kayit)

  sonuc <- env$cc_fail_run_preparation(ctx, "eski hata")

  expect_false(isTRUE(sonuc))
  expect_true(isTRUE(rv$is_running))
  expect_equal(rv$active_request_id, "req-2")
  expect_length(kayit$finalize, 0L)
  expect_length(kayit$mesajlar, 0L)
})

test_that("hazırlık sırasında durdurma geç gelen callback ile yeniden başlamaz", {
  env <- .cc_dispatch_env()
  kayit <- new.env(parent = emptyenv())
  kayit$mesajlar <- list()
  kayit$finalize <- list()

  rv <- new.env(parent = emptyenv())
  rv$is_running <- TRUE
  rv$active_request_id <- "req-1"

  ctx <- .cc_fake_ctx(env, rv, kayit)

  # Kullanıcı Durdur'a bastı: aktif request temizlendi.
  rv$is_running <- FALSE
  rv$active_request_id <- NULL

  expect_false(env$cc_is_active_run(rv, "req-1"))

  # Geç gelen hazırlık geri çağrısı hiçbir şey yapmamalıdır.
  expect_false(isTRUE(env$cc_fail_run_preparation(ctx, "geç hata")))
  expect_length(kayit$finalize, 0L)
})

test_that("çalıştırma aşamaları hazırlık ile model çalıştırmayı ayırır", {
  env <- .cc_dispatch_env()

  asamalar <- env$claude_code_run_stages

  for (anahtar in c("hazirlaniyor", "taraniyor", "girdi", "dokuman", "model",
                    "calisiyor", "cikti", "aktarim", "tamamlandi",
                    "durduruldu", "hata", "zaman_asimi")) {
    expect_true(!is.null(asamalar[[anahtar]]), info = anahtar)
    expect_true(nzchar(asamalar[[anahtar]]$metin), info = anahtar)
  }

  expect_equal(asamalar$hazirlaniyor$metin, "Hazırlanıyor")
  expect_equal(asamalar$calisiyor$metin, "Çalışıyor")

  kayit <- new.env(parent = emptyenv())
  kayit$mesajlar <- list()

  session <- list(sendCustomMessage = function(type, message) {
    kayit$mesajlar <- c(kayit$mesajlar, list(message))
    invisible(TRUE)
  })

  env$cc_send_run_stage(session, function(x) x, "taraniyor")

  expect_equal(kayit$mesajlar[[1]]$status, "Dosyalar taranıyor")
})

# ------------------------------------------------------------------------------
# ANA SÜREÇ BLOKLANMAMA SÖZLEŞMESİ
# ------------------------------------------------------------------------------

test_that("hazırlık gönderimi ana süreçte ağır işi çalıştırmaz", {
  env <- .cc_dispatch_env()

  yakalanan <- new.env(parent = emptyenv())
  yakalanan$task_fn <- NULL
  yakalanan$mode <- NULL
  yakalanan$calisti <- FALSE

  env$cc_build_run_prepare_request <- function(...) list(request_id = "req-1")
  env$cc_run_prepare_worker_globals <- function() list()
  env$cc_prepare_run_workspace <- function(request) {
    # Ağır iş simülasyonu: worker tarafında çalışır, ana süreçte ASLA.
    Sys.sleep(1.5)
    yakalanan$calisti <- TRUE
    list(ok = TRUE)
  }

  env$tracked_future_promise <- function(task_fn, task_type = "generic",
                                         session_token = NULL,
                                         dependency_mode = "auto",
                                         globals = NULL, packages = NULL, ...) {
    yakalanan$task_fn <- task_fn
    yakalanan$mode <- dependency_mode
    promises::promise(function(resolve, reject) resolve(NULL))
  }

  rv <- new.env(parent = emptyenv())
  rv$is_running <- TRUE
  rv$active_request_id <- "req-1"
  rv$active_runtime_source <- NULL
  rv$active_runtime_workdir <- NULL

  ctx <- list(
    session = list(token = "tok", sendCustomMessage = function(...) invisible(TRUE)),
    ns = function(x) x,
    rv = rv,
    run_request_id = "req-1",
    user_id = 1L,
    workdir = tempdir(),
    prompt = "test",
    explicit_files = character(0),
    finalize_streaming = function(...) invisible(TRUE)
  )

  baslangic <- Sys.time()
  env$cc_dispatch_run_preparation(ctx)
  gecen <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

  # Ana süreç ağır işi beklemeden döner; diğer oturumlar bloke olmaz.
  expect_lt(gecen, 1)
  expect_false(isTRUE(yakalanan$calisti))

  # Bağımlılık taraması gönderim anında değil, süreç başına bir kez yapılır.
  expect_equal(yakalanan$mode, "explicit")
  expect_true(is.function(yakalanan$task_fn))
})

test_that("bir oturumun büyük klasör hazırlığı ikinci oturumu bloke etmez", {
  env <- .cc_dispatch_env()
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) {
    if (identical(name, "prepare_timeout_sec")) 0.05 else default_value
  }

  ikinci_oturum_yaniti <- NULL

  env$cc_build_run_prepare_request <- function(...) list(request_id = "req-1")
  env$cc_run_prepare_worker_globals <- function() list()

  # Birinci oturumun hazırlığı worker'a gider ve HENÜZ çözülmez.
  env$tracked_future_promise <- function(task_fn, ...) {
    promises::promise(function(resolve, reject) {
      # Kasıtlı olarak çözülmeyen promise: worker hâlâ çalışıyor.
      invisible(NULL)
    })
  }

  rv <- new.env(parent = emptyenv())
  rv$is_running <- TRUE
  rv$active_request_id <- "req-1"
  rv$active_runtime_source <- NULL
  rv$active_runtime_workdir <- NULL

  ctx <- list(
    session = list(token = "tok1", sendCustomMessage = function(...) invisible(TRUE)),
    ns = function(x) x,
    rv = rv,
    run_request_id = "req-1",
    user_id = 1L,
    workdir = tempdir(),
    prompt = "buyuk klasoru incele",
    explicit_files = character(0),
    finalize_streaming = function(...) invisible(TRUE)
  )

  env$cc_dispatch_run_preparation(ctx)

  # İkinci oturum (bağımsız) basit bir reaktif işi hemen tamamlayabilmelidir.
  baslangic <- Sys.time()
  shiny::testServer(function(input, output, session) {
    sayac <- shiny::reactiveVal(0L)
    shiny::observeEvent(input$tik, sayac(sayac() + 1L))
    output$deger <- shiny::renderText(as.character(sayac()))
  }, {
    session$setInputs(tik = 1)
    ikinci_oturum_yaniti <<- output$deger
  })
  gecen <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

  expect_equal(ikinci_oturum_yaniti, "1")
  expect_lt(gecen, 5)

  # Deadline ana olay döngüsünde uygulanır; çözülmeyen hazırlık aktif kalmaz.
  expect_false(isTRUE(rv$is_running))
  expect_null(rv$active_request_id)
})

test_that("hazırlık ve çıktı işleri açık bağımlılık modu ile gönderilir", {
  dispatch <- .cc_read_prepare_text("R/helpers_claude_code_run_dispatch.R")
  completion <- .cc_read_prepare_text("R/helpers_claude_code_run_completion.R")
  modul <- .cc_read_prepare_text("R/module_claude_code.R")

  for (metin in list(dispatch, completion)) {
    expect_true(grepl("tracked_future_promise\\(", metin, perl = TRUE))
    expect_true(grepl('dependency_mode\\s*=\\s*"explicit"', metin, perl = TRUE))
  }

  # Ana observer artık pahalı dosya sistemi işini kendisi yapmaz.
  expect_false(grepl("prepare_claude_runtime_workdir\\(", modul, perl = TRUE))
  expect_false(grepl("prepare_claude_code_document_context\\(", modul, perl = TRUE))
  expect_false(grepl("snapshot_claude_code_workdir_files\\(", modul, perl = TRUE))
  expect_true(grepl("cc_dispatch_run_preparation\\(", modul, perl = TRUE))
})

test_that("bloklayan bekleme döngüleri ana süreç dosyalarında kalmaz", {
  for (yol in c(
    "R/module_claude_code.R",
    "R/module_claude_code_stream_poll.R",
    "R/helpers_claude_code_run_dispatch.R",
    "R/helpers_claude_code_run_completion.R"
  )) {
    metin <- .cc_read_prepare_text(yol)

    expect_false(
      grepl("Sys.sleep\\(", metin, perl = TRUE),
      info = sprintf("%s ana Shiny sürecinde bloklayan bekleme içermemelidir.", yol)
    )
  }
})
