# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-asset-manifest-contract.R
# Açıklama: UI CSS/JS varlık manifesti yükleme sırası ve handler sözleşmeleri.
# ==============================================================================

.read_repo_text_ui_asset_contract <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.source_ui_asset_config_for_tests <- function() {
  asset_env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R/config_ui_assets.R"),
    encoding = "UTF-8",
    local = asset_env
  )
  asset_env
}

.ui_asset_contract_position <- function(paths, path) {
  pos <- match(path, paths)
  if (is.na(pos)) {
    Inf
  } else {
    pos
  }
}

.ui_asset_contract_handler_names <- function(path) {
  text <- .read_repo_text_ui_asset_contract(path)
  pattern <- "Shiny\\.addCustomMessageHandler\\s*\\(\\s*['\"]([^'\"]+)['\"]"
  matches <- gregexpr(pattern, text, perl = TRUE)
  raw_matches <- regmatches(text, matches)[[1]]

  if (length(raw_matches) == 0) {
    return(character(0))
  }

  sub(pattern, "\\1", raw_matches, perl = TRUE)
}

test_that("UI varlık manifesti dosyaları, sırası ve çevrimdışı sözleşmesi korunur", {
  asset_env <- .source_ui_asset_config_for_tests()
  root <- resolve_repo_root_for_tests()

	css_paths <- asset_env$ui_asset_all_css()
	js_paths <- asset_env$ui_asset_all_js()
	all_paths <- c(css_paths, js_paths)

	expect_lt(
	  .ui_asset_contract_position(css_paths, "css/claude_code.css"),
	  .ui_asset_contract_position(css_paths, "css/claude_code_generated_files.css")
	)

	expect_lt(
	  .ui_asset_contract_position(css_paths, "css/claude_code_generated_files.css"),
	  .ui_asset_contract_position(css_paths, "css/claude_code_streaming.css")
	)

  expect_equal(asset_env$ui_asset_duplicate_paths(css_paths), character(0))
  expect_equal(asset_env$ui_asset_duplicate_paths(js_paths), character(0))
  asset_public_root <- asset_env$ui_asset_public_root(root)

  expect_true(all(file.exists(file.path(asset_public_root, all_paths))))
  expect_false(any(grepl("^(https?:)?//", all_paths, perl = TRUE)))

  asset_env$ui_asset_validate(root = root, check_files = TRUE)

  expect_identical(
    asset_env$ui_asset_js_groups$threejs,
    c(
      "lib/threejs/three.min.js",
      "lib/threejs/OrbitControls.js",
      "lib/threejs/CopyShader.js",
      "lib/threejs/LuminosityHighPassShader.js",
      "lib/threejs/ShaderPass.js",
      "lib/threejs/EffectComposer.js",
      "lib/threejs/RenderPass.js",
      "lib/threejs/UnrealBloomPass.js",
      "lib/threejs/Lensflare.js"
    )
  )

  expect_identical(
    asset_env$ui_asset_js_groups$bilge_yolac,
    c(
      "js/bilge_yolac_motor.js",
      "js/bilge_yolac_fizik.js",
      "js/bilge_yolac_varliklar.js",
      "js/bilge_yolac_seviye.js",
      "js/bilge_yolac_dunya.js",
      "js/bilge_yolac_karakterler.js",
      "js/bilge_yolac_cephanelik.js",
      "js/bilge_yolac_dusmanlar.js",
      "js/bilge_yolac_efektler.js",
      "js/bilge_yolac_arayuz.js",
      "js/bilge_yolac_etkilesim.js",
      "js/bilge_yolac_oyun.js",
      "js/bilge_yolac_kopru.js"
    )
  )

  deferred_paths <- asset_env$ui_asset_deferred_js_paths()
  
  expect_true("js/audio_lifecycle_guard.js" %in% deferred_paths)
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/music_manager.js"),
    .ui_asset_contract_position(js_paths, "js/audio_lifecycle_guard.js")
  )

  expect_true("js/claude_code_pixel_chars.js" %in% deferred_paths)
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/claude_code_pixel_chars.js"),
    .ui_asset_contract_position(js_paths, "js/claude_code.js")
  )
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/claude_code.js"),
    .ui_asset_contract_position(js_paths, "js/claude_code_streaming.js")
  )

  expect_true("js/welcome_tooltip_manager.js" %in% asset_env$ui_asset_js_groups$critical)
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/app_core.js"),
    .ui_asset_contract_position(js_paths, "js/welcome_tooltip_manager.js")
  )
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/welcome_tooltip_manager.js"),
    .ui_asset_contract_position(js_paths, "js/streaming_manager.js")
  )

  expect_lt(
    .ui_asset_contract_position(js_paths, "js/audio_lifecycle_guard.js"),
    .ui_asset_contract_position(js_paths, "js/stt_client.js")
  )
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/audio_lifecycle_guard.js"),
    .ui_asset_contract_position(js_paths, "js/tts_manager.js")
  )
  expect_lt(
    .ui_asset_contract_position(js_paths, "js/audio_lifecycle_guard.js"),
    .ui_asset_contract_position(js_paths, "js/ai_expert_manager.js")
  )

  expect_false(any(grepl("^codemirror/", deferred_paths)))
  expect_false("js/sso_auth.js" %in% deferred_paths)
  expect_false(any(asset_env$ui_asset_js_groups$critical %in% deferred_paths))

  expect_true(is.list(asset_env$ui_asset_js_order_rules))
  expect_gt(length(asset_env$ui_asset_js_order_rules), 0)

  render_plan_groups <- asset_env$ui_asset_render_plan_groups()
  expect_equal(sort(render_plan_groups), sort(names(asset_env$ui_asset_js_groups)))
  expect_equal(sort(render_plan_groups), sort(unique(render_plan_groups)))
  expect_identical(
    asset_env$ui_asset_render_plan_deferred(),
    asset_env$ui_asset_deferred_js_groups
  )

  invisible(lapply(asset_env$ui_asset_js_order_rules, function(rule) {
    expect_length(rule, 2)

    before_pos <- .ui_asset_contract_position(js_paths, rule[[1]])
    after_pos <- .ui_asset_contract_position(js_paths, rule[[2]])

    expect_lt(before_pos, after_pos)
  }))
})

test_that("smoke-only UX probe dosyaları production manifestine eklenmez", {
  asset_env <- .source_ui_asset_config_for_tests()
  root <- resolve_repo_root_for_tests()

  js_paths <- asset_env$ui_asset_all_js()
  css_paths <- asset_env$ui_asset_all_css()
  all_manifest_paths <- c(js_paths, css_paths)

  smoke_only_paths <- c(
    "smoke/ux-smoke.html",
    "smoke/ux-smoke-probes.js"
  )

  expect_true(all(file.exists(file.path(root, "www", smoke_only_paths))))

  expect_equal(
    intersect(smoke_only_paths, all_manifest_paths),
    character(0),
    info = "Smoke-only UX harness/probe dosyaları R/config_ui_assets.R production manifestine eklenmemelidir."
  )

  expect_false(
    any(grepl("ux-smoke-probes\\.js$", all_manifest_paths, perl = TRUE)),
    info = "www/smoke/ux-smoke-probes.js yalnızca /smoke/ux-smoke.html tarafından yüklenmelidir."
  )

  expect_true("js/streaming_markdown_safety.js" %in% js_paths)
  expect_true("js/markdown-parser.js" %in% js_paths)
  expect_true("js/streaming_manager.js" %in% js_paths)

  expect_lt(
    .ui_asset_contract_position(js_paths, "js/streaming_markdown_safety.js"),
    .ui_asset_contract_position(js_paths, "js/markdown-parser.js")
  )

  expect_lt(
    .ui_asset_contract_position(js_paths, "js/markdown-parser.js"),
    .ui_asset_contract_position(js_paths, "js/streaming_manager.js")
  )

  explicit_rules <- vapply(
    asset_env$ui_asset_js_order_rules,
    function(rule) paste(rule, collapse = " -> "),
    character(1)
  )

  expect_true(
    "js/streaming_markdown_safety.js -> js/markdown-parser.js" %in% explicit_rules,
    info = "Streaming markdown safety yükleme sırası açık sıra kuralı olarak kalmalıdır."
  )

  expect_true(
    "js/markdown-parser.js -> js/streaming_manager.js" %in% explicit_rules,
    info = "Markdown parser, streaming manager'dan önce açık sıra kuralıyla korunmalıdır."
  )
})

test_that("ui.R varlık listesini helper üzerinden kullanır", {
  ui_text <- .read_repo_text_ui_asset_contract("ui.R")
  manifest_text <- .read_repo_text_ui_asset_contract("R/config_source_manifest.R")
  health_module_text <- .read_repo_text_ui_asset_contract("R/module_health.R")

  expect_true(grepl("ui_asset_tags\\s*\\(", ui_text, perl = TRUE))
  expect_false(grepl('tags\\$script\\(src = "js/claude_code\\.js"', ui_text, perl = TRUE))
  expect_false(grepl('tags\\$link\\(rel = "stylesheet", type = "text/css", href = "css/fonts\\.css"', ui_text, perl = TRUE))
  expect_false(grepl('tags\\$script\\(src = "js/health_dashboard\\.js"', health_module_text, perl = TRUE))
  expect_false(grepl('tags\\$link\\(rel = "stylesheet", type = "text/css", href = "css/health_dashboard\\.css"', health_module_text, perl = TRUE))
  expect_true(grepl('"R/config_ui_assets.R"', manifest_text, fixed = TRUE))
})

test_that("yüklenen JS dosyalarında Shiny özel mesaj handler adları tekildir", {
  asset_env <- .source_ui_asset_config_for_tests()
  js_paths <- asset_env$ui_asset_all_js()
  app_js_paths <- js_paths[grepl("^(js|lib|codemirror)/", js_paths)]

  handler_names <- unlist(
    lapply(app_js_paths, .ui_asset_contract_handler_names),
    use.names = FALSE
  )

  duplicate_handlers <- sort(unique(handler_names[duplicated(handler_names)]))

  expect_equal(duplicate_handlers, character(0))
})