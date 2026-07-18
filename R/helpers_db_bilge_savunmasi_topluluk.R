# ==============================================================================
# Dosya Yolu: R/helpers_db_bilge_savunmasi_topluluk.R
# Açıklama: Bilge Savunması eşzamansız çok oyunculu DB katmanı: haftalık
#           meydan okuma sezonları ve liderlik tablosu, savunma planı
#           (blueprint) yayınlama/deneme ve haftalık topluluk operasyonu
#           katkıları. GERÇEK ZAMANLI ağ/senkronizasyon içermez.
#
# Sözleşmeler:
#   * Liderlik sıralaması bs_liderlik_sirala() ile deterministiktir; giriş
#     üyeliği koşu bazında idempotenttir (aynı koşu iki kez puan yazamaz).
#   * Plan yükleri yalnızca bs_plan_dogrula() süzgecinden geçmiş halde
#     saklanır; yayın sonrası değişmez (immutable), yalnızca sahibi yumuşak
#     silebilir.
#   * Görünen oyuncu adları MB_Users.KaynakAdi'den okunur; erişilemezse
#     "Oyuncu #<id>" maskesine düşer. E-posta/sicil gibi hassas alanlar
#     istemciye taşınmaz.
#   * Paylaşılan .bs_db_* altyapısı helpers_db_bilge_savunmasi_cekirdek.R
#     dosyasından gelir; bu dosya ondan SONRA yüklenmelidir.
# ==============================================================================

#' Haftalık Meydan Okuma Sezonunu Getir veya Oluştur
#'
#' @description Hafta koduna göre sezon satırını döndürür; yoksa deterministik
#' yapılandırma ile oluşturur. Eşzamanlı oluşturma yarışında tekrar okur.
bs_db_get_or_create_season <- function(meydan = bs_haftalik_meydan_okuma(),
                                       conn = NULL) {
  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Meydan okuma sezonu için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    oku <- function() {
      DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT ChallengeSeasonID, WeekCode, MapID, Difficulty, Seed, ConfigJson",
          "FROM MB_Game_ChallengeSeasons WHERE WeekCode = ?"
        ),
        params = normalize_db_params(list(meydan$hafta_kodu))
      )
    }

    mevcut <- oku()
    if (nrow(mevcut) == 0L) {
      eklendi <- tryCatch({
        DBI::dbExecute(
          handle$conn,
          paste(
            "INSERT INTO MB_Game_ChallengeSeasons",
            "(WeekCode, MapID, Difficulty, Seed, ConfigJson, CreatedAt)",
            "VALUES (?, ?, ?, ?, ?, ?)"
          ),
          params = normalize_db_params(list(
            meydan$hafta_kodu,
            normalize_db_technical_value(meydan$harita),
            normalize_db_technical_value(meydan$zorluk),
            as.integer(meydan$tohum),
            .bs_db_json(meydan),
            .bs_db_now_stamp()
          ))
        )
        TRUE
      }, error = function(e) FALSE)
      # Eşzamanlı yarışta benzersiz kısıt patlayabilir; her durumda tekrar oku.
      mevcut <- oku()
      if (nrow(mevcut) == 0L && !eklendi) return(NULL)
    }

    list(
      sezon_id = as.integer(mevcut$ChallengeSeasonID[1]),
      hafta_kodu = as.character(mevcut$WeekCode[1]),
      harita = as.character(mevcut$MapID[1]),
      zorluk = as.character(mevcut$Difficulty[1]),
      tohum = as.integer(mevcut$Seed[1])
    )
  },
  fallback = NULL,
  uyari = "Meydan okuma sezonu hazırlanamadı:")
}

#' Sezonu Kimliğine Göre Getir (Yeniden Türetmeden)
#'
#' @description Verilen ChallengeSeasonID'ye ait sezon kaydını olduğu gibi
#' döndürür; "şimdiki" haftayı YENİDEN TÜRETMEZ. Haftalık bir koşu, ISO hafta
#' dönümünün tam ortasında bitirilebilir; liderlik gönderimi koşunun
#' BAŞLARKEN atandığı sezonu kullanmalıdır, aksi halde
#' bs_db_submit_challenge_entry() sezon uyuşmazlığından geçerli koşuyu
#' reddeder. Bulunamazsa NULL döner.
bs_db_get_season_by_id <- function(sezon_id, conn = NULL) {
  sid <- suppressWarnings(as.integer(sezon_id))
  if (length(sid) == 0L || is.na(sid)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Meydan okuma sezonu için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    satir <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT ChallengeSeasonID, WeekCode, MapID, Difficulty, Seed",
        "FROM MB_Game_ChallengeSeasons WHERE ChallengeSeasonID = ?"
      ),
      params = normalize_db_params(list(sid))
    )
    if (nrow(satir) == 0L) return(NULL)

    list(
      sezon_id = as.integer(satir$ChallengeSeasonID[1]),
      hafta_kodu = as.character(satir$WeekCode[1]),
      harita = as.character(satir$MapID[1]),
      zorluk = as.character(satir$Difficulty[1]),
      tohum = as.integer(satir$Seed[1])
    )
  },
  fallback = NULL,
  uyari = "Sezon getirilemedi:")
}

# Yeni giriş eski girişten daha mı iyi? (liderlik eşitlik bozucularıyla)
.bs_db_giris_daha_iyi_mi <- function(yeni, eski) {
  if (yeni$puan != eski$puan) return(yeni$puan > eski$puan)
  if (yeni$cekirdek != eski$cekirdek) return(yeni$cekirdek > eski$cekirdek)
  if (yeni$dalga != eski$dalga) return(yeni$dalga > eski$dalga)
  yeni$sure < eski$sure
}

#' Haftalık Meydan Okuma Girişi Gönder (Koşu Bazında Idempotent)
#'
#' @description Sonuçlanmış bir haftalık koşuyu sezona işler. Kullanıcı başına
#' tek giriş tutulur; yeni sonuç yalnızca eşitlik bozucu kurallara göre daha
#' iyiyse mevcut girişin yerine geçer. Aynı koşunun tekrar gönderimi hiçbir
#' şeyi değiştirmez.
bs_db_submit_challenge_entry <- function(user_id, sezon_id, kosu_id,
                                         conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Meydan okuma girişi için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kosu <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameRunID, Status, Mode, ChallengeSeasonID, Score, CoreHealth,",
        "FinalWave, DurationSeconds",
        "FROM MB_Game_Runs WHERE GameRunID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(as.integer(kosu_id), uid))
    )
    if (nrow(kosu) == 0L ||
        !identical(as.character(kosu$Mode[1]), "haftalik") ||
        !as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi") ||
        !identical(as.integer(kosu$ChallengeSeasonID[1]), as.integer(sezon_id))) {
      return(FALSE)
    }

    yeni <- list(
      puan = as.numeric(kosu$Score[1] %||% 0),
      cekirdek = as.numeric(kosu$CoreHealth[1] %||% 0),
      dalga = as.numeric(kosu$FinalWave[1] %||% 0),
      sure = as.numeric(kosu$DurationSeconds[1] %||% 999999)
    )

    mevcut <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT ChallengeEntryID, GameRunID, Score, CoreHealth, FinalWave,",
        "DurationSeconds FROM MB_Game_ChallengeEntries",
        "WHERE ChallengeSeasonID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(as.integer(sezon_id), uid))
    )

    if (nrow(mevcut) > 0L) {
      # Aynı koşu zaten işlenmişse hiçbir şey değişmez (idempotent).
      if (identical(as.integer(mevcut$GameRunID[1]), as.integer(kosu_id))) {
        return(TRUE)
      }
      eski <- list(
        puan = as.numeric(mevcut$Score[1] %||% 0),
        cekirdek = as.numeric(mevcut$CoreHealth[1] %||% 0),
        dalga = as.numeric(mevcut$FinalWave[1] %||% 0),
        sure = as.numeric(mevcut$DurationSeconds[1] %||% 999999)
      )
      if (!.bs_db_giris_daha_iyi_mi(yeni, eski)) {
        return(TRUE)
      }
      DBI::dbExecute(
        handle$conn,
        paste(
          "UPDATE MB_Game_ChallengeEntries SET GameRunID = ?, Score = ?,",
          "CoreHealth = ?, FinalWave = ?, DurationSeconds = ?, SubmittedAt = ?",
          "WHERE ChallengeEntryID = ?"
        ),
        params = normalize_db_params(list(
          as.integer(kosu_id), yeni$puan, yeni$cekirdek, yeni$dalga, yeni$sure,
          .bs_db_now_stamp(), as.integer(mevcut$ChallengeEntryID[1])
        ))
      )
      return(TRUE)
    }

    DBI::dbExecute(
      handle$conn,
      paste(
        "INSERT INTO MB_Game_ChallengeEntries",
        "(ChallengeSeasonID, UserID, GameRunID, Score, CoreHealth, FinalWave,",
        "DurationSeconds, SubmittedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        as.integer(sezon_id), uid, as.integer(kosu_id), yeni$puan,
        yeni$cekirdek, yeni$dalga, yeni$sure, .bs_db_now_stamp()
      ))
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Meydan okuma girişi kaydedilemedi:")
}

# Oyuncu görünen profillerini güvenli biçimde çözer: ad (KaynakAdi),
# rumuz (KullaniciAdi) ve departman. E-posta/sicil gibi hassas alanlar
# ASLA istemciye taşınmaz. MB_Users erişilemezse "Oyuncu #<id>" maskesine düşer.
.bs_db_kullanici_profilleri <- function(conn, user_ids) {
  ids <- unique(as.integer(user_ids))
  ids <- ids[!is.na(ids) & ids > 0L]

  profiller <- list()
  for (id in ids) {
    profiller[[as.character(id)]] <- list(
      ad = paste0("Oyuncu #", id), rumuz = "", departman = ""
    )
  }
  if (length(ids) == 0L) return(profiller)

  gorunur <- function(deger) {
    metin <- as.character(deger)[1]
    if (is.na(metin) || !nzchar(trimws(metin))) return("")
    if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
      metin <- normalize_db_read_visible_value(metin)
    }
    trimws(metin)
  }

  sorgu <- tryCatch({
    yer_tutucular <- paste(rep("?", length(ids)), collapse = ", ")
    DBI::dbGetQuery(
      conn,
      sprintf(
        paste(
          "SELECT UserID, KaynakAdi, KullaniciAdi, Departman",
          "FROM MB_Users WHERE UserID IN (%s)"
        ),
        yer_tutucular
      ),
      params = normalize_db_params(as.list(ids))
    )
  }, error = function(e) NULL)

  if (is.data.frame(sorgu) && nrow(sorgu) > 0L) {
    for (i in seq_len(nrow(sorgu))) {
      anahtar <- as.character(sorgu$UserID[i])
      ad <- gorunur(sorgu$KaynakAdi[i])
      profiller[[anahtar]] <- list(
        ad = if (nzchar(ad)) ad else profiller[[anahtar]]$ad,
        rumuz = gorunur(sorgu$KullaniciAdi[i]),
        departman = gorunur(sorgu$Departman[i])
      )
    }
  }

  profiller
}

#' Haftalık Liderlik Tablosu
#'
#' @description Sezonun girişlerini deterministik eşitlik bozucularla sıralar;
#' ilk `limit` girişi, kullanıcının kendi sırasını ve yakın komşularını
#' döndürür. Girdi hacmi sınırlıdır (en fazla 500 satır işlenir).
bs_db_challenge_leaderboard <- function(sezon_id, user_id = NULL, limit = 20L,
                                        conn = NULL) {
  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Liderlik tablosu için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    girisler <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT UserID, Score AS Puan, CoreHealth AS Cekirdek,",
        "FinalWave AS SonDalga, DurationSeconds AS SureSaniye,",
        "SubmittedAt AS GonderimZamani",
        "FROM MB_Game_ChallengeEntries WHERE ChallengeSeasonID = ?"
      ),
      params = normalize_db_params(list(as.integer(sezon_id)))
    )

    # Kırpmadan ÖNCE sırala: sorgu ORDER BY içermez, bu yüzden 500 satır
    # sınırı sıralanmamış (rastgele) sonuç kümesine uygulanırsa yüksek
    # puanlı satırlar düşebilir ve hem gösterilen ilk sıralar hem de
    # benim_sira yanlış çıkabilir.
    girisler <- bs_liderlik_sirala(girisler)
    if (nrow(girisler) > 500L) girisler <- girisler[seq_len(500L), , drop = FALSE]

    uid <- .bs_db_kullanici_id(user_id)
    benim_sira <- if (!is.null(uid) && nrow(girisler) > 0L) {
      hangi <- which(as.integer(girisler$UserID) == uid)
      if (length(hangi) > 0L) as.integer(hangi[1]) else NULL
    } else {
      NULL
    }

    profiller <- .bs_db_kullanici_profilleri(handle$conn, girisler$UserID)

    paketle <- function(satirlar, siralar) {
      lapply(seq_along(siralar), function(i) {
        satir <- satirlar[i, , drop = FALSE]
        satir_uid <- as.integer(satir$UserID[1])
        profil <- profiller[[as.character(satir_uid)]] %||%
          list(ad = paste0("Oyuncu #", satir_uid), rumuz = "", departman = "")
        list(
          sira = siralar[i],
          oyuncu = profil$ad,
          rumuz = profil$rumuz,
          departman = profil$departman,
          benim = !is.null(uid) && identical(satir_uid, uid),
          puan = as.numeric(satir$Puan[1]),
          cekirdek = as.numeric(satir$Cekirdek[1]),
          son_dalga = as.numeric(satir$SonDalga[1]),
          sure_saniye = as.numeric(satir$SureSaniye[1])
        )
      })
    }

    ilkler_n <- min(nrow(girisler), max(1L, as.integer(limit)))
    ilkler <- if (nrow(girisler) > 0L) {
      paketle(girisler[seq_len(ilkler_n), , drop = FALSE], seq_len(ilkler_n))
    } else {
      list()
    }

    yakinlar <- list()
    if (!is.null(benim_sira) && benim_sira > ilkler_n) {
      aralik <- seq(max(1L, benim_sira - 2L), min(nrow(girisler), benim_sira + 2L))
      yakinlar <- paketle(girisler[aralik, , drop = FALSE], aralik)
    }

    list(
      toplam_katilimci = nrow(girisler),
      benim_sira = benim_sira,
      ilkler = ilkler,
      yakinlar = yakinlar
    )
  },
  fallback = NULL,
  uyari = "Liderlik tablosu yüklenemedi:")
}

#' Savunma Planı Yayınla
#'
#' @description Kullanıcının SONUÇLANMIŞ bir koşusundan doğrulanmış savunma
#' planı yayınlar. Plan yükü bs_plan_dogrula() süzgecinden geçirilir; yayın
#' sonrası değiştirilemez. Başarıda plan kimliği döner.
bs_db_publish_blueprint <- function(user_id, kosu_id, baslik, plan,
                                    conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(NULL)

  dogrulama <- bs_plan_dogrula(plan)
  if (!isTRUE(dogrulama$gecerli)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Plan yayını için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kosu <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameRunID, Status, MapID, Difficulty, Seed, Score, Stars,",
        "FinalWave, CoreHealth",
        "FROM MB_Game_Runs WHERE GameRunID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(as.integer(kosu_id), uid))
    )
    if (nrow(kosu) == 0L ||
        !as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi")) {
      return(NULL)
    }

    # Plan, koşunun gerçek harita/zorluk/tohum üçlüsünü taşımalıdır.
    p <- dogrulama$plan
    if (!identical(p$harita, as.character(kosu$MapID[1])) ||
        !identical(p$zorluk, as.character(kosu$Difficulty[1])) ||
        !identical(p$tohum, as.integer(kosu$Seed[1]))) {
      return(NULL)
    }

    plan_json <- .bs_db_json(p)
    if (nchar(plan_json, type = "bytes") > BS_MAX_PLAN_KARAKTER) return(NULL)

    baslik_temiz <- .bs_metin_temizle(baslik, 80L)
    if (!nzchar(baslik_temiz)) baslik_temiz <- p$baslik

    yaratici_ozet <- .bs_db_json(list(
      puan = as.numeric(kosu$Score[1] %||% 0),
      yildiz = as.integer(kosu$Stars[1] %||% 0L),
      son_dalga = as.integer(kosu$FinalWave[1] %||% 0L),
      cekirdek = as.numeric(kosu$CoreHealth[1] %||% 0)
    ))

    .bs_db_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_Game_Blueprints",
        "(UserID, GameRunID, MapID, Difficulty, Seed, Title, PayloadJson,",
        "SchemaVersion, CreatorResultJson, IsDeleted, CreatedAt)",
        "OUTPUT INSERTED.BlueprintID AS id",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)"
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_Game_Blueprints",
        "(UserID, GameRunID, MapID, Difficulty, Seed, Title, PayloadJson,",
        "SchemaVersion, CreatorResultJson, IsDeleted, CreatedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)"
      ),
      id_column = "BlueprintID",
      params = normalize_db_params(list(
        uid, as.integer(kosu_id),
        normalize_db_technical_value(p$harita),
        normalize_db_technical_value(p$zorluk),
        p$tohum,
        normalize_db_visible_value(baslik_temiz),
        plan_json,
        BS_SEMA_SURUMU,
        yaratici_ozet,
        .bs_db_now_stamp()
      ))
    )
  },
  fallback = NULL,
  uyari = "Savunma planı yayınlanamadı:")
}

#' Yayınlanmış Savunma Planlarını Listele
bs_db_list_blueprints <- function(user_id = NULL, limit = 30L, conn = NULL) {
  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Plan listesi için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    planlar <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT BlueprintID, UserID, MapID, Difficulty, Seed, Title,",
        "SchemaVersion, CreatorResultJson, CreatedAt",
        "FROM MB_Game_Blueprints WHERE IsDeleted = 0",
        "ORDER BY BlueprintID DESC"
      )
    )

    n <- min(nrow(planlar), max(1L, as.integer(limit)))
    if (nrow(planlar) > n) planlar <- planlar[seq_len(n), , drop = FALSE]

    uid <- .bs_db_kullanici_id(user_id)
    profiller <- .bs_db_kullanici_profilleri(handle$conn, planlar$UserID)
    katalog <- bs_harita_katalogu()

    lapply(seq_len(nrow(planlar)), function(i) {
      satir_uid <- as.integer(planlar$UserID[i])
      profil <- profiller[[as.character(satir_uid)]] %||%
        list(ad = paste0("Oyuncu #", satir_uid), rumuz = "", departman = "")
      baslik <- as.character(planlar$Title[i])
      if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
        baslik <- normalize_db_read_visible_value(baslik)
      }
      yaratici_ozet <- tryCatch(
        jsonlite::fromJSON(planlar$CreatorResultJson[i] %||% "{}",
                           simplifyVector = FALSE),
        error = function(e) list()
      )
      harita_id <- as.character(planlar$MapID[i])
      list(
        plan_id = as.integer(planlar$BlueprintID[i]),
        baslik = baslik,
        yaratici = profil$ad,
        yaratici_departman = profil$departman,
        benim = !is.null(uid) && identical(satir_uid, uid),
        harita = harita_id,
        harita_ad = katalog[[harita_id]]$ad %||% harita_id,
        zorluk = as.character(planlar$Difficulty[i]),
        sema = as.integer(planlar$SchemaVersion[i]),
        yaratici_sonucu = yaratici_ozet,
        yayin_zamani = as.character(planlar$CreatedAt[i])
      )
    })
  },
  fallback = NULL,
  uyari = "Plan listesi yüklenemedi:")
}

#' Tek Savunma Planını Getir (Deneme Akışı)
#'
#' @description Silinmemiş planın doğrulanmış yükünü döndürür. Desteklenmeyen
#' şema sürümü zarifçe reddedilir (NULL + neden).
bs_db_get_blueprint <- function(plan_id, conn = NULL) {
  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Plan getirme için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    satir <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT BlueprintID, UserID, MapID, Difficulty, Seed, Title,",
        "PayloadJson, SchemaVersion, CreatorResultJson",
        "FROM MB_Game_Blueprints WHERE BlueprintID = ? AND IsDeleted = 0"
      ),
      params = normalize_db_params(list(as.integer(plan_id)))
    )
    if (nrow(satir) == 0L) return(NULL)

    if (!identical(as.integer(satir$SchemaVersion[1]), BS_SEMA_SURUMU)) {
      return(list(desteklenmiyor = TRUE, sema = as.integer(satir$SchemaVersion[1])))
    }

    yuk <- bs_yuk_coz(satir$PayloadJson[1], sinir = BS_MAX_PLAN_KARAKTER)
    if (is.null(yuk)) return(NULL)

    baslik <- as.character(satir$Title[1])
    if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
      baslik <- normalize_db_read_visible_value(baslik)
    }

    list(
      plan_id = as.integer(satir$BlueprintID[1]),
      sahip_id = as.integer(satir$UserID[1]),
      baslik = baslik,
      harita = as.character(satir$MapID[1]),
      zorluk = as.character(satir$Difficulty[1]),
      tohum = as.integer(satir$Seed[1]),
      plan = yuk,
      yaratici_sonucu = tryCatch(
        jsonlite::fromJSON(satir$CreatorResultJson[1] %||% "{}",
                           simplifyVector = FALSE),
        error = function(e) list()
      )
    )
  },
  fallback = NULL,
  uyari = "Savunma planı yüklenemedi:")
}

#' Savunma Planını Yumuşak Sil (Yalnızca Sahibi)
bs_db_soft_delete_blueprint <- function(user_id, plan_id, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Plan silme için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    guncellenen <- DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_Game_Blueprints SET IsDeleted = 1",
        "WHERE BlueprintID = ? AND UserID = ? AND IsDeleted = 0"
      ),
      params = normalize_db_params(list(as.integer(plan_id), uid))
    )
    guncellenen > 0L
  },
  fallback = FALSE,
  uyari = "Savunma planı silinemedi:")
}

#' Haftalık Topluluk Operasyonu Katkısı Ekle (Koşu Bazında Idempotent)
#'
#' @description Sonuçlanmış koşunun topluluk metriklerini (etkisizleştirilen
#' tehdit, savunulan dalga, puan) haftalık operasyona işler. Koşu başına tek
#' katkı satırı yazılır; tekrar çağrı hiçbir şeyi değiştirmez.
bs_db_add_community_contribution <- function(user_id, kosu_id, hafta_kodu,
                                             etkisizlestirilen = 0L,
                                             conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Topluluk katkısı için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kosu <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameRunID, Status, FinalWave, Score",
        "FROM MB_Game_Runs WHERE GameRunID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(as.integer(kosu_id), uid))
    )
    if (nrow(kosu) == 0L ||
        !as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi")) {
      return(FALSE)
    }

    mevcut <- DBI::dbGetQuery(
      handle$conn,
      "SELECT 1 AS var FROM MB_Game_CommunityContributions WHERE GameRunID = ?",
      params = normalize_db_params(list(as.integer(kosu_id)))
    )
    if (nrow(mevcut) > 0L) return(TRUE)

    etkisiz <- suppressWarnings(as.integer(etkisizlestirilen))
    if (is.na(etkisiz) || etkisiz < 0L) etkisiz <- 0L
    # Katkı metriği makul sınır içinde kalmalı (dalga sınırı x dalga sayısı).
    etkisiz <- min(etkisiz, 600L)

    DBI::dbExecute(
      handle$conn,
      paste(
        "INSERT INTO MB_Game_CommunityContributions",
        "(WeekCode, UserID, GameRunID, ThreatsNeutralized, WavesDefended,",
        "PointsContributed, CreatedAt)",
        "VALUES (?, ?, ?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(as.character(hafta_kodu)[1]),
        uid, as.integer(kosu_id), etkisiz,
        as.integer(kosu$FinalWave[1] %||% 0L),
        as.numeric(kosu$Score[1] %||% 0),
        .bs_db_now_stamp()
      ))
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Topluluk katkısı kaydedilemedi:")
}

#' Haftalık Topluluk Operasyonu Toplamları
#'
#' @description Haftanın toplam topluluk ilerlemesini ve isteyen kullanıcının
#' kendi katkısını döndürür.
bs_db_community_totals <- function(hafta_kodu, user_id = NULL, conn = NULL) {
  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Topluluk toplamları için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    toplam <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT COUNT(DISTINCT UserID) AS Katilimci,",
        "COALESCE(SUM(ThreatsNeutralized), 0) AS Etkisizlestirilen,",
        "COALESCE(SUM(WavesDefended), 0) AS SavunulanDalga,",
        "COALESCE(SUM(PointsContributed), 0) AS ToplamPuan",
        "FROM MB_Game_CommunityContributions WHERE WeekCode = ?"
      ),
      params = normalize_db_params(list(as.character(hafta_kodu)[1]))
    )

    benim <- NULL
    uid <- .bs_db_kullanici_id(user_id)
    if (!is.null(uid)) {
      benim_df <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT COALESCE(SUM(ThreatsNeutralized), 0) AS Etkisizlestirilen,",
          "COALESCE(SUM(WavesDefended), 0) AS SavunulanDalga,",
          "COALESCE(SUM(PointsContributed), 0) AS ToplamPuan",
          "FROM MB_Game_CommunityContributions",
          "WHERE WeekCode = ? AND UserID = ?"
        ),
        params = normalize_db_params(list(as.character(hafta_kodu)[1], uid))
      )
      benim <- list(
        etkisizlestirilen = as.numeric(benim_df$Etkisizlestirilen[1]),
        savunulan_dalga = as.numeric(benim_df$SavunulanDalga[1]),
        toplam_puan = as.numeric(benim_df$ToplamPuan[1])
      )
    }

    list(
      hafta_kodu = as.character(hafta_kodu)[1],
      katilimci = as.numeric(toplam$Katilimci[1]),
      etkisizlestirilen = as.numeric(toplam$Etkisizlestirilen[1]),
      savunulan_dalga = as.numeric(toplam$SavunulanDalga[1]),
      toplam_puan = as.numeric(toplam$ToplamPuan[1]),
      hedef_etkisizlestirilen = 25000,
      benim = benim
    )
  },
  fallback = NULL,
  uyari = "Topluluk toplamları yüklenemedi:")
}
