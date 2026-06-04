# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-server-helpers-behavior.R
# Açıklama: R/module_image_gallery.R imageGalleryServer içindeki kapanış (closure)
#           yardımcılarının davranışsal testleri. coerce_user_id, empty_images_df
#           ve gallery_images_same testServer içinde doğrudan çağrılarak doğrulanır.
#           Gerçek DB/tarayıcı yok; kullanıcı sağlayıcı 0 döndürür (tarama atlanır).
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.igs_env <- new.env(parent = globalenv())
local({
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_image_gallery.R"), encoding = "UTF-8", local = .igs_env)
  source(file.path(kok, "R", "module_image_gallery.R"), encoding = "UTF-8", local = .igs_env)
})

test_that("coerce_user_id metni integer'a çevirir, NULL'ı 0'a indirir", {
  skip_if_not_installed("shiny")
  shiny::testServer(.igs_env$imageGalleryServer,
                    args = list(id = "ig", current_user_id = function() 0L), {
    expect_identical(coerce_user_id("7"), 7L)
    expect_identical(coerce_user_id(NULL), 0L)
    expect_identical(coerce_user_id(12L), 12L)
    # Sayısal olmayan metin NA olur (üst katman bunu geçersiz sayar).
    expect_true(is.na(coerce_user_id("abc")))
  })
})

test_that("empty_images_df beklenen sütunlarla sıfır satırlı veri çerçevesi döner", {
  skip_if_not_installed("shiny")
  shiny::testServer(.igs_env$imageGalleryServer,
                    args = list(id = "ig", current_user_id = function() 0L), {
    df <- empty_images_df()
    expect_true(is.data.frame(df))
    expect_equal(nrow(df), 0L)
    expect_true(all(c("file_path", "chat_id", "filename", "month_label", "description") %in% names(df)))
  })
})

test_that("gallery_images_same anahtar kümesi eşitliğine göre karşılaştırır", {
  skip_if_not_installed("shiny")
  shiny::testServer(.igs_env$imageGalleryServer,
                    args = list(id = "ig", current_user_id = function() 0L), {
    a <- data.frame(file_path = c("a", "b"), file_size = c(1, 2), stringsAsFactors = FALSE)
    b_reorder <- data.frame(file_path = c("b", "a"), file_size = c(2, 1), stringsAsFactors = FALSE)
    farkli <- data.frame(file_path = c("a"), file_size = c(1), stringsAsFactors = FALSE)

    # İki boş galeri aynıdır.
    expect_true(gallery_images_same(empty_images_df(), empty_images_df()))
    # Sıra farklı ama aynı dosyalar -> aynı.
    expect_true(gallery_images_same(a, b_reorder))
    # Farklı satır sayısı -> farklı.
    expect_false(gallery_images_same(a, farkli))
    # data.frame olmayan girdi -> FALSE.
    expect_false(gallery_images_same(a, "metin"))
  })
})
