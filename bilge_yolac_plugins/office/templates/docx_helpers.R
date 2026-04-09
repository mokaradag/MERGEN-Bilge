# ==============================================================================
# Dosya Yolu: bilge_yolac_plugins/office/templates/docx_helpers.R
# Açıklama: DOCX dosya oluşturma yardımcı fonksiyonları.
#           officer paketini kullanır. Bağımsız çalışır, internet gerektirmez.
#           Kullanım: Bu dosyayı source() ile yükleyin, ardından fonksiyonları çağırın.
# Gerekli paket: officer
# ==============================================================================

# --- Temel DOCX oluşturma ---
docx_olustur <- function(dosya_yolu,
                         baslik = NULL,
                         alt_baslik = NULL,
                         yazar = NULL,
                         tarih = format(Sys.Date(), "%d.%m.%Y"),
                         sablon_yolu = NULL) {
  if (!requireNamespace("officer", quietly = TRUE)) {
    stop("officer paketi gerekli. install.packages('officer') ile kurun.")
  }

  # Şablon veya boş belge

  if (!is.null(sablon_yolu) && file.exists(sablon_yolu)) {
    doc <- officer::read_docx(sablon_yolu)
  } else {
    doc <- officer::read_docx()
  }

  # Başlık sayfası

  if (!is.null(baslik)) {
    doc <- officer::body_add_par(doc, baslik, style = "heading 1")
  }
  if (!is.null(alt_baslik)) {
    doc <- officer::body_add_par(doc, alt_baslik, style = "heading 2")
  }
  if (!is.null(yazar)) {
    doc <- officer::body_add_par(doc, paste("Hazırlayan:", yazar))
  }
  if (!is.null(tarih)) {
    doc <- officer::body_add_par(doc, paste("Tarih:", tarih))
  }

  doc
}

# --- Paragraf ekleme ---
docx_paragraf_ekle <- function(doc, metin, stil = "Normal") {
  officer::body_add_par(doc, metin, style = stil)
}

# --- Başlık ekleme (seviye 1-3) ---
docx_baslik_ekle <- function(doc, metin, seviye = 1) {
  stil <- paste("heading", seviye)
  officer::body_add_par(doc, metin, style = stil)
}

# --- Tablo ekleme ---
docx_tablo_ekle <- function(doc, veri, baslik_metin = NULL) {
  if (!is.null(baslik_metin)) {
    doc <- officer::body_add_par(doc, baslik_metin, style = "heading 3")
  }

  # flextable varsa gelişmiş tablo, yoksa basit tablo

  if (requireNamespace("flextable", quietly = TRUE)) {
    ft <- flextable::flextable(veri)
    ft <- flextable::theme_zebra(ft)
    ft <- flextable::autofit(ft)
    ft <- flextable::set_header_labels(ft, values = setNames(names(veri), names(veri)))
    doc <- flextable::body_add_flextable(doc, ft)
  } else {
    doc <- officer::body_add_table(doc, veri, style = "table_template")
  }

  doc
}

# --- Madde işaretli liste ekleme ---
docx_liste_ekle <- function(doc, maddeler) {
  for (madde in maddeler) {
    doc <- officer::body_add_par(doc, madde, style = "List Bullet")
  }
  doc
}

# --- Numaralı liste ekleme ---
docx_numarali_liste_ekle <- function(doc, maddeler) {
  for (madde in maddeler) {
    doc <- officer::body_add_par(doc, madde, style = "List Number")
  }
  doc
}

# --- Grafik ekleme (ggplot veya base R) ---
docx_grafik_ekle <- function(doc, grafik = NULL, genislik = 6, yukseklik = 4) {
  if (!is.null(grafik) && requireNamespace("ggplot2", quietly = TRUE)) {
    doc <- officer::body_add_gg(doc, value = grafik, width = genislik, height = yukseklik)
  }
  doc
}

# --- Sayfa sonu ekleme ---
docx_sayfa_sonu <- function(doc) {
  officer::body_add_break(doc, pos = "after")
}

# --- Belgeyi kaydet ---
docx_kaydet <- function(doc, dosya_yolu) {
  print(doc, target = dosya_yolu)
  message(paste("DOCX kaydedildi:", dosya_yolu))
  invisible(dosya_yolu)
}

# ==============================================================================
# ÖRNEK KULLANIM
# ==============================================================================
# source("bilge_yolac_plugins/office/templates/docx_helpers.R")
#
# doc <- docx_olustur(
#   baslik     = "Aylık Faaliyet Raporu",
#   alt_baslik = "Ocak 2024",
#   yazar      = "Proje Ekibi"
# )
#
# doc <- docx_baslik_ekle(doc, "1. Genel Bakış", seviye = 1)
# doc <- docx_paragraf_ekle(doc, "Bu rapor Ocak ayı faaliyetlerini kapsar.")
#
# doc <- docx_baslik_ekle(doc, "2. Sonuçlar", seviye = 1)
# doc <- docx_tablo_ekle(doc, head(iris, 10), baslik_metin = "Örnek Veri")
#
# doc <- docx_baslik_ekle(doc, "3. Öneriler", seviye = 1)
# doc <- docx_liste_ekle(doc, c("Süreç iyileştirmesi", "Kaynak artırımı", "Eğitim"))
#
# docx_kaydet(doc, "rapor.docx")
# ==============================================================================
