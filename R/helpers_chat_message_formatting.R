# ==============================================================================
# Dosya Yolu: R/helpers_chat_message_formatting.R
# Açıklama: Veritabanından okunan sohbet mesajlarını uygulama içi mesaj nesnesine
#           dönüştüren yardımcıları içerir. Görsel mesajları, Chartlab blokları,
#           markdown HTML çıktısı, zaman damgası ve reasoning alanları burada
#           biçimlendirilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# Görsel dosyasını base64 data-uri olarak hazırlar.
# ------------------------------------------------------------------------------
db_message_get_image_base64 <- function(file_path) {
  if (is.null(file_path) || length(file_path) != 1L || !nzchar(file_path)) {
    return(NULL)
  }

  if (!file.exists(file_path)) {
    return(NULL)
  }

  # Aktif oturum varsa görseli session-scoped URL ile sun (base64 şişmesini
  # önler; kaydedilmiş/galeri söyleşilerinin yüklenmesini hızlandırır). Yardımcı
  # yüklü değilse veya oturum yoksa aşağıdaki base64 yoluna düşülür.
  if (exists("mergen_serve_image_data_url", mode = "function")) {
    served <- mergen_serve_image_data_url(file_path)
    if (!is.null(served) && nzchar(served)) {
      return(served)
    }
  }

  tryCatch({
    raw_data <- readBin(file_path, "raw", file.info(file_path)$size)
    base64_str <- base64enc::base64encode(raw_data)
    paste0("data:image/png;base64,", base64_str)
  }, error = function(e) {
    NULL
  })
}

# ------------------------------------------------------------------------------
# Veritabanında saklanan görsel yolunu gerçek dosya sisteminde çözmeye çalışır.
# ------------------------------------------------------------------------------
db_message_resolve_image_path <- function(image_path, user_id = NULL) {
  if (is.null(image_path) || length(image_path) != 1L || !nzchar(image_path)) {
    return(NULL)
  }

  image_path <- as.character(image_path[1])

  # SAHİPLİK KÖKÜ ÖNCE ÇÖZÜLÜR. Aksi hâlde `[GÖRSEL:<yol>]` taşıyan bir asistan
  # mesajı, var olan HERHANGİ bir mutlak yolu (ya da gömülü `user_images/...`
  # yolunu) doğrudan döndürüyor ve `db_message_get_image_base64()` başka bir
  # kullanıcının görselini veya okunabilir bir sunucu dosyasını istemciye
  # data-URI olarak gönderiyordu.
  uid <- suppressWarnings(as.character(user_id %||% "")[1])
  if (is.na(uid) || !nzchar(uid) || uid %in% c("0", "unknown", "NA", "null")) {
    return(NULL)
  }
  sahip_koku <- file.path(getwd(), "user_images", uid)

  kok_icinde <- function(aday) {
    if (!nzchar(aday) || !file.exists(aday)) return(FALSE)
    if (exists("mergen_path_inside_root", mode = "function", inherits = TRUE)) {
      return(isTRUE(mergen_path_inside_root(aday, sahip_koku)))
    }
    coz <- suppressWarnings(normalizePath(aday, winslash = "/", mustWork = FALSE))
    kok <- suppressWarnings(normalizePath(sahip_koku, winslash = "/", mustWork = FALSE))
    isTRUE(nzchar(coz) && nzchar(kok) && startsWith(coz, paste0(sub("/+$", "", kok), "/")))
  }

  # 1. Doğrudan yol: yalnızca sahibin kökü içindeyse kabul edilir.
  if (kok_icinde(image_path)) {
    return(image_path)
  }

  # 2. Gömülü user_images/ göreli yolu: aynı kapsama denetiminden geçer.
  user_images_match <- regmatches(
    image_path,
    regexec("(user_images/.+)$", image_path)
  )[[1]]

  if (length(user_images_match) >= 2) {
    candidate_path <- file.path(getwd(), user_images_match[2])
    if (kok_icinde(candidate_path)) {
      return(candidate_path)
    }
  }

  # 3. Sadece dosya adını al ve YALNIZCA sahibin user_images klasöründe ara.
  filename <- basename(image_path)
  search_pattern <- file.path(sahip_koku, "*", filename)
  found_files <- Sys.glob(search_pattern)
  found_files <- found_files[vapply(found_files, kok_icinde, logical(1))]

  if (length(found_files) > 0) {
    return(found_files[1])
  }

  NULL
}

# ------------------------------------------------------------------------------
# Görsel mesajı için HTML oluşturur.
# ------------------------------------------------------------------------------
db_message_render_image_html <- function(image_path, description, message_id, user_id = NULL) {
  resolved_path <- db_message_resolve_image_path(image_path, user_id = user_id)

  description_html <- if (!is.null(description) && nzchar(description)) {
    sprintf(
      '<div class="image-description"><p>%s</p></div>',
      htmltools::htmlEscape(description)
    )
  } else {
    ""
  }

  if (is.null(resolved_path)) {
    return(sprintf(
      '<div class="generated-image-container">
         <div class="image-placeholder" style="padding: 20px; background: linear-gradient(135deg, #667eea 0%%, #764ba2 100%%); border-radius: 12px; text-align: center; color: white;">
           <i class="fas fa-image" style="font-size: 48px; margin-bottom: 10px; opacity: 0.8;"></i>
           <p style="margin: 10px 0; font-weight: 500;">Görsel dosyası bulunamadı</p>
         </div>
         %s
       </div>',
      description_html
    ))
  }

  img_src <- db_message_get_image_base64(resolved_path)

  if (is.null(img_src)) {
    return(sprintf(
      '<div class="generated-image-container">
         <div class="image-placeholder" style="padding: 20px; background: #f0f0f0; border-radius: 12px; text-align: center;">
           <p>Görsel yüklenemedi</p>
         </div>
         %s
       </div>',
      description_html
    ))
  }

  # Kart işaretlemesi kanonik güvenli yardımcıdan üretilir (XSS sınırı tek yerde).
  # description ham olarak geçilir; kaçış yardımcının içinde yapılır.
  mergen_generated_image_card_html(
    message_id = message_id,
    img_src = img_src,
    description = description
  )
}

# ------------------------------------------------------------------------------
# Normal metin / Chartlab / markdown içeriğini HTML'e dönüştürür.
# ------------------------------------------------------------------------------
db_message_process_text_content <- function(content_text, msg_type, message_id) {
  has_chartlab <- grepl("```chartlab", content_text, fixed = TRUE)

  if (has_chartlab && msg_type %in% c("ai", "assistant")) {
    chart_fn <- tryCatch(
      get("build_chartlab_message_static", envir = globalenv(), mode = "function"),
      error = function(e) NULL
    )

    if (!is.null(chart_fn)) {
      chart_result <- tryCatch(
        chart_fn(content_text, as.character(message_id)),
        error = function(e) list(found = FALSE)
      )

      if (isTRUE(chart_result$found)) {
        return(list(html = chart_result$html, has_code = FALSE))
      }
    }
  }

  process_fn <- tryCatch(
    get("process_message_content", envir = globalenv(), mode = "function"),
    error = function(e) NULL
  )

  if (!is.null(process_fn)) {
    return(process_fn(content_text, msg_type))
  }

  list(
    html = render_safe_markdown_html(content_text, hardbreaks = TRUE),
    has_code = FALSE
  )
}

# ------------------------------------------------------------------------------
# `[GÖRSEL:<yol>] açıklama` biçimli asistan mesajını görsel kartına çevirir;
# görsel mesajı değilse NULL döner. Yol, sahibin user_images kökünde çözülür.
# ------------------------------------------------------------------------------
db_message_process_image_content <- function(content_text, msg_type, message_id, user_id = NULL) {
  if (!msg_type %in% c("ai", "assistant") ||
      !grepl("^\\[GÖRSEL", content_text, perl = TRUE)) {
    return(NULL)
  }

  image_match <- regmatches(
    content_text,
    regexec("^\\[GÖRSEL:([^\\]]+)\\]\\s*((?s).*)", content_text, perl = TRUE)
  )[[1]]

  if (length(image_match) == 3) {
    image_html <- db_message_render_image_html(
      image_path = image_match[2],
      description = image_match[3],
      message_id = message_id,
      user_id = user_id
    )
    return(list(html = image_html, has_code = FALSE))
  }

  old_match <- regmatches(
    content_text,
    regexec("^\\[GÖRSEL\\]\\s*((?s).*)", content_text, perl = TRUE)
  )[[1]]

  image_description <- if (length(old_match) == 2) {
    old_match[2]
  } else {
    content_text
  }

  styled_html <- sprintf(
    '<div class="generated-image-container">
       <div class="image-description"><p>%s</p></div>
     </div>',
    htmltools::htmlEscape(image_description)
  )

  list(html = styled_html, has_code = FALSE)
}

# ------------------------------------------------------------------------------
# Tek bir DB mesaj satırını uygulama mesaj nesnesine dönüştürür.
# ------------------------------------------------------------------------------
db_message_format_row <- function(row, user_id = NULL) {
  content_text <- row$MessageContent %||% ""
  msg_type <- row$MessageType %||% "user"

  if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    content_text <- normalize_db_read_visible_value(content_text, repair_mojibake = TRUE)
  } else if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    content_text <- normalize_text_utf8(content_text, repair_mojibake = TRUE)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    msg_type <- normalize_text_utf8(msg_type, repair_mojibake = FALSE)
  }

  content_text <- trimws(content_text)

  processed <- db_message_process_image_content(
    content_text = content_text,
    msg_type = msg_type,
    message_id = as.character(row$MessageID),
    user_id = row$UserID %||% user_id
  ) %||% db_message_process_text_content(
    content_text = content_text,
    msg_type = msg_type,
    message_id = as.character(row$MessageID)
  )

  timestamp_val <- row$MessageTimestamp

  ts_tz <- attr(timestamp_val, "tzone")
  if (is.null(ts_tz) || !nzchar(ts_tz)) {
    ts_tz <- "UTC"
  }

  reasoning_text_saved <- NULL

  if ("ReasoningContent" %in% names(row)) {
    rc_val <- row$ReasoningContent

    if (!is.null(rc_val) &&
        length(rc_val) == 1 &&
        !is.na(rc_val) &&
        nzchar(rc_val)) {
      reasoning_text_saved <- if (exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
        normalize_db_read_visible_value(as.character(rc_val), repair_mojibake = TRUE)
      } else if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
        normalize_text_utf8(as.character(rc_val), repair_mojibake = TRUE)
      } else {
        as.character(rc_val)
      }
    }
  }

  base_msg <- list(
    id = as.character(row$MessageID),
    db_id = as.integer(row$MessageID),
    content = content_text,
    html_content = processed$html,
    has_code = processed$has_code,
    type = msg_type,
    timestamp = format(timestamp_val, "%d.%m.%Y - %H:%M", tz = ts_tz)
  )

  if (!is.null(reasoning_text_saved)) {
    base_msg$reasoning_content <- reasoning_text_saved
    base_msg$reasoning_trace <- reasoning_text_saved
  }

  base_msg
}

# ------------------------------------------------------------------------------
# DB mesaj veri çerçevesini uygulama mesaj listesine dönüştürür.
# Bu fonksiyonun adı geriye dönük uyumluluk için korunur.
# ------------------------------------------------------------------------------
# user_id: satırda UserID sütunu yoksa görsel yolu çözümü için kullanıcı kapsamı.
format_chat_messages <- function(chat_df, user_id = NULL) {
  if (is.null(chat_df) || nrow(chat_df) == 0) {
    return(list())
  }

  lapply(seq_len(nrow(chat_df)), function(i) {
    db_message_format_row(chat_df[i, , drop = FALSE], user_id = user_id)
  })
}

# Etkinlik zamanını karşılaştırılabilir saniyeye çevirir (geçersizse NA).
# DB sürücüsü İstanbul duvar saatini UTC etiketiyle döndürür: UTC/GMT etiketli
# POSIXt değer saat yüzünden İstanbul saati olarak yeniden yorumlanır (Kayıtlı
# Söyleşiler'deki parse_timestamp sözleşmesi). Etiketsiz POSIXt (Sys.time())
# gerçek andır ve olduğu gibi kalır; metin değerler İstanbul saati sayılır.
mergen_chat_activity_seconds <- function(value, tz = "Europe/Istanbul") {
  if (is.null(value) || length(value) == 0L) return(NA_real_)
  value <- value[1]
  if (inherits(value, "POSIXt")) {
    if (is.na(value)) return(NA_real_)
    bolge <- attr(value, "tzone")
    if (length(bolge) && toupper(as.character(bolge[1])) %in% c("UTC", "GMT")) {
      return(as.numeric(as.POSIXct(format(value, "%Y-%m-%d %H:%M:%S", tz = "UTC"), tz = tz)))
    }
    return(as.numeric(value))
  }
  if (inherits(value, "Date")) return(as.numeric(as.POSIXct(format(value), tz = tz)))
  if (is.numeric(value)) return(if (is.finite(value)) as.numeric(value) else NA_real_)
  metin <- as.character(value)
  if (is.na(metin) || !nzchar(metin)) return(NA_real_)
  for (bicim in c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%d %H:%M", "%d.%m.%Y - %H:%M", "%Y-%m-%d")) {
    zaman <- suppressWarnings(as.POSIXct(metin, format = bicim, tz = tz))
    if (!is.na(zaman)) return(as.numeric(zaman))
  }
  NA_real_
}

# Vektörel sürüm: mergen_chat_activity_seconds ile aynı sonuçları toplu
# dönüşümle üretir (her öğe için ayrı format/strptime çağrısı yapılmaz).
mergen_chat_activity_seconds_vec <- function(degerler, tz = "Europe/Istanbul") {
  n <- length(degerler)
  sonuc <- rep(NA_real_, n)
  if (!n) return(sonuc)
  tur <- character(n); ham <- rep(NA_real_, n); metin <- rep(NA_character_, n)
  for (i in seq_len(n)) {
    v <- degerler[[i]]
    if (is.null(v) || length(v) == 0L) next
    if (inherits(v, "POSIXt")) {
      v1 <- as.numeric(as.POSIXct(v[1]))
      if (is.na(v1)) next
      bolge <- attr(v, "tzone")
      utc <- length(bolge) && toupper(as.character(bolge[1])) %in% c("UTC", "GMT")
      tur[i] <- if (utc) "utc" else "sayi"; ham[i] <- v1
    } else if (is.numeric(v) && !inherits(v, "Date")) {
      if (is.finite(v[1])) { tur[i] <- "sayi"; ham[i] <- as.numeric(v[1]) }
    } else if (is.character(v) || is.factor(v)) {
      m <- as.character(v[1])
      if (!is.na(m) && nzchar(m)) { tur[i] <- "metin"; metin[i] <- m }
    } else {
      tur[i] <- "tekil"
    }
  }
  sayi <- tur == "sayi"
  sonuc[sayi] <- ham[sayi]
  utc <- which(tur == "utc")
  if (length(utc)) {
    duvar <- format(as.POSIXct(ham[utc], origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S", tz = "UTC")
    sonuc[utc] <- as.numeric(as.POSIXct(duvar, tz = tz))
  }
  kalan <- which(tur == "metin")
  for (bicim in c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%d %H:%M", "%d.%m.%Y - %H:%M", "%Y-%m-%d")) {
    if (!length(kalan)) break
    zaman <- as.numeric(suppressWarnings(as.POSIXct(metin[kalan], format = bicim, tz = tz)))
    tamam <- !is.na(zaman)
    sonuc[kalan[tamam]] <- zaman[tamam]
    kalan <- kalan[!tamam]
  }
  for (i in which(tur == "tekil")) sonuc[i] <- mergen_chat_activity_seconds(degerler[[i]], tz = tz)
  sonuc
}

# Yerel mesaj DB'ye kaydedilmemiş mi (db_id yok ve DB kimlikleri arasında değil)?
mergen_chat_message_unsaved <- function(m, db_ids = character()) {
  if (!is.list(m)) return(FALSE)
  db_id <- m$db_id
  if (!is.null(db_id) && length(db_id) > 0L && !is.na(db_id[1]) && nzchar(trimws(as.character(db_id[1])))) return(FALSE)
  mid <- suppressWarnings(as.character(m$id %||% "")[1])
  if (is.na(mid)) mid <- ""
  if (nzchar(mid) && mid %in% db_ids) return(FALSE)
  if ("db_id" %in% names(m)) return(TRUE)
  nzchar(mid) && is.na(suppressWarnings(as.integer(mid)))
}

# DB'den okunan söyleşi detayını yerel önbellekteki kayıtsız (db_id = NULL)
# mesajlarla uzlaştırır; Kayıtlı Söyleşiler ve Görsel Galerisi tek sözleşme kullanır.
# Kayıtsız mesaj oturumdaki KONUMUNU korur: yerel listede kendisinden sonra
# gelen ilk kayıtlı mesajın hemen önüne yerleşir; ardında kayıtlı mesaj yoksa
# (gerçekten sondaysa) sona eklenir. Kaydı başarısız kullanıcı istemi
# kaydedilmiş yanıtın önünde kalır; DB sırası (eşit zamanlar dahil) değişmez. Kayıtsız mesaj korunursa
# etkinlik zamanı iki adayın daha yenisidir. hidrate_zamani: bu okumanın
# BAŞLANGIÇ anı (okuyucu bildirdiyse); biçimlendirme süresi tazelik sayılmaz.
mergen_chat_reconcile_hydrated_detail <- function(detail, chat_to_load = NULL) {
  if (!is.list(detail)) return(detail)
  db_msgs <- if (is.list(detail$messages)) detail$messages else list()
  onceki_msgs <- if (is.list(chat_to_load) && is.list(chat_to_load$messages)) chat_to_load$messages else list()
  kayitsiz_var <- FALSE
  if (length(onceki_msgs) > 0L) {
    db_ids <- vapply(db_msgs, function(m) as.character(m$id %||% "")[1], character(1))
    db_ids[is.na(db_ids)] <- ""
    # Yerel mesajın DB karşılığının anahtarı (yoksa NA).
    db_anahtari <- function(m) {
      d <- if (is.list(m)) m$db_id else NULL
      aday <- if (!is.null(d) && length(d) > 0L && !is.na(d[1])) trimws(as.character(d[1])) else ""
      if (!nzchar(aday)) aday <- suppressWarnings(as.character(m$id %||% "")[1])
      if (!is.na(aday) && nzchar(aday) && aday %in% db_ids) aday else NA_character_
    }
    anahtarlar <- vapply(onceki_msgs, db_anahtari, character(1))
    kayitsiz_mi <- vapply(onceki_msgs, mergen_chat_message_unsaved, logical(1), db_ids = db_ids)
    if (any(kayitsiz_mi)) {
      kayitsiz_var <- TRUE
      once <- list(); sona <- list()
      for (i in which(kayitsiz_mi)) {
        sonraki_k <- utils::head(stats::na.omit(anahtarlar[seq.int(i, length(anahtarlar))]), 1L)
        if (length(sonraki_k)) {
          once[[sonraki_k]] <- c(once[[sonraki_k]], list(onceki_msgs[[i]]))
        } else {
          sona <- c(sona, list(onceki_msgs[[i]]))
        }
      }
      # DB mesajı başına bir parça toplanır ve tek seferde düzleştirilir: uzun
      # transkriptte her adımda büyüyen listenin kopyalanması (karesel) önlenir.
      parcalar <- vector("list", length(db_msgs))
      for (j in seq_along(db_msgs)) {
        k <- db_ids[[j]]
        onunde <- if (nzchar(k)) once[[k]] else NULL
        parcalar[[j]] <- c(onunde, list(db_msgs[[j]]))
        if (!is.null(onunde)) once[[k]] <- NULL
      }
      birlesik <- unlist(parcalar, recursive = FALSE)
      detail$messages <- c(birlesik %||% list(), sona)
      detail$message_count <- length(detail$messages)
    }
  }
  yerel_zaman <- if (is.list(chat_to_load)) chat_to_load$last_message_timestamp else NULL
  db_zaman <- detail$last_message_timestamp
  db_eksik <- is.null(db_zaman) || length(db_zaman) == 0L || is.na(db_zaman[1])
  if (!is.null(yerel_zaman) && (db_eksik || (kayitsiz_var && isTRUE(
      mergen_chat_activity_seconds(yerel_zaman) > mergen_chat_activity_seconds(db_zaman))))) {
    detail$last_message_timestamp <- yerel_zaman
  }
  detail$hidrate_edildi <- TRUE
  okuma_sn <- suppressWarnings(as.numeric(detail$okuma_baslangici %||% NA_real_)[1])
  detail$hidrate_zamani <- if (length(okuma_sn) == 1L && is.finite(okuma_sn)) okuma_sn else as.numeric(Sys.time())
  detail$okuma_baslangici <- NULL
  detail$transkript_yenile <- NULL
  detail
}
