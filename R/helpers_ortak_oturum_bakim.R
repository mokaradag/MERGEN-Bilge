# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_bakim.R
# Açıklama: Ortak Oturumlar bakım ve gözlem katmanı: süresi dolan davet /
#           bayat bildirim / eski kalp atışı temizliği, fiziksel dosyası
#           kaybolmuş ortak belge işaretleme, yönetici görünürlüğü için
#           istatistik özetleri ve tutanak (transcript) dışa aktarma metni.
#
# Sözleşmeler:
#   * Temizlik yıkıcı DEĞİLDİR: davetler SüresiDoldu'ya, belgeler Silindi'ye
#     İŞARETLENİR; yalnızca kalp atışı satırları (geçici telemetri) silinir.
#   * İstatistik çıktısı gizli değer içermez; yalnızca sayaç/oran döner.
#   * Tutanak üretimi SAF metin fonksiyonudur; yetki denetimi çağıran
#     modüldedir ve dışa aktarma yalnızca içerik erişimli katılımcıya sunulur.
# ==============================================================================

#' Bakım temizliği (operatör/oturum başına bir kez tetiklenir):
#'   - gecerlilik süresi geçmiş ya da bekleme_gun'den eski Bekliyor davetler
#'     SüresiDoldu yapılır,
#'   - bildirim_gun'den eski okunmamış bildirimler SüresiDoldu + okundu yapılır,
#'   - kalp_gun'den eski kalp atışı satırları silinir (geçici telemetri),
#'   - fiziksel dosyası kaybolmuş ortak belgeler Silindi olarak işaretlenir.
#'
#' @return list(davet, bildirim, kalp_atisi, dosya) etkilenen satır sayıları.
ortak_db_bakim_temizlik <- function(bekleme_gun = 30L,
                                    bildirim_gun = 30L,
                                    kalp_gun = 7L,
                                    conn = NULL) {
  bos <- list(davet = 0L, bildirim = 0L, kalp_atisi = 0L, dosya = 0L)

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  esik <- function(gun) {
    format(Sys.time() - as.numeric(gun) * 86400, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  }

  sonuc <- bos

  sonuc$davet <- .oo_db_try(
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_Davetler SET DavetDurumu = ?",
        "WHERE DavetDurumu = ? AND (",
        "  (GecerlilikBitisZamani IS NOT NULL AND GecerlilikBitisZamani < ?)",
        "  OR OlusturmaZamani < ?",
        ")"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value("SüresiDoldu"),
        normalize_db_technical_value("Bekliyor"),
        .oo_db_now(),
        esik(bekleme_gun)
      ))
    ),
    fallback = 0L,
    uyari = "Davet temizliği başarısız:"
  )

  sonuc$bildirim <- .oo_db_try(
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_Bildirimler SET Durum = ?, OkunduMu = 1, OkunmaZamani = ?",
        "WHERE OkunduMu = 0 AND OlusturmaZamani < ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value("SüresiDoldu"),
        .oo_db_now(),
        esik(bildirim_gun)
      ))
    ),
    fallback = 0L,
    uyari = "Bildirim temizliği başarısız:"
  )

  sonuc$kalp_atisi <- .oo_db_try(
    DBI::dbExecute(
      handle$conn,
      "DELETE FROM MB_Kullanici_CanliDurum WHERE SonKalpAtisiZamani < ?",
      params = normalize_db_params(list(esik(kalp_gun)))
    ),
    fallback = 0L,
    uyari = "Kalp atışı temizliği başarısız:"
  )

  # Fiziksel dosyası kaybolan ortak belgeler erişime kapatılır (işaretleme).
  sonuc$dosya <- .oo_db_try({
    dosyalar <- DBI::dbGetQuery(
      handle$conn,
      "SELECT OrtakDosyaID, DosyaYolu FROM MB_OrtakOturum_Dosyalar WHERE DosyaDurumu = ?",
      params = normalize_db_params(list(normalize_db_technical_value("Üretildi")))
    )

    isaretlenen <- 0L
    if (is.data.frame(dosyalar) && nrow(dosyalar) > 0L) {
      for (i in seq_len(nrow(dosyalar))) {
        yol <- as.character(dosyalar$DosyaYolu[i])
        if (!nzchar(yol) || !file.exists(yol)) {
          DBI::dbExecute(
            handle$conn,
            "UPDATE MB_OrtakOturum_Dosyalar SET DosyaDurumu = ? WHERE OrtakDosyaID = ?",
            params = normalize_db_params(list(
              normalize_db_technical_value("Silindi"),
              as.integer(dosyalar$OrtakDosyaID[i])
            ))
          )
          isaretlenen <- isaretlenen + 1L
        }
      }
    }
    isaretlenen
  },
  fallback = 0L,
  uyari = "Ortak belge tutarlılık taraması başarısız:")

  sonuc
}

#' Yönetici görünürlüğü için Ortak Oturum istatistik özeti (yalnızca sayaçlar).
ortak_db_istatistikler <- function(conn = NULL) {
  bos <- list(
    toplam_oda = 0L,
    aktif_oda = 0L,
    toplam_mesaj = 0L,
    yz_soru = 0L,
    toplam_belge = 0L,
    kopyalanan_belge = 0L,
    davet_toplam = 0L,
    davet_kabul = 0L,
    davet_kabul_orani = NA_real_,
    hatali_uretim = 0L
  )

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  say <- function(sql, params = NULL) {
    .oo_db_try({
      res <- if (is.null(params)) {
        DBI::dbGetQuery(handle$conn, sql)
      } else {
        DBI::dbGetQuery(handle$conn, sql, params = normalize_db_params(params))
      }
      as.integer(res[[1]][1])
    }, fallback = 0L)
  }

  sonuc <- bos
  sonuc$toplam_oda <- say("SELECT COUNT(*) FROM MB_OrtakOturumlar")
  sonuc$aktif_oda <- say(
    "SELECT COUNT(*) FROM MB_OrtakOturumlar WHERE OturumDurumu = ?",
    list(normalize_db_technical_value("Aktif"))
  )
  sonuc$toplam_mesaj <- say("SELECT COUNT(*) FROM MB_OrtakOturum_Mesajlar")
  sonuc$yz_soru <- say(
    "SELECT COUNT(*) FROM MB_OrtakOturum_Mesajlar WHERE MesajTuru = ?",
    list(normalize_db_technical_value("YapayZekaSorusu"))
  )
  sonuc$toplam_belge <- say("SELECT COUNT(*) FROM MB_OrtakOturum_Dosyalar")
  sonuc$kopyalanan_belge <- say(
    "SELECT COUNT(*) FROM MB_OrtakOturum_DosyaKopyalari WHERE KopyalamaDurumu = ?",
    list(normalize_db_technical_value("Kopyalandı"))
  )
  sonuc$davet_toplam <- say("SELECT COUNT(*) FROM MB_OrtakOturum_Davetler")
  sonuc$davet_kabul <- say(
    "SELECT COUNT(*) FROM MB_OrtakOturum_Davetler WHERE DavetDurumu = ?",
    list(normalize_db_technical_value("Katıldı"))
  )
  sonuc$hatali_uretim <- say(
    "SELECT COUNT(*) FROM MB_OrtakOturum_AktifUretimler WHERE KilitDurumu = ?",
    list(normalize_db_technical_value("Hata"))
  )

  if (sonuc$davet_toplam > 0L) {
    sonuc$davet_kabul_orani <- round(sonuc$davet_kabul / sonuc$davet_toplam, 3)
  }

  sonuc
}

#' Tutanak (transcript) metni üretir (SAF fonksiyon; dosya yazmaz).
#' Yetki denetimi çağıran modüldedir: yalnızca içerik erişimli katılımcıya
#' indirme sunulur. Metin gizli değer içermez.
ortak_tutanak_metni <- function(oturum_bilgisi, mesajlar_df, belgeler_df = NULL) {
  satirlar <- c(
    "MERGEN Bilge - Ortak Oturum Tutanağı",
    "=====================================",
    ""
  )

  if (is.data.frame(oturum_bilgisi) && nrow(oturum_bilgisi) > 0L) {
    satirlar <- c(
      satirlar,
      paste("Başlık:", as.character(oturum_bilgisi$Baslik[1] %||% "Ortak Oturum")),
      paste("Tür:", as.character(oturum_bilgisi$KaynakTuru[1] %||% "")),
      paste("Durum:", as.character(oturum_bilgisi$OturumDurumu[1] %||% "")),
      paste("Oluşturma:", as.character(oturum_bilgisi$OlusturmaZamani[1] %||% "")),
      ""
    )
  }

  satirlar <- c(satirlar, "Mesaj Akışı", "-----------")

  if (is.data.frame(mesajlar_df) && nrow(mesajlar_df) > 0L) {
    for (i in seq_len(nrow(mesajlar_df))) {
      tur <- as.character(mesajlar_df$MesajTuru[i])
      gonderen <- as.character(mesajlar_df$GonderenAdi[i] %||% "")
      etiket <- switch(
        tur,
        "YapayZekaYanıtı" = "[Yapay Zekâ Yanıtı]",
        "YapayZekaSorusu" = sprintf("[Yapay Zekâ Sorusu] %s", gonderen),
        "SistemMesajı" = "[Sistem]",
        "BelgeBildirimi" = "[Belge]",
        sprintf("[Oda] %s", gonderen)
      )

      satirlar <- c(
        satirlar,
        sprintf(
          "%s | %s",
          as.character(mesajlar_df$OlusturmaZamani[i] %||% ""),
          etiket
        ),
        as.character(mesajlar_df$MesajMetni[i] %||% ""),
        ""
      )
    }
  } else {
    satirlar <- c(satirlar, "(Mesaj yok)", "")
  }

  satirlar <- c(satirlar, "Ortak Belgeler", "--------------")

  if (is.data.frame(belgeler_df) && nrow(belgeler_df) > 0L) {
    for (i in seq_len(nrow(belgeler_df))) {
      satirlar <- c(satirlar, sprintf(
        "- %s (%s)",
        as.character(belgeler_df$DosyaAdi[i] %||% ""),
        as.character(belgeler_df$OlusturmaZamani[i] %||% "")
      ))
    }
  } else {
    satirlar <- c(satirlar, "(Ortak belge yok)")
  }

  paste(satirlar, collapse = "\n")
}

#' Tutanak metnini UTF-8 BOM'lu .txt olarak yazar (Windows/Not Defteri uyumu).
ortak_tutanak_dosyaya_yaz <- function(metin, dosya_yolu) {
  con <- file(dosya_yolu, open = "wb")
  on.exit(close(con), add = TRUE)

  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(charToRaw(enc2utf8(as.character(metin)[1])), con)
  invisible(dosya_yolu)
}
