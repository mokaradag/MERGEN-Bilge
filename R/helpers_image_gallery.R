# Dosya Yolu: R/helpers_image_gallery.R
# Görsel galerisi için yardımcı fonksiyonlar - kullanıcı görsellerini tarama, metadata toplama ve silme işlemleri

#' Kullanıcının tüm görsellerini tara ve metadata topla
#' @param user_id Kullanıcı ID
#' @return data.frame: file_path, chat_id, filename, created_at, file_size, month_key, month_label, description
scan_user_images <- function(user_id) {
  base_dir <- file.path(getwd(), "user_images", as.character(user_id))

  empty_df <- data.frame(
    file_path = character(),
    chat_id = character(),
    filename = character(),
    created_at = as.POSIXct(character()),
    file_size = numeric(),
    month_key = character(),
    month_label = character(),
    description = character(),
    chat_title = character(),
    stringsAsFactors = FALSE
  )

  if (!dir.exists(base_dir)) {
    return(empty_df)
  }

  image_files <- list.files(
    base_dir,
    pattern = "\\.(png|jpg|jpeg|gif|webp)$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(image_files) == 0) {
    return(empty_df)
  }

  month_map <- c(
    "January" = "Ocak", "February" = "Şubat", "March" = "Mart",
    "April" = "Nisan", "May" = "Mayıs", "June" = "Haziran",
    "July" = "Temmuz", "August" = "Ağustos", "September" = "Eylül",
    "October" = "Ekim", "November" = "Kasım", "December" = "Aralık"
  )

  # Veritabanından görsel açıklamalarını toplu olarak al
  descriptions_map <- load_image_descriptions_for_user(user_id)

  records <- lapply(image_files, function(fp) {
    fi <- file.info(fp)
    fname <- basename(fp)

    # Dosya yolundan chat_id çıkar: base_dir/chat_id/dosya.png
    relative <- substring(fp, nchar(base_dir) + 2)
    parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
    cid <- if (length(parts) >= 2) parts[1] else NA_character_

    created <- fi$mtime

    mk <- format(created, "%Y-%m")
    eng_month <- format(created, "%B")
    tr_month <- month_map[eng_month]
    if (is.na(tr_month)) tr_month <- eng_month
    ml <- paste0(tr_month, " ", format(created, "%Y"))

    # Açıklamayı dosya adına göre bul
    desc <- descriptions_map[[fname]] %||% ""

	# Söyleşi başlığını bul
    chat_title <- if (!is.na(cid)) {
      get_chat_title_for_image(cid, user_id) %||% ""
    } else ""

    data.frame(
      file_path = fp,
      chat_id = cid,
      filename = fname,
      created_at = created,
      file_size = fi$size,
      month_key = mk,
      month_label = ml,
      description = desc,
      chat_title = chat_title,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, records)
  result <- result[order(result$created_at, decreasing = TRUE), , drop = FALSE]
  rownames(result) <- NULL
  return(result)
}

#' Kullanıcının tüm görsel mesajlarından açıklamaları toplu yükle
#' @param user_id Kullanıcı ID
#' @return İsimli liste: dosya_adı -> açıklama
load_image_descriptions_for_user <- function(user_id) {
  result_map <- list()
  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    # Görsel mesajını ve hemen sonrasındaki AI yanıtını birlikte al
    # LIKE kalıbında köşeli parantezi escape et (SQL Server uyumluluğu)
    query <- "
      SELECT m.MessageContent, m.ChatID, m.MessageOrder
      FROM MB_Messages m
      INNER JOIN MB_Chats c ON m.ChatID = c.ChatID
      WHERE c.UserID = ? AND c.IsDeleted = 0
        AND m.MessageContent LIKE '\\[GÖRSEL:%' ESCAPE '\\'
    "
    rows <- DBI::dbGetQuery(conn, query, params = list(user_id))

    if (nrow(rows) > 0) {
      for (i in seq_len(nrow(rows))) {
        content <- rows$MessageContent[i]
        chat_id <- rows$ChatID[i]
        msg_order <- rows$MessageOrder[i]

        # Dosya adını çıkar
        m <- regmatches(content, regexec("^\\[GÖRSEL:([^\\]]+)\\]\\s*(.*)", content, perl = TRUE))[[1]]
        if (length(m) >= 3) {
          fname <- basename(m[2])
          inline_desc <- trimws(m[3])

          # Görselden sonraki AI yanıt mesajını ara (aynı söyleşide bir sonraki mesaj)
          next_msg_query <- "
            SELECT TOP 1 MessageContent
            FROM MB_Messages
            WHERE ChatID = ? AND MessageOrder > ? AND MessageType IN ('ai', 'assistant')
              AND MessageContent NOT LIKE '\\[GÖRSEL:%' ESCAPE '\\'
            ORDER BY MessageOrder ASC
          "
          next_row <- tryCatch(
            DBI::dbGetQuery(conn, next_msg_query, params = list(chat_id, msg_order)),
            error = function(e) data.frame()
          )

          # Öncelik: sonraki AI yanıtı > inline açıklama
          if (nrow(next_row) > 0 && nzchar(trimws(next_row$MessageContent[1]))) {
            result_map[[fname]] <- trimws(next_row$MessageContent[1])
          } else if (nzchar(inline_desc)) {
            result_map[[fname]] <- inline_desc
          }
        }
      }
    }
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Açıklama yükleme hatası:", e$message, "\n")
  })
  return(result_map)
}

#' Görsel dosyasını base64 thumbnail olarak yükle
#' @param file_path Görsel dosya yolu
#' @return Base64 data URL veya NULL
get_image_thumbnail_base64 <- function(file_path) {
  if (is.null(file_path) || !file.exists(file_path)) return(NULL)
  tryCatch({
    img_data <- base64enc::base64encode(file_path)
    paste0("data:image/png;base64,", img_data)
  }, error = function(e) {
    NULL
  })
}

#' Tek bir görseli sil ve ilgili mesajı güncelle
#' @param file_path Silinecek görsel dosya yolu
#' @param user_id Kullanıcı ID
#' @param chat_id Sohbet ID
#' @return TRUE/FALSE
delete_single_image <- function(file_path, user_id, chat_id) {
  tryCatch({
    # Dosya yolunu normalize et (URL encoding ve çift slash sorunlarını düzelt)
    file_path <- normalizePath(file_path, mustWork = FALSE)

    if (!file.exists(file_path)) {
      cat("[IMAGE_GALLERY] Görsel zaten mevcut değil:", file_path, "\n")
      return(TRUE)
    }

    # Dosyayı sil ve sonucu kontrol et
    removed <- file.remove(file_path)
    if (!isTRUE(removed)) {
      cat("[IMAGE_GALLERY] Görsel silinemedi (file.remove FALSE döndü):", file_path, "\n")
      return(FALSE)
    }

    # Silme sonrası doğrulama
    if (file.exists(file_path)) {
      cat("[IMAGE_GALLERY] Dosya hâlâ mevcut, Sys.sleep sonrası tekrar deneniyor:", file_path, "\n")
      Sys.sleep(0.2)
      if (file.exists(file_path)) {
        unlink(file_path, force = TRUE)
      }
      if (file.exists(file_path)) {
        cat("[IMAGE_GALLERY] Dosya silinemedi (ikinci deneme):", file_path, "\n")
        return(FALSE)
      }
    }

    cat("[IMAGE_GALLERY] Görsel silindi:", file_path, "\n")

    # Veritabanındaki ilgili mesajı güncelle
    update_message_after_image_deletion(file_path, chat_id)

    # Boş kalan klasörü temizle
    chat_dir <- file.path(getwd(), "user_images", as.character(user_id), as.character(chat_id))
    if (dir.exists(chat_dir)) {
      remaining <- list.files(chat_dir, recursive = FALSE)
      if (length(remaining) == 0) {
        unlink(chat_dir, recursive = TRUE)
        cat("[IMAGE_GALLERY] Boş klasör silindi:", chat_dir, "\n")
      }
    }

    return(TRUE)
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Görsel silme hatası:", e$message, "\n")
    return(FALSE)
  })
}

#' Kullanıcının tüm görsellerini sil
#' @param user_id Kullanıcı ID
#' @return Silinen görsel sayısı
delete_all_user_images <- function(user_id) {
  images <- scan_user_images(user_id)
  if (nrow(images) == 0) return(0L)

  deleted_count <- 0L
  unique_chats <- unique(images$chat_id[!is.na(images$chat_id)])

  for (i in seq_len(nrow(images))) {
    row <- images[i, ]
    tryCatch({
      if (file.exists(row$file_path)) {
        removed <- file.remove(row$file_path)
        if (isTRUE(removed)) {
          deleted_count <- deleted_count + 1L
        }
      }
    }, error = function(e) {
      cat("[IMAGE_GALLERY] Toplu silme hatası:", e$message, "\n")
    })
  }

  # Silinen görsellerin mesajlarını güncelle
  for (cid in unique_chats) {
    update_messages_after_bulk_deletion(cid)
  }

  # Boş klasörleri temizle
  user_dir <- file.path(getwd(), "user_images", as.character(user_id))
  if (dir.exists(user_dir)) {
    chat_dirs <- list.dirs(user_dir, recursive = FALSE, full.names = TRUE)
    for (cd in chat_dirs) {
      remaining <- list.files(cd, recursive = FALSE)
      if (length(remaining) == 0) {
        unlink(cd, recursive = TRUE)
      }
    }
    remaining_dirs <- list.dirs(user_dir, recursive = FALSE)
    if (length(remaining_dirs) == 0) {
      remaining_files <- list.files(user_dir, recursive = FALSE)
      if (length(remaining_files) == 0) {
        unlink(user_dir, recursive = TRUE)
      }
    }
  }

  cat(sprintf("[IMAGE_GALLERY] Toplam %d görsel silindi (kullanıcı: %s)\n", deleted_count, user_id))
  return(deleted_count)
}

#' Görsel silindikten sonra ilgili mesajı güncelle
#' @param image_path Silinen görselin dosya yolu
#' @param chat_id Sohbet ID
update_message_after_image_deletion <- function(image_path, chat_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(invisible(NULL))

  # chat_id'yi integer'a çevir (DB için)
  chat_id_int <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_id_int)) return(invisible(NULL))

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    filename <- basename(image_path)

    query <- "SELECT MessageID, MessageContent FROM MB_Messages WHERE ChatID = ? AND MessageContent LIKE ?"
    search_pattern <- paste0("%", filename, "%")
    rows <- DBI::dbGetQuery(conn, query, params = list(chat_id_int, search_pattern))

    if (nrow(rows) > 0) {
      for (j in seq_len(nrow(rows))) {
        old_content <- rows$MessageContent[j]
        new_content <- gsub(
          "^\\[GÖRSEL:[^\\]]*\\]",
          "[İlgili görsel kullanıcı tarafından silinmiştir]",
          old_content, perl = TRUE
        )
        if (new_content != old_content) {
          update_q <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
          DBI::dbExecute(conn, update_q, params = list(new_content, rows$MessageID[j]))
          cat(sprintf("[IMAGE_GALLERY] Mesaj güncellendi (MessageID: %s)\n", rows$MessageID[j]))
        }
      }
    }
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Mesaj güncelleme hatası:", e$message, "\n")
  })

  invisible(NULL)
}

#' Toplu silme sonrası sohbetteki tüm görsel mesajlarını güncelle
#' @param chat_id Sohbet ID
update_messages_after_bulk_deletion <- function(chat_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(invisible(NULL))

  chat_id_int <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_id_int)) return(invisible(NULL))

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    query <- "SELECT MessageID, MessageContent FROM MB_Messages WHERE ChatID = ? AND MessageContent LIKE '[GÖRSEL:%'"
    rows <- DBI::dbGetQuery(conn, query, params = list(chat_id_int))

    if (nrow(rows) > 0) {
      for (j in seq_len(nrow(rows))) {
        old_content <- rows$MessageContent[j]
        image_match <- regmatches(old_content, regexec("\\[GÖRSEL:([^\\]]+)\\]", old_content, perl = TRUE))[[1]]
        if (length(image_match) >= 2) {
          img_path <- image_match[2]
          # Görselin hâlâ var olup olmadığını kontrol et
          resolved <- NULL
          if (file.exists(img_path)) {
            resolved <- img_path
          } else {
            user_images_match <- regmatches(img_path, regexec("(user_images/.+)$", img_path))[[1]]
            if (length(user_images_match) >= 2) {
              candidate <- file.path(getwd(), user_images_match[2])
              if (file.exists(candidate)) resolved <- candidate
            }
          }

          # Dosya artık yoksa mesajı güncelle
          if (is.null(resolved)) {
            new_content <- gsub(
              "^\\[GÖRSEL:[^\\]]*\\]",
              "[İlgili görsel kullanıcı tarafından silinmiştir]",
              old_content, perl = TRUE
            )
            if (new_content != old_content) {
              update_q <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
              DBI::dbExecute(conn, update_q, params = list(new_content, rows$MessageID[j]))
            }
          }
        }
      }
    }
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Toplu mesaj güncelleme hatası:", e$message, "\n")
  })

  invisible(NULL)
}

#' Görsel dosya yolundan sohbet başlığını bul
#' @param chat_id Sohbet ID
#' @param user_id Kullanıcı ID
#' @return Sohbet başlığı veya NULL
get_chat_title_for_image <- function(chat_id, user_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(NULL)

  chat_id_int <- suppressWarnings(as.integer(chat_id))
  if (is.na(chat_id_int)) return(NULL)

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    query <- "SELECT ChatTitle FROM MB_Chats WHERE ChatID = ? AND UserID = ? AND IsDeleted = 0"
    result <- DBI::dbGetQuery(conn, query, params = list(chat_id_int, user_id))
    if (nrow(result) > 0) result$ChatTitle[1] else NULL
  }, error = function(e) {
    NULL
  })
}