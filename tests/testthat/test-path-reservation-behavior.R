# ==============================================================================
# Dosya Yolu: tests/testthat/test-path-reservation-behavior.R
# Açıklama: R/utils_path_reservation.R sahiplik jetonlu rezervasyon
#           primitiflerinin davranış sözleşmesi: atomik edinme, dayanıklı
#           marker ön koşulu, sahiplik kanıtlı bırakma ve yaş + sahiplik
#           kanıtına dayalı devralma.
#
#           Çevrimdışı ve deterministiktir: gerçek dosya sistemi (tempdir)
#           kullanılır; DB, LLM, ağ, tarayıcı veya Shiny GEREKMEZ.
# ==============================================================================

local({
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_path_reservation.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
})

.rezerv_yolu <- function() {
  file.path(withr::local_tempdir(.local_envir = parent.frame()), "hedef.rsv")
}

test_that("I/O yolu mutlak Windows bütçesini UTF-16 ile ölçer; ad ve kimlik korunur", {
  env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  paths <- c(paste0("C:/", strrep("p", 180), "/", strrep("n", 63)),
             paste0("//server/share/", strrep("p", 170), "/", strrep("n", 61)))
  env$.Platform <- list(OS.type = "unix")
  expect_identical(env$mergen_io_path(paste0(paths, "n")), paste0(paths, "n"))
  env$.Platform <- list(OS.type = "windows")
  expect_identical(env$mergen_io_path(paths), paths)
  for (path in paths) {
    long <- paste0(path, "n")
    expected <- chartr("/", "\\", if (startsWith(long, "//"))
      paste0("//?/UNC/", substring(long, 3L)) else paste0("//?/", long))
    expect_identical(env$mergen_io_path(long), expected)
    expect_identical(env$mergen_io_path(expected), expected)
    expect_identical(env$mergen_logical_path(expected), long)
  }
  # 248 birimden itibaren dizin I/O da kayıt defteri ayarı olmadan çalışır.
  expect_true(startsWith(env$mergen_io_path(paste0(paths[1], strrep("n", 12L))), "\\\\?\\"))
  # BMP dışı karakter iki UTF-16 birimidir; UTF-8 bayt sayısı bütçe değildir.
  supplementary <- paste0(substr(paths[1], 1L, 246L), intToUtf8(0x1f600))
  expect_true(startsWith(env$mergen_io_path(supplementary), "\\\\?\\"))
  posix <- paste0("/tmp/", strrep("p", 260L))
  expect_identical(env$mergen_io_path(posix), posix)
  expect_identical(env$mergen_io_path(c("", NA_character_)), c("", NA_character_))
})

test_that("I/O yolu 260 birimi aşan yolu sözcüksel kurar; nokta/boşluk bileşenine önek eklemez", {
  env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  env$.Platform <- list(OS.type = "windows")
  # fs yol birleştirme (path_abs/path_norm) Windows'ta PATH_MAX=260'da hata verir.
  expect_false(any(grepl("fs::", deparse(env$mergen_io_path), fixed = TRUE)))
  deep <- paste0("C:/", strrep("a", 150), "/", strrep("b", 150), "/", strrep("c", 150), "/f.txt")
  expect_identical(env$mergen_io_path(deep), chartr("/", "\\", paste0("//?/", deep)))
  dotted <- paste0("C:/", strrep("a", 150), "/./x/../", strrep("b", 150), "//f.txt")
  expect_identical(env$mergen_io_path(dotted),
                   chartr("/", "\\", paste0("//?/C:/", strrep("a", 150), "/", strrep("b", 150), "/f.txt")))
  unc <- paste0("\\\\srv\\share\\", strrep("u", 300), "\\f.txt")
  expect_identical(env$mergen_io_path(unc), paste0("\\\\?\\UNC\\srv\\share\\", strrep("u", 300), "\\f.txt"))
  env$getwd <- function() paste0("C:\\", strrep("w", 300))
  expect_identical(env$mergen_io_path("rel/f.txt"),
                   paste0("\\\\?\\C:\\", strrep("w", 300), "\\rel\\f.txt"))
  expect_identical(env$mergen_io_path("/kok/f.txt"), "/kok/f.txt")
  for (ad in c("rapor.", "rapor ", "klasor./f.txt", "klasor /f.txt")) {
    yol <- paste0("C:/", strrep("a", 300), "/", ad)
    expect_identical(env$mergen_io_path(yol), yol)
  }
  expect_identical(env$mergen_io_path("C:rel"), "C:rel")
})

test_that("mantıksal yol ve `\\\\?\\` eşi aynı dosya sayılır; harf anlamı değişmez", {
  env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  env$.Platform <- list(OS.type = "windows")
  env$normalizePath <- function(path, winslash = "\\", mustWork = NA) chartr("\\", winslash, path)
  long <- paste0("C:/", strrep("a", 300), "/f.txt")
  expect_true(env$mergen_same_path(long, env$mergen_io_path(long)))
  expect_true(env$mergen_same_path("C:/k/f.txt", "\\\\?\\C:\\k\\f.txt"))
  unc <- paste0("//srv/share/", strrep("b", 300), "/f.txt")
  expect_true(env$mergen_same_path(env$mergen_io_path(unc), unc))
  expect_false(env$mergen_same_path(long, sub("f.txt$", "g.txt", long)))
  expect_false(env$mergen_same_path("C:/k/f.txt", "C:/k/F.txt"))
  expect_false(env$mergen_same_path("", ""))
  expect_false(env$mergen_same_path(NA_character_, NA_character_))
})

test_that("uzun yol varlığı yalnız I/O yazımıyla görünürse son aday olarak bulunur", {
  env <- new.env(parent = globalenv())
  for (file in c("utils_path_reservation.R", "helpers_files_path.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  root <- withr::local_tempdir()
  dir.create(file.path(root, "k"))
  physical <- file.path(root, "k", "f.txt")
  writeLines("x", physical)
  logical <- file.path(root, strrep("u", 120), "f.txt")
  # Mantıksal bileşen diskte yoktur; yalnız I/O dönüşümü gerçek dizine bağlar.
  env$mergen_io_path <- function(path) sub(strrep("u", 120), "k", path, fixed = TRUE)
  expect_false(file.exists(logical))
  expect_identical(env$path_existing_variant(logical), physical)
  expect_true(env$path_exists_relaxed(logical))
  expect_identical(env$path_existing_variant(physical), physical)
  expect_true(is.na(env$path_existing_variant(file.path(root, strrep("u", 120), "yok.txt"))))
})

test_that("rezervasyon atomiktir: ikinci çağrı alamaz", {
  rezerv <- .rezerv_yolu()

  jeton_a <- mergen_reservation_token("a")
  jeton_b <- mergen_reservation_token("b")
  expect_false(identical(jeton_a, jeton_b))

  expect_true(mergen_reservation_acquire(rezerv, jeton_a))
  # AYNI yol için ikinci edinme BAŞARISIZ olur; aksi hâlde iki çağrı aynı
  # hedefi terfi ettirebilirdi.
  expect_false(mergen_reservation_acquire(rezerv, jeton_b))
  expect_identical(mergen_reservation_owner(rezerv), jeton_a)
})

test_that("bırakma SAHİPLİK KANITI ister", {
  rezerv <- .rezerv_yolu()
  jeton <- mergen_reservation_token("sahip")
  expect_true(mergen_reservation_acquire(rezerv, jeton))

  # Başka bir jetonla bırakma YAPILMAZ: yeni sahibin rezervasyonu silinmemeli.
  expect_false(mergen_reservation_release(rezerv, "baska-jeton"))
  expect_true(dir.exists(rezerv))

  expect_true(mergen_reservation_release(rezerv, jeton))
  expect_false(dir.exists(rezerv))
})

test_that("boş/NA jeton edinme ve bırakma için reddedilir", {
  rezerv <- .rezerv_yolu()
  expect_false(mergen_reservation_acquire(rezerv, ""))
  expect_false(mergen_reservation_acquire(rezerv, NA_character_))
  expect_false(dir.exists(rezerv))

  jeton <- mergen_reservation_token()
  expect_true(mergen_reservation_acquire(rezerv, jeton))
  expect_false(mergen_reservation_release(rezerv, ""))
  expect_true(dir.exists(rezerv))
})

test_that("devralma yalnızca doğrulanmış ölü sahibi geri kazanır", {
  rezerv <- .rezerv_yolu()
  eski <- mergen_reservation_token("eski")
  expect_true(mergen_reservation_acquire(rezerv, eski))
  yeni <- mergen_reservation_token("yeni")
  # Canlı yerel sahip yaştan bağımsız korunur (eşik -1: her yaş bayat sayılırdı).
  expect_false(mergen_reservation_takeover(rezerv, yeni, stale_sec = -1))
  expect_identical(mergen_reservation_owner(rezerv), eski)
  writeLines(c("2147483647-dead", paste0("host=", Sys.info()[["nodename"]])),
    .mergen_reservation_marker(rezerv))
  expect_true(mergen_reservation_takeover(rezerv, yeni, stale_sec = 3600))
  expect_identical(mergen_reservation_owner(rezerv), yeni)
})

test_that("heartbeat sahibi doğrular; yabancı jeton tazelemez", {
  rezerv <- .rezerv_yolu()
  jeton <- mergen_reservation_token()
  expect_true(mergen_reservation_acquire(rezerv, jeton))

  expect_true(mergen_reservation_touch(rezerv, jeton))
  expect_false(mergen_reservation_touch(rezerv, "yabanci"))
  expect_identical(mergen_reservation_owner(rezerv), jeton)
})

test_that("var olmayan rezervasyon için sahip NA ve yaş NA döner", {
  rezerv <- .rezerv_yolu()
  expect_true(is.na(mergen_reservation_owner(rezerv)))
  expect_true(is.na(mergen_reservation_age_sec(rezerv)))
  # Sahip okunamıyorsa bırakma da YAPILMAZ (kanıt yok).
  expect_false(mergen_reservation_release(rezerv, mergen_reservation_token()))
})

test_that("eski biçimli ya da uzak host rezervasyonu yalnız bayatlıktan sonra devralınır", {
  for (bicim in c("eski", "uzak")) {
    rezerv <- .rezerv_yolu()
    dir.create(rezerv)
    marker <- .mergen_reservation_marker(rezerv)
    if (bicim == "eski") writeLines("1-eski", marker) else writeLines(c("1-uzak", "host=baska-dugum"), marker)
    yeni <- mergen_reservation_token("yeni")
    expect_false(mergen_reservation_takeover(rezerv, yeni, stale_sec = 3600), info = bicim)
    Sys.setFileTime(marker, Sys.time() - 7200)
    expect_true(mergen_reservation_takeover(rezerv, yeni, stale_sec = 3600), info = bicim)
    expect_identical(mergen_reservation_owner(rezerv), yeni)
    # Devralma muteksinin yolu kalıcıdır; silinmesi karşılıklı dışlamayı bozardı.
    expect_true(file.exists(file.path(dirname(rezerv), ".mergen-rsv.reclaim")))
    expect_true(mergen_reservation_release(rezerv, yeni))
    expect_true(file.exists(file.path(dirname(rezerv), ".mergen-rsv.reclaim")))
  }
})

test_that("okunamayan sahiplik hiçbir yokluk yoklamasıyla silme yetkisi vermez", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  rezerv <- .rezerv_yolu()
  expect_true(env$mergen_reservation_acquire(rezerv, "2147483647-eski"))
  env$file.exists <- function(...) FALSE
  env$mergen_reclaim_mutex <- function(...) stop("okunamayan sahip mutekse ulaşmamalı")
  expect_false(env$mergen_reservation_takeover(rezerv, "yeni", stale_sec = -1))
  expect_false(env$.mergen_reservation_remove_owned(rezerv, NA_character_))
  expect_true(dir.exists(rezerv))
  expect_identical(readLines(file.path(rezerv, "owner"))[1], "2147483647-eski")
  env$mergen_reservation_owner <- function(path) NA_character_
  expect_false(env$.mergen_reservation_remove_owned(rezerv, "2147483647-eski"))
  expect_true(dir.exists(rezerv))
  expect_length(list.files(dirname(rezerv), pattern = "\\.q-"), 0L)
})

test_that("canlı rezervasyon muteks beklemez ve devralma kilit altında yeniden doğrulanır", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  rezerv <- .rezerv_yolu()
  expect_true(env$mergen_reservation_acquire(rezerv, "sahip"))
  env$mergen_lock_owner_reclaimable <- function(...) FALSE
  env$mergen_reclaim_mutex <- function(...) stop("canlı sahip muteks beklememeli")
  expect_false(env$mergen_reservation_takeover(rezerv, "yeni"))
  env$mergen_lock_owner_reclaimable <- function(...) TRUE
  env$mergen_reclaim_mutex <- function(path, timeout) {
    writeLines("yenilenen-sahip", file.path(rezerv, "owner"))
    filelock::lock(path, timeout = timeout)
  }
  expect_false(env$mergen_reservation_takeover(rezerv, "yeni"))
  expect_identical(env$mergen_reservation_owner(rezerv), "yenilenen-sahip")
})


test_that("izole rezervasyon devralması eksik muteks altyapısında kapalı kalır", {
  env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R/utils_path_reservation.R"),
         encoding = "UTF-8", local = env)
  rezerv <- .rezerv_yolu()
  expect_true(env$mergen_reservation_acquire(rezerv, "sahip"))
  expect_false(env$mergen_reservation_takeover(rezerv, "yeni"))
  expect_identical(env$mergen_reservation_owner(rezerv), "sahip")
})

test_that("uzun ebeveynde bayat rezervasyon aynı geri kazanım muteksiyle devralınır", {
  env <- new.env(parent = globalenv())
  for (name in c("helpers_process_ownership.R", "utils_path_reservation.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", name), local = env, encoding = "UTF-8")
  root <- withr::local_tempdir()
  parent <- file.path(root, strrep("p", 95), strrep("q", 95), strrep("r", 95))
  expect_true(dir.create(env$mergen_io_path(parent), recursive = TRUE))
  reservation <- file.path(parent, "dest.rsv")
  expect_gt(nchar(reservation), 259L)
  expect_true(env$mergen_reservation_acquire(reservation, "old"))
  env$mergen_lock_owner_reclaimable <- function(...) TRUE
  expect_true(env$mergen_reservation_takeover(reservation, "new"))
  expect_identical(env$mergen_reservation_owner(reservation), "new")
  expect_true(env$mergen_reservation_release(reservation, "new"))
  expect_false(dir.exists(env$mergen_io_path(reservation)))
})
