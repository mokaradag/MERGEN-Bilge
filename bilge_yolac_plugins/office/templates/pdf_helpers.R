# ==============================================================================
# Dosya Yolu: bilge_yolac_plugins/office/templates/pdf_helpers.R
# Açıklama: PDF dosya oluşturma yardımcı fonksiyonları.
#           R'nin yerleşik grDevices (pdf/cairo_pdf) ve rmarkdown kullanır.
#           Bağımsız çalışır, internet gerektirmez.
#           Kullanım: Bu dosyayı source() ile yükleyin, ardından fonksiyonları çağırın.
# Gerekli paket: grDevices (yerleşik), opsiyonel: rmarkdown, tinytex
# ==============================================================================

# --- Grafik tabanlı PDF oluşturma (her zaman çalışır, ek paket gerekmez) ---
pdf_grafik_olustur <- function(dosya_yolu,
                                genislik = 10,
                                yukseklik = 7,
                                baslik = NULL,
                                turkce_font = TRUE) {
  # Türkçe karakter desteği için cairo_pdf tercih et
  if (turkce_font && capabilities("cairo")) {
    grDevices::cairo_pdf(dosya_yolu, width = genislik, height = yukseklik)
  } else {
    grDevices::pdf(dosya_yolu, width = genislik, height = yukseklik)
  }

  if (!is.null(baslik)) {
    plot.new()
    title(main = baslik)
  }

  message(paste("PDF cihazı açıldı:", dosya_yolu))
  message("Grafikleri çizdikten sonra pdf_kapat() çağırın.")
  invisible(dosya_yolu)
}

# --- PDF cihazını kapat ---
pdf_kapat <- function() {
  grDevices::dev.off()
  message("PDF kaydedildi.")
}

# --- Çoklu grafik PDF (liste halinde grafikler) ---
pdf_coklu_grafik <- function(dosya_yolu, grafik_listesi,
                              genislik = 10, yukseklik = 7) {
  if (capabilities("cairo")) {
    grDevices::cairo_pdf(dosya_yolu, width = genislik, height = yukseklik,
                         onefile = TRUE)
  } else {
    grDevices::pdf(dosya_yolu, width = genislik, height = yukseklik,
                   onefile = TRUE)
  }

  for (g in grafik_listesi) {
    if (requireNamespace("ggplot2", quietly = TRUE) && inherits(g, "gg")) {
      print(g)
    } else if (is.function(g)) {
      g()  # Base R grafik fonksiyonu
    }
  }

  grDevices::dev.off()
  message(paste("PDF kaydedildi:", dosya_yolu, "-", length(grafik_listesi), "sayfa"))
  invisible(dosya_yolu)
}

# --- Tablo PDF'e çevirme (flextable ile) ---
pdf_tablo_olustur <- function(dosya_yolu, veri, baslik = NULL) {
  if (!requireNamespace("flextable", quietly = TRUE)) {
    stop("Tablo PDF için flextable paketi gerekli. install.packages('flextable')")
  }

  ft <- flextable::flextable(veri)
  ft <- flextable::theme_zebra(ft)
  ft <- flextable::autofit(ft)

  if (!is.null(baslik)) {
    ft <- flextable::add_header_lines(ft, values = baslik)
    ft <- flextable::bold(ft, part = "header")
  }

  flextable::save_as_image(ft, path = dosya_yolu)
  message(paste("Tablo PDF kaydedildi:", dosya_yolu))
  invisible(dosya_yolu)
}

# --- RMarkdown tabanlı PDF (tinytex kurulu olmalı) ---
pdf_rapor_olustur <- function(rmd_icerik, dosya_yolu,
                               baslik = "Rapor",
                               yazar = NULL,
                               tarih = format(Sys.Date(), "%d.%m.%Y")) {
  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("rmarkdown paketi gerekli. install.packages('rmarkdown')")
  }

  # YAML başlığı oluştur
  yaml_baslik <- paste0(
    "---\n",
    'title: "', baslik, '"\n',
    if (!is.null(yazar)) paste0('author: "', yazar, '"\n') else "",
    'date: "', tarih, '"\n',
    "output:\n",
    "  pdf_document:\n",
    "    latex_engine: xelatex\n",
    "    keep_tex: false\n",
    "header-includes:\n",
    "  - \\usepackage{fontspec}\n",
    "---\n\n"
  )

  # Geçici Rmd dosyası oluştur
  gecici_rmd <- tempfile(fileext = ".Rmd")
  writeLines(paste0(yaml_baslik, rmd_icerik), gecici_rmd, useBytes = FALSE)

  tryCatch({
    rmarkdown::render(
      gecici_rmd,
      output_file = basename(dosya_yolu),
      output_dir = dirname(dosya_yolu),
      quiet = TRUE
    )
    message(paste("PDF rapor kaydedildi:", dosya_yolu))
  }, error = function(e) {
    message(paste("PDF oluşturma hatası:", conditionMessage(e)))
    message("Not: PDF rapor için tinytex veya TeX kurulumu gereklidir.")
    message("Alternatif: pdf_grafik_olustur() veya pdf_tablo_olustur() kullanın.")
  }, finally = {
    unlink(gecici_rmd)
  })

  invisible(dosya_yolu)
}

# --- Basit metin PDF (hiç ek paket gerektirmez) ---
pdf_metin_olustur <- function(dosya_yolu, satirlar,
                               baslik = NULL,
                               sayfa_genisligi = 10,
                               sayfa_yuksekligi = 7,
                               satir_yuksekligi = 0.4,
                               kenar_boslugu = 1) {
  if (capabilities("cairo")) {
    grDevices::cairo_pdf(dosya_yolu, width = sayfa_genisligi, height = sayfa_yuksekligi)
  } else {
    grDevices::pdf(dosya_yolu, width = sayfa_genisligi, height = sayfa_yuksekligi)
  }

  # Sayfa başına satır hesapla
  kullanilabilir_yukseklik <- sayfa_yuksekligi - (2 * kenar_boslugu)
  sayfa_basina_satir <- floor(kullanilabilir_yukseklik / satir_yuksekligi)

  # Başlık varsa ilk satır olarak ekle
  tum_satirlar <- if (!is.null(baslik)) c(baslik, "", satirlar) else satirlar

  # Sayfalara böl
  sayfa_sayisi <- ceiling(length(tum_satirlar) / sayfa_basina_satir)

  for (sayfa in seq_len(sayfa_sayisi)) {
    if (sayfa > 1) plot.new()

    plot(0, 0, type = "n",
         xlim = c(0, sayfa_genisligi),
         ylim = c(0, sayfa_yuksekligi),
         axes = FALSE, xlab = "", ylab = "")

    baslangic <- (sayfa - 1) * sayfa_basina_satir + 1
    bitis <- min(sayfa * sayfa_basina_satir, length(tum_satirlar))
    sayfa_satirlari <- tum_satirlar[baslangic:bitis]

    for (i in seq_along(sayfa_satirlari)) {
      y_konum <- sayfa_yuksekligi - kenar_boslugu - (i * satir_yuksekligi)
      kalin <- (sayfa == 1 && i == 1 && !is.null(baslik))
      text(kenar_boslugu, y_konum, sayfa_satirlari[i],
           adj = c(0, 0.5), cex = if (kalin) 1.3 else 0.9,
           font = if (kalin) 2 else 1)
    }
  }

  grDevices::dev.off()
  message(paste("Metin PDF kaydedildi:", dosya_yolu, "-", sayfa_sayisi, "sayfa"))
  invisible(dosya_yolu)
}

# ==============================================================================
# ÖRNEK KULLANIM
# ==============================================================================
# source("bilge_yolac_plugins/office/templates/pdf_helpers.R")
#
# # --- Yöntem 1: Basit metin PDF (hiç ek paket gerekmez) ---
# pdf_metin_olustur(
#   dosya_yolu = "metin_rapor.pdf",
#   baslik = "Aylık Özet Rapor",
#   satirlar = c(
#     "1. Proje durumu: Planlandığı gibi ilerliyor.",
#     "2. Bütçe kullanımı: %78",
#     "3. Tamamlanan görevler: 42/50",
#     "",
#     "Öneriler:",
#     "- Kaynak takviyesi yapılmalı",
#     "- Eğitim planı güncellenmeli"
#   )
# )
#
# # --- Yöntem 2: Grafik PDF ---
# pdf_grafik_olustur("grafik.pdf", baslik = "Veri Analizi")
# plot(1:10, main = "Örnek Grafik")
# pdf_kapat()
#
# # --- Yöntem 3: Çoklu grafik PDF ---
# grafikler <- list(
#   function() plot(1:10, main = "Grafik 1"),
#   function() hist(rnorm(100), main = "Grafik 2")
# )
# pdf_coklu_grafik("coklu_grafik.pdf", grafikler)
# ==============================================================================