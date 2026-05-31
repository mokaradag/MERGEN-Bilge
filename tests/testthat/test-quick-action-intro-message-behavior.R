# ==============================================================================
# Dosya Yolu: tests/testthat/test-quick-action-intro-message-behavior.R
# Açıklama: R/helpers_quick_action_intro_messages.R build_quick_action_intro_message
#           fonksiyonunun DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu;
#           resolve_quick_action_user_name ayrı dosyada kapsanıyor). Tanıtım
#           mesajları LLM üretmez; saf yereldir ve şu sözleşmeye uyar:
#             - selamlama: adsız "Merhaba <el-emojisi>",
#               adlı "Merhaba **<ad>** <el-emojisi>";
#             - başlık get_tool_mode_config(..., by="quick_action_id") ile çözülür,
#               eşleşme yoksa "Hızlı İşlem";
#             - bilinmeyen action_id tek varyantlı (DETERMİNİSTİK) else dalını kullanır;
#             - bilinen action_id'lerde birden çok varyant rastgele seçilebilir,
#               bu yüzden onlarda yalnızca yapısal değişmezler doğrulanır.
#           Emoji, repo kuralı gereği literal yerine intToUtf8(...) ile üretilir.
#           config= açıkça verilir; api_config global GEREKMEZ. DB/LLM/Shiny GEREKMEZ.
# ==============================================================================

.qaintro_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  # build_quick_action_intro_message, get_tool_mode_config'e bağlıdır.
  if (!exists("get_tool_mode_config", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_api_model_config.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("build_quick_action_intro_message",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_quick_action_intro_messages.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# El sallama emojisi (U+1F44B) parser-güvenli biçimde üretilir.
.qaintro_wave <- intToUtf8(0x1F44BL)

# Eşleşme içeren sentetik config.
.qaintro_cfg <- list(
  tool_mode_config = list(
    coding = list(quick_action_id = "coding-support", title = "Kodlama Destegi")
  )
)

# Bilinmeyen action_id için tek varyantlı (deterministik) fallback metni.
# Tam metin gerçek üretim davranışından doğrulanmıştır.
.qaintro_fallback_tail <- "\n\n**Hızlı İşlem** modu hazır. Sorunuzu yazabilirsiniz."

testthat::test_that("build_quick_action_intro_message bilinmeyen action_id'de deterministik else dalını üretir", {
  .qaintro_source_once()
  # Eşleşme yok -> başlık 'Hızlı İşlem'; tek varyant -> deterministik tam metin.
  beklenen <- paste0("Merhaba ", .qaintro_wave, .qaintro_fallback_tail)
  testthat::expect_identical(
    build_quick_action_intro_message("boyle_bir_id_yok", NULL, config = .qaintro_cfg),
    beklenen
  )
  # Aynı çağrı tekrar tekrar aynı sonucu vermeli (rastgelelik yok).
  tekrar <- replicate(
    5,
    build_quick_action_intro_message("boyle_bir_id_yok", NULL, config = .qaintro_cfg)
  )
  testthat::expect_length(unique(tekrar), 1L)
})

testthat::test_that("build_quick_action_intro_message ad verildiğinde '**ad**' selamlaması ekler", {
  .qaintro_source_once()
  beklenen <- paste0("Merhaba **Ayse** ", .qaintro_wave, .qaintro_fallback_tail)
  testthat::expect_identical(
    build_quick_action_intro_message("boyle_bir_id_yok", "Ayse", config = .qaintro_cfg),
    beklenen
  )
  # Baştaki/sondaki boşluk trimlenir.
  testthat::expect_identical(
    build_quick_action_intro_message("boyle_bir_id_yok", "  Ayse  ", config = .qaintro_cfg),
    beklenen
  )
})

testthat::test_that("build_quick_action_intro_message bilinen action_id'de selamlama+başlık değişmezlerini korur", {
  .qaintro_source_once()
  # coding-support 2 varyantlıdır; rastgele seçim olabilir, bu yüzden yapısal kontrol.
  m_noname <- build_quick_action_intro_message("coding-support", NULL, config = .qaintro_cfg)
  testthat::expect_true(startsWith(m_noname, "Merhaba "))
  testthat::expect_true(grepl("Kodlama Destegi", m_noname, fixed = TRUE))

  m_name <- build_quick_action_intro_message("coding-support", "Ali", config = .qaintro_cfg)
  testthat::expect_true(grepl("**Ali**", m_name, fixed = TRUE))
  testthat::expect_true(grepl("Kodlama Destegi", m_name, fixed = TRUE))
})

testthat::test_that("build_quick_action_intro_message config'ten başlığı kullanır, adsızda '**' içermez", {
  .qaintro_source_once()
  m <- build_quick_action_intro_message("boyle_bir_id_yok", NULL, config = .qaintro_cfg)
  # Adsız selamlamada kullanıcı adı kalın metni bulunmamalı.
  testthat::expect_false(grepl("Merhaba \\*\\*", m, perl = TRUE))
  # El emojisi selamlamada yer almalı.
  testthat::expect_true(grepl(.qaintro_wave, m, fixed = TRUE))
})
