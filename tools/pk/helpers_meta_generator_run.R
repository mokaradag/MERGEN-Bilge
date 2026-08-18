# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_run.R
# Açıklama: Faz 3b metadata üreticisi -- ENVANTER KOŞUSU.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# TASARIM: DB erişimi ENJEKTE EDİLİR (`connect_fn`, `describe_fn`, `sample_fn`).
# Böylece koşu mantığının tamamı -- salt-okunur kapısı, şema çıkarımı, birleşme,
# geri çekme kararı, sağlık kaydı -- gerçek bir veritabanı OLMADAN test edilir.
# Varsayılan enjeksiyonlar `helpers_meta_generator_db.R` içindedir.
#
# SERT KURALLAR:
#   * SALT OKUNUR. Her SQL, üretimin kullandığı AYNI `pk_sql_classify_readonly()`
#     kapısından geçer. Kapı reddederse sorgu ÇALIŞTIRILMAZ.
#   * SQL METNİ DEĞİŞTİRİLMEZ. Örnekleme, SQL'i sarmalayarak değil, açık imleçten
#     yalnızca N satır çekerek yapılır; böylece kapıdan geçen metin ile çalışan
#     metin AYNIDIR.
#   * BİLİNMEYEN HEDEFE BAĞLANILMAZ. `get_connection()` bilinmeyen bir hedefi
#     sessizce birincil DSN'e düşürür; bu yüzden hedef, bağlantı AÇILMADAN önce
#     doğrulanır.
#   * TEK BİR SORGU KOŞUYU DÜŞÜRMEZ. Hata bir sağlık bulgusu olur.
#   * BAĞLANTI HER DURUMDA BIRAKILIR (`on.exit`).
# ==============================================================================

.pkgn_is_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

# Enjekte edilen işlevler FARKLI ARİTEDE olabilir: testler `function(conn, sql)`
# geçirir, üretim enjeksiyonu zaman aşımı/tavan gibi ek argümanlar kabul eder.
# Ek argümanlar YALNIZCA hedef işlev onları beyan ettiğinde geçirilir; böylece
# hem belgelenen sade sözleşme hem de üretim sınırları çalışır.
.pkgn_call_injected <- function(fn, positional = list(), optional = list()) {
  arglar <- tryCatch(names(formals(fn)), error = function(e) NULL)
  if (is.null(arglar)) arglar <- character(0)
  if (length(optional)) {
    kabul <- if ("..." %in% arglar) {
      rep(TRUE, length(optional))
    } else {
      names(optional) %in% arglar
    }
    optional <- optional[kabul]
  }
  # `quote = TRUE`: argümanlar ZATEN değerlerdir (bağlantı nesnesi, metin, sayı).
  # Tırnaksız `do.call` bunları çağrı içine gömüp yeniden değerlendirir; bir
  # bağlantı nesnesi için bu gereksiz ve kırılgandır.
  do.call(fn, c(positional, optional), quote = TRUE)
}

# Bağlantı seviyesinde OLDUĞU anlaşılan hata kalıpları. Böyle bir hatadan sonra
# önbelleğe alınmış tutamaç ARTIK GEÇERSİZDİR; bırakılıp yenisi açılmalıdır,
# aksi hâlde aynı hedefteki TÜM sonraki sorgular da düşer.
.PKGN_CONNECTION_ERROR_PATTERN <- paste(
  "08s01", "08001", "08003", "08004", "hyt00", "hyt01",
  "communication link", "connection is closed", "connection was closed",
  "not connected", "server is not found", "login timeout", "broken pipe",
  sep = "|"
)

.pkgn_is_connection_error <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(FALSE)
  grepl(.PKGN_CONNECTION_ERROR_PATTERN, tolower(ham), perl = TRUE, useBytes = TRUE)
}

# Enjekte edilen `connect_fn` sözleşmesi "bağlantı nesnesi ya da NULL" der.
# Uygulamanın `get_connection()` işlevi `list(conn = , pooled = )` sarmalayıcısı
# döndürür; ham bir `DBIConnection` ise LİSTE DEĞİLDİR ve `$conn` erişimi
# üzerinde HATA verir. Bu yüzden sarmalayıcı olup olmadığı ÖNCE sınanır.
.pkgn_unwrap_connection <- function(handle) {
  if (is.null(handle)) return(NULL)
  if (inherits(handle, "DBIConnection")) return(handle)
  if (is.list(handle) && !is.null(handle$conn)) return(handle$conn)
  handle
}

#' Üretilen yerel katman girdisi oluştur
#'
#' YALNIZCA YAPISAL alanlar yazılır. `capability`, `grain`, `additive`, `unit`,
#' `primary_entity`, `intents`, `default_measures` gibi ANLAMSAL alanlar
#' BİLİNÇLİ OLARAK ÜRETİLMEZ: onlar insan küresyonudur ve yokluğunda anlamsal
#' istekler SQL'den önce fail-closed durur.
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

#' Üretilen girdinin başlangıç doğrulamasını GEÇİP GEÇMEDİĞİNİ simüle et
#'
#' Başlangıçta çalışan doğrulayıcıların AYNISI kullanılır. Üreticinin "bu sorgu
#' güvenle dahil edilebilir" kararı, uygulamanın açılışta vereceği kararla
#' birebir aynı olmalıdır; aksi hâlde üretici dosyayı yazar ve uygulama açılmaz.
#'
#' @param alias_overlay Operatörün `pk_query_aliases_local` bindirmesi. Başlangıç
#'   kapısı bu bindirmeyi de uygular; burada UYGULANMAZSA bir sorguya özgü alias
#'   kusuru yalnızca BÜTÜN KÜTÜPHANE kapısında görülür ve tek bir bozuk sorgu
#'   TÜM üretilen katmanın yazılmamasına yol açar. Sorgu bazında geri çekmek
#'   doğru davranıştır.
pkgn_validate_candidate <- function(query, local_entry, auto_entry = NULL,
                                    curated_entry = NULL, registry = NULL,
                                    alias_overlay = NULL) {
  birlesik <- pk_meta_merge_layers(
    auto = if (is.null(auto_entry)) list() else stats::setNames(list(auto_entry), "x"),
    local = stats::setNames(list(local_entry), "x"),
    curated = if (is.null(curated_entry)) list() else stats::setNames(list(curated_entry), "x")
  )[["x"]]

  id <- as.character(query$id %||% "?")[1]

  # Alias katlama: birleşmiş metadata üzerinde başlangıçta da çalışır.
  normal <- pk_meta_normalize_aliases(stats::setNames(list(birlesik), id))
  birlesik <- normal$meta[[id]]
  hatalar <- normal$errors

  if (!is.null(alias_overlay) && is.list(alias_overlay) && !is.null(alias_overlay[[id]])) {
    bindirme <- pk_meta_apply_alias_overlay(
      stats::setNames(list(birlesik), id),
      stats::setNames(list(alias_overlay[[id]]), id)
    )
    birlesik <- bindirme$meta[[id]]
    hatalar <- c(hatalar, bindirme$errors)
  }

  hatalar <- unique(c(
    hatalar,
    pk_meta_validate_query(id, birlesik, registry),
    pk_meta_validate_schema_dependent(id, birlesik, birlesik$result_schema, query$rls_columns)
  ))

  list(merged = birlesik, errors = hatalar[nzchar(hatalar)])
}

# Kanıtlanmış üst sınırı olmayan sütunlar OPERATÖR EYLEMİ gerektirir (operatör
# kılavuzu bunu böyle listeler). `info` şiddeti insan raporunda BASTIRILIR;
# tek bulgusu bu olan bir sorgu rapordan tamamen kaybolurdu.
.pkgn_unbounded_finding <- function(sutunlar) {
  pkgh_finding(
    "unbounded_lob_column", "attention",
    sprintf(
      "Kanitlanmis genislik ust siniri OLMAYAN sutun(lar): %s.",
      paste(sutunlar, collapse = ", ")
    ),
    columns = sutunlar
  )
}

.pkgn_unmapped_finding <- function(eslenmeyen) {
  sutunlar <- vapply(eslenmeyen, function(o) as.character(o$column)[1], character(1))
  etiketler <- vapply(eslenmeyen, function(o) {
    sprintf("%s (%s)", as.character(o$column)[1], as.character(o$source_type)[1])
  }, character(1))

  pkgh_finding(
    "unmapped_sql_type", "attention",
    sprintf(
      paste0(
        "SQL tipi eslenemedi; EN MUHAFAZAKAR yapiya (character/dimension) ",
        "dusuldu: %s. Bu sutun icin toplama YAPILMAZ; gerekiyorsa NATIF tipi ",
        "eslemeye ekleyin ya da kure edin."
      ),
      paste(etiketler, collapse = ", ")
    ),
    columns = sutunlar
  )
}

#' Tek bir sorgunun envanterini çıkar
#'
#' @return list(record, local_entry, cache) -- `local_entry` NULL ise sorgu
#'   üretilen katmana GİRMEZ (Tier-0'da kalır; bu bir GERİLEME DEĞİLDİR).
pkgn_inventory_one <- function(query, config, conn = NULL,
                               describe_fn = NULL, sample_fn = NULL,
                               auto_entry = NULL, curated_entry = NULL,
                               registry = NULL, cached = NULL,
                               alias_overlay = NULL, target_error = NULL) {
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

  # --- HEDEF KAPISI (bağlantı AÇILMADAN önce) ---------------------------------
  if (!is.null(target_error)) {
    return(list(
      record = pkgh_query_record(
        query, "failed", config$mode,
        findings = list(pkgh_finding("invalid_db_target", "blocking", target_error))
      ),
      local_entry = NULL, cache = NULL
    ))
  }

  # --- SALT-OKUNUR KAPISI (üretimle AYNI sınıflandırıcı) -----------------------
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
    # HAM SQL RAPORA GİRMEZ; yalnızca gerekçe.
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

  # --- ŞEMA (önbellekten ya da DB'den) ----------------------------------------
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
        )),
        sample_info = sema_sonucu$sample_info %||% list()
      ),
      local_entry = NULL, cache = NULL,
      connection_error = isTRUE(sema_sonucu$connection_error)
    ))
  }

  sema <- sema_sonucu$schema
  yerel <- pkgn_build_local_entry(
    sema, sema_sonucu$source_types, config$mode, sema_sonucu$observations %||% list()
  )

  dogrulama <- pkgn_validate_candidate(query, yerel, auto_entry, curated_entry, registry,
                                       alias_overlay = alias_overlay)
  bulgular <- pkgh_structural_findings(query, dogrulama$merged, sema, dogrulama$errors)

  if (length(sema_sonucu$unmapped %||% list())) {
    bulgular <- c(bulgular, list(.pkgn_unmapped_finding(sema_sonucu$unmapped)))
  }

  if (length(sema_sonucu$unbounded %||% character(0))) {
    bulgular <- c(bulgular, list(.pkgn_unbounded_finding(sema_sonucu$unbounded)))
  }

  ornek_bilgi <- sema_sonucu$sample_info %||% list()

  # SIFIR SATIRLI SONUÇ: sütunları olduğu için şema GEÇERLİDİR, ama sağlık
  # sözleşmesi böyle bir sorgunun BİLDİRİLMESİNİ gerektirir (SQL yaşayan veriyi
  # döndürmüyor olabilir).
  if (identical(config$mode, "sample") && !isTRUE(ornek_bilgi$from_cache) &&
      identical(as.integer(ornek_bilgi$rows_seen %||% NA_integer_), 0L)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "sample_zero_rows", "attention",
      paste0(
        "Ornekleme SIFIR satir dondurdu. Sema gecerli, ancak sorgu su an veri ",
        "uretmiyor; kanit gerektiren gozlemler (null/benzersizlik/kardinalite) ",
        "URETILEMEDI."
      )
    )))
  }

  # ÖNEK ÖRNEĞİNİN KANITLADIĞI row_cap AŞIMI. Örnek satır sayısı etkin
  # `row_cap` değerini GEÇTİYSE, önek TEK BAŞINA aşımı kanıtlar; bu durumda
  # "bilinmiyor" demek elde olan kanıtı gizlemek olurdu.
  ust_sinir <- suppressWarnings(as.numeric(dogrulama$merged$row_cap %||% NA_real_)[1])
  gorulen <- suppressWarnings(as.numeric(ornek_bilgi$rows_seen %||% NA_real_)[1])
  if (!is.na(ust_sinir) && !is.na(gorulen) && is.finite(ust_sinir) && gorulen > ust_sinir) {
    ornek_bilgi$cardinality_claim <- "row_cap_exceeded"
    bulgular <- c(bulgular, list(pkgh_finding(
      "row_cap_exceeded", "attention",
      sprintf(paste0(
        "Onek ornegi row_cap asimini KANITLADI: gorulen %s satir > row_cap %s. ",
        "Kuresyondaki row_cap degeri ya da sorgu kapsami gozden gecirilmelidir."
      ), format(gorulen), format(ust_sinir))
    )))
  }

  # --- KARAR ------------------------------------------------------------------
  # Bloklayıcı bulgu VARSA sorgu üretilen katmana ALINMAZ. Böylece:
  #   * uygulama başlangıcı ASLA bir üretici koşusu yüzünden kırılmaz,
  #   * sağlıklı sorgular gerçek şemalarını alır,
  #   * sorunlu sorgu BUGÜNKÜ davranışında kalır (Tier-0, pending_no_schema) --
  #     istek zamanı RLS zorlaması KOŞULSUZ olduğu için güvenlik ZAYIFLAMAZ.
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

# `describe` çağrısını yap ve SONUCU ile HATASINI AYIR.
#
# Üretim tanımlayıcı işlevi hataları yutup `NULL` döndürebildiği için varsayılan
# enjeksiyon (helpers_meta_generator_db.R) gerçek hatayı YÜKSELTİR; böylece
# "bu sorgu tanımlanamıyor" ile "sonda BAŞARISIZ oldu" ayrı kalır.
.pkgn_describe <- function(query, config, conn, describe_fn) {
  tryCatch(
    .pkgn_call_injected(
      describe_fn,
      positional = list(conn, query$sql),
      optional = list(timeout_sec = config$sql_timeout_sec)
    ),
    error = function(e) e
  )
}

#' Şema getir (kip bazlı)
pkgn_fetch_schema <- function(query, config, conn, describe_fn, sample_fn) {
  hata_sonucu <- function(code, detail, error = NULL, connection_error = FALSE) {
    list(ok = FALSE, code = code, detail = detail,
         error = if (is.null(error)) NULL else pkgh_db_error_summary(error),
         connection_error = isTRUE(connection_error))
  }

  if (is.null(conn)) {
    return(hata_sonucu(
      "no_connection",
      sprintf("'%s' hedefi icin DB baglantisi kurulamadi; sorgu Tier-0 kaldi.",
              as.character(query$db_target %||% "primary")[1])
    ))
  }

  if (identical(config$mode, "describe")) {
    tanimlayici <- .pkgn_describe(query, config, conn, describe_fn)
    if (inherits(tanimlayici, "condition")) {
      return(hata_sonucu("describe_failed",
                         paste0(
                           "Sonuc kumesi tanimlayicisi ALINAMADI (sonda hatasi). ",
                           "Bu, 'bu sorgu tanimlanamiyor' ile AYNI SEY DEGILDIR."
                         ),
                         conditionMessage(tanimlayici),
                         connection_error = .pkgn_is_connection_error(
                           conditionMessage(tanimlayici))))
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
    if (!isTRUE(cikarim$ok)) {
      return(hata_sonucu(
        "describe_invalid_schema",
        sprintf(paste0(
          "Tanimlayici KULLANILAMAZ sutun(lar) bildirdi: %s. Adsiz bir sonuc ",
          "sutunu dusurulup 'kismi' sema yazmak, baslangic dogrulamasini gecen ",
          "ama gercek sonucla UYUSMAYAN metadata uretirdi."
        ), paste(cikarim$invalid, collapse = ", "))
      ))
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
                   source_types = cikarim$source_types,
                   unmapped = cikarim$unmapped, unbounded = cikarim$unbounded,
                   observations = list(),
                   sample_info = list(mode = "describe", executed = FALSE))
    ))
  }

  # --- sample kipi ------------------------------------------------------------
  # NATİF TİPLER: R sınıfı `nvarchar(max)`, `xml` ya da eşlenmeyen bir tipi
  # AYIRT EDEMEZ. Tanımlayıcı (sorguyu ÇALIŞTIRMAYAN) bu bilgiyi verir; bu
  # yüzden önce denenir. Alınamazsa örnekleme yine yapılır, yalnızca yapısal
  # tip bulguları üretilemez ve bu AÇIKÇA bildirilir.
  natif <- NULL
  tanimlayici <- .pkgn_describe(query, config, conn, describe_fn)
  if (!inherits(tanimlayici, "condition") && is.list(tanimlayici) && length(tanimlayici)) {
    aday <- pkgs_schema_from_descriptor(tanimlayici)
    if (!is.null(aday) && isTRUE(aday$ok)) natif <- aday$source_types
  }

  cerceve <- tryCatch(
    .pkgn_call_injected(
      sample_fn,
      positional = list(conn, query$sql, config$sample_rows),
      optional = list(timeout_sec = config$sql_timeout_sec,
                      max_result_mb = config$max_result_mb)
    ),
    error = function(e) e
  )

  if (inherits(cerceve, "condition")) {
    return(hata_sonucu("sample_failed", "Sorgu orneklenemedi.",
                       conditionMessage(cerceve),
                       connection_error = .pkgn_is_connection_error(
                         conditionMessage(cerceve))))
  }
  if (!is.data.frame(cerceve)) {
    return(hata_sonucu("sample_not_dataframe", "Ornekleme data.frame dondurmedi."))
  }
  if (!ncol(cerceve)) {
    return(hata_sonucu("sample_no_columns", "Ornek sonucunda sutun yok."))
  }

  cikarim <- pkgs_schema_from_dataframe(cerceve, column_types = natif)
  if (is.null(cikarim)) {
    return(hata_sonucu("sample_invalid_schema", "Ornek sonucundan gecerli sema cikarilamadi."))
  }

  gozlemler <- pkgs_sample_observations(
    cerceve, config$high_cardinality_threshold, method = "prefix"
  )

  satir <- nrow(cerceve)
  ornek_bilgi <- list(
    mode = "sample",
    executed = TRUE,
    method = "prefix",
    rows_seen = satir,
    native_types_available = !is.null(natif),
    # DÜRÜSTLÜK: `dbFetch(n = )` bir AKTARIM sınırdır. `dbSendQuery()` SELECT'i
    # çalıştırır; büyük bir birleştirme/ORDER BY bu satırlar çekilmeden ÖNCE
    # sunucuda tamamlanabilir. Gerçek koruma zaman aşımı ve bayt tavanıdır.
    server_bounded = FALSE,
    bound_kind = "transfer_only",
    # 500 satırlık bir örnek 501 satırlık sonucu 5 milyondan AYIRT EDEMEZ.
    # Bu yüzden satır sayısı tavana değdiğinde yalnızca ALT SINIR bildirilir
    # ve row_cap geçti/kaldı iddiası ÜRETİLMEZ.
    row_count_is_lower_bound = satir >= config$sample_rows,
    cardinality_claim = "unknown"
  )

  list(
    ok = TRUE,
    schema = cikarim$schema,
    source_types = cikarim$source_types,
    unmapped = cikarim$unmapped,
    unbounded = cikarim$unbounded,
    observations = gozlemler,
    sample_info = ornek_bilgi,
    cache = list(mode = "sample", columns = cikarim$schema,
                 source_types = cikarim$source_types, rows_seen = satir,
                 unmapped = cikarim$unmapped, unbounded = cikarim$unbounded,
                 observations = gozlemler, sample_info = ornek_bilgi)
  )
}

#' Tüm kütüphane için envanter koşusu
#'
#' @param connect_fn `function(target)` -> bağlantı nesnesi ya da NULL.
#' @param release_fn `function(handle)` -> serbest bırak.
#' @param fingerprints Devam önbelleği parmak izleri (yalnızca önbellek
#'   girdisinin kaydedilmesi için; kabul kararı `pkgh_read_state()` içindedir).
#' @param checkpoint_fn `function(cache)` -> her sorgudan SONRA çağrılır.
#'   Kesintiye uğrayan bir koşunun devam edebilmesi için durum ARA ARA
#'   yazılmalıdır; yalnızca koşu sonunda yazmak, kesintide TÜM ilerlemeyi
#'   kaybettirir.
pkg_meta_run_inventory <- function(query_library, config,
                                   connect_fn, release_fn,
                                   describe_fn, sample_fn,
                                   auto_layer = list(), curated_layer = list(),
                                   registry = NULL, cache = list(),
                                   progress_fn = NULL, alias_overlay = NULL,
                                   fingerprints = NULL, checkpoint_fn = NULL) {
  kayitlar <- list()
  yerel <- list()
  yeni_cache <- list()

  baglantilar <- list()
  baglanti_birak <- function(hedef) {
    tutamac <- baglantilar[[hedef]]
    if (is.null(tutamac)) return(invisible(NULL))
    tryCatch(release_fn(tutamac$handle), error = function(e) NULL)
    baglantilar[[hedef]] <<- NULL
    invisible(NULL)
  }

  on.exit({
    for (hedef in names(baglantilar)) {
      tryCatch(release_fn(baglantilar[[hedef]]$handle), error = function(e) NULL)
    }
  }, add = TRUE)

  # BAŞARISIZ BAĞLANTI ÖNBELLEĞE ALINMAZ. Tek bir geçici checkout/ağ hatası
  # önbelleğe NULL yazsaydı, o hedefteki BÜTÜN sonraki sorgular yeniden deneme
  # şansı bulamadan düşerdi.
  baglanti_al <- function(hedef) {
    if (!is.null(baglantilar[[hedef]])) return(baglantilar[[hedef]]$conn)

    tutamac <- tryCatch(connect_fn(hedef), error = function(e) e)
    if (inherits(tutamac, "condition") || is.null(tutamac)) return(NULL)

    baglantilar[[hedef]] <<- list(handle = tutamac,
                                  conn = .pkgn_unwrap_connection(tutamac))
    baglantilar[[hedef]]$conn
  }

  for (i in seq_along(query_library)) {
    q <- query_library[[i]]

    # BOZUK KÜTÜPHANE ÖGESİ SESSİZCE DÜŞÜRÜLMEZ: aksi hâlde `total_queries`
    # gerçek kütüphaneden küçük olur ve denetim bu kusur sınıfını göremez.
    if (!is.list(q)) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        list(id = sprintf("index_%d", i), name = NA_character_),
        "failed", config$mode,
        findings = list(pkgh_finding(
          "malformed_library_entry", "blocking",
          sprintf("query_library[[%d]] bir liste degil; sorgu envanterlenemez.", i)
        ))
      )
      next
    }

    id <- if (.pkgn_is_text(q$id)) trimws(q$id) else NA_character_
    hedef_ham <- as.character(q$db_target %||% "primary")[1]
    hedef_dogrulama <- pkg_meta_validate_db_target(hedef_ham)
    hedef <- if (isTRUE(hedef_dogrulama$ok)) hedef_dogrulama$target else hedef_ham

    if (is.function(progress_fn)) {
      progress_fn(i, length(query_library), id %||% sprintf("index_%d", i))
    }

    onbellek <- if (isTRUE(config$resume) && !is.na(id)) cache[[id]] else NULL
    # BİLİNMEYEN HEDEFE BAĞLANILMAZ.
    baglanti <- if (!is.null(onbellek) || !isTRUE(hedef_dogrulama$ok)) {
      NULL
    } else {
      baglanti_al(hedef)
    }

    sonuc <- tryCatch(
      pkgn_inventory_one(
        query = q, config = config, conn = baglanti,
        describe_fn = describe_fn, sample_fn = sample_fn,
        auto_entry = if (!is.na(id)) auto_layer[[id]] else NULL,
        curated_entry = if (!is.na(id)) curated_layer[[id]] else NULL,
        registry = registry,
        cached = onbellek,
        alias_overlay = alias_overlay,
        target_error = if (isTRUE(hedef_dogrulama$ok)) NULL else hedef_dogrulama$detail
      ),
      # TEK BİR SORGU KOŞUYU DÜŞÜRMEZ.
      error = function(e) list(
        record = pkgh_query_record(
          q, "failed", config$mode, error = pkgh_db_error_summary(conditionMessage(e)),
          findings = list(pkgh_finding(
            "inventory_exception", "attention",
            "Envanter cikarimi sirasinda beklenmeyen hata; sorgu Tier-0 kaldi."
          ))
        ),
        local_entry = NULL, cache = NULL,
        connection_error = .pkgn_is_connection_error(conditionMessage(e))
      )
    )

    # ÖLÜ BAĞLANTIYI BIRAK. Bağlantı seviyesinde bir hata olduysa önbellekteki
    # tutamaç artık geçersizdir; bırakılmazsa aynı hedefteki sonraki her sorgu
    # da aynı ölü tutamacı kullanıp düşerdi.
    if (isTRUE(sonuc$connection_error)) baglanti_birak(hedef)

    kayitlar[[length(kayitlar) + 1L]] <- sonuc$record
    if (!is.null(sonuc$local_entry) && !is.na(id)) yerel[[id]] <- sonuc$local_entry
    if (!is.null(sonuc$cache) && !is.na(id)) {
      girdi <- sonuc$cache
      if (is.null(girdi$fingerprint)) {
        girdi$fingerprint <- if (!is.null(fingerprints) && !is.null(fingerprints[[id]])) {
          fingerprints[[id]]
        } else if (exists("pkgh_state_fingerprint", mode = "function", inherits = TRUE)) {
          pkgh_state_fingerprint(q)
        } else {
          NA_character_
        }
      }
      yeni_cache[[id]] <- girdi
    }

    # ARA KAYIT: koşu burada kesilse bile buraya kadarki ilerleme korunur.
    if (is.function(checkpoint_fn)) {
      tryCatch(checkpoint_fn(yeni_cache), error = function(e) NULL)
    }
  }

  list(
    local_meta = yerel,
    records = kayitlar,
    summary = pkgh_summarize(kayitlar),
    cache = yeni_cache
  )
}
