# ==============================================================================
# Dosya Yolu: tests/testthat/test-music-url-encoding-behavior.R
# Açıklama: R/server_music_handlers.R UTF-8 müzik URL kodlama yardımcılarının
#           davranışsal testleri. Türkçe karakterler native byte (%DC) değil
#           UTF-8 percent-encoding ile (Ü->%C3%9C) kodlanmalıdır.
#           Türkçe karakterler intToUtf8 ile deterministik üretilir.
# ==============================================================================

testthat::local_edition(3)

.music_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "server_music_handlers.R"),
  encoding = "UTF-8",
  local = .music_env
)

# Deterministik Türkçe karakterler (kod noktasından).
.U_BUYUK <- intToUtf8(0x00DC)  # Ü
.u_kucuk <- intToUtf8(0x00FC)  # ü
.s_kucuk <- intToUtf8(0x015F)  # ş
.c_kucuk <- intToUtf8(0x00E7)  # ç

test_that("music_url_encode_segment_utf8 Türkçe karakterleri UTF-8 percent-encoding ile kodlar", {
  expect_equal(.music_env$music_url_encode_segment_utf8(.U_BUYUK), "%C3%9C")
  expect_equal(.music_env$music_url_encode_segment_utf8(.u_kucuk), "%C3%BC")
  expect_equal(.music_env$music_url_encode_segment_utf8(.s_kucuk), "%C5%9F")
  # Native byte kodlaması (%DC) ASLA üretilmemeli.
  expect_false(identical(.music_env$music_url_encode_segment_utf8(.U_BUYUK), "%DC"))
})

test_that("music_url_encode_segment_utf8 ASCII segmenti değiştirmeden bırakır", {
  expect_equal(.music_env$music_url_encode_segment_utf8("Karakter"), "Karakter")
  expect_equal(.music_env$music_url_encode_segment_utf8("emre"), "emre")
})

test_that("music_url_path_utf8 segmentleri '/' ile birleştirir ve her segmenti UTF-8 kodlar", {
  expect_equal(.music_env$music_url_path_utf8("music", "Karakter", "emre"), "music/Karakter/emre")
  # 'parça' -> 'par%C3%A7a' (ç -> %C3%A7), ayraç '/' korunur.
  expect_equal(.music_env$music_url_path_utf8(paste0("par", .c_kucuk, "a"), "x"), "par%C3%A7a/x")
})

test_that("music_url_path_utf8 boş ve NA segmentleri atar", {
  expect_equal(.music_env$music_url_path_utf8("a", "", NA, "b"), "a/b")
  expect_equal(.music_env$music_url_path_utf8(character(0)), "")
})

test_that("music_force_utf8 çıktıyı UTF-8 olarak işaretler ve ASCII'yi korur", {
  expect_equal(Encoding(.music_env$music_force_utf8(.U_BUYUK)), "UTF-8")
  expect_equal(.music_env$music_force_utf8("abc"), "abc")
})
