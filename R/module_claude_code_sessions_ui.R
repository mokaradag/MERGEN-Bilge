# ==============================================================================
# Dosya Yolu: R/module_claude_code_sessions_ui.R
# Açıklama: Bilge Yolaç Oturumları sayfasının UI tanımı ve SAF HTML üreticileri.
#           Sunucu mantığı R/module_claude_code_sessions.R içindedir ve bu
#           dosyadaki saf kart/rozet/zaman üreticilerini kullanır.
#
#           Tasarım sözleşmesi: tüm yüzeyler tema token'larıyla
#           (var(--color-surface), var(--color-text) vb.) stillendirilir;
#           koyu/açık tema desteği www/css/claude_code_sessions.css içindedir.
# ==============================================================================

claudeCodeSessionsUI <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "claude-code-sessions-container",
      `data-character` = "emre",

      div(
        class = "chat-header settings-header-fixed",
        div(
          class = "chat-header-left",
          h4("Bilge Yolaç Oturumları", class = "page-title"),
          tags$span(class = "cc-badge", "AJAN")
        ),
        div(
          class = "chat-header-right ccs-header-actions",
          actionButton(
            ns("new_session"),
            label = tagList(icon("plus"), span("Yeni Oturum")),
            class = "btn-modern btn-primary ccs-new-session-btn",
            title = "Çalışma alanında yeni bir ajan oturumu başlat",
            `aria-label` = "Yeni oturum başlat"
          ),
          actionButton(
            ns("goto_workbench"),
            label = tagList(icon("terminal"), span("Çalışma Alanı")),
            class = "btn-modern ccs-workbench-btn",
            title = "Bilge Yolaç çalışma alanına git",
            `aria-label` = "Çalışma alanına git"
          ),
          actionButton(
            ns("refresh_sessions"),
            label = tagList(icon("sync"), span("Yenile")),
            class = "btn-modern ccs-refresh-btn",
            title = "Oturum listesini yenile",
            `aria-label` = "Oturum listesini yenile"
          )
        )
      ),

      div(
        class = "ccs-page-body",

        div(
          class = "ccs-hero",
          p(
            class = "ccs-hero-subtitle",
            icon("clock-rotate-left"),
            span(paste(
              "Claude Code tarzı kalıcı ajan çalışma geçmişi:",
              "oturumlarınız dayanıklı, devam edilebilir ve incelenebilir."
            ))
          )
        ),

        uiOutput(ns("summary_metrics"), class = "ccs-metrics-row"),

        div(
          class = "ccs-filter-bar",
          div(
            class = "ccs-filter-item ccs-filter-search",
            tags$label(
              class = "ccs-filter-label",
              `for` = ns("filter_query"),
              "Ara"
            ),
            textInput(
              ns("filter_query"),
              label = NULL,
              value = "",
              placeholder = "Başlık veya proje dizini ara..."
            )
          ),
          div(
            class = "ccs-filter-item",
            tags$label(
              class = "ccs-filter-label",
              `for` = ns("filter_status"),
              "Durum"
            ),
            # selectize = FALSE (yerel <select>): boş-değerli "Tümü" seçeneği
            # selectize'da başka bir seçim yapıldıktan sonra placeholder gibi
            # davranıp erişilemez hale gelebiliyordu. Yerel select ile "Tümü"
            # her zaman seçilebilir kalır ve kullanıcı filtresiz duruma
            # yeniden dönebilir (yenileme/tekrar giriş gerekmez).
            selectInput(
              ns("filter_status"),
              label = NULL,
              choices = c(
                "Tümü" = "",
                "Devam Edilebilir" = "resumable",
                "Tamamlandı" = "completed",
                "Başarısız" = "failed",
                "Durduruldu" = "stopped",
                "Arşivlenmiş" = "archived"
              ),
              selected = "",
              selectize = FALSE
            )
          ),
          div(
            class = "ccs-filter-item",
            tags$label(
              class = "ccs-filter-label",
              `for` = ns("filter_model"),
              "Model"
            ),
            # Model listesi sunucu tarafında kararlı biçimde (birikimli) doldurulur;
            # yerel select "Tümü" seçeneğinin her zaman erişilebilir kalmasını sağlar.
            selectInput(
              ns("filter_model"),
              label = NULL,
              choices = c("Tümü" = ""),
              selectize = FALSE
            )
          ),
          div(
            class = "ccs-filter-item",
            tags$label(
              class = "ccs-filter-label",
              `for` = ns("filter_sort"),
              "Sırala"
            ),
            selectInput(
              ns("filter_sort"),
              label = NULL,
              choices = c(
                "Son Etkinlik" = "last_activity",
                "Oluşturma Tarihi" = "created",
                "Çalıştırma Sayısı" = "run_count"
              ),
              selected = "last_activity"
            )
          )
        ),

        uiOutput(ns("sessions_list"), class = "ccs-sessions-area"),

        div(
          class = "ccs-load-more-row",
          uiOutput(ns("load_more_ui"))
        )
      )
    )
  )
}

# ------------------------------------------------------------------------------
# SAF ÜRETİCİLER (sunucu modülü tarafından kullanılır)
# ------------------------------------------------------------------------------

# Oturum durumunu rozet bilgisine çevirir (saf fonksiyon).
ccs_status_badge_info <- function(status, has_cli_id = FALSE, is_deleted = FALSE) {
  status <- as.character(status %||% "")[1]
  if (is.na(status)) status <- ""

  if (isTRUE(is_deleted)) {
    return(list(label = "Arşivlendi", class = "ccs-badge-archived", icon = "box-archive"))
  }

  switch(
    status,
    "completed" = list(label = "Tamamlandı", class = "ccs-badge-success", icon = "check-circle"),
    "failed" = list(label = "Başarısız", class = "ccs-badge-danger", icon = "triangle-exclamation"),
    "stopped" = list(label = "Durduruldu", class = "ccs-badge-warning", icon = "stop-circle"),
    "active" = list(label = "Aktif", class = "ccs-badge-info", icon = "bolt"),
    list(label = "Bilinmiyor", class = "ccs-badge-muted", icon = "circle-question")
  )
}

# Zaman değerini kısa Türkçe göreli etikete çevirir (saf fonksiyon).
ccs_time_label <- function(x, now = Sys.time()) {
  if (is.null(x) || !length(x) || is.na(x[1])) {
    return("-")
  }

  zaman <- x[1]
  if (is.character(zaman)) {
    zaman <- tryCatch(
      as.POSIXct(zaman, tz = "Europe/Istanbul"),
      error = function(e) NA
    )
  }

  if (is.na(zaman)) {
    return(as.character(x[1]))
  }

  fark_sn <- as.numeric(difftime(now, zaman, units = "secs"))

  if (fark_sn < 0) fark_sn <- 0

  if (fark_sn < 60) {
    "az önce"
  } else if (fark_sn < 3600) {
    paste0(floor(fark_sn / 60), " dk önce")
  } else if (fark_sn < 86400) {
    paste0(floor(fark_sn / 3600), " sa önce")
  } else if (fark_sn < 7 * 86400) {
    paste0(floor(fark_sn / 86400), " gün önce")
  } else {
    format(zaman, "%d.%m.%Y")
  }
}

# Özet metrik kartı üretir (saf fonksiyon). Sınıf adları frontend hayalet
# seçici taramasının doğrulayabilmesi için switch içinde AÇIK yazılır.
ccs_metric_card <- function(icon_name, value, label, accent = "primary") {
  accent_class <- switch(
    as.character(accent %||% "primary")[1],
    "success" = "ccs-metric-success",
    "danger" = "ccs-metric-danger",
    "info" = "ccs-metric-info",
    "muted" = "ccs-metric-muted",
    "ccs-metric-primary"
  )

  div(
    class = paste("ccs-metric-card", accent_class),
    div(class = "ccs-metric-icon", icon(icon_name)),
    div(
      class = "ccs-metric-body",
      div(class = "ccs-metric-value", as.character(value)),
      div(class = "ccs-metric-label", label)
    )
  )
}

# Tek bir oturum satırından zengin oturum kartı üretir (saf fonksiyon).
# Tüm kullanıcı-kontrollü metinler htmlEscape'ten geçer (XSS sınırı).
ccs_session_card <- function(row, ns) {
  kayit_id <- suppressWarnings(as.integer(row$ClaudeSessionRecordID))
  baslik <- htmltools::htmlEscape(as.character(row$SessionTitle %||% "Adsız Oturum"))
  proje <- htmltools::htmlEscape(as.character(row$SourceWorkdir %||% row$Workdir %||% ""))
  son_prompt <- as.character(row$LastPrompt %||% "")
  if (is.na(son_prompt)) son_prompt <- ""
  if (nchar(son_prompt) > 160) {
    son_prompt <- paste0(substr(son_prompt, 1, 157), "...")
  }
  son_prompt <- htmltools::htmlEscape(son_prompt)

  model <- htmltools::htmlEscape(as.character(row$RuntimeModel %||% row$ModelUsed %||% ""))
  run_sayisi <- suppressWarnings(as.integer(row$RunCount %||% 0L))
  dosyali <- suppressWarnings(as.integer(row$RunsWithFiles %||% 0L))
  silinmis <- isTRUE(as.logical(row$IsDeleted %||% FALSE)) ||
    identical(suppressWarnings(as.integer(row$IsDeleted %||% 0L)), 1L)

  cli_id <- as.character(row$ClaudeCliSessionID %||% "")
  devam_edilebilir <- !is.na(cli_id) && nzchar(cli_id)

  rozet <- ccs_status_badge_info(row$Status, devam_edilebilir, silinmis)

  son_etkinlik <- ccs_time_label(row$LastRunAt %||% row$CreatedAt)

  set_input <- function(input_ad) {
    sprintf(
      "event.stopPropagation();Shiny.setInputValue('%s', %d, {priority:'event'});",
      ns(input_ad),
      kayit_id
    )
  }

  div(
    class = "ccs-session-card",
    `data-record-id` = kayit_id,
    role = "listitem",
    tabindex = "0",
    onclick = sprintf(
      "Shiny.setInputValue('%s', %d, {priority:'event'});",
      ns("session_open"),
      kayit_id
    ),
    onkeydown = sprintf(
      "if(event.key==='Enter'||event.key===' '){event.preventDefault();Shiny.setInputValue('%s', %d, {priority:'event'});}",
      ns("session_open"),
      kayit_id
    ),

    div(
      class = "ccs-card-top",
      div(class = "ccs-card-title", HTML(baslik)),
      tags$span(
        class = paste("ccs-status-badge", rozet$class),
        icon(rozet$icon),
        rozet$label
      )
    ),

    if (nzchar(proje)) {
      div(
        class = "ccs-card-project",
        icon("folder-open"),
        tags$span(class = "ccs-card-project-path", HTML(proje))
      )
    },

    if (nzchar(son_prompt)) {
      div(class = "ccs-card-preview", HTML(son_prompt))
    },

    div(
      class = "ccs-card-meta",
      if (nzchar(model)) {
        tags$span(class = "ccs-meta-chip ccs-model-chip", icon("microchip"), HTML(model))
      },
      tags$span(
        class = paste0(
          "ccs-meta-chip ccs-resume-chip",
          if (devam_edilebilir && !silinmis) " ccs-resume-ok" else ""
        ),
        icon(if (devam_edilebilir && !silinmis) "rotate-right" else "circle-minus"),
        if (devam_edilebilir && !silinmis) "Devam edilebilir" else "CLI oturumu yok"
      ),
      tags$span(class = "ccs-meta-chip", icon("bolt"), paste0(run_sayisi, " çalıştırma")),
      if (dosyali > 0L) {
        tags$span(class = "ccs-meta-chip", icon("file-arrow-down"), paste0(dosyali, " dosyalı"))
      },
      tags$span(class = "ccs-meta-chip ccs-time-chip", icon("clock"), son_etkinlik)
    ),

    div(
      class = "ccs-card-actions",
      tags$button(
        type = "button",
        class = "ccs-card-btn ccs-open-btn",
        title = "Oturum detayını görüntüle",
        `aria-label` = "Oturum detayını görüntüle",
        onclick = set_input("session_open"),
        icon("eye"), span("Aç")
      ),
      if (!silinmis) {
        tags$button(
          type = "button",
          class = "ccs-card-btn ccs-resume-btn",
          title = "Bu oturuma çalışma alanında devam et",
          `aria-label` = "Oturuma devam et",
          onclick = set_input("session_resume"),
          icon("play"), span("Devam Et")
        )
      },
      if (!silinmis) {
        tags$button(
          type = "button",
          class = "ccs-card-btn ccs-archive-btn",
          title = "Oturumu arşivle (kalıcı geçmiş silinmez)",
          `aria-label` = "Oturumu arşivle",
          onclick = set_input("session_archive"),
          icon("box-archive"), span("Arşivle")
        )
      },
      # Arşivlenmiş kartlar: arşivden çıkar (geri yükle) ve kalıcı sil eylemleri.
      if (silinmis) {
        tags$button(
          type = "button",
          class = "ccs-card-btn ccs-restore-btn",
          title = "Oturumu arşivden çıkar (normal listeye geri döndür)",
          `aria-label` = "Oturumu arşivden çıkar",
          onclick = set_input("session_restore"),
          icon("box-open"), span("Geri Yükle")
        )
      },
      if (silinmis) {
        tags$button(
          type = "button",
          class = "ccs-card-btn ccs-delete-btn",
          title = "Oturumu kalıcı olarak sil (geri alınamaz)",
          `aria-label` = "Oturumu kalıcı olarak sil",
          onclick = set_input("session_delete"),
          icon("trash"), span("Kalıcı Sil")
        )
      }
    )
  )
}

# Boş/erişilemez durum kartları (saf fonksiyon).
ccs_sessions_empty_state <- function(type = "empty") {
  bilgi <- switch(
    type,
    "unavailable" = list(
      ikon = "database",
      baslik = "Kalıcı oturum tabloları henüz kurulmamış",
      metin = paste(
        "MB_ClaudeCode_Sessions / MB_ClaudeCode_Runs tabloları bulunamadı.",
        "Bilge Yolaç bellek-içi modda çalışmaya devam eder. Kurulum betiği:",
        "docs/sql/2026-07-bilge-yolac-sessions.sql (bkz. RUNBOOK.md)."
      )
    ),
    "auth" = list(
      ikon = "user-clock",
      baslik = "Kimlik doğrulama hazırlanıyor",
      metin = "Oturumlarınız kimlik doğrulama tamamlandığında listelenecek."
    ),
    list(
      ikon = "clock-rotate-left",
      baslik = "Henüz kayıtlı oturum yok",
      metin = paste(
        "Çalışma alanında bir komut çalıştırdığınızda oturum otomatik olarak",
        "burada saklanır; daha sonra inceleyebilir veya devam edebilirsiniz."
      )
    )
  )

  div(
    class = "ccs-empty-state",
    div(class = "ccs-empty-icon", icon(bilgi$ikon)),
    h4(class = "ccs-empty-title", bilgi$baslik),
    p(class = "ccs-empty-text", bilgi$metin)
  )
}

# Detay modalındaki tek çalıştırma zaman çizelgesi öğesi (saf fonksiyon).
ccs_run_timeline_item <- function(run_row) {
  durum <- as.character(run_row$Status %||% "")[1]
  rozet <- ccs_status_badge_info(durum)

  prompt_metin <- as.character(run_row$Prompt %||% "")[1]
  if (is.na(prompt_metin)) prompt_metin <- ""
  if (nchar(prompt_metin) > 400) {
    prompt_metin <- paste0(substr(prompt_metin, 1, 397), "...")
  }

  cikti_metin <- as.character(run_row$FinalOutput %||% "")[1]
  if (is.na(cikti_metin)) cikti_metin <- ""
  if (nchar(cikti_metin) > 700) {
    cikti_metin <- paste0(substr(cikti_metin, 1, 697), "...")
  }

  arac_sayisi <- 0L
  arac_json <- as.character(run_row$ToolUsesJson %||% "")[1]
  if (!is.na(arac_json) && nzchar(arac_json) && !identical(arac_json, "[]")) {
    arac_sayisi <- tryCatch(
      length(jsonlite::fromJSON(arac_json, simplifyVector = FALSE)),
      error = function(e) 0L
    )
  }

  dosya_json <- as.character(run_row$GeneratedDownloadsJson %||% "")[1]
  uretilen_dosyalar <- list()
  if (!is.na(dosya_json) && nzchar(dosya_json) && !identical(dosya_json, "[]")) {
    uretilen_dosyalar <- tryCatch(
      jsonlite::fromJSON(dosya_json, simplifyVector = FALSE),
      error = function(e) list()
    )
  }
  dosya_sayisi <- length(uretilen_dosyalar)

  sure <- suppressWarnings(as.numeric(run_row$DurationSeconds))

  div(
    class = "ccs-run-item",
    div(
      class = "ccs-run-head",
      tags$span(class = "ccs-run-order", paste0("#", run_row$RunOrder %||% "?")),
      tags$span(
        class = paste("ccs-status-badge", rozet$class),
        icon(rozet$icon),
        rozet$label
      ),
      if (!is.na(sure)) {
        tags$span(class = "ccs-meta-chip", icon("stopwatch"), paste0(sure, " sn"))
      },
      if (arac_sayisi > 0L) {
        tags$span(class = "ccs-meta-chip", icon("cogs"), paste0(arac_sayisi, " araç"))
      },
      if (dosya_sayisi > 0L) {
        tags$span(class = "ccs-meta-chip", icon("file-arrow-down"), paste0(dosya_sayisi, " dosya"))
      },
      tags$span(
        class = "ccs-meta-chip ccs-time-chip",
        icon("clock"),
        as.character(run_row$CreatedAt %||% "")
      )
    ),
    div(
      class = "ccs-run-prompt",
      tags$span(class = "ccs-run-label", "Komut"),
      tags$pre(class = "ccs-run-pre", prompt_metin)
    ),
    if (nzchar(cikti_metin)) {
      div(
        class = "ccs-run-output",
        tags$span(class = "ccs-run-label", "Yanıt"),
        tags$pre(class = "ccs-run-pre", cikti_metin)
      )
    },
    # Üretilen belgeler: kayıtlı oturum geri getirildiğinde oluşturulan
    # dosyalar ve bağlantıları görünür kalır. Ad kaçışlanır (XSS sınırı);
    # url uygulama tarafından üretilen kaynak yoludur (bilge_yolac_downloads).
    ccs_run_generated_files_ui(uretilen_dosyalar)
  )
}

# Bir çalıştırmanın ürettiği dosyaları indirilebilir bağlantı listesine çevirir
# (saf fonksiyon). Metin alanları htmlEscape'ten geçer; url zaten güvenli
# uygulama kaynak yoludur.
ccs_run_generated_files_ui <- function(files) {
  if (is.null(files) || !length(files)) {
    return(NULL)
  }

  ogeler <- lapply(files, function(dosya) {
    if (!is.list(dosya)) return(NULL)

    ad <- as.character(dosya$display_name %||% dosya$download_name %||% "")[1]
    if (is.na(ad) || !nzchar(ad)) ad <- "belge"
    boyut <- as.character(dosya$size_label %||% "")[1]
    url <- as.character(dosya$url %||% "")[1]

    etiket <- tagList(
      icon("file-arrow-down"),
      tags$span(class = "ccs-run-file-name", HTML(htmltools::htmlEscape(ad))),
      if (!is.na(boyut) && nzchar(boyut)) {
        tags$span(class = "ccs-run-file-size", HTML(htmltools::htmlEscape(boyut)))
      }
    )

    if (!is.na(url) && nzchar(url)) {
      tags$a(
        class = "ccs-run-file ccs-run-file-link",
        href = url,
        target = "_blank",
        rel = "noopener",
        download = NA,
        etiket
      )
    } else {
      tags$span(class = "ccs-run-file", etiket)
    }
  })

  div(
    class = "ccs-run-files",
    tags$span(class = "ccs-run-label", "Üretilen Belgeler"),
    div(class = "ccs-run-files-list", ogeler)
  )
}

# Oturum detayı modal içeriği (saf fonksiyon).
ccs_session_detail_content <- function(record, resume_ok = FALSE) {
  oturum <- record$session
  runs <- record$runs

  meta_satir <- function(etiket, deger) {
    deger <- as.character(deger %||% "")[1]
    if (is.na(deger) || !nzchar(deger)) return(NULL)
    div(
      class = "ccs-detail-meta-row",
      tags$span(class = "ccs-detail-meta-label", etiket),
      tags$span(class = "ccs-detail-meta-value", deger)
    )
  }

  tagList(
    div(
      class = "ccs-detail-resume-note",
      if (isTRUE(resume_ok)) {
        tags$span(
          class = "ccs-status-badge ccs-badge-success",
          icon("rotate-right"),
          "Bu oturuma çalışma alanında devam edilebilir."
        )
      } else {
        tags$span(
          class = "ccs-status-badge ccs-badge-warning",
          icon("circle-info"),
          "CLI oturumu devam ettirilemez; geçmiş salt okunur yüklenir ve takip soruları yeni bir CLI oturumu başlatır."
        )
      }
    ),
    div(
      class = "ccs-detail-meta",
      meta_satir("Proje Dizini", oturum$SourceWorkdir %||% oturum$Workdir),
      meta_satir("Runtime Dizini", oturum$RuntimeWorkdir),
      meta_satir("Model", oturum$ModelUsed),
      meta_satir("Çalışan Model", oturum$RuntimeModel),
      meta_satir("Karakter", oturum$CharacterID),
      meta_satir("Oluşturma", oturum$CreatedAt),
      meta_satir("Son Etkinlik", oturum$LastRunAt)
    ),
    h5(class = "ccs-detail-timeline-title", icon("timeline"), "Çalıştırma Zaman Çizelgesi"),
    if (is.data.frame(runs) && nrow(runs) > 0L) {
      div(
        class = "ccs-run-timeline",
        lapply(seq_len(nrow(runs)), function(i) {
          ccs_run_timeline_item(as.list(runs[i, , drop = FALSE]))
        })
      )
    } else {
      p(class = "ccs-empty-text", "Bu oturumda kayıtlı çalıştırma yok.")
    }
  )
}
