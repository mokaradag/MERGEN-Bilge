# Dosya Yolu: R/helpers_image_gallery.R
# Gorsel galerisi icin yardimci fonksiyonlar - kullanici gorsellerini tarama, metadata toplama ve silme islemleri

#' Kullanicinin tum gorsellerini tara ve metadata topla
#' @param user_id Kullanici ID
#' @return data.frame: file_path, chat_id, filename, created_at, file_size, month_key, month_label
scan_user_images <- function(user_id) {
  base_dir <- file.path(getwd(), "user_images", as.character(user_id))

  if (!dir.exists(base_dir)) {
    return(data.frame(
      file_path = character(),
      chat_id = character(),
      filename = character(),
      created_at = as.POSIXct(character()),
      file_size = numeric(),
      month_key = character(),
      month_label = character(),
      stringsAsFactors = FALSE
    ))
  }

  image_files <- list.files(
    base_dir,
    pattern = "\\.(png|jpg|jpeg|gif|webp)$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(image_files) == 0) {
    return(data.frame(
      file_path = character(),
      chat_id = character(),
      filename = character(),
      created_at = as.POSIXct(character()),
      file_size = numeric(),
      month_key = character(),
      month_label = character(),
      stringsAsFactors = FALSE
    ))
  }

  month_map <- c(
    "January" = "Ocak", "February" = "\u015eubat", "March" = "Mart",
    "April" = "Nisan", "May" = "May\u0131s", "June" = "Haziran",
    "July" = "Temmuz", "August" = "A\u011fustos", "September" = "Eyl\u00fcl",
    "October" = "Ekim", "November" = "Kas\u0131m", "December" = "Aral\u0131k"
  )

  records <- lapply(image_files, function(fp) {
    fi <- file.info(fp)
    fname <- basename(fp)

    parts <- strsplit(gsub(paste0("^", gsub("([\\[\\]\\{\\}\\(\\)\\*\\+\\?\\.\\^\\$\\|\\\\])", "\\\\\\1", base_dir), "/"), "", fp), "/")[[1]]
    cid <- if (length(parts) >= 2) parts[1] else NA_character_

    created <- fi$mtime

    mk <- format(created, "%Y-%m")
    eng_month <- format(created, "%B")
    tr_month <- month_map[eng_month]
    if (is.na(tr_month)) tr_month <- eng_month
    ml <- paste0(tr_month, " ", format(created, "%Y"))

    data.frame(
      file_path = fp,
      chat_id = cid,
      filename = fname,
      created_at = created,
      file_size = fi$size,
      month_key = mk,
      month_label = ml,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, records)
  result <- result[order(result$created_at, decreasing = TRUE), , drop = FALSE]
  rownames(result) <- NULL
  return(result)
}

#' Gorsel dosyasini base64 thumbnail olarak yukle
#' @param file_path Gorsel dosya yolu
#' @param max_size Maksimum thumbnail boyutu (piksel)
#' @return Base64 data URL veya NULL
get_image_thumbnail_base64 <- function(file_path, max_size = 300) {
  if (is.null(file_path) || !file.exists(file_path)) return(NULL)
  tryCatch({
    img_data <- base64enc::base64encode(file_path)
    paste0("data:image/png;base64,", img_data)
  }, error = function(e) {
    NULL
  })
}

#' Tek bir gorseli sil ve ilgili mesaji guncelle
#' @param file_path Silinecek gorsel dosya yolu
#' @param user_id Kullanici ID
#' @param chat_id Sohbet ID
#' @return TRUE/FALSE
delete_single_image <- function(file_path, user_id, chat_id) {
  tryCatch({
    if (!file.exists(file_path)) {
      cat("[IMAGE_GALLERY] Gorsel zaten mevcut degil:", file_path, "\n")
      return(TRUE)
    }

    file.remove(file_path)
    cat("[IMAGE_GALLERY] Gorsel silindi:", file_path, "\n")

    update_message_after_image_deletion(file_path, chat_id)

    chat_dir <- file.path(getwd(), "user_images", as.character(user_id), as.character(chat_id))
    if (dir.exists(chat_dir)) {
      remaining <- list.files(chat_dir, recursive = FALSE)
      if (length(remaining) == 0) {
        unlink(chat_dir, recursive = TRUE)
        cat("[IMAGE_GALLERY] Bos klasor silindi:", chat_dir, "\n")
      }
    }

    return(TRUE)
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Gorsel silme hatasi:", e$message, "\n")
    return(FALSE)
  })
}

#' Kullanicinin tum gorsellerini sil
#' @param user_id Kullanici ID
#' @return Silinen gorsel sayisi
delete_all_user_images <- function(user_id) {
  images <- scan_user_images(user_id)
  if (nrow(images) == 0) return(0L)

  deleted_count <- 0L

  unique_chats <- unique(images$chat_id[!is.na(images$chat_id)])

  for (i in seq_len(nrow(images))) {
    row <- images[i, ]
    tryCatch({
      if (file.exists(row$file_path)) {
        file.remove(row$file_path)
        deleted_count <- deleted_count + 1L
      }
    }, error = function(e) {
      cat("[IMAGE_GALLERY] Toplu silme hatasi:", e$message, "\n")
    })
  }

  for (cid in unique_chats) {
    update_messages_after_bulk_deletion(cid)
  }

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

  cat(sprintf("[IMAGE_GALLERY] Toplam %d gorsel silindi (kullanici: %s)\n", deleted_count, user_id))
  return(deleted_count)
}

#' Gorsel silindikten sonra ilgili mesaji guncelle
#' @param image_path Silinen gorselin dosya yolu
#' @param chat_id Sohbet ID
update_message_after_image_deletion <- function(image_path, chat_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(invisible(NULL))

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    filename <- basename(image_path)

    query <- "SELECT MessageID, MessageContent FROM MB_Messages WHERE ChatID = ? AND MessageContent LIKE ?"
    search_pattern <- paste0("%", filename, "%")
    rows <- DBI::dbGetQuery(conn, query, params = list(chat_id, search_pattern))

    if (nrow(rows) > 0) {
      for (j in seq_len(nrow(rows))) {
        old_content <- rows$MessageContent[j]
        new_content <- gsub(
          "^\\[G\u00d6RSEL:[^\\]]*\\]",
          "[\u0130lgili g\u00f6rsel kullan\u0131c\u0131 taraf\u0131ndan silinmi\u015ftir]",
          old_content, perl = TRUE
        )
        if (new_content != old_content) {
          update_q <- "UPDATE MB_Messages SET MessageContent = ? WHERE MessageID = ?"
          DBI::dbExecute(conn, update_q, params = list(new_content, rows$MessageID[j]))
          cat(sprintf("[IMAGE_GALLERY] Mesaj guncellendi (MessageID: %s)\n", rows$MessageID[j]))
        }
      }
    }
  }, error = function(e) {
    cat("[IMAGE_GALLERY] Mesaj guncelleme hatasi:", e$message, "\n")
  })

  invisible(NULL)
}

#' Toplu silme sonrasi sohbetteki tum gorsel mesajlarini guncelle
#' @param chat_id Sohbet ID
update_messages_after_bulk_deletion <- function(chat_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(invisible(NULL))

  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    query <- "SELECT MessageID, MessageContent FROM MB_Messages WHERE ChatID = ? AND MessageContent LIKE '[G\u00d6RSEL:%'"
    rows <- DBI::dbGetQuery(conn, query, params = list(chat_id))

    if (nrow(rows) > 0) {
      for (j in seq_len(nrow(rows))) {
        old_content <- rows$MessageContent[j]
        image_match <- regmatches(old_content, regexec("\\[G\u00d6RSEL:([^\\]]+)\\]", old_content, perl = TRUE))[[1]]
        if (length(image_match) >= 2) {
          img_path <- image_match[2]
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

          if (is.null(resolved)) {
            new_content <- gsub(
              "^\\[G\u00d6RSEL:[^\\]]*\\]",
              "[\u0130lgili g\u00f6rsel kullan\u0131c\u0131 taraf\u0131ndan silinmi\u015ftir]",
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
    cat("[IMAGE_GALLERY] Toplu mesaj guncelleme hatasi:", e$message, "\n")
  })

  invisible(NULL)
}

#' Gorsel dosya yolundan sohbet basligini bul
#' @param chat_id Sohbet ID
#' @param user_id Kullanici ID
#' @return Sohbet basligi veya NULL
get_chat_title_for_image <- function(chat_id, user_id) {
  if (is.na(chat_id) || is.null(chat_id)) return(NULL)
  tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    query <- "SELECT ChatTitle FROM MB_Chats WHERE ChatID = ? AND UserID = ? AND IsDeleted = 0"
    result <- DBI::dbGetQuery(conn, query, params = list(chat_id, user_id))
    if (nrow(result) > 0) result$ChatTitle[1] else NULL
  }, error = function(e) {
    NULL
  })
}
