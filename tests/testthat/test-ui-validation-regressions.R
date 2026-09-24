# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-validation-regressions.R
# Açıklama: PR #705 incelemesinden çıkan, birbirinden bağımsız arayüz/doğrulama
#           sözleşmesi gerilemelerini doğrular: selectize ipucu bastırma, mesaj
#           uzunluk tavanı taşması, MCP ikinci geçiş token ayarı, gerçek
#           CodeMirror çekirdeği/uzun kod çizimi ve ayar ipuçlarının erişilebilir
#           açıklamalara bağlanması. Vendored varlık ayrıntıları
#           test-codemirror-vendored-assets-contract.R içindedir.
#
#           BU DOSYA VARLIK/ALIAS ÇÖZÜMLEMESİNİ KAPSAMAZ. Eskiden
#           `test-pk-entity-alias-regressions.R` adını taşıyordu; ad ve başlık
#           alias kapsamı vaat ederken içerik tamamen ilgisizdi, yani gerçek
#           bir alias gerilemesi bu paket yeşilken geçebilirdi. Alias sözleşmesi
#           artık AYNI ADI taşıyan ayrı dosyada gerçekten test edilir.
#
#           Repo kökü çözümlemesi ortak `resolve_repo_root_for_tests()`
#           yardımcısını kullanır; yerel kopya kaldırılmıştır.
# ==============================================================================

repo_root_pk_entity_alias <- resolve_repo_root_for_tests()

.read_pk_entity_alias <- function(...) {
  paste(readLines(
    file.path(repo_root_pk_entity_alias, ...),
    warn = FALSE,
    encoding = "UTF-8"
  ), collapse = "\n")
}

test_that("Selectize açıkken yapılandırma ipucu bastırılır", {
  css <- .read_pk_entity_alias("www", "css", "settings_page.css")

  expect_true(grepl(
    ":has\\(\\.selectize-input\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
  expect_false(grepl(
    ":has\\(\\.selectize-control\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
})

test_that("mesaj güvenlik tavanı tamsayı taşmasında varsayılana düşer", {
  validation_env <- new.env(parent = baseenv())
  source(
    file.path(repo_root_pk_entity_alias, "R", "helpers_db_validation.R"),
    local = validation_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "3000000000"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
    expect_true(validation_env$validate_message_content("geçerli ileti"))
  })

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "Inf"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
  })
})

test_that("MCP ikinci geçişi çıktı token ortam ayarını uygular", {
  second_pass_env <- new.env(parent = baseenv())
  source(
    file.path(repo_root_pk_entity_alias, "R", "helpers_llm_worker_second_pass.R"),
    local = second_pass_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      12000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(
        list(max_output_tokens = 9000L)
      ),
      9000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "3000000000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      32768L
    )
  })
})

test_that("gerçek CodeMirror uzun kodu tam çizer, yalnızca genişlik değişince yeniler", {
  manager_js <- .read_pk_entity_alias("www", "js", "codemirror-manager.js")

  # Otomatik yükseklikte sanallaştırma uzun kodu kırpıyordu; tüm belge çizilir.
  expect_true(grepl("viewportMargin: Infinity", manager_js, fixed = TRUE))
  # Gerçek motorda refresh() tüm satırları yeniden çizer: başlatma sonrası
  # zamanlayıcı yağmuru ve editör başına pencere resize dinleyicisi olmamalı.
  # Ok/fonksiyon geri çağrısı (süslü parantezli ya da değil) ve her tırnak biçimi.
  zamanlayici <- "setTimeout\\([^;]{0,120}?editor\\.refresh\\s*\\("
  yeniden_boyut <- "addEventListener\\(\\s*['\"`]resize['\"`]"
  for (yasak in c("setTimeout(() => editor.refresh(), 10)",
                  "setTimeout(() => { editor.refresh(); }, 50)",
                  "setTimeout(function () { editor.refresh(); })")) {
    expect_true(grepl(zamanlayici, yasak, perl = TRUE), info = yasak)
  }
  for (yasak in c("addEventListener('resize', f)", "window.addEventListener(\"resize\", f)")) {
    expect_true(grepl(yeniden_boyut, yasak, perl = TRUE), info = yasak)
  }
  expect_false(grepl(zamanlayici, manager_js, perl = TRUE))
  expect_false(grepl(yeniden_boyut, manager_js, perl = TRUE))
  expect_true(grepl("new ResizeObserver(", manager_js, fixed = TRUE))
  # JSX modu vendored değildir: jsx/tsx etiketleri JS/TS moduna eşlenip yanlış
  # vurgulanmaz, düz metin kalır.
  expect_false(grepl("\\b(jsx|tsx)\\s*:", manager_js, perl = TRUE))
  expect_true(grepl("measuredWidths.get(wrapper) === width", manager_js, fixed = TRUE))
})

test_that("CodeMirror çekirdeği vendored gerçek dağıtımdır; uyumluluk motoru yoktur", {
  manifest <- .read_pk_entity_alias("R", "config_ui_assets.R")

  expect_true(grepl('"codemirror/codemirror.min.js"', manifest, fixed = TRUE))
  expect_true(grepl('"codemirror/codemirror.min.css"', manifest, fixed = TRUE))
  expect_false(grepl("codemirror_compat", manifest, fixed = TRUE))
  expect_false(file.exists(file.path(repo_root_pk_entity_alias, "www", "js", "codemirror_compat.js")))
  expect_false(file.exists(file.path(repo_root_pk_entity_alias, "www", "css", "codemirror_compat.css")))
})

test_that("yapılandırma ipuçları erişilebilir açıklamalara bağlanır", {
  settings_js <- .read_pk_entity_alias("www", "js", "settings_model_info.js")

  expect_true(grepl("[data-settings-tooltip]", settings_js, fixed = TRUE))
  expect_true(grepl("aria-describedby", settings_js, fixed = TRUE))
  expect_true(grepl("settings-tooltip-sr", settings_js, fixed = TRUE))
  expect_true(grepl("syncSettingsTooltipAccessibility(document)", settings_js, fixed = TRUE))
})
