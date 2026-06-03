# ==============================================================================
# Dosya Yolu: tests/testthat/test-character-video-behavior.R
# Açıklama: R/module_character_video.R persona video/görsel yardımcılarının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Kapsananlar:
#           - get_character_video_data(): persona kimliğini normalize eder
#             (eski kimlikler dahil), config tek kaynağından görsel yolu alır ve
#             www/characters/video/<id>/{intro,loop,select} dizinlerini tarar.
#           - characterVideoUI(): video oynatıcı + statik görsel UI yapısı.
#
#           normalize_character_id / get_character_record helper_bootstrap.R ile
#           global ortama yüklenir. Dizin tarama testleri geçici dizinlerde
#           withr::with_dir ile deterministik tutulur. cat() çıktısı yutulur.
#           Ağ/DB/LLM GEREKMEZ.
# ==============================================================================

.source_character_video_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_character_video.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# get_character_video_data cat() ile log basar; çıktıyı yutarak çağıran yardımcı.
.cv_quiet <- function(expr) {
  out <- NULL
  invisible(utils::capture.output(out <- force(expr)))
  out
}

# Geçici bir www/characters/video ağacı kurar ve dizin yolunu döndürür.
.make_video_tree <- function(char_key, intro = character(0), loop = character(0), select = character(0)) {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  base <- file.path(tmp, "www", "characters", "video", char_key)
  for (tip in c("intro", "loop", "select")) {
    dir.create(file.path(base, tip), recursive = TRUE, showWarnings = FALSE)
  }
  for (f in intro) file.create(file.path(base, "intro", f))
  for (f in loop) file.create(file.path(base, "loop", f))
  for (f in select) file.create(file.path(base, "select", f))
  tmp
}

# ------------------------------------------------------------------------------
# get_character_video_data: yapı ve normalize
# ------------------------------------------------------------------------------
testthat::test_that("get_character_video_data beklenen anahtar yapısını döndürür", {
  env <- .source_character_video_for_test()
  veri <- .cv_quiet(env$get_character_video_data("emre"))

  testthat::expect_true(is.list(veri))
  testthat::expect_named(veri, c("character", "image", "videos"))
  testthat::expect_named(veri$videos, c("intro", "loop", "select"))
  testthat::expect_true(is.character(veri$image))
})

testthat::test_that("get_character_video_data eski persona kimliğini yeni kimliğe normalize eder", {
  env <- .source_character_video_for_test()
  # Eski mitolojik kimlik 'mergen' -> 'emre' (göç sözleşmesi).
  veri <- .cv_quiet(env$get_character_video_data("mergen"))
  testthat::expect_identical(veri$character, "emre")
})

testthat::test_that("get_character_video_data bilinmeyen kimlikte güvenli varsayılana düşer", {
  env <- .source_character_video_for_test()
  veri <- .cv_quiet(env$get_character_video_data("kesinlikle_yok_xyz"))
  # normalize_character_id bilinmeyeni varsayılan persona 'emre'ye çözer.
  testthat::expect_identical(veri$character, "emre")
})

# ------------------------------------------------------------------------------
# get_character_video_data: dizin tarama
# ------------------------------------------------------------------------------
testthat::test_that("get_character_video_data mevcut video dosyalarını istemci yollarına çevirir", {
  env <- .source_character_video_for_test()
  tmp <- .make_video_tree("emre", intro = c("giris.mp4", "tanitim.webm"))

  veri <- withr::with_dir(tmp, .cv_quiet(env$get_character_video_data("emre")))

  # intro listesi iki dosya içermeli; istemci yolu 'characters/...' önekli olmalı.
  testthat::expect_length(veri$videos$intro, 2L)
  yollar <- unlist(veri$videos$intro, use.names = FALSE)
  testthat::expect_true("characters/video/emre/intro/giris.mp4" %in% yollar)
  testthat::expect_true("characters/video/emre/intro/tanitim.webm" %in% yollar)
  # loop ve select dizinleri boş -> boş liste.
  testthat::expect_length(veri$videos$loop, 0L)
  testthat::expect_length(veri$videos$select, 0L)
})

testthat::test_that("get_character_video_data dizin yoksa tüm video listeleri boş döner", {
  env <- .source_character_video_for_test()
  tmp <- withr::local_tempdir()  # www ağacı yok
  veri <- withr::with_dir(tmp, .cv_quiet(env$get_character_video_data("emre")))
  testthat::expect_length(veri$videos$intro, 0L)
  testthat::expect_length(veri$videos$loop, 0L)
  testthat::expect_length(veri$videos$select, 0L)
})

testthat::test_that("get_character_video_data yalnızca mp4/webm uzantılarını tarar", {
  env <- .source_character_video_for_test()
  tmp <- .make_video_tree("selin", intro = c("var.mp4", "okuma.txt", "kapak.png"))
  veri <- withr::with_dir(tmp, .cv_quiet(env$get_character_video_data("selin")))
  # Yalnızca .mp4 dahil edilmeli; .txt/.png dışlanır.
  testthat::expect_length(veri$videos$intro, 1L)
  testthat::expect_true(grepl("var.mp4", unlist(veri$videos$intro)[1], fixed = TRUE))
})

# ------------------------------------------------------------------------------
# characterVideoUI
# ------------------------------------------------------------------------------
testthat::test_that("characterVideoUI ad alanlı oynatıcı/görsel elemanlarını üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_character_video_for_test()

  html <- paste(as.character(env$characterVideoUI("cv")), collapse = "\n")
  testthat::expect_true(grepl("cv-video_container", html, fixed = TRUE))
  testthat::expect_true(grepl("cv-character_player", html, fixed = TRUE))
  testthat::expect_true(grepl("cv-character_static_img", html, fixed = TRUE))
  # Boş src yerine şeffaf 1x1 GIF data URI kullanılmalı (gizli konsol hatası önlenir).
  testthat::expect_true(grepl("data:image/gif;base64", html, fixed = TRUE))
  testthat::expect_false(grepl("src=\"\"", html, fixed = TRUE))
  # Başlatma betiği CinematicVideoManager'a bağlanmalı.
  testthat::expect_true(grepl("CinematicVideoManager", html, fixed = TRUE))
})
