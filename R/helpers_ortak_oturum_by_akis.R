# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_by_akis.R
# Açıklama: Ortak Bilge Yolaç CANLI çalıştırma akışı SAF yardımcıları:
#           oda-kapsamlı çalıştırma yan dosyaları (durdurma bayrağı + ilerleme),
#           akış parçası -> ilerleme kaydı dönüşümü (worker tarafı) ve tüm
#           katılımcılara yayınlanan kısa canlı ilerleme metni. Bu dosya Shiny
#           reaktif durumu, DB bağlantısı veya süreç başlatma İÇERMEZ; işçi ve
#           izole test bağlamlarında güvenle çalışır. Çalıştırma köprüsü
#           R/module_ortak_oturum_by_calistirma.R içindedir.
# ==============================================================================

# İstek kimliğini dosya adına güvenli biçime indirger (yol enjeksiyonu yok).
.ortak_by_istek_dosya_adi <- function(istek_id) {
  gsub("[^A-Za-z0-9_-]", "", as.character(istek_id %||% "")[1])
}

# Oda-kapsamlı çalıştırma yan dosyası: durdurma bayrağı ve canlı ilerleme
# dosyası odanın PAYLAŞILAN dosya kökü altındadır. Böylece yatay ölçeklenen
# birden çok uygulama sürecinde de tüm oturumlar aynı yolu çözer (tempdir
# süreç-yereldir ve yalnızca kök çözülemezse son çare olarak kullanılır).
ortak_by_calistirma_yan_dosyasi <- function(oturum_id, istek_id, tur = c("durdur", "ilerleme")) {
  tur <- match.arg(tur)
  ad <- .ortak_by_istek_dosya_adi(istek_id)
  if (!nzchar(ad)) {
    return("")
  }

  kok <- NULL
  if (exists("ortak_oturum_dosya_koku", mode = "function", inherits = TRUE)) {
    kok <- tryCatch(ortak_oturum_dosya_koku(oturum_id), error = function(e) NULL)
  }
  if (is.null(kok) || !nzchar(as.character(kok %||% "")[1])) {
    kok <- tempdir()
  }

  onek <- if (identical(tur, "durdur")) ".oo_by_durdur_" else ".oo_by_ilerleme_"
  file.path(kok, paste0(onek, ad, if (identical(tur, "ilerleme")) ".jsonl" else ""))
}

# Ayrıştırılmış akış parçasını (parse_streaming_chunk çıktısı) ilerleme
# kayıtlarına çevirir (SAF; worker içinde koşar). Kayıt biçimi:
#   list(t = "metin", v = "...")                      -> asistan metin deltası
#   list(t = "arac",  v = "Kabuk Komutu", d = "npm…") -> araç kullanımı
# Görüntülenmeyecek parçalar boş liste döndürür.
oo_by_ilerleme_kayitlari <- function(parca, durum = NULL) {
  if (!is.list(parca)) {
    return(list())
  }

  arac_kaydi <- function(arac) {
    baslik <- switch(
      as.character(arac$arac_turu %||% "")[1],
      "bash" = "Kabuk Komutu",
      "file_read" = "Dosya Okuma",
      "file_write" = "Dosya Yazma",
      "search" = "Arama",
      as.character(arac$arac_adi %||% "Araç")[1]
    )
    detay <- as.character(arac$komut %||% "")[1]
    if (!nzchar(detay)) {
      detay <- as.character(arac$dosya_yolu %||% "")[1]
    }
    if (!nzchar(detay)) {
      girdi <- arac$girdi
      if (is.list(girdi)) {
        detay <- as.character(
          girdi$command %||% girdi$file_path %||% girdi$path %||% girdi$pattern %||% ""
        )[1]
      }
    }
    list(t = "arac", v = baslik, d = detay)
  }

  blok_anahtari <- function(x) {
    as.character(x$blok_indeks %||% x$index %||% 0L)[1]
  }

  arac_kaydi_durumdan <- function(anahtar) {
    if (is.null(durum) || is.null(durum$araclar) || is.null(durum$araclar[[anahtar]])) {
      return(NULL)
    }
    arac <- durum$araclar[[anahtar]]
    parcali_json <- paste(arac$parcali_json %||% character(0), collapse = "")
    detay <- as.character(arac$detay %||% "")[1]
    if (!nzchar(detay) && nzchar(parcali_json) && requireNamespace("jsonlite", quietly = TRUE)) {
      girdi <- tryCatch(jsonlite::fromJSON(parcali_json, simplifyVector = FALSE), error = function(e) NULL)
      if (is.list(girdi)) {
        detay <- as.character(
          girdi$command %||% girdi$cmd %||% girdi$file_path %||%
            girdi$path %||% girdi$pattern %||% ""
        )[1]
      }
    }
    list(t = "arac", v = as.character(arac$baslik %||% "Araç")[1], d = detay)
  }

  tip <- as.character(parca$tip %||% "")[1]

  if (tip %in% c("text_delta", "text")) {
    icerik <- as.character(parca$icerik %||% "")[1]
    if (!nzchar(icerik)) {
      return(list())
    }
    return(list(list(t = "metin", v = icerik)))
  }

  if (identical(tip, "tool_use")) {
    kayit <- arac_kaydi(parca)
    if (!is.null(durum)) {
      anahtar <- blok_anahtari(parca)
      if (is.null(durum$araclar)) {
        durum$araclar <- list()
      }
      durum$araclar[[anahtar]] <- list(
        baslik = kayit$v,
        detay = kayit$d,
        parcali_json = character(0),
        yayinlandi = nzchar(as.character(kayit$d %||% "")[1])
      )
      # stream-json tool_use başlangıcında araç girdisi çoğunlukla boştur;
      # komut/yol bilgisi sonraki input_json_delta parçalarıyla gelir. Boş
      # ayrıntılı bir araç satırını hemen yayınlamak yerine content_block_stop
      # anında tamamlanmış ayrıntıyla yayınla.
      if (!nzchar(as.character(kayit$d %||% "")[1])) {
        return(list())
      }
    }
    return(list(kayit))
  }

  if (identical(tip, "tool_input_delta")) {
    if (!is.null(durum)) {
      anahtar <- blok_anahtari(parca)
      if (is.null(durum$araclar)) {
        durum$araclar <- list()
      }
      mevcut <- durum$araclar[[anahtar]] %||% list(
        baslik = "Araç",
        detay = "",
        parcali_json = character(0),
        yayinlandi = FALSE
      )
      mevcut$parcali_json <- c(
        mevcut$parcali_json %||% character(0),
        as.character(parca$parcali_json %||% "")[1]
      )
      durum$araclar[[anahtar]] <- mevcut
    }
    return(list())
  }

  if (identical(tip, "content_block_stop")) {
    anahtar <- blok_anahtari(parca)
    yayinlandi <- !is.null(durum) && !is.null(durum$araclar) &&
      isTRUE(durum$araclar[[anahtar]]$yayinlandi %||% FALSE)
    kayit <- arac_kaydi_durumdan(anahtar)
    if (!is.null(durum) && !is.null(durum$araclar)) {
      durum$araclar[[anahtar]] <- NULL
    }
    if (is.null(kayit) || isTRUE(yayinlandi)) {
      return(list())
    }
    return(list(kayit))
  }

  if (identical(tip, "assistant") && is.list(parca$bloklar)) {
    kayitlar <- list()
    for (blok in parca$bloklar) {
      if (is.list(blok) && identical(as.character(blok$tip %||% "")[1], "tool_use")) {
        kayitlar <- c(kayitlar, list(arac_kaydi(blok)))
      }
    }
    return(kayitlar)
  }

  list()
}

# İlerleme dosyası satırlarını (JSONL) tüm katılımcılara yayınlanacak kısa
# canlı ilerleme metnine çevirir (SAF). Son araç satırları + asistan metninin
# kuyruğu gösterilir; toplam uzunluk sınırlıdır (KismiYanit ön izlemedir).
oo_by_kismi_ilerleme_metni <- function(satirlar,
                                       arac_limit = 5L,
                                       metin_limit = 700L) {
  satirlar <- as.character(satirlar %||% character(0))
  satirlar <- satirlar[!is.na(satirlar) & nzchar(trimws(satirlar))]
  if (length(satirlar) == 0L || !requireNamespace("jsonlite", quietly = TRUE)) {
    return("")
  }

  arac_satirlari <- character(0)
  metin <- ""

  for (satir in satirlar) {
    kayit <- tryCatch(
      jsonlite::fromJSON(satir, simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (!is.list(kayit)) {
      next
    }

    tur <- as.character(kayit$t %||% "")[1]
    if (identical(tur, "metin")) {
      metin <- paste0(metin, as.character(kayit$v %||% "")[1])
    } else if (identical(tur, "arac")) {
      detay <- as.character(kayit$d %||% "")[1]
      if (!is.na(detay) && nchar(detay) > 80L) {
        detay <- paste0(substr(detay, 1L, 80L), "…")
      }
      arac_satirlari <- c(arac_satirlari, paste0(
        "> ", as.character(kayit$v %||% "Araç")[1],
        if (nzchar(detay) && !is.na(detay)) paste0(": ", detay) else ""
      ))
    }
  }

  arac_satirlari <- utils::tail(arac_satirlari, arac_limit)

  if (nchar(metin) > metin_limit) {
    metin <- paste0("…", substr(metin, nchar(metin) - metin_limit + 1L, nchar(metin)))
  }

  parcalar <- c(
    if (length(arac_satirlari) > 0L) paste(arac_satirlari, collapse = "\n") else NULL,
    if (nzchar(trimws(metin))) trimws(metin) else NULL
  )

  paste(parcalar, collapse = "\n\n")
}


# BilgeYolaç odasında çalıştırma köprüsü kullanılamadığında odaya düşen açık
# engelleyici mesaj (normal LLM'e sessiz düşüş yasağının kullanıcı yüzü).
ortak_by_kopru_kullanilamiyor_mesaji <- function() {
  paste(
    "Bilge Yolaç çalıştırma köprüsü bu oturumda kullanılamıyor; komut çalıştırılamadı.",
    "Komutunuz sohbette duruyor; bağlantı sağlandığında yeniden gönderebilirsiniz."
  )
}
