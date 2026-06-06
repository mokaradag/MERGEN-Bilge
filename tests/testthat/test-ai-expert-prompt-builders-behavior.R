# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-prompt-builders-behavior.R
# Açıklama: AI Uzman üretim yapılandırması ve prompt/bağlam kurucularının saf
#           davranışını doğrular: get_ai_expert_generation_config,
#           build_ai_expert_system_prompt, build_ai_expert_user_context.
#           Çevrimdışı/deterministik: DB/LLM çağrısı yok (recent_prompts kapalı).
# ==============================================================================

repo_root_aiexp <- resolve_repo_root_for_tests()

.aiexp_env <- new.env(parent = globalenv())
source(file.path(repo_root_aiexp, "R/utils_common.R"), encoding = "UTF-8", local = .aiexp_env)
source(file.path(repo_root_aiexp, "R/utils_text_encoding.R"), encoding = "UTF-8", local = .aiexp_env)
source(file.path(repo_root_aiexp, "R/helpers_ai_expert.R"), encoding = "UTF-8", local = .aiexp_env)

test_that("get_ai_expert_generation_config senaryo/uzunluk/stil değerlerini doğru çözer", {
  c1 <- .aiexp_env$get_ai_expert_generation_config("idle_chat", "orta", "profesyonel")
  expect_identical(c1$max_tokens, 560L)
  expect_identical(c1$temperature, 0.55)

  c2 <- .aiexp_env$get_ai_expert_generation_config("greeting", "kisa", "samimi")
  expect_identical(c2$max_tokens, 264L) # max(200, round(480*0.55))
  expect_identical(c2$temperature, 0.80)

  c3 <- .aiexp_env$get_ai_expert_generation_config("page_guidance", "uzun", "bilimsel")
  expect_identical(c3$max_tokens, 648L) # round(360*1.80)
  expect_identical(c3$temperature, 0.45)

  c4 <- .aiexp_env$get_ai_expert_generation_config("bilinmeyen", "bilinmeyen", "bilinmeyen")
  expect_identical(c4$max_tokens, 480L)
  expect_identical(c4$temperature, 0.70)

  c5 <- .aiexp_env$get_ai_expert_generation_config("idle_chat", "kisa", "motivasyonel")
  expect_identical(c5$max_tokens, 308L) # max(200, round(560*0.55))
  expect_identical(c5$temperature, 0.90)
})

test_that("get_ai_expert_generation_config kisa uzunlukta 200 token alt sınırını korur", {
  # page_guidance base 360 -> round(360*0.55)=198 -> alt sınır 200
  cfg <- .aiexp_env$get_ai_expert_generation_config("page_guidance", "kisa", "profesyonel")
  expect_identical(cfg$max_tokens, 200L)
})

test_that("build_ai_expert_system_prompt senaryoya göre farklı içerik üretir", {
  char <- list(display_name = "EMRE ONAT", style_tr = "dengeli", system_prompt_en = "BASE")

  greeting <- .aiexp_env$build_ai_expert_system_prompt(char, scenario = "greeting", user_name = "Ahmet")
  expect_true(is.character(greeting) && nzchar(greeting))
  expect_true(grepl("Ahmet", greeting, fixed = TRUE))
  expect_true(grepl("Hızlı Başlangıç", greeting, fixed = TRUE))

  guidance <- .aiexp_env$build_ai_expert_system_prompt(
    char, scenario = "page_guidance", page_name = "Dosya Yönetimi"
  )
  expect_true(grepl("Dosya Yönetimi", guidance, fixed = TRUE))
  # Senaryolar gerçekten farklı metin üretmeli
  expect_false(identical(greeting, guidance))
})

test_that("build_ai_expert_system_prompt kullanıcı adı talimatını koşullu ekler", {
  char <- list(display_name = "EMRE ONAT", style_tr = "dengeli", system_prompt_en = "BASE")

  with_name <- .aiexp_env$build_ai_expert_system_prompt(char, scenario = "greeting", user_name = "Zeynep")
  expect_true(grepl("Kullanıcının adı Zeynep", with_name, fixed = TRUE))

  without_name <- .aiexp_env$build_ai_expert_system_prompt(char, scenario = "greeting", user_name = "")
  expect_false(grepl("Kullanıcının adı", without_name, fixed = TRUE))
})

test_that("build_ai_expert_user_context kullanıcı adı ve birim bilgisini ekler", {
  ctx <- .aiexp_env$build_ai_expert_user_context(
    user_id = 1L,
    user_name = "Ayşe",
    last_login_date = NULL,
    include_recent_prompts = FALSE,
    user_work_context = list(
      effective_unit = "Bilgi İşlem",
      department = "Bilgi İşlem",
      mudurluk = "Yazılım Müdürlüğü"
    )
  )
  expect_true(is.character(ctx) && length(ctx) == 1L)
  expect_true(grepl("Kullanıcının adı: Ayşe", ctx, fixed = TRUE))
  expect_true(grepl("departmanı: Bilgi İşlem", ctx, fixed = TRUE))
  expect_true(grepl("Yazılım Müdürlüğü", ctx, fixed = TRUE))
  expect_true(grepl("Şimdi:", ctx, fixed = TRUE))
})

test_that("build_ai_expert_user_context yalnızca birim varsa 'çalıştığı birim' satırını kullanır", {
  ctx <- .aiexp_env$build_ai_expert_user_context(
    user_id = 1L,
    user_name = "",
    last_login_date = NULL,
    include_recent_prompts = FALSE,
    user_work_context = list(effective_unit = "Ar-Ge")
  )
  expect_true(grepl("çalıştığı birim: Ar-Ge", ctx, fixed = TRUE))
  expect_false(grepl("Kullanıcının adı:", ctx, fixed = TRUE))
})

test_that("build_ai_expert_user_context giriş kaydı yoksa ilk kullanım notu ekler", {
  ctx <- .aiexp_env$build_ai_expert_user_context(
    user_id = 1L, user_name = "Mert",
    last_login_date = NULL, include_recent_prompts = FALSE
  )
  expect_true(grepl("önceki giriş kaydı bulunamadı", ctx, fixed = TRUE))
})

test_that("build_ai_expert_user_context uzun süredir girmeyen kullanıcıyı işaretler", {
  on_gun_once <- Sys.time() - as.difftime(10, units = "days")
  ctx <- .aiexp_env$build_ai_expert_user_context(
    user_id = 1L, user_name = "Mert",
    last_login_date = on_gun_once, include_recent_prompts = FALSE
  )
  expect_true(grepl("gün önce giriş", ctx, fixed = TRUE))
  expect_true(grepl("uzun süredir giriş yapmamış", ctx, fixed = TRUE))
})

test_that("build_ai_expert_user_context oturum mesajlarını bağlama ekler", {
  ctx <- .aiexp_env$build_ai_expert_user_context(
    user_id = 1L, user_name = "Mert",
    last_login_date = NULL, include_recent_prompts = FALSE,
    current_session_messages = c("Proje durumu nedir?", "Raporu özetle")
  )
  expect_true(grepl("Bu oturumdaki kullanıcı mesajları", ctx, fixed = TRUE))
  expect_true(grepl("Proje durumu nedir?", ctx, fixed = TRUE))
})
