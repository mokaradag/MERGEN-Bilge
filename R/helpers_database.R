# Dosya Yolu: R/helpers_database.R
# Açıklama: Veritabanı erişimi ve worker-safe işlemler için yardımcı fonksiyonlar.
#   - Worker'lara pool/DBI harici pointer'ları aktarmayın.
#   - Worker fonksiyonları kendi DB bağlantılarını oluşturur (pool gerekmez).
#   - Bu fonksiyonlar Shiny reactive'lerine ERİŞMEZ; her zaman düz R değerleri
#     (chat_id, user_id, prompt_text vb.) future/worker'lara geçirin.
#   - Reactive değerleri ana Shiny reactive bağlamında yakalayın (isolate ile).
#
# NOT: SQL Server'a özgü OUTPUT ... INSERTED sözdizimi kullanılmaktadır.

library(DBI)
library(odbc)
library(pool)

# --- Yapılandırma ---
.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")

# Havuz istatistiklerini al
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

  # 3. Doğrudan Bağlantı
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

  # Türkçe karakter desteği: ODBC sürücüsüne UTF-8 istemci karakter seti bildir.
  # FreeTDS için ClientCharset=UTF-8, NVARCHAR sütunlarına doğru Unicode yazımı sağlar.
  # Microsoft ODBC Driver bu parametreyi sessizce yoksayar, dolayısıyla güvenlidir.
  # LANG ortam değişkeni global.R'de ayarlanır (MSODBCSQL sürücüsü bunu kullanır).
  # NOT: ODBC sürücüsü C seviyesindeki LC_CTYPE locale değerini kullanarak
  # gelen baytların kodlamasını belirler. global.R'de C.UTF-8 locale zorunlu
  # kılınmıştır; bu sayede R'dan gelen UTF-8 baytları doğru yorumlanır.
  conn <- tryCatch({
    conn_str <- paste0("DSN=", dsn_name, ";ClientCharset=UTF-8;")
    DBI::dbConnect(
      odbc::odbc(),
      .connection_string = conn_str,
      encoding = "UTF-8",
      name_encoding = "UTF-8"
    )
  }, error = function(e) {
    log_warn("ODBC bağlantısı ClientCharset ile başarısız: {e$message}")
    # Yedek bağlantı: encoding parametresi korunur
    DBI::dbConnect(
      odbc::odbc(),
      dsn = dsn_name,
      encoding = "UTF-8",
      name_encoding = "UTF-8"
    )
  })

  # Bağlantı sonrası: SQL Server oturumunda NVARCHAR parametrelerin
  # doğru yorumlanması için ANSI ayarlarını etkinleştir
  tryCatch({
    DBI::dbExecute(conn, "SET ANSI_NULLS ON")
    DBI::dbExecute(conn, "SET QUOTED_IDENTIFIER ON")
    DBI::dbExecute(conn, "SET ANSI_PADDING ON")
  }, error = function(e) NULL)

  return(list(conn = conn, pooled = FALSE, pool = NULL))
}

# Bağlantı serbest bırakma - sadece pool OLMAYAN bağlantıları kapat
release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))

  # Pool bağlantısıysa dokunma - pool kendi bağlantılarını yönetir
  if (isTRUE(conn_info$pooled)) {
    return(invisible(NULL))
  }

  # Sadece doğrudan (pool dışı) bağlantıları kapat
  tryCatch({
    DBI::dbDisconnect(conn_info$conn)
  }, error = function(e) {
    # yoksay
  })

  invisible(NULL)
}

# Worker tarafı: arka plan işlemlerinde kullanılmak üzere yeni bir DBI bağlantısı oluşturur.
# Yeniden deneme mantığı ile bağlantı hatalarına dayanıklıdır.
worker_db_connect <- function(max_retries = 3, retry_delay = 1) {
  dsn_name <- Sys.getenv("DB_DSN", .DEFAULT_DSN)
  for (i in 1:max_retries) {
    tryCatch({
      if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
        stop("Worker needs 'odbc' and 'DBI' packages installed.")
      }
      # Türkçe karakter desteği: ClientCharset=UTF-8 ile ODBC sürücüsüne bildir
      # Worker süreçlerinde de LC_CTYPE locale kontrolü yap (fork edilen
      # süreçler ana sürecin locale ayarını miras almalı, ama garanti değil)
      if (!grepl("UTF-8|utf8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE)) {
        for (.wloc in c("C.UTF-8", "en_US.UTF-8", "en_US.utf8")) {
          .wres <- tryCatch(suppressWarnings(Sys.setlocale("LC_CTYPE", .wloc)), error = function(e) "")
          if (nzchar(.wres) && grepl("UTF-8|utf8", .wres, ignore.case = TRUE)) break
        }
      }
      conn <- tryCatch({
        conn_str <- paste0("DSN=", dsn_name, ";ClientCharset=UTF-8;")
		DBI::dbConnect(
		  odbc::odbc(),
		  .connection_string = conn_str,
		  encoding = "UTF-8",
		  name_encoding = "UTF-8"
		)
      }, error = function(e2) {
		DBI::dbConnect(
		  odbc::odbc(),
		  dsn = dsn_name,
		  encoding = "UTF-8",
		  name_encoding = "UTF-8"
		)
      })
      # Worker bağlantısı için de ANSI ayarlarını etkinleştir
      tryCatch({
        DBI::dbExecute(conn, "SET ANSI_NULLS ON")
        DBI::dbExecute(conn, "SET QUOTED_IDENTIFIER ON")
        DBI::dbExecute(conn, "SET ANSI_PADDING ON")
      }, error = function(e2) NULL)
      return(conn)
    }, error = function(e) {
      if (i == max_retries) {
        stop(paste("Failed to connect to database after", max_retries, "attempts:", e$message))
      }
      Sys.sleep(retry_delay * i)
    })
  }
}

# -------------------------
# UTF-8 Kodlama Yardımcısı
# -------------------------
# Veritabanına yazılacak metinleri UTF-8 olarak normalleştirir.
# Türkçe karakterlerin (ç, ğ, ı, ö, ş, ü vb.) doğru kaydedilmesini sağlar.
# ODBC sürücüsüne gönderilmeden önce R encoding etiketinin UTF-8 olmasını garanti eder.
ensure_utf8 <- function(text) {
  if (is.null(text)) return(text)

  if (!is.character(text)) {
    text <- as.character(text)
  }

  repair_one <- function(x) {
    if (is.na(x) || !nzchar(x)) return(x)

    out <- enc2utf8(x)

    if (exists("fixTurkishEncoding", mode = "function")) {
      out <- tryCatch(fixTurkishEncoding(out), error = function(e) out)
    }

    out2 <- tryCatch(iconv(out, from = "", to = "UTF-8", sub = ""), error = function(e) out)
    if (!is.na(out2) && nzchar(out2)) {
      out <- out2
    }

    Encoding(out) <- "UTF-8"
    out
  }

  vapply(text, repair_one, character(1), USE.NAMES = FALSE)
}

# SQL'e gidecek metin parametreleri için tek giriş noktası.
# İlke: Sonradan yorumda düzeltmek yerine, veriyi doğru formatta kaydet.
prepare_sql_text_params <- function(...) {
  values <- list(...)
  lapply(values, function(x) {
    if (is.null(x)) return(x)
    ensure_utf8(x)
  })
}

# -------------------------
# Girdi Doğrulama Yardımcıları
# -------------------------
validate_username <- function(username) {
  # Sadece harf, rakam, alt çizgi, nokta ve tire karakterlerine izin ver
  if (!grepl("^[a-zA-Z0-9_.-]+$", username)) {
    stop("Geçersiz kullanıcı adı formatı. Sadece harf, rakam, alt çizgi, nokta ve tire kullanılabilir.")
  }
  
  # Uzunluk sınırı kontrolü
  if (nchar(username) < 3 || nchar(username) > 50) {
    stop("Kullanıcı adı 3-50 karakter arasında olmalıdır.")
  }
  
  return(TRUE)
}

validate_chat_title <- function(title) {
  # Uzunluk sınırı kontrolü
  if (nchar(title) > 200) {
    stop("Sohbet başlığı 200 karakterden kısa olmalıdır.")
  }

  if (nchar(title) < 1) {
    stop("Sohbet başlığı boş olamaz.")
  }

  # Olası SQL enjeksiyon kalıplarını engelle (derinlemesine savunma)
  # Parametreli sorgular kullanılsa bile şüpheli kalıpları reddet
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
      stop("Sohbet başlığı geçersiz SQL kalıpları içeriyor.")
    }
  }
  
  return(TRUE)
}

validate_message_content <- function(content) {
  # Uzunluk sınırı kontrolü (maksimum 20000 karakter)
  if (nchar(content) > 20000) {
    stop("Mesaj içeriği 20.000 karakter sınırını aşıyor.")
  }

  if (nchar(content) < 1) {
    stop("Mesaj içeriği boş olamaz.")
  }
  
  return(TRUE)
}

# -------------------------
# Veritabanı İşlem Yardımcıları
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
  # Türkçe karakterlerin doğru kaydedilmesi için encoding düzeltmesi + UTF-8 normalleştirme
  kaynak_adi <- username
  if (!is.null(sso_claims$full_name) && nzchar(sso_claims$full_name)) {
    # fixTurkishEncoding SSO claim'lerinde zaten uygulanmış olabilir;
    # yine de DB yazımı öncesi son kontrol olarak tekrar uygula
    kaynak_adi <- ensure_utf8(
      if (exists("fixTurkishEncoding", mode = "function")) {
        fixTurkishEncoding(sso_claims$full_name)
      } else {
        sso_claims$full_name
      }
    )
  } else {
    user_details_query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    user_details <- dbGetQuery(conn, user_details_query, params = list(username))
    if (nrow(user_details) > 0 && nzchar(user_details$KaynakAdi[1] %||% "")) {
      kaynak_adi <- ensure_utf8(
        if (exists("fixTurkishEncoding", mode = "function")) {
          fixTurkishEncoding(user_details$KaynakAdi[1])
        } else {
          user_details$KaynakAdi[1]
        }
      )
    }
  }

  user_id_query <- "SELECT UserID FROM MB_Users WHERE KullaniciAdi = ?"
  user_id_result <- dbGetQuery(conn, user_id_query, params = list(username))

  if (nrow(user_id_result) > 0) {
    user_id <- as.integer(user_id_result$UserID[1])
    update_query <- "UPDATE MB_Users SET KaynakAdi = CAST(? AS NVARCHAR(255)), LastLoginDate = GETDATE() WHERE UserID = ?"
    dbExecute(conn, update_query, params = list(kaynak_adi, user_id))

    # SSO ek alanlarını güncelle (tablo destekliyorsa)
    if (!is.null(sso_claims)) {
      update_sso_fields(conn, user_id, sso_claims)
    }

    return(user_id)
  } else {
    insert_query <- "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate) OUTPUT INSERTED.UserID AS UserID VALUES (?, CAST(? AS NVARCHAR(255)), GETDATE())"
    res <- dbGetQuery(conn, insert_query, params = list(username, kaynak_adi))
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

    # Türkçe karakterlerin doğru kaydedilmesi için tüm metin değerlerine ensure_utf8 uygula
    if ("Sicil" %in% existing_cols && !is.null(sso_claims$sicil)) {
      set_parts <- c(set_parts, "Sicil = ?")
      params <- c(params, list(ensure_utf8(sso_claims$sicil)))
    }
    if ("Email" %in% existing_cols && !is.null(sso_claims$email)) {
      set_parts <- c(set_parts, "Email = ?")
      params <- c(params, list(ensure_utf8(sso_claims$email)))
    }
    if ("Sektor" %in% existing_cols && !is.null(sso_claims$sektor)) {
      set_parts <- c(set_parts, "Sektor = CAST(? AS NVARCHAR(255))")
      params <- c(params, list(ensure_utf8(sso_claims$sektor)))
    }
    if ("Departman" %in% existing_cols && !is.null(sso_claims$department)) {
      set_parts <- c(set_parts, "Departman = CAST(? AS NVARCHAR(255))")
      params <- c(params, list(ensure_utf8(sso_claims$department)))
    }
    if ("Mudurluk" %in% existing_cols && !is.null(sso_claims$mudurluk)) {
      set_parts <- c(set_parts, "Mudurluk = CAST(? AS NVARCHAR(255))")
      params <- c(params, list(ensure_utf8(sso_claims$mudurluk)))
    }
    if ("MasrafYeriKodu" %in% existing_cols && !is.null(sso_claims$masraf_yeri_kodu)) {
      set_parts <- c(set_parts, "MasrafYeriKodu = ?")
      params <- c(params, list(ensure_utf8(sso_claims$masraf_yeri_kodu)))
    }
    if ("SonGirisKaynagi" %in% existing_cols) {
      set_parts <- c(set_parts, "SonGirisKaynagi = CAST(? AS NVARCHAR(50))")
      params <- c(params, list("keycloak"))
    }

    if (length(set_parts) > 0) {
      query <- paste0("UPDATE MB_Users SET ", paste(set_parts, collapse = ", "), " WHERE UserID = ?")
      params <- c(params, list(user_id))
      dbExecute(conn, query, params = params)
    }
  }, error = function(e) {
    # SSO alanları güncellenemedi - kritik değil, sessizce devam et
    log_warn("SSO alanları güncellenemedi (UserID={user_id}): {e$message}")
  })
  invisible(NULL)
}

# Kullanıcının sohbetlerini ve mesajlarını yükle (liste döndürür)
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

    # SQL sorgusundaki CreateTimestamp DESC sırasını koru
    unique_chat_ids <- as.character(summary_data$ChatID)

    formatted <- lapply(seq_len(nrow(summary_data)), function(i) {
      row <- summary_data[i, ]
      msg_count <- ifelse(is.na(row$MessageCount), 0L, row$MessageCount)
      list(
        title = ensure_utf8(
          if (exists("fixTurkishEncoding", mode = "function")) {
            fixTurkishEncoding(row$ChatTitle %||% "")
          } else {
            row$ChatTitle %||% ""
          }
        ),
        messages = NULL,
        timestamp = row$CreateTimestamp,
        last_message_timestamp = row$LastMessageTimestamp,
        message_count = as.integer(msg_count)
      )
    })
    names(formatted) <- unique_chat_ids

    # SQL sorgusuyla eşleşen doğru sırada olduğundan emin ol
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

  # SQL sorgusundaki CreateTimestamp DESC sırasını koru
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
      title = ensure_utf8(
        if (exists("fixTurkishEncoding", mode = "function")) {
          fixTurkishEncoding(chat_df$ChatTitle[1] %||% "")
        } else {
          chat_df$ChatTitle[1] %||% ""
        }
      ),
      messages = messages,
      timestamp = chat_df$CreateTimestamp[1],
      last_message_timestamp = last_msg_time,
      message_count = length(messages)
    )
  })
  
  # Orijinal CreateTimestamp DESC sırasına göre yeniden sırala
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
    
    # Render katmanı: yalnız görüntüleme için metni toparla.
    # Kayıt katmanı zaten doğru formatta saklamalıdır; burada DB verisini değiştirmeyiz.
    content_text <- ensure_utf8(
      if (exists("fixTurkishEncoding", mode = "function")) {
        fixTurkishEncoding(row$MessageContent %||% "")
      } else {
        row$MessageContent %||% ""
      }
    )
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

load_chat_messages_from_db <- function(chat_id, user_id = NULL) {
  stopifnot(!is.null(chat_id))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Güvenlik: user_id verilmişse yalnızca o kullanıcının söyleşisini yükle
  if (!is.null(user_id)) {
    query <- "
      SELECT c.ChatTitle, c.CreateTimestamp, m.MessageID, m.MessageContent,
             m.MessageType, m.MessageTimestamp, m.MessageOrder
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.ChatID = ? AND c.UserID = ?
      ORDER BY m.MessageOrder ASC
    "
  } else {
    query <- "
      SELECT c.ChatTitle, c.CreateTimestamp, m.MessageID, m.MessageContent,
             m.MessageType, m.MessageTimestamp, m.MessageOrder
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.ChatID = ?
      ORDER BY m.MessageOrder ASC
    "
  }

  chat_param <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_param)) {
    chat_param <- chat_id
  }

  params <- if (!is.null(user_id)) list(chat_param, as.integer(user_id)) else list(chat_param)
  chat_df <- dbGetQuery(conn, query, params = params)
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
		title = ensure_utf8(
		  if (exists("fixTurkishEncoding", mode = "function")) {
			fixTurkishEncoding(chat_df$ChatTitle[1] %||% "")
		  } else {
			chat_df$ChatTitle[1] %||% ""
		  }
		),
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

# Hafif geçmiş sorgusu: her sohbet için kullanıcı/asistan mesaj çiftlerini döndür
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

# Yeni sohbet oluştur, ChatID tamsayı döndür
create_new_chat_in_db <- function(user_id, initial_title = "Yeni Söyleşi") {
  stopifnot(!is.null(user_id))
  
  validate_chat_title(initial_title)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Kayıt katmanında doğru kodlama: SQL parametresinden hemen önce normalize et.
  sql_text <- prepare_sql_text_params(initial_title)

  query <- "INSERT INTO MB_Chats (UserID, ChatTitle) OUTPUT INSERTED.ChatID AS ChatID VALUES (?, CAST(? AS NVARCHAR(4000)))"
  res <- dbGetQuery(conn, query, params = list(user_id, sql_text[[1]]))
  if (nrow(res) == 0) stop("Veritabanında yeni sohbet oturumu oluşturulamadı.")
  return(as.integer(res$ChatID[1]))
}

sanitize_input <- function(text) {
  warning("sanitize_input() is deprecated when using parameterized queries")
  return(text)
}

# Mesajı kaydet (senkron/ana süreç veya worker-safe)
# msg: list(content=..., type="user"/"assistant", timestamp=POSIXct veya biçimlendirilmiş metin)
save_message_to_db <- function(chat_id, msg) {
  stopifnot(!is.null(chat_id))
  stopifnot(is.list(msg) && !is.null(msg$content) && !is.null(msg$type))

  validate_message_content(msg$content)

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, CAST(? AS NVARCHAR(MAX)), CAST(? AS NVARCHAR(50)), ?, ?)
  "
  
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  max_order_query <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- dbGetQuery(conn, max_order_query, params = list(chat_id))$maxord[1]
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  # Kayıt katmanında doğru kodlama: SQL parametresinden hemen önce normalize et.
  sql_text <- prepare_sql_text_params(msg$content, msg$type)
  res <- dbGetQuery(conn, query, params = list(chat_id, sql_text[[1]], sql_text[[2]], ts, next_order))
  if (nrow(res) == 0) stop("Mesaj veritabanına kaydedilemedi.")
  return(as.integer(res$MessageID[1]))
}

# Güvenli mesaj kaydetme (hata durumunda dosyaya log yazar)
save_message_safely <- function(chat_id, message, user_id = NULL) {
  tryCatch({
    save_message_to_db(chat_id, message)
  }, error = function(e) {
    # Başarısız mesajları kurtarma için dosyaya logla
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

# Veritabanındaki mevcut bir mesajın içeriğini güncelle
update_message_content_in_db <- function(message_id, new_content) {
  stopifnot(!is.null(message_id), is.character(new_content))
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))
  
  # Kayıt katmanında doğru kodlama: SQL parametresinden hemen önce normalize et.
  sql_text <- prepare_sql_text_params(new_content)

  query <- "UPDATE MB_Messages SET MessageContent = CAST(? AS NVARCHAR(MAX)) WHERE MessageID = ?"
  dbExecute(conn, query, params = list(sql_text[[1]], as.integer(message_id)))
}

update_chat_title_in_db <- function(chat_id, new_title) {
  stopifnot(!is.null(chat_id))
  
  validate_chat_title(new_title)
  
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Kayıt katmanında doğru kodlama: SQL parametresinden hemen önce normalize et.
  sql_text <- prepare_sql_text_params(new_title)

  query <- "UPDATE MB_Chats SET ChatTitle = CAST(? AS NVARCHAR(4000)) WHERE ChatID = ?"
  dbExecute(conn, query, params = list(sql_text[[1]], chat_id))
}

# Geri bildirim fonksiyonları
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
  dbExecute(conn, query, params = list(user_id, as.integer(message_id), feedback_type))
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

# Kullanım günlüğü kaydet
log_ai_usage <- function(chat_id, message_id, user_id, model_used, duration, success) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess)
    VALUES (?, ?, ?, ?, ?, ?)
  "
  dbExecute(conn, query, params = list(chat_id, message_id, user_id, model_used, duration, success))
}

# Sohbet silme
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
# Worker-safe yardımcı fonksiyonlar
# -------------------------
# Future / worker içinde kullanılır. Shiny reactive'lerine burada ERİŞMEYİN.
worker_save_assistant_response <- function(chat_id, response_text,
                                           message_type = "assistant",
                                           timestamp = Sys.time(),
                                           log_usage = TRUE,
                                           user_id = NULL,
                                           model_used = "<local-llm>",
                                           duration = 0.0) {
  # Yeni worker bağlantısı oluştur
  conn <- worker_db_connect()
  on.exit({
    tryCatch(DBI::dbDisconnect(conn), error = function(e) NULL)
  })

  # Sonraki mesaj sırasını güvenli şekilde hesapla
  max_order_q <- "SELECT MAX(MessageOrder) AS maxord FROM MB_Messages WHERE ChatID = ?"
  max_order <- tryCatch(DBI::dbGetQuery(conn, max_order_q, params = list(chat_id))$maxord[1],
                        error = function(e) NA)
  next_order <- if (is.na(max_order)) 1L else as.integer(max_order) + 1L

  # Zaman damgasını Türkiye saatine (GMT+3) çevir
  timestamp_gmt3 <- format(timestamp, "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")

  # Kayıt katmanında doğru kodlama: SQL parametresinden hemen önce normalize et.
  sql_text <- prepare_sql_text_params(response_text, message_type)

  insert_q <- "
    INSERT INTO MB_Messages (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
    OUTPUT INSERTED.MessageID AS MessageID
    VALUES (?, CAST(? AS NVARCHAR(MAX)), CAST(? AS NVARCHAR(50)), ?, ?)
  "
  res <- DBI::dbGetQuery(conn, insert_q, params = list(chat_id, sql_text[[1]], sql_text[[2]], timestamp_gmt3, next_order))
  response_message_id <- if (nrow(res) > 0) as.integer(res$MessageID[1]) else NA_integer_

  if (isTRUE(log_usage)) {
    tryCatch({
      log_q <- "INSERT INTO MB_Usage_Log (ChatID, MessageID, UserID, ModelUsed, ResponseDuration, ResponseSuccess) VALUES (?, ?, ?, ?, ?, ?)"
      DBI::dbExecute(conn, log_q, params = list(chat_id, response_message_id, user_id, model_used, duration, 1))
    }, error = function(e) {
      # Loglama hatalarını yoksay
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
  # Türkçe karakterlerin doğru kaydedilmesi için UTF-8 normalleştirmesi
  safe_tags <- if (is.null(tags) || length(tags) == 0) NA_character_ else ensure_utf8(as.character(tags))
  safe_comment <- if (is.null(comment) || length(comment) == 0) NA_character_ else ensure_utf8(as.character(comment))

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
  
  dbExecute(conn, query, params = list(
    user_id, 
    as.integer(message_id), 
    feedback_type,
    safe_tags,
    safe_comment
  ))
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
