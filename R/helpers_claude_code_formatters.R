# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_formatters.R
# Açıklama: Claude Code araç kullanımı ve kabuk komutları için gelişmiş HTML
#           biçimlendiriciler. Canlı akış parçalarını, dosya önizlemelerini
#           ve kabuk çıktılarını kullanıcı arayüzüne uygun biçimde sunar.
# ==============================================================================

# ------------------------------------------------------------------------------
# CANLI AKIŞ PARCASI HTML BİÇİMLENDİRME
# Tekil akış parçalarını anlık görüntüleme için HTML'e dönüştürür.
# ------------------------------------------------------------------------------

#' Akış parçasını HTML mesajına dönüştür
#'
#' @param parca parse_streaming_chunk sonucu
#' @return Liste: html (HTML içerik), tip (mesaj tipi)
format_streaming_chunk_html <- function(parca) {
  if (is.null(parca)) return(NULL)

  tip <- parca$tip

  if (tip == "tool_use") {
    # Araç kullanımı başladı - canlı kabuk bloğu oluştur
    html <- format_live_tool_use_html(parca)
    return(list(html = html, tip = "tool_use", arac_id = parca$arac_id))

  } else if (tip == "tool_result") {
    # Araç sonucu - mevcut bloğa sonuç ekle
    sonuc_html <- format_tool_result_snippet(parca$icerik)
    return(list(html = sonuc_html, tip = "tool_result", arac_id = parca$arac_id))

  } else if (tip == "text") {
    # Metin parçası
    return(list(html = parca$icerik, tip = "text"))

  } else if (tip == "result") {
    # Son sonuç
    return(list(html = parca$icerik, tip = "result",
                session_id = parca$session_id))

  } else if (tip == "raw_text") {
    # Ham metin (JSON ayrıştırılamadı)
    return(list(html = htmltools::htmlEscape(parca$icerik), tip = "raw_text"))

  } else if (tip == "assistant") {
    # Asistan mesajı blokları
    html_parcalar <- c()
    for (blok in parca$bloklar) {
      if (blok$tip == "text") {
        html_parcalar <- c(html_parcalar, blok$icerik)
      } else if (blok$tip == "tool_use") {
        html_parcalar <- c(html_parcalar, format_live_tool_use_html(blok))
      }
    }
    return(list(html = paste(html_parcalar, collapse = "\n"), tip = "assistant"))
  }

  return(NULL)
}

# ------------------------------------------------------------------------------
# CANLI ARAÇ KULLANIMI HTML
# Kabuk komutu, dosya işlemi gibi araç kullanımlarını canlı blok olarak
# biçimlendirir. Açılır/kapanır yapıda ve gizlenebilir.
# ------------------------------------------------------------------------------

#' Canlı araç kullanımını HTML bloğuna dönüştür
#'
#' @param parca Araç kullanımı parça verisi
#' @return HTML metni
format_live_tool_use_html <- function(parca) {
  arac_adi <- parca$arac_adi %||% "bilinmeyen"
  arac_turu <- parca$arac_turu %||% "other"
  komut <- parca$komut %||% ""
  dosya_yolu <- parca$dosya_yolu %||% ""
  dosya_icerigi <- parca$dosya_icerigi %||% ""

  # Araç türüne göre ikon, başlık ve içerik belirle
  arac_bilgisi <- get_tool_display_info(arac_turu, arac_adi)

  # İçerik alanını oluştur
  icerik_html <- ""
  if (arac_turu == "bash" && nzchar(komut)) {
    # Kabuk komutu - komut satırını göster
    icerik_html <- paste0(
      '<div class="cc-tool-content cc-shell-content">',
      '<code class="cc-tool-command cc-shell-command">',
      '<span class="cc-shell-prompt">$ </span>',
      htmltools::htmlEscape(komut),
      '</code></div>'
    )
  } else if (arac_turu == "file_read" && nzchar(dosya_yolu)) {
    # Dosya okuma
    icerik_html <- paste0(
      '<div class="cc-tool-content">',
      '<span class="cc-tool-path">',
      '<i class="fas fa-file-code cc-tool-path-icon"></i> ',
      htmltools::htmlEscape(dosya_yolu),
      '</span></div>'
    )
  } else if (arac_turu == "file_write" && nzchar(dosya_yolu)) {
    # Dosya yazma - dosya yolu ve önizleme
    onizleme <- ""
    if (nzchar(dosya_icerigi)) {
      # İlk 10 satırı göster
      satirlar <- strsplit(dosya_icerigi, "\n")[[1]]
      ilk_satirlar <- head(satirlar, 10)
      kisaltildi <- length(satirlar) > 10
      onizleme_metni <- paste(ilk_satirlar, collapse = "\n")
      if (kisaltildi) {
        onizleme_metni <- paste0(onizleme_metni, "\n... (+",
                                  length(satirlar) - 10, " satır daha)")
      }
      onizleme <- paste0(
        '<div class="cc-file-preview">',
        '<div class="cc-file-preview-header">',
        '<i class="fas fa-eye"></i> Dosya Önizlemesi',
        '</div>',
        '<pre class="cc-file-preview-content">',
        htmltools::htmlEscape(onizleme_metni),
        '</pre></div>'
      )
    }
    icerik_html <- paste0(
      '<div class="cc-tool-content">',
      '<span class="cc-tool-path">',
      '<i class="fas fa-pen cc-tool-path-icon"></i> ',
      htmltools::htmlEscape(dosya_yolu),
      '</span>',
      onizleme,
      '</div>'
    )
  } else if (arac_turu == "search") {
    # Arama
    desen <- parca$girdi$pattern %||% parca$girdi$query %||% ""
    if (nzchar(desen)) {
      icerik_html <- paste0(
        '<div class="cc-tool-content">',
        '<span class="cc-tool-path">',
        '<i class="fas fa-search cc-tool-path-icon"></i> ',
        htmltools::htmlEscape(desen),
        '</span></div>'
      )
    }
  }

  # Bloğu oluştur
  paste0(
    '<div class="cc-tool-block cc-shell-block" data-tool-id="',
    htmltools::htmlEscape(parca$arac_id %||% ""), '" ',
    'data-tool-type="', arac_turu, '">',
    '<div class="cc-tool-header">',
    '<i class="fas fa-', arac_bilgisi$ikon, '"></i> ',
    '<span class="cc-tool-title">', htmltools::htmlEscape(arac_bilgisi$baslik), '</span>',
    '<span class="cc-tool-status cc-tool-running">',
    '<i class="fas fa-spinner fa-spin"></i></span>',
    '<i class="fas fa-chevron-down cc-tool-toggle-icon"></i>',
    '</div>',
    icerik_html,
    '<div class="cc-tool-result cc-tool-result-pending">',
    '<div class="cc-tool-result-loading">',
    '<i class="fas fa-ellipsis-h fa-fade"></i> Çalışıyor...</div>',
    '</div>',
    '</div>'
  )
}

# ------------------------------------------------------------------------------
# ARAÇ SONUCU KISMI HTML
# Araç sonucunu mevcut bloğa eklenecek biçimde döndürür.
# ------------------------------------------------------------------------------

#' Araç sonucunu HTML parçasına dönüştür
#'
#' @param icerik Sonuç içeriği (metin)
#' @return HTML metni
format_tool_result_snippet <- function(icerik) {
  if (is.null(icerik) || !nzchar(icerik)) return("")

  # Sonucu kısalt
  kisaltilmis <- if (nchar(icerik) > 1000) {
    paste0(substr(icerik, 1, 1000), "\n... (kısaltıldı)")
  } else {
    icerik
  }

  paste0(
    '<pre class="cc-tool-result-pre">',
    htmltools::htmlEscape(kisaltilmis),
    '</pre>'
  )
}

# ------------------------------------------------------------------------------
# ARAÇ GÖRÜNTÜLEME BİLGİSİ
# Araç türüne göre ikon ve başlık döndürür.
# ------------------------------------------------------------------------------

#' Araç türüne göre görüntüleme bilgisi al
#'
#' @param arac_turu Araç türü (bash, file_read, file_write, search, other)
#' @param arac_adi Araç adı (yedek başlık için)
#' @return Liste: ikon (FontAwesome), baslik (Türkçe)
get_tool_display_info <- function(arac_turu, arac_adi = "") {
  bilgiler <- list(
    bash = list(ikon = "terminal", baslik = "Kabuk Komutu"),
    file_read = list(ikon = "file-code", baslik = "Dosya Okuma"),
    file_write = list(ikon = "pen", baslik = "Dosya Yazma"),
    search = list(ikon = "search", baslik = "Arama"),
    other = list(ikon = "cog", baslik = if (nzchar(arac_adi)) arac_adi else "Araç")
  )

  bilgiler[[arac_turu]] %||% bilgiler[["other"]]
}

# ------------------------------------------------------------------------------
# GELİŞMİŞ ARAÇ KULLANIMI HTML BİÇİMLENDİRME
# format_tool_uses_html fonksiyonunun gelişmiş sürümü.
# Kabuk görünürlüğü düğmesi ve dosya önizlemeleri içerir.
# ------------------------------------------------------------------------------

#' Araç kullanımlarını gelişmiş HTML formatına dönüştür
#'
#' @param tool_uses Araç kullanımları listesi
#' @return HTML formatlı metin
format_tool_uses_html_enhanced <- function(tool_uses) {
  if (length(tool_uses) == 0) return("")

  html_parcalari <- lapply(tool_uses, function(arac) {
    arac_adi <- arac$name %||% "bilinmeyen"
    girdi <- arac$input %||% list()
    sonuc_metni <- arac$result %||% ""

    # Araç türünü tespit et
    arac_turu <- detect_tool_type(arac_adi)
    arac_bilgisi <- get_tool_display_info(arac_turu, arac_adi)

    # İçerik alanı
    icerik <- ""
    if (arac_turu == "bash") {
      komut <- girdi$command %||% girdi$cmd %||% ""
      if (nzchar(komut)) {
        icerik <- paste0(
          '<div class="cc-tool-content cc-shell-content">',
          '<code class="cc-tool-command cc-shell-command">',
          '<span class="cc-shell-prompt">$ </span>',
          htmltools::htmlEscape(komut),
          '</code></div>'
        )
      }
    } else if (arac_turu == "file_read") {
      dosya <- girdi$path %||% girdi$file_path %||% ""
      if (nzchar(dosya)) {
        icerik <- paste0(
          '<div class="cc-tool-content">',
          '<span class="cc-tool-path">',
          '<i class="fas fa-file-code cc-tool-path-icon"></i> ',
          htmltools::htmlEscape(dosya),
          '</span></div>'
        )
      }
    } else if (arac_turu == "file_write") {
      dosya <- girdi$path %||% girdi$file_path %||% ""
      dosya_icerigi <- girdi$content %||% girdi$new_content %||% ""
      if (nzchar(dosya)) {
        onizleme <- ""
        if (nzchar(dosya_icerigi)) {
          satirlar <- strsplit(dosya_icerigi, "\n")[[1]]
          ilk_satirlar <- head(satirlar, 10)
          kisaltildi <- length(satirlar) > 10
          onizleme_metni <- paste(ilk_satirlar, collapse = "\n")
          if (kisaltildi) {
            onizleme_metni <- paste0(onizleme_metni, "\n... (+",
                                      length(satirlar) - 10, " satır daha)")
          }
          onizleme <- paste0(
            '<div class="cc-file-preview">',
            '<div class="cc-file-preview-header">',
            '<i class="fas fa-eye"></i> Dosya Önizlemesi',
            '</div>',
            '<pre class="cc-file-preview-content">',
            htmltools::htmlEscape(onizleme_metni),
            '</pre></div>'
          )
        }
        icerik <- paste0(
          '<div class="cc-tool-content">',
          '<span class="cc-tool-path">',
          '<i class="fas fa-pen cc-tool-path-icon"></i> ',
          htmltools::htmlEscape(dosya),
          '</span>',
          onizleme,
          '</div>'
        )
      }
    } else if (arac_turu == "search") {
      desen <- girdi$pattern %||% girdi$query %||% ""
      if (nzchar(desen)) {
        icerik <- paste0(
          '<div class="cc-tool-content">',
          '<span class="cc-tool-path">',
          '<i class="fas fa-search cc-tool-path-icon"></i> ',
          htmltools::htmlEscape(desen),
          '</span></div>'
        )
      }
    }

    # Sonuç HTML
    sonuc_html <- ""
    if (nzchar(sonuc_metni)) {
      sonuc_kisaltilmis <- if (nchar(sonuc_metni) > 1000) {
        paste0(substr(sonuc_metni, 1, 1000), "\n... (kısaltıldı)")
      } else {
        sonuc_metni
      }
      sonuc_html <- paste0(
        '<div class="cc-tool-result"><pre class="cc-tool-result-pre">',
        htmltools::htmlEscape(sonuc_kisaltilmis),
        '</pre></div>'
      )
    }

    paste0(
      '<div class="cc-tool-block cc-shell-block" data-tool-type="', arac_turu, '">',
      '<div class="cc-tool-header">',
      '<i class="fas fa-', arac_bilgisi$ikon, '"></i> ',
      '<span class="cc-tool-title">', htmltools::htmlEscape(arac_bilgisi$baslik), '</span>',
      '<i class="fas fa-chevron-down cc-tool-toggle-icon"></i>',
      '</div>',
      icerik,
      sonuc_html,
      '</div>'
    )
  })

  # Tümü sarmalayıcı: kabuk görünürlüğü düğmesi ile
  paste0(
    '<div class="cc-tool-section">',
    '<div class="cc-tool-section-header">',
    '<i class="fas fa-cogs"></i> Araç Kullanımları ',
    '<span class="cc-tool-count">(', length(tool_uses), ')</span>',
    '<span class="cc-tool-toggle-all" ',
    'onclick="window.ccToggleAllTools(this)" ',
    'title="Tümünü gizle/göster">',
    '<i class="fas fa-eye"></i></span>',
    '<span class="cc-shell-visibility-toggle" ',
    'onclick="window.ccToggleShellVisibility(this)" ',
    'title="Kabuk komutlarını gizle/göster">',
    '<i class="fas fa-terminal"></i></span>',
    '</div>',
    paste(html_parcalari, collapse = "\n"),
    '</div>'
  )
}