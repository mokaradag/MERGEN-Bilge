# ==============================================================================
# Dosya Yolu: tests/testthat/test-accessibility-contract.R
# Açıklama: Erişilebilirlik (a11y) sözleşmesi. Ana söyleşi giriş alanındaki
#           ikon-yalnız (icon-only) etkileşim kontrolleri, açılır menüler ve
#           bildirim (toast) sistemi için ekran okuyucu etiketlerinin
#           (aria-label / role / aria-live) yerinde kaldığını doğrular.
#
#           Bu test SADECE statik metin taramasıdır: gerçek tarayıcı, Shiny
#           uygulaması, DB veya ağ GEREKTİRMEZ. Türkçe etiket metinleri Windows
#           VM bayt eşleşmesinde kırılgan olabileceği için, doğrulamalar ASCII
#           yapısal çapalara (id, sınıf, öznitelik adı) dayanır; Türkçe değer
#           metni doğrudan beklenmez.
# ==============================================================================

# UTF-8 dosyaları bayt-güvenli okuyan yardımcı (selector-contract ile aynı desen).
.a11y_read_repo_text <- function(path) {
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

# Bir ASCII çapasının metinde bulunup bulunmadığını kontrol eder.
.a11y_has <- function(text, needle) {
  isTRUE(suppressWarnings(grepl(needle, text, fixed = TRUE)))
}

# `anchor` çapasından sonra `window` karakter içinde `attr` özniteliğinin
# geçip geçmediğini kontrol eder. Karakter konumu tutarlı kullanılır
# (useBytes KARIŞTIRILMAZ), böylece Türkçe çok baytlı metin ofset kaydırmaz.
.a11y_attr_near <- function(text, anchor, attr, window = 260L) {
  hit <- regexpr(anchor, text, fixed = TRUE)
  if (hit[[1]] < 0) {
    return(FALSE)
  }
  start <- hit[[1]]
  parca <- substr(text, start, start + window)
  isTRUE(grepl(attr, parca, fixed = TRUE))
}

# ------------------------------------------------------------------------------
# 1) Ana söyleşi giriş alanı: ikon-yalnız kontroller erişilebilir isim almalı.
# ------------------------------------------------------------------------------
testthat::test_that("ana söyleşi giriş kontrolleri aria-label taşır", {
  ui_text <- .a11y_read_repo_text("ui.R")
  testthat::expect_true(nzchar(ui_text))

  # Mesaj giriş alanı (textarea) yalnızca placeholder'a bağımlı kalmamalı.
  testthat::expect_true(.a11y_has(ui_text, 'id = "user_input"'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'id = "user_input"', "aria-label", window = 120L),
    info = "user_input textarea aria-label taşımalıdır."
  )

  # Gönder/Durdur düğmesi (ikon-yalnız).
  testthat::expect_true(.a11y_has(ui_text, 'inputId = "send_stop_btn"'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'inputId = "send_stop_btn"', "aria-label", window = 320L),
    info = "send_stop_btn aria-label taşımalıdır."
  )

  # Sesli giriş düğmesi (ikon-yalnız).
  testthat::expect_true(.a11y_has(ui_text, 'inputId = "voice_btn"'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'inputId = "voice_btn"', "aria-label", window = 220L),
    info = "voice_btn aria-label taşımalıdır."
  )

  # Dosya ekle düğmesi (ikon-yalnız label).
  testthat::expect_true(.a11y_has(ui_text, 'id = "file_btn_container"'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'id = "file_btn_container"', "aria-label", window = 200L),
    info = "Dosya ekle kontrolü aria-label taşımalıdır."
  )
})

# ------------------------------------------------------------------------------
# 2) Giriş alanındaki açılır menüler erişilebilir isim almalı.
# ------------------------------------------------------------------------------
testthat::test_that("giriş alanı açılır menüleri (select) aria-label taşır", {
  ui_text <- .a11y_read_repo_text("ui.R")

  select_ids <- c(
    "chat_image_size",
    "chat_summary_detail",
    "chat_summary_focus",
    "chat_analysis_detail",
    "chat_excel_deep_level",
    "chat_coding_deep_level"
  )

  for (sid in select_ids) {
    anchor <- sprintf('id = "%s"', sid)
    testthat::expect_true(
      .a11y_has(ui_text, anchor),
      info = sprintf("%s select kimliği korunmalıdır.", sid)
    )
    testthat::expect_true(
      .a11y_attr_near(ui_text, anchor, "aria-label", window = 320L),
      info = sprintf("%s select aria-label taşımalıdır.", sid)
    )
  }
})

# ------------------------------------------------------------------------------
# 3) Dekoratif ikonlar ekran okuyucudan gizlenmeli (aria-hidden).
# ------------------------------------------------------------------------------
testthat::test_that("giriş alanındaki dekoratif ikonlar aria-hidden taşır", {
  ui_text <- .a11y_read_repo_text("ui.R")

  # Sürükle-bırak bulutu ve ataç ikonu dekoratiftir; metin eşdeğeri vardır.
  testthat::expect_true(.a11y_has(ui_text, 'fas fa-cloud-upload-alt fa-3x'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'fas fa-cloud-upload-alt fa-3x', "aria-hidden", window = 80L),
    info = "Sürükle-bırak ikonu aria-hidden taşımalıdır."
  )

  testthat::expect_true(.a11y_has(ui_text, 'fas fa-paperclip'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'fas fa-paperclip', "aria-hidden", window = 60L),
    info = "Ataç (dosya) ikonu aria-hidden taşımalıdır."
  )

  # Derin düşünme beyin ikonu dekoratiftir (düğmenin görünür metin etiketi var).
  testthat::expect_true(.a11y_has(ui_text, 'fas fa-brain toggle-icon'))
  testthat::expect_true(
    .a11y_attr_near(ui_text, 'fas fa-brain toggle-icon', "aria-hidden", window = 60L),
    info = "Beyin (derin düşünme) ikonu aria-hidden taşımalıdır."
  )
})

# ------------------------------------------------------------------------------
# 4) Bildirim (toast) sistemi ekran okuyucu için canlı bölge olmalı.
# ------------------------------------------------------------------------------
testthat::test_that("toast sistemi canlı bölge ve etiketli kapat düğmesi içerir", {
  toast_js <- .a11y_read_repo_text("www/js/toast.js")
  testthat::expect_true(nzchar(toast_js))

  # Konteyner canlı bölge (live region) olarak işaretlenmeli.
  testthat::expect_true(
    .a11y_has(toast_js, "setAttribute('role', 'status')"),
    info = "toast-container role=status taşımalıdır."
  )
  testthat::expect_true(
    .a11y_has(toast_js, "setAttribute('aria-live', 'polite')"),
    info = "toast-container aria-live=polite taşımalıdır."
  )

  # Hata/uyarı için daha güçlü 'alert' rolü seçimi korunmalı.
  testthat::expect_true(.a11y_has(toast_js, "const toastRole"))
  testthat::expect_true(.a11y_has(toast_js, "role=\"${toastRole}\""))

  # Kapat düğmesi ikon-yalnızdır; erişilebilir isim taşımalı (ASCII metin).
  testthat::expect_true(
    .a11y_has(toast_js, 'aria-label="Bildirimi kapat"'),
    info = "toast kapat düğmesi aria-label taşımalıdır."
  )

  # Dekoratif ikon ekran okuyucudan gizlenmeli.
  testthat::expect_true(
    .a11y_has(toast_js, 'toast-icon" aria-hidden="true"'),
    info = "toast ikonu aria-hidden taşımalıdır."
  )
})

# ------------------------------------------------------------------------------
# 5) Gönder/Durdur düğmesinin ekran okuyucu etiketi mod ile birlikte güncellenir.
#    Görünür `title` zaten güncelleniyordu; aria-label de aynı çapalardan
#    güncellenmelidir, böylece ekran okuyucu kullanıcısı modu kaybetmez.
# ------------------------------------------------------------------------------
testthat::test_that("gönder/durdur düğmesi mod değişiminde aria-label günceller", {
  send_msg_r <- .a11y_read_repo_text("R/server_send_message.R")
  reset_r <- .a11y_read_repo_text("R/helpers_chat_runtime.R")

  # Durdur moduna geçiş: stop-mode + aria-label güncellemesi birlikte olmalı.
  testthat::expect_true(.a11y_has(send_msg_r, "addClass('stop-mode')"))
  testthat::expect_true(
    .a11y_has(send_msg_r, "attr('aria-label'"),
    info = "Durdur moduna geçiş aria-label güncellemelidir."
  )

  # Gönder moduna dönüş: stop-mode kaldırılır + aria-label sıfırlanır.
  testthat::expect_true(.a11y_has(reset_r, "removeClass('stop-mode')"))
  testthat::expect_true(
    .a11y_has(reset_r, "attr('aria-label'"),
    info = "Gönder moduna dönüş aria-label sıfırlamalıdır."
  )
})
