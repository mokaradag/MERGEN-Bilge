# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db_kuyruk.R
# Açıklama: Ortak Oturumlar yapay zekâ kuyruğu (MB_OrtakOturum_YapayZekaKuyrugu),
#           aktif üretim ayrıntısı/kısmi yanıt yayını ve kişisel geçmiş
#           kopyalama otomasyonu. Çekirdek altyapı (.oo_db_*)
#           helpers_ortak_oturum_db.R içindedir ve bu dosyadan ÖNCE yüklenir.
#
# Sözleşmeler:
#   * Kuyruk kalıcıdır: kilit doluyken gelen sorular kaybolmaz, sıraya girer.
#     Üretimi bitiren oturum kuyruğun başındaki soruyu devralır.
#   * Kısmi yanıt (KismiYanit) kolonu opsiyoneldir: kurulu olmayan şemada tüm
#     fonksiyonlar sessizce güvenli düşer (aşamalı devreye alma).
#   * Geçmiş kopyalama YALNIZCA açık kullanıcı onayıyla çağrılır; kişisel
#     MB_Chats/MB_Messages satırları OKUNUR, asla değiştirilmez/silinmez.
# ==============================================================================

# --- Yapay zekâ kuyruğu -----------------------------------------------------------

#' Soruyu yanıt kuyruğuna ekler (kilit doluyken). Sıra numarası yarış-korumalı
#' artar. @return KuyrukID (integer) veya NULL.
ortak_db_kuyruk_ekle <- function(oturum_id, mesaj_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  mesaj_id <- .oo_db_pos_int(mesaj_id)
  if (is.na(oturum_id) || is.na(mesaj_id)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      sira_sql <- if (.oo_db_is_sqlite(handle$conn)) {
        "SELECT COALESCE(MAX(SiraNo), 0) + 1 AS sonraki FROM MB_OrtakOturum_YapayZekaKuyrugu WHERE OrtakOturumID = ?"
      } else {
        paste(
          "SELECT ISNULL(MAX(SiraNo), 0) + 1 AS sonraki",
          "FROM MB_OrtakOturum_YapayZekaKuyrugu WITH (UPDLOCK, HOLDLOCK)",
          "WHERE OrtakOturumID = ?"
        )
      }

      sira <- DBI::dbGetQuery(handle$conn, sira_sql, params = list(oturum_id))

      .oo_db_insert_returning_id(
        conn = handle$conn,
        insert_sql_tsql = paste(
          "INSERT INTO MB_OrtakOturum_YapayZekaKuyrugu",
          "(OrtakOturumID, OrtakMesajID, SiraNo, Durum, OlusturmaZamani)",
          "OUTPUT INSERTED.KuyrukID AS id",
          "VALUES (?, ?, ?, ?, ?)"
        ),
        insert_sql_plain = paste(
          "INSERT INTO MB_OrtakOturum_YapayZekaKuyrugu",
          "(OrtakOturumID, OrtakMesajID, SiraNo, Durum, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?)"
        ),
        id_column = "KuyrukID",
        params = normalize_db_params(list(
          oturum_id,
          mesaj_id,
          as.integer(sira$sonraki[1]),
          normalize_db_technical_value(ortak_kuyruk_durumlari()[1]),
          .oo_db_now()
        ))
      )
    })
  },
  fallback = NULL,
  uyari = "Ortak yapay zekâ kuyruğuna eklenemedi:")
}

#' Bekleyen kuyruk kayıtları (soru metni + soran adıyla; sıra artan).
ortak_db_kuyruk_bekleyenler <- function(oturum_id, conn = NULL) {
  bos <- data.frame()

  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(bos)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT q.KuyrukID, q.OrtakMesajID, q.SiraNo, q.Durum, q.OlusturmaZamani,",
        "m.MesajMetni, m.GonderenKullaniciID, u.KaynakAdi AS SoranAdi",
        "FROM MB_OrtakOturum_YapayZekaKuyrugu q",
        "JOIN MB_OrtakOturum_Mesajlar m ON m.OrtakMesajID = q.OrtakMesajID",
        "LEFT JOIN MB_Users u ON u.UserID = m.GonderenKullaniciID",
        "WHERE q.OrtakOturumID = ? AND q.Durum = ?",
        "ORDER BY q.SiraNo ASC"
      ),
      params = normalize_db_params(list(
        oturum_id,
        normalize_db_technical_value(ortak_kuyruk_durumlari()[1])
      ))
    ),
    fallback = bos,
    uyari = "Ortak yapay zekâ kuyruğu okunamadı:"
  )

  .oo_db_restore_visible(sonuc, c("MesajMetni", "SoranAdi"))
}

#' Kuyruğun başındaki bekleyen soruyu Çalışıyor durumuna alır ve döner.
#' Yarış koruması: aynı kayıt yalnızca bir kez devralınabilir (Durum filtreli
#' UPDATE etkilenen satır sayısıyla doğrulanır).
#' @return list(kuyruk_id, mesaj_id, soran_id, mesaj_metni) veya NULL.
ortak_db_kuyruk_sonraki_al <- function(oturum_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      bekleyen <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT q.KuyrukID, q.OrtakMesajID, m.MesajMetni, m.GonderenKullaniciID",
          "FROM MB_OrtakOturum_YapayZekaKuyrugu q",
          "JOIN MB_OrtakOturum_Mesajlar m ON m.OrtakMesajID = q.OrtakMesajID",
          "WHERE q.OrtakOturumID = ? AND q.Durum = ?",
          "ORDER BY q.SiraNo ASC"
        ),
        params = normalize_db_params(list(
          oturum_id,
          normalize_db_technical_value(ortak_kuyruk_durumlari()[1])
        ))
      )

      if (nrow(bekleyen) == 0L) {
        NULL
      } else {
        kuyruk_id <- as.integer(bekleyen$KuyrukID[1])

        devralindi <- DBI::dbExecute(
          handle$conn,
          paste(
            "UPDATE MB_OrtakOturum_YapayZekaKuyrugu",
            "SET Durum = ?, BaslamaZamani = ?",
            "WHERE KuyrukID = ? AND Durum = ?"
          ),
          params = normalize_db_params(list(
            normalize_db_technical_value(ortak_kuyruk_durumlari()[2]),
            .oo_db_now(),
            kuyruk_id,
            normalize_db_technical_value(ortak_kuyruk_durumlari()[1])
          ))
        )

        if (devralindi == 0L) {
          NULL
        } else {
          metin <- as.character(bekleyen$MesajMetni[1] %||% "")
          if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
            metin <- normalize_db_read_visible_value(metin)
          }
          list(
            kuyruk_id = kuyruk_id,
            mesaj_id = as.integer(bekleyen$OrtakMesajID[1]),
            soran_id = suppressWarnings(as.integer(bekleyen$GonderenKullaniciID[1])),
            mesaj_metni = metin
          )
        }
      }
    })
  },
  fallback = NULL,
  uyari = "Ortak yapay zekâ kuyruğundan kayıt devralınamadı:")
}

#' Devralınmış (Çalışıyor) kuyruk kaydını yeniden Bekliyor durumuna alır.
#' Yarış senaryosu: kayıt devralındıktan sonra kilit başka oturuma geçtiyse
#' soru kaybolmaz; sıradaki tur yeniden devralır.
ortak_db_kuyruk_beklet <- function(kuyruk_id, conn = NULL) {
  kuyruk_id <- .oo_db_pos_int(kuyruk_id)
  if (is.na(kuyruk_id)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_YapayZekaKuyrugu",
        "SET Durum = ?, BaslamaZamani = NULL",
        "WHERE KuyrukID = ? AND Durum = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(ortak_kuyruk_durumlari()[1]),
        kuyruk_id,
        normalize_db_technical_value(ortak_kuyruk_durumlari()[2])
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak yapay zekâ kuyruğu kaydı bekletilemedi:")

  invisible(isTRUE(sonuc))
}

#' Kuyruk kaydını sonuçlandırır (Tamamlandı/İptalEdildi/Hata).
ortak_db_kuyruk_tamamla <- function(kuyruk_id, durum = "Tamamlandı", conn = NULL) {
  kuyruk_id <- .oo_db_pos_int(kuyruk_id)
  if (is.na(kuyruk_id) || !(durum %in% ortak_kuyruk_durumlari())) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_YapayZekaKuyrugu",
        "SET Durum = ?, BitisZamani = ? WHERE KuyrukID = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(durum),
        .oo_db_now(),
        kuyruk_id
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak yapay zekâ kuyruğu kaydı sonuçlandırılamadı:")

  invisible(isTRUE(sonuc))
}

# --- Aktif üretim ayrıntısı ve kısmi yanıt yayını ------------------------------------

#' Aktif üretim kilidinin ayrıntısı: soran adı, başlama zamanı ve (şema
#' destekliyorsa) kısmi yanıt metni. Kolon yoksa KismiYanit NA döner.
ortak_db_aktif_uretim_detay <- function(oturum_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  # Önce KismiYanit kolonlu sorgu denenir; eski şemada kolonsuz sorguya düşer.
  sorgu_kismi <- paste(
    "SELECT a.OrtakOturumID, a.BaslatanKullaniciID, a.IstekID, a.KilitDurumu,",
    "a.BaslamaZamani, a.KismiYanit, u.KaynakAdi AS BaslatanAdi",
    "FROM MB_OrtakOturum_AktifUretimler a",
    "LEFT JOIN MB_Users u ON u.UserID = a.BaslatanKullaniciID",
    "WHERE a.OrtakOturumID = ?"
  )
  sorgu_eski <- paste(
    "SELECT a.OrtakOturumID, a.BaslatanKullaniciID, a.IstekID, a.KilitDurumu,",
    "a.BaslamaZamani, u.KaynakAdi AS BaslatanAdi",
    "FROM MB_OrtakOturum_AktifUretimler a",
    "LEFT JOIN MB_Users u ON u.UserID = a.BaslatanKullaniciID",
    "WHERE a.OrtakOturumID = ?"
  )

  sonuc <- tryCatch(
    DBI::dbGetQuery(handle$conn, sorgu_kismi, params = list(oturum_id)),
    error = function(e) {
      .oo_db_try(
        DBI::dbGetQuery(handle$conn, sorgu_eski, params = list(oturum_id)),
        fallback = NULL
      )
    }
  )

  if (!is.data.frame(sonuc) || nrow(sonuc) == 0L) {
    return(NULL)
  }
  if (!"KismiYanit" %in% names(sonuc)) {
    sonuc$KismiYanit <- NA_character_
  }

  .oo_db_restore_visible(sonuc, c("BaslatanAdi", "KismiYanit"))
}

#' Aktif üretim kilidine kısmi yanıt metni yazar (yayın: tüm katılımcılar
#' yoklamayla görür). KismiYanit kolonu kurulu değilse sessiz no-op.
ortak_db_uretim_kismi_yanit_guncelle <- function(oturum_id,
                                                 istek_id,
                                                 metin,
                                                 conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  istek_id <- as.character(istek_id %||% "")[1]
  if (is.na(oturum_id) || !nzchar(istek_id)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- tryCatch({
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_AktifUretimler",
        "SET KismiYanit = ?, GuncellemeZamani = ?",
        "WHERE OrtakOturumID = ? AND IstekID = ? AND KilitDurumu = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_visible_value(as.character(metin %||% NA_character_)[1]),
        .oo_db_now(),
        oturum_id,
        normalize_db_technical_value(istek_id),
        normalize_db_technical_value("Çalışıyor")
      ))
    ) > 0L
  },
  # Kolon kurulu değilse (eski şema) sessizce no-op; tamamlanan yanıt yine
  # normal yoldan dağıtılır.
  error = function(e) FALSE)

  invisible(isTRUE(sonuc))
}

# --- Kişisel geçmiş kopyalama otomasyonu ------------------------------------------------

#' Kullanıcının kişisel sohbetini (MB_Chats/MB_Messages) AÇIK ONAY sonrasında
#' ortak oturuma kopyalar. Kaynak kayıtlar yalnızca OKUNUR; sahiplik ve
#' zaman damgaları korunarak ortak mesaj olarak yeniden yazılır.
#'
#' Eşleme: kişisel "user" mesajı -> YapayZekaSorusu (kopyalayan kullanıcı
#' adına), kişisel "ai" yanıtı -> YapayZekaYanıtı. Böylece kopyalanan geçmiş
#' odanın LLM bağlamına da doğal olarak girer (ortak_yz_sohbet_gecmisi).
#'
#' @return list(basarili, kopyalanan, mesaj)
ortak_db_gecmis_kopyala <- function(oturum_id,
                                    kullanici_id,
                                    chat_id,
                                    conn = NULL) {
  basarisiz <- function(mesaj) {
    list(basarili = FALSE, kopyalanan = 0L, mesaj = mesaj)
  }

  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  chat_id <- .oo_db_pos_int(chat_id)
  if (is.na(oturum_id) || is.na(kullanici_id) || is.na(chat_id)) {
    return(basarisiz("Geçersiz oturum, kullanıcı veya söyleşi kimliği."))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(basarisiz("Veritabanı bağlantısı alınamadı."))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  # Yetki: kopyalayan, içerik erişimli katılımcı olmalı ve yazabilmeli.
  katilimci <- ortak_db_katilimci_getir(oturum_id, kullanici_id, conn = handle$conn)
  if (is.null(katilimci) ||
      !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
      !ortak_yetki_var_mi(katilimci$Rol[1], "yapay_zeka_sor")) {
    return(basarisiz("Bu odaya geçmiş kopyalama yetkiniz yok."))
  }

  # Kaynak söyleşi SAHİPLİK doğrulamalı okunur (yalnızca kendi söyleşisi).
  kaynak <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT c.ChatTitle, m.MessageType, m.MessageContent, m.MessageTimestamp",
        "FROM MB_Chats c",
        "JOIN MB_Messages m ON m.ChatID = c.ChatID",
        "WHERE c.ChatID = ? AND c.UserID = ?",
        "ORDER BY m.MessageOrder ASC"
      ),
      params = normalize_db_params(list(chat_id, kullanici_id))
    ),
    fallback = NULL,
    uyari = "Kişisel söyleşi geçmişi okunamadı:"
  )

  if (!is.data.frame(kaynak) || nrow(kaynak) == 0L) {
    return(basarisiz("Kopyalanacak söyleşi bulunamadı veya boş."))
  }

  if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    kaynak$MessageContent <- vapply(
      as.character(kaynak$MessageContent),
      function(x) normalize_db_read_visible_value(x, repair_mojibake = TRUE),
      character(1),
      USE.NAMES = FALSE
    )
    baslik <- normalize_db_read_visible_value(as.character(kaynak$ChatTitle[1] %||% ""))
  } else {
    baslik <- as.character(kaynak$ChatTitle[1] %||% "")
  }

  kopyalanan <- 0L

  for (i in seq_len(nrow(kaynak))) {
    tur <- tolower(as.character(kaynak$MessageType[i] %||% ""))
    icerik <- as.character(kaynak$MessageContent[i] %||% "")
    if (!nzchar(trimws(icerik))) {
      next
    }

    zaman <- as.character(kaynak$MessageTimestamp[i] %||% NA_character_)

    mesaj_id <- if (tur %in% c("user", "human")) {
      ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = kullanici_id,
        mesaj_turu = "YapayZekaSorusu",
        mesaj_metni = icerik,
        llm_gonderildi = TRUE,
        olusturma_zamani = zaman,
        conn = handle$conn
      )
    } else if (tur %in% c("ai", "assistant")) {
      ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = NULL,
        mesaj_turu = "YapayZekaYanıtı",
        mesaj_metni = icerik,
        olusturma_zamani = zaman,
        conn = handle$conn
      )
    } else {
      NULL
    }

    if (!is.null(mesaj_id)) {
      kopyalanan <- kopyalanan + 1L
    }
  }

  if (kopyalanan > 0L) {
    ortak_db_mesaj_ekle(
      oturum_id = oturum_id,
      gonderen_kullanici_id = NULL,
      mesaj_turu = "SistemMesajı",
      mesaj_metni = sprintf(
        "Kişisel söyleşi geçmişi kopyalandı: %s (%d mesaj). Kaynak kişisel kayıt değişmedi.",
        baslik, kopyalanan
      ),
      conn = handle$conn
    )
    ortak_db_olay_ekle(oturum_id, "GeçmişKopyalandı", kullanici_id, conn = handle$conn)
  }

  list(
    basarili = kopyalanan > 0L,
    kopyalanan = kopyalanan,
    mesaj = if (kopyalanan > 0L) {
      sprintf("%d mesaj ortak oturuma kopyalandı.", kopyalanan)
    } else {
      "Kopyalanabilir mesaj bulunamadı."
    }
  )
}
