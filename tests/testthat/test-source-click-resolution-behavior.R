# ==============================================================================
# Dosya Yolu: tests/testthat/test-source-click-resolution-behavior.R
# Açıklama: Kaynak tıklama çözümlemesinin (R/helpers_preview.R +
#           R/utils_file_index.R) DAVRANIŞ ve BAŞARIM sözleşmesi:
#           - Bilinen kaynak, ilgisiz belge sayısından bağımsız olarak dizin
#             TARANMADAN belirleyici göreli adayla açılır (PDF -> aynı gövdeli
#             Word dahil).
#           - Gerçek geri dönüş yolunda bir tıklama bir tabanı EN FAZLA BİR kez
#             tarar; tüm arama aşamaları aynı indeksi paylaşır.
#           - Kısmi/başarısız tarama geri çekilmesi taramanın BİTİŞİNDEN ölçülür.
#           - Yol geçişi, mutlak yol, ADS, kök dışı indeks isabeti, kişisel kova
#             ve model_bases kapsamı güvenlik sınırları korunur.
#           Gerçek geçici dizinler kullanılır; tarayıcı sayaçlı sarmalayıcıyla
#           (ya da çağrılırsa hata veren saplamayla) izlenir. Ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.scr_env <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  for (f in c("R/utils_common.R", "R/utils_path_helpers.R", "R/helpers_files_path.R",
              "R/utils_file_index.R", "R/helpers_preview.R")) {
    source(file.path(kok, f), encoding = "UTF-8", local = env)
  }
  sessiz <- function(...) invisible(NULL)
  env$log_info <- sessiz
  env$log_debug <- sessiz
  env$log_warn <- sessiz
  env$log_error <- sessiz
  env$.toasts <- character(0)
  env$showToast <- function(session, msg, ...) {
    env$.toasts <- c(env$.toasts, msg)
    invisible(NULL)
  }
  env$.opened <- NULL
  env$openAnyPreview <- function(file_info, session, filePreview) {
    env$.opened <- file_info
    invisible(TRUE)
  }
  env$.resolve_calls <- list()
  env$.bucket <- list()
  env$resolve_uploaded_file <- function(name, user_id = NULL, ...) {
    env$.resolve_calls[[length(env$.resolve_calls) + 1L]] <- list(name = name, user_id = user_id)
    env$.bucket[[paste0(user_id, "|", name)]]
  }
  # Sayaçlı tarayıcı: `.build_basename_index()` env içinde tanımlı olduğu için
  # bu sarmalayıcıyı görür.
  gercek <- env$.file_index_scan_bounded
  env$.scan_calls <- character(0)
  env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
    env$.scan_calls <- c(env$.scan_calls, base_path)
    gercek(base_path, pattern, ...)
  }
  env
}

# Tarayıcı ÇAĞRILIRSA test başarısız olur: belirleyici yolun kanıtı.
.scr_forbid_scan <- function(env) {
  env$.file_index_scan_bounded <- function(...) stop("tarama bu yolda çağrılmamalı")
  invisible(env)
}

.scr_touch <- function(...) {
  yol <- file.path(...)
  dir.create(dirname(yol), recursive = TRUE, showWarnings = FALSE)
  writeLines("x", yol)
  yol
}

# ~1000 belgelik gerçek bir modeli temsil eden ilgisiz belgeler.
.scr_noise <- function(base, n_dirs = 20L, per_dir = 50L) {
  for (d in seq_len(n_dirs)) {
    klasor <- file.path(base, sprintf("Arsiv_%02d", d))
    dir.create(klasor, recursive = TRUE, showWarnings = FALSE)
    for (i in seq_len(per_dir)) writeLines("x", file.path(klasor, sprintf("Belge_%03d.pdf", i)))
  }
  invisible(base)
}

.scr_click <- function(env, hint, bases, scope = NULL, uid = 7L) {
  env$.opened <- NULL
  ev <- if (is.list(hint)) hint else list(filename = hint, nonce = 1)
  if (!is.null(scope)) ev$scope <- scope
  se <- new.env()
  se$userData <- new.env()
  se$userData$user_id <- uid
  api <- list(
    local_models = c(M = "m1"),
    local_model_paths = stats::setNames(as.list(bases), paste0("m", seq_along(bases)))
  )
  env$handle_source_file_click(ev, list(model_selection = "m1"), api, se, filePreview = NULL)
  env$.opened
}

.scr_same <- function(a, b) {
  identical(normalizePath(a, winslash = "/", mustWork = TRUE),
            normalizePath(b, winslash = "/", mustWork = TRUE))
}

# ------------------------------------------------------------------------------
# Belirleyici hızlı yol: tarama YOK
# ------------------------------------------------------------------------------

test_that("tam kaynak yolu belirleyici adayla açılır; ilgisiz belgeler taranmaz", {
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_noise(base)
  hedef <- .scr_touch(base, "rapor.pdf")

  acilan <- .scr_click(env, "rapor.pdf", base)
  expect_true(.scr_same(acilan$datapath, hedef))
  # İndeks hiç kurulmadı: çözüm dizin numaralandırmasına dokunmadı.
  expect_null(env$.file_index_peek(base))
})

test_that("A&&B&&C.pdf ipucu iç içe klasör ve düz '&&' adı olarak taramasız çözülür", {
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_noise(base, n_dirs = 5L)
  ic_ice <- .scr_touch(base, "Kalite", "Prosedurler", "Talimat.pdf")
  expect_true(.scr_same(.scr_click(env, "Kalite&&Prosedurler&&Talimat.pdf", base)$datapath, ic_ice))

  base2 <- withr::local_tempdir(pattern = "scr-duz-")
  duz <- .scr_touch(base2, "Kalite&&Prosedurler&&Talimat.pdf")
  expect_true(.scr_same(.scr_click(env, "Kalite&&Prosedurler&&Talimat.pdf", base2)$datapath, duz))
})

test_that("PDF atfı aynı gövdeli Word belgesine TARAMADAN çözülür (üretim senaryosu)", {
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_noise(base)
  word <- .scr_touch(base, "Surec", "Alt Surec", "Is Akisi.docx")
  expect_true(.scr_same(.scr_click(env, "Surec&&Alt Surec&&Is Akisi.pdf", base)$datapath, word))

  base2 <- withr::local_tempdir(pattern = "scr-duz-")
  duz_word <- .scr_touch(base2, "Surec&&Alt Surec&&Is Akisi.docx")
  expect_true(.scr_same(.scr_click(env, "Surec&&Alt Surec&&Is Akisi.pdf", base2)$datapath, duz_word))
})

test_that("Word eşdeğerleri docx > docm > doc önceliğiyle; tam PDF her zaman önce", {
  env <- .scr_forbid_scan(.scr_env())

  base <- withr::local_tempdir(pattern = "scr-")
  docm <- .scr_touch(base, "A", "B", "C.docm")
  expect_true(.scr_same(.scr_click(env, "A&&B&&C.pdf", base)$datapath, docm))

  base_doc <- withr::local_tempdir(pattern = "scr-doc-")
  doc <- .scr_touch(base_doc, "A", "B", "C.doc")
  expect_true(.scr_same(.scr_click(env, "A&&B&&C.pdf", base_doc)$datapath, doc))

  .scr_touch(base_doc, "A", "B", "C.docx")
  expect_true(.scr_same(.scr_click(env, "A&&B&&C.pdf", base_doc)$datapath,
                        file.path(base_doc, "A", "B", "C.docx")))

  pdf <- .scr_touch(base_doc, "A", "B", "C.pdf")
  expect_true(.scr_same(.scr_click(env, "A&&B&&C.pdf", base_doc)$datapath, pdf))
})

test_that("Word eşdeğeri yalnızca PDF atfı için uygulanır (tür genişletilmez)", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_touch(base, "A", "B", "C.docx")

  expect_null(.scr_click(env, "A&&B&&C.xlsx", base))
  expect_true(any(grepl("Dosya bulunamadı", env$.toasts, fixed = TRUE)))
})

test_that("aynı basename farklı klasörlerde: ipucu doğru klasörü taramasız seçer", {
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-")
  ist <- .scr_touch(base, "istanbul", "rapor.pdf")
  ank <- .scr_touch(base, "ankara", "rapor.pdf")

  expect_true(.scr_same(.scr_click(env, "ankara&&rapor.pdf", base)$datapath, ank))
  expect_true(.scr_same(.scr_click(env, "istanbul&&rapor.pdf", base)$datapath, ist))
})

test_that("Türkçe klasör ve dosya adları taramasız çözülür (PDF -> Word dahil)", {
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-tr-")
  word <- .scr_touch(base, "Süreç Yönetimi", "İş Akışı", "Çalışma Talimatı.docx")
  acilan <- .scr_click(env, "Süreç Yönetimi&&İş Akışı&&Çalışma Talimatı.pdf", base)
  expect_true(.scr_same(acilan$datapath, word))
  expect_identical(enc2utf8(basename(acilan$datapath)), enc2utf8("Çalışma Talimatı.docx"))
})

test_that("belirleyici isabet başka bir tabanın taramasını tetiklemez", {
  env <- .scr_forbid_scan(.scr_env())
  bos <- withr::local_tempdir(pattern = "scr-bos-")
  .scr_noise(bos, n_dirs = 3L)
  dolu <- withr::local_tempdir(pattern = "scr-dolu-")
  hedef <- .scr_touch(dolu, "A", "B", "C.docx")

  expect_true(.scr_same(.scr_click(env, "A&&B&&C.pdf", c(bos, dolu))$datapath, hedef))
})

# ------------------------------------------------------------------------------
# Gerçek geri dönüş: taban başına EN FAZLA BİR tarama
# ------------------------------------------------------------------------------

test_that("alt klasördeki düz '&&' adı tek taramayla bulunur; ikinci tıklama taramaz", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_touch(base, "Diger", "prosedur.pdf")                      # yanıltıcı aday
  hedef <- .scr_touch(base, "Arsiv", "Grup&&Kalite&&prosedur.pdf")

  expect_true(.scr_same(.scr_click(env, "Grup&&Kalite&&prosedur.pdf", base)$datapath, hedef))
  expect_length(env$.scan_calls, 1L)

  expect_true(.scr_same(.scr_click(env, "Grup&&Kalite&&prosedur.pdf", base)$datapath, hedef))
  expect_length(env$.scan_calls, 1L)
})

test_that("bulunamayan kaynak: taban başına tek tarama, kullanıcıya bildirim", {
  env <- .scr_env()
  b1 <- withr::local_tempdir(pattern = "scr-b1-")
  b2 <- withr::local_tempdir(pattern = "scr-b2-")
  .scr_noise(b1, n_dirs = 3L)
  .scr_noise(b2, n_dirs = 3L)

  expect_null(.scr_click(env, "Yok&&Olmayan&&Belge.pdf", c(b1, b2), scope = "model_bases"))
  expect_true(any(grepl("Dosya bulunamadı", env$.toasts, fixed = TRUE)))
  expect_identical(as.integer(table(env$.scan_calls)), c(1L, 1L))

  # Tam tarama TTL boyunca yetkilidir: aynı eksik kaynağa tekrar tıklama taramaz.
  expect_null(.scr_click(env, "Yok&&Olmayan&&Belge.pdf", c(b1, b2), scope = "model_bases"))
  expect_length(env$.scan_calls, 2L)
})

test_that("uzun süren KISMİ tarama aynı tıklamada yeniden başlatılmaz", {
  env <- .scr_env()
  env$FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 1
  # Tarama geri çekilme süresinden UZUN sürer. Damga başlangıç anı olsaydı her
  # arama aşaması taramayı yeniden başlatırdı (üretimdeki üç tarama).
  env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
    env$.scan_calls <- c(env$.scan_calls, base_path)
    Sys.sleep(1.3)
    structure(character(0), scan_partial = TRUE)
  }
  base <- withr::local_tempdir(pattern = "scr-")

  expect_null(.scr_click(env, "A&&B&&C.pdf", base))
  expect_length(env$.scan_calls, 1L)

  # Doğrudan arama zinciri de (dört aşama) tek indeksle yürür.
  rm(list = env$.file_index_key(base), envir = env$.FILE_INDEX_CACHE)
  expect_null(env$search_file_in_folder(base, "A&&B&&C"))
  expect_length(env$.scan_calls, 2L)
})

test_that("arama aşamaları geri çekilme olmasa bile TEK indeksi paylaşır", {
  env <- .scr_env()
  env$FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 0
  env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
    env$.scan_calls <- c(env$.scan_calls, base_path)
    structure(character(0), scan_partial = TRUE)
  }
  base <- withr::local_tempdir(pattern = "scr-")

  # Uzantısız '&&' ipucu dört aşamanın hepsini çalıştırır.
  expect_null(env$search_file_in_folder(base, "A&&B&&C"))
  expect_length(env$.scan_calls, 1L)
  expect_null(.scr_click(env, "A&&B&&C.pdf", base))
  expect_length(env$.scan_calls, 2L)
})

test_that("geri çekilme damgası taramanın BİTİŞ anıdır (kısmi ve başarısız)", {
  for (isaret in c("scan_partial", "scan_failed")) {
    env <- .scr_env()
    env$FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 1
    bitis <- NULL
    env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
      env$.scan_calls <- c(env$.scan_calls, base_path)
      Sys.sleep(1.2)
      bitis <<- Sys.time()
      do.call(structure, c(list(character(0)), stats::setNames(list(TRUE), isaret)))
    }
    base <- withr::local_tempdir(pattern = "scr-")

    ent <- env$.build_basename_index(base)
    expect_true(ent$scan_failed_at >= bitis, info = isaret)
    expect_identical(env$.file_index_entry_state(ent), "backoff", info = isaret)
    env$.build_basename_index(base)
    expect_length(env$.scan_calls, 1L)
  }
})

test_that("kısmi indeks sonraki tıklamada önbellekten TARAMASIZ kullanılır", {
  env <- .scr_env()
  env$FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 0
  gercek <- env$.file_index_scan_bounded
  env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
    out <- gercek(base_path, pattern, ...)
    structure(as.character(out), scan_partial = TRUE)
  }
  base <- withr::local_tempdir(pattern = "scr-")
  hedef <- .scr_touch(base, "Arsiv", "Grup&&Kalite&&prosedur.pdf")

  expect_true(.scr_same(.scr_click(env, "Grup&&Kalite&&prosedur.pdf", base)$datapath, hedef))
  expect_length(env$.scan_calls, 1L)
  expect_identical(env$.file_index_entry_state(env$.file_index_peek(base)), "stale")
  expect_true(.scr_same(.scr_click(env, "Grup&&Kalite&&prosedur.pdf", base)$datapath, hedef))
  expect_length(env$.scan_calls, 1L)
})

test_that("önbellekte isabet eden taban, diğer tabanın taramasını beklemez", {
  env <- .scr_env()
  b1 <- withr::local_tempdir(pattern = "scr-b1-")
  b2 <- withr::local_tempdir(pattern = "scr-b2-")
  hedef <- .scr_touch(b2, "Arsiv", "Grup&&Kalite&&prosedur.pdf")
  env$.build_basename_index(b2)
  onceki <- length(env$.scan_calls)

  expect_true(.scr_same(.scr_click(env, "Grup&&Kalite&&prosedur.pdf", c(b1, b2))$datapath, hedef))
  expect_length(env$.scan_calls, onceki)
})

# ------------------------------------------------------------------------------
# Güvenlik ve gizlilik sınırları
# ------------------------------------------------------------------------------

test_that("bozuk tıklama yükleri çökmeden reddedilir", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_touch(base, "rapor.pdf")
  for (yuk in list(list(filename = NULL), list(filename = NA_character_),
                   list(filename = 42), list(filename = list("rapor.pdf")),
                   list(filename = ""), list(filename = "&&&&"))) {
    expect_null(.scr_click(env, yuk, base))
  }
  expect_length(env$.scan_calls, 0L)
})

test_that("yol geçişi, mutlak yol ve ADS ipuçları kök dışını açamaz", {
  env <- .scr_env()
  ust <- withr::local_tempdir(pattern = "scr-ust-")
  base <- file.path(ust, "model")
  dir.create(base)
  gizli <- .scr_touch(ust, "gizli.pdf")
  gizli_abs <- normalizePath(gizli, winslash = "/")

  for (ipucu in c("..&&gizli.pdf", "alt&&..&&..&&gizli.pdf", "../gizli.pdf",
                  "..\\gizli.pdf", gizli_abs, paste0("C:&&", basename(gizli)),
                  "//sunucu/pay/gizli.pdf", "gizli.pdf:akis", "gizli\n.pdf")) {
    expect_null(.scr_click(env, ipucu, base), info = ipucu)
  }

  # Mutlak ipucu yalnızca KÖK İÇİNDEKİ aynı adlı dosyaya çözülebilir (yeni
  # ortam: önceki tıklamaların TTL boyunca taze boş indeksi kullanılmaz).
  icerideki <- .scr_touch(base, "gizli.pdf")
  acilan <- .scr_click(.scr_env(), gizli_abs, base)
  expect_true(.scr_same(acilan$datapath, icerideki))
})

test_that("indeks isabeti kök dışına çıkıyorsa açılmaz", {
  env <- .scr_env()
  ust <- withr::local_tempdir(pattern = "scr-ust-")
  base <- file.path(ust, "model")
  dir.create(base)
  disarida <- .scr_touch(ust, "disarida", "gizli.pdf")
  # Bozuk/ele geçirilmiş indeks saplaması: kök dışı yol döndürür.
  env$.file_index_scan_bounded <- function(base_path, pattern, ...) {
    env$.scan_calls <- c(env$.scan_calls, base_path)
    disarida
  }

  expect_null(.scr_click(env, "gizli.pdf", base))
  expect_length(env$.scan_calls, 1L)
})

test_that("sembolik bağlantı adayı kök dışına çözülürse reddedilir", {
  skip_on_os("windows")
  env <- .scr_env()
  ust <- withr::local_tempdir(pattern = "scr-ust-")
  base <- file.path(ust, "model")
  dir.create(base)
  disarida <- .scr_touch(ust, "gizli.pdf")
  skip_if_not(isTRUE(file.symlink(disarida, file.path(base, "baglanti.pdf"))))

  expect_null(.scr_click(env, "baglanti.pdf", base))
})

test_that("klasör, dosya adayı olarak açılmaz", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  dir.create(file.path(base, "A", "B", "C.pdf"), recursive = TRUE)

  expect_null(.scr_click(env, "A&&B&&C.pdf", base))
})

test_that("kişisel kova yalnızca tıklayan kullanıcının kimliğiyle sorgulanır", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  kova <- withr::local_tempdir(pattern = "scr-kova-")
  benim <- .scr_touch(kova, "rapor.pdf")
  env$.bucket[["7|rapor.pdf"]] <- benim

  expect_true(.scr_same(.scr_click(env, "rapor.pdf", base, uid = 7L)$datapath, benim))
  expect_true(all(vapply(env$.resolve_calls, function(x) identical(x$user_id, 7L), logical(1))))

  # Başka kullanıcı aynı atfı tıklar: kendi kovasında yok, model tabanında yok.
  env$.resolve_calls <- list()
  expect_null(.scr_click(env, "rapor.pdf", base, uid = 8L))
  expect_true(length(env$.resolve_calls) >= 1L)
  expect_true(all(vapply(env$.resolve_calls, function(x) identical(x$user_id, 8L), logical(1))))
})

test_that("model_bases kapsamı kişisel kovaya hiç başvurmaz ve oradan açmaz", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  kova <- withr::local_tempdir(pattern = "scr-kova-")
  env$.bucket[["7|rapor.pdf"]] <- .scr_touch(kova, "rapor.pdf")

  expect_null(.scr_click(env, "rapor.pdf", base, scope = "model_bases"))
  expect_length(env$.resolve_calls, 0L)

  kurumsal <- .scr_touch(base, "rapor.pdf")
  expect_true(.scr_same(.scr_click(env, "rapor.pdf", base, scope = "model_bases")$datapath, kurumsal))
  expect_length(env$.resolve_calls, 0L)
})

# ------------------------------------------------------------------------------
# Windows / UNC uyumu
# ------------------------------------------------------------------------------

test_that("UNC kökünde belirleyici aday dize düzeyinde kurulur ve kapsama korunur", {
  env <- .scr_env()
  kok <- "//sunucu/pay/Model"
  # Ağ yok: Windows'ta sahte UNC sunucusuna dosya sistemi çağrısı yapılmaz.
  env$dir.exists <- function(paths) rep(FALSE, length(paths))
  env$path_existing_variant <- function(path) {
    yol <- gsub("\\\\", "/", as.character(path)[1])
    if (identical(yol, "//sunucu/pay/Model/Surec/Alt/Talimat.docx")) yol else NA_character_
  }
  adaylar <- env$.preview_direct_rel_candidates("Surec&&Alt&&Talimat.pdf",
                                                c("Surec", "Alt", "Talimat.pdf"))
  expect_identical(adaylar[[1]], "Surec&&Alt&&Talimat.pdf")
  expect_identical(adaylar[[2]], c("Surec", "Alt", "Talimat.pdf"))
  expect_identical(adaylar[[4]], c("Surec", "Alt", "Talimat.docx"))
  expect_identical(env$.preview_probe_direct(kok, adaylar),
                   "//sunucu/pay/Model/Surec/Alt/Talimat.docx")

  expect_true(env$.preview_path_inside("\\\\sunucu\\pay\\Model\\Surec\\x.pdf", kok))
  expect_false(env$.preview_path_inside("//sunucu/pay/Model2/x.pdf", kok))
  expect_false(env$.preview_path_inside("//sunucu/pay/Model/../Diger/x.pdf", kok))
})

test_that("ters eğik çizgili Windows taban yolu çözülür", {
  skip_on_os(c("mac", "linux", "solaris"))
  env <- .scr_forbid_scan(.scr_env())
  base <- withr::local_tempdir(pattern = "scr-win-")
  hedef <- .scr_touch(base, "A", "B", "C.docx")

  acilan <- .scr_click(env, "A&&B&&C.pdf", gsub("/", "\\\\", base, fixed = TRUE))
  expect_true(.scr_same(acilan$datapath, hedef))
})

# ------------------------------------------------------------------------------
# Ad-tabanlı sınırlı tarayıcı
# ------------------------------------------------------------------------------

test_that("indeks tarayıcısı yalnızca desene uyan belgeleri alır, hariç ağaçları atlar", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  belge <- .scr_touch(base, "Kalite", "rapor.pdf")
  .scr_touch(base, "Kalite", "resim.png")
  .scr_touch(base, "node_modules", "paket", "okuma.md")

  out <- env$.file_index_scan_bounded(base, "\\.(pdf|md)$")
  expect_identical(basename(out), "rapor.pdf")
  expect_true(.scr_same(out[[1]], belge))
  expect_false(isTRUE(attr(out, "scan_partial")))
})

test_that("tarayıcı sınır aşımını KISMİ olarak işaretler", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_noise(base, n_dirs = 2L, per_dir = 5L)
  .scr_touch(base, "a", "b", "c", "derin.pdf")

  expect_true(isTRUE(attr(env$.file_index_scan_bounded(base, "\\.pdf$", max_files = 3L), "scan_partial")))
  expect_true(isTRUE(attr(env$.file_index_scan_bounded(base, "\\.pdf$", max_depth = 1L), "scan_partial")))
})

test_that("alt klasör listelenemezse indeks KISMİ olur ve TTL boyunca önbelleğe alınmaz", {
  env <- .scr_env()
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_touch(base, "Kalite", "rapor.pdf")
  .scr_touch(base, "Erisilemez", "gizli_belge.pdf")
  gercek_liste <- env$.file_index_list_dir
  # Geçici UNC/erişim hatası: alt klasör listelenemez (ok = FALSE).
  env$.file_index_list_dir <- function(yol, kalan_ms, max_entries) {
    if (identical(basename(yol), "Erisilemez")) {
      return(list(entries = character(0), truncated = FALSE, ok = FALSE))
    }
    gercek_liste(yol, kalan_ms, max_entries)
  }

  out <- env$.file_index_scan_bounded(base, "\\.pdf$")
  expect_identical(basename(out), "rapor.pdf")
  expect_true(isTRUE(attr(out, "scan_partial")))

  ent <- env$.build_basename_index(base)
  expect_null(ent$ts)
  expect_false(identical(env$.file_index_entry_state(ent), "fresh"))
})

test_that("klasör geçici olarak görünmezse önceki indeks korunur; taze boş indeks yazılmaz", {
  env <- .scr_env()
  env$FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 30
  base <- withr::local_tempdir(pattern = "scr-")
  .scr_touch(base, "Arsiv", "Grup&&Kalite&&prosedur.pdf")
  ilk <- env$.build_basename_index(base)
  expect_identical(env$.file_index_entry_state(ilk), "fresh")
  expect_true("grup&&kalite&&prosedur.pdf" %in% names(ilk$map))

  # UNC kopması: klasör görünmüyor.
  env$dir.exists <- function(paths) rep(FALSE, length(paths))
  sonra <- env$.build_basename_index(base, force = TRUE)
  expect_identical(sonra$map, ilk$map)
  expect_identical(sonra$ts, ilk$ts)
  expect_false(is.null(sonra$scan_failed_at))
  expect_identical(env$.file_index_entry_state(sonra), "backoff")

  # Önceki indeks yokken de boş harita TAZE sayılmaz; geri çekilme sonrası
  # yeniden taranır.
  rm(list = env$.file_index_key(base), envir = env$.FILE_INDEX_CACHE)
  bos <- env$.build_basename_index(base)
  expect_length(bos$map, 0L)
  expect_null(bos$ts)
  expect_identical(env$.file_index_entry_state(bos), "backoff")

  # Tarayıcı kök kaybolduğunda "boş klasör" değil BAŞARISIZ tarama bildirir.
  expect_true(isTRUE(attr(env$.file_index_scan_bounded(base, "\\.pdf$"), "scan_failed")))
})

test_that("tarayıcı sembolik bağlantılı dosya ve klasörleri indekse almaz", {
  skip_on_os("windows")
  env <- .scr_env()
  ust <- withr::local_tempdir(pattern = "scr-ust-")
  base <- file.path(ust, "model")
  dir.create(base)
  disarida <- .scr_touch(ust, "dis", "gizli.pdf")
  skip_if_not(isTRUE(file.symlink(disarida, file.path(base, "baglanti.pdf"))))
  skip_if_not(isTRUE(file.symlink(dirname(disarida), file.path(base, "baglanti_klasor"))))

  expect_length(env$.file_index_scan_bounded(base, "\\.pdf$"), 0L)
})
