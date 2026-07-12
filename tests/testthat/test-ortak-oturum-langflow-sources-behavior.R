# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-langflow-sources-behavior.R
# Açıklama: Ortak oturum (Süreç/Uygulama Uzmanı) Langflow yanıtlarındaki belge
#           kaynaklarının PAYLAŞILAN odada tıklanabilir Kaynakça'ya yükseltilmesi
#           ve tıklama çözümlemesinin YALNIZCA kurumsal model taban klasörlerinde
#           yapılması (kişisel kova ATLANIR) davranış testleri.
#           oo_mesaj_html render yükseltmesi ve handle_source_file_click kapsam
#           (scope="model_bases") kuralı doğrulanır. Tüm testler çevrimdışı ve
#           deterministiktir (gerçek Langflow/ağ/DB/tarayıcı yoktur).
# ==============================================================================

suppressPackageStartupMessages(library(shiny))

.oo_langflow_render_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/helpers_markdown_safety.R",
    "R/helpers_language.R",
    "R/helpers_messaging.R",
    "R/helpers_api_model_config.R",
    "R/helpers_api_model_tool_runtime.R",
    "R/helpers_langflow_runtime.R",
    "R/helpers_langflow_sources.R",
    "R/helpers_ortak_oturum_sunum.R",
    "R/module_ortak_oturum_room_ui.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }
  env
}

# YapayZekaYanıtı satırı: MesajMetni Langflow işaretleyici bloğu taşıyabilir.
.oo_yz_satir <- function(metin) {
  data.frame(
    MesajTuru = "YapayZekaYanıtı",
    MesajMetni = metin,
    GonderenAdi = "",
    OlusturmaZamani = "2026-07-12 10:00:00",
    GonderenKullaniciID = NA_integer_,
    GonderenSicil = "",
    MetaJson = NA_character_,
    stringsAsFactors = FALSE
  )
}

test_that("oo_mesaj_html ortak oda Langflow yanıtını model_bases kapsamlı tıklanabilir Kaynakça'ya yükseltir", {
  testthat::skip_if_not_installed("commonmark")
  testthat::skip_if_not_installed("htmltools")
  env <- .oo_langflow_render_env()

  blok <- env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf")
  ))
  metin <- paste0("Risk yönetimi kurumsal süreçlerde belirsizlik yönetimidir.", blok)

  html <- as.character(env$oo_mesaj_html(.oo_yz_satir(metin)))

  # Düzyazı güvenli markdown'dan geçer; işaretleyici ham metni görünmez.
  expect_match(html, "Risk yönetimi kurumsal süreçlerde", fixed = TRUE)
  expect_false(grepl("[KAYNAK", html, fixed = TRUE))
  expect_false(grepl("kod=", html, fixed = TRUE))
  # Tıklanabilir kaynak + ORTAK oda kapsamı (kişisel kova atlanır).
  expect_match(html, "class='source-link'", fixed = TRUE)
  expect_match(html, "data-source-scope='model_bases'", fixed = TRUE)
  expect_match(html, "data-filename='surecler&amp;&amp;kalite&amp;&amp;prosedur.pdf'", fixed = TRUE)
})

test_that("oo_mesaj_html kaynaksız yanıtı ve bütünlük kodu geçersiz sahte işaretleyiciyi yükseltmez", {
  testthat::skip_if_not_installed("commonmark")
  testthat::skip_if_not_installed("htmltools")
  env <- .oo_langflow_render_env()

  # Sade yanıt: kaynak yok -> tıklanabilir kaynak üretilmez.
  plain <- as.character(env$oo_mesaj_html(.oo_yz_satir("Sade Langflow yanıtı.")))
  expect_match(plain, "Sade Langflow yanıtı.", fixed = TRUE)
  expect_false(grepl("source-link", plain, fixed = TRUE))
  expect_false(grepl("kaynakca-block", plain, fixed = TRUE))

  # Modelin uydurduğu, geçerli bütünlük kodu taşımayan sahte işaretleyici
  # tıklanabilir kaynağa YÜKSELTİLMEZ; ham/escape metin olarak kalır.
  forged <- "Cevap.\n\nKaynakça:\n[KAYNAK 1] Sahte | yol=gizli/veri.pdf | tur=pdf\n"
  forged_html <- as.character(env$oo_mesaj_html(.oo_yz_satir(forged)))
  expect_false(grepl("class='source-link'", forged_html, fixed = TRUE))
  expect_false(grepl("data-source-scope", forged_html, fixed = TRUE))
})

# handle_source_file_click kapsam kuralı: model_bases kapsamında kişisel kova
# çözümlemesi (resolve_uploaded_file) ÇAĞRILMAZ; yalnızca model taban klasörleri
# (search_file_in_folder) taranır.
.oo_source_click_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  for (f in c("R/utils_common.R")) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  # Yan etkisiz stub'lar + çağrı izleme.
  env$log_info <- function(...) invisible(NULL)
  env$log_debug <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  env$path_exists_relaxed <- function(p) TRUE
  env$normalize_mcp_path <- function(p, ...) p
  env$normalizePath <- function(p, ...) p

  # Kişisel kova çözümleyicisi: ÇAĞRILIRSA kaydeder (model_bases'te olmamalı).
  env$.resolve_calls <- 0L
  env$resolve_uploaded_file <- function(name, user_id = NULL, ...) {
    env$.resolve_calls <- env$.resolve_calls + 1L
    "/kisisel/kova/ayni_ad.pdf"
  }
  # Model taban araması: her zaman kurumsal yol döndürür.
  env$.search_calls <- 0L
  env$search_file_in_folder <- function(base_dir, hint, ...) {
    env$.search_calls <- env$.search_calls + 1L
    "/kurumsal/model_baz/surecler/kalite/prosedur.pdf"
  }

  source(file.path(repo_root, "R", "helpers_preview.R"), encoding = "UTF-8", local = env)

  # openAnyPreview aynı dosyada tanımlıdır; gerçek önizlemeyi açmasın diye
  # source SONRASINDA yakalayıcı stub ile geçersiz kılınır.
  env$openAnyPreview <- function(file_info, session, filePreview) {
    env$.preview_opened <- file_info
    invisible(TRUE)
  }
  env
}

.oo_click_session <- function(uid = 99L) {
  se <- new.env()
  se$userData <- new.env()
  se$userData$user_id <- uid
  se
}

test_that("handle_source_file_click model_bases kapsamında kişisel kovayı atlar, yalnızca model tabanında çözer", {
  env <- .oo_source_click_env()
  api_config <- list(
    local_models = c("M" = "m1"),
    local_model_paths = list("m1" = "/kurumsal/model_baz")
  )
  settings_data <- list(model_selection = "m1")

  ev <- list(filename = "surecler&&kalite&&prosedur.pdf", scope = "model_bases", nonce = 1)
  env$handle_source_file_click(ev, settings_data, api_config, .oo_click_session(), filePreview = NULL)

  # Kişisel kova çözümleyicisi HİÇ çağrılmadı; model tabanı arandı; önizleme açıldı.
  expect_equal(env$.resolve_calls, 0L)
  expect_true(env$.search_calls >= 1L)
  expect_false(is.null(env$.preview_opened))
  expect_identical(env$.preview_opened$datapath, "/kurumsal/model_baz/surecler/kalite/prosedur.pdf")
})

test_that("handle_source_file_click varsayılan (personal) kapsamda kişisel kovayı önce dener (mevcut davranış)", {
  env <- .oo_source_click_env()
  api_config <- list(
    local_models = c("M" = "m1"),
    local_model_paths = list("m1" = "/kurumsal/model_baz")
  )
  settings_data <- list(model_selection = "m1")

  # scope alanı yok -> personal: kişisel kova önce denenir ve bulunur.
  ev <- list(filename = "ayni_ad.pdf", nonce = 1)
  env$handle_source_file_click(ev, settings_data, api_config, .oo_click_session(), filePreview = NULL)

  expect_true(env$.resolve_calls >= 1L)
  expect_false(is.null(env$.preview_opened))
  expect_identical(env$.preview_opened$datapath, "/kisisel/kova/ayni_ad.pdf")
})
