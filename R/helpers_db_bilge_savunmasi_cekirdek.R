# ==============================================================================
# Dosya Yolu: R/helpers_db_bilge_savunmasi_cekirdek.R
# Açıklama: Bilge Savunması kalıcılık çekirdeği: bağlantı edinme/bırakma,
#           tablo erişilebilirlik önbelleği, lehçe tespiti, JSON/kimlik
#           yardımcıları ve oyuncu profili (MB_Game_Profiles) işlemleri.
#
# Sözleşmeler:
#   * MB_Game_* ailesi MB_Chats / MB_Messages / MB_ClaudeCode_* tablolarından
#     kasıtlı olarak AYRIDIR; oyun ilerlemesi sohbet şemasına yazılmaz.
#   * Tablolar henüz kurulmamışsa (aşamalı devreye alma) tüm fonksiyonlar
#     çökmek yerine güvenli NULL/FALSE/boş sonuç döner; oyun kalıcılıksız
#     modda oynanabilir kalır.
#   * Yalnızca parametreli SQL kullanılır; tüm parametreler normalize_db_params()
#     ile bağlanır. Bu tablolara gizli değer (anahtar, token, ortam değişkeni,
#     dosya içeriği) veya görsel ikili veri YAZILMAZ.
#   * Testler gerçek SQLite bağlantısı enjekte edebilsin diye tüm fonksiyonlar
#     opsiyonel `conn` parametresi alır; üretim yolu T-SQL kalır.
#   * Tablo kurulum betiği: docs/sql/2026-07-bilge-savunmasi.sql (uygulama
#     açılışında OTOMATİK ÇALIŞTIRILMAZ; bkz. RUNBOOK.md).
# ==============================================================================

# Tablo erişilebilirlik önbelleği.
.bs_db_state <- new.env(parent = emptyenv())

.bs_db_log_warn <- function(...) {
  msg <- paste(..., collapse = " ")
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    # logger glue çözümlemesine takılmaması için süslü parantezler temizlenir.
    log_warn(gsub("[{}]", "", msg))
  } else {
    warning(msg, call. = FALSE)
  }
  invisible(NULL)
}

# Merkezi güvenli değerlendirme: hata durumunda fallback döner, uyarı loglar.
.bs_db_try <- function(expr, fallback = NULL, uyari = NULL) {
  tryCatch(expr, error = function(e) {
    if (!is.null(uyari)) {
      .bs_db_log_warn(uyari, conditionMessage(e))
    }
    fallback
  })
}

# Bağlantı edinme: conn enjekte edilmişse sahiplik çağırandadır (release
# no-op). İşlem (transaction) gerektiren yollar havuz-güvenli
# db_acquire_tx_connection() kullanır.
.bs_db_acquire <- function(conn = NULL, tx = FALSE) {
  if (!is.null(conn)) {
    return(list(conn = conn, mode = "injected", info = NULL))
  }

  if (isTRUE(tx) &&
      exists("db_acquire_tx_connection", mode = "function", inherits = TRUE)) {
    conn_info <- db_acquire_tx_connection("primary")
    return(list(conn = conn_info$conn, mode = "tx", info = conn_info))
  }

  conn_info <- get_connection()
  list(conn = conn_info$conn, mode = "plain", info = conn_info)
}

.bs_db_release <- function(handle) {
  if (is.null(handle) || identical(handle$mode, "injected")) {
    return(invisible(NULL))
  }

  if (identical(handle$mode, "tx")) {
    db_release_tx_connection(handle$info)
  } else {
    release_connection(handle$info)
  }

  invisible(NULL)
}

# SQLite lehçe tespiti: yalnızca çevrimdışı testlerde TRUE olur.
.bs_db_is_sqlite <- function(conn) {
  isTRUE(inherits(conn, "SQLiteConnection")) ||
    any(grepl("sqlite", class(conn), ignore.case = TRUE))
}

.bs_db_now_stamp <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")
}

# Kayıt zaman damgasını sunucu saatine göre saniye farkına çevirir.
.bs_db_gecen_saniye <- function(baslangic_stamp) {
  if (is.null(baslangic_stamp) || is.na(baslangic_stamp)) return(NA_real_)
  baslangic <- suppressWarnings(as.POSIXct(
    as.character(baslangic_stamp)[1],
    tz = "Europe/Istanbul"
  ))
  if (is.na(baslangic)) return(NA_real_)
  as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
}

# Liste değerini sınırlı, tek satır JSON metnine çevirir (hata halinde empty).
.bs_db_json <- function(x, empty = "{}") {
  if (is.null(x) || length(x) == 0) return(empty)
  out <- tryCatch(
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")),
    error = function(e) empty
  )
  if (!nzchar(out)) empty else out
}

# INSERT sonrası üretilen kimliği lehçeye göre okur (üretim: OUTPUT INSERTED).
.bs_db_insert_returning_id <- function(conn, insert_sql_tsql, insert_sql_plain,
                                       id_column, params) {
  if (.bs_db_is_sqlite(conn)) {
    DBI::dbExecute(conn, insert_sql_plain, params = params)
    res <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")
    return(as.integer(res$id[1]))
  }

  res <- DBI::dbGetQuery(conn, insert_sql_tsql, params = params)
  if (nrow(res) == 0L) {
    stop(sprintf("INSERT %s kimlik dondurmedi.", id_column), call. = FALSE)
  }
  as.integer(res[[1]][1])
}

# Pozitif kullanıcı kimliği; placeholder (0/NA/geçersiz) değerler NULL sayılır.
.bs_db_kullanici_id <- function(user_id) {
  uid <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  if (is.na(uid) || uid <= 0L) return(NULL)
  uid
}

#' Tablo Erişilebilirlik Önbelleğini Sıfırla
bs_db_reset_availability_cache <- function() {
  .bs_db_state$available <- NULL
  .bs_db_state$checked_at <- NULL
  invisible(NULL)
}

bs_db_required_tables <- function() {
  c(
    "MB_Game_Profiles",
    "MB_Game_CampaignProgress",
    "MB_Game_HeroProgress",
    "MB_Game_Runs",
    "MB_Game_RunCheckpoints",
    "MB_Game_Achievements",
    "MB_Game_ChallengeSeasons",
    "MB_Game_ChallengeEntries",
    "MB_Game_Blueprints",
    "MB_Game_CommunityContributions"
  )
}

#' MB_Game_* Tabloları Erişilebilir mi?
#'
#' @description Aşamalı devreye alma için yalnızca birkaç nöbetçi tabloyu değil,
#' kalıcılık akışlarının okuduğu/yazdığı tam MB_Game tablo kümesini kontrol
#' eder. TRUE kalıcı önbelleğe alınır; FALSE 60 saniye boyunca tekrar
#' sorgulanmaz.
bs_db_tables_available <- function(conn = NULL, force_refresh = FALSE) {
  cached <- .bs_db_state$available

  if (!isTRUE(force_refresh) && !is.null(cached)) {
    if (isTRUE(cached)) return(TRUE)

    checked_at <- .bs_db_state$checked_at
    if (!is.null(checked_at) &&
        as.numeric(difftime(Sys.time(), checked_at, units = "secs")) < 60) {
      return(FALSE)
    }
  }

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Savunması tabloları için DB bağlantısı alınamadı:"
  )

  ok <- FALSE

  if (!is.null(handle)) {
    on.exit(.bs_db_release(handle), add = TRUE)

    ok <- .bs_db_try(
      all(vapply(
        bs_db_required_tables(),
        function(tablo) isTRUE(DBI::dbExistsTable(handle$conn, tablo)),
        logical(1)
      )),
      fallback = FALSE,
      uyari = "Bilge Savunması tabloları kontrol edilemedi:"
    )
  }

  .bs_db_state$available <- isTRUE(ok)
  .bs_db_state$checked_at <- Sys.time()

  isTRUE(ok)
}

#' Oyuncu Profilini Getir veya Oluştur
#'
#' @description Kullanıcının oyun profil satırını döndürür; yoksa varsayılan
#' değerlerle oluşturur. Başarısızlıkta NULL döner (oyun kalıcılıksız devam
#' eder).
#' @return Liste: profil_id, seviye, xp, toplam_puan, ayarlar (liste).
bs_db_get_or_create_profile <- function(user_id, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Oyun profili için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    mevcut <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT GameProfileID, PlayerLevel, TotalXP, TotalScore, SettingsJson",
        "FROM MB_Game_Profiles WHERE UserID = ?"
      ),
      params = normalize_db_params(list(uid))
    )

    if (nrow(mevcut) == 0L) {
      # SELECT-INSERT yarışı: eşzamanlı ilk açılışta INSERT tekil kısıtına
      # takılırsa satır yeniden okunur; profil ikilenmez.
      profil_id <- tryCatch(
        .bs_db_insert_returning_id(
          conn = handle$conn,
          insert_sql_tsql = paste(
            "INSERT INTO MB_Game_Profiles",
            "(UserID, PlayerLevel, TotalXP, TotalScore, SettingsJson, CreatedAt, UpdatedAt)",
            "OUTPUT INSERTED.GameProfileID AS id",
            "VALUES (?, 1, 0, 0, ?, ?, ?)"
          ),
          insert_sql_plain = paste(
            "INSERT INTO MB_Game_Profiles",
            "(UserID, PlayerLevel, TotalXP, TotalScore, SettingsJson, CreatedAt, UpdatedAt)",
            "VALUES (?, 1, 0, 0, ?, ?, ?)"
          ),
          id_column = "GameProfileID",
          params = normalize_db_params(list(
            uid, "{}", .bs_db_now_stamp(), .bs_db_now_stamp()
          ))
        ),
        error = function(e) NULL
      )
      if (!is.null(profil_id)) {
        return(list(
          profil_id = profil_id, seviye = 1L, xp = 0L,
          toplam_puan = 0L, ayarlar = list()
        ))
      }
      mevcut <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT GameProfileID, PlayerLevel, TotalXP, TotalScore, SettingsJson",
          "FROM MB_Game_Profiles WHERE UserID = ?"
        ),
        params = normalize_db_params(list(uid))
      )
      if (nrow(mevcut) == 0L) {
        stop("Oyun profili oluşturulamadı ve yeniden okunamadı.", call. = FALSE)
      }
    }

    ayarlar <- tryCatch(
      jsonlite::fromJSON(mevcut$SettingsJson[1] %||% "{}", simplifyVector = FALSE),
      error = function(e) list()
    )
    if (!is.list(ayarlar)) ayarlar <- list()

    list(
      profil_id = as.integer(mevcut$GameProfileID[1]),
      seviye = as.integer(mevcut$PlayerLevel[1]),
      xp = as.integer(mevcut$TotalXP[1]),
      toplam_puan = as.numeric(mevcut$TotalScore[1]),
      ayarlar = ayarlar
    )
  },
  fallback = NULL,
  uyari = "Oyun profili getirilemedi/oluşturulamadı:")
}

#' Oyuncu Oyun Ayarlarını Kaydet
#'
#' @description Ses/kalite gibi kalıcı oyun ayarlarını profil satırına yazar.
#' Ayarlar sınırlı JSON'dur; gizli değer taşımaz.
bs_db_update_settings <- function(user_id, ayarlar, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(FALSE)

  ayar_json <- .bs_db_json(ayarlar, empty = "{}")
  if (nchar(ayar_json, type = "bytes") > 4000L) return(FALSE)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Oyun ayarları için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(FALSE)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    guncellenen <- DBI::dbExecute(
      handle$conn,
      "UPDATE MB_Game_Profiles SET SettingsJson = ?, UpdatedAt = ? WHERE UserID = ?",
      params = normalize_db_params(list(ayar_json, .bs_db_now_stamp(), uid))
    )
    guncellenen > 0L
  },
  fallback = FALSE,
  uyari = "Oyun ayarları kaydedilemedi:")
}

#' Oyuncu Durum Paketini Yükle
#'
#' @description İstemci başlangıcı için tek seferde profil + kampanya
#' ilerlemesi + kahraman ilerlemesi + başarımları döndürür. Profil yoksa
#' oluşturulur. Başarısızlıkta NULL döner.
bs_db_load_profile_bundle <- function(user_id, conn = NULL) {
  uid <- .bs_db_kullanici_id(user_id)
  if (is.null(uid)) return(NULL)

  profil <- bs_db_get_or_create_profile(uid, conn = conn)
  if (is.null(profil)) return(NULL)

  handle <- .bs_db_try(
    .bs_db_acquire(conn),
    fallback = NULL,
    uyari = "Oyun durumu için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) return(NULL)
  on.exit(.bs_db_release(handle), add = TRUE)

  .bs_db_try({
    kampanya <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT MapID, Difficulty, Stars, BestScore, HighestWave,",
        "CompletedCount, LastPlayedAt",
        "FROM MB_Game_CampaignProgress WHERE UserID = ?"
      ),
      params = normalize_db_params(list(uid))
    )

    kahramanlar <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT HeroID, UsesCount, MasteryXP",
        "FROM MB_Game_HeroProgress WHERE UserID = ?"
      ),
      params = normalize_db_params(list(uid))
    )

    basarimlar <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT ItemID, ItemType, EarnedAt",
        "FROM MB_Game_Achievements WHERE UserID = ?"
      ),
      params = normalize_db_params(list(uid))
    )

    list(
      profil = profil,
      kampanya = kampanya,
      kahramanlar = kahramanlar,
      basarimlar = basarimlar
    )
  },
  fallback = NULL,
  uyari = "Oyun durum paketi yüklenemedi:")
}
