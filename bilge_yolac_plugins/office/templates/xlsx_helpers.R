# ==============================================================================
# Dosya Yolu: bilge_yolac_plugins/office/templates/xlsx_helpers.R
# Açıklama: XLSX dosya oluşturma yardımcı fonksiyonları.
#           openxlsx paketini kullanır. Java gerektirmez, internet gerektirmez.
#           Kullanım: Bu dosyayı source() ile yükleyin, ardından fonksiyonları çağırın.
# Gerekli paket: openxlsx
# ==============================================================================

# --- Temel XLSX çalışma kitabı oluşturma ---
xlsx_olustur <- function() {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("openxlsx paketi gerekli. install.packages('openxlsx') ile kurun.")
  }
  openxlsx::createWorkbook()
}

# --- Sayfa ekleme ---
xlsx_sayfa_ekle <- function(wb, sayfa_adi) {
  openxlsx::addWorksheet(wb, sayfa_adi)
  invisible(wb)
}

# --- Başlık stili oluşturma ---
xlsx_baslik_stili <- function(yazi_renk = "#FFFFFF",
                              arka_plan = "#4472C4",
                              kalin = TRUE,
                              boyut = 11) {
  openxlsx::createStyle(
    fontColour    = yazi_renk,
    fgFill        = arka_plan,
    textDecoration = if (kalin) "bold" else NULL,
    fontSize      = boyut,
    halign        = "center",
    valign        = "center",
    border        = "TopBottomLeftRight",
    borderColour  = "#999999"
  )
}

# --- Veri yazma (başlık stili ile) ---
xlsx_veri_yaz <- function(wb, sayfa, veri,
                          baslangic_satir = 1,
                          baslangic_sutun = 1,
                          baslik_stili = NULL) {
  openxlsx::writeData(
    wb, sayfa, veri,
    startRow = baslangic_satir,
    startCol = baslangic_sutun,
    headerStyle = baslik_stili %||% xlsx_baslik_stili()
  )

  # Sütun genişliğini otomatik ayarla
  sutun_sayisi <- ncol(veri)
  openxlsx::setColWidths(
    wb, sayfa,
    cols = baslangic_sutun:(baslangic_sutun + sutun_sayisi - 1),
    widths = "auto"
  )

  invisible(wb)
}

# --- Filtre ekleme ---
xlsx_filtre_ekle <- function(wb, sayfa, veri, baslangic_satir = 1) {
  openxlsx::addFilter(
    wb, sayfa,
    rows = baslangic_satir,
    cols = seq_len(ncol(veri))
  )
  invisible(wb)
}

# --- Satırları dondur (başlık satırı sabit) ---
xlsx_satir_dondur <- function(wb, sayfa, ilk_satir = 2, ilk_sutun = 1) {
  openxlsx::freezePane(wb, sayfa, firstActiveRow = ilk_satir, firstActiveCol = ilk_sutun)
  invisible(wb)
}

# --- Koşullu biçimlendirme (renk skalası) ---
xlsx_renk_skalasi <- function(wb, sayfa, sutun, satir_baslangic, satir_bitis,
                               renkler = c("#F8696B", "#FFEB84", "#63BE7B")) {
  openxlsx::conditionalFormatting(
    wb, sayfa,
    cols = sutun,
    rows = satir_baslangic:satir_bitis,
    type = "colourScale",
    style = renkler
  )
  invisible(wb)
}

# --- Sayı biçimlendirme ---
xlsx_sayi_bicimi <- function(wb, sayfa, sutunlar, satir_baslangic, satir_bitis,
                              bicim = "#,##0.00") {
  stil <- openxlsx::createStyle(numFmt = bicim)
  openxlsx::addStyle(
    wb, sayfa, style = stil,
    rows = satir_baslangic:satir_bitis,
    cols = sutunlar,
    gridExpand = TRUE
  )
  invisible(wb)
}

# --- Tarih biçimlendirme ---
xlsx_tarih_bicimi <- function(wb, sayfa, sutunlar, satir_baslangic, satir_bitis,
                               bicim = "DD.MM.YYYY") {
  stil <- openxlsx::createStyle(numFmt = bicim)
  openxlsx::addStyle(
    wb, sayfa, style = stil,
    rows = satir_baslangic:satir_bitis,
    cols = sutunlar,
    gridExpand = TRUE
  )
  invisible(wb)
}

# --- Para birimi biçimlendirme ---
xlsx_para_bicimi <- function(wb, sayfa, sutunlar, satir_baslangic, satir_bitis,
                              para_birimi = "TL") {
  bicim <- switch(para_birimi,
    "TL"  = '#,##0.00 "TL"',
    "USD" = '$#,##0.00',
    "EUR" = '\u20AC#,##0.00',
    '#,##0.00'
  )
  xlsx_sayi_bicimi(wb, sayfa, sutunlar, satir_baslangic, satir_bitis, bicim)
}

# --- Özet satırı ekleme (TOPLAM, ORTALAMA vb.) ---
xlsx_ozet_satiri <- function(wb, sayfa, veri,
                              baslangic_satir = 1,
                              etiket = "TOPLAM",
                              fonksiyon = "SUM") {
  satir_sayisi <- nrow(veri)
  sutun_sayisi <- ncol(veri)
  ozet_satir <- baslangic_satir + satir_sayisi  # Başlık + veri sonrası

  # Etiket yaz
  openxlsx::writeData(wb, sayfa, etiket, startRow = ozet_satir, startCol = 1)

  # Sayısal sütunlar için formül ekle
  for (j in seq_len(sutun_sayisi)) {
    if (is.numeric(veri[[j]])) {
      hucre_baslangic <- paste0(
        openxlsx::int2col(j), baslangic_satir + 1  # Başlık sonrası
      )
      hucre_bitis <- paste0(
        openxlsx::int2col(j), baslangic_satir + satir_sayisi
      )
      formul <- paste0(fonksiyon, "(", hucre_baslangic, ":", hucre_bitis, ")")
      openxlsx::writeFormula(wb, sayfa, formul, startRow = ozet_satir, startCol = j)
    }
  }

  # Özet satırını kalın yap
  kalin_stil <- openxlsx::createStyle(textDecoration = "bold", border = "Top")
  openxlsx::addStyle(
    wb, sayfa, style = kalin_stil,
    rows = ozet_satir, cols = 1:sutun_sayisi,
    gridExpand = TRUE
  )

  invisible(wb)
}

# --- Çalışma kitabını kaydet ---
xlsx_kaydet <- function(wb, dosya_yolu) {
  openxlsx::saveWorkbook(wb, dosya_yolu, overwrite = TRUE)
  message(paste("XLSX kaydedildi:", dosya_yolu))
  invisible(dosya_yolu)
}

# ==============================================================================
# ÖRNEK KULLANIM
# ==============================================================================
# source("bilge_yolac_plugins/office/templates/xlsx_helpers.R")
#
# wb <- xlsx_olustur()
# xlsx_sayfa_ekle(wb, "Satış Verileri")
#
# veri <- data.frame(
#   Ürün   = c("Kalem", "Defter", "Silgi"),
#   Adet   = c(100, 50, 200),
#   Fiyat  = c(5.50, 12.00, 3.25),
#   Toplam = c(550, 600, 650)
# )
#
# xlsx_veri_yaz(wb, "Satış Verileri", veri)
# xlsx_filtre_ekle(wb, "Satış Verileri", veri)
# xlsx_satir_dondur(wb, "Satış Verileri")
# xlsx_para_bicimi(wb, "Satış Verileri", sutunlar = 3:4, satir_baslangic = 2, satir_bitis = 4)
# xlsx_ozet_satiri(wb, "Satış Verileri", veri, etiket = "TOPLAM")
#
# xlsx_kaydet(wb, "satis_raporu.xlsx")
# ==============================================================================
