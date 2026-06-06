# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-choice-modal-builders-behavior.R
# Açıklama: API anahtarı seçim/onboarding modalı UI üreticilerinin davranışsal
#           testleri: api_key_choice_request_url, .api_key_choice_personal_card,
#           .api_key_choice_corporate_card, api_key_choice_modal_dialog.
#           Korumalı input kimlikleri (api_key_plain_input, api_key_save_btn,
#           api_key_clear_btn, api_key_use_default_btn) ve varsayılan-anahtar
#           durumuna göre tekli/çiftli kart düzeni doğrulanır. Sır/secret
#           kullanılmaz; ağ/DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

suppressMessages(library(shiny))

.akc_src <- function() {
  env <- new.env(parent = globalenv())
  # Kişisel kart şifre-girişi yardımcısına bağımlıdır.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_api_key_password_toggle.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "module_api_key_choice_modal.R"),
         encoding = "UTF-8", local = env)
  env
}

.akc_text <- function(ui) paste(as.character(ui), collapse = "\n")

testthat::test_that("api_key_choice_request_url güvenli çözümleme yapar", {
  env <- .akc_src()
  testthat::expect_identical(env$api_key_choice_request_url(NULL), "")
  testthat::expect_identical(env$api_key_choice_request_url(list()), "")
  testthat::expect_identical(env$api_key_choice_request_url(list(api_key_request_url = "")), "")
  testthat::expect_identical(
    env$api_key_choice_request_url(list(api_key_request_url = "http://intranet/talep")),
    "http://intranet/talep"
  )
})

testthat::test_that(".api_key_choice_personal_card korumalı input kimliklerini üretir", {
  env <- .akc_src()
  txt <- .akc_text(env$.api_key_choice_personal_card(NS("a")))

  # Sunucu observer'larının bağımlı olduğu korumalı kimlikler.
  testthat::expect_true(grepl("a-api_key_plain_input", txt, fixed = TRUE))
  testthat::expect_true(grepl("a-api_key_save_btn", txt, fixed = TRUE))
  testthat::expect_true(grepl("a-api_key_clear_btn", txt, fixed = TRUE))
})

testthat::test_that(".api_key_choice_corporate_card kurumsal kart işaretini üretir", {
  env <- .akc_src()
  txt <- .akc_text(env$.api_key_choice_corporate_card(NS("a")))
  testthat::expect_true(grepl("akc-card--corporate", txt, fixed = TRUE))
})

testthat::test_that("api_key_choice_modal_dialog varsayılan anahtar VARKEN çiftli kart sunar", {
  env <- .akc_src()
  txt <- .akc_text(env$api_key_choice_modal_dialog(NS("a"), default_available = TRUE))

  testthat::expect_true(grepl("akc-cards--dual", txt, fixed = TRUE))
  testthat::expect_true(grepl("Daha Sonra Karar Ver", txt, fixed = TRUE))
  # Kurumsal anahtar yolu mevcutken use_default düğmesi görünür.
  testthat::expect_true(grepl("a-api_key_use_default_btn", txt, fixed = TRUE))
})

testthat::test_that("api_key_choice_modal_dialog varsayılan anahtar YOKKEN tekli kart sunar", {
  env <- .akc_src()
  txt <- .akc_text(env$api_key_choice_modal_dialog(NS("a"), default_available = FALSE))

  testthat::expect_true(grepl("akc-cards--single", txt, fixed = TRUE))
  testthat::expect_true(grepl("Kapat", txt, fixed = TRUE))
  # Varsayılan anahtar yokken kurumsal "use_default" düğmesi gösterilmez.
  testthat::expect_false(grepl("a-api_key_use_default_btn", txt, fixed = TRUE))
})

# --- llm_worker_extract_preview_df (Türkçe alan adı toleranslı önizleme) -------

testthat::test_that("llm_worker_extract_preview_df liste olmayan girdide NULL döner", {
  env <- new.env(parent = globalenv())
  # llm_worker_extract_preview_df, main merge'i sonrasi _preview.R'ye TASINDI
  # (CLAUDE.md sozlesmesi). Eski _tool_results.R'den source etmek "fonksiyon
  # olmayana uygulama" hatasi verir.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_tool_results_preview.R"),
         encoding = "UTF-8", local = env)
  testthat::expect_null(env$llm_worker_extract_preview_df(42))
  testthat::expect_null(env$llm_worker_extract_preview_df("metin"))
})

testthat::test_that("llm_worker_extract_preview_df Türkçe 'sonuç_önizleme' adını çözer", {
  env <- new.env(parent = globalenv())
  # llm_worker_extract_preview_df, main merge'i sonrasi _preview.R'ye TASINDI
  # (CLAUDE.md sozlesmesi). Eski _tool_results.R'den source etmek "fonksiyon
  # olmayana uygulama" hatasi verir.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_tool_results_preview.R"),
         encoding = "UTF-8", local = env)

  # Türkçe alan adı deterministik biçimde (intToUtf8) kurulur: "sonuç_önizleme".
  turkce_ad <- intToUtf8(c(115, 111, 110, 117, 231, 95, 246, 110, 105, 122, 108, 101, 109, 101))
  df <- data.frame(a = 1:2, b = 3:4)
  raw <- list(durum = "ok", df)
  names(raw) <- c("durum", turkce_ad)

  out <- env$llm_worker_extract_preview_df(raw)
  testthat::expect_true(is.data.frame(out))
  testthat::expect_equal(nrow(out), 2L)
})

testthat::test_that("llm_worker_extract_preview_df ASCII 'preview' ve tek-data.frame yedeğini çözer", {
  env <- new.env(parent = globalenv())
  # llm_worker_extract_preview_df, main merge'i sonrasi _preview.R'ye TASINDI
  # (CLAUDE.md sozlesmesi). Eski _tool_results.R'den source etmek "fonksiyon
  # olmayana uygulama" hatasi verir.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_tool_results_preview.R"),
         encoding = "UTF-8", local = env)

  # ASCII 'preview' alanı
  df1 <- data.frame(x = 1:3)
  out1 <- env$llm_worker_extract_preview_df(list(preview = df1, baska = "x"))
  testthat::expect_identical(out1, df1)

  # Eşleşen ad yok ama tek bir data.frame var -> onu döndür
  df2 <- data.frame(y = 5:6)
  out2 <- env$llm_worker_extract_preview_df(list(meta = 1L, tablo = df2))
  testthat::expect_identical(out2, df2)

  # Hiç data.frame yok -> NULL
  testthat::expect_null(env$llm_worker_extract_preview_df(list(a = 1L, b = "x")))
})
