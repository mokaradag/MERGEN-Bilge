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

  invisible(isTRUE(sonuc))
}
