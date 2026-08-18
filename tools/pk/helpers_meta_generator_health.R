# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_health.R
# Açıklama: Faz 3b metadata üreticisi -- SORGU KÜTÜPHANESİ SAĞLIK RAPORU.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Rapor iki okuyucu içindir:
#   * MAKİNE: artifacts/pk-meta/<koşu>/health.json
#   * İNSAN : aynı dizinde health.txt + konsol özeti
#
# Bulgu ÜRETİMİ ayrı dosyadadır (helpers_meta_generator_findings.R); burada
# yalnızca KAYIT, SAYIM, BİÇİMLENDİRME ve ARTEFAKT YAZMA vardır.
# ==============================================================================

PKG_HEALTH_STATUS <- c("ok", "withheld", "failed", "skipped")

# ŞEMA ALINAMAMASINA özgü başarısızlık kodları. `failed` durumu bundan DAHA
# GENİŞTİR (örneğin `missing_query_id` hiçbir DB çağrısı yapılmadan üretilir);
# hepsini "şema alınamadı" saymak kusuru yanlış katmana atfeder.
PKG_HEALTH_SCHEMA_FAILURE_CODES <- c(
  "no_connection", "describe_failed", "describe_unavailable",
  "describe_empty_schema", "describe_invalid_schema",
  "sample_failed", "sample_not_dataframe", "sample_no_columns",
  "sample_invalid_schema", "sample_not_normalized", "sample_not_server_bounded",
  "schema_unavailable"
)

# `health.json` içinde HER ZAMAN dizi olarak kalması gereken alanlar.
#
# `auto_unbox = TRUE` atomik vektörleri KARDİNALİTEYE göre farklı JSON türüne
# çevirir: tek ögeli `columns` bir dize, iki ögeli ise dizi olur. Makine
# okuyucusu böylece her alan için skaler-ya-da-dizi özel durumu yazmak zorunda
# kalır ve bir sorgu tek eksik sütundan iki eksik sütuna geçtiğinde KIRILIR.
PKG_HEALTH_ARRAY_FIELDS <- c(
  "queries", "findings", "columns", "unmapped", "unbounded", "invalid",
  "entries", "records", "problem_query_ids", "curation_query_ids"
)

.pkgh_status_of <- function(record) as.character(record$status %||% "")[1]

.pkgh_finding_codes <- function(findings) {
  if (!length(findings)) return(character(0))
  vapply(findings, function(f) as.character(f$code %||% "")[1], character(1))
}

#' Sorgu sağlık kaydı oluştur
#'
#' HAZIRLIK DURUMU ŞEMANIN VARLIĞINDAN DEĞİL, DAHİL EDİLME KARARINDAN türer.
#' Bloklayıcı bir bulgu yüzünden geri çekilen bir sorgunun şeması ELDE olsa da
#' üretilen katmana GİRMEZ; çalışma zamanı onu Tier-0/`pending_no_schema`
#' olarak görür. Rapor bunu `validated` diye bildirseydi operatöre YANLIŞ bir
#' hazırlık tablosu sunardı.
pkgh_query_record <- function(query, status, mode, schema = NULL, findings = list(),
                              error = NULL, sample_info = list()) {
  if (!(status %in% PKG_HEALTH_STATUS)) status <- "failed"

  sutun_adlari <- if (is.null(schema)) character(0) else names(schema)
  siddetler <- vapply(findings, function(f) as.character(f$severity)[1], character(1))
  guvenlik <- vapply(findings, function(f) isTRUE(f$security_relevant), logical(1))
  kodlar <- .pkgh_finding_codes(findings)

  dahil <- identical(status, "ok")
  sema_var <- !is.null(schema) && length(sutun_adlari) > 0L

  # Kararlı kimlik: `query_library` sözleşmesi boşluklu bir id'yi kabul edip
  # `trimws()` ile kanonik hâle getirir. Rapor da AYNI kanonik kimliği
  # kullanmalıdır, aksi hâlde JSON kaydı ile üretilen metadata anahtarı farklı
  # olur ve makine korelasyonu kırılır.
  ham_id <- as.character(query$id %||% NA_character_)[1]
  kimlik <- if (is.na(ham_id)) NA_character_ else trimws(ham_id)

  list(
    query_id = kimlik,
    query_name = as.character(query$name %||% NA_character_)[1],
    # KANONİK HEDEF: envanter, hedefi büyük/küçük harf ve boşluktan bağımsız
    # doğrular ve BAĞLANTIYI kanonik `primary`/`secondary`/`tertiary` değeriyle
    # açar. Ham alanı yeniden serileştirmek, `" Secondary "` gibi geçerli bir
    # beyanda `health.json` içinde ÇALIŞTIRILANDAN FARKLI bir hedef bildirir ve
    # makine tarafında kararlı gruplama/korelasyonu kırar.
    db_target = .pkgh_canonical_db_target(query$db_target),
    status = status,
    mode = as.character(mode)[1],
    schema_obtained = sema_var,
    from_cache = isTRUE(sample_info$from_cache),
    column_count = length(sutun_adlari),
    schema_validation = if (dahil && sema_var) "validated" else "pending_no_schema",
    tier0 = !(dahil && sema_var),
    blocking_count = sum(siddetler == "blocking"),
    attention_count = sum(siddetler == "attention"),
    security_finding_count = sum(guvenlik),
    schema_failure = identical(status, "failed") &&
      any(kodlar %in% PKG_HEALTH_SCHEMA_FAILURE_CODES),
    # Anlamsal küresyon kontrolü YALNIZCA dahil edilen sorgular için ÇALIŞIR;
    # başarısız/atlanan bir sorguda kontrol hiç yapılmadığı için ne "küresyon
    # gerekiyor" ne de "anlamsal metadata var" denebilir.
    semantics_checked = dahil,
    needs_curation = dahil && any(kodlar == "no_semantic_capability"),
    error = if (is.null(error)) NA_character_ else .pkgh_redact(error),
    # TÜR KARARLILIĞI: `auto_unbox = TRUE` altında BOŞ ADSIZ liste `[]` (dizi),
    # dolu liste ise `{...}` (nesne) olur. Aynı alanın sorgu durumuna göre tür
    # değiştirmesi, şema kararlı makine tüketicilerini KIRAR. Boş durum bu
    # yüzden `null` olarak yazılır.
    sample = if (is.list(sample_info) && length(sample_info)) sample_info else NULL,
    findings = findings
  )
}

# Envanter ile AYNI kanonikleştirme. Doğrulayıcı yoksa (izole test) ham değer
# korunur; bir teşhis alanı için sessiz bir varsayılan uydurmak yanlış olurdu.
.pkgh_canonical_db_target <- function(raw) {
  ham <- as.character(raw %||% "primary")[1]
  if (is.na(ham) || !nzchar(trimws(ham))) return("primary")

  if (exists("pkg_meta_validate_db_target", mode = "function", inherits = TRUE)) {
    dogrulama <- tryCatch(pkg_meta_validate_db_target(ham), error = function(e) NULL)
    if (is.list(dogrulama) && isTRUE(dogrulama$ok)) return(as.character(dogrulama$target)[1])
  }
  trimws(ham)
}

# ÜRETİLEN KATMANLA UZLAŞTIRMA.
#
# `pkgc_merge_local_layers()` GEÇİCİ bir başarısızlıkta önceki GEÇERLİ girdiyi
# KORUR. Kayıt yalnızca BU KOŞUNUN getirme durumuna baktığı için, o sorgu son
# katmanda gerçek bir şemayla dururken raporda `pending_no_schema`/Tier-0 diye
# görünürdü. Hazırlık durumu SON ADAY KATMANDAN türetilir.
#
# `withheld` ve `ok` durumları DEĞİŞMEZ: `ok` zaten `validated`, `withheld` ise
# bilinçli olarak katmandan çıkarılmıştır.
pkgh_reconcile_records_with_layer <- function(records, layer) {
  katman <- if (is.list(layer)) layer else list()
  if (!length(records)) return(records)

  lapply(records, function(r) {
    durum <- .pkgh_status_of(r)
    if (!(durum %in% c("failed", "skipped"))) return(r)

    id <- as.character(r$query_id %||% NA_character_)[1]
    if (is.na(id) || is.null(katman[[id]])) return(r)

    r$schema_validation <- "preserved_previous"
    r$tier0 <- FALSE
    r$preserved_previous <- TRUE
    r
  })
}

#' Rapor özetini hesapla
pkgh_summarize <- function(records) {
  say <- function(pred) sum(vapply(records, pred, logical(1)))

  list(
    total_queries = length(records),
    # DB'ye BU KOŞUDA gidilen sorgular. Önbellekten gelenler ayrı sayılır;
    # aksi hâlde tamamen devam önbelleğinden çalışan bir koşu "hepsi
    # describe/sample edildi" der ve üretilen kanıtı ABARTIR.
    described_or_sampled = say(function(r) isTRUE(r$schema_obtained) && !isTRUE(r$from_cache)),
    from_cache = say(function(r) isTRUE(r$from_cache)),
    schema_failures = say(function(r) isTRUE(r$schema_failure)),
    failed_queries = say(function(r) identical(.pkgh_status_of(r), "failed")),
    withheld = say(function(r) identical(.pkgh_status_of(r), "withheld")),
    skipped = say(function(r) identical(.pkgh_status_of(r), "skipped")),
    # `included` = bu koşuda ADAY katmana giren sorgu sayısı. Bütün kütüphane
    # kapısı düşerse hiçbir şey YAZILMAZ; yazılan sayı ayrıca raporlanır.
    included = say(function(r) identical(.pkgh_status_of(r), "ok")),
    rls_mismatches = say(function(r) r$security_finding_count > 0L),
    blocking_queries = say(function(r) r$blocking_count > 0L),
    attention_queries = say(function(r) r$attention_count > 0L),
    tier0_queries = say(function(r) isTRUE(r$tier0)),
    # Bu koşuda sorgulanamayan ama ÖNCEKİ geçerli metadata'sı katmanda KALAN
    # sorgular. Tier-0 sayısından ayrı raporlanır, aksi hâlde operatör bunları
    # şemasız sanır.
    preserved_previous = say(function(r) isTRUE(r$preserved_previous)),
    queries_needing_curation = say(function(r) isTRUE(r$needs_curation)),
    queries_with_semantics = say(function(r) {
      isTRUE(r$semantics_checked) && !isTRUE(r$needs_curation)
    })
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

# Operatör EYLEMİ gerektiren kayıtlar. `attention` tanımı gereği eylem
# gerektirir; yalnızca bloklayıcı/başarısız kayıtları listelemek, örneğin tek
# bulgusu `unmapped_sql_type` olan bir sorguyu insan raporundan TAMAMEN
# gizlerdi (ve yalnızca böyle bulgular varken rapor "BULGU YOK" derdi).
.pkgh_needs_attention <- function(r) {
  r$blocking_count > 0L || r$attention_count > 0L ||
    identical(.pkgh_status_of(r), "failed") ||
    identical(.pkgh_status_of(r), "skipped") ||
    r$security_finding_count > 0L
}

#' İnsan tarafından okunabilir rapor metni
pkgh_render_text <- function(summary, records, config_summary) {
  satirlar <- c(
    "===============================================================================",
    " MERGEN Bilge -- Proje ve Kaynak Analizi / Sorgu Kutuphanesi Saglik Raporu",
    " Faz 3b metadata ureticisi",
    "===============================================================================",
    "",
    sprintf("Kip                        : %s", config_summary$mode),
    sprintf("Kosu kimligi               : %s", config_summary$run_id %||% "?"),
    sprintf("Ornek satir siniri         : %s", format(config_summary$sample_rows)),
    sprintf("Yuksek kardinalite esigi   : %s", format(config_summary$high_cardinality_threshold)),
    sprintf("Uretilen katman            : %s", config_summary$output_rel),
    "",
    "-- SAYIMLAR --------------------------------------------------------------",
    sprintf("Toplam sorgu               : %d", summary$total_queries),
    sprintf("Bu kosuda sema alinan      : %d", summary$described_or_sampled),
    sprintf("Devam onbelleginden gelen  : %d", summary$from_cache %||% 0L),
    sprintf("Aday katmana dahil         : %d", summary$included),
    sprintf("GERI CEKILEN (bloklayici)  : %d", summary$withheld),
    sprintf("Sema alinamayan            : %d", summary$schema_failures),
    sprintf("Basarisiz (tum nedenler)   : %d", summary$failed_queries %||% 0L),
    sprintf("Atlanan (guvenlik/gate)    : %d", summary$skipped),
    sprintf("RLS/GUVENLIK bulgusu olan  : %d", summary$rls_mismatches),
    sprintf("Tier-0 kalan               : %d", summary$tier0_queries),
    sprintf("Onceki metadata KORUNAN    : %d", summary$preserved_previous %||% 0L),
    sprintf("Anlamsal kuresyon gereken  : %d", summary$queries_needing_curation),
    ""
  )

  if (!is.null(summary$written_entries)) {
    satirlar <- c(satirlar, sprintf(
      "Uretilen katmana YAZILAN   : %d", summary$written_entries
    ), "")
  }

  sorunlu <- Filter(.pkgh_needs_attention, records)

  if (!length(sorunlu)) {
    satirlar <- c(satirlar,
      "-- BULGU YOK -------------------------------------------------------------",
      "Bloklayici ya da eylem gerektiren bulgu yok.",
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

  kuresyon <- Filter(function(r) isTRUE(r$needs_curation), records)
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

#' Raporu JSON tür kararlılığı için hazırla
#'
#' Koleksiyon alanları `I(...)` ile işaretlenir; böylece tek ögeli bir alan da
#' JSON dizisi olarak yazılır.
pkgh_stabilize_report <- function(x, array_fields = PKG_HEALTH_ARRAY_FIELDS) {
  if (is.list(x)) {
    adlar <- names(x)
    for (i in seq_along(x)) {
      oge <- pkgh_stabilize_report(x[[i]], array_fields)

      ad <- if (is.null(adlar)) "" else as.character(adlar[i])
      if (nzchar(ad) && ad %in% array_fields && !is.null(oge) && is.atomic(oge)) {
        oge <- I(unname(oge))
      }

      # NULL ATAMASI ÖGEYİ SİLER.
      #
      # `x[[i]] <- NULL` bir liste ögesini KALDIRIR ve kalan ögeleri KAYDIRIR;
      # döngü de sonraki turda "subscript out of bounds" ile düşer. Rapor
      # kayıtları bilinçli olarak `NULL` alan taşır (örneğin boş `sample`,
      # `null = "null"` ile JSON `null` olarak yazılır), bu yüzden değer
      # `x[i] <- list(oge)` ile KORUNARAK atanır.
      x[i] <- list(oge)
    }
    return(x)
  }
  x
}

# Aynı dizindeki iki dosyayı, canlı hedefin üzerine KOPYALAMADAN, yedekli
# `file.rename()` takasıyla değiştir. Bu yardımcı hem JSON hem insan raporu için
# kullanılır; süreç ortasında düşse bile eski dosyanın baytları yarım kalmaz.
.pkgh_replace_with_backup <- function(staged, path, attempts = 3L) {
  if (!file.exists(path)) return(FALSE)

  yedek <- paste0(path, ".bak-", Sys.getpid(), "-", format(Sys.time(), "%Y%m%d%H%M%OS6"))
  yedek <- gsub(":", "", yedek, fixed = TRUE)
  if (file.exists(yedek)) unlink(yedek)

  tasi <- function(from, to) {
    deneme <- max(1L, suppressWarnings(as.integer(attempts)[1]))
    for (i in seq_len(deneme)) {
      if (isTRUE(tryCatch(file.rename(from, to), error = function(e) FALSE))) return(TRUE)
      if (i < deneme) Sys.sleep(0.05)
    }
    FALSE
  }

  if (!tasi(path, yedek)) return(FALSE)
  if (!tasi(staged, path)) {
    geri <- tasi(yedek, path)
    if (!geri) {
      stop(sprintf(
        "[PK_META_GEN] Artefakt atomik takasi basarisiz; onceki dosya YEDEKTE: %s",
        yedek
      ), call. = FALSE)
    }
    return(FALSE)
  }

  if (file.exists(yedek)) unlink(yedek)
  TRUE
}

# Metin/JSON artefaktını geçici dosyaya yazıp yerine taşı. Yarım bir rapor
# operatörü yanıltır; ayrıca RStudio sürecinde açık kalan bir tutamaç Windows'ta
# sonraki koşuyu engelleyebilir.
.pkgh_atomic_write_bytes <- function(bytes, path) {
  gecici <- paste0(path, ".tmp-", Sys.getpid())
  basarili <- FALSE
  on.exit(if (!basarili && file.exists(gecici)) unlink(gecici), add = TRUE)

  con <- file(gecici, open = "wb")
  acik <- TRUE
  on.exit(if (acik) tryCatch(close(con), error = function(e) NULL), add = TRUE)
  writeBin(bytes, con)
  close(con)
  acik <- FALSE

  if (!isTRUE(tryCatch(file.rename(gecici, path), error = function(e) FALSE))) {
    if (!.pkgh_replace_with_backup(gecici, path)) {
      stop(sprintf("[PK_META_GEN] Artefakt yazilamadi: %s", path), call. = FALSE)
    }
  }

  basarili <- TRUE
  invisible(path)
}

#' Koşuya özel artefakt dizinini ÇARPIŞMASIZ ayır
#'
#' `run_id` milisaniye + süreç kimliği taşıdığı için çarpışma pratikte olanaksız
#' olsa da, var olan bir rapor dizini ASLA üzerine yazılmaz.
pkgh_allocate_artifact_dir <- function(artifact_dir, max_suffix = 50L) {
  dolu <- function(yol) dir.exists(yol) && length(list.files(yol)) > 0L

  aday <- artifact_dir
  i <- 1L
  while (dolu(aday) && i <= max_suffix) {
    i <- i + 1L
    aday <- sprintf("%s-%d", artifact_dir, i)
  }

  # SON ADAY DA DOLUYSA HATA VERİLİR.
  #
  # Döngü yalnızca `i > max_suffix` olduğu için de sonlanabilir; o durumda son
  # aday SINANMAMIŞTIR. `dir.create(showWarnings = FALSE)` var olan dizin için
  # SESSİZCE başarısız olur ve fonksiyon DOLU dizini döndürürdü; artefakt
  # yazıcısı da önceki koşunun `health.json`/`health.txt` dosyalarını EZERDİ --
  # bu, ilan edilen "asla üzerine yazma" sözleşmesinin tam tersidir.
  if (dolu(aday)) {
    stop(sprintf(paste0(
      "[PK_META_GEN] Artefakt dizini AYRILAMADI: '%s' ve %d sonek adayinin ",
      "tamami DOLU. Onceki kosu raporlarinin uzerine YAZILMAMASI icin kosu ",
      "durduruldu; artifacts dizinini temizleyin."
    ), artifact_dir, max_suffix), call. = FALSE)
  }

  dir.create(aday, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(aday)) {
    stop(sprintf("[PK_META_GEN] Artefakt dizini OLUSTURULAMADI: '%s'.", aday),
         call. = FALSE)
  }
  aday
}

#' Sağlık raporu artefaktlarını yaz
#'
#' Giriş betiğinden AYRILMIŞTIR ki artefakt yazma yolu (JSON + metin + dizin
#' oluşturma) uygulama bootstrap'i OLMADAN test edilebilsin.
#'
#' @return Yazılan dosya yolları.
pkgh_write_artifacts <- function(report, artifact_dir, records, summary,
                                 config_summary) {
  if (!dir.exists(artifact_dir)) {
    dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  }

  json_yolu <- file.path(artifact_dir, "health.json")
  metin_yolu <- file.path(artifact_dir, "health.txt")

  kararli <- pkgh_stabilize_report(report)

  json_metin <- as.character(jsonlite::toJSON(
    kararli, auto_unbox = TRUE, pretty = TRUE, null = "null"
  ))
  .pkgh_atomic_write_bytes(charToRaw(enc2utf8(json_metin)), json_yolu)

  metin <- pkgh_render_text(summary, records, config_summary)
  .pkgh_atomic_write_bytes(charToRaw(enc2utf8(metin)), metin_yolu)

  list(json = json_yolu, text = metin_yolu)
}

#' Konsol özeti (kısa)
pkgh_render_console <- function(summary, records) {
  satirlar <- c(
    "",
    "[PK_META_GEN] ---------------- SAGLIK OZETI ----------------",
    sprintf("[PK_META_GEN] Toplam sorgu            : %d", summary$total_queries),
    sprintf("[PK_META_GEN] Bu kosuda sema alinan   : %d", summary$described_or_sampled),
    sprintf("[PK_META_GEN] Onbellekten gelen       : %d", summary$from_cache %||% 0L),
    sprintf("[PK_META_GEN] Aday katmana dahil      : %d", summary$included),
    sprintf("[PK_META_GEN] GERI CEKILEN            : %d", summary$withheld),
    sprintf("[PK_META_GEN] Sema alinamayan         : %d", summary$schema_failures),
    sprintf("[PK_META_GEN] Atlanan                 : %d", summary$skipped),
    sprintf("[PK_META_GEN] RLS/GUVENLIK bulgusu    : %d", summary$rls_mismatches),
    sprintf("[PK_META_GEN] Tier-0 kalan            : %d", summary$tier0_queries),
    sprintf("[PK_META_GEN] Onceki metadata korunan : %d", summary$preserved_previous %||% 0L),
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
