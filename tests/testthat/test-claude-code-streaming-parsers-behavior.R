# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-streaming-parsers-behavior.R
# Açıklama: R/helpers_claude_code_streaming.R saf akış-ayrıştırma yardımcılarının
#           DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu):
#             - parse_tool_use_nesne (tool_use nesnesini normalize alanlara açar)
#             - cc_collect_covered_tool_paths (kapsanan yol setini küçük harf tekiller)
#             - cc_synthesize_tool_uses_from_downloads (kapsanmayan dosyalar için
#               additif sentetik Write üretir; CLAUDE.md sözleşmesi)
#           Parse edilmiş R listeleri alınır; processx/jsonlite/canlı CLI GEREKMEZ.
#           Sentetik tool-use yan etkisi (sendCustomMessage) NULL session ile
#           güvenle tryCatch'lenir; test yalnızca dönen değeri doğrular.
# ==============================================================================

.ccstream_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("parse_tool_use_nesne",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_streaming.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# parse_tool_use_nesne
# ------------------------------------------------------------------------------
testthat::test_that("parse_tool_use_nesne Write nesnesini dosya yolu/içeriğine açar", {
  .ccstream_source_once()
  p <- parse_tool_use_nesne(list(
    name = "Write", id = "t2",
    input = list(file_path = "/a/b.txt", content = "merhaba")
  ))
  testthat::expect_identical(p$tip, "tool_use")
  testthat::expect_identical(p$arac_id, "t2")
  testthat::expect_identical(p$arac_adi, "Write")
  testthat::expect_identical(p$arac_turu, "file_write")
  testthat::expect_identical(p$dosya_yolu, "/a/b.txt")
  testthat::expect_identical(p$dosya_icerigi, "merhaba")
  testthat::expect_identical(p$komut, "")
})

testthat::test_that("parse_tool_use_nesne Bash nesnesini komuta açar (command/cmd alias)", {
  .ccstream_source_once()
  b1 <- parse_tool_use_nesne(list(name = "Bash", id = "t1", input = list(command = "ls -la")))
  testthat::expect_identical(b1$arac_turu, "bash")
  testthat::expect_identical(b1$komut, "ls -la")
  testthat::expect_identical(b1$dosya_yolu, "")

  # cmd alias da komut olarak okunur.
  b2 <- parse_tool_use_nesne(list(name = "Bash", input = list(cmd = "pwd")))
  testthat::expect_identical(b2$komut, "pwd")
  testthat::expect_identical(b2$arac_id, "")   # id yoksa boş
})

testthat::test_that("parse_tool_use_nesne path/new_content alias'larını ve boş nesneyi işler", {
  .ccstream_source_once()
  r <- parse_tool_use_nesne(list(name = "Read", input = list(path = "/x.txt")))
  testthat::expect_identical(r$dosya_yolu, "/x.txt")

  e <- parse_tool_use_nesne(list(name = "Edit", input = list(new_content = "yeni")))
  testthat::expect_identical(e$dosya_icerigi, "yeni")

  bos <- parse_tool_use_nesne(list())
  testthat::expect_identical(bos$arac_adi, "")
  testthat::expect_identical(bos$arac_id, "")
  testthat::expect_identical(bos$komut, "")
  testthat::expect_identical(bos$dosya_yolu, "")
  testthat::expect_true(is.list(bos$girdi))
})

# ------------------------------------------------------------------------------
# cc_collect_covered_tool_paths
# ------------------------------------------------------------------------------
testthat::test_that("cc_collect_covered_tool_paths boş girdide character(0) döner", {
  .ccstream_source_once()
  testthat::expect_identical(cc_collect_covered_tool_paths(NULL), character(0))
  testthat::expect_identical(cc_collect_covered_tool_paths(list()), character(0))
})

testthat::test_that("cc_collect_covered_tool_paths yolları küçük harfe indirip tekiller", {
  .ccstream_source_once()
  tool_uses <- list(
    list(name = "Write", input = list(file_path = "/A/B.txt")),
    list(name = "Edit",  input = list(path = "/a/b.txt")),       # küçük harf eşi -> tekille
    list(name = "Write", input = list(new_file = "/C/D.md")),
    "liste_degil",                                                # liste olmayan -> atlanır
    list(name = "Write", input = list(file = "/E/F.csv"))
  )
  donen <- cc_collect_covered_tool_paths(tool_uses)
  testthat::expect_setequal(donen, c("/a/b.txt", "/c/d.md", "/e/f.csv"))
})

# ------------------------------------------------------------------------------
# cc_synthesize_tool_uses_from_downloads
# ------------------------------------------------------------------------------
testthat::test_that("cc_synthesize_tool_uses_from_downloads boş/hepsi-kapsanan girdide boş liste döner", {
  .ccstream_source_once()
  ayr <- list(tool_uses = list(list(name = "Write", input = list(file_path = "/a/b.txt"))))

  # Üretilen dosya yok.
  testthat::expect_identical(
    cc_synthesize_tool_uses_from_downloads(NULL, NULL, NULL, ayr, list()),
    list()
  )
  # Üretilen dosya zaten kapsanıyor (küçük harf eşleşmesi).
  out <- cc_synthesize_tool_uses_from_downloads(
    NULL, NULL, NULL, ayr,
    list(list(original_path = "/A/B.txt"))
  )
  testthat::expect_identical(out, list())
})

testthat::test_that("cc_synthesize_tool_uses_from_downloads kapsanmayan dosya için additif Write üretir", {
  .ccstream_source_once()
  ayr <- list(tool_uses = list(list(name = "Write", input = list(file_path = "/a/b.txt"))))
  out <- cc_synthesize_tool_uses_from_downloads(
    NULL, NULL, NULL, ayr,
    list(
      list(original_path = "/a/b.txt"),        # kapsanan -> atlanır
      list(original_path = "/c/YeniDoc.txt")   # kapsanmayan -> sentetik
    )
  )
  testthat::expect_length(out, 1L)
  testthat::expect_identical(out[[1]]$name, "Write")
  testthat::expect_identical(out[[1]]$input$file_path, "/c/YeniDoc.txt")
  testthat::expect_true(grepl("^synth_write_", out[[1]]$id))
})
