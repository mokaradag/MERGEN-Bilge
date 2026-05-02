# ==============================================================================
# Dosya Yolu: R/helpers_llm_worker_payload.R
# Açıklama:   helpers_llm_worker.R için saf mesaj, grafik niyeti ve içgörü
#             yardımcıları. Shiny oturumu, reactive state veya worker global
#             durumuna dokunmaz.
# ==============================================================================

llm_worker_scalar_nzchar <- function(x) {
  is.character(x) &&
    length(x) > 0L &&
    !is.na(x[1]) &&
    nzchar(x[1])
}

llm_worker_chat_history_to_messages <- function(chat_history) {
  lapply(chat_history, function(msg) {
    role_val <- if (!is.null(msg$type)) {
      if (identical(msg$type, "user")) "user"
      else if (identical(msg$type, "system")) "system"
      else "assistant"
    } else if (!is.null(msg$role)) {
      tolower(as.character(msg$role))
    } else {
      "user"
    }

    content_val <- msg$content %||% msg$message %||% as.character(msg)
    list(role = role_val, content = content_val)
  })
}

llm_worker_merge_system_messages_to_front <- function(messages) {
  if (!length(messages)) return(messages)

  roles <- vapply(messages, function(m) {
    tolower(as.character(m$role %||% "user"))[1]
  }, character(1))

  system_idx <- which(roles == "system")
  if (!length(system_idx)) return(messages)

  system_text <- paste(
    vapply(messages[system_idx], function(m) {
      as.character(m$content %||% "")[1]
    }, character(1)),
    collapse = "\n\n"
  )
  system_text <- trimws(system_text)

  non_system_messages <- messages[roles != "system"]

  c(
    list(list(role = "system", content = system_text)),
    non_system_messages
  )
}

# Geriye dönük uyumluluk:
# helpers_llm_worker.R içindeki eski ikinci-geçiş/recursive yollar bu kısa adı
# çağırıyorsa runtime'da kırılmasın. Yeni kod canonical llm_worker_* adını kullanır.
merge_system_messages_to_front <- function(messages) {
  llm_worker_merge_system_messages_to_front(messages)
}

llm_worker_detect_chart_type_from_text <- function(text) {
  if (!llm_worker_scalar_nzchar(text)) return("auto")

  txt <- tolower(text[1])

  if (grepl("\\b(histogram|histogramı|histogramını|dağılım grafiği)\\b", txt, perl = TRUE)) return("hist")
  if (grepl("\\b(çizgi|line|trend|zaman serisi|time series|eğilim)\\b", txt, perl = TRUE)) return("line")
  if (grepl("\\b(bar|çubuk|sütun|column|karşılaştır)\\b", txt, perl = TRUE)) return("bar")
  if (grepl("\\b(pie|pasta|dilim|pay)\\b", txt, perl = TRUE)) return("pie")
  if (grepl("\\b(donut|halka)\\b", txt, perl = TRUE)) return("donut")
  if (grepl("\\b(area|alan)\\b", txt, perl = TRUE)) return("area")
  if (grepl("\\b(pareto)\\b", txt, perl = TRUE)) return("pareto")
  if (grepl("\\b(scatter|saçılım|nokta|dağılım|serpilme)\\b", txt, perl = TRUE)) return("scatter")

  "auto"
}

llm_worker_last_user_text <- function(chat_history) {
  last_user_txt <- NULL

  if (length(chat_history) > 0) {
    for (i in seq_along(chat_history)) {
      msg <- chat_history[[i]]
      role_val <- tolower(as.character(msg$type %||% msg$role %||% ""))

      if (identical(role_val, "user")) {
        last_user_txt <- as.character(msg$content %||% msg$message %||% "")
      }
    }
  }

  last_user_txt
}

llm_worker_has_chart_intent <- function(chat_history) {
  last_user_txt <- tryCatch(
    llm_worker_last_user_text(chat_history),
    error = function(e) NULL
  )

  if (!llm_worker_scalar_nzchar(last_user_txt)) {
    return(FALSE)
  }

  grepl(
    "(?i)\\b(grafik|grafikleri|grafiğini|görselleştir|gorsellestir|görselleştirme|gorsellestirme|plot|chart|chartlab|figure|graph|viz|visualize|visualise|çiz|çizelge|histogram|bar|çubuk|line|çizgi|trend|dağılım|scatter|pie|pasta|donut|pareto|area|spline|boxplot)\\b",
    last_user_txt[1],
    perl = TRUE
  )
}

llm_worker_add_fallback_chart <- function(original_text) {
  original_text %||% ""
}

llm_worker_build_chart_summary <- function(raw_chart) {
  chart <- raw_chart$chart %||% raw_chart

  if (is.null(chart) || !is.list(chart)) {
    return("Grafik hazırlandı; veri kısa süreli özetlendi.")
  }

  desc_parts <- c()

  chart_type <- chart$type %||% chart$chart_type %||% ""
  if (llm_worker_scalar_nzchar(chart_type)) {
    desc_parts <- c(desc_parts, paste0("Tür: ", as.character(chart_type)[1]))
  }

  mapping <- chart$mapping %||% list()
  x_col <- as.character(mapping$x %||% "")[1]
  y_col <- as.character(mapping$y %||% "")[1]
  group_col <- as.character(mapping$group %||% "")[1]

  axes <- c()
  if (llm_worker_scalar_nzchar(x_col)) axes <- c(axes, paste0("X=", x_col))
  if (llm_worker_scalar_nzchar(y_col)) axes <- c(axes, paste0("Y=", y_col))
  if (llm_worker_scalar_nzchar(group_col)) axes <- c(axes, paste0("Gruplama=", group_col))

  if (length(axes)) {
    desc_parts <- c(desc_parts, paste(axes, collapse = ", "))
  }

  df <- chart$data
  row_hint <- chart$n %||% if (is.data.frame(df)) nrow(df) else NULL
  row_hint_num <- suppressWarnings(as.numeric(row_hint[1] %||% NA_real_))

  if (!is.na(row_hint_num) && is.finite(row_hint_num)) {
    desc_parts <- c(desc_parts, paste0("Örnek satır sayısı: ", as.character(row_hint[1])))
  }

  summary_line <- if (length(desc_parts)) {
    paste(desc_parts, collapse = " | ")
  } else {
    "Dosyadaki verilerden üretildi"
  }

  quick_observation <- NULL

  if (is.data.frame(df)) {
    num_candidate <- NULL

    if (llm_worker_scalar_nzchar(y_col) &&
        y_col %in% names(df) &&
        is.numeric(df[[y_col]])) {
      num_candidate <- df[[y_col]]
    }

    if (is.null(num_candidate) &&
        llm_worker_scalar_nzchar(x_col) &&
        x_col %in% names(df) &&
        is.numeric(df[[x_col]])) {
      num_candidate <- df[[x_col]]
    }

    if (!is.null(num_candidate)) {
      num_candidate <- suppressWarnings(as.numeric(num_candidate))
      num_candidate <- num_candidate[is.finite(num_candidate)]

      if (length(num_candidate)) {
        med_val <- stats::median(num_candidate)
        q1 <- stats::quantile(num_candidate, 0.25, na.rm = TRUE)
        q3 <- stats::quantile(num_candidate, 0.75, na.rm = TRUE)
        mn <- min(num_candidate)
        mx <- max(num_candidate)
        iqr_span <- q3 - q1
        tail_hint <- if (med_val > mean(c(q1, q3))) "üst" else "alt"

        quick_observation <- paste(
          sprintf("Ortanca %.2f (Q1=%.2f, Q3=%.2f), min %.2f, max %.2f.", med_val, q1, q3, mn, mx),
          sprintf("Değerler %s kuyrukta yoğunlaşıyor; dışa taşan uçlar için kutu yaylarını inceleyebilirsin.", tail_hint),
          sprintf("IQR %.2f olduğundan veri yayılımı %s; bu aralık grafik üzerinde renk/yoğunluk olarak hissedilir.", iqr_span, if (iqr_span > 0) "belirgin" else "düşük")
        )
      }
    } else if (llm_worker_scalar_nzchar(x_col) &&
               x_col %in% names(df) &&
               !is.numeric(df[[x_col]])) {
      top_levels <- sort(table(df[[x_col]]), decreasing = TRUE)
      top_levels <- head(top_levels, 3)

      if (length(top_levels)) {
        top_share <- round(as.numeric(top_levels) / sum(top_levels) * 100, 1)
        quick_observation <- paste0(
          "En sık kategoriler: ",
          paste(
            sprintf(
              "%s (%d, %s%%)",
              names(top_levels),
              as.integer(top_levels),
              format(top_share, nsmall = 1)
            ),
            collapse = ", "
          ),
          ". Yoğunluğun bu gruplarda toplandığını vurgula; kalan uzun kuyruğu da kısaca hatırlat."
        )
      }
    }
  }

  base_line <- paste0("Grafik hazırlandı: ", summary_line, ".")

  if (llm_worker_scalar_nzchar(quick_observation)) {
    paste(
      base_line,
      quick_observation,
      "Eksenlerdeki deseni iki cümleyle anlat ve kullanıcının aklında net bir tablo oluşmasını sağla."
    )
  } else {
    paste(
      base_line,
      "Veri dağılımını ve olası uç değerleri kısaca betimleyip okuyucuya yol gösterici bir paragraf ekle."
    )
  }
}

llm_worker_build_auto_insight <- function(raw_results) {
  chart_pick <- Filter(
    function(x) is.list(x) && (!is.null(x[["chart"]]) || isTRUE(x[["__mcp_plot"]])),
    raw_results
  )

  if (length(chart_pick)) {
    return(llm_worker_build_chart_summary(chart_pick[[1]]))
  }

  for (rr in raw_results) {
    if (!is.list(rr)) next

    df <- rr$`sonuç_önizleme` %||% rr$preview

    if (is.data.frame(df) && nrow(df) > 0) {
      num_cols <- names(df)[vapply(df, is.numeric, logical(1))]

      if (length(num_cols)) {
        vals <- suppressWarnings(as.numeric(df[[num_cols[1]]]))
        vals <- vals[is.finite(vals)]

        if (length(vals)) {
          avg <- mean(vals)
          med <- stats::median(vals)
          mn <- min(vals)
          mx <- max(vals)
          sdv <- stats::sd(vals)

          return(sprintf(
            paste(
              "İçgörü: %d satırın %s sütunu min %.2f, medyan %.2f, ortalama %.2f, max %.2f.",
              "Standart sapma %.2f; dağılımın genişliği ve olası uç noktalar üzerine birkaç cümle kur.",
              "Kısa, öğretici bir paragrafla kullanıcının görebileceği trendleri ve aksiyon önerilerini anlat."
            ),
            nrow(df), num_cols[1], mn, med, avg, mx, sdv
          ))
        }
      }

      head_cols <- paste(head(colnames(df), 3), collapse = ", ")

      return(sprintf(
        paste(
          "İçgörü: İlk %d satırda öne çıkan sütunlar %s; satır örneklerini kullanarak eğilimleri anlat.",
          "Okuyucuya rehberlik edecek 4-5 cümlelik bir paragraf yaz; hangi kolonların dikkat çektiğini ve neden önemli olabileceğini açıkla."
        ),
        nrow(df), head_cols
      ))
    }
  }

  "İçgörü: Sonuçlar yukarıda; dağılımı, beklenmedik değerleri ve olası aksiyonları birkaç cümleyle rehber gibi açıkla."
}