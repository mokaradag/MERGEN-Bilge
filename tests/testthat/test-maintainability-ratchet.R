# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet.R
# Açıklama: Maintainability skorunun ve büyük dosya sayaçlarının mevcut
#           üretim taban çizgisinin altına düşmesini engeller.
# ==============================================================================

.find_repo_root_maint_ratchet <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

test_that("maintainability skoru mevcut taban çizgisinin altına düşmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score <- attr(report, "maintainability_score", exact = TRUE)

  expect_true(
    is.numeric(score) || is.integer(score),
    info = "maintainability_report.R attr(..., 'maintainability_score') üretmelidir."
  )

  min_score <- .as_int_env("MERGEN_TEST_MIN_MAINTAINABILITY_SCORE", 100L)

  expect_true(
    score >= min_score,
    info = sprintf(
      "Maintainability skoru geriledi: %s/100 < minimum %s/100.",
      score,
      min_score
    )
  )
})

test_that("büyük dosya ve fonksiyon sayaçları mevcut taban çizgisinden kötüye gitmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score_report <- attr(report, "score_report", exact = TRUE)

  expect_true(
    is.data.frame(score_report),
    info = "maintainability_report.R attr(..., 'score_report') üretmelidir."
  )

  max_large_files <- .as_int_env("MERGEN_TEST_MAX_800_LINE_FILES", 0L)
  max_function_heavy_files <- .as_int_env("MERGEN_TEST_MAX_25_FUNCTION_FILES", 0L)
  max_very_large_files <- .as_int_env("MERGEN_TEST_MAX_1500_LINE_FILES", 0L)
  max_file_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_LINES", 690L)
  max_file_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_FUNCTIONS", 24L)

  actual_large_files <- sum(score_report$lines >= 800)
  actual_function_heavy_files <- sum(score_report$functions >= 25)
  actual_very_large_files <- sum(score_report$lines >= 1500)
  actual_max_lines <- max(score_report$lines, na.rm = TRUE)
  actual_max_functions <- max(score_report$functions, na.rm = TRUE)

  expect_true(
    actual_large_files <= max_large_files,
    info = sprintf(
      "800+ satır dosya sayısı arttı: %d > %d.",
      actual_large_files,
      max_large_files
    )
  )

  expect_true(
    actual_function_heavy_files <= max_function_heavy_files,
    info = sprintf(
      "25+ fonksiyon dosya sayısı arttı: %d > %d.",
      actual_function_heavy_files,
      max_function_heavy_files
    )
  )

  expect_true(
    actual_very_large_files <= max_very_large_files,
    info = sprintf(
      "1500+ satır dosya sayısı arttı: %d > %d.",
      actual_very_large_files,
      max_very_large_files
    )
  )

  expect_true(
    actual_max_lines <= max_file_lines,
    info = sprintf(
      "En büyük dosya satırı arttı: %d > %d.",
      actual_max_lines,
      max_file_lines
    )
  )

  expect_true(
    actual_max_functions <= max_file_functions,
    info = sprintf(
      "En yüksek fonksiyon sayısı arttı: %d > %d.",
      actual_max_functions,
      max_file_functions
    )
  )
})

test_that("near-limit runtime files do not silently consume remaining headroom", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  assert_current_budget <- function(path, max_lines, max_functions) {
    row <- report[
      grepl(
        paste0("(^|/)", gsub("([.])", "\\\\\\1", path), "$"),
        report$file,
        perl = TRUE
      ),
      ,
      drop = FALSE
    ]

    expect_equal(
      nrow(row),
      1L,
      info = sprintf("%s maintainability raporunda tek satır olarak görünmelidir.", path)
    )

    expect_true(
      row$lines[1] <= max_lines,
      info = sprintf("%s mevcut satır baş boşluğunu tüketti: %d > %d.", path, row$lines[1], max_lines)
    )

    expect_true(
      row$functions[1] <= max_functions,
      info = sprintf("%s mevcut fonksiyon baş boşluğunu tüketti: %d > %d.", path, row$functions[1], max_functions)
    )
  }

  assert_current_budget("R/module_claude_code.R", 780L, 11L)
  # TTS açık streaming dalı R/server_handler_streaming_tts.R'ye çıkarıldı; gerçek
  # SSE ve non-streaming dalları gibi simetrik handler oldu. send_message
  # 694/14 -> 590/9'a indi. Bütçeler geri birleşmeyi ve büyümeyi kilitler.
  assert_current_budget("R/server_send_message.R", 620L, 11L)
  assert_current_budget("R/server_handler_streaming_tts.R", 200L, 8L)
  assert_current_budget("R/module_admin_hata_analizi.R", 640L, 7L)
  assert_current_budget("R/helpers_admin_hata_detail_runtime.R", 380L, 12L)
  # Görsel UI/HTML render katmanı (ayarlar paneli, sohbet kontrolleri, görsel kartı
  # HTML üreticileri) R/module_image_generation_ui.R'ye çıkarıldı; runtime dosyası
  # 730/22 -> 545/17'ye indi. Bütçeler geri birleşmeyi ve büyümeyi kilitler.
  assert_current_budget("R/module_image_generation.R", 560L, 18L)
  assert_current_budget("R/module_image_generation_ui.R", 220L, 8L)
  assert_current_budget("R/helpers_llm_sse.R", 762L, 20L)
  # At-budget admin modüllerinin inline highcharter/DT renderer'ları *_outputs()
  # dosyalarına çıkarıldı (davranış değişmedi). Modüller veri/sekme orkestrasyonuna
  # odaklı kaldı; renderer'lar ayrı tek-sorumluluk dosyasında. Budgetler geri
  # birleşmeyi yakalar.
  assert_current_budget("R/module_admin_geri_bildirim.R", 90L, 3L)
  assert_current_budget("R/module_admin_geri_bildirim_outputs.R", 670L, 5L)
  assert_current_budget("R/helpers_admin_geri_bildirim_output_tables.R", 145L, 5L)
  assert_current_budget("R/module_admin_yanit_analizi.R", 140L, 4L)
  assert_current_budget("R/module_admin_yanit_analizi_outputs.R", 710L, 5L)
  assert_current_budget("R/server_module_wiring.R", 735L, 14L)
  assert_current_budget("R/server_core_interaction_runtime.R", 360L, 8L)
  assert_current_budget("R/server_core_observer_runtime.R", 320L, 6L)
  # AI Uzman sunucu işleyicileri: saf karar yardımcıları (sayfa adı, sıklık,
  # boşta bağlam) helpers_ai_expert_handlers_support.R'ye ayrıldıktan sonra
  # 726/23 -> 652/22'ye indi. Bütçe geri tırmanışı kilitler.
  assert_current_budget("R/server_ai_expert_handlers.R", 660L, 22L)
  assert_current_budget("R/helpers_ai_expert_handlers_support.R", 180L, 8L)
  assert_current_budget("R/module_file_manager.R", 725L, 14L)
  assert_current_budget("R/module_ai_expert.R", 686L, 22L)
  # AI Uzman yardımcı dosyası, worker-safe DB okuyucuları
  # helpers_ai_expert_user_data.R'ye ayrıldıktan sonra 24-fonksiyon küresel
  # tavanından indi (680/24 -> 507/13). Bütçe geri tırmanışı kilitler.
  assert_current_budget("R/helpers_ai_expert.R", 540L, 15L)
  assert_current_budget("R/helpers_ai_expert_user_data.R", 220L, 13L)
  assert_current_budget("R/helpers_mcp_tools.R", 535L, 20L)
  assert_current_budget("R/module_chartlab.R", 532L, 20L)
  # Sohbet okuma SQL'i (önizleme/liste/mesaj/toplu/geçmiş) saf üretici dosyasına
  # ayrıldı: helpers_db_chat_readers.R 680/13 -> 522/13; üreticiler 133/6.
  # SQL byte-birebir korundu (golden). Bütçeler SQL'in reader'a geri sızmasını kilitler.
  assert_current_budget("R/helpers_db_chat_readers.R", 560L, 14L)
  assert_current_budget("R/helpers_db_chat_read_queries.R", 180L, 8L)

  # Derin uzay giriş ekranı UI/sunucu olarak bölündü: createStartupScreenUI()
  # ve saf .startup_*() yapıcıları module_startup_screen_ui.R'ye taşındı; üç
  # deneyim-modu kartı tek veri-odaklı .startup_mode_card() ile üretilir.
  # module_startup_screen.R 740 -> 358 satıra indi. Bütçeler geri birleşmeyi
  # ve büyümeyi yakalar.
  assert_current_budget("R/module_startup_screen.R", 380L, 7L)
  assert_current_budget("R/module_startup_screen_ui.R", 430L, 16L)

  # Yapılandırma UI'sinin medya/görsel/analiz kartları ayrı gelişmiş UI dosyasına
  # çıkarıldı; ana kompozitör ve temel kartlar ayrı kaldı. Bütçeler geri birleşmeyi
  # ve yeni en-büyük-dosya pinini yakalar.
  assert_current_budget("R/module_settings_yapilandirma_ui.R", 430L, 8L)
  assert_current_budget("R/module_settings_yapilandirma_advanced_ui.R", 370L, 6L)

  # Yönetişim katmanı (seam kayıt defteri + frontend bölge haritası) saf veri
  # dosyalarıdır; bütçeler bölge/seam başına birkaç yeni varlık satırına izin
  # verir ama dosyaların runtime mantığıyla şişmesini erken yakalar.
  # Bilinçli güncelleme: frontend bölge dosyası VERİ + DOĞRULAYICI olarak
  # bölündü (config_source_manifest.R / bootstrap_source_manifest.R deseni).
  # config_ui_asset_zones.R artık SADECE veri (777/10 -> 502/0); doğrulayıcı
  # API (saf fonksiyonlar) config_ui_asset_zone_validators.R'ye taşındı.
  # Veri dosyası 0 fonksiyonda kilitlenir (runtime mantık sızması engellenir);
  # doğrulayıcı dosyası 10 fonksiyonu taşır. Bütçeler geri birleşmeyi yakalar.
  assert_current_budget("R/config_ui_asset_zones.R", 550L, 2L)
  assert_current_budget("R/config_ui_asset_zone_validators.R", 360L, 12L)
  assert_current_budget("R/config_seam_registry.R", 580L, 8L)
})

test_that("module_claude_code.R setup extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  cc_row <- report[
    grepl("(^|/)R/module_claude_code\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(cc_row),
    1L,
    info = "R/module_claude_code.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_cc_lines <- .as_int_env("MERGEN_TEST_MAX_CLAUDE_CODE_LINES", 780L)

  expect_true(
    cc_row$lines[1] <= max_cc_lines,
    info = sprintf(
      "module_claude_code.R setup extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      cc_row$lines[1],
      max_cc_lines
    )
  )
})

test_that("mevcut büyük ve fonksiyon yoğun dosya taban çizgileri sessizce büyümez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  assert_file_budget <- function(path, max_lines, max_functions) {
    row <- report[
      grepl(paste0("(^|/)", gsub("([.])", "\\\\\\1", path), "$"), report$file, perl = TRUE),
      ,
      drop = FALSE
    ]

    expect_equal(
      nrow(row),
      1L,
      info = sprintf("%s maintainability raporunda tek satır olarak görünmelidir.", path)
    )

    expect_true(
      row$lines[1] <= max_lines,
      info = sprintf("%s satır bütçesini aştı: %d > %d.", path, row$lines[1], max_lines)
    )

    expect_true(
      row$functions[1] <= max_functions,
      info = sprintf("%s fonksiyon bütçesini aştı: %d > %d.", path, row$functions[1], max_functions)
    )
  }

  # Renderer'lar *_outputs() dosyalarına çıkarıldıktan sonra modül tabanı düştü.
  assert_file_budget("R/module_admin_geri_bildirim.R", 90L, 3L)
  assert_file_budget("R/module_admin_geri_bildirim_outputs.R", 670L, 5L)
  assert_file_budget("R/helpers_admin_geri_bildirim_output_tables.R", 145L, 5L)
  assert_file_budget("R/module_admin_yanit_analizi.R", 140L, 4L)
  assert_file_budget("R/module_admin_yanit_analizi_outputs.R", 710L, 5L)
  assert_file_budget("R/helpers_admin_geri_bildirim_queries.R", 260L, 3L)
  # Sidebar kullanıcı paneli bölünmesi: saf görünüm yardımcıları
  # helpers_sidebar_user_display.R içindedir; modül Shiny orkestrasyonuna
  # odaklı kalır. 24-fonksiyon tavanına geri tırmanmayı engeller.
  assert_file_budget("R/module_sidebar_user_panel.R", 360L, 17L)
  assert_file_budget("R/helpers_sidebar_user_display.R", 320L, 11L)
  # config_api.R bölünmesi sonrası sıkılaştırılmış bütçe: Derin Düşünme yetenek
  # kaydı helpers_deep_thinking_model_capabilities.R, API anahtarı kripto katmanı
  # helpers_api_key_crypto.R içindedir; bu dosyaya geri taşınarak bütçe tüketilemez.
  assert_file_budget("R/config_api.R", 520L, 6L)
  assert_file_budget("R/helpers_deep_thinking_model_capabilities.R", 160L, 4L)
  assert_file_budget("R/helpers_api_key_crypto.R", 220L, 12L)
  assert_file_budget("R/helpers_api_model_config.R", 360L, 18L)
  assert_file_budget("R/helpers_llm_worker.R", 799L, 8L)
  assert_file_budget("R/helpers_llm_worker_tool_results.R", 260L, 2L)
  assert_file_budget("R/helpers_claude_code.R", 450L, 18L)
  assert_file_budget("R/helpers_claude_code_directory_listing.R", 260L, 19L)
  # Bütçe: UNC ağ paylaşımı için runtime workdir yeniden kullanım yolu ve
  # fs::dir_ls fallback'i eklenince satır sayısı 240 -> ~325'e çıktı.
  assert_file_budget("R/helpers_claude_code_runtime_workdir.R", 360L, 14L)
  assert_file_budget("R/helpers_claude_code_workdir_scan.R", 423L, 14L)
  assert_file_budget("R/helpers_claude_code_workdir_snapshot.R", 450L, 24L)
  assert_file_budget("R/helpers_db_chat_mutations.R", 420L, 24L)
  assert_file_budget("R/helpers_database.R", 320L, 12L)
  assert_file_budget("R/helpers_server_runtime_contracts.R", 160L, 7L)
  assert_file_budget("R/server_runtime_context.R", 690L, 18L)
  assert_file_budget("R/server_core_observer_runtime.R", 320L, 6L)
  assert_file_budget("R/server_core_interaction_runtime.R", 360L, 8L)
  assert_file_budget("R/helpers_chartlab.R", 577L, 24L)
  assert_file_budget("R/helpers_chartlab_spec.R", 220L, 12L)
  assert_file_budget("R/helpers_files_path.R", 220L, 18L)
  assert_file_budget("R/helpers_files.R", 260L, 24L)
})

test_that("module_file_manager.R state runtime extraction sonrası 800 satır altı kalır", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  fm_row <- report[
    grepl("(^|/)R/module_file_manager\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  helper_row <- report[
    grepl("(^|/)R/helpers_file_manager_state_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(fm_row),
    1L,
    info = "R/module_file_manager.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_file_manager_state_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_fm_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_LINES", 799L)
  max_helper_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_STATE_RUNTIME_LINES", 450L)
  max_helper_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_STATE_RUNTIME_FUNCTIONS", 10L)

  expect_true(
    fm_row$lines[1] <= max_fm_lines,
    info = sprintf(
      "module_file_manager.R state runtime extraction sonrası 800 satır altı kalmalıdır: %d > %d.",
      fm_row$lines[1],
      max_fm_lines
    )
  )

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_file_manager_state_runtime.R küçük runtime helper dosyası olarak kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
      "helpers_file_manager_state_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      helper_row$functions[1],
      max_helper_functions
    )
  )
})

test_that("helpers_llm_sse.R akış I/O ayrımı sonrası ince kalır", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  sse_row <- report[
    grepl("(^|/)R/helpers_llm_sse\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(sse_row),
    1L,
    info = "R/helpers_llm_sse.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_sse_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_LINES", 799L)
  max_sse_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_FUNCTIONS", 24L)

  expect_true(
    sse_row$lines[1] <= max_sse_lines,
    info = sprintf(
      "helpers_llm_sse.R stream I/O ayrımı sonrası 800 satır altı kalmalıdır: %d > %d.",
      sse_row$lines[1],
      max_sse_lines
    )
  )

  expect_true(
    sse_row$functions[1] <= max_sse_functions,
    info = sprintf(
      "helpers_llm_sse.R fonksiyon sayısı stream I/O ayrımı sonrası 25 altı kalmalıdır: %d > %d.",
      sse_row$functions[1],
      max_sse_functions
    )
  )
})

test_that("helpers_llm_worker.R payload extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  worker_row <- report[
    grepl("(^|/)R/helpers_llm_worker\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  payload_row <- report[
    grepl("(^|/)R/helpers_llm_worker_payload\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  tool_results_row <- report[
    grepl("(^|/)R/helpers_llm_worker_tool_results\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(worker_row),
    1L,
    info = "R/helpers_llm_worker.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(payload_row),
    1L,
    info = "R/helpers_llm_worker_payload.R maintainability raporunda tek satır olarak görünmelidir."
  )
  
  expect_equal(
    nrow(tool_results_row),
    1L,
    info = "R/helpers_llm_worker_tool_results.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_worker_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_LINES", 799L)
  max_payload_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES", 320L)
  max_payload_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS", 12L)
  max_tool_results_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_TOOL_RESULTS_LINES", 260L)
  max_tool_results_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_TOOL_RESULTS_FUNCTIONS", 2L)

  expect_true(
    worker_row$lines[1] <= max_worker_lines,
    info = sprintf(
      "helpers_llm_worker.R payload extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      worker_row$lines[1],
      max_worker_lines
    )
  )

  expect_true(
    payload_row$lines[1] <= max_payload_lines,
    info = sprintf(
      "helpers_llm_worker_payload.R küçük saf helper dosyası olarak kalmalıdır: %d > %d.",
      payload_row$lines[1],
      max_payload_lines
    )
  )

  expect_true(
    payload_row$functions[1] <= max_payload_functions,
    info = sprintf(
      "helpers_llm_worker_payload.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      payload_row$functions[1],
      max_payload_functions
    )
  )

  expect_true(
    tool_results_row$lines[1] <= max_tool_results_lines,
    info = sprintf(
      "helpers_llm_worker_tool_results.R küçük araç-sonuç helper dosyası olarak kalmalıdır: %d > %d.",
      tool_results_row$lines[1],
      max_tool_results_lines
    )
  )

  expect_true(
    tool_results_row$functions[1] <= max_tool_results_functions,
    info = sprintf(
      "helpers_llm_worker_tool_results.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      tool_results_row$functions[1],
      max_tool_results_functions
    )
  )
})

test_that("helpers_mcp_tools.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  mcp_row <- report[grepl("(^|/)R/helpers_mcp_tools\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(mcp_row),
    1L,
    info = "R/helpers_mcp_tools.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_mcp_lines <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_LINES", 700L)
  max_mcp_functions <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_FUNCTIONS", 24L)

  expect_true(
    mcp_row$lines[1] <= max_mcp_lines,
    info = sprintf(
      "helpers_mcp_tools.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$lines[1],
      max_mcp_lines
    )
  )

  expect_true(
    mcp_row$functions[1] <= max_mcp_functions,
    info = sprintf(
      "helpers_mcp_tools.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$functions[1],
      max_mcp_functions
    )
  )
})

test_that("module_admin_geri_bildirim.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  gb_row <- report[grepl("(^|/)R/module_admin_geri_bildirim\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(gb_row),
    1L,
    info = "R/module_admin_geri_bildirim.R maintainability raporunda tek satır olarak görünmelidir."
  )

  # Inline highcharter/DT renderer'lar R/module_admin_geri_bildirim_outputs.R'ye
  # çıkarıldıktan sonra modül 760 -> 55 satıra indi. Taban 799 -> 90.
  max_gb_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES", 90L)
  max_gb_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS", 3L)

  expect_true(
    gb_row$lines[1] <= max_gb_lines,
    info = sprintf(
      "module_admin_geri_bildirim.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$lines[1],
      max_gb_lines
    )
  )

  expect_true(
    gb_row$functions[1] <= max_gb_functions,
    info = sprintf(
      "module_admin_geri_bildirim.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$functions[1],
      max_gb_functions
    )
  )
})

test_that("module_admin_hata_analizi.R helper extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  hata_row <- report[
    grepl("(^|/)R/module_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(hata_row),
    1L,
    info = "R/module_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_hata_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_ANALIZI_LINES", 640L)

  expect_true(
    hata_row$lines[1] <= max_hata_lines,
    info = sprintf(
      "module_admin_hata_analizi.R detail runtime extraction sonrası küçük kalmalıdır: %d > %d.",
      hata_row$lines[1],
      max_hata_lines
    )
  )

  helper_row <- report[
    grepl("(^|/)R/helpers_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  heatmap_helper_row <- report[
    grepl("(^|/)R/helpers_admin_hata_heatmap_data\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  detail_runtime_row <- report[
    grepl("(^|/)R/helpers_admin_hata_detail_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(heatmap_helper_row),
    1L,
    info = "R/helpers_admin_hata_heatmap_data.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(detail_runtime_row),
    1L,
    info = "R/helpers_admin_hata_detail_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_helper_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_LINES", 799L)
  max_helper_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_FUNCTIONS", 20L)
  max_heatmap_helper_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HEATMAP_HELPER_LINES", 120L)
  max_heatmap_helper_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HEATMAP_HELPER_FUNCTIONS", 2L)
  max_detail_runtime_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_DETAIL_RUNTIME_LINES", 380L)
  max_detail_runtime_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_DETAIL_RUNTIME_FUNCTIONS", 12L)

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_admin_hata_analizi.R 800 satır altı kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
      "helpers_admin_hata_analizi.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      helper_row$functions[1],
      max_helper_functions
    )
  )

  expect_true(
    heatmap_helper_row$lines[1] <= max_heatmap_helper_lines,
    info = sprintf(
      "helpers_admin_hata_heatmap_data.R küçük saf helper dosyası olarak kalmalıdır: %d > %d.",
      heatmap_helper_row$lines[1],
      max_heatmap_helper_lines
    )
  )

  expect_true(
    heatmap_helper_row$functions[1] <= max_heatmap_helper_functions,
    info = sprintf(
      "helpers_admin_hata_heatmap_data.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      heatmap_helper_row$functions[1],
      max_heatmap_helper_functions
    )
  )

  expect_true(
    detail_runtime_row$lines[1] <= max_detail_runtime_lines,
    info = sprintf(
      "helpers_admin_hata_detail_runtime.R küçük detay runtime helper dosyası olarak kalmalıdır: %d > %d.",
      detail_runtime_row$lines[1],
      max_detail_runtime_lines
    )
  )

  expect_true(
    detail_runtime_row$functions[1] <= max_detail_runtime_functions,
    info = sprintf(
      "helpers_admin_hata_detail_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      detail_runtime_row$functions[1],
      max_detail_runtime_functions
    )
  )
})

test_that("module_admin_yanit_analizi.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  yanit_row <- report[
    grepl("(^|/)R/module_admin_yanit_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(yanit_row),
    1L,
    info = "R/module_admin_yanit_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  # Inline highcharter/DT renderer'lar R/module_admin_yanit_analizi_outputs.R'ye
  # çıkarıldıktan sonra modül 753 -> 106 satıra indi. Taban 799 -> 140.
  max_yanit_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_YANIT_ANALIZI_LINES", 140L)

  expect_true(
    yanit_row$lines[1] <= max_yanit_lines,
    info = sprintf(
      "module_admin_yanit_analizi.R refactor sonrası taban çizgisini aşmamalıdır: %d > %d.",
      yanit_row$lines[1],
      max_yanit_lines
    )
  )
})