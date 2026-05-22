# R/module_app_loading.R
# Dosya Yolu: R/module_app_loading.R
# Açıklama: Uygulama açılışında tüm ekranı kaplayan modern, çok aşamalı
#   yükleme katmanı. SSO kimlik doğrulama, oturum kurulumu ve çalışma alanı
#   hazırlığı boyunca gerçek ilerlemeyi yansıtır.
#
#   Stil ve betikler artık ayrı www varlık dosyalarında tutulur:
#     www/css/app_loading.css
#     www/js/app_loading_snippets.js
#     www/js/app_loading_content.js
#     www/js/app_loading_codestream.js
#     www/js/app_loading.js
#   Bu dosyalar derleme anında okunup ilk boyamada satır içine gömülür; bu
#   sayede harici varlık yüklenmesini beklemeden ekran tutarlı görünür ve
#   R dosyası küçük/okunabilir kalır. Bu varlıklar bilinçli olarak normal
#   UI manifestine (R/config_ui_assets.R) eklenmez.

#' Açılış varlık dosyasını UTF-8 metin olarak oku
#' @description www altındaki bir CSS/JS dosyasını ham bayt olarak okuyup
#'   UTF-8 metne dönüştürür; satır içine gömme için kullanılır.
#' @param rel_path www köküne göre göreli yol (örn. "css/app_loading.css")
#' @return Karakter dizisi (dosya içeriği) ya da bulunamazsa boş dize
app_loading_asset <- function(rel_path) {
  path <- file.path("www", rel_path)

  if (!file.exists(path)) {
    warning(sprintf("Açılış yükleme varlığı bulunamadı: %s", path), call. = FALSE)
    return("")
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)

  # Olası UTF-8 BOM'unu ayıkla
  if (length(raw_data) >= 3 &&
      raw_data[1] == as.raw(0xEF) &&
      raw_data[2] == as.raw(0xBB) &&
      raw_data[3] == as.raw(0xBF)) {
    raw_data <- raw_data[-(1:3)]
  }

  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  txt
}

#' Yedigen köşe noktalarını üret
#' @description Verilen yarıçap ve merkez için tepe-yukarı düzgün yedigenin
#'   SVG polygon "points" dizesini döndürür.
#' @param r Yarıçap
#' @param cx,cy Merkez koordinatları (varsayılan 240x240 viewBox merkezi)
#' @return SVG polygon points karakter dizisi
app_loading_heptagon_points <- function(r, cx = 120, cy = 120) {
  # Tepe-yukarı düzgün yedigenin birim köşe koordinatları
  vx <- c(0, 0.7818315, 0.9749279, 0.4338837, -0.4338837, -0.9749279, -0.7818315)
  vy <- c(-1, -0.6234898, 0.2225209, 0.9009689, 0.9009689, 0.2225209, -0.6234898)
  paste(sprintf("%.2f,%.2f", cx + r * vx, cy + r * vy), collapse = " ")
}

#' Yedigen yükleme amblemi SVG'sini üret
#' @description İç içe yedigenlerden oluşan amblemi ve ilerleme halkasını
#'   içeren SVG işaretlemesini döndürür.
#' @return SVG karakter dizisi
app_loading_mark_svg <- function() {
  paste0(
    '<svg class="alo-mark-svg" viewBox="0 0 240 240" ',
    'aria-hidden="true" focusable="false">',
    '<defs><linearGradient id="aloProgressGrad" x1="0" y1="0" x2="0" y2="1">',
    '<stop offset="0" stop-color="#ffb27a"/>',
    '<stop offset="0.55" stop-color="#ff7a3c"/>',
    '<stop offset="1" stop-color="#ff5620"/>',
    '</linearGradient></defs>',
    '<polygon class="alo-hept alo-hept-outer" points="',
    app_loading_heptagon_points(106), '"/>',
    '<polygon class="alo-hept alo-hept-track" points="',
    app_loading_heptagon_points(80), '"/>',
    # pathLength=100: yedigen çevresi 0-100 birime ölçeklenir; ilerleme JS
    # tarafından stroke-dashoffset ile sürülür. Satır içi başlangıç %0 (boş)
    # olduğundan ilk boyamada sıçrama/geri sarma görülmez.
    '<polygon class="alo-hept alo-hept-progress" id="alo-progress-hept" ',
    'pathLength="100" stroke-dasharray="100" stroke-dashoffset="100" points="',
    app_loading_heptagon_points(80), '"/>',
    '<polygon class="alo-hept alo-hept-inner" points="',
    app_loading_heptagon_points(52), '"/>',
    '</svg>'
  )
}

#' Uygulama Yükleme Ekranı UI
#' @description Açılış yükleme katmanını üretir ve ayrı www varlıklarını
#'   satır içine gömer. ui.R içinde mümkün olan en erken noktada çağrılmalıdır.
#' @return Shiny tagList
appLoadingUI <- function() {
  tagList(
    tags$div(
      id = "app-loading-overlay",
      # Kritik konum/zemin satır içinde: <style> ayrıştırılmadan da ekran
      # opak biçimde kaplanır ve koyu tema zemini tutarlı kalır.
      style = paste0(
        "position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483600;",
        "background:",
        "radial-gradient(circle at 50% 40%,rgba(0,45,122,0.34),transparent 56%),",
        "radial-gradient(circle at 50% 108%,rgba(9,120,128,0.16),transparent 60%),",
        "linear-gradient(168deg,#04060e 0%,#0a1026 52%,#050810 100%);"
      ),
      tags$div(class = "alo-aurora"),
      tags$div(class = "alo-stars"),
      tags$div(class = "alo-corner"),
      tags$div(class = "alo-corner alo-corner-mirror"),
      tags$div(class = "alo-vignette"),
      tags$div(class = "alo-codestream"),
      tags$div(
        class = "alo-stage",
        tags$div(
          class = "alo-mark",
          HTML(app_loading_mark_svg()),
          tags$div(class = "alo-mark-glow"),
          tags$div(
            class = "alo-mark-readout",
            tags$span("0", class = "alo-readout-num"),
            tags$span("%", class = "alo-readout-pct")
          )
        ),
        tags$div(
          class = "alo-wordmark",
          tags$span("MERGEN", class = "alo-wordmark-primary"),
          tags$span("Bilge", class = "alo-wordmark-accent")
        ),
        tags$div(class = "alo-divider"),
        tags$div(
          class = "alo-status",
          tags$span(class = "alo-status-dot"),
          tags$span("Başlatılıyor", class = "alo-status-text")
        )
      ),
      # Satır içi stil ve betikler (ayrı www dosyalarından okunur)
      tags$style(HTML(app_loading_asset("css/app_loading.css"))),
      tags$script(HTML(app_loading_asset("js/app_loading_snippets.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_content.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_codestream.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading.js")))
    )
  )
}
