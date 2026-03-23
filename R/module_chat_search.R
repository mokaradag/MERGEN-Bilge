# Dosya Yolu: R/module_chat_search.R
# Açıklama:   Kayıtlı söyleşilerde içerik araması yapan modal modülü.
#              Kullanıcının girdiği arama terimini tüm sohbet mesajlarında arar
#              ve eşleşen sonuçları listeler.

# Türkçe karakter güvenli arama fonksiyonu
search_chats_content_from_db <- function(user_id, search_term) {
  # Boş arama terimini yoksay
  if (is.null(search_term) || !nzchar(trimws(search_term))) {
    return(data.frame(
      chat_id = character(),
      chat_title = character(),
      message_content = character(),
      message_type = character(),
      message_timestamp = character(),
      stringsAsFactors = FALSE
    ))
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # SQL Server'da LIKE ile içerik araması (sonuç limiti 1000)
  query <- "
    SELECT TOP 1000
      c.ChatID,
      c.ChatTitle,
      m.MessageContent,
      m.MessageType,
      m.MessageTimestamp
    FROM MB_Chats c
    INNER JOIN MB_Messages m ON c.ChatID = m.ChatID
    WHERE c.UserID = ?
      AND m.MessageContent LIKE ?
    ORDER BY m.MessageTimestamp DESC
  "

  # Arama terimi için joker karakter ekle
  like_term <- paste0("%", search_term, "%")

  result <- tryCatch({
    rows <- DBI::dbGetQuery(conn, query, params = list(user_id, like_term))
    if (is.null(rows) || nrow(rows) == 0) {
      return(data.frame(
        chat_id = character(),
        chat_title = character(),
        message_content = character(),
        message_type = character(),
        message_timestamp = character(),
        stringsAsFactors = FALSE
      ))
    }

    data.frame(
      chat_id = as.character(rows$ChatID),
      chat_title = rows$ChatTitle,
      message_content = rows$MessageContent,
      message_type = rows$MessageType,
      message_timestamp = as.character(rows$MessageTimestamp),
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    warning(sprintf("[CHAT_SEARCH] Veritabanı hatası: %s", e$message))
    data.frame(
      chat_id = character(),
      chat_title = character(),
      message_content = character(),
      message_type = character(),
      message_timestamp = character(),
      stringsAsFactors = FALSE
    )
  })

  return(result)
}

#' Sohbet İçerik Arama Modülü - Sunucu Başlatma
#' @description Kayıtlı söyleşilerde içerik araması yapan gözlemcileri başlatır
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param current_user_id Mevcut kullanıcı ID'si
#' @param load_chat_callback Sohbet yükleme fonksiyonu
chatSearchInit <- function(input, session, current_user_id, load_chat_callback) {

  # Arama sonuçları reaktif değeri
  search_results <- reactiveVal(NULL)
  search_active <- reactiveVal(FALSE)

  # Arama butonuna tıklanınca veya JS'den gelen arama isteği
  observeEvent(input$chat_search_query, {
    query <- input$chat_search_query
    if (is.null(query) || !nzchar(trimws(query$term %||% ""))) {
      search_results(NULL)
      return()
    }

    search_term <- trimws(query$term)
    search_active(TRUE)

    # Veritabanında ara
    results <- tryCatch(
      search_chats_content_from_db(current_user_id(), search_term),
      error = function(e) {
        warning(sprintf("[CHAT_SEARCH] Arama hatası: %s", e$message))
        NULL
      }
    )

    search_active(FALSE)

    if (is.null(results) || nrow(results) == 0) {
      # Sonuç bulunamadı mesajını JS'ye gönder
      session$sendCustomMessage("chatSearchResults", list(
        results = list(),
        term = search_term,
        count = 0
      ))
      return()
    }

    # Sonuçları sohbet bazında grupla
    grouped <- split(results, results$chat_id)
    formatted_results <- lapply(names(grouped), function(cid) {
      group <- grouped[[cid]]
      # Her sohbet için en fazla 3 eşleşme göster
      snippets <- lapply(seq_len(min(3, nrow(group))), function(i) {
        row <- group[i, ]
        content <- row$message_content
        # Eşleşen kısmın etrafını kes (snippet oluştur)
        # fixed = TRUE ile regex özel karakterlerinin (ör. C++ içindeki +) hata vermesi önlenir
        match_pos <- regexpr(search_term, content, ignore.case = TRUE, fixed = TRUE)
        if (match_pos > 0) {
          start <- max(1, match_pos - 80)
          end <- min(nchar(content), match_pos + attr(match_pos, "match.length") + 80)
          snippet <- substr(content, start, end)
          if (start > 1) snippet <- paste0("...", snippet)
          if (end < nchar(content)) snippet <- paste0(snippet, "...")
        } else {
          snippet <- substr(content, 1, 160)
          if (nchar(content) > 160) snippet <- paste0(snippet, "...")
        }
        # Zaman damgasını okunabilir formata çevir
        ts_formatted <- tryCatch({
          format(as.POSIXct(row$message_timestamp), "%d.%m.%Y %H:%M")
        }, error = function(e) row$message_timestamp)
        list(
          snippet = snippet,
          type = row$message_type,
          timestamp = ts_formatted
        )
      })

      list(
        chat_id = cid,
        chat_title = group$chat_title[1],
        match_count = nrow(group),
        snippets = snippets
      )
    })

    # Sonuçları JS'ye gönder
    session$sendCustomMessage("chatSearchResults", list(
      results = formatted_results,
      term = search_term,
      count = nrow(results)
    ))
  }, ignoreInit = TRUE)

  # Arama sonucundan sohbet yükleme isteği
  observeEvent(input$chat_search_load_chat, {
    chat_id <- input$chat_search_load_chat
    if (!is.null(chat_id) && nzchar(chat_id)) {
      # Modal'ı kapat (JS tarafında yapılıyor)
      if (is.function(load_chat_callback)) {
        load_chat_callback(chat_id)
      }
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}