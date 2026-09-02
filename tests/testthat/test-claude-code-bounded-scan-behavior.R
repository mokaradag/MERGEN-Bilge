# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-bounded-scan-behavior.R
# Açıklama: Bilge Yolaç sınırlı (bounded) dizin tarayıcısının davranışını
#           doğrular: sınıra ulaşıldığında ERKEN durma, dizin/derinlik/bayt/
#           süre sınırları, varsayılan hariç tutmalar, erişilemeyen alt dizinin
#           ölümcül olmaması ve bağlantı (symlink) döngü koruması.
#           Çevrimdışı ve deterministiktir; DB/LLM/tarayıcı gerektirmez.
# ==============================================================================

.cc_bounded_scan_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  source(
    file.path(repo_root, "R", "helpers_claude_code_bounded_scan.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

# Kaynak metni bayt güvenli okur (Windows VM'de geçersiz UTF-8 baytları
# taramayı kırmasın diye repo genelindeki desen kullanılır).
.cc_bounded_scan_source_text <- function(code_only = FALSE) {
  yol <- file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_bounded_scan.R")
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  if (!isTRUE(code_only)) return(metin)

  # Açıklayıcı yorum satırları yasaklı-desen taramasında yanlış pozitif
  # üretmesin diye ayıklanır (repo genelindeki tarama kuralı).
  satirlar <- strsplit(metin, "\r?\n", perl = TRUE)[[1]]
  paste(satirlar[!grepl("^\\s*#", satirlar)], collapse = "\n")
}

# --- Platformdan bağımsız bağlantı/erişim yardımcıları --------------------
#
# Bu testler daha önce Windows'ta ATLANIYORDU. Oysa üretim platformu Windows
# VM'dir: sınır kontrollerinin orada da doğrulanması gerekir. Bu yüzden POSIX'e
# özgü mekanizmalar (chmod "000", file.symlink) platform uygun karşılıklarıyla
# değiştirilir; hiçbiri yönetici hakkı gerektirmez.

# Dizin bağlantısı: Windows'ta yönetici izni gerektirmeyen junction kullanılır.
.cc_scan_dir_link <- function(hedef, baglanti) {
  if (.Platform$OS.type == "windows") {
    return(isTRUE(suppressWarnings(tryCatch(
      Sys.junction(hedef, baglanti),
      error = function(e) FALSE
    ))))
  }

  isTRUE(suppressWarnings(tryCatch(
    file.symlink(hedef, baglanti),
    error = function(e) FALSE
  )))
}

# Dosya bağlantısı yalnızca POSIX'te (ve yetkili Windows oturumlarında)
# kurulabilir. Kurulamazsa çağıran taraf sözlüksel benzetime düşer.
.cc_scan_file_link <- function(hedef, baglanti) {
  isTRUE(suppressWarnings(tryCatch(
    file.symlink(hedef, baglanti),
    error = function(e) FALSE
  )))
}

# Bir dizini gerçekten okunamaz yapmak POSIX'e özgüdür. Windows'ta (ve root
# altında) aynı SÖZLEŞME, listeleyicinin dayandığı iki tabana lexical mock
# uygulanarak doğrulanır: list.files() sessizce boş döner ve file.access()
# okuma izni olmadığını bildirir. Fonksiyonlar env içine source edildiği için
# bu atamalar base sürümlerinden önce bulunur.
.cc_scan_can_chmod <- function() {
  .Platform$OS.type != "windows" &&
    !identical(Sys.info()[["user"]], "root") &&
    !identical(Sys.info()[["effective_user"]], "root")
}

.cc_scan_mock_unreadable <- function(env, yollar) {
  anahtar <- normalizePath(yollar, winslash = "/", mustWork = FALSE)

  gercek_list <- base::list.files
  gercek_access <- base::file.access
  gercek_require <- base::requireNamespace

  env$list.files <- function(path, ...) {
    if (normalizePath(path, winslash = "/", mustWork = FALSE) %in% anahtar) {
      return(character(0))
    }
    gercek_list(path, ...)
  }

  # `fs` yedeği namespace ile nitelenmiş çağrıdır ve lexical mock ile
  # yakalanamaz; erişilemez dizin benzetiminde kullanılabilir olmadığı
  # bildirilerek devre dışı bırakılır.
  env$requireNamespace <- function(package, ...) {
    if (identical(package, "fs")) return(FALSE)
    gercek_require(package, ...)
  }

  env$file.access <- function(names, mode = 0L) {
    if (normalizePath(names, winslash = "/", mustWork = FALSE) %in% anahtar) {
      return(stats::setNames(-1L, names))
    }
    gercek_access(names, mode)
  }

  invisible(TRUE)
}

.cc_bounded_scan_fixture <- function(dosya_sayisi = 12L) {
  kok <- withr::local_tempdir(.local_envir = parent.frame())

  for (i in seq_len(dosya_sayisi)) {
    writeLines("veri", file.path(kok, sprintf("dosya%02d.txt", i)), useBytes = TRUE)
  }

  dir.create(file.path(kok, "alt", "derin"), recursive = TRUE)
  writeLines("alt", file.path(kok, "alt", "alt.txt"), useBytes = TRUE)
  writeLines("derin", file.path(kok, "alt", "derin", "derin.txt"), useBytes = TRUE)

  for (haric in c(".git", "node_modules", "document_support")) {
    dir.create(file.path(kok, haric))
    writeLines("x", file.path(kok, haric, "gizli.txt"), useBytes = TRUE)
  }

  dir.create(file.path(kok, "renv", "library"), recursive = TRUE)
  writeLines("x", file.path(kok, "renv", "library", "paket.R"), useBytes = TRUE)

  kok
}

test_that("sınırlı tarayıcı max_files sınırında erken durur", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(40L)

  sonuc <- env$cc_scan_directory_bounded(kok, max_files = 5L)

  expect_true(isTRUE(sonuc$ok))
  expect_equal(sonuc$file_count, 5L)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_files")

  # Erken durma gerçek olmalı: kalan ağaç numaralandırılmamalıdır.
  expect_lt(sonuc$file_count, 40L)
})

test_that("sınırlı tarayıcı max_directories sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_dirs = 0L)

  expect_equal(sonuc$dir_count, 0L)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_directories")
})

test_that("sınırlı tarayıcı max_depth sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_depth = 0L)

  expect_equal(sonuc$dir_count, 0L)
  expect_false(any(grepl("/alt/", sonuc$files, fixed = TRUE)))
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_depth")
})

test_that("sınırlı tarayıcı max_total_bytes sınırını uygular", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_total_bytes = 6)

  expect_true(sonuc$total_bytes <= 6)
  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "max_total_bytes")
})

test_that("sınırlı tarayıcı zaman aşımını raporlar", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, max_elapsed_ms = 0)

  expect_true(isTRUE(sonuc$truncated))
  expect_equal(sonuc$truncated_reason, "timeout")
})

test_that("tek dosya boyut sınırını aşan dosya atlanır", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  writeLines("kucuk", file.path(kok, "kucuk.txt"), useBytes = TRUE)
  writeLines(strrep("x", 5000), file.path(kok, "buyuk.txt"), useBytes = TRUE)

  sonuc <- env$cc_scan_directory_bounded(kok, max_file_bytes = 100)

  expect_true("kucuk.txt" %in% basename(sonuc$files))
  expect_false("buyuk.txt" %in% basename(sonuc$files))
  expect_true(any(grepl("buyuk.txt", sonuc$skipped, fixed = TRUE)))
})

test_that("varsayılan hariç tutulan dizinler taranmaz", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_false(any(grepl("/\\.git/", sonuc$files, perl = TRUE)))
  expect_false(any(grepl("/node_modules/", sonuc$files, fixed = TRUE)))
  expect_false(any(grepl("/document_support/", sonuc$files, fixed = TRUE)))
  expect_false(any(grepl("/renv/library/", sonuc$files, fixed = TRUE)))

  # Normal alt klasörler taranmaya devam eder.
  expect_true("alt.txt" %in% basename(sonuc$files))
  expect_true("derin.txt" %in% basename(sonuc$files))
})

test_that("hariç tutulan dizin listesi yapılandırılabilir", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture()

  sonuc <- env$cc_scan_directory_bounded(kok, exclude_dirs = c("alt"))

  expect_false("alt.txt" %in% basename(sonuc$files))
  expect_true(any(grepl("gizli.txt", basename(sonuc$files), fixed = TRUE)))
})

test_that("erişilemeyen alt dizin taramayı düşürmez", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  writeLines("veri", file.path(kok, "gorunur.txt"), useBytes = TRUE)

  kapali <- file.path(kok, "kapali")
  dir.create(kapali)
  writeLines("gizli", file.path(kapali, "gizli.txt"), useBytes = TRUE)

  if (.cc_scan_can_chmod()) {
    Sys.chmod(kapali, "000")
    on.exit(Sys.chmod(kapali, "700"), add = TRUE)
  } else {
    .cc_scan_mock_unreadable(env, kapali)
  }

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_true("gorunur.txt" %in% basename(sonuc$files))
  expect_false("gizli.txt" %in% basename(sonuc$files))
})

test_that("dizin listeleyici hatası tarama hatalarına aktarılır", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  # Okunamayan kök dizin: list.files() sessizce boş döner, bu yüzden
  # listeleyici gerçek erişim hatasını ayrıca tespit etmelidir.
  if (.cc_scan_can_chmod()) {
    Sys.chmod(kok, "000")
    withr::defer(Sys.chmod(kok, "700"))
  } else {
    .cc_scan_mock_unreadable(env, kok)
  }

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_false(isTRUE(sonuc$ok))
  expect_true(isTRUE(sonuc$truncated))
  expect_identical(sonuc$truncated_reason, "listing_error")
  expect_length(sonuc$files, 0L)
  # MESAJ SÖZLEŞMESİ: erişim kontrolü `mode = 5L` (okuma + arama) yaptığı için
  # metin de her iki izni anar. Kararlı parçalar üzerinden eşleşilir; yalnızca
  # "okuma izni yok" arayan eski hâli, doğrulama güçlendirildiğinde kırılırdı.
  expect_true(any(grepl("Dizin listelenemedi", sonuc$errors, fixed = TRUE)))
  # OKUMA+ARAMA MESAJI DETERMİNİSTİK DALDA DENETLENİR.
  #
  # `fs` kurulu bir POSIX koşucusunda (root OLMAYAN) `fs::dir_ls(fail = FALSE)`
  # erişim hatasını UYARIYA çevirir; tarayıcı `options(warn = 2L)` altında
  # onu `Dizin listelenemedi: <fs mesajı>` hatasına dönüştürür ve
  # `file.access(mode = 5L)` ön denetimine HİÇ ULAŞMAZ. Yani yukarıdaki
  # yolda `okuma/arama izni yok` metnini şart koşmak, üretim doğruyken
  # başarısızlık üretirdi. Sözleşme bu yüzden yedeği KAPATAN çağrıda
  # doğrulanır: orada `list.files()` boş döner ve izin denetimi kesin çalışır.
  # `fs` yedeği devrede DEĞİLKEN (mock ya da paket yok) `list.files()` boş
  # döner ve izin ön denetimi KESİN çalışır; o zaman tam metin şart koşulur.
  fs_yedegi_var <- isTRUE(tryCatch(env$requireNamespace("fs", quietly = TRUE),
                                   error = function(e) FALSE))
  if (!fs_yedegi_var) {
    expect_true(any(grepl("okuma/arama izni yok", sonuc$errors, fixed = TRUE)))
  }
})

test_that("dizin listeleyici kabuk alt süreci çalıştırmaz", {
  # REGRESYON: powershell.exe/find ile listeleme, Türkçe adları konsol OEM
  # kod sayfasıyla bozuyor ve uzun UNC yollarını satır genişliğinde katlıyordu.
  kaynak <- .cc_bounded_scan_source_text(code_only = TRUE)

  expect_false(grepl("powershell", kaynak, fixed = TRUE))
  expect_false(grepl("Get-ChildItem", kaynak, fixed = TRUE))
  expect_false(grepl("processx", kaynak, fixed = TRUE))
})

test_that("Türkçe karakterli dosya adları bozulmadan listelenir", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  # Parser/konsol bağımsızlığı için adlar Unicode kod noktalarından kurulur.
  turkce_ad <- paste0(
    "EK-U S", intToUtf8(0x00FC), "re", intToUtf8(0x00E7), " ",
    intToUtf8(0x0130), intToUtf8(0x015F), " Ak", intToUtf8(0x0131),
    intToUtf8(0x015F), "lar", intToUtf8(0x0131), ".txt"
  )

  hedef <- file.path(kok, turkce_ad)
  yazildi <- tryCatch({
    writeLines("veri", hedef, useBytes = TRUE)
    file.exists(hedef)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  skip_if_not(isTRUE(yazildi), "Dosya sistemi Türkçe adı desteklemiyor.")

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_length(sonuc$files, 1L)

  bulunan <- basename(sonuc$files[[1]])
  # Listelenen yol gerçekten diskte çözülebilmelidir; mojibake durumunda
  # bayt dizisi farklı olacağı için file.exists() FALSE dönerdi.
  expect_true(file.exists(sonuc$files[[1]]))
  expect_identical(enc2utf8(bulunan), enc2utf8(turkce_ad))

  # OEM -> ANSI bozulmasının imzası olan karakterler hiç görünmemelidir.
  expect_false(grepl(intToUtf8(0x20AC), bulunan, fixed = TRUE))
  expect_false(grepl(intToUtf8(0x0178), bulunan, fixed = TRUE))
  expect_false(grepl(intToUtf8(0x2021), bulunan, fixed = TRUE))
})

test_that("alt dizin listeleme hatası erişilebilir kardeşleri engellemez", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()
  dir.create(file.path(kok, "kapali"))
  dir.create(file.path(kok, "acik"))
  writeLines("veri", file.path(kok, "acik", "gorunur.txt"), useBytes = TRUE)

  gercek_listeleyici <- env$.cc_scan_list_entries
  env$.cc_scan_list_entries <- function(path, ...) {
    if (identical(basename(path), "kapali")) stop("paylaşım erişilemez")
    gercek_listeleyici(path, ...)
  }

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_false(isTRUE(sonuc$truncated))
  expect_true("gorunur.txt" %in% basename(sonuc$files))
  expect_true(any(grepl("paylaşım erişilemez", sonuc$errors, fixed = TRUE)))
})

test_that("dizin bağlantısı döngüsü sonsuz gezinmeye yol açmaz", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "alt"))
  writeLines("veri", file.path(kok, "alt", "veri.txt"), useBytes = TRUE)

  # Windows'ta junction, POSIX'te symlink: her ikisi de köke geri döner.
  baglanti_ok <- .cc_scan_dir_link(kok, file.path(kok, "alt", "dongu"))
  expect_true(baglanti_ok)

  sonuc <- env$cc_scan_directory_bounded(kok, max_elapsed_ms = 3000)

  expect_true(isTRUE(sonuc$ok))
  expect_false(identical(sonuc$truncated_reason, "timeout"))
  expect_true("veri.txt" %in% basename(sonuc$files))
  # Döngü yalnızca bir kez ziyaret edilebilir; aynı dosya tekrar tekrar
  # toplanmamalıdır.
  expect_equal(sum(basename(sonuc$files) == "veri.txt"), 1L)
})

test_that("izinli kök dışına kaçan bağlantı atlanır", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()
  disari <- withr::local_tempdir()

  writeLines("disarida", file.path(disari, "sizinti.txt"), useBytes = TRUE)
  writeLines("icerde", file.path(kok, "icerde.txt"), useBytes = TRUE)

  expect_true(.cc_scan_dir_link(disari, file.path(kok, "kacak")))

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_false("sizinti.txt" %in% basename(sonuc$files))
  expect_true("icerde.txt" %in% basename(sonuc$files))
})

test_that("izinli kök dışındaki dosya bağlantısı izole girdiye alınmaz", {
  env <- .cc_bounded_scan_env()
  kok <- withr::local_tempdir()
  disari <- withr::local_tempdir()
  hedef <- file.path(disari, "sizinti.txt")
  writeLines("disarida", hedef, useBytes = TRUE)
  baglanti <- file.path(kok, "baglanti.txt")

  gercek_baglanti <- .cc_scan_file_link(hedef, baglanti)

  if (!isTRUE(gercek_baglanti)) {
    # Windows'ta DOSYA symlink'i yönetici hakkı ister. Sözleşme yine de
    # doğrulanır: bağlantı bildirimi ve çözülmüş hedef sözlüksel olarak
    # taklit edilir; asıl korunan karar (izinli kök dışına çözülen girdi
    # asla izole girdiye alınmaz) aynen çalıştırılır.
    writeLines("yer tutucu", baglanti, useBytes = TRUE)
    baglanti_norm <- normalizePath(baglanti, winslash = "/", mustWork = FALSE)
    hedef_norm <- normalizePath(hedef, winslash = "/", mustWork = FALSE)

    env$.cc_scan_is_link <- function(path) {
      identical(normalizePath(path, winslash = "/", mustWork = FALSE), baglanti_norm)
    }

    gercek_norm <- base::normalizePath
    env$normalizePath <- function(path, winslash = "\\", mustWork = NA) {
      if (identical(gercek_norm(path, winslash = "/", mustWork = FALSE), baglanti_norm)) {
        return(hedef_norm)
      }
      gercek_norm(path, winslash = winslash, mustWork = mustWork)
    }
  }

  takip_yok <- env$cc_scan_directory_bounded(kok)
  takip_var <- env$cc_scan_directory_bounded(kok, follow_symlinks = TRUE)

  expect_false("baglanti.txt" %in% basename(takip_yok$files))
  expect_false("sizinti.txt" %in% basename(takip_var$files))
  expect_true(any(grepl("baglanti.txt", takip_yok$skipped, fixed = TRUE)))
})

test_that("göreli yol dönüşümü kök altındaki yapıyı korur", {
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(2L)

  sonuc <- env$cc_scan_directory_bounded(kok)
  rel <- env$cc_scan_relative_paths(sonuc$files, kok)

  expect_true("alt/alt.txt" %in% rel)
  expect_false(any(startsWith(rel, "/")))
})

test_that("list.files boş dönerse fs yedeği ile listeleme sürer", {
  # Windows VM / UNC paylaşımlarında base R list.files bazen boş döner; bu
  # yedek olmadan tarama sessizce boş sonuç üretir.
  env <- .cc_bounded_scan_env()
  kok <- .cc_bounded_scan_fixture(3L)

  env$list.files <- function(...) character(0)

  sonuc <- env$cc_scan_directory_bounded(kok)

  expect_true(isTRUE(sonuc$ok))
  expect_true(sonuc$file_count > 0L)
  expect_true("dosya01.txt" %in% basename(sonuc$files))
})

test_that("geçersiz kök güvenli sonuç döndürür", {
  env <- .cc_bounded_scan_env()

  bos <- env$cc_scan_directory_bounded("")
  expect_false(isTRUE(bos$ok))
  expect_equal(bos$truncated_reason, "invalid_root")

  yok <- env$cc_scan_directory_bounded(file.path(tempdir(), "kesinlikle_yok_12345"))
  expect_false(isTRUE(yok$ok))
  expect_equal(yok$truncated_reason, "missing_root")
})
