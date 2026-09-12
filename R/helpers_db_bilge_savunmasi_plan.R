# ==============================================================================
# Dosya Yolu: R/helpers_db_bilge_savunmasi_plan.R
# Açıklama: Bilge Savunması savunma planı (blueprint) DB katmanı: yayınlama,
#           listeleme, tekil okuma ve sahibi tarafından yumuşak silme.
#
# Sözleşmeler:
#   * Plan yükleri yalnızca bs_plan_dogrula() süzgecinden geçmiş halde
#     saklanır; yayın sonrası değişmez (immutable).
#   * Yumuşak silme YALNIZCA plan sahibine açıktır (UserID kapsamı).
#   * Paylaşılan .bs_db_* altyapısı helpers_db_bilge_savunmasi_cekirdek.R'den,
#     kullanıcı profil maskesi .bs_db_kullanici_profilleri ise
#     helpers_db_bilge_savunmasi_topluluk.R'den gelir; bu dosya İKİSİNDEN de
#     SONRA yüklenmelidir.
#   * Bakım-yapılabilirlik cırcırı (800 satır / 25 fonksiyon) nedeniyle
#     topluluk dosyasından bilinçli olarak ayrılmıştır; geri taşımayın.
# ==============================================================================

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
        "SELECT GameRunID, Status, Mode, MapID, Difficulty, Seed, Score, Stars,",
        "FinalWave, CoreHealth",
        "FROM MB_Game_Runs WHERE GameRunID = ? AND UserID = ?"
      ),
      params = normalize_db_params(list(as.integer(kosu_id), uid))
    )
    if (nrow(kosu) == 0L ||
        !as.character(kosu$Status[1]) %in% c("Tamamlandı", "Yenilgi")) {
      return(NULL)
    }

    # Haftalık meydan okuma koşuları o haftaya özgü bir değiştiriciyle
    # (düşman hızı/kaynak/dalga yoğunluğu) oynanır; savunma planı yalnızca
    # harita/zorluk/tohum taşır ve deneme (plan) modu hiçbir değiştirici
    # uygulamaz. Böyle bir koşudan plan yayınlamak, yaratıcının
    # değiştiriciyle elde ettiği sonucu değiştiricisiz bir tekrar oynanışla
    # haksız biçimde kıyaslar; bu yüzden haftalık koşu kaynaklı yayın
    # reddedilir.
    if (identical(as.character(kosu$Mode[1]), "haftalik")) {
      return(NULL)
    }

    # DOĞRULAMA ÖNCE: idempotency kontrolü önce çalışırsa, harita/zorluk/tohum
    # üçlüsü uyuşmayan GEÇERSİZ bir yük için mevcut BlueprintID dönüyor ve
    # istemci geçersiz yükün yayınlandığını sanıyordu.
    p <- dogrulama$plan
    if (!identical(p$harita, as.character(kosu$MapID[1])) ||
        !identical(p$zorluk, as.character(kosu$Difficulty[1])) ||
        !identical(p$tohum, as.integer(kosu$Seed[1]))) {
      return(NULL)
    }

    # Aynı koşudan ikinci yayın kopya üretmez: mevcut plan kimliği döner.
    mevcut_plan_sorgusu <- paste(
      "SELECT BlueprintID FROM MB_Game_Blueprints",
      "WHERE GameRunID = ? AND UserID = ? AND IsDeleted = 0"
    )
    mevcut_plan <- DBI::dbGetQuery(
      handle$conn,
      mevcut_plan_sorgusu,
      params = normalize_db_params(list(as.integer(kosu_id), uid))
    )
    if (nrow(mevcut_plan) > 0L) {
      return(as.integer(mevcut_plan$BlueprintID[1]))
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

    # EŞZAMANLILIK: oku-sonra-yaz ikilisi atomik değildir; iki istek aynı anda
    # "plan yok" görüp iki satır ekleyebilir. Benzersizlik DB sınırında
    # (filtrelenmiş UNIQUE indeks) zorlanır; ihlal yakalanınca mevcut plan
    # yeniden okunup DÖNDÜRÜLÜR, böylece sözleşme (ikinci yayın mevcut planı
    # döndürür) eşzamanlı durumda da korunur.
    eklendi <- tryCatch(
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
      ),
      error = function(e) e
    )

    if (!inherits(eklendi, "condition")) {
      return(eklendi)
    }

    yarisan <- tryCatch(
      DBI::dbGetQuery(
        handle$conn,
        mevcut_plan_sorgusu,
        params = normalize_db_params(list(as.integer(kosu_id), uid))
      ),
      error = function(e) NULL
    )
    if (is.data.frame(yarisan) && nrow(yarisan) > 0L) {
      return(as.integer(yarisan$BlueprintID[1]))
    }
    stop(eklendi)
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
    # Sınır SQL tarafında uygulanır (doğrulanmış tamsayı; NA/geçersiz -> 30).
    limit_n <- suppressWarnings(as.integer(limit %||% 30L)[1])
    if (is.na(limit_n) || limit_n < 1L) limit_n <- 30L
    # Üst sınır (liderlik tablosuyla aynı desen): büyük bir `limit`, o kadar
    # CreatorResultJson satırını R belleğine alıp tek tek ayrıştırıyordu.
    limit_n <- min(limit_n, 200L)
    secim <- paste(
      "BlueprintID, UserID, MapID, Difficulty, Seed, Title,",
      "SchemaVersion, CreatorResultJson, CreatedAt",
      "FROM MB_Game_Blueprints WHERE IsDeleted = 0",
      "ORDER BY BlueprintID DESC"
    )
    planlar <- DBI::dbGetQuery(
      handle$conn,
      if (.bs_db_is_sqlite(handle$conn)) {
        sprintf("SELECT %s LIMIT %d", secim, limit_n)
      } else {
        sprintf("SELECT TOP (%d) %s", limit_n, secim)
      }
    )

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
