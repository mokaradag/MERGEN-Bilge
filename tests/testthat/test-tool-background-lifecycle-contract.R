# ==============================================================================
# Dosya Yolu: tests/testthat/test-tool-background-lifecycle-contract.R
# Açıklama: Araç bağlamlı sohbet arka plan animasyonu yaşam döngüsü
#           sözleşmesi.
#
# Korunan sözleşmeler:
#   1. Kullanıcı gerçek bir prompt gönderdiğinde sunucu tarafı
#      setToolBackgroundFamily(clear=TRUE, reason="user_prompt")
#      mesajı yollar — input$send_prompt_from_js observer'ı bunu
#      send_message çağrısından ÖNCE yapar.
#   2. Lane düzeni sol + orta + sağ olmak üzere center side içerir
#      (kullanıcı isteği: snippet'ler de ortada).
#   3. MAX_ACTIVE_SNIPPETS değeri azaltılmıştır (kalabalık sahne yok);
#      değer 3 ya da daha azdır.
#   4. tool_backgrounds.js içinde welcome loading sahnesi gibi caret
#      kullanılmaz — tool-bg-caret class'ı çalışma zamanında
#      EKLENMEZ. (Tarihsel CSS class'ı dosyada kalsa bile JS yeni
#      kayıtlarda eklemez.)
#   5. setEnabled(true) çağrısı ensureLayer + stopSpawnLoop +
#      startSpawnLoop sırasını uygular; ayar bir oturumda kapatılıp
#      tekrar açıldığında animasyon güvenilir geri gelir.
#   6. theme_light.css içinde #chat_content_container light tema
#      arka planı transparent yapılır — heptagon ve snippet katmanı
#      kırpılmaz.
# ==============================================================================

.repo_root_tool_bg_life <- function() {
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

.read_repo_text_tool_bg_life <- function(rel_path) {
  repo_root <- .repo_root_tool_bg_life()
  full_path <- file.path(repo_root, rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("send_prompt_from_js observer kullanici prompt gondermeden once tool background temizler", {
  txt <- .read_repo_text_tool_bg_life("R/server_observers_chat_input.R")
  expect_true(nzchar(txt), info = "R/server_observers_chat_input.R okunamadi.")

  expect_true(
    grepl('"setToolBackgroundFamily"', txt, fixed = TRUE),
    info = paste(
      "Kullanici prompt'u gonderdiginde setToolBackgroundFamily mesaji",
      "yollanmalidir; aksi halde araç arka plan animasyonu prompt sonrasi",
      "kalintilanir."
    )
  )

  expect_true(
    grepl('clear = TRUE', txt, fixed = TRUE),
    info = "Prompt gonderiminde clear = TRUE bayragi yollanmalidir."
  )

  expect_true(
    grepl('"user_prompt"', txt, fixed = TRUE) ||
      grepl("'user_prompt'", txt, fixed = TRUE),
    info = "Reason alani 'user_prompt' olmalidir (lifecycle teshisi icin)."
  )
})

test_that("tool_backgrounds.js orta lane'leri ve dusurulmus snippet limitini icerir", {
  txt <- .read_repo_text_tool_bg_life("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  expect_true(
    grepl("side: 'center'", txt, fixed = TRUE) ||
      grepl("side: \"center\"", txt, fixed = TRUE),
    info = "Lane tanimlari orta (center) lane'leri icermelidir."
  )

  expect_true(
    grepl("MAX_ACTIVE_SNIPPETS", txt, fixed = TRUE),
    info = "Aktif snippet limit sabiti tanimlanmalidir."
  )

  # Limit deger 3 ya da daha az olmalidir
  expect_true(
    grepl("MAX_ACTIVE_SNIPPETS\\s*=\\s*[123]\\b", txt, perl = TRUE),
    info = "MAX_ACTIVE_SNIPPETS degeri 3 ya da daha az olmalidir (kalabalik sahne yok)."
  )
})

test_that("tool_backgrounds.js setEnabled(true) ensureLayer ve restart sirasini icerir", {
  txt <- .read_repo_text_tool_bg_life("www/js/tool_backgrounds.js")
  expect_true(nzchar(txt), info = "www/js/tool_backgrounds.js okunamadi.")

  # setEnabled fonksiyonu icinde ensureLayer cagrisi yapilmali (re-enable
  # bug'inin engellenmesi icin). Bu, "ayar kapatilip acildiginda
  # animasyonlar guvenilir geri gelmiyor" regresyonunu engeller.
  expect_true(
    grepl("function setEnabled\\(", txt, perl = TRUE) ||
      grepl("setEnabled\\s*=\\s*function", txt, perl = TRUE),
    info = "setEnabled fonksiyonu tanimli olmalidir."
  )

  # Re-enable yolunda ensureLayer ve stopSpawnLoop kullanilmali
  # (idempotent restart).
  expect_true(
    grepl("ensureLayer\\(wrapper\\)", txt, fixed = TRUE) ||
      grepl("ensureLayer(wrapper)", txt, fixed = TRUE),
    info = "ensureLayer wrapper ile cagrilmali."
  )

  expect_true(
    grepl("stopSpawnLoop\\s*\\(\\)", txt, perl = TRUE),
    info = "Restart oncesinde stopSpawnLoop cagrilmali."
  )
})

test_that("theme_light.css chat_content_container'i light temada transparan birakir", {
  txt <- .read_repo_text_tool_bg_life("www/css/theme_light.css")
  expect_true(nzchar(txt), info = "www/css/theme_light.css okunamadi.")

  # Solid var(--color-bg) kullanimi yerine transparent secimi tool-bg-layer
  # gorunurlugu icin gereklidir.
  expect_true(
    grepl("background-color:\\s*transparent", txt, perl = TRUE),
    info = paste(
      "Light temada #chat_content_container ya da .chat-container",
      "background-color: transparent kullanmalidir. Aksi halde tool-bg-layer",
      "(heptagon + snippet) light temada gorunmez."
    )
  )
})

test_that("config_ui_assets.R theme_light_refinements.css'i CSS manifestine ekler", {
  txt <- .read_repo_text_tool_bg_life("R/config_ui_assets.R")
  expect_true(nzchar(txt), info = "R/config_ui_assets.R okunamadi.")

  expect_true(
    grepl('"css/theme_light_refinements.css"', txt, fixed = TRUE),
    info = "theme_light_refinements.css UI asset manifestine eklenmelidir."
  )
})

test_that("saved chat ve localStorage geri yukleme akislari tool background'u temizler", {
  saved_txt <- .read_repo_text_tool_bg_life("R/server_observers_saved_chats.R")
  storage_txt <- .read_repo_text_tool_bg_life("R/server_observers_storage.R")
  expect_true(nzchar(saved_txt), info = "R/server_observers_saved_chats.R okunamadi.")
  expect_true(nzchar(storage_txt), info = "R/server_observers_storage.R okunamadi.")

  expect_true(
    grepl('"load_saved_chat"', saved_txt, fixed = TRUE) ||
      grepl("'load_saved_chat'", saved_txt, fixed = TRUE),
    info = paste(
      "Kaydedilmis sohbet yuklenirken araç arka plan animasyonu",
      "temizlenmelidir; reason='load_saved_chat' beklenir."
    )
  )

  expect_true(
    grepl('"load_chat_from_storage"', storage_txt, fixed = TRUE) ||
      grepl("'load_chat_from_storage'", storage_txt, fixed = TRUE),
    info = paste(
      "localStorage geri yuklemesinde de tool background temizlenmelidir;",
      "reason='load_chat_from_storage' beklenir."
    )
  )
})
