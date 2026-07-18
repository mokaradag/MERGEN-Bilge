# ==============================================================================
# Dosya Yolu: R/helpers_db_bilge_savunmasi_kosu.R
# Açıklama: Bilge Savunması koşu (run) yaşam döngüsü DB katmanı: sunucu
#           kimlikli koşu başlatma, kontrol noktası kaydetme/yükleme ve
#           işlem-güvenli, idempotent koşu sonuçlandırma (kampanya/kahraman/
#           profil/başarım güncellemeleri tek transaction içinde).
#
# Sözleşmeler:
#   * Koşu kimliği SUNUCU tarafından verilir; istemci jetonu (ClientToken)
#     yeniden denemeleri idempotent yapar (düşen Shiny mesajı ödül/kayıt
#     çoğaltamaz).
#   * Sonuçlandırma puanı istemci beyanından değil,
#     bs_kosu_ozeti_dogrula() sunucu doğrulamasından gelir.
#   * Çok tablolu güncellemeler tek transaction'dadır; hata durumunda tam
#     geri alma (rollback) yapılır ve bağlantı açık işlem ile havuza dönmez.
#   * Tüm sorgular kullanıcı kimliğiyle (UserID) izole edilir.
#   * Paylaşılan .bs_db_* altyapısı helpers_db_bilge_savunmasi_cekirdek.R
#     dosyasından gelir; bu dosya ondan SONRA yüklenmelidir.
# ==============================================================================

# Kullanıcının eski Aktif koşularını kapatır (tek aktif koşu kuralı).
.bs_db_aktif_kosu_kapat <- function(conn, uid, haric_kosu_id = NULL) {
  if (is.null(haric_kosu_id)) {
    DBI::dbExecute(
      conn,
      "UPDATE MB_Game_Runs SET Status = ?, FinalizedAt = ? WHERE UserID = ? AND Status = ?",
      params = normalize_db_params(list(
        "Bırakıldı", .bs_db_now_stamp(), uid, "Aktif"
      ))
    )
  } else {
    DBI::dbExecute(
      conn,
      paste(
        "UPDATE MB_Game_Runs SET Status = ?, FinalizedAt = ?",
        "WHERE UserID = ? AND Status = ? AND GameRunID <> ?"
      ),
      params = normalize_db_params(list(
        "Bırakıldı", .bs_db_now_stamp(), uid, "Aktif", as.integer(haric_kosu_id)
      ))
    )
  }
  invisible(NULL)
}

#' Yeni Koşu Başlat (Sunucu Kimlikli, Jetonla Idempotent, İşlem-Güvenli)
#'
#' @description Kullanıcı için yeni bir koşu kaydı açar ve sunucu koşu
#' kimliğini döndürür. Aynı istemci jetonuyla tekrarlanan çağrı mevcut kaydı
#' döndürür (yeniden deneme güvenliği). Önceki Aktif koşuları Bırakıldı yapma
#' ve yeni koşuyu ekleme TEK transaction içindedir: ekleme herhangi bir
#' nedenle (geçici DB hatası, kısıt/encoding hatası) başarısız olursa eski
#' koşu(lar) Bırakıldı olarak COMMIT EDİLMEZ; kullanıcı devam edilebilir
#' kontrol noktasını kaybetmeden tam geri alma (rollback) yapılır.
#' @return Liste: kosu_id, tohum, harita, zorluk, mod veya NULL.
bs_db_start_run <- function(user_id, harita, zorluk, tohum, mod = "kampanya",
                            sezon_id = NULL, plan_id = NULL,
                            istemci_jetonu = NULL, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(NULL)

  jeton <- .bs_metin_temizle(istemci_jetonu, 64L)
  if (!nzchar(jeton)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn, tx = TRUE),
    fallback = NULL,
    uyari = "Koşu başlatma için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  tamamlandi <- FALSE
  DBI::dbBegin(handle$conn)
  # Geri alma bağlantı bırakılmadan ÖNCE çalışmalı (after = FALSE): havuza
  # açık transaction'lı bağlantı dönmez.
  on.exit({
    if (!tamamlandi) {
      try(DBI::dbRollback(handle$conn), silent = TRUE)
    }
  }, add = TRUE, after = FALSE)

  .bs_db_try({
    mevcut <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameRunID, MapID, Difficulty, Seed, Mode, ChallengeSeasonID,",
        "BlueprintID FROM MB_Game_Runs WHERE UserID = ? AND ClientToken = ?"
      ),
      params = normalize_db_params(list(uid, jeton))
    )
    if (nrow(mevcut) > 0L) {
      # Yalnızca okuma yapıldı; yazım yok, güvenle geri alınabilir.
      DBI::dbRollback(handle$conn)
      tamamlandi <- TRUE
      return(list(
        kosu_id = as.integer(mevcut$GameRunID[1]),
        harita = as.character(mevcut$MapID[1]),
        zorluk = as.character(mevcut$Difficulty[1]),
        tohum = as.integer(mevcut$Seed[1]),
        mod = as.character(mevcut$Mode[1]),
        sezon_id = .bs_db_kosu_sezon_id(mevcut),
        plan_id = {
          deger <- suppressWarnings(as.integer(mevcut$BlueprintID[1]))
          if (length(deger) == 0L || is.na(deger)) NULL else deger
        }
      ))
    }

    .bs_db_aktif_kosu_kapat(handle$conn, uid)

    surumler <- bs_surum_bilgisi()
    kosu_id <- .bs_db_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_Game_Runs",
        "(UserID, MapID, Difficulty, Seed, Mode, ChallengeSeasonID, BlueprintID,",
        "GameVersion, BalanceVersion, SchemaVersion, Status, ClientToken, StartedAt)",
        "OUTPUT INSERTED.GameRunID AS id",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_Game_Runs",
        "(UserID, MapID, Difficulty, Seed, Mode, ChallengeSeasonID, BlueprintID,",
        "GameVersion, BalanceVersion, SchemaVersion, Status, ClientToken, StartedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      id_column = "GameRunID",
      params = normalize_db_params(list(
        uid,
        normalize_db_technical_value(as.character(harita)[1]),
        normalize_db_technical_value(as.character(zorluk)[1]),
        as.integer(tohum),
        normalize_db_technical_value(as.character(mod)[1]),
        if (is.null(sezon_id)) NA_integer_ else as.integer(sezon_id),
        if (is.null(plan_id)) NA_integer_ else as.integer(plan_id),
        surumler$oyun,
        surumler$denge,
        surumler$sema,
        "Aktif",
        jeton,
        .bs_db_now_stamp()
      ))
    )

    DBI::dbCommit(handle$conn)
    tamamlandi <- TRUE

    list(
      kosu_id = kosu_id,
      harita = as.character(harita)[1],
      zorluk = as.character(zorluk)[1],
      tohum = as.integer(tohum),
      mod = as.character(mod)[1],
      sezon_id = if (is.null(sezon_id)) NULL else as.integer(sezon_id),
      plan_id = if (is.null(plan_id)) NULL else as.integer(plan_id)
    )
  },
  fallback = NULL,
  uyari = "Koşu kaydı oluşturulamadı:")
}

# Koşu satırını sahiplik doğrulamasıyla getirir (yoksa NULL).
.bs_db_kosu_satiri <- function(conn, uid, kosu_id) {
  res <- DBI::dbGetQuery(
    conn,
    paste(
      "SELECT GameRunID, MapID, Difficulty, Seed, Mode, ChallengeSeasonID,",
      "BlueprintID, Status, ClientToken, StartedAt, Score, Stars, XPEarned,",
      "FinalWave, CoreHealth, DurationSeconds",
      "FROM MB_Game_Runs WHERE GameRunID = ? AND UserID = ?"
    ),
    params = normalize_db_params(list(as.integer(kosu_id), uid))
  )
  if (nrow(res) == 0L) return(NULL)
  res
}

# Koşu satırındaki ChallengeSeasonID'yi güvenle okur (NA/NULL ise NULL döner).
# Haftalık liderlik gönderimi, koşu BAŞLARKEN atanan bu sezonu kullanmalıdır;
# sonuçlandırma anında "şimdiki" hafta yeniden türetilirse, hafta haftalık
# koşu sırasında değişmişse (ISO hafta dönümü) sezon uyuşmazlığından skor
# liderlik tablosuna hiç ulaşamaz.
.bs_db_kosu_sezon_id <- function(kosu) {
  deger <- suppressWarnings(as.integer(kosu$ChallengeSeasonID[1]))
  if (length(deger) == 0L || is.na(deger)) return(NULL)
  deger
}

# Sonuçlanmış koşu satırından istemci sonuç paketi üretir (idempotent yanıt).
.bs_db_sonuc_paketi <- function(kosu, tekrar = TRUE) {
  list(
    kabul = as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi"),
    neden = if (as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi")) {
      NULL
    } else {
      "kosu_kapali"
    },
    kosu_id = as.integer(kosu$GameRunID[1]),
    sezon_id = .bs_db_kosu_sezon_id(kosu),
    puan = as.integer(kosu$Score[1] %||% 0L),
    yildiz = as.integer(kosu$Stars[1] %||% 0L),
    xp = as.integer(kosu$XPEarned[1] %||% 0L),
    zafer = identical(as.character(kosu$Status[1]), "Tamamlandı"),
    tekrar = isTRUE(tekrar),
    yeni_basarimlar = character(0)
  )
}

#' Devam Edilebilir Aktif Koşuyu Getir
#'
#' @description Kullanıcının en son Aktif koşusunu ve varsa en son kontrol
#' noktasını döndürür (sayfaya geri dönüşte devam akışı için). ChallengeSeasonID
#' ve BlueprintID de dahildir: istemci "Devam Et" isteğini gönderirken bu
#' alanları düzleştirip (flatten) koşu başlatma isteğine taşımalıdır, aksi
#' halde haftalık/plan modlu devam istekleri harita_zorluk/plan_kimligi
#' nedeniyle reddedilir veya sessizce yeni bir koşu başlatır.
bs_db_active_run <- function(user_id, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Aktif koşu sorgusu için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kosu <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameRunID, MapID, Difficulty, Seed, Mode, ChallengeSeasonID,",
        "BlueprintID, ClientToken, StartedAt",
        "FROM MB_Game_Runs WHERE UserID = ? AND Status = ?",
        "ORDER BY GameRunID DESC"
      ),
      params = normalize_db_params(list(uid, "Aktif"))
    )
    if (nrow(kosu) == 0L) return(NULL)

    kontrol <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT WaveNumber, StateJson FROM MB_Game_RunCheckpoints",
        "WHERE GameRunID = ? ORDER BY WaveNumber DESC"
      ),
      params = normalize_db_params(list(as.integer(kosu$GameRunID[1])))
    )

    list(
      kosu_id = as.integer(kosu$GameRunID[1]),
      harita = as.character(kosu$MapID[1]),
      zorluk = as.character(kosu$Difficulty[1]),
      tohum = as.integer(kosu$Seed[1]),
      mod = as.character(kosu$Mode[1]),
      istemci_jetonu = as.character(kosu$ClientToken[1]),
      sezon_id = .bs_db_kosu_sezon_id(kosu),
      plan_id = {
        deger <- suppressWarnings(as.integer(kosu$BlueprintID[1]))
        if (length(deger) == 0L || is.na(deger)) NULL else deger
      },
      kontrol_dalga = if (nrow(kontrol) > 0L) as.integer(kontrol$WaveNumber[1]) else NULL,
      kontrol_durum = if (nrow(kontrol) > 0L) as.character(kontrol$StateJson[1]) else NULL
    )
  },
  fallback = NULL,
  uyari = "Aktif koşu yüklenemedi:")
}

#' Kontrol Noktası Kaydet
#'
#' @description Dalga sınırında doğrulanmış kontrol noktasını yazar. Aynı
#' dalga için tekrarlanan yazım günceller (yeniden deneme güvenliği).
bs_db_save_checkpoint <- function(user_id, kosu_id, dalga, durum_json,
                                  conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Kontrol noktası için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kosu <- .bs_db_kosu_satiri(handle$conn, uid, kosu_id)
    if (is.null(kosu) || !identical(as.character(kosu$Status[1]), "Aktif")) {
      return(FALSE)
    }

    harita_kaydi <- bs_harita_katalogu()[[as.character(kosu$MapID[1])]]
    if (is.null(harita_kaydi)) return(FALSE)

    onceki <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT MAX(WaveNumber) AS son FROM MB_Game_RunCheckpoints",
        "WHERE GameRunID = ?"
      ),
      params = normalize_db_params(list(as.integer(kosu_id)))
    )
    onceki_dalga <- suppressWarnings(as.integer(onceki$son[1]))
    if (is.na(onceki_dalga)) onceki_dalga <- 0L

    dogrulama <- bs_kontrol_noktasi_dogrula(
      dalga, durum_json, harita_kaydi, onceki_dalga = onceki_dalga
    )

    # Aynı dalganın tekrar gönderimi: mevcut satırı güncelle (idempotent).
    if (!isTRUE(dogrulama$gecerli)) {
      if (identical(dogrulama$neden, "kontrol_sirasi") &&
          identical(suppressWarnings(as.integer(dalga)), onceki_dalga)) {
        guncellenen <- DBI::dbExecute(
          handle$conn,
          paste(
            "UPDATE MB_Game_RunCheckpoints SET StateJson = ?, CreatedAt = ?",
            "WHERE GameRunID = ? AND WaveNumber = ?"
          ),
          params = normalize_db_params(list(
            as.character(durum_json)[1], .bs_db_now_stamp(),
            as.integer(kosu_id), onceki_dalga
          ))
        )
        return(guncellenen > 0L)
      }
      return(FALSE)
    }

    DBI::dbExecute(
      handle$conn,
      paste(
        "INSERT INTO MB_Game_RunCheckpoints",
        "(GameRunID, WaveNumber, StateJson, CreatedAt)",
        "VALUES (?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        as.integer(kosu_id), dogrulama$dalga,
        as.character(durum_json)[1], .bs_db_now_stamp()
      ))
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Kontrol noktası kaydedilemedi:")
}

# --- Sonuçlandırma iç yardımcıları (transaction içinde çağrılır) --------------

.bs_db_upsert_campaign <- function(conn, uid, harita, zorluk, sonuc) {
  simdi <- .bs_db_now_stamp()
  tamamlanan_artis <- if (isTRUE(sonuc$zafer)) 1L else 0L

  guncellenen <- DBI::dbExecute(
    conn,
    paste(
      "UPDATE MB_Game_CampaignProgress SET",
      "Stars = CASE WHEN ? > Stars THEN ? ELSE Stars END,",
      "BestScore = CASE WHEN ? > BestScore THEN ? ELSE BestScore END,",
      "HighestWave = CASE WHEN ? > HighestWave THEN ? ELSE HighestWave END,",
      "CompletedCount = CompletedCount + ?,",
      "LastPlayedAt = ?",
      "WHERE UserID = ? AND MapID = ? AND Difficulty = ?"
    ),
    params = normalize_db_params(list(
      sonuc$yildiz, sonuc$yildiz,
      sonuc$puan, sonuc$puan,
      sonuc$son_dalga, sonuc$son_dalga,
      tamamlanan_artis, simdi,
      uid, harita, zorluk
    ))
  )

  if (guncellenen == 0L) {
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO MB_Game_CampaignProgress",
        "(UserID, MapID, Difficulty, Stars, BestScore, HighestWave,",
        "CompletedCount, LastPlayedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        uid, harita, zorluk, sonuc$yildiz, sonuc$puan,
        sonuc$son_dalga, tamamlanan_artis, simdi
      ))
    )
  }

  invisible(NULL)
}

.bs_db_upsert_hero <- function(conn, uid, kahraman_id, xp) {
  guncellenen <- DBI::dbExecute(
    conn,
    paste(
      "UPDATE MB_Game_HeroProgress SET UsesCount = UsesCount + 1,",
      "MasteryXP = MasteryXP + ? WHERE UserID = ? AND HeroID = ?"
    ),
    params = normalize_db_params(list(as.integer(xp), uid, kahraman_id))
  )
  if (guncellenen == 0L) {
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO MB_Game_HeroProgress (UserID, HeroID, UsesCount, MasteryXP)",
        "VALUES (?, ?, 1, ?)"
      ),
      params = normalize_db_params(list(uid, kahraman_id, as.integer(xp)))
    )
  }
  invisible(NULL)
}

.bs_db_profil_guncelle <- function(conn, uid, sonuc) {
  profil <- DBI::dbGetQuery(
    conn,
    "SELECT TotalXP, TotalScore FROM MB_Game_Profiles WHERE UserID = ?",
    params = normalize_db_params(list(uid))
  )

  # Profil satırı henüz açılmamışsa transaction içinde oluşturulur; XP/puan
  # kaybolmaz (koşu, profil ekranı hiç açılmadan da bitirilebilir).
  if (nrow(profil) == 0L) {
    ilk_xp <- as.integer(sonuc$xp)
    ilk_seviye <- bs_seviye_hesapla(ilk_xp)
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO MB_Game_Profiles",
        "(UserID, PlayerLevel, TotalXP, TotalScore, SettingsJson,",
        "CreatedAt, UpdatedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        uid, ilk_seviye, ilk_xp, as.integer(sonuc$puan), "{}",
        .bs_db_now_stamp(), .bs_db_now_stamp()
      ))
    )
    return(list(seviye = ilk_seviye, xp = ilk_xp))
  }

  yeni_xp <- as.integer(profil$TotalXP[1]) + as.integer(sonuc$xp)
  yeni_seviye <- bs_seviye_hesapla(yeni_xp)

  DBI::dbExecute(
    conn,
    paste(
      "UPDATE MB_Game_Profiles SET TotalXP = ?, PlayerLevel = ?,",
      "TotalScore = TotalScore + ?, UpdatedAt = ? WHERE UserID = ?"
    ),
    params = normalize_db_params(list(
      yeni_xp, yeni_seviye, as.integer(sonuc$puan), .bs_db_now_stamp(), uid
    ))
  )

  list(seviye = yeni_seviye, xp = yeni_xp)
}

.bs_db_basarim_ekle <- function(conn, uid, item_id, item_tur) {
  mevcut <- DBI::dbGetQuery(
    conn,
    "SELECT 1 AS var FROM MB_Game_Achievements WHERE UserID = ? AND ItemID = ?",
    params = normalize_db_params(list(uid, item_id))
  )
  if (nrow(mevcut) > 0L) return(FALSE)

  DBI::dbExecute(
    conn,
    paste(
      "INSERT INTO MB_Game_Achievements (UserID, ItemID, ItemType, EarnedAt)",
      "VALUES (?, ?, ?, ?)"
    ),
    params = normalize_db_params(list(uid, item_id, item_tur, .bs_db_now_stamp()))
  )
  TRUE
}

# Başarımları koşu sonucuna ve güncel kampanya durumuna göre değerlendirir;
# yeni kazanılan kimliklerin karakter vektörünü döndürür.
.bs_db_basarimlari_degerlendir <- function(conn, uid, kosu, sonuc, ozet) {
  yeni <- character(0)

  kampanya <- DBI::dbGetQuery(
    conn,
    "SELECT MapID, Stars, CompletedCount FROM MB_Game_CampaignProgress WHERE UserID = ?",
    params = normalize_db_params(list(uid))
  )

  kazandir <- function(item_id, tur = "basarim") {
    if (.bs_db_basarim_ekle(conn, uid, item_id, tur)) {
      yeni <<- c(yeni, item_id)
    }
  }

  if (isTRUE(sonuc$zafer)) {
    kazandir("ilk_zafer")

    harita_kaydi <- bs_harita_katalogu()[[as.character(kosu$MapID[1])]]
    if (!is.null(harita_kaydi) &&
        sonuc$son_cekirdek >= harita_kaydi$taban_cekirdek) {
      kazandir("kusursuz_savunma")
    }
    if (sonuc$yildiz >= 3L) {
      kazandir("uc_yildiz")
      kazandir("acilim_veri_izleri", tur = "acilim")
    }
    if (identical(as.character(kosu$Mode[1]), "haftalik")) {
      kazandir("haftalik_katilimci")
    }

    tamamlanan_haritalar <- unique(as.character(
      kampanya$MapID[kampanya$CompletedCount > 0]
    ))
    if (all(names(bs_harita_katalogu()) %in% tamamlanan_haritalar)) {
      kazandir("kampanya_ustasi")
      kazandir("acilim_gece_temasi", tur = "acilim")
    }
  }

  if (length(sonuc$kahramanlar) >= 5L) {
    kazandir("tam_kadro")
  }

  # Patron Avcısı: patron dalgalarında çekirdek kaybı yaşanmamış olmalı.
  dalgalar <- ozet$dalga_ozetleri
  if (is.list(dalgalar) && length(dalgalar) > 0) {
    harita_kaydi <- bs_harita_katalogu()[[as.character(kosu$MapID[1])]]
    if (!is.null(harita_kaydi)) {
      onceki <- harita_kaydi$taban_cekirdek
      for (dalga in dalgalar) {
        d_no <- suppressWarnings(as.integer(dalga$dalga))
        d_cekirdek <- suppressWarnings(as.numeric(dalga$cekirdek))
        if (!is.na(d_no) && !is.na(d_cekirdek) &&
            bs_patron_dalgasi_mi(d_no, harita_kaydi$dalga_sayisi) &&
            d_cekirdek >= onceki) {
          kazandir("patron_avcisi")
          break
        }
        if (!is.na(d_cekirdek)) onceki <- d_cekirdek
      }
    }
  }

  yeni
}

#' Koşuyu Sonuçlandır (İşlem-Güvenli, Idempotent)
#'
#' @description İstemci özetini sunucu doğrulamasından geçirir; geçerliyse
#' koşu kaydını, kampanya/kahraman ilerlemesini, profil XP/seviyesini ve
#' başarımları TEK transaction içinde günceller. Aynı jetonla tekrar çağrı
#' saklanan sonucu döndürür; hiçbir ödül çoğaltılmaz. Geçersiz özet koşuyu
#' Reddedildi yapar ve açıklayıcı neden döndürür.
bs_db_finalize_run <- function(user_id, kosu_id, istemci_jetonu, ozet,
                               conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(list(kabul = FALSE, neden = "kullanici"))

  handle <- .bs_db_try(
    .bs_db_acquire(conn, tx = TRUE),
    fallback = NULL,
    uyari = "Koşu sonuçlandırma için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(list(kabul = FALSE, neden = "baglanti"))
  on.exit(.bs_db_release(handle), add = TRUE)

  tamamlandi <- FALSE
  DBI::dbBegin(handle$conn)
  # Geri alma bağlantı bırakılmadan ÖNCE çalışmalı (after = FALSE): havuza
  # açık transaction'lı bağlantı dönmez.
  on.exit({
    if (!tamamlandi) {
      try(DBI::dbRollback(handle$conn), silent = TRUE)
    }
  }, add = TRUE, after = FALSE)

  sonuc_paketi <- .bs_db_try({
    kosu <- .bs_db_kosu_satiri(handle$conn, uid, kosu_id)
    if (is.null(kosu)) {
      return_paketi <- list(kabul = FALSE, neden = "kosu_bulunamadi")
      DBI::dbRollback(handle$conn)
      tamamlandi <- TRUE
      return(return_paketi)
    }

    # Jeton eşleşmesi: koşu başka bir istemci oturumunun kaydı olamaz.
    if (!identical(as.character(kosu$ClientToken[1]),
                   .bs_metin_temizle(istemci_jetonu, 64L))) {
      DBI::dbRollback(handle$conn)
      tamamlandi <- TRUE
      return(list(kabul = FALSE, neden = "jeton"))
    }

    # Idempotent tekrar: koşu zaten sonuçlanmışsa saklanan sonucu döndür.
    if (!identical(as.character(kosu$Status[1]), "Aktif")) {
      DBI::dbRollback(handle$conn)
      tamamlandi <- TRUE
      return(.bs_db_sonuc_paketi(kosu, tekrar = TRUE))
    }

    dogrulama <- bs_kosu_ozeti_dogrula(
      ozet = ozet,
      kosu = list(
        harita = as.character(kosu$MapID[1]),
        zorluk = as.character(kosu$Difficulty[1]),
        tohum = as.integer(kosu$Seed[1])
      ),
      sunucu_gecen_saniye = .bs_db_gecen_saniye(kosu$StartedAt[1])
    )

    if (!isTRUE(dogrulama$gecerli)) {
      DBI::dbExecute(
        handle$conn,
        paste(
          "UPDATE MB_Game_Runs SET Status = ?, RejectReason = ?,",
          "FinalizedAt = ? WHERE GameRunID = ? AND UserID = ?"
        ),
        params = normalize_db_params(list(
          "Reddedildi", normalize_db_technical_value(dogrulama$neden),
          .bs_db_now_stamp(), as.integer(kosu_id), uid
        ))
      )
      DBI::dbCommit(handle$conn)
      tamamlandi <- TRUE
      return(list(kabul = FALSE, neden = dogrulama$neden))
    }

    durum <- if (isTRUE(dogrulama$zafer)) "Tamamlandı" else "Yenilgi"
    puan_detay <- .bs_db_json(list(
      puan = dogrulama$puan, yildiz = dogrulama$yildiz, xp = dogrulama$xp,
      zafer = dogrulama$zafer, son_dalga = dogrulama$son_dalga,
      son_cekirdek = dogrulama$son_cekirdek,
      kahramanlar = as.list(dogrulama$kahramanlar)
    ))

    olay_ozeti <- .bs_db_json(ozet$olay_ozeti, empty = "[]")
    if (nchar(olay_ozeti, type = "bytes") > BS_MAX_YUK_KARAKTER) {
      olay_ozeti <- "[]"
    }

    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_Game_Runs SET Status = ?, Score = ?, Stars = ?, XPEarned = ?,",
        "FinalWave = ?, CoreHealth = ?, DurationSeconds = ?,",
        "ScoreDetailJson = ?, EventSummaryJson = ?, FinalizedAt = ?",
        "WHERE GameRunID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(
        durum, dogrulama$puan, dogrulama$yildiz, dogrulama$xp,
        dogrulama$son_dalga, dogrulama$son_cekirdek, dogrulama$sure_saniye,
        puan_detay, olay_ozeti, .bs_db_now_stamp(),
        as.integer(kosu_id), uid
      ))
    )

    # Kampanya ilerlemesi yalnızca kampanya modunda güncellenir.
    if (identical(as.character(kosu$Mode[1]), "kampanya")) {
      .bs_db_upsert_campaign(
        handle$conn, uid,
        as.character(kosu$MapID[1]), as.character(kosu$Difficulty[1]),
        dogrulama
      )
    }

    for (kahraman_id in dogrulama$kahramanlar) {
      .bs_db_upsert_hero(handle$conn, uid, kahraman_id, dogrulama$xp)
    }

    profil <- .bs_db_profil_guncelle(handle$conn, uid, dogrulama)
    yeni_basarimlar <- .bs_db_basarimlari_degerlendir(
      handle$conn, uid, kosu, dogrulama, ozet
    )

    DBI::dbCommit(handle$conn)
    tamamlandi <- TRUE

    list(
      kabul = TRUE,
      neden = NULL,
      kosu_id = as.integer(kosu_id),
      sezon_id = .bs_db_kosu_sezon_id(kosu),
      puan = dogrulama$puan,
      yildiz = dogrulama$yildiz,
      xp = dogrulama$xp,
      zafer = dogrulama$zafer,
      seviye = profil$seviye,
      toplam_xp = profil$xp,
      yeni_basarimlar = yeni_basarimlar,
      tekrar = FALSE
    )
  },
  fallback = list(kabul = FALSE, neden = "sunucu_hatasi"),
  uyari = "Koşu sonuçlandırılamadı:")

  sonuc_paketi
}

#' Aktif Koşuyu Bırak
#'
#' @description Kullanıcının sahip olduğu Aktif koşuyu Bırakıldı durumuna
#' çeker (onaylı vazgeçme akışı).
bs_db_abandon_run <- function(user_id, kosu_id, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Koşu bırakma için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    guncellenen <- DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_Game_Runs SET Status = ?, FinalizedAt = ?",
        "WHERE GameRunID = ? AND UserID = ? AND Status = ?"
      ),
      params = normalize_db_params(list(
        "Bırakıldı", .bs_db_now_stamp(), as.integer(kosu_id), uid, "Aktif"
      ))
    )
    guncellenen > 0L
  },
  fallback = FALSE,
  uyari = "Koşu bırakılamadı:")
}
