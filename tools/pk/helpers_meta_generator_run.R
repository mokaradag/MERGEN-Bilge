# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_run.R
# Aciklama: Faz 3b metadata ureticisi -- ENVANTER KOSUSU.
#
# BU DOSYA CALISMA ZAMANI KODU DEGILDIR; kaynak manifestine EKLENMEZ.
#
# TASARIM: DB erisimi ENJEKTE EDILIR (`connect_fn`, `describe_fn`, `sample_fn`).
# Boylece kosu mantiginin tamami -- salt-okunur kapisi, sema cikarimi, birlesme,
# geri cekme karari, saglik kaydi -- gercek bir veritabani OLMADAN test edilir.
# Varsayilan enjeksiyonlar dosyanin sonundadir ve yalnizca VM'de kullanilir.
#
# SERT KURALLAR:
#   * SALT OKUNUR. Her SQL, uretimin kullandigi AYNI `pk_sql_classify_readonly()`
#     kapisindan gecer. Kapi reddederse sorgu CALISTIRILMAZ.
#   * SQL METNI DEGISTIRILMEZ. Ornekleme, SQL'i sarmalayarak degil, acik imlecten
#     yalnizca N satir cekerek yapilir; boylece kapidan gecen metin ile calisan
#     metin AYNIDIR.
#   * TEK BIR SORGU KOSUYU DUSURMEZ. Hata bir saglik bulgusu olur.
#   * BAGLANTI HER DURUMDA BIRAKILIR (`on.exit`).
# ==============================================================================

.pkgn_is_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

#' Uretilen yerel katman girdisi olustur
#'
#' YALNIZCA YAPISAL alanlar yazilir. `capability`, `grain`, `additive`, `unit`,
#' `primary_entity`, `intents`, `default_measures` gibi ANLAMSAL alanlar
#' BILINCLI OLARAK URETILMEZ: onlar insan kuresyonudur ve yoklugunda anlamsal
#' istekler SQL'den once fail-closed durur.
pkgn_build_local_entry <- function(schema, source_types, mode, observations = list()) {
  cmeta <- pkgs_build_column_meta(schema, source_types = source_types, mode = mode)
  cmeta <- pkgs_apply_observations(cmeta, observations)

  list(
    result_schema = schema,
    column_meta = cmeta,
    generated_mode = as.character(mode)[1],
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    tier = 1L
  )
}

#' Uretilen girdinin baslangic dogrulamasini GECIP GECMEDIGINI simule et
#'
#' Baslangicta calisan dogrulayicilarin AYNISI kullanilir. Ureticinin "bu sorgu
#' guvenle dahil edilebilir" karari, uygulamanin acilista verecegi kararla
#' birebir ayni olmalidir; aksi halde uretici dosyayi yazar ve uygulama acilmaz.
pkgn_validate_candidate <- function(query, local_entry, auto_entry = NULL,
                                    curated_entry = NULL, registry = NULL) {
  birlesik <- pk_meta_merge_layers(
    auto = if (is.null(auto_entry)) list() else stats::setNames(list(auto_entry), "x"),
    local = stats::setNames(list(local_entry), "x"),
    curated = if (is.null(curated_entry)) list() else stats::setNames(list(curated_entry), "x")
  )[["x"]]

  id <- as.character(query$id %||% "?")[1]

  # Alias katlama: birlesmis metadata uzerinde baslangicta da calisir.
  normal <- pk_meta_normalize_aliases(stats::setNames(list(birlesik), id))
  birlesik <- normal$meta[[id]]

  hatalar <- unique(c(
    normal$errors,
    pk_meta_validate_query(id, birlesik, registry),
    pk_meta_validate_schema_dependent(id, birlesik, birlesik$result_schema, query$rls_columns)
  ))

  list(merged = birlesik, errors = hatalar[nzchar(hatalar)])
}

#' Tek bir sorgunun envanterini cikar
#'
#' @return list(record, local_entry, cache) -- `local_entry` NULL ise sorgu
#'   uretilen katmana GIRMEZ (Tier-0'da kalir; bu bir GERILEME DEGILDIR).
pkgn_inventory_one <- function(query, config, conn = NULL,
                               describe_fn = NULL, sample_fn = NULL,
                               auto_entry = NULL, curated_entry = NULL,
                               registry = NULL, cached = NULL) {
  id <- if (.pkgn_is_text(query$id)) trimws(query$id) else NA_character_

  if (is.na(id)) {
    return(list(
      record = pkgh_query_record(
        query, "failed", config$mode,
        findings = list(pkgh_finding(
          "missing_query_id", "blocking",
          "Sorgu KARARLI bir id tasimiyor; metadata liste konumuna baglanamaz."
        ))
      ),
      local_entry = NULL, cache = NULL
    ))
  }

  # --- SALT-OKUNUR KAPISI (uretimle AYNI siniflandirici) -----------------------
  sql <- query$sql
  if (!.pkgn_is_text(sql)) {
    return(list(
      record = pkgh_query_record(
        query, "failed", config$mode,
        findings = list(pkgh_finding(
          "missing_sql", "blocking",
          "Sorgu icin SQL metni yok (sql_file yuklenmemis olabilir)."
        ))
      ),
      local_entry = NULL, cache = NULL
    ))
  }

  kapi <- pk_sql_classify_readonly(sql)
  if (!isTRUE(kapi$allowed)) {
    # HAM SQL RAPORA GIRMEZ; yalnizca gerekce.
    return(list(
      record = pkgh_query_record(
        query, "skipped", config$mode,
        findings = list(pkgh_finding(
          "sql_not_readonly", "blocking",
          sprintf(
            paste0(
              "SQL salt-okunur kapisindan gecemedi (gerekce=%s, tur=%s). ",
              "Sorgu CALISTIRILMADI. Uretici asla DDL/yazma/EXEC calistirmaz."
            ),
            kapi$reason %||% "?", kapi$statement_kind %||% "?"
          )
        ))
      ),
      local_entry = NULL, cache = NULL
    ))
  }

  # --- SEMA (onbellekten ya da DB'den) ----------------------------------------
  sema_sonucu <- if (!is.null(cached)) {
    cached
  } else {
    pkgn_fetch_schema(query, config, conn, describe_fn, sample_fn)
  }

  if (!isTRUE(sema_sonucu$ok)) {
    return(list(
      record = pkgh_query_record(
        query, "failed", config$mode, error = sema_sonucu$error,
        findings = list(pkgh_finding(
          sema_sonucu$code %||% "schema_unavailable", "attention",
          sema_sonucu$detail %||% "Sorgu semasi alinamadi; sorgu Tier-0 olarak kalir."
        ))
      ),
      local_entry = NULL, cache = NULL
    ))
  }

  sema <- sema_sonucu$schema
  yerel <- pkgn_build_local_entry(
    sema, sema_sonucu$source_types, config$mode, sema_sonucu$observations %||% list()
  )

  dogrulama <- pkgn_validate_candidate(query, yerel, auto_entry, curated_entry, registry)
  bulgular <- pkgh_structural_findings(query, dogrulama$merged, sema, dogrulama$errors)

  if (length(sema_sonucu$unmapped %||% character(0))) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "unmapped_sql_type", "attention",
      sprintf(
        paste0(
          "SQL tipi eslenemedi; EN MUHAFAZAKAR yapiya (character/dimension) ",
          "dusuldu: %s. Bu sutun icin toplama YAPILMAZ; gerekiyorsa kure edin."
        ),
        paste(sema_sonucu$unmapped, collapse = ", ")
      ),
      columns = sema_sonucu$unmapped
    )))
  }

  if (length(sema_sonucu$unbounded %||% character(0))) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "unbounded_lob_column", "info",
      sprintf(
        "Kanitlanmis genislik ust siniri OLMAYAN sutun(lar): %s.",
        paste(sema_sonucu$unbounded, collapse = ", ")
      ),
      columns = sema_sonucu$unbounded
    )))
  }

  ornek_bilgi <- sema_sonucu$sample_info %||% list()

  # --- KARAR ------------------------------------------------------------------
  # Bloklayici bulgu VARSA sorgu uretilen katmana ALINMAZ. Boylece:
  #   * uygulama baslangici ASLA bir uretici kosusu yuzunden kirilmaz,
  #   * saglikli sorgular gercek semalarini alir,
  #   * sorunlu sorgu BUGUNKU davranisinda kalir (Tier-0, pending_no_schema) --
  #     istek zamani RLS zorlamasi KOSULSUZ oldugu icin guvenlik ZAYIFLAMAZ.
  bloklayici <- sum(vapply(bulgular, function(f) identical(f$severity, "blocking"), logical(1)))

  if (bloklayici > 0L) {
    return(list(
      record = pkgh_query_record(query, "withheld", config$mode, schema = sema,
                                 findings = bulgular, sample_info = ornek_bilgi),
      local_entry = NULL,
      cache = sema_sonucu$cache
    ))
  }

  list(
    record = pkgh_query_record(query, "ok", config$mode, schema = sema,
                               findings = bulgular, sample_info = ornek_bilgi),
    local_entry = yerel,
    cache = sema_sonucu$cache
  )
}

#' Sema getir (kip bazli)
pkgn_fetch_schema <- function(query, config, conn, describe_fn, sample_fn) {
  hata_sonucu <- function(code, detail, error = NULL) {
    list(ok = FALSE, code = code, detail = detail, error = error)
  }

  if (is.null(conn)) {
    return(hata_sonucu(
      "no_connection",
      sprintf("'%s' hedefi icin DB baglantisi kurulamadi; sorgu Tier-0 kaldi.",
              as.character(query$db_target %||% "primary")[1])
    ))
  }

  if (identical(config$mode, "describe")) {
    tanimlayici <- tryCatch(describe_fn(conn, query$sql), error = function(e) e)
    if (inherits(tanimlayici, "error")) {
      return(hata_sonucu("describe_failed",
                         "Sonuc kumesi tanimlayicisi alinamadi.",
                         conditionMessage(tanimlayici)))
    }
    if (is.null(tanimlayici) || !length(tanimlayici)) {
      return(hata_sonucu(
        "describe_unavailable",
        paste0(
          "sys.dm_exec_describe_first_result_set bu sorgu icin sema donduremedi ",
          "(gecici tablo, dinamik SQL ya da belirsiz sonuc kumesi olabilir). ",
          "'sample' kipi bu sorgu icin gerekebilir."
        )
      ))
    }

    cikarim <- pkgs_schema_from_descriptor(tanimlayici)
    if (is.null(cikarim)) {
      return(hata_sonucu("describe_empty_schema",
                         "Tanimlayici bos/gecersiz sema dondurdu."))
    }

    return(list(
      ok = TRUE,
      schema = cikarim$schema,
      source_types = cikarim$source_types,
      unmapped = cikarim$unmapped,
      unbounded = cikarim$unbounded,
      observations = list(),
      sample_info = list(mode = "describe", executed = FALSE),
      cache = list(mode = "describe", columns = cikarim$schema,
                   source_types = cikarim$source_types)
    ))
  }

  # --- sample kipi ------------------------------------------------------------
  cerceve <- tryCatch(sample_fn(conn, query$sql, config$sample_rows), error = function(e) e)
  if (inherits(cerceve, "error")) {
    return(hata_sonucu("sample_failed", "Sorgu orneklenemedi.", conditionMessage(cerceve)))
  }
  if (!is.data.frame(cerceve)) {
    return(hata_sonucu("sample_not_dataframe", "Ornekleme data.frame dondurmedi."))
  }
  if (!ncol(cerceve)) {
    return(hata_sonucu("sample_no_columns", "Ornek sonucunda sutun yok."))
  }

  cikarim <- pkgs_schema_from_dataframe(cerceve)
  if (is.null(cikarim)) {
    return(hata_sonucu("sample_invalid_schema", "Ornek sonucundan gecerli sema cikarilamadi."))
  }

  gozlemler <- pkgs_sample_observations(
    cerceve, config$high_cardinality_threshold, method = "prefix"
  )

  satir <- nrow(cerceve)
  list(
    ok = TRUE,
    schema = cikarim$schema,
    source_types = cikarim$source_types,
    unmapped = character(0),
    unbounded = character(0),
    observations = gozlemler,
    sample_info = list(
      mode = "sample",
      executed = TRUE,
      method = "prefix",
      rows_seen = satir,
      # 500 satirlik bir ornek 501 satirlik sonucu 5 milyondan AYIRT EDEMEZ.
      # Bu yuzden satir sayisi tavana degdiginde yalnizca ALT SINIR bildirilir
      # ve row_cap gecti/kaldi iddiasi URETILMEZ.
      row_count_is_lower_bound = satir >= config$sample_rows,
      cardinality_claim = "unknown"
    ),
    cache = list(mode = "sample", columns = cikarim$schema,
                 source_types = cikarim$source_types, rows_seen = satir)
  )
}

#' Tum kutuphane icin envanter kosusu
#'
#' @param connect_fn `function(target)` -> baglanti nesnesi ya da NULL.
#' @param release_fn `function(handle)` -> serbest birak.
pkg_meta_run_inventory <- function(query_library, config,
                                   connect_fn, release_fn,
                                   describe_fn, sample_fn,
                                   auto_layer = list(), curated_layer = list(),
                                   registry = NULL, cache = list(),
                                   progress_fn = NULL) {
  kayitlar <- list()
  yerel <- list()
  yeni_cache <- list()

  baglantilar <- list()
  on.exit({
    for (hedef in names(baglantilar)) {
      tryCatch(release_fn(baglantilar[[hedef]]$handle), error = function(e) NULL)
    }
  }, add = TRUE)

  baglanti_al <- function(hedef) {
    if (!is.null(baglantilar[[hedef]])) return(baglantilar[[hedef]]$conn)

    tutamac <- tryCatch(connect_fn(hedef), error = function(e) e)
    if (inherits(tutamac, "error") || is.null(tutamac)) {
      baglantilar[[hedef]] <<- list(handle = NULL, conn = NULL)
      return(NULL)
    }

    baglantilar[[hedef]] <<- list(handle = tutamac, conn = tutamac$conn %||% tutamac)
    baglantilar[[hedef]]$conn
  }

  for (i in seq_along(query_library)) {
    q <- query_library[[i]]
    if (!is.list(q)) next

    id <- if (.pkgn_is_text(q$id)) trimws(q$id) else NA_character_
    hedef <- as.character(q$db_target %||% "primary")[1]

    if (is.function(progress_fn)) {
      progress_fn(i, length(query_library), id %||% sprintf("index_%d", i))
    }

    onbellek <- if (isTRUE(config$resume) && !is.na(id)) cache[[id]] else NULL
    baglanti <- if (is.null(onbellek)) baglanti_al(hedef) else NULL

    sonuc <- tryCatch(
      pkgn_inventory_one(
        query = q, config = config, conn = baglanti,
        describe_fn = describe_fn, sample_fn = sample_fn,
        auto_entry = if (!is.na(id)) auto_layer[[id]] else NULL,
        curated_entry = if (!is.na(id)) curated_layer[[id]] else NULL,
        registry = registry,
        cached = onbellek
      ),
      # TEK BIR SORGU KOSUYU DUSURMEZ.
      error = function(e) list(
        record = pkgh_query_record(
          q, "failed", config$mode, error = conditionMessage(e),
          findings = list(pkgh_finding(
            "inventory_exception", "attention",
            "Envanter cikarimi sirasinda beklenmeyen hata; sorgu Tier-0 kaldi."
          ))
        ),
        local_entry = NULL, cache = NULL
      )
    )

    kayitlar[[length(kayitlar) + 1L]] <- sonuc$record
    if (!is.null(sonuc$local_entry) && !is.na(id)) yerel[[id]] <- sonuc$local_entry
    if (!is.null(sonuc$cache) && !is.na(id)) yeni_cache[[id]] <- sonuc$cache
  }

  list(
    local_meta = yerel,
    records = kayitlar,
    summary = pkgh_summarize(kayitlar),
    cache = yeni_cache
  )
}

# ==============================================================================
# VARSAYILAN ENJEKSIYONLAR (yalnizca VM'de kullanilir)
# ==============================================================================

#' Varsayilan baglanti acici
pkg_default_connect_fn <- function(target = "primary") {
  if (!exists("get_connection", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] get_connection bulunamadi; uygulama bootstrap'i yuklenmedi.",
         call. = FALSE)
  }
  get_connection(target)
}

pkg_default_release_fn <- function(handle) {
  if (is.null(handle)) return(invisible(NULL))
  if (exists("release_connection", mode = "function", inherits = TRUE)) {
    return(invisible(release_connection(handle)))
  }
  invisible(NULL)
}

#' Varsayilan `describe` cagrisi
#'
#' `sys.dm_exec_describe_first_result_set` sorguyu CALISTIRMAZ; metni parametre
#' olarak alir ve sonuc kumesi semasini dondurur.
pkg_default_describe_fn <- function(conn, sql) {
  if (!exists("pk_sql_describe_result_schema", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] pk_sql_describe_result_schema bulunamadi.", call. = FALSE)
  }
  pk_sql_describe_result_schema(conn, sql)
}

#' Varsayilan `sample` cagrisi -- SINIRLI ve SQL'i DEGISTIRMEYEN
#'
#' SQL SARMALANMAZ (`SELECT TOP n FROM (...)` YOK): uretim sorgulari `ORDER BY`,
#' CTE ve `OPTION(...)` icerebilir; sarmalamak hem sorguyu bozar hem de
#' salt-okunur kapisindan GECEN metin ile CALISAN metni ayirir. Bunun yerine
#' imleç acilir ve yalnizca N satir cekilir; kalan sonuc sunucuda birakilir.
#'
#' Bu YONTEM bir ONEKTIR (prefix): temsili DEGILDIR ve tek yonlu gozlem disinda
#' hicbir kardinalite/null/benzersizlik iddiasini desteklemez.
pkg_default_sample_fn <- function(conn, sql, sample_rows = 500L) {
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("[PK_META_GEN] DBI paketi gerekli.", call. = FALSE)
  }

  n <- suppressWarnings(as.integer(sample_rows)[1])
  if (length(n) != 1L || is.na(n) || n < 1L) n <- 500L

  sonuc <- DBI::dbSendQuery(conn, sql)
  # Sonuc kumesi HER DURUMDA kapatilir; aksi halde baglanti kirli kalir.
  on.exit(tryCatch(DBI::dbClearResult(sonuc), error = function(e) NULL), add = TRUE)

  cerceve <- DBI::dbFetch(sonuc, n = n)

  if (exists("normalize_pk_dataframe_utf8", mode = "function", inherits = TRUE)) {
    cerceve <- tryCatch(normalize_pk_dataframe_utf8(cerceve), error = function(e) cerceve)
  }

  cerceve
}
