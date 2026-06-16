# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-handlers-support-behavior.R
# Açıklama: R/helpers_ai_expert_handlers_support.R içindeki saf karar
#           yardımcılarının davranışsal testleri:
#             - ai_expert_page_name_tr (sayfa kimliği -> Türkçe ad)
#             - ai_expert_first_idle_delay_ms / ai_expert_idle_interval_ms
#               (sıklık -> ms eşlemesi)
#             - build_ai_expert_idle_user_context (boşta konuşma bağlam metni)
#           Saf, yan etkisiz yardımcılardır; DB/LLM/Shiny/ağ GEREKMEZ. now_text
#           dışarıdan verilir, bu yüzden testler deterministiktir.
# ==============================================================================

# utils_common.R safe_trimws/safe_nzchar/%||% sağlar; bağlam metni helper'ı
# bunları kullanır. Her ikisi de izole env'e yüklenir, böylece global ortam
# kirlenmez ve lexical scoping ile çözümleme korunur.
.ai_expert_handlers_support_env <- function() {
  env <- new.env(parent = globalenv())
  root <- resolve_repo_root_for_tests()
  source(file.path(root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(root, "R", "helpers_ai_expert_handlers_support.R"),
         encoding = "UTF-8", local = env)
  env
}

# ------------------------------------------------------------------------------
# ai_expert_page_name_tr
# ------------------------------------------------------------------------------
testthat::test_that("ai_expert_page_name_tr bilinen sayfalar için Türkçe adı döner", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_identical(env$ai_expert_page_name_tr("history"), "Söyleşi Geçmişi")
  testthat::expect_identical(env$ai_expert_page_name_tr("saved_chats"), "Kayıtlı Söyleşiler")
  testthat::expect_identical(env$ai_expert_page_name_tr("image_gallery"), "Görsel Galerisi")
  testthat::expect_identical(env$ai_expert_page_name_tr("claude_code"), "Bilge Yolaç")
  testthat::expect_identical(env$ai_expert_page_name_tr("files"), "Dosya Yönetimi")
  testthat::expect_identical(env$ai_expert_page_name_tr("settings_yapilandirma"), "Yapılandırma")
  testthat::expect_identical(env$ai_expert_page_name_tr("destek_yardim"), "Yardım Merkezi")
  testthat::expect_identical(
    env$ai_expert_page_name_tr("destek_geri_bildirim"),
    "Geri Bildirim ve Hata Bildirimi"
  )
  testthat::expect_identical(env$ai_expert_page_name_tr("destek_surum"), "Yenilikler")
  testthat::expect_identical(env$ai_expert_page_name_tr("destek_hakkinda"), "Hakkında")
})

testthat::test_that("ai_expert_page_name_tr 'chat' için Ana Söyleşi döner", {
  env <- .ai_expert_handlers_support_env()
  testthat::expect_identical(env$ai_expert_page_name_tr("chat"), "Ana Söyleşi")
})

testthat::test_that("ai_expert_page_name_tr bilinmeyen/yasaklı sayfa için NULL döner", {
  env <- .ai_expert_handlers_support_env()

  # Yasaklı sayfalar (settings_kisisel/admin_analytics/health) ve bilinmeyenler.
  testthat::expect_null(env$ai_expert_page_name_tr("settings_kisisel"))
  testthat::expect_null(env$ai_expert_page_name_tr("admin_analytics"))
  testthat::expect_null(env$ai_expert_page_name_tr("health"))
  testthat::expect_null(env$ai_expert_page_name_tr("bilinmeyen_sayfa"))
})

testthat::test_that("ai_expert_page_name_tr geçersiz girdileri güvenle NULL'a indirir", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_null(env$ai_expert_page_name_tr(NULL))
  testthat::expect_null(env$ai_expert_page_name_tr(NA))
  testthat::expect_null(env$ai_expert_page_name_tr(""))
  testthat::expect_null(env$ai_expert_page_name_tr(character(0)))
  # Uzunluğu 1 olmayan girdi de güvenle reddedilir.
  testthat::expect_null(env$ai_expert_page_name_tr(c("history", "files")))
})

# ------------------------------------------------------------------------------
# ai_expert_first_idle_delay_ms / ai_expert_idle_interval_ms
# ------------------------------------------------------------------------------
testthat::test_that("ai_expert_first_idle_delay_ms sıklığa göre ilk gecikmeyi verir", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_equal(env$ai_expert_first_idle_delay_ms("az"), 30000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms("orta"), 20000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms("sik"), 12000)
})

testthat::test_that("ai_expert_first_idle_delay_ms geçersiz/eksik sıklıkta orta'ya düşer", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_equal(env$ai_expert_first_idle_delay_ms(), 20000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms(NULL), 20000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms(NA), 20000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms(""), 20000)
  testthat::expect_equal(env$ai_expert_first_idle_delay_ms("garip_deger"), 20000)
})

testthat::test_that("ai_expert_idle_interval_ms sıklığa göre tekrar aralığını verir", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_equal(env$ai_expert_idle_interval_ms("az"), 60000)
  testthat::expect_equal(env$ai_expert_idle_interval_ms("orta"), 35000)
  testthat::expect_equal(env$ai_expert_idle_interval_ms("sik"), 20000)
})

testthat::test_that("ai_expert_idle_interval_ms geçersiz/eksik sıklıkta orta'ya düşer", {
  env <- .ai_expert_handlers_support_env()

  testthat::expect_equal(env$ai_expert_idle_interval_ms(), 35000)
  testthat::expect_equal(env$ai_expert_idle_interval_ms(NULL), 35000)
  testthat::expect_equal(env$ai_expert_idle_interval_ms("garip_deger"), 35000)
})

# ------------------------------------------------------------------------------
# build_ai_expert_idle_user_context
# ------------------------------------------------------------------------------
testthat::test_that("build_ai_expert_idle_user_context taban metni sayfa/sayaç/zaman içerir", {
  env <- .ai_expert_handlers_support_env()

  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    idle_count = 7L,
    now_text = "TEST_ZAMAN"
  )

  testthat::expect_type(out, "character")
  testthat::expect_length(out, 1L)
  # Sayfa adı, boşta sayaç cümlesi ve güncel zaman metni mevcut olmalı.
  testthat::expect_true(grepl("'TestSayfa'", out, fixed = TRUE))
  testthat::expect_true(grepl("Bu oturumda 7.", out, fixed = TRUE))
  testthat::expect_true(grepl("Selam verme", out, fixed = TRUE))
  testthat::expect_true(grepl("TEST_ZAMAN", out, fixed = TRUE))

  # İş bağlamı/oturum/veritabanı parçaları verilmediyse hiç eklenmemeli.
  # Taban metin tam olarak 3 parçadan (sayfa + sayaç + zaman) oluşur.
  parts <- strsplit(out, "\n\n", fixed = TRUE)[[1]]
  testthat::expect_length(parts, 3L)
})

testthat::test_that("build_ai_expert_idle_user_context departman+müdürlük bağlamını ekler", {
  env <- .ai_expert_handlers_support_env()

  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    user_work_context = list(
      department = "DeptX",
      mudurluk = "MudX",
      effective_unit = "UnitZ"
    ),
    idle_count = 1L,
    now_text = "Z"
  )

  # Departman ve müdürlük varsa o cümle kullanılır; birim cümlesi kullanılmaz.
  testthat::expect_true(grepl("DeptX", out, fixed = TRUE))
  testthat::expect_true(grepl("MudX", out, fixed = TRUE))
  testthat::expect_false(grepl("UnitZ", out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context yalnızca birim varsa birim cümlesini ekler", {
  env <- .ai_expert_handlers_support_env()

  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    user_work_context = list(effective_unit = "UnitZ"),
    idle_count = 1L,
    now_text = "Z"
  )

  testthat::expect_true(grepl("UnitZ", out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context müdürlük boşsa birim cümlesine düşer", {
  env <- .ai_expert_handlers_support_env()

  # Departman var ama müdürlük boş => departman+müdürlük dalı çalışmaz,
  # effective_unit dalına düşülür (özgün davranış).
  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    user_work_context = list(department = "DeptX", mudurluk = "", effective_unit = "UnitZ"),
    idle_count = 1L,
    now_text = "Z"
  )

  testthat::expect_true(grepl("UnitZ", out, fixed = TRUE))
  testthat::expect_false(grepl("DeptX", out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context oturum mesajlarını 200 karaktere kırpar", {
  env <- .ai_expert_handlers_support_env()

  uzun_mesaj <- strrep("a", 300)
  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    idle_count = 1L,
    session_msgs = uzun_mesaj,
    now_text = "Z"
  )

  testthat::expect_true(grepl("Bu oturumdaki", out, fixed = TRUE))
  # İlk 200 karakter mevcut; 201. karakter kırpıldığı için yok.
  testthat::expect_true(grepl(strrep("a", 200), out, fixed = TRUE))
  testthat::expect_false(grepl(strrep("a", 201), out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context son konuşma konularını 120 karaktere kırpar", {
  env <- .ai_expert_handlers_support_env()

  uzun_prompt <- strrep("b", 200)
  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    idle_count = 1L,
    recent_prompts = uzun_prompt,
    now_text = "Z"
  )

  testthat::expect_true(grepl("Veritabanından son konuşma konuları", out, fixed = TRUE))
  testthat::expect_true(grepl(strrep("b", 120), out, fixed = TRUE))
  testthat::expect_false(grepl(strrep("b", 121), out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context tüm parçaları sırayla birleştirir", {
  env <- .ai_expert_handlers_support_env()

  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    user_work_context = list(department = "DeptX", mudurluk = "MudX"),
    idle_count = 3L,
    session_msgs = c("ilk mesaj", "ikinci mesaj"),
    recent_prompts = c("eski konu"),
    now_text = "ZAMAN"
  )

  # Parçalar: sayfa + iş bağlamı + sayaç + oturum mesajları + son konular + zaman.
  parts <- strsplit(out, "\n\n", fixed = TRUE)[[1]]
  testthat::expect_length(parts, 6L)
  testthat::expect_true(grepl("ilk mesaj", out, fixed = TRUE))
  testthat::expect_true(grepl("ikinci mesaj", out, fixed = TRUE))
  testthat::expect_true(grepl("eski konu", out, fixed = TRUE))
})

testthat::test_that("build_ai_expert_idle_user_context NULL iş bağlamı/mesaj/konu ile güvenli çalışır", {
  env <- .ai_expert_handlers_support_env()

  out <- env$build_ai_expert_idle_user_context(
    page_name_tr = "TestSayfa",
    user_work_context = NULL,
    idle_count = 1L,
    session_msgs = NULL,
    recent_prompts = NULL,
    now_text = "Z"
  )

  parts <- strsplit(out, "\n\n", fixed = TRUE)[[1]]
  testthat::expect_length(parts, 3L)
})
