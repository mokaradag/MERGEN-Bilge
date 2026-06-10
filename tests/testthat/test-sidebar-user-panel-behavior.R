# ==============================================================================
# Dosya Yolu: tests/testthat/test-sidebar-user-panel-behavior.R
# Açıklama: Sidebar kullanıcı paneli saf yardımcılarının davranışsal testleri:
#           mb_sidebar_user_initials (ad -> baş harfler, Türkçe güvenli)
#           ve mb_sidebar_user_avatar_url (placeholder kullanıcı id reddi).
#           Saf yardımcılar artık R/helpers_sidebar_user_display.R içindedir.
#           turkish_toupper'ın gerçek davranışı için module_user_identity de
#           aynı ortama yüklenir.
# ==============================================================================

testthat::local_edition(3)

.sb_env <- new.env(parent = globalenv())
# first_char() turkish_toupper'ı kullanır; gerçek yolu test etmek için yükle.
source(file.path(resolve_repo_root_for_tests(), "R", "module_user_identity.R"), encoding = "UTF-8", local = .sb_env)
source(file.path(resolve_repo_root_for_tests(), "R", "helpers_sidebar_user_display.R"), encoding = "UTF-8", local = .sb_env)
source(file.path(resolve_repo_root_for_tests(), "R", "module_sidebar_user_panel.R"), encoding = "UTF-8", local = .sb_env)

# -----------------------------------------------------------------------------
# mb_sidebar_user_initials
# -----------------------------------------------------------------------------

test_that("mb_sidebar_user_initials iki kelimeli adda baş ve son harfi büyük üretir", {
  expect_equal(.sb_env$mb_sidebar_user_initials("Ahmet Yılmaz"), "AY")
  # Türkçe karakter bozulmamalı: ç->Ç, ö->Ö.
  expect_equal(.sb_env$mb_sidebar_user_initials("çetin öz"), "ÇÖ")
})

test_that("mb_sidebar_user_initials tek kelimede tek baş harf üretir", {
  expect_equal(.sb_env$mb_sidebar_user_initials("Mehmet"), "M")
})

test_that("mb_sidebar_user_initials full_name boşsa first_name'e düşer", {
  expect_equal(.sb_env$mb_sidebar_user_initials("", "Selin"), "S")
})

test_that("mb_sidebar_user_initials isim yoksa 'MB' varsayılanına döner", {
  expect_equal(.sb_env$mb_sidebar_user_initials(NULL, NULL), "MB")
  expect_equal(.sb_env$mb_sidebar_user_initials("   ", NULL), "MB")
})

# -----------------------------------------------------------------------------
# mb_sidebar_user_avatar_url
# -----------------------------------------------------------------------------

test_that("mb_sidebar_user_avatar_url geçerli id için .jpg URL'si üretir", {
  url <- .sb_env$mb_sidebar_user_avatar_url(42)
  expect_true(nzchar(url))
  expect_true(grepl("42", url, fixed = TRUE))
  expect_true(grepl("\\.jpg$", url))
})

test_that("mb_sidebar_user_avatar_url placeholder/geçersiz id için boş string döner", {
  expect_equal(.sb_env$mb_sidebar_user_avatar_url(0), "")
  expect_equal(.sb_env$mb_sidebar_user_avatar_url("unknown"), "")
  expect_equal(.sb_env$mb_sidebar_user_avatar_url(NULL), "")
})
