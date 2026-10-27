# R/server_observers_storage.R
# Dosya Yolu: R/server_observers_storage.R
# Açıklama: LocalStorage ve sohbet kalıcılığı ile ilgili observer fonksiyonları.
# Tarayıcı deposu senkronizasyonu ve sohbet geri yükleme işlemlerini yönetir.

# Tarayıcıda saklanan sohbetin sahibini DOĞRULANMIŞ sunucu kimliğine bağlar.
# Etiket sunucu sırrıyla (HMAC) üretilir; istemci başka bir hesabın etiketini
# hesaplayamaz. Kimlik hazır değilse NULL döner (saklama/geri yükleme yapılmaz).
mergen_chat_storage_owner <- function(session, master = Sys.getenv("AI_KEYS_MASTER", "")) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (!is.environment(ud) || !isTRUE(ud$auth_initialized)) return(NULL)
  uid <- suppressWarnings(as.integer(as.character(ud$user_id %||% 0L)[1]))
  master <- as.character(master %||% "")[1]
  if (is.na(uid) || uid <= 0L || is.na(master) || !nzchar(master)) return(NULL)
  anahtar <- openssl::sha256(charToRaw(enc2utf8(paste0("mergen-chat-storage|", master))))
  paste(as.character(openssl::sha256(charToRaw(as.character(uid)), key = anahtar)), collapse = "")
}

# Tarayıcıya yalnızca sohbeti yeniden kurmak için gereken düz alanlar gider;
# HTML, kimlikler, akıl yürütme ve DB kimlikleri saklanmaz. Kayıt, geri
# yüklemenin kabul ettiği bütçeye sığan EN YENİ mesajlarla sınırlanır.
mergen_chat_storage_payload <- function(messages, max_messages = 200L,
                                        max_total_chars = 2000000L) {
  kayit <- Filter(Negate(is.null), lapply(messages, function(msg) {
    tur <- as.character(msg$type %||% "")[1]
    if (is.na(tur) || !tur %in% c("user", "ai", "assistant", "system")) return(NULL)
    if (isTRUE(msg$is_streaming)) return(NULL)
    list(type = tur, content = as.character(msg$content %||% "")[1],
         timestamp = as.character(msg$timestamp %||% "")[1],
         include_in_context = !isFALSE(msg$include_in_context))
  }))
  if (length(kayit) > max_messages) kayit <- utils::tail(kayit, max_messages)
  boyut <- vapply(kayit, function(m) {
    if (is.na(m$content)) 0 else as.numeric(nchar(m$content, type = "bytes"))
  }, numeric(1))
  sigan <- rev(cumsum(rev(boyut))) <= max_total_chars
  kayit[sigan]
}

# Tarayıcıdan gelen kayıt veridir: yalnızca doğrulanmış düz alanlar alınır,
# kimlik sunucuda üretilir ve görünen HTML kayıtlı-sohbet yoluyla aynı güvenli
# render sözleşmesiyle (db_message_process_text_content) yeniden üretilir.
mergen_chat_storage_restore_messages <- function(raw_messages,
                                                 max_messages = 200L,
                                                 max_chars = 200000L,
                                                 max_total_chars = 2000000L,
                                                 user_id = NULL) {
  if (!is.list(raw_messages) || length(raw_messages) == 0L ||
      length(raw_messages) > max_messages) {
    return(list())
  }
  # Toplam bütçe render'dan ÖNCE denetlenir: istemci girdiyi doğrudan gönderebilir.
  toplam <- sum(vapply(raw_messages, function(m) {
    icerik <- if (is.list(m)) m$content else NULL
    if (is.character(icerik) && length(icerik) == 1L && !is.na(icerik)) nchar(icerik, type = "bytes") else 0
  }, numeric(1)))
  if (toplam > max_total_chars) return(list())
  damga <- floor(as.numeric(Sys.time()) * 1000)
  sonuc <- list()
  for (i in seq_along(raw_messages)) {
    m <- raw_messages[[i]]
    if (!is.list(m)) next
    tur <- m$type
    icerik <- m$content
    if (!is.character(tur) || length(tur) != 1L || is.na(tur) ||
        !tur %in% c("user", "ai", "assistant", "system")) next
    if (!is.character(icerik) || length(icerik) != 1L || is.na(icerik) ||
        !isTRUE(validUTF8(icerik)) || nchar(icerik) > max_chars ||
        !nzchar(trimws(icerik))) next
    if (identical(tur, "assistant")) tur <- "ai"
    # Bağlam dışı tutulan mesaj (ör. hızlı eylem tanıtımı) yeniden yüklemede
    # model bağlamına girmez; yalnız mantıksal tekil değer kabul edilir.
    baglam <- m$include_in_context
    baglam <- !(is.logical(baglam) && length(baglam) == 1L && isFALSE(baglam))
    zaman <- m$timestamp
    zaman <- if (is.character(zaman) && length(zaman) == 1L && !is.na(zaman) &&
                 isTRUE(validUTF8(zaman)) && nchar(zaman) <= 64L) zaman else ""
    mesaj_id <- sprintf("msg_restore_%.0f_%d", damga, i)
    # Görsel mesajları kayıtlı-sohbet okuyucusuyla aynı yoldan (sahip kökü
    # denetimiyle) karta çevrilir; diğerleri güvenli metin render'ından geçer.
    islenmis <- db_message_process_image_content(icerik, tur, mesaj_id, user_id = user_id) %||%
      db_message_process_text_content(icerik, tur, mesaj_id)
    sonuc[[length(sonuc) + 1L]] <- list(
      id = mesaj_id, db_id = NULL, content = icerik,
      html_content = as.character(islenmis$html %||% ""),
      has_code = isTRUE(islenmis$has_code),
      type = tur, timestamp = zaman, include_in_context = baglam,
      tarayicidan_geri_yuklendi = TRUE
    )
  }
  sonuc
}

#' Depolama Gözlemcilerini Başlat
#' @description LocalStorage senkronizasyonu ve sohbet yükleme observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param output Shiny output nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param chat_rebind_all_charts Grafikleri yeniden bağlama fonksiyonu
storageObserversInit <- function(input, session, output, values, settings_data, 
                                  chat_rebind_all_charts) {
  
 
  # Sekme değişikliğini takip et
  observeEvent(input$last_active_tab, {
    updateTabItems(session, "tabs", selected = input$last_active_tab)
  })
  
  # Mesajlar değiştiğinde localStorage'a kaydet: yalnızca doğrulanmış sahip
  # etiketiyle ve en az veriyle. Kimlik yoksa tarayıcıya sohbet yazılmaz.
  # Doğrulanmış kullanıcı sohbeti boşalttığında (yeni sohbet) tarayıcı kaydı da
  # silinir; kimlik kaybında (sahip yok) aynı kullanıcının kurtarma kaydı kalır.
  # Bellekteki sohbet ilk kaydedildiği sahibe bağlanır: aynı oturumda kimlik
  # A -> B değişirse A'nın mesajları B'nin etiketiyle asla yazılmaz.
  sohbet_sahibi <- NULL
  observeEvent(values$messages, {
    sahip <- mergen_chat_storage_owner(session)
    if (length(values$messages) == 0) {
      sohbet_sahibi <<- NULL
      if (!is.null(sahip)) session$sendCustomMessage("clearCurrentChat", list())
      return(invisible(NULL))
    }
    if (is.null(sahip)) return(invisible(NULL))
    if (is.null(sohbet_sahibi)) sohbet_sahibi <<- sahip
    if (!identical(sohbet_sahibi, sahip)) {
      session$sendCustomMessage("clearCurrentChat", list())
      return(invisible(NULL))
    }
    session$sendCustomMessage("saveCurrentChat", list(
      owner = sahip,
      messages = mergen_chat_storage_payload(values$messages)
    ))
  }, ignoreNULL = FALSE, ignoreInit = TRUE)

  # Tarayıcı kaydı kimlik hazır olana kadar bekletilir; kimlik geldiğinde ya da
  # değiştiğinde aşağıdaki geri yükleme gözlemcisi yeniden değerlendirir.
  bekleyen_geri_yukleme <- reactiveVal(NULL)
  kimlik_sinyali <- mergen_session_identity_signal(session)

  observeEvent(input$load_chat_from_storage, {
    bekleyen_geri_yukleme(input$load_chat_from_storage)
  }, ignoreInit = TRUE)

  # localStorage'dan sohbet yükle
  observeEvent(list(bekleyen_geri_yukleme(), kimlik_sinyali()), {
    loaded_data <- bekleyen_geri_yukleme()
    req(loaded_data)
    sahip <- mergen_chat_storage_owner(session)
    if (is.null(sahip)) return(invisible(NULL))
    bekleyen_geri_yukleme(NULL)

    kayit_sahibi <- if (is.list(loaded_data)) loaded_data$owner else NULL
    if (!is.character(kayit_sahibi) || length(kayit_sahibi) != 1L ||
        !identical(kayit_sahibi, sahip)) {
      # Başka hesaba ait ya da sahipsiz (eski biçim) kayıt: yüklenmez, silinir.
      session$sendCustomMessage("clearCurrentChat", list())
      return(invisible(NULL))
    }

    # Sahip etiketi yalnızca doğrulanmış kimlikle üretildiği için user_id güvenilirdir.
    geri_yuklenen <- mergen_chat_storage_restore_messages(
      loaded_data$messages, user_id = session$userData$user_id
    )
    if (length(geri_yuklenen) == 0) return(invisible(NULL))
    if (length(values$messages) == 0) {

      # localStorage'dan geçmiş sohbet geri yüklenirken araç bağlamlı arka
      # plan animasyonu temizlenir; eski sohbet bağlamı yeni bir araç
      # tanıtımı değildir.
      tryCatch(
        session$sendCustomMessage("setToolBackgroundFamily", list(
          clear = TRUE,
          reason = "load_chat_from_storage"
        )),
        error = function(e) invisible(NULL)
      )

      removeUI(selector = "#chat_content_container > *", multiple = TRUE)
      
      values$messages <- geri_yuklenen
      values$show_welcome <- FALSE
      
      if (length(values$messages) > 0) {
        for (i in seq_along(values$messages)) {
          msg <- values$messages[[i]]
          is_last_user_msg <- (msg$type == "user" && i == length(values$messages))
          
          # Persona verisini al (eski kimlikler normalleştirilir)
          selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
          chars_data <- get_characters_data()
          character_data <- if (!is.null(chars_data)) {
            Find(function(x) x$id == selected_char_id, chars_data$styles)
          } else NULL
          
          ui_to_insert <- render_message_bubble_ui(
            msg, settings_data,
            is_last_user_message = is_last_user_msg,
            character_data = character_data,
            liked_ids = values$liked_messages,
            disliked_ids = values$disliked_messages
          )
          
          insertUI(selector = "#chat_content_container", where = "beforeEnd", ui = ui_to_insert)
          
          if (isTRUE(msg$has_code)) {
            wrapper_id <- paste0("message_wrapper_", msg$id)
            shinyjs::runjs(sprintf("setTimeout(() => { window.initializeCodeMirrorInElement('%s'); }, 200);", wrapper_id))
          }
        }
        shinyjs::runjs("setTimeout(() => { scrollToBottom(false); }, 100);")
        
        # Geçmiş sohbet yüklendiğinde grafikleri yeniden bağla
        chat_rebind_all_charts(session, output, values$messages)
      }
      
      showToast(session, "Önceki sohbetiniz geri yüklendi.", "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}