# R/module_chat_history.R (Updated with "Bugün" button functionality)

# Erişilebilir tarih aralığı girdisi üretir.
# Bootstrap datepicker yerine tarayıcının yerel tarih alanları kullanılır.
# Böylece Shiny'nin bootstrap-datepicker-js-1.9.0 bağımlılığı ve vendor
# deprecation uyarıları uygulama başlangıcında yüklenmez.
history_accessible_date_range_input <- function(ns) {
  input_id <- ns("date_range")
  start_id <- ns("date_range_start")
  end_id <- ns("date_range_end")
  label_id <- paste0(input_id, "-label")

  today <- Sys.Date()
  start_value <- format(today - 30, "%Y-%m-%d")
  end_value <- format(today, "%Y-%m-%d")

  tags$div(
    class = "history-native-date-range shiny-input-container",
    `data-shiny-input-id` = input_id,
    `aria-labelledby` = label_id,

    tags$div(
      "Tarih Aralığı:",
      id = label_id,
      class = "control-label history-date-range-label"
    ),

    tags$div(
      class = "history-native-date-fields",

      tags$label(
        "Başlangıç tarihi",
        `for` = start_id,
        class = "sr-only"
      ),
      tags$input(
        id = start_id,
        type = "date",
        class = "form-control history-native-date-input",
        value = start_value,
        # lang="tr-TR": tarayıcı tarih alanını gün/ay/yıl (dd/mm/yyyy) biçiminde
        # gösterir; varsayılan İngilizce yerel ay/gün/yıl (mm/dd/yyyy) yerine.
        lang = "tr-TR",
        `data-history-date-role` = "start",
        `aria-label` = "Başlangıç tarihi"
      ),

      tags$span(
        class = "history-native-date-separator",
        " - "
      ),

      tags$label(
        "Bitiş tarihi",
        `for` = end_id,
        class = "sr-only"
      ),
      tags$input(
        id = end_id,
        type = "date",
        class = "form-control history-native-date-input",
        value = end_value,
        lang = "tr-TR",
        `data-history-date-role` = "end",
        `aria-label` = "Bitiş tarihi"
      )
    )
  )
}

historyUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("Söyleşi Geçmişi", class = "page-title"),
        div(
          class = "history-actions",
          actionButton(ns("refresh_history"), label = tagList(icon("sync-alt"), "Yenile"), class = "btn-modern btn-refresh"),
          actionButton(ns("today_filter"), label = tagList(icon("calendar-day"), "Bugün"), class = "btn-modern btn-info"),
          downloadButton(ns("export_history"), label = "Excel'e Aktar", class = "btn-modern btn-success")
        )
      ),
      div(
        class = "scrollable-content",
		div(
		  class = "history-controls date-filter dark-date-picker",
		  history_accessible_date_range_input(ns)
		),
        div(
          class = "history-table-card",
		  tags$style(HTML(sprintf("#%s table.dataTable thead th { text-align: center !important; }", ns("history_table")))),
          DTOutput(ns("history_table"))
        )
      )
    )
  )
}

historyServer <- function(id, all_messages, current_user_id = NULL) {
  moduleServer(id, function(input, output, session) {
  
    resolve_current_user_id <- function() {
      uid <- if (is.function(current_user_id)) {
        tryCatch(current_user_id(), error = function(e) NULL)
      } else {
        current_user_id
      }

      session_uid <- session$userData$user_id %||% NULL
      uid <- suppressWarnings(as.integer(session_uid %||% uid %||% 0L))
      if (is.na(uid)) uid <- 0L
      uid
    }
    
    trigger_refresh <- reactiveVal(0)
	messages_cache <- reactiveVal(list())
    latest_chats <- reactiveVal(list())
    # Önbellek nesli: zorla yenileme, tarih aralığı ve sahip değişimi nesli
    # artırır; eski nesle ait ertelenmiş partiler önbelleğe yazamaz.
    isitma <- new.env(parent = emptyenv())
    isitma$nesil <- 0L
    isitma$aktif <- FALSE
    isitma$planli <- character()
    # Zincir: bu nesilde planlanan kimlik -> planlandığı andaki damga.
    isitma$zincir <- character()
    # Isıtma sürerken gelen senkronizasyonların hazır-olma geri çağrıları;
    # zincir tamamlanınca nihai sonuçla çağrılır (erken "hazır" bildirilmez).
    isitma$bekleyenler <- list()
    # Geçmiş etkinleştirildi mi (sekme ziyareti/yenileme/hazırlık): önbellek
    # uzunluğundan ayrı tutulur; başarısız okuma önbelleği boşaltsa da liste
    # değişince senkronizasyon sürer (açık sayfa boş kalmaz).
    isitma$etkin <- FALSE
    # Söyleşi başına önbellek yazım sürümü (history_touch): eşzamansız
    # hazırlık, gönderimden sonra yazılan/düşürülen söyleşinin üzerine yazamaz.
    isitma$surum <- integer()

    stamp_for_chat <- function(chat_info) {
      stamp_obj <- chat_info$last_message_timestamp %||% chat_info$timestamp %||% NA
      zaman <- if (inherits(stamp_obj, "POSIXt")) {
        format(stamp_obj, "%Y-%m-%d %H:%M:%S", tz = "UTC")
      } else {
        as.character(stamp_obj %||% "")
      }
      # Saniye çözünürlüğü aynı saniyedeki yeni mesajı kaçırıyordu; mesaj sayısı
      # da damgaya katılır.
      sayi <- chat_info$message_count %||% length(chat_info$messages %||% list())
      paste0(as.character(zaman)[1], "#", as.character(sayi)[1])
    }

    history_chat_activity_day_num <- function(chat_info) {
      stamp_obj <- chat_info$last_message_timestamp %||% chat_info$timestamp %||% NA

      if (inherits(stamp_obj, "POSIXt")) {
        return(as.numeric(as.Date(stamp_obj)))
      }

      if (inherits(stamp_obj, "Date")) {
        return(as.numeric(stamp_obj))
      }

      stamp_chr <- as.character(stamp_obj %||% "")
      if (!nzchar(stamp_chr) || is.na(stamp_chr)) {
        return(NA_real_)
      }

      parsed_time <- suppressWarnings(as.POSIXct(
        stamp_chr,
        tz = Sys.timezone(),
        tryFormats = c(
          "%Y-%m-%d %H:%M:%S",
          "%Y-%m-%d %H:%M",
          "%Y-%m-%d",
          "%d.%m.%Y - %H:%M",
          "%d.%m.%Y %H:%M",
          "%d/%m/%Y"
        )
      ))

      if (!is.na(parsed_time)) {
        return(as.numeric(as.Date(parsed_time)))
      }

      parsed_date <- suppressWarnings(as.Date(
        stamp_chr,
        tryFormats = c("%Y-%m-%d", "%d.%m.%Y", "%d/%m/%Y")
      ))

      if (!is.na(parsed_date)) {
        return(as.numeric(parsed_date))
      }

      NA_real_
    }
	
    history_normalize_date_range <- function(date_range) {
      if (is.null(date_range)) {
        return(NULL)
      }

      values <- unlist(date_range, use.names = FALSE)
      if (length(values) != 2L) {
        return(NULL)
      }

      values <- trimws(as.character(values))
      if (any(!nzchar(values))) {
        return(NULL)
      }

      parsed <- suppressWarnings(as.Date(
        values,
        tryFormats = c("%Y-%m-%d", "%d/%m/%Y", "%d.%m.%Y")
      ))

      if (any(is.na(parsed))) {
        return(NULL)
      }

      if (parsed[1] > parsed[2]) {
        parsed <- rev(parsed)
      }

      parsed
    }

    history_chat_ids_for_date_range <- function(chats, date_range = NULL) {
      all_chat_ids <- setdiff(names(chats %||% list()), "current_chat")

      if (length(all_chat_ids) == 0L) {
        return(character(0))
      }

      active_date_range <- history_normalize_date_range(date_range)

      if (is.null(active_date_range)) {
        return(all_chat_ids)
      }

      start_num <- as.numeric(active_date_range[1])
      end_num <- as.numeric(active_date_range[2])

      chat_days <- vapply(
        all_chat_ids,
        function(chat_id) history_chat_activity_day_num(chats[[chat_id]]),
        numeric(1)
      )

      all_chat_ids[!is.na(chat_days) & chat_days >= start_num & chat_days <= end_num]
    }

    build_history_rows <- function(chat_title, messages) {
      if (length(messages) == 0) {
        return(list())
      }

      user_messages <- messages[sapply(messages, function(x) x$type == "user")]
      ai_messages <- messages[sapply(messages, function(x) x$type %in% c("ai", "assistant"))]

      if (length(user_messages) == 0 || length(ai_messages) == 0) {
        return(list())
      }

      n <- min(length(user_messages), length(ai_messages))
      lapply(seq_len(n), function(i) {
        list(
          Chat_ID = chat_title,
          Tarih = user_messages[[i]]$timestamp,
          Soru = substr(user_messages[[i]]$content, 1, 100),
          Cevap = substr(ai_messages[[i]]$content, 1, 100)
        )
      })
    }

	ensure_history_cache <- function(chat_ids, chats, invalidate = TRUE) {
      # Okunacak söyleşi yoksa (boş geçmiş ya da hepsi önbellekte) bu başarıdır.
      if (length(chat_ids) == 0) {
        return(invisible(TRUE))
      }

      cache <- messages_cache()
      to_fetch <- character()
      stamp_map <- list()

      normalized_ids <- as.character(chat_ids)
      normalized_ids <- normalized_ids[nzchar(normalized_ids)]

      for (chat_id in normalized_ids) {
        chat_info <- chats[[chat_id]]
        if (is.null(chat_info)) next
		
		if (identical(chat_id, "current_chat")) {
          if (!is.null(chat_info$messages) && length(chat_info$messages) > 0) {
            rows <- build_history_rows(chat_info$title %||% chat_id, chat_info$messages)
            cache[[chat_id]] <- list(rows = rows, stamp = Sys.time())
          }
          next
        }

        stamp_key <- stamp_for_chat(chat_info)
        stamp_map[[chat_id]] <- stamp_key

        # Damgası eşleşen kayıt (boş geçmiş dahil) isabettir; başarısız okumalar
        # önbelleğe yazılmadığından burada yoktur ve yeniden denenir.
        cached <- cache[[chat_id]]
        if (!is.null(cached) && identical(cached$stamp, stamp_key)) {
          next
        }

        to_fetch <- c(to_fetch, chat_id)
      }

      basarili <- TRUE
      cache_onceki <- cache
      if (length(to_fetch) > 0) {
        fetched <- try(
          load_history_rows_batch(
            to_fetch,
            user_id = resolve_current_user_id()
          ),
          silent = TRUE
        )

        # Hata ya da hiç çalışmayan okuma (geçersiz kimlik -> list()) boş geçmiş
        # olarak önbelleğe ALINMAZ: "başarısız" ile "gerçekten boş" ayrı kalır.
        # Yükleyici istenen her kimliği (boşsa list()) döndürür; sonuçta
        # bulunmayan kimlik okunamamış sayılır. Okunamayan söyleşinin damgası
        # eşleşmeyen eski satırları da düşer: bayat geçmiş güncelmiş gibi
        # gösterilmez, sonraki ziyarette yeniden denenir.
        okunan <- if (inherits(fetched, "try-error")) character() else intersect(to_fetch, names(fetched))
        if (length(okunan) < length(to_fetch)) basarili <- FALSE
        for (chat_id in setdiff(to_fetch, okunan)) cache[[chat_id]] <- NULL
        okuma_zamani <- Sys.time()
        for (chat_id in okunan) {
          pairs <- fetched[[chat_id]]
          cache[[chat_id]] <- list(
            rows = if (is.list(pairs)) pairs else list(),
            stamp = stamp_map[[chat_id]],
            okuma = okuma_zamani,
            liste_baslik = chats[[chat_id]]$title %||% NULL
          )
        }
        # Yalnızca BAŞARILI yazım ve gerçekten düşen eski kayıt yeni sürümdür.
        # Okunamayan ve önbellekte olmayan kayıt sürüm artırmaz: süren açılış
        # hazırlığının başarılı (damgası eşleşen) sonucu bu yüzden atılmaz.
        history_touch(isitma, c(okunan, intersect(setdiff(to_fetch, okunan), names(cache_onceki))))
      }

      messages_cache(cache)
      if (isTRUE(invalidate) && length(to_fetch) > 0) {
        trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
      }
      invisible(basarili)
    }

    # Önbelleği geçersiz kılar: süren arka plan planı artık yazamaz.
    gecersiz_kil <- function() {
      isitma$nesil <- isitma$nesil + 1L
      isitma$aktif <- FALSE
      isitma$planli <- character()
      isitma$zincir <- character()
      isitma$bekleyenler <- list()
    }

    # Tek senkronizasyon girişi: en çok 60 eksik/bayat söyleşi eşzamanlı (tek
    # sorgu) alınır; daha fazlası nesil korumalı arka plan partileriyle (ilk
    # parti bir sonraki döngü turunda, tetikleyici olay döngüsünü tutmaz).
    # Hiçbir gözlemci olay döngüsünde sınırsız eşzamanlı SQL çalıştıramaz; ara
    # partiler tabloyu yeniden çizmez, yayın sonda tek seferdir. Isıtma
    # sürerken yeni gelen (planlanmamış) söyleşiler en çok 60'lık tek turda alınır.
    history_sync <- function(chat_ids, chats, on_done = NULL, date_range = NULL, devam = FALSE) {
      isitma$etkin <- TRUE
      etkin_aralik <- history_normalize_date_range(date_range)
      gerekli <- history_ids_needing_fetch(chat_ids, chats, shiny::isolate(messages_cache()), stamp_for_chat)
      if (isTRUE(isitma$aktif)) {
        gerekli <- setdiff(gerekli, isitma$planli)
        if (length(gerekli)) {
          gerekli_damga <- history_stamps(gerekli, chats, stamp_for_chat)
          gerekli <- gerekli[is.na(isitma$zincir[gerekli]) | unname(isitma$zincir[gerekli]) != unname(gerekli_damga)]
        }
      }
      if (length(gerekli) <= 60L || isTRUE(isitma$aktif)) {
        parti <- utils::head(gerekli, 60L)
        if ((isTRUE(isitma$aktif) || isTRUE(devam)) && length(parti)) {
          isitma$zincir[parti] <- history_stamps(parti, chats, stamp_for_chat)
        }
        basarili <- ensure_history_cache(parti, chats, invalidate = TRUE)
        if (is.function(on_done)) {
          if (isTRUE(isitma$aktif)) {
            isitma$bekleyenler <- c(isitma$bekleyenler, list(on_done))
          } else {
            on_done(basarili)
          }
        }
        return(invisible(basarili))
      }
      kalan <- gerekli
      basarili <- TRUE
      isitma$aktif <- TRUE
      isitma$planli <- kalan
      if (isTRUE(devam)) {
        isitma$zincir[kalan] <- history_stamps(kalan, chats, stamp_for_chat)
      } else {
        isitma$zincir <- history_stamps(kalan, chats, stamp_for_chat)
      }
      nesil <- isitma$nesil
      historyBackgroundWarm(
        session, kalan, chats,
        ensure_history_cache = function(parti, chats) {
          guncel <- shiny::isolate(latest_chats())
          havuz <- if (!is.null(etkin_aralik)) history_chat_ids_for_date_range(guncel, etkin_aralik) else aralik_kimlikleri()
          okunacak <- intersect(parti, havuz)
          if (length(okunacak)) isitma$zincir[okunacak] <- history_stamps(okunacak, guncel, stamp_for_chat)
          ensure_history_cache(okunacak, guncel, invalidate = FALSE)
        },
        batch_size = 60L, delay_sec = 0.05,
        is_current = function() identical(isitma$nesil, nesil),
        on_complete = function(tamam) {
          if (!identical(isitma$nesil, nesil)) return(invisible(NULL))
          isitma$aktif <- FALSE
          isitma$planli <- character()
          bekleyenler <- c(if (is.function(on_done)) list(on_done), isitma$bekleyenler)
          isitma$bekleyenler <- list()
          trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
          guncel <- shiny::isolate(latest_chats())
          havuz <- if (!is.null(etkin_aralik)) history_chat_ids_for_date_range(guncel, etkin_aralik) else aralik_kimlikleri()
          adaylar <- history_ids_needing_fetch(havuz, guncel, shiny::isolate(messages_cache()), stamp_for_chat)
          yeni <- if (length(adaylar)) {
            aday_damga <- history_stamps(adaylar, guncel, stamp_for_chat)
            adaylar[is.na(isitma$zincir[adaylar]) | unname(isitma$zincir[adaylar]) != unname(aday_damga)]
          } else character()
          bitir <- function(ok = TRUE) {
            isitma$zincir <- character()
            guncel_son <- shiny::isolate(latest_chats())
            son_havuz <- if (!is.null(etkin_aralik)) history_chat_ids_for_date_range(guncel_son, etkin_aralik) else aralik_kimlikleri()
            son <- history_all_cached(son_havuz, guncel_son, shiny::isolate(messages_cache()), stamp_for_chat)
            for (fn in bekleyenler) fn(isTRUE(son))
          }
          if (length(yeni)) history_sync(yeni, guncel, on_done = bitir, date_range = etkin_aralik, devam = TRUE) else bitir()
        }
      )
      invisible(basarili)
    }
	
    refresh_history_cache <- function(chats = latest_chats(), force = FALSE, date_range = NULL,
                                      on_done = hazir_bildir) {
      chats <- chats %||% list()

      active_date_range <- history_normalize_date_range(
        date_range %||% shiny::isolate(input$date_range)
      )
      chat_ids <- history_chat_ids_for_date_range(chats, active_date_range)
      # Kullanıcı eylemi (Yenile/Bugün/tarih) ya da etkin sayfanın senkronu.
      isitma$etkin <- TRUE

      if (isTRUE(force)) {
        gecersiz_kil()
        messages_cache(list())
        # Sıfırlama hemen yayımlanır: tablo ve dışa aktarma eski görüntüyü
        # yeni satırlar gelene dek "güncel" diye göstermez.
        trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
      } else {
        cache <- shiny::isolate(messages_cache())
        if (length(cache) > 0) {
          keep_ids <- intersect(names(cache), chat_ids)
          if (length(keep_ids) < length(cache)) {
            messages_cache(cache[keep_ids])
            trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
          }
        }
      }

      if (length(chat_ids) == 0) {
        trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
        if (is.function(on_done)) on_done(TRUE)
        return(invisible(TRUE))
      }

      # Zorla yenileme süren ısıtmayı geçersiz kılar; hazır-olma bu senkronizasyonun
      # sonucuyla bildirilir (bekleyen geri çağrılar düşmüş olur).
      history_sync(chat_ids, chats, on_done = on_done, date_range = active_date_range)
    }

    # Bugün düğmesi: yerel tarih alanlarını istemci tarafında günceller;
    # bildirim partiler tamamlandıktan sonra gösterilir.
    observeEvent(input$today_filter, {
      today <- Sys.Date()
      today_value <- format(today, "%Y-%m-%d")

      session$sendCustomMessage(
        type = "history-date-range-set",
        message = list(
          inputId = session$ns("date_range"),
          start = today_value,
          end = today_value
        )
      )

      refresh_history_cache(
        chats = latest_chats(),
        force = TRUE,
        date_range = c(today, today),
        on_done = history_refresh_notifier(
          session, hazir_bildir, showToast,
          tam_mesaj = "Bugünün kayıtları gösteriliyor.",
          kismen_mesaj = "Bugünün kayıtları kısmen yüklendi; okunamayanlar yeniden denenecek."
        )
      )
    })
	
    observeEvent(all_messages(), {
      chats <- all_messages() %||% list()
      latest_chats(chats)

      # Geçmiş sekmesi henüz açılmadıysa başlangıçta ağır ön yükleme yapma.
      # Kullanıcı geçmişi ilk kez açtığında veya elle yenilediğinde doldurulacak.
      # Arka plan hazırlığının doldurduğu önbellek etkinleştirme sayılmaz.
      if (isTRUE(isitma$etkin)) {
        refresh_history_cache(
          chats = chats,
          force = FALSE,
          date_range = history_normalize_date_range(shiny::isolate(input$date_range))
        )
      }
    }, ignoreNULL = FALSE, priority = 1)

    observeEvent(input$date_range, {
      active_date_range <- history_normalize_date_range(input$date_range)
      req(!is.null(active_date_range))
      # Sayfa yüklenirken istemcinin gönderdiği ilk aralık geçmişi ETKİNLEŞTİRMEZ:
      # okuma kullanıcı Geçmiş'i açınca ya da yenileme isteyince yapılır.
      # Tablo aralığı filtered_history() içinde reaktif olarak okur.
      if (!isTRUE(isitma$etkin)) return(invisible(NULL))

      refresh_history_cache(
        chats = latest_chats(),
        force = TRUE,
        date_range = active_date_range
      )
    }, ignoreInit = TRUE)
	
    filtered_history <- reactive({
      req(all_messages())
      trigger_refresh()

      history_list <- list()
      chats <- all_messages()
      chat_ids <- names(chats)

      # Önbellek yalnızca trigger_refresh ile yayınlanır: arka plan partilerinin
      # her yazımı büyüyen tabloyu yeniden kurup sıralatmaz.
      cache <- shiny::isolate(messages_cache())
      for (chat_id in chat_ids) {
        cached <- cache[[chat_id]]
        if (!is.null(cached) && length(cached$rows) > 0) {
          satirlar <- cached$rows
          # Liste başlığı yalnızca okuma sonrasındaki yerel değişiklikte uygulanır;
          # Yenile ile DB'den gelen taze başlık eski oturum başlığıyla ezilmez.
          baslik <- chats[[chat_id]]$title
          liste_degisti <- is.null(cached$liste_baslik) || !identical(baslik, cached$liste_baslik)
          if (isTRUE(liste_degisti) && is.character(baslik) && length(baslik) == 1L && !is.na(baslik) && nzchar(baslik)) {
            satirlar <- lapply(satirlar, function(r) { r$Chat_ID <- baslik; r })
          }
          history_list <- c(history_list, satirlar)
        }
	  }

      if (length(history_list) == 0) {
        return(data.frame(
          Chat_ID = character(0),
          Tarih = character(0),
          Soru = character(0),
          Cevap = character(0)
        ))
      }

      history_data <- data.table::rbindlist(history_list)

      # Tarih filtresini yerel tarih aralığı girdisine göre uygula.
      active_date_range <- history_normalize_date_range(input$date_range)

      if (!is.null(active_date_range) && length(active_date_range) == 2L) {
        dates <- tryCatch(
          as.Date(history_data$Tarih, format = "%d.%m.%Y - %H:%M"),
          error = function(e) as.Date(NA)
        )

        if (any(!is.na(dates))) {
          mask <- dates >= active_date_range[1] & dates <= active_date_range[2]
          history_data <- history_data[mask & !is.na(mask), ]
        }
      }

      # Sort by date
      if (nrow(history_data) > 0) {
        history_data[, sort_ts := as.POSIXct(Tarih, format = "%d.%m.%Y - %H:%M", tz = Sys.timezone())]
        data.table::setorder(history_data, -sort_ts)
        history_data[, sort_ts := NULL]
      }

      return(history_data)
    })
    
    output$history_table <- DT::renderDT({
      DT::datatable(
        filtered_history(),
        colnames = c("Söyleşi Adı", "Tarih", "Soru", "Cevap"),
        escape = TRUE,
        class = "display compact stripe hover dark-table",
        options = list(
          selection = "none",
          pageLength = 10,
          lengthMenu = list(c(5, 10, 25, 50, -1), c('5', '10', '25', '50', 'Tümü')),
          dom = 'lfrtip',
          responsive = TRUE,
          language = list(
            search = "Ara:",
            lengthMenu = "Sayfa başına _MENU_ kayıt göster",
            paginate = list(first = "İlk", last = "Son", previous = "Önceki", `next` = "Sonraki"),
            emptyTable = "Gösterilecek sohbet geçmişi yok",
            zeroRecords = "Filtre ile eşleşen kayıt bulunamadı",
            info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
            infoEmpty = "0 kayıt gösteriliyor",
            infoFiltered = "(_MAX_ kayıt içerisinden filtrelendi)"
          ),
          columnDefs = list(
            list(className = 'dt-center', targets = '_all')
          )
        ),
        rownames = FALSE
      ) %>%
        formatStyle(
          columns = 1:4,
          color = '#e6e6e6',
          backgroundColor = 'transparent'
        )
    })
    
	# Gizli Geçmiş sayfası arka plan hazırlığının yayınlarıyla yeniden kurulmaz;
	# tablo sayfa görünür olunca çizilir (dışa aktarma filtered_history()'yi
	# doğrudan çağırır, etkilenmez).
	outputOptions(output, "history_table", suspendWhenHidden = TRUE)
	
    output$export_history <- downloadHandler(
      filename = function() {
        paste0("mergen_sohbet_gecmisi_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
      },
      content = function(file) {
        export_data <- filtered_history()
        
        if (nrow(export_data) == 0) {
          export_data <- data.frame(Bilgi = "Dışa aktarılacak veri bulunamadı.")
        }
        
        writexl::write_xlsx(export_data, file)
      }
    )
    
    # Başarı bildirimi yeni satırlar yayımlandıktan SONRA gösterilir (partili
    # yenilemede zincir sonu); okunamayan söyleşi varsa "kısmen" denir.
    observeEvent(input$refresh_history, {
      refresh_history_cache(force = TRUE, on_done = history_refresh_notifier(session, hazir_bildir, showToast))
    })

    # Dürüst hazır-olma: yalnızca tam söyleşi listesi yüklendikten sonra; okuma
    # başarısızsa kontrol noktası "kısmen" (degraded) olarak bildirilir.
    hazir_bildir <- function(basarili = TRUE) {
      isaretle <- session$userData$mergen_yonetim_hazir
      if (is.function(isaretle) && isTRUE(session$userData$saved_chats_full_loaded)) {
        # Hazırlık söyleşi etkinliğine göre en yeni 60 söyleşiyi kapsar; tablo
        # istem tarihine göre sıralandığı için bu "ilk sayfa" kanıtı değildir.
        isaretle("history_rows_ready",
                 if (isTRUE(basarili)) "Söyleşi geçmişi hazırlandı (en yeni 60 söyleşi)"
                 else "Söyleşi geçmişi kısmen hazır; okunamayanlar yeniden denenecek",
                 detail = list(count = length(shiny::isolate(messages_cache())),
                               kapsam = "en_yeni_60_soylesi",
                               degraded = !isTRUE(basarili)))
      }
    }
    # Aralık uygunluğu liste ya da tarih aralığı değişene dek önbellekte kalır:
    # binlerce söyleşide her ısıtma partisi tüm etkinlik tarihlerini yeniden
    # değerlendirmez. Partiler yine güncel sonuçla kesiştirilir.
    aralik_reaktif <- shiny::reactive({
      history_chat_ids_for_date_range(latest_chats(), history_normalize_date_range(input$date_range))
    })
    aralik_kimlikleri <- function() shiny::isolate(aralik_reaktif())

    # Yerinde içerik düzenlemesi (galeriden görsel silme) damgayı değiştirmez;
    # ilgili kayıtlar düşer ve tablo yeniden yayınlanır (silinmiş görselin
    # alıntısı tabloda kalmaz). Düşen söyleşiler sonraki ziyarette okunur.
    # Düşürme, önbellekte olmasa da söyleşinin sürümünü artırır: uçuştaki
    # hazırlık okuması düşürülen satırları geri yazamaz; ısıtma nesli korunur.
    session$userData$mergen_gecmis_onbellek_dusur <- history_cache_dropper(messages_cache, yayin_sayaci = trigger_refresh,
                                                                           isitma = isitma)

    # Sahip değişiminde eski sahibin önbelleği ve süren planı düşer.
    # Sekme hâlâ açıksa yeni sahibin listesi gelince senkronizasyon etkin kalır.
    if (exists("mergen_session_on_owner_change", mode = "function", inherits = TRUE)) {
      mergen_session_on_owner_change(session, function(neden) {
        gecersiz_kil()
        acik_sekme <- try(shiny::isolate(session$rootScope()$input$tabs), silent = TRUE)
        if (!identical(acik_sekme, "history")) {
          isitma$etkin <- FALSE
        }
        messages_cache(list())
      })
    }

    # Arka plan hazırlığı SINIRLIDIR ve olay döngüsünü tutmaz: yalnızca en yeni
    # 60 söyleşinin eksik/bayat satırları mevcut açık işçi sınırında tek
    # sorguyla okunur (DB beklemesi ana süreçte olmaz, süre bütçelidir). Sonuç,
    # gönderimdeki önbellek nesli ve sahip hâlâ geçerliyse gönderim anındaki
    # damgalarla yazılır; damgası arada değişen söyleşi sonraki ziyarette
    # yeniden okunur. Kimlik yoksa okuma yapılmaz, durum "kısmen" bildirilir.
    # Hazırlık tetiği açılışın tam liste neslini taşır; önceki sahibe/yüklemeye
    # ait ertelenmiş (boşta çalışan) tetik yeni sahip için hazırlık başlatmaz.
    # Sonuç, gönderilen kimliklerden değil GÜNCEL ilk 60 söyleşiden türetilir:
    # arada eklenen söyleşi eksikse "kısmen", silinen söyleşi eksik sayılmaz.
    observeEvent(input$hazirla, {
      gecerli_tetik <- session$userData$mergen_gecmis_hazirla_gecerli
      if (is.function(gecerli_tetik) && !isTRUE(gecerli_tetik(input$hazirla))) return(invisible(NULL))
      chats <- latest_chats()
      ids <- history_ids_needing_fetch(utils::head(aralik_kimlikleri(), 60L), chats,
                                       messages_cache(), stamp_for_chat)
      if (!length(ids)) return(hazir_bildir(TRUE))
      # İşçi hazır değilse (sequential yedek) otomatik hazırlık olay döngüsünü
      # bloklamaz; hazır-olma dürüstçe kısmen kapanır, ilk sekme ziyareti korunur.
      if (exists("mergen_startup_async_worker_ready", mode = "function", inherits = TRUE) &&
          !isTRUE(mergen_startup_async_worker_ready())) {
        return(hazir_bildir(FALSE))
      }
      liste_basliklar <- stats::setNames(lapply(ids, function(id) chats[[id]]$title %||% NULL), ids)
      history_prepare_rows_async(session, ids, history_stamps(ids, chats, stamp_for_chat),
                                 uid = resolve_current_user_id(), isitma = isitma,
                                 resolve_uid = resolve_current_user_id, messages_cache = messages_cache,
                                 yayin_sayaci = trigger_refresh,
                                 bildir = history_first_page_notifier(hazir_bildir, aralik_kimlikleri, latest_chats,
                                                                      messages_cache, stamp_for_chat),
                                 guncel_sohbetler = latest_chats, damga_fn = stamp_for_chat,
                                 liste_basliklar = liste_basliklar)
      invisible(NULL)
    }, ignoreInit = TRUE)

    # Sekme açılışı (parent session'dan gelen sinyal). Önbellek KORUNUR: yalnızca
    # eksik, damgası değişen veya önceki okuması başarısız olan söyleşiler
    # çekilir (ilk 60 eşzamanlı, kalanı partilerle). Tam yenileme yalnızca
    # kullanıcının "Yenile"/"Bugün"/tarih eylemlerindedir.
    # Başka oturumdaki yerinde içerik düzenlemesi (galeriden görsel silme)
    # damgayı değiştirmez; sekme açılışında ilk sayfanın (en çok 60) planlı
    # olmayan yaşlı kayıtları ısıtma sürerken bile yeniden doğrulanır.
    observeEvent(input$external_refresh_trigger, {
      kimlikler <- aralik_kimlikleri()
      dogrulanacak <- setdiff(
        utils::head(kimlikler, 60L),
        if (isTRUE(isitma$aktif)) isitma$planli else character()
      )
      if (length(dogrulanacak)) {
        messages_cache(history_mark_stale_for_revalidation(
          shiny::isolate(messages_cache()), dogrulanacak,
          getOption("mergen.history_revalidate_secs", 60)))
      }
      history_sync(kimlikler, latest_chats(), on_done = hazir_bildir)
    }, ignoreInit = TRUE)
  })
}

showToast <- function(session, message, type = 'info', duration = NULL) {
  # Süre varsayılan olarak gönderilmez; istemci (toast.js) mesaj uzunluğuna göre
  # okunabilir bir süre hesaplar (kısa ~5 sn, uzun en fazla 12 sn). Açık süre
  # verilirse iletilir ve istemci ona uyar.
  payload <- list(message = message, type = type)
  if (!is.null(duration)) {
    payload$duration <- duration
  }
  session$sendCustomMessage(type = 'showToast', message = payload)
}