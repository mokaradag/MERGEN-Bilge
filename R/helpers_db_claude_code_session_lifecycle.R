# ==============================================================================
# Dosya Yolu: R/helpers_db_claude_code_session_lifecycle.R
# Açıklama: Bilge Yolaç kalıcı oturumlarının arşiv-geri yükleme ve KALICI silme
#           yaşam döngüsü DB işlemleri. Orkestrasyon dosyasının
#           (R/helpers_db_claude_code_sessions.R) maintainability ratchet
#           bütçesi altında kalması için buraya ayrılmıştır ve ondan SONRA
#           yüklenir (kaynak manifest sözleşmesi): paylaşılan iç yardımcılar
#           (.cc_db_try, .cc_db_sessions_acquire/_release, normalize_db_params)
#           o dosyada tanımlıdır.
#
# Sözleşmeler:
#   * Tüm işlemler kullanıcı-izoledir (UserID = ?). Bir kullanıcı başka bir
#     kullanıcının oturumunu geri yükleyemez veya silemez.
#   * Arşivleme (cc_db_soft_delete_session, IsDeleted = 1) orkestrasyon
#     dosyasındadır; geri yükleme (IsDeleted = 0) onunla simetriktir.
#   * KALICI silme geri alınamaz fiziksel silmedir ve yalnızca Oturumlar
#     sayfasındaki açık kullanıcı eylemiyle (ikinci onay adımıyla) tetiklenir.
# ==============================================================================

# Bir oturumun çalıştırmalarının ürettiği indirilebilir dosya yollarını
# (GeneratedDownloadsJson içindeki download_path) toplar. KALICI silmede,
# run satırları silinmeden ÖNCE çağrılır. Hata durumunda boş vektör döner.
.cc_lifecycle_collect_download_paths <- function(conn, session_record_id) {
  satirlar <- .cc_db_try(
    DBI::dbGetQuery(
      conn,
      "SELECT GeneratedDownloadsJson FROM MB_ClaudeCode_Runs
       WHERE ClaudeSessionRecordID = ?
         AND GeneratedDownloadsJson IS NOT NULL
         AND GeneratedDownloadsJson <> '' AND GeneratedDownloadsJson <> '[]'",
      params = normalize_db_params(list(session_record_id))
    ),
    fallback = NULL
  )

  if (is.null(satirlar) || !nrow(satirlar)) {
    return(character(0))
  }

  yollar <- character(0)
  for (json_metin in satirlar$GeneratedDownloadsJson) {
    liste <- .cc_db_try(
      jsonlite::fromJSON(as.character(json_metin)[1], simplifyVector = FALSE)
    )
    if (is.null(liste) || !length(liste)) next
    for (dosya in liste) {
      yol <- .cc_db_try(as.character(dosya$download_path %||% "")[1], fallback = "")
      if (length(yol) == 1L && !is.na(yol) && nzchar(yol)) {
        yollar <- c(yollar, yol)
      }
    }
  }

  unique(yollar)
}

# Toplanan üretilen-dosya yollarını en iyi çaba ile kaldırır. Yalnızca
# indirme kökü (get_claude_code_download_root) ALTINDAKİ gerçek dosyalar
# silinir; kök dışı / var olmayan / dizin olan yollar yok sayılır. İndirme
# kökü veya kök-içi kontrol yardımcıları yüklü değilse (izole test/worker)
# güvenle no-op'tur ve asla hata fırlatmaz. @return silinen dosya sayısı.
.cc_lifecycle_remove_download_files <- function(paths) {
  if (is.null(paths) || !length(paths)) {
    return(invisible(0L))
  }

  if (!exists("get_claude_code_download_root", mode = "function", inherits = TRUE) ||
      !exists("cc_policy_path_inside_roots", mode = "function", inherits = TRUE)) {
    return(invisible(0L))
  }

  kok <- .cc_db_try(get_claude_code_download_root(), fallback = "")
  if (!is.character(kok) || length(kok) != 1L || !nzchar(kok)) {
    return(invisible(0L))
  }

  silinen <- 0L
  for (yol in paths) {
    kaldirilabilir <- .cc_db_try({
      is.character(yol) && length(yol) == 1L && !is.na(yol) && nzchar(yol) &&
        file.exists(yol) && !dir.exists(yol) &&
        isTRUE(cc_policy_path_inside_roots(yol, kok, must_exist = TRUE))
    }, fallback = FALSE)

    if (isTRUE(kaldirilabilir)) {
      basari <- .cc_db_try(
        isTRUE(suppressWarnings(unlink(yol)) == 0L),
        fallback = FALSE
      )
      if (isTRUE(basari)) silinen <- silinen + 1L
    }
  }

  invisible(silinen)
}

#' Arşivlenmiş (yumuşak silinmiş) oturumu geri yükler (kullanıcı-izole).
#'
#' IsDeleted = 0 yaparak oturumu normal listeye geri döndürür. Fiziksel veri
#' değişmez; yalnızca arşiv bayrağı kaldırılır. Arşivleme ile simetriktir.
cc_db_restore_session <- function(user_id, session_record_id, conn = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])

  if (is.na(user_id) || user_id <= 0L ||
      is.na(session_record_id) || session_record_id <= 0L) {
    return(invisible(FALSE))
  }

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum geri yükleme için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  sonuc <- .cc_db_try({
    etkilenen <- DBI::dbExecute(
      handle$conn,
      "UPDATE MB_ClaudeCode_Sessions
       SET IsDeleted = 0
       WHERE ClaudeSessionRecordID = ? AND UserID = ?",
      params = normalize_db_params(list(session_record_id, user_id))
    )

    isTRUE(etkilenen > 0L)
  },
  fallback = FALSE,
  uyari = "Bilge Yolaç oturumu geri yüklenemedi:")

  invisible(isTRUE(sonuc))
}

#' Oturumu ve çalıştırmalarını KALICI olarak siler (kullanıcı-izole; onaylı).
#'
#' Bu yumuşak silmenin AKSİNE geri alınamaz fiziksel silmedir ve yalnızca
#' Oturumlar sayfasındaki açık kullanıcı eylemiyle (ikinci onay adımıyla)
#' tetiklenir. Silme tek işlemde yapılır: önce sahiplik doğrulanır, sonra
#' alt çalıştırma kayıtları, en son oturum satırı silinir. Sahiplik
#' doğrulanamazsa hiçbir satır silinmez (kullanıcı izolasyonu).
cc_db_hard_delete_session <- function(user_id, session_record_id, conn = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])

  if (is.na(user_id) || user_id <= 0L ||
      is.na(session_record_id) || session_record_id <= 0L) {
    return(invisible(FALSE))
  }

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn, tx = TRUE),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum kalıcı silme için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(invisible(FALSE))
  }

  tx_conn <- handle$conn
  tx_begun <- FALSE
  tx_committed <- FALSE
  # Silinecek çalıştırmaların ürettiği indirilebilir dosya yolları; satırlar
  # silinmeden ÖNCE (metadata hâlâ okunabilirken) toplanır, DB commit'ten
  # SONRA en iyi çaba ile kaldırılır (aşağıda).
  silinecek_dosyalar <- character(0)

  # after = FALSE: rollback bağlantı iadesinden ÖNCE çalışır (havuz sözleşmesi).
  on.exit(.cc_db_sessions_release(handle), add = TRUE)
  on.exit({
    if (isTRUE(tx_begun) && !isTRUE(tx_committed)) {
      try(DBI::dbRollback(tx_conn), silent = TRUE)
    }
  }, add = TRUE, after = FALSE)

  sonuc <- .cc_db_try({
    DBI::dbBegin(tx_conn)
    tx_begun <- TRUE

    # Kullanıcı izolasyonu: kayıt bu kullanıcıya ait değilse hiçbir şey silme.
    sahiplik <- DBI::dbGetQuery(
      tx_conn,
      "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Sessions
       WHERE ClaudeSessionRecordID = ? AND UserID = ?",
      params = normalize_db_params(list(session_record_id, user_id))
    )
    sahip_var <- as.integer(sahiplik$n[1] %||% 0L) > 0L

    if (!isTRUE(sahip_var)) {
      DBI::dbRollback(tx_conn)
      tx_begun <- FALSE
      FALSE
    } else {
      # Üretilen dosya yollarını, run metadata'sı silinmeden önce topla.
      silinecek_dosyalar <- .cc_lifecycle_collect_download_paths(
        tx_conn, session_record_id
      )

      # Alt kayıtlar önce (FK cascade olmayabilir). session_record_id ile
      # kapsanır; sahiplik yukarıda aynı işlemde doğrulandı.
      DBI::dbExecute(
        tx_conn,
        "DELETE FROM MB_ClaudeCode_Runs WHERE ClaudeSessionRecordID = ?",
        params = normalize_db_params(list(session_record_id))
      )

      etkilenen <- DBI::dbExecute(
        tx_conn,
        "DELETE FROM MB_ClaudeCode_Sessions
         WHERE ClaudeSessionRecordID = ? AND UserID = ?",
        params = normalize_db_params(list(session_record_id, user_id))
      )

      DBI::dbCommit(tx_conn)
      tx_committed <- TRUE

      isTRUE(etkilenen > 0L)
    }
  },
  fallback = FALSE,
  uyari = "Bilge Yolaç oturumu kalıcı silinemedi:")

  # İşlem başarıyla commit edildiyse metadata artık DB'de yok. "Kalıcı Sil"
  # kullanıcının artefaktlarını da kaldırmalıdır: aksi halde bilge_yolac_downloads
  # kaynak yolu altındaki üretilen dosyalar, daha önce açılmış/kopyalanmış
  # indirme URL'leriyle sunulmaya devam edebilir (Codex P2 veri saklama sızıntısı).
  # Kaldırma yalnızca commit sonrası ve yalnızca indirme kökü altındaki gerçek
  # dosyalar için yapılır; en iyi çabadır ve asla hata fırlatmaz.
  if (isTRUE(sonuc)) {
    .cc_lifecycle_remove_download_files(silinecek_dosyalar)
  }

  invisible(isTRUE(sonuc))
}
