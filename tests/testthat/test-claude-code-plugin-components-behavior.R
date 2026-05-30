# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-plugin-components-behavior.R
# Açıklama: R/helpers_claude_code_plugins.R detect_plugin_components DAVRANIŞSAL
#           testleri. Bir plugin dizinindeki alt klasörlere göre bileşen
#           listesini (commands/agents/skills/hooks/mcp->mcp_servers/templates)
#           sabit sırada üretir. Saf dosya sistemi kontrolü; geçici dizinlerle
#           test edilir. Ağ/CLI/Shiny/jsonlite GEREKMEZ.
# ==============================================================================

.plgcomp_source_once <- function() {
  if (exists("detect_plugin_components", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_plugins.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Belirtilen alt dizinlerle geçici bir plugin dizini oluşturur.
.plgcomp_make <- function(subdirs = character(0)) {
  d <- tempfile("plg")
  dir.create(d)
  for (s in subdirs) dir.create(file.path(d, s))
  d
}

testthat::test_that("detect_plugin_components bileşensiz/yok dizinde character(0) döner", {
  .plgcomp_source_once()
  testthat::expect_identical(detect_plugin_components(.plgcomp_make(character(0))), character(0))
  # Var olmayan dizin de boş döner (hata yok).
  testthat::expect_identical(detect_plugin_components(tempfile("yok-dizin")), character(0))
})

testthat::test_that("detect_plugin_components tek bileşeni tespit eder", {
  .plgcomp_source_once()
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("commands")), "commands")
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("agents")), "agents")
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("skills")), "skills")
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("hooks")), "hooks")
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("templates")), "templates")
})

testthat::test_that("detect_plugin_components mcp dizinini 'mcp_servers' bileşenine eşler", {
  .plgcomp_source_once()
  # Dizin adı 'mcp' ama bileşen adı 'mcp_servers'.
  testthat::expect_identical(detect_plugin_components(.plgcomp_make("mcp")), "mcp_servers")
})

testthat::test_that("detect_plugin_components tüm bileşenleri sabit sırada döner", {
  .plgcomp_source_once()
  # Oluşturma sırası farklı olsa da çıktı kontrol sırasına göre sabittir.
  d <- .plgcomp_make(c("templates", "mcp", "hooks", "skills", "agents", "commands"))
  testthat::expect_identical(
    detect_plugin_components(d),
    c("commands", "agents", "skills", "hooks", "mcp_servers", "templates")
  )
})

testthat::test_that("detect_plugin_components alt kümeyi kontrol sırasında döndürür", {
  .plgcomp_source_once()
  # Yalnızca skills + templates: kontrol sırası korunur (skills önce).
  res <- detect_plugin_components(.plgcomp_make(c("templates", "skills")))
  testthat::expect_identical(res, c("skills", "templates"))
  testthat::expect_type(res, "character")
})
