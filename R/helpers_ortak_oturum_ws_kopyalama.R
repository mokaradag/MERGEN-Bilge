# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_ws_kopyalama.R
# Açıklama: Ortak Bilge Yolaç çalışma alanına dosya kopyalama SAF yardımcıları:
#           aşamalı çalışma alanı çözümü (hangi aşamanın başarısız olduğunu
#           söyleyen Türkçe tanılama) ve güvenli/deterministik toplu kopyalama
#           (doğru sayaçlar: kopyalanan / atlanan / başarısız). Shiny reaktif
#           durumu, DB bağlantısı veya süreç başlatma İÇERMEZ.
#
# Sözleşmeler:
#   * Hedefler her zaman çalışma alanı KÖKÜ İÇİNDE doğrulanır (traversal yok).
#   * Ad çakışmaları deterministik sayaçla çözülür (.oo_dosya_hedef_adi).
#   * Başarısız tek dosya diğerlerini durdurmaz; sayaçlar gerçeği yansıtır.
#   * Hata metinleri yol ayrıntısı sızdırmadan aşamayı söyler (kullanıcı yüzü);
#     ayrıntı sunucu günlüğüne gider.
# ==============================================================================

# Çalışma alanını AŞAMALI çözer. Dönen liste: yol (veya NULL), asama, hata.
# Aşamalar: "ozel" (özel proje dizini), "paylasilan" (oda klasörü),
# "kok_yapilandirma" (dosya kökü çözülemedi).
oo_ws_hedef_cozumle <- function(kayit_dizini,
                                oturum_id,
                                etkin_fn = NULL,
                                otomatik_fn = NULL) {
  if (is.null(etkin_fn) &&
      exists("ortak_by_etkin_calisma_dizini", mode = "function", inherits = TRUE)) {
    etkin_fn <- get("ortak_by_etkin_calisma_dizini", inherits = TRUE)
  }

  bilgi <- if (is.function(etkin_fn)) {
    tryCatch(
      etkin_fn(kayit_dizini, oturum_id, otomatik_fn = otomatik_fn),
      error = function(e) list(yol = NULL, ozel = FALSE)
    )
  } else {
    list(yol = NULL, ozel = FALSE)
  }

  yol <- as.character(bilgi$yol %||% "")[1]
  if (!is.na(yol) && nzchar(yol)) {
    return(list(
      yol = yol,
      asama = if (isTRUE(bilgi$ozel)) "ozel" else "paylasilan",
      hata = ""
    ))
  }

  # Etkin dizin çözülemedi: nedeni aşamaya göre ayrıştır.
  ozel <- trimws(as.character(kayit_dizini %||% "")[1])
  if (!is.na(ozel) && nzchar(ozel)) {
    return(list(
      yol = NULL,
      asama = "kok_yapilandirma",
      hata = paste(
        "Özel proje dizini şu an erişilemiyor ve paylaşılan oda klasörü de",
        "hazırlanamadı. Proje dizinini doğrulayın ya da sistem yöneticinize",
        "MERGEN dosya kökü erişimini sorun."
      )
    ))
  }

  list(
    yol = NULL,
    asama = "kok_yapilandirma",
    hata = paste(
      "Paylaşılan oda klasörü oluşturulamadı: MERGEN dosya kökü",
      "(MERGEN_FILES_ROOT) bu sunucudan erişilebilir değil.",
      "Sistem yöneticinize başvurun."
    )
  )
}

# Kaynak dosyaları çalışma alanına kopyalar. Sayaçlar gerçek sonucu yansıtır;
# kök dışına çözünen hedefler ve kopyalama hataları ayrı sayılır.
# @return list(kopyalanan, atlanan, basarisiz, toplam, hatalar)
oo_ws_kopyalama_calistir <- function(kaynak_yollar, kaynak_adlar, ws) {
  kaynak_yollar <- as.character(kaynak_yollar %||% character(0))
  kaynak_adlar <- as.character(kaynak_adlar %||% character(0))

  sonuc <- list(
    kopyalanan = 0L, atlanan = 0L, basarisiz = 0L,
    toplam = length(kaynak_yollar), hatalar = character(0)
  )

  ws <- as.character(ws %||% "")[1]
  if (is.na(ws) || !nzchar(ws)) {
    sonuc$basarisiz <- sonuc$toplam
    sonuc$hatalar <- "Çalışma alanı çözümlenemedi."
    return(sonuc)
  }

  for (i in seq_along(kaynak_yollar)) {
    yol <- kaynak_yollar[i]
    ad <- if (i <= length(kaynak_adlar) && nzchar(kaynak_adlar[i])) {
      kaynak_adlar[i]
    } else {
      basename(yol)
    }

    if (!file.exists(yol) || dir.exists(yol)) {
      sonuc$atlanan <- sonuc$atlanan + 1L
      next
    }

    hedef <- if (exists(".oo_dosya_hedef_adi", mode = "function", inherits = TRUE)) {
      .oo_dosya_hedef_adi(ws, ad)
    } else {
      file.path(ws, basename(ad))
    }

    kok_icinde <- if (exists(".oo_dosya_kok_icinde_mi", mode = "function", inherits = TRUE)) {
      isTRUE(.oo_dosya_kok_icinde_mi(hedef, ws))
    } else {
      identical(normalizePath(dirname(hedef), winslash = "/", mustWork = FALSE),
                normalizePath(ws, winslash = "/", mustWork = FALSE))
    }

    if (!kok_icinde) {
      sonuc$basarisiz <- sonuc$basarisiz + 1L
      sonuc$hatalar <- c(sonuc$hatalar, sprintf("%s: hedef güvenli köke çözümlenemedi.", ad))
      next
    }

    # Kopyalama uyarıları (ör. hedef oluşturulamadı) sayaçla raporlanır;
    # strict test koşucusunda uyarı gürültüsü üretilmez.
    kopyalandi <- tryCatch(
      isTRUE(suppressWarnings(file.copy(yol, hedef, overwrite = FALSE))) && file.exists(hedef),
      error = function(e) FALSE
    )

    if (kopyalandi) {
      sonuc$kopyalanan <- sonuc$kopyalanan + 1L
    } else {
      # Yarım kopya bırakma: hedef bu kopyalama için tahsis edilmiş taze bir
      # addır (çakışma sayacı); başarısızlıkta kalan parça güvenle silinir.
      if (file.exists(hedef)) {
        tryCatch(unlink(hedef), error = function(e) NULL)
      }
      sonuc$basarisiz <- sonuc$basarisiz + 1L
      sonuc$hatalar <- c(sonuc$hatalar, sprintf("%s: kopyalama başarısız.", ad))
    }
  }

  sonuc
}

# Kopyalama sonucunu tek, doğru Türkçe bildirime çevirir (SAF sunum kararı).
# @return list(mesaj, tur)
oo_ws_kopyalama_bildirimi <- function(sonuc) {
  kopyalanan <- as.integer(sonuc$kopyalanan %||% 0L)
  basarisiz <- as.integer(sonuc$basarisiz %||% 0L)
  atlanan <- as.integer(sonuc$atlanan %||% 0L)

  if (kopyalanan > 0L && basarisiz == 0L) {
    ek <- if (atlanan > 0L) sprintf(" (%d öğe klasör/eksik olduğu için atlandı)", atlanan) else ""
    return(list(
      mesaj = sprintf("%d dosya paylaşılan çalışma alanına kopyalandı.%s", kopyalanan, ek),
      tur = "message"
    ))
  }

  if (kopyalanan > 0L) {
    return(list(
      mesaj = sprintf(
        "%d dosya kopyalandı; %d dosya kopyalanamadı. Ayrıntı sunucu günlüğünde.",
        kopyalanan, basarisiz
      ),
      tur = "warning"
    ))
  }

  if (basarisiz > 0L) {
    return(list(
      mesaj = "Hiçbir dosya kopyalanamadı; çalışma alanı yazılabilir değil olabilir. Ayrıntı sunucu günlüğünde.",
      tur = "error"
    ))
  }

  list(mesaj = "Kopyalanacak uygun dosya bulunamadı.", tur = "warning")
}
