# ==============================================================================
# Dosya Yolu: tests/testthat/test-character-identity-behavior.R
# Açıklama: R/config_characters.R persona kimliği yardımcılarının DAVRANIŞSAL
#           testleri. Persona sistemi (CLAUDE.md §2A) tek kaynak sözleşmesidir ve
#           eski (mitolojik) kimliklerin yeni kimliklere göçü yalnızca
#           normalize_character_id() sınırında desteklenir. Test edilenler:
#             - normalize_character_id (varsayılan/geçersiz/geçerli/eski-göç)
#             - get_character_record (kayıt çözümleme + varsayılana düşme)
#             - get_character_asset_paths (id/avatar/image/video_dir/music_dir)
#             - get_characters_data (5 persona, varsayılan emre)
#           Saf base R; ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.charid_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("normalize_character_id",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "config_characters.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# normalize_character_id
# ------------------------------------------------------------------------------
testthat::test_that("normalize_character_id geçersiz/boş girdilerde varsayılan 'emre' döner", {
  .charid_source_once()
  testthat::expect_identical(normalize_character_id(NULL), "emre")
  testthat::expect_identical(normalize_character_id(character(0)), "emre")
  testthat::expect_identical(normalize_character_id(NA_character_), "emre")
  testthat::expect_identical(normalize_character_id(""), "emre")
  testthat::expect_identical(normalize_character_id("   "), "emre")
  testthat::expect_identical(normalize_character_id("bilinmeyen_persona"), "emre")
})

testthat::test_that("normalize_character_id geçerli kimlikleri korur (büyük/küçük harf duyarsız)", {
  .charid_source_once()
  for (id in c("emre", "selin", "deniz", "can", "ipek")) {
    testthat::expect_identical(normalize_character_id(id), id)
  }
  # tolower + trim uygulanır.
  testthat::expect_identical(normalize_character_id("EMRE"), "emre")
  testthat::expect_identical(normalize_character_id("  selin  "), "selin")
})

testthat::test_that("normalize_character_id eski mitolojik kimlikleri yeni kimliklere göçürür", {
  .charid_source_once()
  # CLAUDE.md §2A göç haritası.
  testthat::expect_identical(normalize_character_id("mergen"), "emre")
  testthat::expect_identical(normalize_character_id("ulgen"), "selin")
  testthat::expect_identical(normalize_character_id("ülgen"), "selin")
  testthat::expect_identical(normalize_character_id("kayra"), "deniz")
  testthat::expect_identical(normalize_character_id("erlik"), "can")
  testthat::expect_identical(normalize_character_id("umay"), "ipek")
  testthat::expect_identical(normalize_character_id("umay_ana"), "ipek")
  testthat::expect_identical(normalize_character_id("umay ana"), "ipek")
  # Büyük/küçük harf duyarsız göç.
  testthat::expect_identical(normalize_character_id("MERGEN"), "emre")
  testthat::expect_identical(normalize_character_id("Kayra"), "deniz")
})

# ------------------------------------------------------------------------------
# get_character_record
# ------------------------------------------------------------------------------
testthat::test_that("get_character_record kimliğe karşılık gelen kaydı döndürür", {
  .charid_source_once()
  rec <- get_character_record("selin")
  testthat::expect_identical(rec$id, "selin")
  testthat::expect_identical(rec$full_name, "Selin Sezgin")

  # Eski kimlik göç edilerek çözülür.
  testthat::expect_identical(get_character_record("mergen")$id, "emre")
  # Bilinmeyen / NULL -> varsayılan ilk kayıt (emre).
  testthat::expect_identical(get_character_record("yok_boyle")$id, "emre")
  testthat::expect_identical(get_character_record(NULL)$id, "emre")
})

# ------------------------------------------------------------------------------
# get_character_asset_paths
# ------------------------------------------------------------------------------
testthat::test_that("get_character_asset_paths kanonik id ve medya yollarını üretir", {
  .charid_source_once()
  ap <- get_character_asset_paths("deniz")
  testthat::expect_identical(ap$id, "deniz")
  testthat::expect_identical(ap$video_dir, file.path("characters", "video", "deniz"))
  testthat::expect_identical(ap$music_dir, file.path("Karakter", "deniz"))
  testthat::expect_true(is.character(ap$avatar) && nzchar(ap$avatar))
  testthat::expect_true(is.character(ap$image) && nzchar(ap$image))

  # Eski kimlik göç edilerek kanonik klasör adına dönüşür.
  ap_legacy <- get_character_asset_paths("kayra")
  testthat::expect_identical(ap_legacy$id, "deniz")
  testthat::expect_identical(ap_legacy$video_dir, file.path("characters", "video", "deniz"))
})

# ------------------------------------------------------------------------------
# get_characters_data
# ------------------------------------------------------------------------------
testthat::test_that("get_characters_data 5 personayı ve varsayılanı içerir", {
  .charid_source_once()
  data <- get_characters_data()
  testthat::expect_identical(data$default_style, "emre")
  testthat::expect_length(data$styles, 5L)

  ids <- vapply(data$styles, function(x) x$id, character(1))
  testthat::expect_setequal(ids, c("emre", "selin", "deniz", "can", "ipek"))
  testthat::expect_true(is.character(data$title) && nzchar(data$title))
})
