# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_yanit_icerik.R
# Açıklama: Ortak Oturum yapay zekâ YANIT içeriği zengin render katmanı.
#           Tekil oturumla aynı boru hatlarını yeniden kullanır:
#             * Kod blokları: process_message_content -> .code-container
#               (dil algılama, kopyalama, CodeMirror) — çift kaçış yok.
#             * ChartLab: ```chartlab blokları highcharter çıktısına bağlanır
#               (wire_chart_output tek motor; veri mesaj metnine gömülüdür,
#               böylece TÜM katılımcılar kendi oturumunda render eder).
#           Güvenlik: düzyazı her zaman güvenli markdown yolundan geçer;
#           ham HTML inert kalır. Grafik çıktı kimlikleri OrtakMesajID'den
#           deterministik türetilir (yeniden render çakışmasız).
# ==============================================================================

# Mesaj metnini metin / chartlab parçalarına ayırır (SAF).
oo_yanit_icerik_parcala <- function(metin) {
  metin <- as.character(metin %||% "")[1]
  if (is.na(metin)) {
    metin <- ""
  }

  if (!grepl("```chartlab", metin, fixed = TRUE)) {
    return(list(list(kind = "text", value = metin)))
  }

  parcalar <- list()
  kalan <- metin
  while (TRUE) {
    ac <- regexpr("```chartlab\\s*", kalan, perl = TRUE)
    if (ac[1] == -1) {
      parcalar <- append(parcalar, list(list(kind = "text", value = kalan)))
      break
    }
    on_metin <- substr(kalan, 1, ac[1] - 1)
    parcalar <- append(parcalar, list(list(kind = "text", value = on_metin)))
    devam <- substr(kalan, ac[1] + attr(ac, "match.length"), nchar(kalan))
    kapa <- regexpr("```", devam, perl = TRUE)
    if (kapa[1] == -1) {
      # Kapanmamış blok: güvenli tarafta düz metin olarak bırakılır.
      parcalar <- append(parcalar, list(list(kind = "text", value = paste0("```chartlab\n", devam))))
      break
    }
    parcalar <- append(parcalar, list(list(kind = "chart", value = substr(devam, 1, kapa[1] - 1))))
    kalan <- substr(devam, kapa[1] + attr(kapa, "match.length"), nchar(kalan))
  }

  parcalar
}

# Düzyazı parçasını güvenli HTML'e çevirir: kod çitleri .code-container'a,
# kalan metin güvenli markdown'a gider. process_message_content yüklü değilse
# (izole test) güvenli markdown'a, o da yoksa kaçışlı düz metne düşer.
oo_yanit_metin_html <- function(metin) {
  metin <- as.character(metin %||% "")[1]
  if (is.na(metin) || !nzchar(trimws(metin))) {
    return("")
  }

  if (exists("process_message_content", mode = "function", inherits = TRUE)) {
    sonuc <- tryCatch(process_message_content(metin, type = "ai"), error = function(e) NULL)
    if (is.list(sonuc) && !is.null(sonuc$html)) {
      return(as.character(sonuc$html))
    }
  }

  if (exists("render_safe_markdown_html", mode = "function", inherits = TRUE)) {
    return(as.character(render_safe_markdown_html(metin)))
  }

  as.character(htmltools::htmlEscape(metin))
}

# Yanıt gövdesini zengin HTML + grafik bağlama listesine çevirir.
# ns_fn: Shiny modül namespace fonksiyonu (grafik konteyner kimliği DOM'da
# namespaceli olmalıdır; wire_chart_output modül output'una ham kimlikle yazar).
# @return list(html = <karakter>, grafikler = list(list(output_id, spec)))
oo_yanit_icerik_html <- function(metin, mesaj_id, ns_fn = identity) {
  parcalar <- oo_yanit_icerik_parcala(metin)

  html_parcalari <- character(0)
  grafikler <- list()
  sayac <- 0L

  for (parca in parcalar) {
    if (identical(parca$kind, "text")) {
      html_parcalari <- c(html_parcalari, oo_yanit_metin_html(parca$value))
      next
    }

    sayac <- sayac + 1L
    out_id <- sprintf("chart_oo%s_%d", as.character(mesaj_id), sayac)

    spec <- tryCatch(
      jsonlite::fromJSON(parca$value, simplifyVector = TRUE),
      error = function(e) NULL
    )

    veri_var <- is.list(spec) && !is.null(spec$data)
    if (!veri_var) {
      # Veri gömülü değilse (yalnızca ref) diğer katılımcılar çözemez;
      # dürüst Türkçe durum kartı gösterilir.
      html_parcalari <- c(
        html_parcalari,
        '<div class="chart-card"><div class="oo-grafik-uyari">Grafik verisi bu oturumda çözümlenemedi.</div></div>'
      )
      next
    }

    konteyner <- if (requireNamespace("highcharter", quietly = TRUE)) {
      as.character(highcharter::highchartOutput(ns_fn(out_id), height = "380px"))
    } else {
      as.character(shiny::uiOutput(ns_fn(out_id)))
    }
    html_parcalari <- c(
      html_parcalari,
      sprintf('<div class="chart-card oo-grafik-karti">%s</div>', konteyner)
    )
    grafikler <- append(grafikler, list(list(output_id = out_id, spec = spec)))
  }

  list(
    html = paste(html_parcalari, collapse = ""),
    grafikler = grafikler
  )
}

# Yapay zekâ yanıtının TAM zengin içeriği: sondaki Kaynakça işaretleyici bloğu
# ayrılır (ortak odada kapsam "model_bases": tıklama yalnızca kurumsal model
# taban klasörlerinde çözümlenir), kalan düzyazı kod/chartlab farkındalıklı
# render edilir. oo_mesaj_html bu HTML'i olduğu gibi gösterir.
# @return list(html, grafikler)
oo_mesaj_yz_icerigi <- function(metin, mesaj_id, ns_fn = identity) {
  metin <- as.character(metin %||% "")[1]
  if (is.na(metin)) {
    metin <- ""
  }

  kaynak_html <- ""
  prose <- metin

  if (exists("mergen_kaynakca_marker_split", mode = "function", inherits = TRUE) &&
      exists("mergen_kaynakca_marker_html", mode = "function", inherits = TRUE)) {
    kaynak_split <- tryCatch(mergen_kaynakca_marker_split(metin), error = function(e) NULL)
    if (!is.null(kaynak_split) && length(kaynak_split$entries) > 0) {
      prose <- as.character(kaynak_split$prose %||% "")[1]
      kaynak_html <- tryCatch(
        mergen_kaynakca_marker_html(kaynak_split$entries, scope = "model_bases"),
        error = function(e) ""
      )
    }
  }

  icerik <- oo_yanit_icerik_html(prose, mesaj_id, ns_fn)
  list(
    html = paste0(icerik$html, kaynak_html),
    grafikler = icerik$grafikler
  )
}

# Grafik çıktılarının Shiny output bağlaması (tek motor: wire_chart_output).
# Aynı output kimliğine tekrar bağlama güvenlidir (yeniden render üzerine yazar).
oo_yanit_grafikleri_bagla <- function(output, grafikler) {
  if (!is.list(grafikler) || length(grafikler) == 0L) {
    return(invisible(0L))
  }
  if (!exists("wire_chart_output", mode = "function", inherits = TRUE)) {
    return(invisible(0L))
  }

  baglanan <- 0L
  for (g in grafikler) {
    out_id <- as.character(g$output_id %||% "")[1]
    if (!nzchar(out_id) || is.null(g$spec)) {
      next
    }
    tryCatch({
      wire_chart_output(output, out_id, g$spec)
      baglanan <- baglanan + 1L
    }, error = function(e) {
      if (exists("log_warn", mode = "function", inherits = TRUE)) {
        tryCatch(
          log_warn(paste("[ORTAK_GRAFIK] Grafik bağlanamadı:", gsub("[{}]", "", conditionMessage(e)))),
          error = function(e2) NULL
        )
      }
    })
  }

  invisible(baglanan)
}
