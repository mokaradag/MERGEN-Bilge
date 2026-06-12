# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-doc-internal-helpers-behavior.R
# Açıklama: Yönetici dokümantasyon görüntüleyicisinin iç yardımcıları için
#           davranış testleri: admin_doc_lookup, admin_doc_repo_root,
#           admin_doc_strip_tags ve admin_doc_allowed_tags. Çevrimdışı,
#           deterministik; gerçek DB/LLM/browser gerekmez.
# ==============================================================================

.adminDocEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_documentation.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("admin_doc_lookup bilinen kimliği döndürür, bilinmeyeni NULL yapar", {
  env <- .adminDocEnv()

  # Kayıt defterindeki ilk belgeyi referans al (gerçek kayıt, sabit kodlanmış değil)
  ilk_doc <- env$admin_doc_registry()[[1]]$docs[[1]]
  bulunan <- env$admin_doc_lookup(ilk_doc$id)

  testthat::expect_false(is.null(bulunan))
  testthat::expect_identical(bulunan$id, ilk_doc$id)
  testthat::expect_identical(bulunan$file, ilk_doc$file)

  # Bilinmeyen / geçersiz kimlikler NULL döner
  testthat::expect_null(env$admin_doc_lookup("boyle-bir-belge-yok"))
  testthat::expect_null(env$admin_doc_lookup(NULL))
  testthat::expect_null(env$admin_doc_lookup(NA_character_))
  testthat::expect_null(env$admin_doc_lookup(""))
  testthat::expect_null(env$admin_doc_lookup(c("a", "b")))
  testthat::expect_null(env$admin_doc_lookup(42L))
})

testthat::test_that("admin_doc_repo_root app.R + R/ içeren gerçek kökü bulur", {
  env <- .adminDocEnv()
  repo_root <- resolve_repo_root_for_tests()

  # Repo kökünden çağrıldığında kendisini döndürmeli
  kok <- withr::with_dir(repo_root, env$admin_doc_repo_root())
  testthat::expect_true(file.exists(file.path(kok, "app.R")))
  testthat::expect_true(dir.exists(file.path(kok, "R")))

  # app.R içermeyen geçici dizinden: MERGEN_REPO_ROOT adayı kazanmalı
  tmp <- withr::local_tempdir()
  kok2 <- withr::with_envvar(
    c(MERGEN_REPO_ROOT = repo_root),
    withr::with_dir(tmp, env$admin_doc_repo_root())
  )
  testthat::expect_identical(
    normalizePath(kok2, winslash = "/", mustWork = FALSE),
    normalizePath(repo_root, winslash = "/", mustWork = FALSE)
  )

  # Hiçbir aday uymuyorsa getwd() güvenli geri dönüş olur
  tmp2 <- withr::local_tempdir()
  kok3 <- withr::with_envvar(
    c(MERGEN_REPO_ROOT = ""),
    withr::with_dir(tmp2, env$admin_doc_repo_root())
  )
  testthat::expect_identical(
    normalizePath(kok3, winslash = "/", mustWork = FALSE),
    normalizePath(tmp2, winslash = "/", mustWork = FALSE)
  )
})

testthat::test_that("admin_doc_strip_tags etiketleri ayıklar ve entity'leri çözer", {
  env <- .adminDocEnv()

  # HTML etiketleri kaldırılır, metin korunur
  testthat::expect_identical(
    env$admin_doc_strip_tags("<strong>Başlık</strong> metni"),
    "Başlık metni"
  )

  # Temel entity'ler insan-okur biçime çözülür
  testthat::expect_identical(
    env$admin_doc_strip_tags("a &lt;- 1 &amp; b &gt; 2"),
    "a <- 1 & b > 2"
  )
  testthat::expect_identical(env$admin_doc_strip_tags("&quot;söz&quot;"), "\"söz\"")
  testthat::expect_identical(env$admin_doc_strip_tags("&#39;tek&#39;"), "'tek'")

  # Kenar durumlar güvenli boş döner
  testthat::expect_identical(env$admin_doc_strip_tags(NULL), "")
  testthat::expect_identical(env$admin_doc_strip_tags(NA_character_), "")
  testthat::expect_identical(env$admin_doc_strip_tags(123), "")

  # Türkçe karakterler bozulmaz
  testthat::expect_identical(
    env$admin_doc_strip_tags("<em>çğıİöşü</em>"),
    "çğıİöşü"
  )
})

testthat::test_that("admin_doc_allowed_tags beyaz listesi güvenli ve tehlikesiz kalır", {
  env <- .adminDocEnv()
  izinli <- env$admin_doc_allowed_tags()

  testthat::expect_true(is.character(izinli))
  testthat::expect_true(length(izinli) > 0)

  # Belge görüntüleme için gereken temel etiketler listede
  testthat::expect_true(all(c("p", "code", "pre", "table", "a", "h1") %in% izinli))

  # Tehlikeli etiketler asla beyaz listede olamaz (XSS sınırı)
  testthat::expect_false(any(c("script", "iframe", "style", "object", "embed",
                               "form", "svg", "math", "base", "link") %in% izinli))
})
