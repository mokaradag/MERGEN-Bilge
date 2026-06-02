# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-plugins-scan-behavior.R
# Açıklama: R/helpers_claude_code_plugins.R ve R/config_claude_code_plugins.R
#           için DAVRANIŞSAL testler. Bu dosyalar daha önce hiçbir test
#           tarafından çağrılmıyordu.
#
#           Kapsam:
#           - detect_plugin_components() dizin tabanlı bileşen tespiti,
#           - config (claude_code_plugin_bilesenler) ile detector arasındaki
#             SENKRONİZASYON sözleşmesi (CLAUDE.md'de belgelenmiştir),
#           - scan_local_plugins() güvenlik ilkesi (kök dışı engellenir) ve
#             gerçek bilge_yolac_plugins/ dizininin taranması.
#
#           İnternet, CLI, DB veya Shiny sunucusu GEREKMEZ.
# ==============================================================================

.source_cc_plugins_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  if (!exists("%||%", envir = globalenv(), inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }

  # Log fonksiyonları için sessiz stub'lar (test çıktısını kirletmemek için).
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)

  # Güvenlik ilkesi yardımcıları (cc_policy_path_inside_roots) ayrı dosyada.
  source(
    file.path(repo_root, "R", "helpers_claude_code_path_policy.R"),
    encoding = "UTF-8",
    local = env
  )
  source(
    file.path(repo_root, "R", "config_claude_code_plugins.R"),
    encoding = "UTF-8",
    local = env
  )
  source(
    file.path(repo_root, "R", "helpers_claude_code_plugins.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

# ------------------------------------------------------------------------------
# detect_plugin_components: dizin tabanlı bileşen tespiti
# ------------------------------------------------------------------------------
testthat::test_that("detect_plugin_components mevcut alt dizinleri doğru anahtarlara çevirir", {
  env <- .source_cc_plugins_for_test()

  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "commands"))
  dir.create(file.path(tmp, "skills"))
  dir.create(file.path(tmp, "mcp"))

  bilesenler <- env$detect_plugin_components(tmp)

  # mcp/ dizini 'mcp_servers' anahtarına çevrilmelidir.
  testthat::expect_setequal(bilesenler, c("commands", "skills", "mcp_servers"))
})

testthat::test_that("detect_plugin_components bileşenleri sabit (deterministik) sırada döndürür", {
  env <- .source_cc_plugins_for_test()

  tmp <- withr::local_tempdir()
  for (d in c("templates", "hooks", "agents", "commands", "skills", "mcp")) {
    dir.create(file.path(tmp, d))
  }

  bilesenler <- env$detect_plugin_components(tmp)

  testthat::expect_identical(
    bilesenler,
    c("commands", "agents", "skills", "hooks", "mcp_servers", "templates")
  )
})

testthat::test_that("detect_plugin_components bileşen yoksa boş karakter vektörü döndürür", {
  env <- .source_cc_plugins_for_test()

  tmp <- withr::local_tempdir()
  bilesenler <- env$detect_plugin_components(tmp)

  testthat::expect_identical(bilesenler, character(0))
})

# ------------------------------------------------------------------------------
# SENKRONİZASYON sözleşmesi: detector anahtarları config ile hizalı kalmalı.
# CLAUDE.md: "If a new component type is added, update BOTH
# claude_code_plugin_bilesenler ve detect_plugin_components()."
# ------------------------------------------------------------------------------
testthat::test_that("detect_plugin_components anahtarları config (bilesenler) ile senkron", {
  env <- .source_cc_plugins_for_test()

  tmp <- withr::local_tempdir()
  for (d in c("commands", "agents", "skills", "hooks", "mcp", "templates")) {
    dir.create(file.path(tmp, d))
  }
  detector_keys <- env$detect_plugin_components(tmp)
  config_keys <- names(env$claude_code_plugin_bilesenler)

  # Detector'ın üretebildiği her anahtar config'te tanımlı olmalı.
  testthat::expect_true(all(detector_keys %in% config_keys))
  # Config'teki her bileşen anahtarı detector tarafından da tespit edilebilmeli.
  testthat::expect_setequal(detector_keys, config_keys)
})

testthat::test_that("her plugin bileşeni Türkçe etiket, ikon ve açıklama içerir", {
  env <- .source_cc_plugins_for_test()

  for (anahtar in names(env$claude_code_plugin_bilesenler)) {
    bilesen <- env$claude_code_plugin_bilesenler[[anahtar]]
    testthat::expect_true(
      all(c("etiket", "ikon", "aciklama") %in% names(bilesen)),
      info = sprintf("%s bileşeni etiket/ikon/aciklama içermeli.", anahtar)
    )
    testthat::expect_true(nzchar(bilesen$etiket))
  }
})

# ------------------------------------------------------------------------------
# scan_local_plugins: güvenlik ilkesi ve gerçek dizin taraması
# ------------------------------------------------------------------------------
testthat::test_that("scan_local_plugins kök dışı dizini güvenlik ilkesiyle engeller", {
  env <- .source_cc_plugins_for_test()

  # bilge_yolac_plugins kökü dışındaki bir geçici dizin engellenmelidir.
  disari <- withr::local_tempdir()
  res <- env$scan_local_plugins(plugins_dir = disari)

  testthat::expect_false(res$success)
  testthat::expect_length(res$plugins, 0L)
  testthat::expect_true(nzchar(res$error))
})

testthat::test_that("scan_local_plugins gerçek bilge_yolac_plugins dizinini başarıyla tarar", {
  env <- .source_cc_plugins_for_test()
  repo_root <- resolve_repo_root_for_tests()

  # Çalışma dizini repo kökü olduğunda resolve_app_root() repo kökünü bulur ve
  # varsayılan plugins_dir gerçek bilge_yolac_plugins/ olur.
  res <- withr::with_dir(repo_root, env$scan_local_plugins())

  testthat::expect_true(res$success)
  testthat::expect_true(length(res$plugins) >= 1L)

  isimler <- vapply(res$plugins, function(p) p$name %||% "", character(1))
  testthat::expect_true(all(nzchar(isimler)))

  # 'office' eklentisi templates ve skills bileşenlerine sahip olmalı (repoda mevcut).
  office <- Filter(function(p) identical(basename(p$path), "office"), res$plugins)
  if (length(office) == 1L) {
    testthat::expect_true(all(c("skills", "templates") %in% office[[1]]$components))
  }
})

testthat::test_that("scan_local_plugins olmayan (kök içi) dizin için boş ama başarılı döner", {
  env <- .source_cc_plugins_for_test()
  repo_root <- resolve_repo_root_for_tests()

  # Kök içinde olup henüz var olmayan bir alt yol: engellenmez, boş döner.
  hayali <- file.path(repo_root, "bilge_yolac_plugins", "___olmayan_test_klasoru___")
  res <- withr::with_dir(repo_root, env$scan_local_plugins(plugins_dir = hayali))

  testthat::expect_true(res$success)
  testthat::expect_length(res$plugins, 0L)
})
