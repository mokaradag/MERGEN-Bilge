# ==============================================================================
# Dosya Yolu: tests/testthat/test-codemirror-vendored-assets-contract.R
# Açıklama: Kod bloklarının sözdizimi vurgulaması GERÇEK, çevrimdışı CodeMirror 5
#           dağıtımına dayanır. Bu dosya şu gerilemeyi engeller: manifest bir
#           sahte/uyumluluk motorunu yükler, www/codemirror altındaki mod/tema/
#           eklenti dosyaları tek satırlık yer tutuculara döner ya da yönetici
#           (codemirror-manager.js) yüklenmemiş bir modu "destekleniyor" diye
#           ilan eder. Çalışma zamanı belirteç/katlama/kopyalama davranışı
#           test-codemirror-rendering-browser-behavior.R içinde gerçek tarayıcıda
#           doğrulanır.
# ==============================================================================

.cm_root <- function() resolve_repo_root_for_tests()

.cm_read <- function(...) {
  path <- file.path(.cm_root(), ...)
  size <- file.info(path)$size
  if (is.na(size) || size <= 0) return("")
  raw <- readBin(path, what = "raw", n = size)
  enc2utf8(iconv(list(raw), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
}

.cm_asset_env <- function() {
  env <- new.env(parent = globalenv())
  for (f in c("R/config_ui_assets.R", "R/config_ui_asset_validators.R")) {
    source(file.path(.cm_root(), f), encoding = "UTF-8", local = env)
  }
  env
}

# Yer tutucu imzaları (eski sahte dosyalardan). Gerçek çekirdekte geçen
# "specialCharPlaceholder" gibi adlar yanlış pozitif üretmesin diye tam
# ifadeler aranır.
.cm_placeholder_markers <- c(
  "MERGEN offline", "placeholder asset", "extension placeholder",
  "Replace with vendored", "mergen-offline-compat"
)

.cm_sha256 <- function(path) {
  if (exists("sha256sum", envir = asNamespace("tools"), inherits = FALSE)) {
    return(unname(tools::sha256sum(path)))
  }
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(path, algo = "sha256", file = TRUE))
  }
  NA_character_
}

test_that("manifest gerçek çekirdeği modlardan, modlar eklentilerden ve yöneticiden önce yükler", {
  env <- .cm_asset_env()
  css <- env$ui_asset_all_css()
  js <- env$ui_asset_all_js()

  expect_identical(env$ui_asset_js_groups$codemirror_core, "codemirror/codemirror.min.js")
  expect_identical(env$ui_asset_css_groups$codemirror[[1]], "codemirror/codemirror.min.css")
  expect_true("codemirror/theme/material-darker.min.css" %in% css)
  expect_false(any(grepl("compat", c(css, js), fixed = TRUE)))

  core <- match("codemirror/codemirror.min.js", js)
  modes <- match(env$ui_asset_js_groups$codemirror_modes, js)
  addons <- match(env$ui_asset_js_groups$codemirror_addons, js)
  manager <- match("js/codemirror-manager.js", js)
  expect_true(all(core < modes))
  expect_true(all(core < addons))
  expect_true(max(c(modes, addons)) < manager)
  # Tanım anında defineSimpleMode çağıran modlar eklentiden sonra gelir.
  simple <- match("codemirror/addon/mode/simple.min.js", js)
  expect_lt(simple, match("codemirror/mode/rust.min.js", js))
  expect_lt(simple, match("codemirror/mode/dockerfile.min.js", js))

  expect_silent(env$ui_asset_validate(root = .cm_root(), check_files = TRUE))
})

test_that("manifestteki her CodeMirror dosyası yer tutucu değil, gerçek upstream içeriktir", {
  env <- .cm_asset_env()
  paths <- grep("^codemirror/", c(env$ui_asset_all_css(), env$ui_asset_all_js()), value = TRUE)
  expect_gt(length(paths), 30L)

  for (p in paths) {
    txt <- .cm_read("www", p)
    for (marker in .cm_placeholder_markers) {
      expect_false(grepl(marker, txt, fixed = TRUE), info = paste(p, marker))
    }
    # Upstream MIT başlığı (JS'te "copyright", CSS'te kaynak satırı) korunur.
    expect_true(grepl("Marijn Haverbeke", txt, fixed = TRUE), info = p)
    if (startsWith(p, "codemirror/mode/")) {
      expect_true(grepl("\\.define(Mode|MIME|SimpleMode)\\(\"", txt, perl = TRUE) ||
                    grepl("modeInfo", txt, fixed = TRUE), info = p)
    }
  }

  core <- .cm_read("www", "codemirror", "codemirror.min.js")
  expect_gt(nchar(core, type = "bytes"), 100000L)
  expect_true(grepl("5.65.21", core, fixed = TRUE))
  expect_true(grepl("defineMode", core, fixed = TRUE))
  theme <- .cm_read("www", "codemirror", "theme", "material-darker.min.css")
  expect_true(grepl(".cm-s-material-darker .cm-keyword", theme, fixed = TRUE))
  expect_true(grepl(".cm-s-material-darker.CodeMirror", theme, fixed = TRUE))
  for (helper in c("brace", "indent", "xml", "markdown")) {
    expect_true(any(vapply(
      grep("^codemirror/addon/fold/", paths, value = TRUE),
      function(p) grepl(sprintf("registerHelper\\(\"fold\",\\s*\"%s\"", helper), .cm_read("www", p), perl = TRUE),
      logical(1)
    )), info = helper)
  }
  expect_true(grepl("registerGlobalHelper(\"fold\",\"comment\"",
                    .cm_read("www", "codemirror", "addon", "fold", "comment-fold.min.js"), fixed = TRUE))
})

test_that("README'deki SHA-256 kaynak kaydı vendored dosyalarla birebir eşleşir", {
  readme <- strsplit(.cm_read("www", "codemirror", "README.md"), "\n", fixed = TRUE)[[1]]
  rows <- regmatches(readme, regexec("^\\| `([^`]+)` \\| `[^`]+` \\| [a-z-]+ \\| `([0-9a-f]{64})` \\|$", readme))
  rows <- Filter(function(m) length(m) == 3L, rows)
  expect_gt(length(rows), 30L)

  env <- .cm_asset_env()
  manifest <- sub("^codemirror/", "", grep("^codemirror/", c(env$ui_asset_all_css(), env$ui_asset_all_js()), value = TRUE))
  listed <- vapply(rows, `[[`, character(1), 2L)
  expect_true(all(manifest %in% listed))
  expect_true("LICENSE" %in% listed)

  # Satır sonu dönüşümü özetleri bozmasın (Windows checkout).
  expect_true(grepl("www/codemirror/** -text", .cm_read(".gitattributes"), fixed = TRUE))

  skip_if(is.na(.cm_sha256(file.path(.cm_root(), "www", "codemirror", "LICENSE"))),
          "SHA-256 hesaplayıcı yok (tools::sha256sum / digest).")
  for (m in rows) {
    expect_identical(.cm_sha256(file.path(.cm_root(), "www", "codemirror", m[[2]])), m[[3]], info = m[[2]])
  }
})

test_that("yöneticinin ilan ettiği her dil ve katlama yardımcısı gerçekten yüklenir", {
  manager <- .cm_read("www", "js", "codemirror-manager.js")
  block <- regmatches(manager, regexpr("const LANG_CONFIG = \\{[^;]*\\};", manager, perl = TRUE))
  expect_length(block, 1L)
  specs <- regmatches(block, gregexpr("mode: '([^']+)'", block, perl = TRUE))[[1]]
  specs <- sub("^mode: '([^']+)'$", "\\1", specs)
  expect_gt(length(specs), 30L)

  env <- .cm_asset_env()
  mode_paths <- c("codemirror/codemirror.min.js", env$ui_asset_js_groups$codemirror_modes)
  mode_text <- paste(vapply(mode_paths, function(p) .cm_read("www", p), character(1)), collapse = "\n")
  # clike MIME türlerini döngüyle kaydeder (def([...])); bu yüzden tanım
  # çağrısı yerine MIME/mod adının yüklenen bir mod dosyasında geçtiği
  # doğrulanır. Gerçek çözümleme tarayıcı testinde yapılır.
  for (spec in setdiff(specs, "text/plain")) {
    expect_true(grepl(sprintf("\"%s\"", spec), mode_text, fixed = TRUE), info = spec)
  }

  folds <- unique(unlist(regmatches(block, gregexpr("'(brace|indent|comment|xml|markdown)'", block, perl = TRUE))))
  addon_text <- paste(vapply(env$ui_asset_js_groups$codemirror_addons, function(p) .cm_read("www", p), character(1)), collapse = "\n")
  for (f in gsub("'", "", folds, fixed = TRUE)) {
    expect_true(grepl(sprintf("Helper\\(\"fold\",\\s*\"%s\"", f), addon_text, perl = TRUE), info = f)
  }
  # Anlamsız uyumluluk kalıntısı (katlamayan gutterClick kancası) kalmadı.
  expect_false(grepl("_isFolding", manager, fixed = TRUE))
})

test_that("koyu ve açık tema editör zeminleri çelişmez; satırlar zemini devralır", {
  custom <- .cm_read("www", "css", "codemirror-custom.css")
  light <- .cm_read("www", "css", "theme_light_core.css")

  expect_true(grepl("\\.CodeMirror \\{[^}]*background: #1e1e1e !important", custom, perl = TRUE))
  expect_true(grepl("html\\[data-theme=\"light\"\\] \\.CodeMirror \\{[^}]*background: #f6f8fa !important", light, perl = TRUE))
  # Açık temadaki genel koyu `pre` kuralı editör satırlarına sızmaz.
  expect_true(grepl("html\\[data-theme=\"light\"\\] \\.CodeMirror pre,[^{]*\\{[^}]*background: transparent !important",
                    custom, perl = TRUE))

  css_dir <- file.path(.cm_root(), "www", "css")
  for (f in list.files(css_dir, pattern = "\\.css$", full.names = TRUE)) {
    txt <- gsub("(?s)/\\*.*?\\*/", "", .cm_read("www", "css", basename(f)), perl = TRUE)
    rules <- regmatches(txt, gregexpr("[^{}]*CodeMirror-line[^{}]*\\{[^}]*\\}", txt, perl = TRUE))[[1]]
    for (r in rules) {
      bg <- regmatches(r, regexpr("background(-color)?:\\s*[^;]+", r, perl = TRUE))
      if (length(bg)) expect_true(grepl("transparent", bg, fixed = TRUE), info = paste(basename(f), r))
    }
  }

  # Token renkleri iki temada da tanımlı ve düz metinden ayrışır.
  for (token in c("keyword", "def", "variable", "string", "number", "comment", "operator")) {
    expect_true(grepl(sprintf("\\.CodeMirror \\.cm-%s \\{ color: #[0-9a-f]{6}", token), custom, perl = TRUE), info = token)
    expect_true(grepl(sprintf("html\\[data-theme=\"light\"\\] \\.cm-%s[ ,]", token), light, perl = TRUE), info = token)
  }
})
