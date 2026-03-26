# R/helpers_database.R
# Complete, corrected helpers for DB access and worker-safe operations.
# - Never serialize pool/DBI external pointers into workers.
# - Worker functions create their own DB connections (no 'pool' needed).
# - These functions DO NOT access Shiny reactives; always pass plain R values
#   (e.g. chat_id, user_id, prompt_text) into futures/workers. Capture reactives
#   in the main Shiny reactive context BEFORE starting background work.
#
# Usage:
# 1) In main process: source("helpers_database.R"); call init_db_pool(dsn) if you want a pool.
# 2) In server code: capture reactive values (e.g. chat_id <- isolate(rv$current_chat_id)) and
#    pass those primitives into futures.
# 3) In workers (future blocks) call worker_save_assistant_response(...) which will create
#    a fresh DB connection inside the worker.
#
# NOTE: This file assumes a SQL Server-like OUTPUT ... INSERTED.MessageID behavior.
#       If your DB differs, adjust the INSERT returning syntax accordingly.

library(DBI)
library(odbc)
library(pool)

# --- Configuration ---
.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")
.DEFAULT_DB_CLIENT_ENCODING <- getOption("mergen.db.client_encoding", "UTF-8")
.DEFAULT_DB_NAME_ENCODING <- getOption("mergen.db.name_encoding", .DEFAULT_DB_CLIENT_ENCODING)

normalize_db_value <- function(x) {
  if (is.null(x) || is.na(x) || !is.character(x)) {
    return(x)
  }

  # DB parametresini çalışma ortamının yerel kodlamasına çevir:
  # - UTF-8 oturumda UTF-8 gönder
  # - UTF-8 olmayan Windows oturumunda native (örn. CP1254) gönder
  out_utf8 <- tryCatch(enc2utf8(x), error = function(e) x)
  if (isTRUE(l10n_info()[["UTF-8"]])) {
    return(out_utf8)
  }
  tryCatch(enc2native(out_utf8), error = function(e) out_utf8)
}

normalize_db_params <- function(params) {
  lapply(params, normalize_db_value)
}

# Get pool statistics
get_pool_info <- function() {
  return(list(
    valid = TRUE,
    mode = "Direct Connections",
    note = "Doğrudan bağlantı modu kullanılıyor (havuz devre dışı)"
  ))
}

get_connection <- function(target = "primary") {
  
  # 1. Hangi Veritabanı? (.Renviron içindeki değişkeni seçiyoruz)
  dsn_var <- switch(target,
    "primary"   = "DB_DSN",      # Varsayılan Ana Veritabanı
    "secondary" = "DB_DSN_2",    # İkincil Veritabanı (Arşiv vb.)
    "tertiary"  = "DB_DSN_3",    # Üçüncül Veritabanı
    "DB_DSN"                     # Hata durumunda varsayılan
  )
  
  # 2. Pooling Kontrolü (Sadece Ana Veritabanı için ve pool aktifse)
  # Şu an kullanmıyor, ama performans için kapıyı açık bırakıldı.
  if (target == "primary" && exists("pool", envir = .GlobalEnv)) {
    pool_obj <- get("pool", envir = .GlobalEnv)
    if (!is.null(pool_obj) && inherits(pool_obj, "Pool")) {
      return(list(conn = pool_obj, pooled = TRUE, pool = pool_obj))
    }
  }

  # 3. Direct Connection (Fallback)
  # Havuz yoksa veya ikincil veritabanı isteniyorsa doğrudan bağlan.
  if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop("Worker/process requires 'odbc' and 'DBI' packages installed.")
  }
  
  # Seçilen hedefin DSN adını çevresel değişkenden al
  dsn_name <- Sys.getenv(dsn_var, .DEFAULT_DSN)
  
  # Eğer DSN tanımlı değilse hata ver (Debugging kolaylığı için)
  if (dsn_name == "") {
    stop(sprintf("HATA: '%s' için .Renviron içinde DSN tanımı bulunamadı (Target: %s)", dsn_var, target))
  }
  
  conn <- DBI::dbConnect(
    odbc::odbc(),
    dsn = dsn_name,
    encoding = .DEFAULT_DB_CLIENT_ENCODING,
    name_encoding = .DEFAULT_DB_NAME_ENCODING
  )
  return(list(conn = conn, pooled = FALSE, pool = NULL))
}

# Release connection - only disconnect if it's NOT a pool
release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))
  
  # If it's a pool, do nothing - pool manages its own connections
  if (isTRUE(conn_info$pooled)) {
    return(invisible(NULL))
  }
  
  # Only disconnect direct connections (non-pooled)
  tryCatch({
    DBI::dbDisconnect(conn_info$conn)
  }, error = function(e) {
    # ignore
  })
  
  invisible(NULL)
}

# Worker-side helper: create a fresh DBI connection in the worker with retry logic
worker_db_connect <- function(max_retries = 3, retry_delay = 1) {
  for (i in 1:max_retries) {
    tryCatch({
      if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
        stop("Worker needs 'odbc' and 'DBI' packages installed.")
      }
      conn <- DBI::dbConnect(
        odbc::odbc(),
        dsn = Sys.getenv("DB_DSN", .DEFAULT_DSN),
        encoding = .DEFAULT_DB_CLIENT_ENCODING,
        name_encoding = .DEFAULT_DB_NAME_ENCODING
      )
      return(conn)
    }, error = function(e) {
      if (i == max_retries) {
        stop(paste("Failed to connect to database after", max_retries, "attempts:", e$message))
      }
      Sys.sleep(retry_delay * i)  # Exponential backoff
    })
  }
}

# -------------------------
# Input Validation Helper (NEW - Suggestion #2)
# -------------------------
validate_username <- function(username) {
  # Only allow alphanumeric, underscore, dot, and hyphen
  if (!grepl("^[a-zA-Z0-9_.-]+$", username)) {
    stop("Geçersiz kullanıcı adı formatı. Sadece harf, rakam, alt çizgi, nokta ve tire kullanılabilir.")
  }
  
  # Check length constraints
  if (nchar(username) < 3 || nchar(username) > 50) {
    stop("Kullanıcı adı 3-50 karakter arasında olmalıdır.")
  }
  
  return(TRUE)
}

validate_chat_title <- function(title) {
  # Length constraint
  if (nchar(title) > 200) {
    stop("Chat title must be less than 200 characters.")
  }
  
  if (nchar(title) < 1) {
    stop("Chat title cannot be empty.")
  }
  
  # Block potential SQL injection patterns (defense in depth)
  # Even with parameterized queries, we reject suspicious patterns
  dangerous_patterns <- c(
    "';",           # SQL statement terminator
    "--",           # SQL comment
    "/\\*", "\\*/", # SQL block comment
    "xp_", "sp_",   # SQL Server extended/stored procedures
    "\\bEXEC\\b", "\\bEXECUTE\\b",
    "\\bSELECT\\b.*\\bFROM\\b",
    "\\bINSERT\\b.*\\bINTO\\b",
    "\\bUPDATE\\b.*\\bSET\\b",
    "\\bDELETE\\b.*\\bFROM\\b",
    "\\bDROP\\b.*\\bTABLE\\b",
    "\\bCREATE\\b.*\\bTABLE\\b",
    "\\bALTER\\b.*\\bTABLE\\b",
    "\\bUNION\\b.*\\bSELECT\\b"
  )
  
  for (pattern in dangerous_patterns) {
    if (grepl(pattern, title, ignore.case = TRUE)) {
      stop("Chat title contains invalid SQL patterns.")
    }
  }
  
  return(TRUE)
}

validate_message_content <- function(content) {
  # Length constraint (adjusted to 20000)
  if (nchar(content) > 20000) {
    stop("Message content exceeds maximum length of 20,000 characters.")
  }
  
  if (nchar(content) < 1) {
    stop("Message content cannot be empty.")
  }
  
  return(TRUE)
}

# -------------------------
# Database operation helpers
# -------------------------

# Kullanıcı al veya oluştur; tam sayı UserID döndürür
# sso_claims: SSO aktifken Keycloak'tan gelen ek bilgiler (opsiyonel)
get_or_create_user <- function(username, sso_claims = NULL) {
  stopifnot(is.character(username) && length(username) == 1)

  # Girdi doğrulama
  validate_username(username)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # KaynakAdi'nı belirle: önce SSO claim, sonra DC01_user_base, en son username
  kaynak_adi <- username
  if (!is.null(sso_claims$full_name) && nzchar(sso_claims$full_name)) {
    kaynak_adi <- sso_claims$full_name
  } else {
    user_details_query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    user_details <- dbGetQuery(conn, user_details_query, params = normalize_db_params(list(username)))
    if (nrow(user_details) > 0 && nzchar(user_details$KaynakAdi[1] %||% "")) {
      kaynak_adi <- user_details$KaynakAdi[1]
    }
  }

  user_id_query <- "SELECT UserID FROM MB_Users WHERE KullaniciAdi = ?"
  user_id_result <- dbGetQuery(conn, user_id_query, params = normalize_db_params(list(username)))

  if (nrow(user_id_result) > 0) {
    user_id <- as.integer(user_id_result$UserID[1])
    update_query <- "UPDATE MB_Users SET KaynakAdi = ?, LastLoginDate = GETDATE() WHERE UserID = ?"
    dbExecute(conn, update_query, params = normalize_db_params(list(kaynak_adi, user_id)))

    # SSO ek alanlarını güncelle (tablo destekliyorsa)
    if (!is.null(sso_claims)) {
      update_sso_fields(conn, user_id, sso_claims)
    }

    return(user_id)
  } else {
    insert_query <- "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate) OUTPUT INSERTED.UserID AS UserID VALUES (?, ?, GETDATE())"
    res <- dbGetQuery(conn, insert_query, params = normalize_db_params(list(username, kaynak_adi)))
    if (nrow(res) == 0) stop("Yeni kullanıcı oluşturulduktan sonra UserID alınamadı.")
    user_id <- as.integer(res$UserID[1])

    # SSO ek alanlarını kaydet
    if (!is.null(sso_claims)) {
      update_sso_fields(conn, user_id, sso_claims)
    }

    return(user_id)
  }
}

# SSO ek alanlarını MB_Users tablosunda güncelle
# Tablo bu sütunlara sahip değilse sessizce atla
update_sso_fields <- function(conn, user_id, sso_claims) {
  tryCatch({
    # Tabloda SSO sütunlarının varlığını kontrol et
    cols_query <- "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'MB_Users' AND COLUMN_NAME IN ('Sicil', 'Email', 'Sektor', 'Departman', 'Mudurluk', 'MasrafYeriKodu', 'SonGirisKaynagi')"
    existing_cols <- dbGetQuery(conn, cols_query)$COLUMN_NAME

    if (length(existing_cols) == 0) {
      # SSO sütunları henüz eklenmemiş - sessizce atla
      return(invisible(NULL))
    }

    # Mevcut sütunlara göre dinamik UPDATE oluştur
    set_parts <- c()
    params <- list()

    if ("Sicil" %in% existing_cols && !is.null(sso_claims$sicil)) {
      set_parts <- c(set_parts, "Sicil = ?")
      params <- c(params, list(sso_claims$sicil))
    }
    if ("Email" %in% existing_cols && !is.null(sso_claims$email)) {
      set_parts <- c(set_parts, "Email = ?")
      params <- c(params, list(sso_claims$email))
    }
    if ("Sektor" %in% existing_cols && !is.null(sso_claims$sektor)) {
      set_parts <- c(set_parts, "Sektor = ?")
      params <- c(params, list(sso_claims$sektor))
    }
    if ("Departman" %in% existing_cols && !is.null(sso_claims$department)) {
      set_parts <- c(set_parts, "Departman = ?")
      params <- c(params, list(sso_claims$department))
    }
    if ("Mudurluk" %in% existing_cols && !is.null(sso_claims$mudurluk)) {
      set_parts <- c(set_parts, "Mudurluk = ?")
      params <- c(params, list(sso_claims$mudurluk))
    }
    if ("MasrafYeriKodu" %in% existing_cols && !is.null(sso_claims$masraf_yeri_kodu)) {
      set_parts <- c(set_parts, "MasrafYeriKodu = ?")
      params <- c(params, list(sso_claims$masraf_yeri_kodu))
    }
    if ("SonGirisKaynagi" %in% existing_cols) {
      set_parts <- c(set_parts, "SonGirisKaynagi = ?")
      params <- c(params, list("keycloak"))
    }

    if (length(set_parts) > 0) {
      query <- paste0("UPDATE MB_Users SET ", paste(set_parts, collapse = ", "), " WHERE UserID = ?")
      params <- c(params, list(user_id))
      dbExecute(conn, query, params = normalize_db_params(params))
    }
  }, error = function(e) {
    # SSO alanları güncellenemedi - kritik değil, sessizce devam et
    log_warn("SSO alanları güncellenemedi (UserID={user_id}): {e$message}")
  })
  invisible(NULL)
}

# Load chats and their messages for a user (returns list)
# process_message_content() fallback is provided if missing.
load_chats_preview_from_db <- function(user_id, limit = 30L) {
  stopifnot(!is.null(user_id))

  safe_limit <- suppressWarnings(as.integer(limit))
  if (is.na(safe_limit) || safe_limit <= 0) {
    safe_limit <- 30L
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- sprintf("
      SELECT TOP %d c.ChatID, c.ChatTitle, c.CreateTimestamp
      FROM MB_Chats c
      WHERE c.UserID = ? AND c.IsDeleted = 0
      ORDER BY c.CreateTimestamp DESC
    ", safe_limit)

  preview_data <- dbGetQuery(conn, query, params = list(user_id))
  if (nrow(preview_data) == 0) return(list())

  chat_ids <- as.character(preview_data$ChatID)
  formatted <- lapply(seq_len(nrow(preview_data)), function(i) {
    row <- preview_data[i, ]
    list(
      title = row$ChatTitle,
      messages = NULL,
      timestamp = row$CreateTimestamp,
      last_message_timestamp = row$CreateTimestamp,
      message_count = 0L
    )
  })
  names(formatted) <- chat_ids
  formatted[chat_ids]
}

load_chats_from_db <- function(user_id, include_messages = TRUE) {
  stopifnot(!is.null(user_id))
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))
  
  if (!isTRUE(include_messages)) {
    query <- "
      SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,
             COUNT(m.MessageID) AS MessageCount,
             MAX(m.MessageTimestamp) AS LastMessageTimestamp
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.UserID = ? AND c.IsDeleted = 0
      GROUP BY c.ChatID, c.ChatTitle, c.CreateTimestamp
      ORDER BY c.CreateTimestamp DESC
    "
    summary_data <- dbGetQuery(conn, query, params = list(user_id))
    if (nrow(summary_data) == 0) return(list())

    # Preserve the CreateTimestamp DESC order from the SQL query
    unique_chat_ids <- as.character(summary_data$ChatID)

    formatted <- lapply(seq_len(nrow(summary_data)), function(i) {
      row <- summary_data[i, ]
      msg_count <- ifelse(is.na(row$MessageCount), 0L, row$MessageCount)
      list(
        title = row$ChatTitle,
        messages = NULL,
        timestamp = row$CreateTimestamp,
        last_message_timestamp = row$LastMessageTimestamp,
        message_count = as.integer(msg_count)
      )
    })
    names(formatted) <- unique_chat_ids

    # Ensure the list is in the correct order matching the SQL query
    formatted <- formatted[unique_chat_ids]
    return(formatted)
  }

  query <- "
    SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,
           m.MessageID, m.MessageContent, m.MessageType, m.MessageTimestamp, m.MessageOrder
    FROM MB_Chats c
    JOIN MB_Messages m ON c.ChatID = m.ChatID
    WHERE c.UserID = ? AND c.IsDeleted = 0
    ORDER BY c.CreateTimestamp DESC, m.MessageOrder ASC
  "
  all_data <- dbGetQuery(conn, query, params = list(user_id))
  if (nrow(all_data) == 0) return(list())

  # Preserve the CreateTimestamp DESC order from the SQL query
  unique_chat_ids <- unique(all_data$ChatID)
  
  chat_list <- split(all_data, all_data$ChatID)

  formatted_chats <- lapply(chat_list, function(chat_df) {
    messages <- format_chat_messages(chat_df)
    
    # Son mesaj zamanını hesapla
    last_msg_time <- if (nrow(chat_df) > 0 && "MessageTimestamp" %in% names(chat_df)) {
      max(chat_df$MessageTimestamp, na.rm = TRUE)
    } else {
      chat_df$CreateTimestamp[1]
    }
    
    list(
      title = chat_df$ChatTitle[1],
      messages = messages,
      timestamp = chat_df$CreateTimestamp[1],
      last_message_timestamp = last_msg_time,
      message_count = length(messages)
    )
  })
  
  # Reorder the list to match the original CreateTimestamp DESC order
  formatted_chats <- formatted_chats[as.character(unique_chat_ids)]
  return(formatted_chats)
}

format_chat_messages <- function(chat_df) {
  
  # Yardımcı fonksiyon: Görseli base64'e çevir (inline - dış bağımlılık yok)
  inline_get_image_base64 <- function(file_path) {
    if (!file.exists(file_path)) return(NULL)
    tryCatch({
      raw_data <- readBin(file_path, "raw", file.info(file_path)$size)
      base64_str <- base64enc::base64encode(raw_data)
      paste0("data:image/png;base64,", base64_str)
    }, error = function(e) NULL)
  }
  
  # Yardımcı fonksiyon: Görsel yolunu çözümle (inline)
  inline_resolve_image_path <- function(image_path) {
    if (is.null(image_path) || !nzchar(image_path)) return(NULL)
    
    # 1. Doğrudan yolu dene
    if (file.exists(image_path)) {
      return(image_path)
    }
    
    # 2. user_images/ içeren göreli yolu çıkarmayı dene
    user_images_match <- regmatches(image_path, regexec("(user_images/.+)$", image_path))[[1]]
    if (length(user_images_match) >= 2) {
      relative_path <- user_images_match[2]
      candidate_path <- file.path(getwd(), relative_path)
      if (file.exists(candidate_path)) {
        return(candidate_path)
      }
    }
    
    # 3. Sadece dosya adını al ve user_images altında ara
    filename <- basename(image_path)
    search_pattern <- file.path(getwd(), "user_images", "*", "*", filename)
    found_files <- Sys.glob(search_pattern)
    if (length(found_files) > 0) {
      return(found_files[1])
    }
    
    return(NULL)
  }
  
  # Yardımcı fonksiyon: Görsel HTML'i oluştur (inline)
  inline_render_image_html <- function(image_path, description, message_id) {
    resolved_path <- inline_resolve_image_path(image_path)
    
    if (is.null(resolved_path)) {
      # Dosya bulunamadı - yer tutucu göster
      placeholder_html <- sprintf(
        '<div class="generated-image-container">
           <div class="image-placeholder" style="padding: 20px; background: linear-gradient(135deg, #667eea 0%%, #764ba2 100%%); border-radius: 12px; text-align: center; color: white;">
             <i class="fas fa-image" style="font-size: 48px; margin-bottom: 10px; opacity: 0.8;"></i>
             <p style="margin: 10px 0; font-weight: 500;">Görsel dosyası bulunamadı</p>
           </div>
           %s
         </div>',
        if (!is.null(description) && nzchar(description)) {
          sprintf('<div class="image-description"><p>%s</p></div>', htmltools::htmlEscape(description))
        } else ""
      )
      return(placeholder_html)
    }
    
    # Görseli base64'e çevir
    img_src <- inline_get_image_base64(resolved_path)
    if (is.null(img_src)) {
      # Base64 dönüşümü başarısız
      return(sprintf(
        '<div class="generated-image-container">
           <div class="image-placeholder" style="padding: 20px; background: #f0f0f0; border-radius: 12px; text-align: center;">
             <p>Görsel yüklenemedi</p>
           </div>
           %s
         </div>',
        if (!is.null(description) && nzchar(description)) {
          sprintf('<div class="image-description"><p>%s</p></div>', htmltools::htmlEscape(description))
        } else ""
      ))
    }
    
    # Başarılı - tam görsel HTML'i oluştur
    sprintf(
      '<div class="generated-image-container" data-message-id="%s">
         <div class="image-wrapper">
           <img src="%s" alt="Oluşturulan görsel" class="generated-image" loading="lazy" />
           <div class="image-watermark">MERGEN Bilge</div>
         </div>
         <div class="image-actions">
           <button class="image-action-btn-modern" onclick="window.downloadGeneratedImage(this)" title="İndir">
             <i class="fas fa-download"></i>
           </button>
           <button class="image-action-btn-modern" onclick="window.copyGeneratedImage(this)" title="Kopyala">
             <i class="fas fa-copy"></i>
           </button>
           <button class="image-action-btn-modern" onclick="window.printGeneratedImage(this)" title="Yazdır">
             <i class="fas fa-print"></i>
           </button>
         </div>
         %s
       </div>',
      message_id,
      img_src,
      if (!is.null(description) && nzchar(description)) {
        sprintf('<div class="image-description"><p>%s</p></div>', htmltools::htmlEscape(description))
      } else ""
    )
  }
  
  # Ana işleme döngüsü
  lapply(seq_len(nrow(chat_df)), function(i) {
    row <- chat_df[i, ]
    
    content_text <- row$MessageContent %||% ""
    msg_type <- row$MessageType %||% "user"
    
    # Boşlukları temizle (BOM veya görünmez karakterler için)
    content_text <- trimws(content_text)
 
    # Görsel mesajı kontrolü: [GÖRSEL:path] veya [GÖRSEL] ile başlıyor mu?
    is_image_message <- grepl("^\\[GÖRSEL", content_text, perl = TRUE)
 
    # Görsel mesajı işleme: "ai" veya "assistant" tipi kabul edilir
    processed <- if (is_image_message && msg_type %in% c("ai", "assistant")) {
      
      # Görsel yolunu ve açıklamasını ayıkla
      # Format: [GÖRSEL:/path/to/image.png] açıklama metni
      image_match <- regmatches(content_text, regexec("^\\[GÖRSEL:([^\\]]+)\\]\\s*(.*)", content_text, perl = TRUE))[[1]]
 
      if (length(image_match) == 3) {
        # Yeni format: [GÖRSEL:path] description
        image_path <- image_match[2]
        image_description <- image_match[3]
        
        # Inline görsel HTML oluştur
        image_html <- inline_render_image_html(
          image_path,
          image_description,
          as.character(row$MessageID)
        )
        list(html = image_html, has_code = FALSE)
        
      } else {
        # Eski format: [GÖRSEL] description (path yok)
        old_match <- regmatches(content_text, regexec("^\\[GÖRSEL\\]\\s*(.*)", content_text, perl = TRUE))[[1]]
        image_description <- if (length(old_match) == 2) old_match[2] else content_text
 
        # Sadece açıklamayı stilize göster
        styled_html <- sprintf(
          '<div class="generated-image-container">
             <div class="image-description"><p>%s</p></div>
           </div>',
          htmltools::htmlEscape(image_description)
        )
        list(html = styled_html, has_code = FALSE)
      }
    } else {
      # Normal mesaj işleme (chartlab veya diğer)
      has_chartlab <- grepl("```chartlab", content_text, fixed = TRUE)
 
      if (has_chartlab && identical(msg_type, "ai")) {
        # Chartlab işleme - globalenv'den fonksiyonu almaya çalış
        chart_fn <- tryCatch(
          get("build_chartlab_message_static", envir = globalenv(), mode = "function"),
          error = function(e) NULL
        )
        if (!is.null(chart_fn)) {
          chart_result <- tryCatch(
            chart_fn(content_text, as.character(row$MessageID)),
            error = function(e) list(found = FALSE)
          )
          if (isTRUE(chart_result$found)) {
            list(html = chart_result$html, has_code = FALSE)
          } else {
            # Chartlab bulunamadı, normal işle
            process_fn <- tryCatch(
              get("process_message_content", envir = globalenv(), mode = "function"),
              error = function(e) NULL
            )
            if (!is.null(process_fn)) {
              process_fn(content_text, msg_type)
            } else {
              list(html = commonmark::markdown_html(content_text, hardbreaks = TRUE), has_code = FALSE)
            }
          }
        } else {
          # chart fonksiyonu yok, normal işle
          process_fn <- tryCatch(
            get("process_message_content", envir = globalenv(), mode = "function"),
            error = function(e) NULL
          )
          if (!is.null(process_fn)) {
            process_fn(content_text, msg_type)
          } else {
            list(html = commonmark::markdown_html(content_text, hardbreaks = TRUE), has_code = FALSE)
          }
        }
      } else {
        # Normal mesaj
        process_fn <- tryCatch(
          get("process_message_content", envir = globalenv(), mode = "function"),
          error = function(e) NULL
        )
        if (!is.null(process_fn)) {
          process_fn(content_text, msg_type)
        } else {
          list(html = commonmark::markdown_html(content_text, hardbreaks = TRUE), has_code = FALSE)
        }
      }
    }

    timestamp_val <- row$MessageTimestamp
    # Saat dilimini belirle: ODBC sürücüsü genellikle UTC döndürür,
    # format() tz parametresiyle ham saat değerini korur
    ts_tz <- attr(timestamp_val, "tzone")
    if (is.null(ts_tz) || !nzchar(ts_tz)) {
      ts_tz <- "UTC"
    }

    list(
      id = as.character(row$MessageID),
      db_id = as.integer(row$MessageID),
      content = row$MessageContent,
      html_content = processed$html,
      has_code = processed$has_code,
      type = row$MessageType,
      timestamp = format(timestamp_val, "%d.%m.%Y - %H:%M", tz = ts_tz)
    )
  })
}

load_chat_messages_from_db <- function(chat_id) {
  stopifnot(!is.null(chat_id))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    SELECT c.ChatTitle, c.CreateTimestamp, m.MessageID, m.MessageContent,
           m.MessageType, m.MessageTimestamp, m.MessageOrder
    FROM MB_Chats c
    LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
    WHERE c.ChatID = ?
    ORDER BY m.MessageOrder ASC
  "

  chat_param <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_param)) {
    chat_param <- chat_id
  }

  chat_df <- dbGetQuery(conn, query, params = list(chat_param))
  if (nrow(chat_df) == 0) {
    return(list(title = NULL, timestamp = NULL, messages = list(), message_count = 0L))
  }

  messages_df <- chat_df[!is.na(chat_df$MessageID), , drop = FALSE]
  messages <- if (nrow(messages_df) > 0) format_chat_messages(messages_df) else list()

  list(
    title = chat_df$ChatTitle[1],
    timestamp = chat_df$CreateTimestamp[1],
    messages = messages,
    message_count = length(messages)
  )
}

load_chat_messages_batch <- function(chat_ids) {
  if (is.null(chat_ids) || length(chat_ids) == 0) {
    return(list())
  }

  ids <- unique(as.character(chat_ids))
  ids <- ids[nzchar(ids)]
  if (length(ids) == 0) {
    return(list())
  }

  placeholder <- paste(rep("?", length(ids)), collapse = ", ")

  param_values <- lapply(ids, function(id) {
    numeric_id <- suppressWarnings(as.integer(id))
    if (!is.na(numeric_id)) {
      numeric_id
    } else {
      id
    }
  })

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- paste0(
    "SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,",
    "       m.MessageID, m.MessageContent, m.MessageType,",
    "       m.MessageTimestamp, m.MessageOrder",
    "  FROM MB_Chats c",
    "  LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID",
    " WHERE c.ChatID IN (", placeholder, ")",
    " ORDER BY c.ChatID ASC, m.MessageOrder ASC"
  )

  result <- dbGetQuery(conn, query, params = param_values)

  if (nrow(result) == 0) {
    empty <- stats::setNames(vector("list", length(ids)), ids)
    return(lapply(empty, function(...) {
      list(
        title = NULL,
        timestamp = NULL,
        messages = list(),
        message_count = 0L,
        last_message_timestamp = NULL
      )
    }))
  }

  split_rows <- split(result, result$ChatID)
  names(split_rows) <- as.character(names(split_rows))
  formatted <- lapply(split_rows, function(chat_df) {
    messages_df <- chat_df[!is.na(chat_df$MessageID), , drop = FALSE]
    messages <- if (nrow(messages_df) > 0) format_chat_messages(messages_df) else list()
    last_ts <- if (nrow(messages_df) > 0) {
      messages_df$MessageTimestamp[nrow(messages_df)]
    } else {
      chat_df$CreateTimestamp[1]
    }

    list(
      title = chat_df$ChatTitle[1],
      timestamp = chat_df$CreateTimestamp[1],
	  messages = messages,
      message_count = length(messages),
      last_message_timestamp = last_ts
    )
  })
  names(formatted) <- as.character(names(formatted))

  # Zaman damgasına göre sırala (en yeni önce)
  if (length(formatted) > 1) {
    timestamps <- vapply(formatted, function(chat) {
      ts <- chat$timestamp
      if (inherits(ts, "POSIXct")) {
        as.numeric(ts)
      } else {
        0
      }
    }, numeric(1))
    
    sorted_order <- order(timestamps, decreasing = TRUE)
    formatted <- formatted[sorted_order]
  }
  
  missing_ids <- setdiff(ids, names(formatted))
  if (length(missing_ids) > 0) {
    for (mid in missing_ids) {
      formatted[[mid]] <- list(
        title = NULL,
        timestamp = NULL,
        messages = list(),
        message_count = 0L,
        last_message_timestamp = NULL
      )
    }
  }

  formatted
}

# Lightweight history fetch: return paired user/assistant rows per chat
load_history_rows_batch <- function(chat_ids) {
  if (is.null(chat_ids) || length(chat_ids) == 0) {
    return(list())
  }

  ids <- unique(as.character(chat_ids))
  ids <- ids[nzchar(ids)]
  if (length(ids) == 0) {
    return(list())
  }

  chat_data <- load_chat_messages_batch(ids)
  if (length(chat_data) == 0) {
    return(stats::setNames(vector("list", length(ids)), ids))
  }

  build_rows <- function(chat, chat_id) {
    messages <- chat$messages %||% list()
    if (length(messages) == 0) {
      return(list())
    }

    output_rows <- list()
    pending_user <- NULL
    chat_title <- chat$title %||% chat_id

    for (msg in messages) {
      msg_type <- tolower(msg$type %||% "")

      if (identical(msg_type, "user")) {
        pending_user <- msg
      } else if (msg_type %in% c("assistant", "ai")) {
        if (!is.null(pending_user)) {
          ts_val <- pending_user$timestamp %||% pending_user$timestamp_raw %||% pending_user$time

          formatted_ts <- if (inherits(ts_val, "POSIXt")) {
            format(ts_val, "%d.%m.%Y - %H:%M", tz = attr(ts_val, "tzone") %||% "")
          } else if (is.character(ts_val) && nzchar(ts_val)) {
            ts_val
          } else {
            tryCatch({
              parsed <- as.POSIXct(ts_val, origin = "1970-01-01", tz = "UTC")
              format(parsed, "%d.%m.%Y - %H:%M", tz = attr(parsed, "tzone") %||% "UTC")
            }, error = function(...) "")
          }

          output_rows <- append(output_rows, list(list(
            Chat_ID = chat_title,
            Tarih = formatted_ts,
            Soru = substr(pending_user$content %||% "", 1, 100),
            Cevap = substr(msg$content %||% msg$html_content %||% "", 1, 100)
          )))

          pending_user <- NULL
        }
      }
    }

    output_rows
  }

  formatted <- lapply(ids, function(chat_id) {
    chat <- chat_data[[chat_id]] %||% chat_data[[as.character(chat_id)]]
    if (is.null(chat)) {
      return(list())
    }
    build_rows(chat, chat_id)
  })

  names(formatted) <- ids
  formatted
}

# Create new chat, return ChatID integer (UPDATED with validation)
create_new_chat_in_db <- function(user_id, initial_title = "Yeni Söyleşi") {
  stopifnot(!is.null(user_id))
  
  # ADDED: Input validation
  validate_chat_title(initial_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "INSERT INTO MB_Chats (UserID, ChatTitle) OUTPUT INSERTED.ChatID AS ChatID VALUES (?, ?)"
  res <- dbGetQuery(conn, query, params = normalize_db_params(list(user_id, initial_title)))
  if (nrow(res) == 0) stop("Failed to create new chat session in DB.")
  return(as.integer(res$ChatID[1]))
}

sanitize_input <- function(text) {
  warning("sanitize_input() is deprecated when using parameterized queries")
  return(text)
}

# Save message (synchronous/main process or worker-safe if get_connection created a worker conn)
# msg is a list: list(content=..., type="user"/"assistant", timestamp=POSIXct or formatted string)
save_message_to_db <- function(chat_id, msg) {
  stopifnot(!is.null(chat_id))
  stopifnot(is.list(msg) && !is.null(msg$content) && !is.null(msg$type))

  # Validate message content
  validate_message_content(msg$content)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "
  
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  max_order_query <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- dbGetQuery(conn, max_order_query, params = list(chat_id))$maxord[1]
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  res <- dbGetQuery(conn, query, params = normalize_db_params(list(chat_id, msg$content, msg$type, ts, next_order)))
  if (nrow(res) == 0) stop("Failed to save message to DB.")
  return(as.integer(res$MessageID[1]))
}

# Safe message saving with fallback logging
save_message_safely <- function(chat_id, message, user_id = NULL) {
  tryCatch({
    save_message_to_db(chat_id, message)
  }, error = function(e) {
    # Log failed messages to file for recovery
    log_file <- file.path(tempdir(), paste0("failed_messages_", Sys.Date(), ".log"))
    log_entry <- list(
      timestamp = Sys.time(),
      chat_id = chat_id,
      message = message,
      user_id = user_id,
      error = e$message
    )
    cat(jsonlite::toJSON(log_entry, auto_unbox = TRUE), 
        "\n", 
        file = log_file, 
        append = TRUE)
    warning(paste("Message save failed, logged to:", log_file))
    return(NULL)
  })
}                          

# Update an existing message's content in the database
update_message_content_in_db <- function(message_id, new_content) {
  stopifnot(!is.null(message_id), is.character(new_content))
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))
  
  query <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
  
  # Execute the update statement
  dbExecute(conn, query, params = normalize_db_params(list(new_content, as.integer(message_id))))
}

update_chat_title_in_db <- function(chat_id, new_title) {
  stopifnot(!is.null(chat_id))
  
  # ADDED: Input validation
  validate_chat_title(new_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "UPDATE MB_Chats SET ChatTitle = ? WHERE ChatID = ?"
  dbExecute(conn, query, params = normalize_db_params(list(new_title, chat_id)))
}

# Feedback functions
save_feedback_to_db <- function(user_id, message_id, feedback_type) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    MERGE MB_Feedback AS target
    USING (SELECT ? AS UserID, ? AS MessageID, ? AS FeedbackType) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
    WHEN MATCHED THEN UPDATE SET FeedbackType = source.FeedbackType
    WHEN NOT MATCHED BY TARGET THEN INSERT (UserID, MessageID, FeedbackType) VALUES (source.UserID, source.MessageID, source.FeedbackType);
  "
  dbExecute(conn, query, params = normalize_db_params(list(user_id, as.integer(message_id), feedback_type)))
}

remove_feedback_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "DELETE FROM MB_Feedback WHERE UserID = ? AND MessageID = ?"
  dbExecute(conn, query, params = list(user_id, as.integer(message_id)))
}

load_feedback_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT MessageID, FeedbackType FROM MB_Feedback WHERE UserID = ?"
  feedback_data <- dbGetQuery(conn, query, params = list(user_id))
  if (nrow(feedback_data) == 0) return(list(liked = character(0), disliked = character(0)))
  list(
    liked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == 'like']),
    disliked = as.character(feedback_data$MessageID[feedback_data$FeedbackType == 'dislike'])
  )
}

# Log usage
log_ai_usage <- function(chat_id, message_id, user_id, model_used, duration, success) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess)
    VALUES (?, ?, ?, ?, ?, ?)
  "
  dbExecute(conn, query, params = normalize_db_params(list(chat_id, message_id, user_id, model_used, duration, success)))
}

# Chat deletion
delete_chat_from_db <- function(chat_id, user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Önce sohbetin görsel klasörünü sil (varsa)
  tryCatch({
    image_dir <- file.path("user_images", as.character(user_id), as.character(chat_id))
    if (dir.exists(image_dir)) {
      # Klasördeki tüm dosyaları ve klasörün kendisini sil
      unlink(image_dir, recursive = TRUE)
      cat("[DATABASE] Görsel klasörü silindi:", image_dir, "\n")
    }
  }, error = function(e) {
    cat("[DATABASE] Görsel klasörü silinirken hata:", e$message, "\n")
  })

  # Sohbeti silinmiş olarak işaretle
  query <- "UPDATE MB_Chats SET IsDeleted = 1 WHERE ChatID = ? AND UserID = ?"
  dbExecute(conn, query, params = list(chat_id, user_id))
}

clear_all_chats_from_db <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Önce kullanıcının tüm görsel klasörlerini sil
  tryCatch({
    user_image_dir <- file.path("user_images", as.character(user_id))
    if (dir.exists(user_image_dir)) {
      # Kullanıcının tüm görsel klasörlerini sil
      unlink(user_image_dir, recursive = TRUE)
      cat("[DATABASE] Kullanıcının tüm görsel klasörleri silindi:", user_image_dir, "\n")
    }
  }, error = function(e) {
    cat("[DATABASE] Görsel klasörleri silinirken hata:", e$message, "\n")
  })

  # Tüm sohbetleri silinmiş olarak işaretle
  query <- "UPDATE MB_Chats SET IsDeleted = 1 WHERE UserID = ?"
  dbExecute(conn, query, params = list(user_id))
}

# -------------------------
# Worker-safe convenience
# -------------------------
# Use inside future / worker. Do NOT reference Shiny reactives here.
# Example usage inside future:
#   future({
#     worker_save_assistant_response(chat_id = chat_id_val, response_text = resp, model_used = "<local-llm>", user_id = user_id)
#   })
worker_save_assistant_response <- function(chat_id, response_text,
                                           message_type = "assistant",
                                           timestamp = Sys.time(),
                                           log_usage = TRUE,
                                           user_id = NULL,
                                           model_used = "<local-llm>",
                                           duration = 0.0) {
  # create fresh worker connection
  conn <- worker_db_connect()
  on.exit({
    tryCatch(DBI::dbDisconnect(conn), error = function(e) NULL)
  })

  # compute next order safely
  max_order_q <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- tryCatch(DBI::dbGetQuery(conn, max_order_q, params = list(chat_id))$maxord[1],
                        error = function(e) NA)
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  # FIX: Add 3 hours to timestamp for GMT+3
  timestamp_gmt3 <- format(timestamp, "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  insert_q <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, ?, ?, ?, ?)
  "
  res <- DBI::dbGetQuery(conn, insert_q, params = normalize_db_params(list(chat_id, response_text, message_type, timestamp_gmt3, next_order)))
  response_message_id <- if (nrow(res) > 0) as.integer(res$MessageID[1]) else NA_integer_

  if (isTRUE(log_usage)) {
    tryCatch({
      log_q <- "INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess) VALUES (?, ?, ?, ?, ?, ?)"
      DBI::dbExecute(conn, log_q, params = normalize_db_params(list(chat_id, response_message_id, user_id, model_used, duration, 1)))
    }, error = function(e) {
      # ignore logging errors
    })
  }

  return(response_message_id)
}

# Genişletilmiş geri bildirim kaydetme
save_feedback_to_db_extended <- function(user_id, message_id, feedback_type, tags = NULL, comment = NULL) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # NULL degerleri SQL NULL (NA) olarak isle
  safe_tags <- if (is.null(tags) || length(tags) == 0) NA_character_ else as.character(tags)
  safe_comment <- if (is.null(comment) || length(comment) == 0) NA_character_ else as.character(comment)

  query <- "
    MERGE MB_Feedback AS target
    USING (SELECT ? AS UserID, ? AS MessageID, ? AS FeedbackType, ? AS FeedbackTags, ? AS FeedbackComment) AS source
    ON (target.UserID = source.UserID AND target.MessageID = source.MessageID)
	WHEN MATCHED THEN 
      UPDATE SET 
        FeedbackType = source.FeedbackType,
        FeedbackTags = source.FeedbackTags,
        FeedbackComment = source.FeedbackComment,
        FeedbackTimestamp = CAST(GETDATE() AS datetime2(0))
    WHEN NOT MATCHED BY TARGET THEN 
      INSERT (UserID, MessageID, FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp) 
      VALUES (source.UserID, source.MessageID, source.FeedbackType, source.FeedbackTags, source.FeedbackComment, CAST(GETDATE() AS datetime2(0)));
  "
  
  dbExecute(conn, query, params = normalize_db_params(list(
    user_id, 
    as.integer(message_id), 
    feedback_type,
    safe_tags,
    safe_comment
  )))
}

# Geri bildirim detaylarını yükleme
load_feedback_details_from_db <- function(user_id, message_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp FROM MB_Feedback WHERE UserID = ? AND MessageID = ?"
  result <- dbGetQuery(conn, query, params = list(user_id, as.integer(message_id)))
  
  if (nrow(result) == 0) return(NULL)
  as.list(result[1, ])
}