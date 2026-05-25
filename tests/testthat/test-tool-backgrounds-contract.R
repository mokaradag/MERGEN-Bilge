# ==============================================================================
# Dosya Yolu: tests/testthat/test-tool-backgrounds-contract.R
# Açıklama: Sohbet arka plan animasyon katmanı (heptagon + snippet'ler)
#           için kritik istemci/sunucu sözleşmelerini korur.
#
# Korunan sözleşmeler:
#   1. ui.R erken bir tarihte boş .tool-bg-layer placeholder'i render
#      ediyor olabilir; bu nedenle ensureLayer() ERKEN DONUS yapmamali,
#      her cagride heptagon + snippet alt katmanlarini tamamlamalidir.
#   2. www/js/tool_backgrounds.js setToolBackgroundFamily custom message
#      handler'i kayitli olmalidir.
#   3. R/module_quick_actions.R quick action handler'i setToolBackgroundFamily
#      mesajini sunucu tarafindan otoriter olarak gondermelidir.
#   4. R/server_observers_chat_ui.R "Yeni Söyleşi" akisinda
#      setToolBackgroundFamily clear=TRUE gondermelidir.
#   5. Aile -> action_id eslemeleri ACTION_TO_FAMILY dogru tutmalidir.
# ==============================================================================

.find_repo_root_tool_bg <- function() {
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
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_tool_bg <- function(rel_path) {
  repo_root <- .find_repo_root_tool_bg()
  full_path <- file.path(repo_root, rel_path)

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

test_that("ui.R icindeki bos .tool-bg-layer placeholder'i sozlesme kabul edilir", {
  ui_txt <- .read_repo_text_tool_bg("ui.R")
  expect_true(nzchar(ui_txt), info = "ui.R okunamadi.")

  # ui.R erken bir #chat_main_wrapper > .tool-bg-layer placeholder'i render
  # ediyor olabilir; bu sozlesme test ensureLayer'in bu placeholder'i
  # tamamlamasi gerektiginin temelini olusturur.
  expect_true(
    grepl('class = "tool-bg-layer"', ui_txt, fixed = TRUE) ||
      grepl('class = \\"tool-bg-layer\\"', ui_txt, fixed = TRUE) ||
      grepl("tool-bg-layer", ui_txt, fixed = TRUE),
    info = "ui.R araç arka plan katmani placeholder'ini render etmelidir."
  )
})

test_that("tool_backgrounds.js ensureLayer() idempotenttir; ERKEN donus yapmaz", {
  txt <- .read_repo_text_tool_bg("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  # Eski regresyon: layer mevcutsa "if (layer) return layer;" ile cocuksuz
  # placeholder geri donuluyordu. Yeni kod ensureLayer'i her zaman heptagon
  # ve snippets ile tamamlamalidir.
  expect_false(
    grepl("if (layer) return layer;", txt, fixed = TRUE),
    info = paste(
      "ensureLayer() mevcut layer icin ERKEN donus yapmamalidir; aksi halde",
      "ui.R icindeki bos placeholder heptagon/snippet alamadan kalir."
    )
  )

  expect_true(
    grepl("function ensureHeptagonLayer(", txt, fixed = TRUE),
    info = "ensureHeptagonLayer() yardimcisi tanimli olmalidir."
  )

  expect_true(
    grepl("function ensureSnippetsHolder(", txt, fixed = TRUE),
    info = "ensureSnippetsHolder() yardimcisi tanimli olmalidir."
  )

  expect_true(
    grepl("ensureHeptagonLayer(layer);", txt, fixed = TRUE),
    info = "ensureLayer() her cagride ensureHeptagonLayer'i tetiklemelidir."
  )

  expect_true(
    grepl("ensureSnippetsHolder(layer);", txt, fixed = TRUE),
    info = "ensureLayer() her cagride ensureSnippetsHolder'i tetiklemelidir."
  )
})

test_that("tool_backgrounds.js heptagon SVG olusturma ve snippet kayit yollarini icerir", {
  txt <- .read_repo_text_tool_bg("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  expect_true(
    grepl("function buildHeptagonSvg(", txt, fixed = TRUE),
    info = "buildHeptagonSvg() yedigen SVG cizimini tanimlamalidir."
  )

  expect_true(
    grepl(".tool-bg-heptagon", txt, fixed = TRUE),
    info = "tool_backgrounds.js .tool-bg-heptagon yardimcisini icermelidir."
  )

  expect_true(
    grepl(".tool-bg-snippets", txt, fixed = TRUE),
    info = "tool_backgrounds.js .tool-bg-snippets yardimcisini icermelidir."
  )
})

test_that("tool_backgrounds.js setToolBackgroundFamily ve toggleToolBackgrounds handler'lari kayitlidir", {
  txt <- .read_repo_text_tool_bg("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  expect_true(
    grepl("'setToolBackgroundFamily'", txt, fixed = TRUE),
    info = paste(
      "tool_backgrounds.js 'setToolBackgroundFamily' Shiny custom message",
      "handler'i icermelidir; sunucu tarafi aktivasyon mesajidir."
    )
  )

  expect_true(
    grepl("'toggleToolBackgrounds'", txt, fixed = TRUE),
    info = "tool_backgrounds.js 'toggleToolBackgrounds' handler'i icermelidir."
  )
})

test_that("ACTION_TO_FAMILY eslemesi her quick action'i kapsar", {
  txt <- .read_repo_text_tool_bg("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  expected_pairs <- list(
    c("'coding-support'",    "'coding'"),
    c("'project-process'",   "'process'"),
    c("'app-expert'",        "'app_expert'"),
    c("'resource-analysis'", "'sql_analysis'"),
    c("'excel-analysis'",    "'mcp_excel'"),
    c("'image-creation'",    "'image'"),
    c("'summarization'",     "'summarization'")
  )

  for (pair in expected_pairs) {
    action_token <- pair[[1]]
    family_token <- pair[[2]]
    expect_true(
      grepl(action_token, txt, fixed = TRUE),
      info = sprintf("ACTION_TO_FAMILY eslemesinde %s eksik.", action_token)
    )
    expect_true(
      grepl(family_token, txt, fixed = TRUE),
      info = sprintf("ACTION_TO_FAMILY hedef ailesinde %s eksik.", family_token)
    )
  }
})

test_that("module_quick_actions.R setToolBackgroundFamily sunucu mesajini gonderir", {
  qa_txt <- .read_repo_text_tool_bg("R/module_quick_actions.R")
  expect_true(nzchar(qa_txt), info = "R/module_quick_actions.R okunamadi.")

  expect_true(
    grepl('"setToolBackgroundFamily"', qa_txt, fixed = TRUE),
    info = paste(
      "R/module_quick_actions.R setToolBackgroundFamily mesajini sunucu",
      "tarafindan otoriter olarak gondermelidir; istemci tarafi click listener",
      "bagimsiz olarak da kalir, ancak gercek aktivasyon yetkisi sunucudadir."
    )
  )

  # Mesajin handle_tool_action icinde gonderildigi anchor
  expect_true(
    grepl("tool_cfg$family", qa_txt, fixed = TRUE),
    info = "Quick action handler tool_cfg$family degerini family parametresi olarak kullanmalidir."
  )
})

test_that("server_observers_chat_ui.R 'Yeni Söyleşi' setToolBackgroundFamily clear gonderir", {
  txt <- .read_repo_text_tool_bg("R/server_observers_chat_ui.R")
  expect_true(nzchar(txt), info = "R/server_observers_chat_ui.R okunamadi.")

  expect_true(
    grepl('"setToolBackgroundFamily"', txt, fixed = TRUE),
    info = paste(
      "Yeni Söyleşi akisi sunucu tarafindan setToolBackgroundFamily(clear=TRUE)",
      "gondermelidir; aksi halde eski araç arka plan animasyonu yeni",
      "soyleside kalintilanabilir."
    )
  )

  expect_true(
    grepl("clear = TRUE", txt, fixed = TRUE),
    info = "Yeni Söyleşi akisi clear = TRUE parametresini gondermelidir."
  )
})

test_that("config_ui_assets.R tool_backgrounds CSS/JS varliklarini icerir", {
  txt <- .read_repo_text_tool_bg("R/config_ui_assets.R")
  expect_true(nzchar(txt), info = "R/config_ui_assets.R okunamadi.")

  expect_true(
    grepl('"css/tool_backgrounds.css"', txt, fixed = TRUE),
    info = "Manifest css/tool_backgrounds.css icermelidir."
  )

  expect_true(
    grepl('"js/tool_backgrounds.js"', txt, fixed = TRUE),
    info = "Manifest js/tool_backgrounds.js icermelidir."
  )
})
