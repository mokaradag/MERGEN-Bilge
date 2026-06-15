# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_user_data.R
# Açıklama: AI Uzman (AI Expert) için worker-safe veritabanı okuma yardımcıları.
#            MB_Users / MB_Messages üzerinden kullanıcının adını, birim bilgisini,
#            son mesajlarını ve son giriş tarihini okur. Bu yardımcılar
#            R/helpers_ai_expert.R içinden ayrılmıştır; her biri kendi DB
#            bağlantısını açıp kapatır (reaktif bağımlılık taşımaz) ve kullanıcıya
#            görünen alanları kanonik görünür-değer normalizasyonundan geçirir.
#            Çağıranlar: build_ai_expert_user_context() ve
#            R/server_ai_expert_handlers.R.
# ==============================================================================

# --- Kullanıcının tam adını DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
# MB_Users tablosundaki KaynakAdi sütunundan kullanıcı adını alır.
#
# @param user_id Kullanıcı ID
# @return Karakter dizisi (tam ad) veya boş karakter
fetch_user_full_name <- function(user_id) {
  conn_info <- tryCatch(get_connection(), error = function(e) NULL)
  if (is.null(conn_info)) return("")
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT KaynakAdi FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] KaynakAdi sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0 && !is.na(result$KaynakAdi[1])) {
    ad_soyad <- safe_trimws(as.character(result$KaynakAdi[1]))

    # Okuma sınırı: kanonik profil okuyucusuyla (helpers_database.R) aynı
    # görünür-değer normalizasyonu uygulanır; eski mojibake adlar TTS/altyazı
    # metnine onarılmadan sızmasın.
    if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
      ad_soyad <- normalize_db_read_visible_value(ad_soyad, repair_mojibake = TRUE)
    }

    if (safe_nzchar(ad_soyad)) {
      return(ad_soyad)
    }
  }

  return("")
}

# --- Kullanıcının birim bilgisini DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
# MB_Users tablosundaki Departman ve Mudurluk sütunlarını okur.
# Departman boşsa Mudurluk değerini bağlam birimi olarak kullanır.
#
# @param user_id Kullanıcı ID
# @return Liste: department, mudurluk, effective_unit, display_text
fetch_user_work_context <- function(user_id) {
  conn_info <- tryCatch(get_connection(), error = function(e) NULL)
  if (is.null(conn_info)) {
    return(list(
      department = "",
      mudurluk = "",
      effective_unit = "",
      display_text = ""
    ))
  }

  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT Departman, Mudurluk FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] Departman/Mudurluk sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) == 0) {
    return(list(
      department = "",
      mudurluk = "",
      effective_unit = "",
      display_text = ""
    ))
  }

  department <- ""
  mudurluk <- ""

  # Okuma sınırı: kullanıcıya görünen birim adları, kanonik profil
  # okuyucusuyla aynı görünür-değer normalizasyonundan geçer.
  .aix_read_visible <- function(x) {
    if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
      normalize_db_read_visible_value(x, repair_mojibake = TRUE)
    } else {
      x
    }
  }

  if ("Departman" %in% names(result) && !is.na(result$Departman[1])) {
    department <- .aix_read_visible(safe_trimws(as.character(result$Departman[1])))
  }

  if ("Mudurluk" %in% names(result) && !is.na(result$Mudurluk[1])) {
    mudurluk <- .aix_read_visible(safe_trimws(as.character(result$Mudurluk[1])))
  }

  effective_unit <- if (safe_nzchar(department)) department else mudurluk

  display_text <- ""
  if (safe_nzchar(department) && safe_nzchar(mudurluk)) {
    display_text <- sprintf("%s (%s)", department, mudurluk)
  } else if (safe_nzchar(effective_unit)) {
    display_text <- effective_unit
  }

  list(
    department = department,
    mudurluk = mudurluk,
    effective_unit = effective_unit,
    display_text = display_text
  )
}

# --- Son kullanıcı mesajlarını DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
#
# @param user_id Kullanıcı ID
# @param max_prompts Maksimum mesaj sayısı
# @return Karakter vektörü (mesaj içerikler) veya NULL
fetch_recent_user_prompts <- function(user_id, max_prompts = 5) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- sprintf("
    SELECT TOP %d m.MessageContent
    FROM MB_Messages m
    JOIN MB_Chats c ON m.ChatID = c.ChatID
    WHERE c.UserID = ? AND m.MessageType = 'user' AND c.IsDeleted = 0
    ORDER BY m.MessageTimestamp DESC
  ", as.integer(max_prompts))

  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] DB sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0) {
    return(normalize_utf8_text(as.character(result$MessageContent)))
  }

  return(NULL)
}

# --- Son giriş tarihini DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
#
# @param user_id Kullanıcı ID
# @return POSIXct tarih veya NULL
fetch_user_last_login <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT LastLoginDate FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] LastLoginDate sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0 && !is.na(result$LastLoginDate[1])) {
    return(as.POSIXct(result$LastLoginDate[1]))
  }

  return(NULL)
}
