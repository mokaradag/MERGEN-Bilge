# ==============================================================================
# Dosya Yolu: tests/testthat/test-cc-yerel-yukleme-hedefi-behavior.R
# Açıklama: cc_setup_yerel_yukleme_hedefi() davranış testleri. Bilge Yolaç
#           "yerel klasör yükleme" akışında göreli yol TARAYICIDAN gelir
#           (webkitRelativePath); doğrulanmadan birleştirildiğinde '..',
#           mutlak yol veya sürücü harfi ile çalışma alanının DIŞINA
#           overwrite = TRUE yazılabiliyordu. Çevrimdışı ve deterministik.
# ==============================================================================

.cc_yy_env <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
    encoding = "UTF-8", local = env
  )
  env
}

testthat::test_that("güvenli göreli yollar çalışma alanı altına çözülür", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()

  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "proje/a.txt"),
    file.path(ws, "proje", "a.txt")
  )
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "a.txt"),
    file.path(ws, "a.txt")
  )

  # Türkçe dosya/klasör adları korunmalı (Latinleştirme yok).
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "klasör/Türkçe çalışma.txt"),
    file.path(ws, "klasör", "Türkçe çalışma.txt")
  )

  # Windows tarzı ayırıcı yol ayırıcısı olarak ele alınır.
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "a\\b.txt"),
    file.path(ws, "a", "b.txt")
  )
})

testthat::test_that("geçiş, mutlak yol ve sürücü harfi reddedilir", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()

  for (kotu in c("../../app.R", "../user_2/x.txt", "/etc/passwd", "C:/Windows/x.ini",
                 "..", ".", "", "alt/../a.txt", "//sunucu/pay/x.txt")) {
    testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, kotu), info = kotu)
  }

  # NULL / NA girdiler de güvenli biçimde reddedilir.
  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, NULL))
  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, NA_character_))
})

testthat::test_that("yükleme gözlemcisi hedefi doğrulama yardımcısından alır", {
  # Statik sözleşme: gözlemci ham file.path(calisma_alani, goreceli) birleşimine
  # geri dönmemelidir.
  metin <- paste(
    readLines(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_server_setup.R"),
      encoding = "UTF-8", warn = FALSE
    ),
    collapse = "\n"
  )
  testthat::expect_true(grepl("cc_setup_yerel_yukleme_hedefi(calisma_alani, goreceli)", metin, fixed = TRUE))
  testthat::expect_false(grepl("hedef <- file.path(calisma_alani, goreceli)", metin, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Son bileşen bağlantı (symlink / reparse point) denetimi
# ------------------------------------------------------------------------------
# Üst dizin kanoniklestirmesi hedefin KENDISINE dokunmaz. Hedef zaten calisma
# alani disina isaret eden bir baglanti olarak duruyorsa
# file.copy(..., overwrite = TRUE) baglantiyi izleyip harici dosyayi ezerdi.

# Platforma uygun baglanti kurar. Windows'ta DOSYA symlink'i ayricalik ister;
# bu yuzden orada dizin junction'i kullanilir (yonetici hakki gerekmez).
.cc_yy_baglanti_kur <- function(hedef_yol, disari_dosya, disari_dizin) {
  if (.Platform$OS.type == "windows") {
    isTRUE(tryCatch(Sys.junction(disari_dizin, hedef_yol), error = function(e) FALSE))
  } else {
    isTRUE(tryCatch(file.symlink(disari_dosya, hedef_yol), error = function(e) FALSE))
  }
}

testthat::test_that("çalışma alanı dışına işaret eden hedef bağlantısı reddedilir", {
  env <- .cc_yy_env()
  # Gercek baglanti denetimi icin yardimci gereklidir.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_bounded_scan.R"),
    encoding = "UTF-8", local = env
  )

  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari_dosya <- file.path(disari_kok, "kurban.txt")
  writeLines("degismemeli", disari_dosya)
  disari_dizin <- file.path(disari_kok, "kurban_dizin")
  dir.create(disari_dizin, showWarnings = FALSE)

  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)
  hedef_yol <- file.path(ws, "proje", "baglanti.txt")

  if (!.cc_yy_baglanti_kur(hedef_yol, disari_dosya, disari_dizin)) {
    testthat::skip("Bu ortamda bağlantı oluşturulamıyor.")
  }

  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, "proje/baglanti.txt"))
  # Guard yoksa file.copy bu dosyayı ezerdi; dokunulmamış olmalı.
  testthat::expect_identical(readLines(disari_dosya), "degismemeli")

  # NEGATİF KONTROL: aynı klasördeki sıradan (bağlantı olmayan) dosya, klasör
  # yeniden yüklendiğinde hâlâ üzerine yazılabilmelidir.
  writeLines("x", file.path(ws, "proje", "sade.txt"))
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "proje/sade.txt"),
    file.path(ws, "proje", "sade.txt")
  )
})

testthat::test_that("sarkan (kırık) bağlantı hedefi reddedilir", {
  env <- .cc_yy_env()
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_bounded_scan.R"),
    encoding = "UTF-8", local = env
  )

  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)

  # Hedef, var OLMAYAN bir dış dosyaya işaret eder: file.exists() bağlantıyı
  # izlediği için FALSE döner, ancak kopyalama bağlantıyı izleyip dış dosyayı
  # oluşturur/ezer.
  kirik <- file.path(ws, "proje", "kirik.txt")
  kuruldu <- isTRUE(tryCatch(
    file.symlink(file.path(disari_kok, "olmayan.txt"), kirik),
    error = function(e) FALSE
  ))
  if (!kuruldu) {
    testthat::skip("Bu ortamda sembolik bağlantı oluşturulamıyor.")
  }

  # POSIX sözleşmesi: sarkan bağlantıda file.exists() bağlantıyı izler ve FALSE
  # döner. Windows'ta R aynı girişi VAR sayıp yerinde çözebiliyor; orada bu ön
  # koşul hiç oluşmaz. Kararın kendisi bir sonraki (platformdan bağımsız) testte
  # sözcüksel olarak sınanır.
  if (isTRUE(file.exists(kirik))) {
    testthat::skip("Bu platformda sarkan bağlantı ön koşulu oluşmuyor.")
  }

  testthat::expect_false(file.exists(kirik))
  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, "proje/kirik.txt"))

  # Aynı klasörde gerçekten var olmayan sıradan ad hâlâ kabul edilir.
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "proje/yeni.txt"),
    file.path(ws, "proje", "yeni.txt")
  )
})

testthat::test_that("üst dizin listesinde duran ama stat edilemeyen hedef reddedilir", {
  # Platformdan BAĞIMSIZ: giriş üst dizin listesinde görünür fakat stat
  # edilemez (POSIX'te sarkan symlink, Windows'ta erişilemeyen reparse point).
  # Ayrıcalık gerektiren gerçek bağlantı yerine rapor sözcüksel taklit edilir.
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(ws, "proje", "sade.txt"))

  env$cc_path_is_reparse_link <- function(path) FALSE
  gercek_bilgi <- file.info
  env$file.info <- function(...) {
    yollar <- as.character(c(...))
    cikti <- gercek_bilgi(...)
    if (length(yollar) && grepl("sade\\.txt$", yollar[1])) {
      cikti$isdir <- NA
      cikti$size <- NA_real_
    }
    cikti
  }

  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, "proje/sade.txt"))

  # Listede olmayan ad bu denetimden etkilenmez.
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "proje/yeni.txt"),
    file.path(ws, "proje", "yeni.txt")
  )
})

testthat::test_that("üst dizin listelenemiyorsa kapalı-başarısız davranılır", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)

  env$list.files <- function(...) stop("listelenemedi")
  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, "proje/yeni.txt"))
})

testthat::test_that("bağlantı denetimi yapılamıyorsa var olan hedef fail-closed reddedilir", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(ws, "proje", "sade.txt"))

  # Denetim yardımcısı hata verirse doğrulanamayan hedefin üzerine yazılmaz.
  env$cc_path_is_reparse_link <- function(path) stop("denetim yok")
  testthat::expect_null(env$cc_setup_yerel_yukleme_hedefi(ws, "proje/sade.txt"))

  # Var OLMAYAN hedef bu denetimden etkilenmez.
  testthat::expect_identical(
    env$cc_setup_yerel_yukleme_hedefi(ws, "proje/yeni.txt"),
    file.path(ws, "proje", "yeni.txt")
  )
})

# ------------------------------------------------------------------------------
# Doğrulama SONRASI takas (TOCTOU) - cc_yerel_yukleme_yaz()
# ------------------------------------------------------------------------------
# Yol doğrulaması ile kopyalama arasında hedef ya da bir atası bağlantıyla
# değiştirilebilir. file.copy(..., overwrite = TRUE) bağlantıyı izlediği için
# yazma çalışma alanının dışına kaçardı.

testthat::test_that("yükleme yazımı normal dosyayı oluşturur ve üzerine yazar", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("yeni", kaynak)

  hedef <- file.path(ws, "proje", "a.txt")
  testthat::expect_true(env$cc_yerel_yukleme_yaz(kaynak, hedef, ws))
  testthat::expect_identical(readLines(hedef), "yeni")

  writeLines("guncel", kaynak)
  testthat::expect_true(env$cc_yerel_yukleme_yaz(kaynak, hedef, ws))
  testthat::expect_identical(readLines(hedef), "guncel")

  # Geçici parça dosyası bırakılmaz.
  testthat::expect_length(
    list.files(file.path(ws, "proje"), all.files = TRUE, pattern = "^\\.cc_yukleme_"),
    0L
  )
})

testthat::test_that("takas edilen hedef bağlantısı dış dosyayı ezmez", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari_dosya <- file.path(disari_kok, "kurban.txt")
  writeLines("degismemeli", disari_dosya)

  dir.create(file.path(ws, "proje"), recursive = TRUE, showWarnings = FALSE)
  hedef <- file.path(ws, "proje", "x.txt")
  if (!isTRUE(tryCatch(file.symlink(disari_dosya, hedef), error = function(e) FALSE))) {
    testthat::skip("Bu ortamda sembolik bağlantı oluşturulamıyor.")
  }

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  testthat::expect_true(env$cc_yerel_yukleme_yaz(kaynak, hedef, ws))
  # rename() bağlantıyı İZLEMEZ, DEĞİŞTİRİR: dış dosya dokunulmamış olmalı.
  testthat::expect_identical(readLines(disari_dosya), "degismemeli")
  testthat::expect_identical(readLines(hedef), "saldirgan")
})

testthat::test_that("takas edilen ata dizini bağlantısında yazma reddedilir", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari_dizin <- file.path(disari_kok, "disari")
  dir.create(disari_dizin, showWarnings = FALSE)

  bagli_ata <- file.path(ws, "altd")
  kuruldu <- if (.Platform$OS.type == "windows") {
    isTRUE(tryCatch(Sys.junction(disari_dizin, bagli_ata), error = function(e) FALSE))
  } else {
    isTRUE(tryCatch(file.symlink(disari_dizin, bagli_ata), error = function(e) FALSE))
  }
  if (!kuruldu) {
    testthat::skip("Bu ortamda dizin bağlantısı oluşturulamıyor.")
  }

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  testthat::expect_false(env$cc_yerel_yukleme_yaz(kaynak, file.path(bagli_ata, "x.txt"), ws))
  # Ne hedef ne de geçici parça dış dizinde kalmalı.
  testthat::expect_length(list.files(disari_dizin, all.files = TRUE, no.. = TRUE), 0L)
})

testthat::test_that("yükleme gözlemcisi ham file.copy overwrite kullanmaz", {
  metin <- paste(
    readLines(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_server_setup.R"),
      encoding = "UTF-8", warn = FALSE
    ),
    collapse = "\n"
  )
  testthat::expect_true(grepl("cc_yerel_yukleme_yaz(dosyalar$datapath[i], hedef, calisma_alani)", metin, fixed = TRUE))
  testthat::expect_false(grepl("file.copy(dosyalar$datapath[i], hedef, overwrite = TRUE)", metin, fixed = TRUE))
})

testthat::test_that("son bileşen denetimi kaynakta korunur", {
  metin <- paste(
    readLines(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
      encoding = "UTF-8", warn = FALSE
    ),
    collapse = "\n"
  )
  kod <- paste(
    Filter(function(satir) !grepl("^\\s*#", satir), strsplit(metin, "\n", fixed = TRUE)[[1]]),
    collapse = "\n"
  )
  testthat::expect_true(grepl("cc_path_is_reparse_link", kod, fixed = TRUE))
  testthat::expect_true(grepl("mustWork = TRUE", kod, fixed = TRUE))
  # Varlık kararı yalnızca file.exists() ile verilmemelidir.
  testthat::expect_true(grepl("list.files(ust_dizin", kod, fixed = TRUE))
  testthat::expect_true(grepl("stat_ok", kod, fixed = TRUE))
})


# ------------------------------------------------------------------------------
# Doğrulama SONRASI ATA TAKASI (Greptile P1 iddiası) - deneysel karşı kontrol
# ------------------------------------------------------------------------------
# İddia: `gecici` doğrulandıktan sonra `file.rename()` ayrı ve değiştirilebilir
# `hedef` yolunu yeniden çözer; saldırgan aradaki pencerede bir ATA dizini
# bağlantıyla değiştirirse yazma kökün dışına düşer.
#
# Koruma yapısaldır: `gecici` HEDEFİN KENDİ DİZİNİNDE üretildiği için `hedef`in
# son bileşeni dışındaki her atası aynı zamanda `gecici`nin de atasıdır. Ata
# takası KAYNAK yolu da geçersiz kılar ve rename ENOENT ile düşer. Bu test
# saldırganın yarışı KAZANDIĞI durumu (rename'den hemen önce takas) kurar.

testthat::test_that("dogrulama sonrasi ata takasinda yazma disari tasmaz", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari <- file.path(disari_kok, "disari")
  dir.create(disari, showWarnings = FALSE)

  altd <- file.path(ws, "altd")
  dir.create(altd, showWarnings = FALSE)
  hedef <- file.path(altd, "x.txt")

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  baglanti_kur <- function(hedef_dizin, yol) {
    if (.Platform$OS.type == "windows") {
      isTRUE(tryCatch(Sys.junction(hedef_dizin, yol), error = function(e) FALSE))
    } else {
      isTRUE(tryCatch(file.symlink(hedef_dizin, yol), error = function(e) FALSE))
    }
  }

  # Saldırgan yarışı kazanır: rename çağrılmadan hemen önce ata takas edilir.
  gercek_rename <- base::file.rename
  takas_yapildi <- FALSE
  env$file.rename <- function(from, to) {
    if (!takas_yapildi) {
      unlink(altd, recursive = TRUE, force = TRUE)
      takas_yapildi <<- baglanti_kur(disari, altd)
    }
    gercek_rename(from, to)
  }

  sonuc <- env$cc_yerel_yukleme_yaz(kaynak, hedef, ws)

  if (!takas_yapildi) {
    testthat::skip("Bu ortamda dizin bağlantısı oluşturulamıyor.")
  }

  testthat::expect_false(isTRUE(sonuc))
  # Dış dizinde ne hedef ne de geçici parça dosyası oluşmalıdır.
  testthat::expect_length(list.files(disari, all.files = TRUE, no.. = TRUE), 0L)
})

# Başarısız rename'den sonra `unlink(hedef)` DENENMEMELİDİR: ata bağlantıyla
# değiştirilmişse bu yol kökün DIŞINI gösterir ve oradaki dosyayı silerdi.

testthat::test_that("basarisiz rename disaridaki dosyayi silmez", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari <- file.path(disari_kok, "disari")
  dir.create(disari, showWarnings = FALSE)
  kurban <- file.path(disari, "x.txt")
  writeLines("KURBAN", kurban)

  altd <- file.path(ws, "altd")
  dir.create(altd, showWarnings = FALSE)
  hedef <- file.path(altd, "x.txt")

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  # Rename basarisiz olur ve ata takas edilir; hedef artik dis dosyayi gosterir.
  gercek_rename <- base::file.rename
  takas_yapildi <- FALSE
  cagri <- 0L
  env$file.rename <- function(from, to) {
    cagri <<- cagri + 1L
    if (cagri == 1L) {
      unlink(altd, recursive = TRUE, force = TRUE)
      takas_yapildi <<- if (.Platform$OS.type == "windows") {
        isTRUE(tryCatch(Sys.junction(disari, altd), error = function(e) FALSE))
      } else {
        isTRUE(tryCatch(file.symlink(disari, altd), error = function(e) FALSE))
      }
      return(FALSE)
    }
    gercek_rename(from, to)
  }

  sonuc <- env$cc_yerel_yukleme_yaz(kaynak, hedef, ws)

  if (!takas_yapildi) {
    testthat::skip("Bu ortamda dizin bağlantısı oluşturulamıyor.")
  }

  testthat::expect_false(isTRUE(sonuc))
  # Dis dosya SILINMEMELI ve icerigi degismemelidir.
  testthat::expect_true(file.exists(kurban))
  testthat::expect_identical(readLines(kurban, warn = FALSE), "KURBAN")
})

# Geçici dosyanın temizliği de yol tabanlıdır. Kopyadan SONRA bir ata
# bağlantıyla değiştirilir ve dışarıya aynı adlı bir dosya konursa, ham yol
# üzerinden silme o dış dosyayı yok ederdi; temizlik dizin KİMLİĞİNE bağlıdır.

testthat::test_that("gecici temizligi ata takasindaki dis dosyayi silmez", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari <- file.path(disari_kok, "disari")
  dir.create(disari, showWarnings = FALSE)

  altd <- file.path(ws, "altd")
  dir.create(altd, showWarnings = FALSE)
  hedef <- file.path(altd, "x.txt")

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  # Saldirgan gecici dosyanin adini gozler, disariya AYNI adla bir dosya koyar,
  # sonra atayi baglantiyla degistirir ve rename'i basarisiz kilar.
  takas_yapildi <- FALSE
  ekilen <- NULL
  env$file.rename <- function(from, to) {
    ekilen <<- file.path(disari, basename(from))
    writeLines("KURBAN", ekilen)
    unlink(altd, recursive = TRUE, force = TRUE)
    takas_yapildi <<- if (.Platform$OS.type == "windows") {
      isTRUE(tryCatch(Sys.junction(disari, altd), error = function(e) FALSE))
    } else {
      isTRUE(tryCatch(file.symlink(disari, altd), error = function(e) FALSE))
    }
    FALSE
  }

  sonuc <- env$cc_yerel_yukleme_yaz(kaynak, hedef, ws)

  if (!takas_yapildi) {
    testthat::skip("Bu ortamda dizin bağlantısı oluşturulamıyor.")
  }

  testthat::expect_false(isTRUE(sonuc))
  # Disariya ekilen ayni adli dosya SILINMEMELIDIR.
  testthat::expect_true(file.exists(ekilen))
  testthat::expect_identical(readLines(ekilen, warn = FALSE), "KURBAN")
})

# Tam rename anında ata takas edilir ve dışarıya aynı adlı bir dosya konursa
# hem kaynak hem hedef dışarı çözülebilir. Bu, çalışma alanı verisini sızdırmaz
# (taşınan dosya saldırganın kendi ektiği dosyadır) ama işlem BAŞARILI
# BİLDİRİLMEMELİDİR; son doğrulama bunu yakalar.

testthat::test_that("tasima disari indiyse basari bildirilmez", {
  env <- .cc_yy_env()
  ws <- withr::local_tempdir()
  disari_kok <- withr::local_tempdir()
  disari <- file.path(disari_kok, "disari")
  dir.create(disari, showWarnings = FALSE)

  altd <- file.path(ws, "altd")
  dir.create(altd, showWarnings = FALSE)
  hedef <- file.path(altd, "x.txt")

  kaynak <- file.path(withr::local_tempdir(), "kaynak.txt")
  writeLines("saldirgan", kaynak)

  gercek_rename <- base::file.rename
  takas_yapildi <- FALSE
  env$file.rename <- function(from, to) {
    writeLines("EKILEN", file.path(disari, basename(from)))
    unlink(altd, recursive = TRUE, force = TRUE)
    takas_yapildi <<- if (.Platform$OS.type == "windows") {
      isTRUE(tryCatch(Sys.junction(disari, altd), error = function(e) FALSE))
    } else {
      isTRUE(tryCatch(file.symlink(disari, altd), error = function(e) FALSE))
    }
    gercek_rename(from, to)
  }

  sonuc <- env$cc_yerel_yukleme_yaz(kaynak, hedef, ws)

  if (!takas_yapildi) {
    testthat::skip("Bu ortamda dizin bağlantısı oluşturulamıyor.")
  }

  # Taşıma kökün dışına indiği için başarı bildirilmemelidir.
  testthat::expect_false(isTRUE(sonuc))
})

# Geçici dosyanın hedefin KENDİ dizininde üretilmesi bir güvenlik değişmezidir;
# tempdir() gibi ayrı bir dizine taşınırsa ata takası koruması kaybolur.
testthat::test_that("gecici dosya hedefin kendi dizininde uretilir", {
  metin <- paste(
    readLines(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
      encoding = "UTF-8", warn = FALSE
    ),
    collapse = "\n"
  )
  kod <- paste(
    Filter(function(satir) !grepl("^\\s*#", satir), strsplit(metin, "\n", fixed = TRUE)[[1]]),
    collapse = "\n"
  )
  testthat::expect_true(grepl("gecici <- file.path(", kod, fixed = TRUE))
  testthat::expect_true(grepl("    hedef_dizin,", kod, fixed = TRUE))
  # Geçici dosya tempdir()/tempfile() dizinine kaçırılmamalıdır.
  testthat::expect_false(grepl("gecici <- tempfile(", kod, fixed = TRUE))
  testthat::expect_false(grepl("gecici <- file.path(tempdir()", kod, fixed = TRUE))
  # Basarisiz rename sonrasi yol tabanli hedef silme geri getirilmemelidir.
  testthat::expect_false(grepl("unlink(hedef", kod, fixed = TRUE))
})
