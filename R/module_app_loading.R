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
#     www/js/app_loading_media.js
#   Bu dosyalar derleme anında okunup ilk boyamada satır içine gömülür; bu
#   sayede harici varlık yüklenmesini beklemeden ekran tutarlı görünür ve
#   R dosyası küçük/okunabilir kalır. Bu varlıklar bilinçli olarak normal
#   UI manifestine (R/config_ui_assets.R) eklenmez.

#' Açılış varlık dosyası yolunu çöz
#' @description Açılış katmanı ilk boyamada satır içi CSS/JS'e bağımlıdır.
#'   Shiny uygulaması normalde repo kökünden başlatılır; ancak servis
#'   sarmalayıcıları ve izole testler çalışma dizinini değiştirebilir. Bu
#'   nedenle yalnızca getwd()/www varsayımına bağlı kalmadan önce
#'   MERGEN_REPO_ROOT, sonra çalışma dizini ve üst dizinleri taranır.
#' @param rel_path www köküne göre göreli yol
#' @return Tam dosya yolu ya da bulunamazsa boş dize
app_loading_asset_path <- function(rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  if (!nzchar(rel_path)) {
    return("")
  }

  rel_path <- gsub("^/+|^www/+", "", rel_path)

  candidates <- character(0)
  env_root <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  if (nzchar(env_root)) {
    candidates <- c(candidates, env_root)
  }

  cwd <- base::try(getwd(), silent = TRUE)
  if (inherits(cwd, "try-error")) {
    cwd <- ""
  }
  if (nzchar(cwd)) {
    current <- normalizePath(cwd, winslash = "/", mustWork = FALSE)
    repeat {
      candidates <- c(candidates, current)
      parent <- dirname(current)
      if (!nzchar(parent) || identical(parent, current)) {
        break
      }
      current <- parent
    }
  }

  candidates <- unique(Filter(nzchar, candidates))
  for (root in candidates) {
    path <- file.path(root, "www", rel_path)
    if (file.exists(path)) {
      return(path)
    }
  }

  ""
}

#' Açılış varlık dosyasını UTF-8 metin olarak oku
#' @description www altındaki bir CSS/JS dosyasını ham bayt olarak okuyup
#'   UTF-8 metne dönüştürür; satır içine gömme için kullanılır.
#' @param rel_path www köküne göre göreli yol (örn. "css/app_loading.css")
#' @return Karakter dizisi (dosya içeriği) ya da bulunamazsa boş dize
app_loading_asset <- function(rel_path) {
  path <- app_loading_asset_path(rel_path)

  if (!nzchar(path) || !file.exists(path)) {
    warning(sprintf("Açılış yükleme varlığı bulunamadı: www/%s", rel_path), call. = FALSE)
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

#' Açılış kabuk kapısı (pre-paint) head etiketleri
#' @description Tarayıcı, HTML'i parça parça alırken kenar çubuğu/başlık
#'   işaretlemesi yükleme katmanından ÖNCE geldiği için ilk boyamada kabuk
#'   kısa süre görünebilir (flash). Bu kapı <head> içinde çalışır: gövde
#'   boyanmadan önce <html> elemanına "mergen-boot-shell-gate" sınıfını
#'   uygular ve shinydashboard kabuğunu (başlık, kenar çubuğu, içerik)
#'   görünmez tutar. Yükleme katmanı, şerit seçicisi ve SSO hata yüzeyi
#'   açık istisnadır. Kapı yalnızca GÖSTERİLEN ilerleme %100'e ulaştığında
#'   www/js/app_loading.js tarafından bırakılır; katman hiç kurulamazsa
#'   DOMContentLoaded yetenek denetimi kabuğu kalıcı gizli bırakmaz.
#'   visibility kullanılır (display değil): kabuk açığa çıkarken yerleşim
#'   sıçraması olmaz ve katman/istisna yüzeyleri alt öğe olarak görünür kalır.
#' @return Shiny tagList (style + script; ui.R head içinde en erken noktada)
app_loading_shell_gate_head_tags <- function() {
  tagList(
    tags$style(HTML(paste(
      "html.mergen-boot-shell-gate .main-header,",
      "html.mergen-boot-shell-gate .main-sidebar,",
      "html.mergen-boot-shell-gate .content-wrapper {",
      "  visibility: hidden !important;",
      "}",
      "html.mergen-boot-shell-gate #app-loading-overlay,",
      "html.mergen-boot-shell-gate #mergen-lane-select,",
      "html.mergen-boot-shell-gate .sso-auth-overlay {",
      "  visibility: visible !important;",
      "}",
      sep = "\n"
    ))),
    tags$script(HTML(paste(
      "(function () {",
      "  var kok = document.documentElement;",
      "  kok.classList.add(\"mergen-boot-shell-gate\");",
      "  function birak() {",
      "    kok.classList.remove(\"mergen-boot-shell-gate\");",
      "  }",
      "  window.MergenBootShellGate = {",
      "    release: birak,",
      "    isHeld: function () {",
      "      return kok.classList.contains(\"mergen-boot-shell-gate\");",
      "    }",
      "  };",
      "  document.addEventListener(\"DOMContentLoaded\", function () {",
      "    var katman = document.getElementById(\"app-loading-overlay\");",
      "    if (!katman || !window.MergenAppLoading) {",
      "      birak();",
      "    }",
      "  });",
      "})();",
      sep = "\n"
    )))
  )
}

#' İlk açılış başlangıç şeridi seçicisi işaretlemesi
#' @description Kayıtlı şerit tercihi yoksa gösterilen tam ekran, koyu temalı
#'   iki kartlı seçici. Video, Three.js veya persona medyası GEREKTİRMEZ;
#'   yalnızca hafif CSS mikro-animasyonları kullanır. Görünürlüğü
#'   www/js/app_loading_lane.js yönetir (varsayılan gizli).
#' @return tags$div
app_loading_lane_selector_ui <- function() {
  lane_card <- function(lane, title, desc, svg_path) {
    tags$div(
      class = "mlane-card",
      `data-lane` = lane,
      role = "button",
      tabindex = "0",
      `aria-label` = paste0(title, ": ", desc),
      tags$div(class = "mlane-card-glow", `aria-hidden` = "true"),
      tags$div(
        class = "mlane-card-icon",
        `aria-hidden` = "true",
        HTML(paste0(
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ',
          'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" ',
          'aria-hidden="true" focusable="false">', svg_path, '</svg>'
        ))
      ),
      tags$h3(class = "mlane-card-title", title),
      tags$p(class = "mlane-card-desc", desc)
    )
  }

  tags$div(
    id = "mergen-lane-select",
    class = "mlane-overlay",
    hidden = "hidden",
    role = "dialog",
    `aria-modal` = "true",
    `aria-labelledby` = "mlane-title",
    tags$div(
      class = "mlane-panel",
      tags$h2(id = "mlane-title", class = "mlane-title", "Başlangıç Deneyiminizi Seçin"),
      tags$p(
        class = "mlane-subtitle",
        "Tercihiniz kaydedilir; Ayarlar > Yapılandırma bölümünden dilediğinizde değiştirebilirsiniz."
      ),
      tags$div(
        class = "mlane-cards",
        lane_card(
          "fast_lane",
          "Hızlı Başlangıç",
          "Doğrudan Ana Söyleşi'ye geç. Zengin medya ve diğer sayfalar gerektiğinde yüklenir.",
          '<path d="M13 2 4.5 13.5H11L9.5 22 19 10h-6.5L13 2Z"/>'
        ),
        lane_card(
          "rich_lane",
          "Zengin Deneyim",
          "MERGEN Bilge'nin sinematik açılışını, Keşfet akışını ve gelişmiş deneyim modlarını kullan.",
          paste0(
            '<circle cx="12" cy="12" r="8.2"/>',
            '<path d="M12 3.8v2.2M12 18v2.2M3.8 12H6M18 12h2.2"/>',
            '<path d="m14.6 9.4-1.7 3.5-3.5 1.7 1.7-3.5 3.5-1.7Z"/>'
          )
        )
      )
    )
  )
}

#' Uygulama Yükleme Ekranı UI
#' @description Açılış yükleme katmanını üretir ve ayrı www varlıklarını
#'   satır içine gömer. ui.R içinde mümkün olan en erken noktada çağrılmalıdır.
#' @return Shiny tagList
appLoadingUI <- function() {
  # MERGEN_STARTUP_LANE dağıtım varsayılanı istemciye gömülür; şerit
  # çözümleme önceliği istemcide: kayıtlı tercih > ortam varsayılanı >
  # ask_once (ilk açılış seçicisi).
  lane_env_default <- if (exists("mergen_startup_lane_env_default", mode = "function")) {
    mergen_startup_lane_env_default()
  } else {
    "ask_once"
  }

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
        style = "position:absolute;top:24px;left:28px;z-index:50;pointer-events:none;",
        tags$img(
          src = "img/company_logo.svg",
          alt = "Şirket Logosu",
          style = "height:38px;width:auto;filter:brightness(1) drop-shadow(0 0 8px rgba(255,255,255,0.15));"
        )
      ),
      tags$style(HTML(".deep-space-company-logo img { height: 38px; }")),
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
      # İlk açılış başlangıç şeridi seçicisi (kayıtlı tercih yoksa görünür)
      app_loading_lane_selector_ui(),
      # Satır içi stil ve betikler (ayrı www dosyalarından okunur).
      # Şerit çözümleyici (app_loading_lane.js) ilerleme denetleyicisinden
      # (app_loading.js) ÖNCE gömülür; ilerleme aşama planı şeride bağlıdır.
      tags$style(HTML(app_loading_asset("css/app_loading.css"))),
      tags$script(HTML(sprintf(
        "window.__mergenStartupLaneEnvDefault = %s;",
        jsonlite::toJSON(lane_env_default, auto_unbox = TRUE)
      ))),
      tags$script(HTML(app_loading_asset("js/app_loading_lane.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_snippets.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_content.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_codestream.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading.js"))),
      tags$script(HTML(app_loading_asset("js/app_loading_media.js")))
    )
  )
}
