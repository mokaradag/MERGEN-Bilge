# ==============================================================================
# Dosya Yolu: bilge_yolac_plugins/office/templates/pptx_helpers.R
# Açıklama: PPTX sunum oluşturma yardımcı fonksiyonları.
#           officer paketini kullanır. Bağımsız çalışır, internet gerektirmez.
#           Kullanım: Bu dosyayı source() ile yükleyin, ardından fonksiyonları çağırın.
# Gerekli paket: officer
# ==============================================================================

# --- Temel sunum oluşturma ---
pptx_olustur <- function(sablon_yolu = NULL) {
  if (!requireNamespace("officer", quietly = TRUE)) {
    stop("officer paketi gerekli. install.packages('officer') ile kurun.")
  }

  if (!is.null(sablon_yolu) && file.exists(sablon_yolu)) {
    officer::read_pptx(sablon_yolu)
  } else {
    officer::read_pptx()
  }
}

# --- Kullanılabilir düzenleri listele ---
pptx_duzenleri_listele <- function(pptx) {
  duzenler <- officer::layout_summary(pptx)
  message("Kullanılabilir düzenler:")
  print(duzenler[, c("layout", "master")])
  invisible(duzenler)
}

# --- Başlık slaydı ekleme ---
pptx_baslik_slaydi <- function(pptx, baslik, alt_baslik = NULL,
                                duzen = "Title Slide",
                                master = "Office Theme") {
  pptx <- officer::add_slide(pptx, layout = duzen, master = master)
  pptx <- officer::ph_with(
    pptx,
    value = baslik,
    location = officer::ph_location_type(type = "ctrTitle")
  )
  if (!is.null(alt_baslik)) {
    pptx <- officer::ph_with(
      pptx,
      value = alt_baslik,
      location = officer::ph_location_type(type = "subTitle")
    )
  }
  pptx
}

# --- İçerik slaydı ekleme (başlık + metin) ---
pptx_icerik_slaydi <- function(pptx, baslik, icerik,
                                duzen = "Title and Content",
                                master = "Office Theme") {
  pptx <- officer::add_slide(pptx, layout = duzen, master = master)
  pptx <- officer::ph_with(
    pptx,
    value = baslik,
    location = officer::ph_location_type(type = "title")
  )
  pptx <- officer::ph_with(
    pptx,
    value = icerik,
    location = officer::ph_location_type(type = "body")
  )
  pptx
}

# --- Madde işaretli slayt ekleme ---
pptx_liste_slaydi <- function(pptx, baslik, maddeler,
                               duzen = "Title and Content",
                               master = "Office Theme") {
  # Maddeleri tek metin olarak birleştir (her biri yeni satır)
  birlesik_metin <- paste(paste("\u2022", maddeler), collapse = "\n")

  pptx_icerik_slaydi(pptx, baslik, birlesik_metin, duzen, master)
}

# --- Tablo slaydı ekleme ---
pptx_tablo_slaydi <- function(pptx, baslik, veri,
                               duzen = "Title and Content",
                               master = "Office Theme") {
  pptx <- officer::add_slide(pptx, layout = duzen, master = master)
  pptx <- officer::ph_with(
    pptx,
    value = baslik,
    location = officer::ph_location_type(type = "title")
  )

  if (requireNamespace("flextable", quietly = TRUE)) {
    ft <- flextable::flextable(veri)
    ft <- flextable::theme_zebra(ft)
    ft <- flextable::autofit(ft)
    ft <- flextable::fontsize(ft, size = 10, part = "all")
    pptx <- officer::ph_with(
      pptx,
      value = ft,
      location = officer::ph_location_type(type = "body")
    )
  } else {
    # flextable yoksa metin tablosu olarak ekle
    tablo_metin <- paste(capture.output(print(veri)), collapse = "\n")
    pptx <- officer::ph_with(
      pptx,
      value = tablo_metin,
      location = officer::ph_location_type(type = "body")
    )
  }

  pptx
}

# --- Grafik slaydı ekleme (ggplot) ---
pptx_grafik_slaydi <- function(pptx, baslik, grafik,
                                duzen = "Title and Content",
                                master = "Office Theme") {
  pptx <- officer::add_slide(pptx, layout = duzen, master = master)
  pptx <- officer::ph_with(
    pptx,
    value = baslik,
    location = officer::ph_location_type(type = "title")
  )

  if (requireNamespace("ggplot2", quietly = TRUE) && inherits(grafik, "gg")) {
    pptx <- officer::ph_with(
      pptx,
      value = grafik,
      location = officer::ph_location_type(type = "body")
    )
  }

  pptx
}

# --- Boş slayt (özel konumlandırma için) ---
pptx_bos_slayt <- function(pptx, duzen = "Blank", master = "Office Theme") {
  officer::add_slide(pptx, layout = duzen, master = master)
}

# --- Özel konumda metin ekleme ---
pptx_metin_ekle <- function(pptx, metin, sol = 1, ust = 1,
                             genislik = 4, yukseklik = 1,
                             boyut = 14, kalin = FALSE) {
  fp <- officer::fp_text(
    font.size = boyut,
    bold = kalin
  )
  blok <- officer::fpar(officer::ftext(metin, prop = fp))

  officer::ph_with(
    pptx,
    value = blok,
    location = officer::ph_location(
      left = sol, top = ust,
      width = genislik, height = yukseklik
    )
  )
}

# --- Sunumu kaydet ---
pptx_kaydet <- function(pptx, dosya_yolu) {
  print(pptx, target = dosya_yolu)
  message(paste("PPTX kaydedildi:", dosya_yolu))
  invisible(dosya_yolu)
}

# ==============================================================================
# ÖRNEK KULLANIM
# ==============================================================================
# source("bilge_yolac_plugins/office/templates/pptx_helpers.R")
#
# sunum <- pptx_olustur()
#
# # Başlık slaydı
# sunum <- pptx_baslik_slaydi(sunum,
#   baslik = "Proje Durum Raporu",
#   alt_baslik = "Ocak 2024 - Proje Ekibi"
# )
#
# # Gündem slaydı
# sunum <- pptx_liste_slaydi(sunum,
#   baslik = "Gündem",
#   maddeler = c("Proje özeti", "Tamamlanan işler", "Planlanan adımlar", "Sorular")
# )
#
# # İçerik slaydı
# sunum <- pptx_icerik_slaydi(sunum,
#   baslik = "Proje Özeti",
#   icerik = "Proje planına uygun şekilde ilerlenmektedir."
# )
#
# # Tablo slaydı
# sunum <- pptx_tablo_slaydi(sunum,
#   baslik = "Performans Verileri",
#   veri = data.frame(Metrik = c("Tamamlama", "Bütçe", "Kalite"),
#                     Durum = c("%85", "%92", "İyi"))
# )
#
# pptx_kaydet(sunum, "sunum.pptx")
# ==============================================================================