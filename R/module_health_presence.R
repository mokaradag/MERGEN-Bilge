# ==============================================================================
# Dosya Yolu: R/module_health_presence.R
# Açıklama: Sistem Durumu panelinin "Çevrimiçi" sekmesi: anlık ve yakın zamanda
#           çevrimiçi kullanıcı sayaçları ile oturum takip tablosu. Veri
#           R/helpers_user_presence.R::mb_presence_snapshot() çıktısıdır.
# ==============================================================================

health_presence_pill <- function(status) {
  secim <- switch(status,
    cevrimici = list("ok", "Çevrimiçi", "Son 3 dakikada nabız görüldü"),
    sessiz = list("warning", "Sessiz", "Oturum açık ancak son nabız 3 dakikadan eski"),
    list("not_configured", "Ayrıldı", "Oturum kapandı"))
  tags$span(
    class = paste("health-pill health-presence-pill", health_status_class(secim[[1]])),
    `data-health-tooltip` = secim[[3]],
    tags$span(class = "health-presence-dot", `aria-hidden` = "true"),
    secim[[2]]
  )
}

health_presence_time_cell <- function(epoch, now) {
  zaman <- as.POSIXct(epoch, origin = "1970-01-01")
  bicim <- if (identical(format(zaman, "%Y-%m-%d"), format(now, "%Y-%m-%d"))) "%H:%M:%S" else "%d.%m %H:%M"
  tagList(
    strong(mb_presence_ago_label(as.numeric(now) - epoch)),
    tags$div(class = "health-presence-sub", format(zaman, bicim))
  )
}

health_presence_table <- function(users, now, max_rows = 200L) {
  if (is.null(users) || !nrow(users)) {
    return(div(class = "health-empty", "Son 24 saatte uygulamayı kullanan kullanıcı görünmüyor."))
  }
  # Tablo 30 sn'de bir yeniden çizildiği için satır sayısı sınırlıdır (liste
  # önce çevrimiçi, sonra en son görülen sırasındadır); sayaçlar tamdır.
  toplam <- nrow(users)
  users <- users[seq_len(min(toplam, max_rows)), , drop = FALSE]
  bas_harf <- if (exists("mb_sidebar_user_initials", mode = "function")) {
    mb_sidebar_user_initials
  } else {
    function(full_name = NULL, first_name = NULL) toupper(substr(full_name %||% "?", 1, 1))
  }
  satirlar <- lapply(seq_len(nrow(users)), function(i) {
    u <- users[i, ]
    ad <- if (nzchar(u$full_name)) u$full_name else if (nzchar(u$username)) u$username else paste0("Kullanıcı #", u$user_id)
    satir_sinifi <- switch(u$status, cevrimici = "health-presence-online",
                           sessiz = "health-presence-idle", "health-presence-left")
    tags$tr(
      class = paste("health-presence-row", satir_sinifi),
      tags$td(health_presence_pill(u$status)),
      tags$td(div(
        class = "health-presence-user",
        tags$span(class = "health-presence-avatar", `aria-hidden` = "true", bas_harf(full_name = ad)),
        div(strong(ad), if (nzchar(u$username)) tags$div(class = "health-check-id", u$username))
      )),
      tags$td(if (nzchar(u$sicil)) u$sicil else "—"),
      tags$td(
        if (nzchar(u$department)) u$department else "—",
        if (nzchar(u$mudurluk)) tags$div(class = "health-presence-sub", u$mudurluk)
      ),
      tags$td(if (u$sessions > 0L) paste(u$sessions, "sekme") else "—"),
      tags$td(mb_presence_duration_label(u$duration_secs)),
      tags$td(health_presence_time_cell(u$last_seen, now))
    )
  })
  div(
    class = "health-table-wrap health-presence-table-wrap",
    tabindex = "0", role = "region", `aria-label` = "Kullanıcı oturum takip tablosu",
    tags$table(
      class = "health-table health-presence-table",
      tags$thead(tags$tr(
        tags$th("Durum"), tags$th("Kullanıcı"), tags$th("Sicil"), tags$th("Birim"),
        tags$th("Açık Oturum"), tags$th("Süre"), tags$th("Son Görülme")
      )),
      tags$tbody(satirlar)
    ),
    if (toplam > nrow(users)) {
      tags$p(class = "health-presence-note",
             sprintf("İlk %d kullanıcı gösteriliyor (toplam %d).", nrow(users), toplam))
    }
  )
}

health_presence_ui <- function(snapshot) {
  if (!is.list(snapshot) || !is.list(snapshot$metrics)) {
    return(div(class = "health-empty", "Kullanıcı varlık bilgisi alınamadı."))
  }
  m <- snapshot$metrics
  sayi_durumu <- function(n) if (isTRUE(n > 0)) "ok" else "unknown"
  now <- snapshot$generated_at %||% Sys.time()
  tagList(
    div(
      class = "health-metrics-grid",
      health_metric_tile("Şu Anda Çevrimiçi", m$online, "user-check", sayi_durumu(m$online),
                         "Bağlı oturumunda son 3 dakikada nabız görülen kullanıcı"),
      health_metric_tile("Son 15 Dakika", m$recent, "clock", sayi_durumu(m$recent),
                         "Son 15 dakikada uygulamayı kullanan kullanıcı"),
      health_metric_tile("Son 24 Saat", m$day, "calendar-day", "unknown",
                         "Son 24 saatte uygulamayı kullanan kullanıcı"),
      health_metric_tile("Açık Oturum", m$open_sessions, "window-restore", "unknown",
                         "Bağlı tarayıcı sekmesi sayısı (kimliği henüz çözülmeyenler dahil)"),
      health_metric_tile("Aktif Birim", m$departments, "sitemap", "unknown",
                         "Şu anda çevrimiçi kullanıcıların farklı birim sayısı")
    ),
    health_section_card(
      "Kullanıcı Oturum Takibi",
      "users",
      tags$p(
        class = "health-presence-note",
        icon("circle-info"),
        " Çevrimiçi: uygulamaya bağlı oturumundan son 3 dakikada nabız görülen kullanıcı.",
        " Liste son 24 saati kapsar ve 30 saniyede bir yenilenir; çok-süreçli dağıtımda",
        " diğer uygulama süreçlerinin oturumları paylaşılan dizinden en fazla 30 sn gecikmeyle eklenir."
      ),
      health_presence_table(snapshot$users, now),
      tooltip = "Anlık ve yakın zamanda çevrimiçi kullanıcılar; açık oturum, süre ve son görülme bilgisi."
    )
  )
}
