# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_health.R
# Aciklama: Faz 3b metadata ureticisi -- SORGU KUTUPHANESI SAGLIK RAPORU.
#
# BU DOSYA CALISMA ZAMANI KODU DEGILDIR; kaynak manifestine EKLENMEZ.
#
# Rapor iki okuyucu icindir:
#   * MAKINE: artifacts/pk-meta/<zaman>/health.json
#   * INSAN : ayni dizinde health.txt + konsol ozeti
#
# GIZLI DEGER SIZDIRMAZ: DSN, kimlik bilgisi, jeton, baglanti dizesi ve
# URETIM SATIR DEGERLERI rapora GIRMEZ. Sema/sutun ADLARI operatorun kendi
# VM'inde beklenen ve gerekli bilgidir; satir ICERIGI degildir.
# ==============================================================================

PKG_HEALTH_STATUS <- c("ok", "withheld", "failed", "skipped")

# Bulgu siddetleri:
#   blocking  -> uretilen sema ILE baslangic dogrulamasini DUSURURDU; sorgu
#                bu kosuda uretilen katmandan GERI CEKILIR (withheld).
#   attention -> operator eylemi gerekir ama baslangici dusurmez.
#   info      -> bilgilendirme.
PKG_HEALTH_SEVERITIES <- c("blocking", "attention", "info")

.pkgh_redact <- function(x) {
  metin <- as.character(x %||% "")[1]
  if (is.na(metin)) return("")
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin), error = function(e) metin)
  }
  # Yerel yedek: DSN/uc nokta bicimlerini kaba bicimde maskele.
  metin <- gsub("(?i)(dsn|uid|pwd|password|server|database)\\s*=\\s*[^;\\s]+",
                "\\1=<gizli>", metin, perl = TRUE)
  metin <- gsub("(?i)(https?://)[^\\s;'\"]+", "\\1<gizli>", metin, perl = TRUE)
  metin
}

#' Tek bir bulgu kaydi
pkgh_finding <- function(code, severity, detail, columns = character(0),
                         security = FALSE) {
  if (!(severity %in% PKG_HEALTH_SEVERITIES)) severity <- "attention"
  list(
    code = as.character(code)[1],
    severity = severity,
    security_relevant = isTRUE(security),
    detail = .pkgh_redact(detail),
    columns = as.character(columns %||% character(0))
  )
}

#' Sorgu icin YAPISAL saglik bulgularini uret
#'
#' Girdi:
#'   query   : query_library ogesi (id, name, db_target, rls_columns, ...)
#'   merged  : uretilen yerel katman + kuresyon birlesmis metadata
#'   schema  : uretilen sema (adlandirilmis karakter vektoru) veya NULL
#'   blocking: `pk_meta_validate_schema_dependent()` ciktisi (mesaj vektoru)
#'
#' `pk_meta_validate_actual_columns()` CALISMA ZAMANI kapisidir ve burada AYNEN
#' kullanilir: rapor ile istek zamani zorlamasi ayni mantigi paylasir, boylece
#' rapor "temiz" derken uretimde patlayan bir uyusmazlik kalmaz.
pkgh_structural_findings <- function(query, merged, schema, blocking = character(0)) {
  bulgular <- list()
  sema_sutunlari <- if (is.null(schema)) character(0) else names(schema)
  sema_sutunlari <- sema_sutunlari[!is.na(sema_sutunlari) & nzchar(trimws(sema_sutunlari))]

  # --- 1) RLS: GUVENLIK KRITIK -------------------------------------------------
  # Beyan edilen bir RLS sutunu gercek sonucda yoksa, o sorgu istek zamaninda
  # KAPALI BASARISIZ olur (D6). Otomatik olarak KALDIRILMAZ/DEVRE DISI
  # BIRAKILMAZ; operator ya SQL'i ya beyani duzeltir.
  rls <- if (is.list(query)) query$rls_columns else NULL
  rls_beyan <- character(0)
  if (is.list(rls)) {
    for (alan in names(rls)) {
      deger <- rls[[alan]]
      if (is.null(deger)) next
      if (is.character(deger) && length(deger) == 1L && !is.na(deger) && nzchar(trimws(deger))) {
        rls_beyan <- c(rls_beyan, trimws(deger))
      }
    }
  }
  rls_beyan <- unique(rls_beyan)

  if (length(sema_sutunlari) && length(rls_beyan)) {
    eksik_rls <- setdiff(rls_beyan, sema_sutunlari)
    if (length(eksik_rls)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "rls_column_missing", "blocking",
        sprintf(
          paste0(
            "Beyan edilen RLS sutunu gercek sonucda yok: %s. ",
            "Ya SQL bu guvenlik sutununu dondurmeli ya da rls_columns beyani yanlis. ",
            "Beyan OTOMATIK KALDIRILMAZ; istek zamaninda sorgu kapali basarisiz olur."
          ),
          paste(eksik_rls, collapse = ", ")
        ),
        columns = eksik_rls, security = TRUE
      )))
    }
  }

  if (!length(rls_beyan)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "rls_not_declared", "info",
      "Sorgu icin RLS sutunu beyan edilmemis (yetki filtresi uygulanmayacak)."
    )))
  }

  # --- 2) Metadata atiflari semada var mi? -------------------------------------
  if (length(sema_sutunlari)) {
    cmeta_adlari <- names(merged$column_meta %||% list())
    eksik_cmeta <- setdiff(cmeta_adlari, sema_sutunlari)
    if (length(eksik_cmeta)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "column_meta_missing_in_schema", "blocking",
        sprintf("column_meta sutunu semada yok: %s", paste(eksik_cmeta, collapse = ", ")),
        columns = eksik_cmeta
      )))
    }

    atif_alanlari <- list(
      grain_columns = merged$grain_columns,
      default_group_by = merged$default_group_by,
      default_measures = merged$default_measures,
      primary_entity = merged$primary_entity
    )
    for (alan in names(atif_alanlari)) {
      deger <- atif_alanlari[[alan]]
      if (!is.character(deger) || !length(deger)) next
      eksik <- setdiff(deger[!is.na(deger) & nzchar(trimws(deger))], sema_sutunlari)
      if (length(eksik)) {
        bulgular <- c(bulgular, list(pkgh_finding(
          sprintf("%s_missing_in_schema", alan), "blocking",
          sprintf("%s beyan edilen sutun semada yok: %s", alan, paste(eksik, collapse = ", ")),
          columns = eksik
        )))
      }
    }
  }

  # --- 3) Rol / tip uyusmazliklari ---------------------------------------------
  # Kuresyon "measure" derken semadaki tip metin ise, sessizce yanlis toplam
  # uretilmeden ONCE yakalanmalidir.
  if (length(sema_sutunlari) &&
      exists(".pk_meta_role_from_class", mode = "function", inherits = TRUE)) {
    uyusmaz <- character(0)
    for (sutun in intersect(names(merged$column_meta %||% list()), sema_sutunlari)) {
      cmeta <- merged$column_meta[[sutun]]
      if (!is.list(cmeta) || is.null(cmeta$role)) next
      yapisal <- .pk_meta_role_from_class(schema[[sutun]])
      if (identical(cmeta$role, "date") && !identical(yapisal, "date")) {
        uyusmaz <- c(uyusmaz, sprintf("%s (role=date, sema=%s)", sutun, schema[[sutun]]))
      }
      if (identical(cmeta$role, "measure") && !identical(yapisal, "measure")) {
        uyusmaz <- c(uyusmaz, sprintf("%s (role=measure, sema=%s)", sutun, schema[[sutun]]))
      }
    }
    if (length(uyusmaz)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "role_type_mismatch", "blocking",
        sprintf("Beyan edilen role semadaki tiple uyusmuyor: %s", paste(uyusmaz, collapse = "; "))
      )))
    }
  }

  # --- 4) Anlamsal yetenek durumu ----------------------------------------------
  yetenekler <- character(0)
  for (cmeta in (merged$column_meta %||% list())) {
    if (is.list(cmeta) && is.character(cmeta$capability) && length(cmeta$capability) == 1L &&
        !is.na(cmeta$capability) && nzchar(trimws(cmeta$capability))) {
      yetenekler <- c(yetenekler, trimws(cmeta$capability))
    }
  }
  yetenekler <- unique(yetenekler)

  if (!length(yetenekler)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_semantic_capability", "attention",
      paste0(
        "Sorguda anlamsal yetenek (capability) beyani YOK. Olcu/tarih/boyut ",
        "gerektiren istekler bu sorgu icin SQL'den ONCE ",
        "'unknown_no_semantic_metadata' ile durur. Uretici bunu KENDILIGINDEN ",
        "dolduramaz: hangi sayinin planlanan hangisinin kalan isgucu oldugu ",
        "insan kuresyonudur (R/library_query_meta.R)."
      )
    )))
  }

  if (is.null(merged$primary_entity)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_primary_entity", "attention",
      "primary_entity beyan edilmemis; Tier-0 geri dususu uygulanir (tek filtre yapragi birincil)."
    )))
  }
  if (is.null(merged$grain)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_grain", "info",
      "grain beyan edilmemis; mukerrer satir elemesi YAPILMAZ."
    )))
  }

  # --- 5) Baslangici dusurecek ham bulgular (otoriter) --------------------------
  # `pk_meta_validate_schema_dependent()` baslangicta CALISAN dogrulayicidir.
  # Yukaridaki yapisal bulgular okunabilirlik icindir; KARAR bu listeden verilir.
  if (length(blocking)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "startup_validation_would_fail", "blocking",
      paste(blocking, collapse = " | ")
    )))
  }

  bulgular
}

#' Sorgu saglik kaydi olustur
pkgh_query_record <- function(query, status, mode, schema = NULL, findings = list(),
                              error = NULL, sample_info = list()) {
  if (!(status %in% PKG_HEALTH_STATUS)) status <- "failed"

  sutun_adlari <- if (is.null(schema)) character(0) else names(schema)
  siddetler <- vapply(findings, function(f) as.character(f$severity)[1], character(1))
  guvenlik <- vapply(findings, function(f) isTRUE(f$security_relevant), logical(1))

  list(
    query_id = as.character(query$id %||% NA_character_)[1],
    query_name = as.character(query$name %||% NA_character_)[1],
    db_target = as.character(query$db_target %||% "primary")[1],
    status = status,
    mode = as.character(mode)[1],
    schema_obtained = !is.null(schema) && length(sutun_adlari) > 0L,
    column_count = length(sutun_adlari),
    schema_validation = if (!is.null(schema) && length(sutun_adlari)) {
      "validated"
    } else {
      "pending_no_schema"
    },
    tier0 = is.null(schema) || !length(sutun_adlari),
    blocking_count = sum(siddetler == "blocking"),
    attention_count = sum(siddetler == "attention"),
    security_finding_count = sum(guvenlik),
    needs_curation = any(vapply(findings, function(f) {
      identical(f$code, "no_semantic_capability")
    }, logical(1))),
    error = if (is.null(error)) NA_character_ else .pkgh_redact(error),
    sample = sample_info,
    findings = findings
  )
}

#' Rapor ozetini hesapla
pkgh_summarize <- function(records) {
  say <- function(pred) sum(vapply(records, pred, logical(1)))

  list(
    total_queries = length(records),
    described_or_sampled = say(function(r) isTRUE(r$schema_obtained)),
    schema_failures = say(function(r) identical(r$status, "failed")),
    withheld = say(function(r) identical(r$status, "withheld")),
    skipped = say(function(r) identical(r$status, "skipped")),
    included = say(function(r) identical(r$status, "ok")),
    rls_mismatches = say(function(r) r$security_finding_count > 0L),
    blocking_queries = say(function(r) r$blocking_count > 0L),
    tier0_queries = say(function(r) isTRUE(r$tier0)),
    queries_needing_curation = say(function(r) isTRUE(r$needs_curation)),
    queries_with_semantics = say(function(r) !isTRUE(r$needs_curation))
  )
}

.pkgh_status_label <- function(status) {
  switch(as.character(status)[1],
    ok = "DAHIL",
    withheld = "GERI CEKILDI",
    failed = "BASARISIZ",
    skipped = "ATLANDI",
    "?"
  )
}

#' Insan tarafindan okunabilir rapor metni
pkgh_render_text <- function(summary, records, config_summary) {
  satirlar <- c(
    "===============================================================================",
    " MERGEN Bilge -- Proje ve Kaynak Analizi / Sorgu Kutuphanesi Saglik Raporu",
    " Faz 3b metadata ureticisi",
    "===============================================================================",
    "",
    sprintf("Kip                        : %s", config_summary$mode),
    sprintf("Ornek satir siniri         : %s", format(config_summary$sample_rows)),
    sprintf("Yuksek kardinalite esigi   : %s", format(config_summary$high_cardinality_threshold)),
    sprintf("Uretilen katman            : %s", config_summary$output_rel),
    "",
    "-- SAYIMLAR --------------------------------------------------------------",
    sprintf("Toplam sorgu               : %d", summary$total_queries),
    sprintf("Sema alinan                : %d", summary$described_or_sampled),
    sprintf("Uretilen katmana dahil     : %d", summary$included),
    sprintf("GERI CEKILEN (bloklayici)  : %d", summary$withheld),
    sprintf("Sema alinamayan (hata)     : %d", summary$schema_failures),
    sprintf("Atlanan (guvenlik/gate)    : %d", summary$skipped),
    sprintf("RLS UYUSMAZLIGI olan       : %d", summary$rls_mismatches),
    sprintf("Tier-0 kalan               : %d", summary$tier0_queries),
    sprintf("Anlamsal kuresyon gereken  : %d", summary$queries_needing_curation),
    ""
  )

  sorunlu <- Filter(function(r) {
    r$blocking_count > 0L || identical(r$status, "failed") ||
      identical(r$status, "skipped") || r$security_finding_count > 0L
  }, records)

  if (!length(sorunlu)) {
    satirlar <- c(satirlar,
      "-- BULGU YOK -------------------------------------------------------------",
      "Bloklayici bulgu yok. Anlamsal kuresyon listesi asagidadir.",
      ""
    )
  } else {
    satirlar <- c(satirlar,
      "-- EYLEM GEREKTIREN SORGULAR ---------------------------------------------",
      ""
    )
    for (r in sorunlu) {
      satirlar <- c(satirlar, sprintf(
        "[%s] %s -- %s (db=%s)",
        .pkgh_status_label(r$status), r$query_id, r$query_name, r$db_target
      ))
      if (!is.na(r$error) && nzchar(r$error)) {
        satirlar <- c(satirlar, sprintf("    hata: %s", r$error))
      }
      for (f in r$findings) {
        if (identical(f$severity, "info")) next
        satirlar <- c(satirlar, sprintf(
          "    - [%s%s] %s: %s",
          f$severity,
          if (isTRUE(f$security_relevant)) "/GUVENLIK" else "",
          f$code, f$detail
        ))
      }
      satirlar <- c(satirlar, "")
    }
  }

  kuresyon <- Filter(function(r) isTRUE(r$needs_curation) && identical(r$status, "ok"), records)
  if (length(kuresyon)) {
    satirlar <- c(satirlar,
      "-- ANLAMSAL KURESYON BEKLEYEN SORGULAR -----------------------------------",
      "Bu sorgular YAPISAL olarak saglikli; ancak capability beyani olmadigi icin",
      "olcu/tarih/boyut gerektiren istekler SQL'den ONCE durur (fail-closed).",
      "Telemetriye gore en cok kullanilan ~30 sorguyu R/library_query_meta.R",
      "icinde kure edin.",
      ""
    )
    for (r in kuresyon) {
      satirlar <- c(satirlar, sprintf("    %s -- %s", r$query_id, r$query_name))
    }
    satirlar <- c(satirlar, "")
  }

  satirlar <- c(satirlar,
    "-- SONRAKI ADIM ----------------------------------------------------------",
    "1) Bloklayici/GUVENLIK bulgularini duzeltin (SQL ya da rls_columns beyani).",
    "2) Uretici yeniden calistirilir; geri cekilen sorgular tekrar degerlendirilir.",
    "3) Anlamsal kuresyon R/library_query_meta.R icinde yapilir (elle).",
    "4) MERGEN Bilge YENIDEN BASLATILIR (tarayici yenilemesi YETMEZ).",
    "==============================================================================="
  )

  paste(satirlar, collapse = "\n")
}

#' Saglik raporu artefaktlarini yaz
#'
#' Giris betiginden AYRILMISTIR ki artefakt yazma yolu (JSON + metin + dizin
#' olusturma) uygulama bootstrap'i OLMADAN test edilebilsin.
#'
#' @return Yazilan dosya yollari.
pkgh_write_artifacts <- function(report, artifact_dir, records, summary,
                                 config_summary) {
  if (!dir.exists(artifact_dir)) {
    dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  }

  json_yolu <- file.path(artifact_dir, "health.json")
  metin_yolu <- file.path(artifact_dir, "health.txt")

  if (exists("atomic_write_json", mode = "function", inherits = TRUE)) {
    atomic_write_json(report, json_yolu)
  } else {
    con <- file(json_yolu, open = "wb")
    on.exit(close(con), add = TRUE)
    writeBin(charToRaw(enc2utf8(as.character(jsonlite::toJSON(
      report, auto_unbox = TRUE, pretty = TRUE, null = "null"
    )))), con)
  }

  metin <- pkgh_render_text(summary, records, config_summary)
  con2 <- file(metin_yolu, open = "wb")
  writeBin(charToRaw(enc2utf8(metin)), con2)
  close(con2)

  list(json = json_yolu, text = metin_yolu)
}

#' Devam (resume) onbellegi durumunu yaz
#'
#' Onbellek YALNIZCA DB gozlemlerini tasir; karar/kuresyon her kosuda YENIDEN
#' hesaplanir, boylece kuresyon degisikligi onbellek yuzunden kacirilmaz.
pkgh_write_state <- function(cache, state_path, mode, timestamp) {
  girdiler <- unname(lapply(names(cache %||% list()), function(id) {
    girdi <- cache[[id]]
    sema <- girdi$columns
    tipler <- girdi$source_types %||% character(0)
    list(
      query_id = id,
      columns = unname(lapply(names(sema), function(sutun) list(
        name = sutun,
        r_class = unname(sema[[sutun]]),
        source_type = if (sutun %in% names(tipler)) {
          unname(tipler[[sutun]])
        } else {
          NA_character_
        }
      )))
    )
  }))

  durum <- list(mode = mode, timestamp = timestamp, entries = girdiler)

  dizin <- dirname(state_path)
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    con <- file(state_path, open = "wb")
    on.exit(close(con), add = TRUE)
    writeBin(charToRaw(enc2utf8(as.character(jsonlite::toJSON(
      durum, auto_unbox = TRUE, pretty = TRUE, null = "null"
    )))), con)
    invisible(state_path)
  }, error = function(e) invisible(NULL))
}

#' Devam onbellegini geri oku
#'
#' Kip DEGISTIYSE onbellek YOK SAYILIR: `describe` ile alinmis bir sema
#' `sample` kosusunun gozlemlerini tasimaz.
pkgh_read_state <- function(state_path, mode) {
  if (!file.exists(state_path)) return(list())

  tryCatch({
    ham <- jsonlite::fromJSON(state_path, simplifyVector = FALSE)
    if (!identical(as.character(ham$mode)[1], as.character(mode)[1])) return(list())

    cikti <- list()
    for (girdi in (ham$entries %||% list())) {
      id <- as.character(girdi$query_id %||% "")[1]
      sutunlar <- girdi$columns %||% list()
      if (!nzchar(id) || !length(sutunlar)) next

      adlar <- vapply(sutunlar, function(s) as.character(s$name)[1], character(1))
      siniflar <- vapply(sutunlar, function(s) as.character(s$r_class)[1], character(1))
      tipler <- vapply(sutunlar, function(s) {
        as.character(s$source_type %||% NA_character_)[1]
      }, character(1))

      sema <- stats::setNames(siniflar, adlar)
      kaynak <- stats::setNames(tipler, adlar)

      cikti[[id]] <- list(
        ok = TRUE, schema = sema, source_types = kaynak,
        unmapped = character(0), unbounded = character(0), observations = list(),
        sample_info = list(mode = mode, from_cache = TRUE),
        cache = list(mode = mode, columns = sema, source_types = kaynak)
      )
    }
    cikti
  }, error = function(e) list())
}

#' Konsol ozeti (kisa)
pkgh_render_console <- function(summary, records) {
  satirlar <- c(
    "",
    "[PK_META_GEN] ---------------- SAGLIK OZETI ----------------",
    sprintf("[PK_META_GEN] Toplam sorgu            : %d", summary$total_queries),
    sprintf("[PK_META_GEN] Sema alinan             : %d", summary$described_or_sampled),
    sprintf("[PK_META_GEN] Uretilen katmana dahil  : %d", summary$included),
    sprintf("[PK_META_GEN] GERI CEKILEN            : %d", summary$withheld),
    sprintf("[PK_META_GEN] Sema alinamayan         : %d", summary$schema_failures),
    sprintf("[PK_META_GEN] Atlanan                 : %d", summary$skipped),
    sprintf("[PK_META_GEN] RLS UYUSMAZLIGI         : %d", summary$rls_mismatches),
    sprintf("[PK_META_GEN] Tier-0 kalan            : %d", summary$tier0_queries),
    sprintf("[PK_META_GEN] Kuresyon bekleyen       : %d", summary$queries_needing_curation)
  )

  guvenlik <- Filter(function(r) r$security_finding_count > 0L, records)
  if (length(guvenlik)) {
    satirlar <- c(satirlar,
      "[PK_META_GEN]",
      "[PK_META_GEN] !!! GUVENLIK: RLS BEYANI ILE GERCEK SONUC UYUSMUYOR !!!"
    )
    for (r in guvenlik) {
      satirlar <- c(satirlar, sprintf("[PK_META_GEN]   %s -- %s", r$query_id, r$query_name))
    }
  }

  satirlar <- c(satirlar, "[PK_META_GEN] ------------------------------------------------", "")
  paste(satirlar, collapse = "\n")
}
