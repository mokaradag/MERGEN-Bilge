# ==============================================================================
# Dosya Yolu: tests/testthat/test-settings-yapilandirma-ui-refactor-contract.R
# Açıklama: Yapılandırma sekmesi UI ayrımının kaynak sırası ve sorumluluk
#           sınırlarını korur. Uygulamayı başlatmaz.
# ==============================================================================

.find_repo_root_settings_ui_refactor <- function() {
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

.read_repo_text_settings_ui_refactor <- function(path) {
  repo_root <- .find_repo_root_settings_ui_refactor()
  full_path <- file.path(repo_root, path)

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

.extract_safe_source_paths_settings_ui_refactor <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

test_that("Yapılandırma UI dosyası sunucu modülünden önce yüklenir", {
  expect_source_manifest_order_for_tests(
    c(
      "R/module_settings_yapilandirma_ui.R",
      "R/module_settings_yapilandirma.R",
      "R/module_settings.R"
    ),
    label = "Yapılandırma UI/server source sırası bozulmuş:"
  )
})

test_that("Yapılandırma UI dosyası yalnızca UI sorumluluğunu taşır", {
  ui_text <- .read_repo_text_settings_ui_refactor("R/module_settings_yapilandirma_ui.R")

  expect_true(
    grepl("settingsYapilandirmaUIImpl <- function(id)", ui_text, fixed = TRUE),
    info = "UI uygulaması settingsYapilandirmaUIImpl(id) olarak ayrı dosyada tanımlanmalıdır."
  )

  required_anchors <- c(
    "Model Ayarları",
    "API Anahtarı Yönetimi",
    "Analiz Araçları",
    "Claude Code Yapılandırma",
    "Arayüz Ayarları",
    "Ses Ayarları",
    "AI Uzman Konuşması",
    "Görsel Oluşturma Ayarları",
    "Özetleme Ayarları",
    "Proje ve Kaynak Analizi Ayarları",
    "enable_background_music",
    "music_volume",
    "claude_code_timeout"
  )

  missing_anchors <- required_anchors[!vapply(
    required_anchors,
    function(anchor) grepl(anchor, ui_text, fixed = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_anchors,
    character(0),
    info = paste(
      "Yapılandırma UI dosyasında beklenen UI anchor'ları eksik:",
      paste(missing_anchors, collapse = ", ")
    )
  )

  forbidden_runtime_anchors <- c(
    "settingsYapilandirmaServer <- function",
    "moduleServer(",
    "observeEvent(",
    "reactiveVal(",
    "sendCustomMessage("
  )

  leaked_runtime_anchors <- forbidden_runtime_anchors[vapply(
    forbidden_runtime_anchors,
    function(anchor) grepl(anchor, ui_text, fixed = TRUE),
    logical(1)
  )]

  expect_equal(
    leaked_runtime_anchors,
    character(0),
    info = paste(
      "Yapılandırma UI dosyası runtime/server sorumluluğu içermemelidir:",
      paste(leaked_runtime_anchors, collapse = ", ")
    )
  )
})

test_that("Eski public UI adı wrapper olarak korunur ve büyük UI bloğu geri taşınmaz", {
  server_text <- .read_repo_text_settings_ui_refactor("R/module_settings_yapilandirma.R")

  expect_true(
    grepl("settingsYapilandirmaUI <- function(id)", server_text, fixed = TRUE),
    info = "Public settingsYapilandirmaUI(id) adı geriye dönük uyumluluk için korunmalıdır."
  )

  expect_true(
    grepl("settingsYapilandirmaUIImpl(id)", server_text, fixed = TRUE),
    info = "Public UI wrapper yeni UI uygulamasına delege etmelidir."
  )

  expect_true(
    grepl("settingsYapilandirmaServer <- function", server_text, fixed = TRUE),
    info = "Sunucu modülü R/module_settings_yapilandirma.R içinde kalmalıdır."
  )

  moved_ui_markers <- c(
    'h3("Model Ayarları"',
    'h3("Claude Code Yapılandırma"',
    'h3("Ses Ayarları"',
    'h3("Özetleme Ayarları"'
  )

  returned_markers <- moved_ui_markers[vapply(
    moved_ui_markers,
    function(anchor) grepl(anchor, server_text, fixed = TRUE),
    logical(1)
  )]

  expect_equal(
    returned_markers,
    character(0),
    info = paste(
      "Büyük Yapılandırma UI bloğu server dosyasına geri taşınmamalıdır:",
      paste(returned_markers, collapse = ", ")
    )
  )
})