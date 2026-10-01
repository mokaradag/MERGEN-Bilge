# İstemci tercih sürümü ve yeniden bağlanma davranışı.

test_that("istemci durum regresyonları Node ile çalışır", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "Node kullanılamıyor")
  script <- file.path(resolve_repo_root_for_tests(), "tests", "scripts", "client_state_regressions.js")
  sonuc <- system2(node, shQuote(script), stdout = TRUE, stderr = TRUE)
  expect_null(attr(sonuc, "status"), info = paste(sonuc, collapse = "\n"))
  expect_match(paste(sonuc, collapse = "\n"), "regressions passed")
})
