# Dosya Yolu: R/helpers_admin_geri_bildirim_output_tables.R
# Açıklama: Yönetici paneli Geri Bildirim Analizi çıktı tabloları için saf
#           veri hazırlama yardımcıları. Shiny/DT renderer kaydı
#           R/module_admin_geri_bildirim_outputs.R içinde kalır.

#' Kullanıcı bazlı memnuniyet tablosu görünüm verisini hazırlar
#' @param data admin_gb_fetch_data()$kullanici_memnuniyet çıktısı
#' @return DT::datatable öncesi Türkçe başlıklı data.frame
admin_gb_prepare_kullanici_table_data <- function(data) {
  if (nrow(data) == 0) return(data.frame())

  data$row_num <- seq_len(nrow(data))
  data$ort_memnuniyet <- round(data$ort_memnuniyet, 1)
  data$ort_nps <- round(data$ort_nps, 1)
  data$son_bildirim <- format(as.POSIXct(data$son_bildirim), "%d.%m.%Y %H:%M")

  display_data <- data[, c(
    "row_num", "KullaniciAdi", "bildirim_sayisi",
    "ort_memnuniyet", "ort_nps", "son_bildirim"
  )]
  colnames(display_data) <- c(
    "#", "Kullanıcı", "Bildirim", "Ort. Memnuniyet", "Ort. NPS", "Son Bildirim"
  )

  display_data
}

.admin_gb_nps_display <- function(puan) {
  if (is.na(puan)) return("-")

  renk <- if (puan >= 9) {
    "#10b981"
  } else if (puan >= 7) {
    "#f59e0b"
  } else {
    "#ef4444"
  }

  sprintf('<span style="color:%s; font-weight:bold;">%d</span>', renk, puan)
}

.admin_gb_mailto_icon <- function(row) {
  if (!isTRUE(row$IletisimIzni == 1) || is.na(row$EmailAddress) || !nzchar(row$EmailAddress)) {
    return("")
  }

  kullanici_adi <- ifelse(
    !is.na(row$KullaniciAdi) && nzchar(row$KullaniciAdi),
    row$KullaniciAdi,
    "Kullanıcı"
  )
  konu <- utils::URLencode(paste0("MERGEN Bilge - Geri Bildirim #", row$GeriBildirimID))
  govde <- utils::URLencode(paste0(
    "Sayın ", kullanici_adi, ",\n\n",
    "MERGEN Bilge uygulamasına bıraktığınız geri bildirim (",
    format(as.POSIXct(row$OlusturmaTarihi), "%d.%m.%Y"),
    ") hakkında sizinle iletişime geçmek istiyoruz.\n\n",
    "Saygılarımızla,\nMERGEN Bilge Yönetim Ekibi"
  ))

  sprintf(
    '<a href="mailto:%s?subject=%s&body=%s" title="%s adresine e-posta gönder" class="admin-mail-icon"><i class="fas fa-envelope"></i></a>',
    htmltools::htmlEscape(row$EmailAddress), konu, govde,
    htmltools::htmlEscape(row$EmailAddress)
  )
}

#' Detaylı geri bildirim tablosu görünüm verisini hazırlar
#' @param data admin_gb_fetch_data()$tumu çıktısı
#' @return DT::datatable öncesi Türkçe başlıklı data.frame
admin_gb_prepare_detay_table_data <- function(data) {
  if (nrow(data) == 0) return(data.frame())

  data$row_num <- seq_len(nrow(data))

  memn_emoji <- c("\U0001F621", "\U0001F61E", "\U0001F610", "\U0001F60A", "\U0001F929")
  data$memn_display <- ifelse(
    !is.na(data$Memnuniyet) & data$Memnuniyet >= 1 & data$Memnuniyet <= 5,
    paste0(memn_emoji[data$Memnuniyet], " ", data$Memnuniyet, "/5"),
    "-"
  )
  data$memn_sort <- ifelse(!is.na(data$Memnuniyet), data$Memnuniyet, 0)

  data$nps_display <- vapply(data$NPS_Puan, .admin_gb_nps_display, character(1))
  data$nps_sort <- ifelse(!is.na(data$NPS_Puan), data$NPS_Puan, -1)

  data$tarih <- format(as.POSIXct(data$OlusturmaTarihi), "%d.%m.%Y %H:%M")
  data$etiketler_display <- ifelse(!is.na(data$Etiketler) & nzchar(data$Etiketler), data$Etiketler, "-")
  data$sevilen_display <- ifelse(!is.na(data$EnCokSevilen) & nzchar(data$EnCokSevilen), data$EnCokSevilen, "-")
  data$gelistirme_display <- ifelse(!is.na(data$Gelistirme) & nzchar(data$Gelistirme), data$Gelistirme, "-")

  data$iletisim_display <- ifelse(
    data$IletisimIzni == 1,
    '<span style="color:#10b981;"><i class="fas fa-check-circle"></i> Evet</span>',
    '<span style="color:#ef4444;"><i class="fas fa-times-circle"></i> Hayır</span>'
  )

  data$eposta_display <- vapply(seq_len(nrow(data)), function(i) {
    .admin_gb_mailto_icon(data[i, , drop = FALSE])
  }, character(1))

  data$kullanici <- ifelse(!is.na(data$KullaniciAdi) & nzchar(data$KullaniciAdi), data$KullaniciAdi, "-")

  display_data <- data[, c(
    "row_num", "kullanici", "memn_display", "memn_sort",
    "nps_display", "nps_sort", "etiketler_display", "sevilen_display",
    "gelistirme_display", "iletisim_display", "eposta_display", "tarih"
  )]
  colnames(display_data) <- c(
    "#", "Kullanıcı", "Memnuniyet", "memn_sort", "NPS", "nps_sort",
    "Etiketler", "En Çok Sevilen", "Geliştirilecek", "İletişim İzni", "\U0001F4E7", "Tarih"
  )

  display_data
}
