# ==============================================================================
# Dosya Yolu: R/module_health_release.R
# Açıklama: Sistem Durumu panelinin "Release Kanıtı" sekmesi için UI yardımcıları.
#            R/helpers_release_evidence.R saf okuyucusunun ürettiği secret-safe
#            özeti operatöre görünür hale getirir: en son VM evidence gate,
#            ai-validation summary ve günlük log sağlık sayaçları.
#
#            Kanıt sınırı dürüstlüğü korunur: bulunamayan kanıt "Bulunamadı"
#            olarak gösterilir, asla başarı gibi sunulmaz; SKIP edilen adımlar
#            kanıt değildir. Bu sekme yalnızca okunan artifact alanlarını
#            gösterir; ham log içeriği veya ortam değeri taşımaz.
# ==============================================================================

# Kanıt durum anahtarını (passed/failed/skipped/not_found) sağlık rozet
# rengine ve Türkçe etikete eşler. health_status_pill yalnızca renk için
# kullanılır; etiket bu fonksiyonda netleştirilir.
.health_release_pill <- function(evidence_status, label = NULL) {
  s <- tolower(trimws(as.character(evidence_status %||% "")[1]))

  mapped <- switch(s,
    passed = "ok", pass = "ok", ok = "ok", success = "ok",
    failed = "critical", fail = "critical", error = "critical",
    skipped = "not_configured", skip = "not_configured",
    not_found = "unknown", unknown = "unknown",
    "unknown"
  )

  pretty <- label %||% switch(s,
    passed = "Geçti", pass = "Geçti", ok = "Geçti", success = "Geçti",
    failed = "Başarısız", fail = "Başarısız", error = "Başarısız",
    skipped = "Atlandı", skip = "Atlandı",
    not_found = "Bulunamadı", unknown = "Bilinmiyor",
    health_safe_value(evidence_status)
  )

  health_status_pill(mapped, label = pretty)
}

# VM evidence gate adımlarını küçük bir tabloya çevirir (id / durum / zorunlu).
# Yalnızca id, status ve required üçlüsü gösterilir; log yolu/not taşınmaz.
.health_release_steps_table <- function(steps) {
  if (is.null(steps) || !length(steps)) {
    return(div(class = "health-empty", "Adım kaydı yok."))
  }

  satirlar <- lapply(steps, function(s) {
    durum <- s$status %||% "unknown"
    zorunlu <- isTRUE(s$required)
    tags$tr(
      tags$td(health_escape(s$id %||% "—")),
      tags$td(.health_release_pill(durum)),
      tags$td(if (zorunlu) "Evet" else "Hayır")
    )
  })

  tags$table(
    class = "health-table health-release-steps",
    tags$thead(tags$tr(
      tags$th("Adım"),
      tags$th("Durum"),
      tags$th("Zorunlu")
    )),
    tags$tbody(satirlar)
  )
}

# ERROR bağlam kategorilerini (etiket + sayım) güvenli bir özet listesine
# çevirir. YALNIZCA geliştirici bağlam etiketi ve sayı gösterilir; log mesaj
# içeriği taşınmaz. Kategori yoksa NULL döner (mevcut UI değişmez).
.health_release_error_contexts <- function(error_contexts) {
  if (is.null(error_contexts) || !length(error_contexts)) {
    return(NULL)
  }

  satirlar <- lapply(error_contexts, function(ec) {
    etiket <- health_escape(as.character(ec$context %||% "—"))
    adet <- as.integer(ec$count %||% 0L)
    div(strong(paste0(etiket, ":")), span(health_safe_value(adet)))
  })

  div(
    class = "health-summary-list health-release-error-contexts",
    `data-health-tooltip` = "ERROR satırlarının geliştirici bağlam etiketine göre dağılımı (içerik taşınmaz).",
    div(strong("Hata kategorileri (bağlam):")),
    satirlar
  )
}

health_release_ui <- function(overview) {
  if (is.null(overview) || !is.list(overview)) {
    return(div(
      class = "health-empty",
      "Release kanıt okuyucusu kullanılamıyor veya henüz kanıt üretilmedi."
    ))
  }

  vm <- overview$vm_evidence %||% list()
  ai <- overview$ai_validation %||% list()
  log_saglik <- overview$log_health %||% list()

  vm_bulundu <- isTRUE(vm$found)
  ai_bulundu <- isTRUE(ai$found)
  log_bulundu <- isTRUE(log_saglik$found)

  hata_sayisi <- as.integer(log_saglik$error_count %||% 0L)
  uyari_sayisi <- as.integer(log_saglik$warn_count %||% 0L)

  tagList(
    # Operatöre kanıt sınırını ve son okuma zamanını açıklayan kısa hero kartı.
    div(
      class = "health-hero health-status-unknown",
      `data-health-tooltip` = "Bu sekme yalnızca üretilmiş doğrulama artifact'larını okur; canlı bir kapı çalıştırmaz.",
      div(class = "health-hero-copy",
          h2("Release Kanıtı"),
          p(paste(
            "En son doğrulama kapılarının secret-safe özeti.",
            "Yalnızca 'Geçti' adımlar ilgili kapsam için kanıttır."
          )),
          .health_release_pill(if (vm_bulundu) vm$status else "not_found",
                               label = if (vm_bulundu) NULL else "VM Kanıtı Yok")),
      div(class = "health-hero-meta",
          span(icon("clock"), paste("Okuma:", health_safe_value(overview$generated_at))),
          span(icon("vial"), paste("VM profili:",
                                   health_safe_value(if (vm_bulundu) vm$profile_effective else "—"))))
    ),
    div(
      class = "health-metrics-grid",
      health_metric_tile("VM Geçti", if (vm_bulundu) vm$passed else "—", "check-circle",
                         if (vm_bulundu && isTRUE(vm$failed == 0L)) "ok" else "unknown",
                         "VM evidence gate geçen adım sayısı"),
      health_metric_tile("VM Başarısız", if (vm_bulundu) vm$failed else "—", "times-circle",
                         if (vm_bulundu && isTRUE(vm$failed > 0L)) "critical" else "ok",
                         "VM evidence gate başarısız adım sayısı"),
      health_metric_tile("VM Atlandı", if (vm_bulundu) vm$skipped else "—", "minus-circle",
                         "not_configured", "Atlanan adımlar kanıt değildir"),
      health_metric_tile("Log Hataları", if (log_bulundu) hata_sayisi else "—", "exclamation-circle",
                         if (log_bulundu && hata_sayisi > 0L) "critical" else "ok",
                         "Bugünkü logda ERROR satırı sayısı"),
      health_metric_tile("Log Uyarıları", if (log_bulundu) uyari_sayisi else "—", "exclamation-triangle",
                         if (log_bulundu && uyari_sayisi > 0L) "warning" else "ok",
                         "Bugünkü logda WARN satırı sayısı")
    ),
    fluidRow(
      column(
        7,
        health_section_card(
          "VM Evidence Gate",
          "shield-alt",
          if (vm_bulundu) {
            tagList(
              div(class = "health-summary-list",
                  div(strong("Genel durum:"), .health_release_pill(vm$status)),
                  div(strong("Profil:"), span(health_safe_value(vm$profile_effective))),
                  div(strong("Üretim (UTC):"), span(health_safe_value(vm$generated_at_utc))),
                  div(strong("Sayaçlar:"),
                      span(sprintf("%d geçti / %d başarısız / %d atlandı",
                                   as.integer(vm$passed %||% 0L),
                                   as.integer(vm$failed %||% 0L),
                                   as.integer(vm$skipped %||% 0L))))),
              .health_release_steps_table(vm$steps)
            )
          } else {
            div(class = "health-empty",
                "VM evidence artifact'ı bulunamadı. Cloud profili VM/SSO/DB kanıtı üretmez.")
          },
          tooltip = "run_vm_evidence_gate.R tarafından üretilen en son evidence.json özeti."
        )
      ),
      column(
        5,
        health_section_card(
          "ai_validate Özeti",
          "clipboard-check",
          if (ai_bulundu) {
            div(class = "health-summary-list",
                div(strong("Çalışma durumu:"), span(health_safe_value(ai$validation_execution_status))),
                div(strong("İstenen profil:"), span(health_safe_value(ai$profile_requested))),
                div(strong("Etkin profil:"), span(health_safe_value(ai$profile_effective))),
                div(strong("Başarısız adım:"),
                    span(health_safe_value(if (is.na(ai$failed_steps)) "—" else ai$failed_steps))),
                div(strong("App source smoke:"), .health_release_pill(ai$app_source_smoke_status)),
                div(strong("Shiny boot smoke:"), .health_release_pill(ai$shiny_boot_smoke_status)),
                div(strong("Browser smoke:"), .health_release_pill(ai$browser_smoke_status)))
          } else {
            div(class = "health-empty", "ai-validation summary.json bulunamadı.")
          },
          tooltip = "tools/ai_validate.sh tarafından üretilen en son summary.json kanıt alanları."
        )
      )
    ),
    fluidRow(
      column(
        12,
        health_section_card(
          "Günlük Log Sağlığı",
          "file-medical-alt",
          if (log_bulundu) {
            tagList(
              div(class = "health-summary-list",
                  div(strong("İncelenen satır:"), span(health_safe_value(log_saglik$window_lines))),
                  div(strong("ERROR sayısı:"), span(health_safe_value(hata_sayisi))),
                  div(strong("WARN sayısı:"), span(health_safe_value(uyari_sayisi))),
                  div(strong("Son hata zamanı:"), span(health_safe_value(log_saglik$last_error_at)))),
              # Yeni: ERROR satırlarının bağlam kategorisi dağılımı (secret-safe)
              .health_release_error_contexts(log_saglik$error_contexts)
            )
          } else {
            div(class = "health-empty", "Bugüne ait uygulama logu bulunamadı.")
          },
          tooltip = "Bugünkü mergen_*.log dosyasında sınırlı pencerede ERROR/WARN sayımı (içerik taşınmaz)."
        )
      )
    ),
    div(
      class = "health-empty health-release-proof-note",
      icon("info-circle"),
      " ",
      health_safe_value(overview$proof_note %||%
        "SKIP edilen adımlar kanıt değildir; cloud profili VM/SSO/DB kanıtı üretmez.")
    )
  )
}
