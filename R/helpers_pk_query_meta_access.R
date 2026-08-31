# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta_access.R
# Açıklama: Tier-0 çıkarım, tüketici erişimcileri, yetenek kapısı ve
#           getirme-sonrası gerçek sütun doğrulaması.
# ==============================================================================


# Yerelden BAĞIMSIZ ASCII küçük harf (makine/protokol belirteçleri için).
# Ortak yardımcı `R/helpers_pk_text_turkish.R` içindedir; bu dosya izole
# testlerde tek başına source edilebildiği için yerel bir yedeği vardır.
.pk_meta_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

PK_META_STATUS_NO_SEMANTICS <- "unknown_no_semantic_metadata"
PK_META_STATUS_OK <- "ok"
PK_META_RLS_FIELDS <- c("masraf_yeri_col", "proje_kodu_col", "eps_kodu_col")

pk_meta_tier0_fallbacks <- function() {
  list(
    primary_entity = paste(
      "primary_entity yok -> tek filtre yapragi birincil kabul edilir;",
      "birden fazla yaprak varsa birincil varlik SECILMEZ."
    ),
    additive = "additive yok -> toplama YAPILMAZ; olcu satir bazinda raporlanir.",
    aggregate = "aggregate yok -> 'none' (satir bazinda), asla ortalama/toplam degil.",
    grain = "grain yok -> tekillestirme iddiasi yok; her satir kendi grain'idir.",
    grain_columns = "grain_columns yok -> mukerrer satir elemesi yapilmaz.",
    default_measures = "default_measures yok -> ortulu olcu secilmez.",
    default_group_by = "default_group_by yok -> ortulu gruplama yapilmaz.",
    row_cap = "row_cap yok -> MERGEN_PK_ROW_CAP genel degeri kullanilir.",
    unit = "unit yok -> sayiya birim eklenmez.",
    decimals = "decimals yok -> zorlamali yuvarlama yapilmaz.",
    match = "match yok -> 'none'; bulanik varlik cozumleme YAPILMAZ.",
    filterable = "filterable yok -> sutun filtrelenebilir SAYILMAZ (fail-closed).",
    domain = "domain yok -> kod/etiket cevirisi yapilmaz; ham deger gosterilir.",
    high_cardinality = "high_cardinality yok -> bilinmeyen (NA); dusuk kardinalite VARSAYILMAZ.",
    capability = paste(
      "capability yok -> anlamsal gereksinimli istek SQL'den ONCE",
      PK_META_STATUS_NO_SEMANTICS, "dondurur."
    )
  )
}

.pk_meta_role_from_class <- function(tip) {
  # ŞEMA TİPİ BİR PROTOKOL BELİRTECİDİR, İNSAN METNİ DEĞİL.
  #
  # Türkçe yerelde `tolower("POSIXct")` -> "posıxct" (noktasız ı) üretir ve
  # eşleşme listesiyle uyuşmaz; tarih sütunu sessizce "dimension" rolüne düşer,
  # zaman kapsamı/olgu üretimi ve filtre yolu yanlış davranır.
  tip <- .pk_meta_ascii_lower(as.character(tip)[1])
  if (tip %in% c("date", "posixct", "posixt", "posixlt", "datetime", "idate")) return("date")
  if (tip %in% c("numeric", "double", "integer", "int", "num", "integer64", "decimal", "float")) {
    return("measure")
  }
  "dimension"
}

pk_meta_tier0_column_meta <- function(schema) {
  if (is.data.frame(schema)) {
    tipler <- vapply(schema, function(s) class(s)[1], character(1))
    schema <- stats::setNames(as.character(tipler), names(schema))
  }

  if (is.null(schema) || !length(schema) || is.null(names(schema))) return(list())

  out <- list()
  for (sutun in names(schema)) {
    if (is.na(sutun) || !nzchar(sutun)) next
    rol <- .pk_meta_role_from_class(schema[[sutun]])
    out[[sutun]] <- list(
      label = sutun,
      role = rol,
      capability = NULL,
      match = "none",
      filterable = FALSE,
      high_cardinality = NA,
      tier = 0L,
      inferred_from = "structural_schema"
    )
  }
  out
}

.pk_meta_of <- function(query) {
  if (is.null(query)) return(list())
  if (is.list(query) && is.list(query$meta)) return(query$meta)
  if (is.list(query)) return(query)
  list()
}

# ADA GÖRE GÜVENLİ ÇÖZÜMLEME.
#
# `[[` bir LİSTEDE eşleşmeyen ad için `NULL` döner, fakat ATOMİK bir vektörde
# "subscript out of bounds" FIRLATIR. Bozuk bir metadata katmanı `column_meta`
# ya da `capability_variants` alanını karakter vektörü olarak yazdığında
# erişimciler belgelenen kapalı-başarısız yedeklerini ("none" / FALSE)
# döndürmek yerine isteği ÇÖKERTİYORDU. Tek çözümleme noktası bu sınıfı kapatır.
.pk_meta_named_entry <- function(x, name) {
  if (!is.list(x) || !length(x)) return(NULL)
  adlar <- names(x)
  if (is.null(adlar)) return(NULL)
  i <- match(as.character(name)[1], adlar)
  if (is.na(i)) return(NULL)
  x[[i]]
}

.pk_meta_column_entry <- function(query, column) {
  .pk_meta_named_entry(.pk_meta_of(query)$column_meta, column)
}

pk_meta_primary_entity <- function(query, filter_columns = character(0)) {
  meta <- .pk_meta_of(query)
  if (.pk_meta_is_scalar_text(meta$primary_entity)) return(trimws(meta$primary_entity))

  filter_columns <- unique(as.character(filter_columns %||% character(0)))
  filter_columns <- filter_columns[!is.na(filter_columns) & nzchar(trimws(filter_columns))]
  if (length(filter_columns) == 1L) return(filter_columns)
  NULL
}

pk_meta_aggregate_for <- function(query, column) {
  cmeta <- .pk_meta_column_entry(query, column)
  if (!is.list(cmeta) || !identical(cmeta$role, "measure")) return("none")

  if (.pk_meta_is_scalar_text(cmeta$aggregate) && cmeta$aggregate %in% PK_META_AGGREGATES) {
    if (identical(cmeta$aggregate, "sum") && !isTRUE(cmeta$additive)) return("none")
    return(cmeta$aggregate)
  }

  if (isTRUE(cmeta$additive)) return("sum")
  "none"
}

# `match_mode`, `match` alanının TAKMA ADIDIR.
#
# Alan `PK_META_COLUMN_FIELDS` içinde kabul ediliyor ama hiçbir yer okumuyordu:
# küratör `match = "resolve"` yerine `match_mode = "resolve"` yazdığında
# başlangıç doğrulaması geçiyor, bilinmeyen-alan koruması ad izinli olduğu için
# susuyor ve varlık çözümlemesi sessizce `"none"` kalıyordu. Artık okunur;
# değeri `helpers_pk_query_meta_schema.R` içinde `match` ile AYNI kümeye karşı
# doğrulanır.
pk_meta_match_mode <- function(query, column) {
  cmeta <- .pk_meta_column_entry(query, column)
  if (is.list(cmeta) && .pk_meta_is_scalar_text(cmeta$match) &&
      cmeta$match %in% PK_META_MATCH_MODES) return(cmeta$match)
  if (is.list(cmeta) && .pk_meta_is_scalar_text(cmeta$match_mode) &&
      cmeta$match_mode %in% PK_META_MATCH_MODES) return(cmeta$match_mode)
  if (is.list(cmeta) && identical(cmeta$role, "id")) return("exact")
  "none"
}

pk_meta_is_filterable <- function(query, column) {
  cmeta <- .pk_meta_column_entry(query, column)
  is.list(cmeta) && isTRUE(cmeta$filterable)
}

pk_meta_row_cap <- function(query) {
  meta <- .pk_meta_of(query)

  if (!exists("pk_config_resolve", mode = "function")) {
    if (!.pk_meta_is_whole_number(meta$row_cap, min = 1, max = .Machine$integer.max)) return(NULL)
    return(as.integer(meta$row_cap))
  }

  pk_config_resolve("MERGEN_PK_ROW_CAP", query_meta = meta)
}

.pk_meta_declared_capability_records <- function(query) {
  meta <- .pk_meta_of(query)
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar) || is.null(names(sutunlar))) return(list())

  adaylar <- list()
  for (sutun in names(sutunlar)) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$capability) ||
        !.pk_meta_is_scalar_text(cmeta$role)) next
    cap <- trimws(cmeta$capability)
    # BİRİKTİRİCİ `list()` OLARAK BAŞLAR: karakter alt simgesi BOŞ/ADSIZ
    # listede `NULL` DÖNDÜRMEZ, "subscript out of bounds" fırlatır ve ilk
    # yetenek sütununda yetenek kapısı OPAK bir hatayla düşerdi.
    adaylar[[cap]] <- c(.pk_meta_named_entry(adaylar, cap), sutun)
  }

  out <- list()
  for (cap in names(adaylar)) {
    sahipler <- unique(adaylar[[cap]])
    secilen <- NULL

    if (length(sahipler) == 1L) {
      secilen <- sahipler[[1]]
    } else {
      varyant <- .pk_meta_named_entry(meta$capability_variants, cap)
      tercih <- if (is.list(varyant)) varyant$prefer else NULL
      if (.pk_meta_is_scalar_text(tercih) && tercih %in% sahipler) secilen <- tercih
    }

    if (is.null(secilen)) next
    cmeta <- sutunlar[[secilen]]
    out[[cap]] <- list(column = secilen, role = cmeta$role)
  }

  out
}

pk_meta_declared_capabilities <- function(query) {
  kayitlar <- .pk_meta_declared_capability_records(query)
  lapply(kayitlar, function(x) x$column)
}

pk_meta_capability_check <- function(query, requirements = list()) {
  if (is.null(requirements)) requirements <- list()
  if (!is.list(requirements)) {
    return(list(
      status = PK_META_STATUS_NO_SEMANTICS,
      missing = character(0), columns = list(), entity = NULL,
      missing_entity = character(0), role_mismatches = list(),
      invalid_requirements = "requirements liste olmalidir."
    ))
  }

  alanlar <- c(measures = "measure", dates = "date", dimensions = "dimension")
  izinli_alanlar <- c("entity", names(alanlar), "group_by")
  istekler <- list()
  gecersiz <- character(0)

  req_adlari <- names(requirements)
  if (length(requirements) &&
      (is.null(req_adlari) || any(is.na(req_adlari) | !nzchar(trimws(req_adlari))))) {
    gecersiz <- c(gecersiz, "requirements adlandirilmis liste olmalidir.")
    req_adlari <- character(0)
  }
  tekrar_alan <- unique(req_adlari[duplicated(req_adlari)])
  if (length(tekrar_alan)) {
    gecersiz <- c(gecersiz, sprintf(
      "requirements icinde tekrar eden alan: %s", paste(tekrar_alan, collapse = ", ")
    ))
  }
  bilinmeyen_alan <- setdiff(req_adlari, izinli_alanlar)
  if (length(bilinmeyen_alan)) {
    gecersiz <- c(gecersiz, sprintf(
      "requirements bilinmeyen alan iceriyor: %s", paste(bilinmeyen_alan, collapse = ", ")
    ))
  }

  group_by <- requirements$group_by %||% character(0)
  if (!is.character(group_by)) {
    gecersiz <- c(gecersiz, "requirements$group_by karakter vektoru veya NULL olmalidir.")
    group_by <- character(0)
  } else if (length(group_by) && any(is.na(group_by) | !nzchar(trimws(group_by)))) {
    gecersiz <- c(gecersiz, "requirements$group_by bos veya NA deger iceremez.")
    group_by <- group_by[!is.na(group_by) & nzchar(trimws(group_by))]
  }

  for (alan in names(alanlar)) {
    deger <- requirements[[alan]] %||% character(0)
    if (!is.character(deger)) {
      gecersiz <- c(gecersiz, sprintf("requirements$%s karakter vektoru olmalidir.", alan))
      next
    }
    if (length(deger) && any(is.na(deger) | !nzchar(trimws(deger)))) {
      gecersiz <- c(gecersiz, sprintf("requirements$%s bos veya NA deger iceremez.", alan))
    }
    if (identical(alan, "dimensions")) deger <- c(deger, group_by)
    deger <- unique(trimws(deger[!is.na(deger) & nzchar(trimws(deger))]))
    for (cap in deger) {
      # AYNI AD-GÜVENLİ OKUMA: `istekler` `list()` olarak başlar ve karakter
      # alt simgesi boş/adsız listede `NULL` yerine HATA üretir.
      mevcut_istek <- .pk_meta_named_entry(istekler, cap)
      if (!is.null(mevcut_istek) && !identical(mevcut_istek, unname(alanlar[[alan]]))) {
        gecersiz <- c(gecersiz, sprintf("capability '%s' birden fazla rol altinda istendi.", cap))
      } else {
        istekler[[cap]] <- unname(alanlar[[alan]])
      }
    }
  }

  entity_req <- requirements$entity
  if (!is.null(entity_req) && !.pk_meta_is_scalar_text(entity_req)) {
    gecersiz <- c(gecersiz, "requirements$entity tek bos olmayan metin veya NULL olmalidir.")
    entity_req <- NULL
  }
  if (.pk_meta_is_scalar_text(entity_req)) entity_req <- trimws(entity_req)

  beyan <- .pk_meta_declared_capability_records(query)
  eksik <- setdiff(names(istekler), names(beyan))
  rol_uyusmazliklari <- list()
  sutunlar <- list()

  for (cap in intersect(names(istekler), names(beyan))) {
    beklenen <- istekler[[cap]]
    bulunan <- beyan[[cap]]$role
    if (!identical(beklenen, bulunan)) {
      rol_uyusmazliklari[[cap]] <- list(expected = beklenen, actual = bulunan)
    } else {
      sutunlar[[cap]] <- beyan[[cap]]$column
    }
  }

  meta <- .pk_meta_of(query)
  declared_entities <- unique(c(
    if (.pk_meta_is_scalar_text(meta$entity)) trimws(meta$entity) else character(0),
    unlist(lapply(meta$column_meta %||% list(), function(cm) {
      if (is.list(cm) && .pk_meta_is_scalar_text(cm$entity)) trimws(cm$entity) else character(0)
    }), use.names = FALSE)
  ))
  entity_missing <- if (.pk_meta_is_scalar_text(entity_req) && !(entity_req %in% declared_entities)) {
    entity_req
  } else {
    character(0)
  }

  durum <- if (length(eksik) || length(rol_uyusmazliklari) ||
                length(entity_missing) || length(gecersiz)) {
    PK_META_STATUS_NO_SEMANTICS
  } else {
    PK_META_STATUS_OK
  }

  list(
    status = durum,
    missing = unique(c(
      eksik,
      names(rol_uyusmazliklari),
      if (length(entity_missing)) paste0("entity:", entity_missing) else character(0)
    )),
    columns = sutunlar,
    entity = if (!length(entity_missing)) entity_req else NULL,
    missing_entity = entity_missing,
    role_mismatches = rol_uyusmazliklari,
    invalid_requirements = unique(gecersiz)
  )
}

.pk_meta_validate_rls_columns <- function(query_id, rls_columns) {
  if (is.null(rls_columns)) return(character(0))
  if (!is.list(rls_columns)) {
    return(.pk_meta_err(query_id, "rls_columns adlandirilmis liste olmalidir."))
  }
  if (!length(rls_columns)) return(character(0))

  adlar <- names(rls_columns)
  if (is.null(adlar) || length(adlar) != length(rls_columns) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(.pk_meta_err(query_id, "rls_columns adlandirilmis liste olmalidir."))
  }

  hatalar <- character(0)
  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "rls_columns icinde tekrar eden alan: %s", paste(tekrar, collapse = ", ")
    )))
  }

  bilinmeyen <- setdiff(adlar, PK_META_RLS_FIELDS)
  if (length(bilinmeyen)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "rls_columns bilinmeyen alan iceriyor: %s", paste(bilinmeyen, collapse = ", ")
    )))
  }

  for (alan in adlar) {
    deger <- rls_columns[[alan]]
    if (is.null(deger)) next
    if (!.pk_meta_is_scalar_text(deger)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "rls_columns$%s ya NULL ya tek bos olmayan sutun adi olmalidir.", alan
      )))
    }
  }

  unique(hatalar)
}

pk_meta_validate_actual_columns <- function(query, actual_columns) {
  meta <- .pk_meta_of(query)
  query_id <- if (is.list(query) && .pk_meta_is_scalar_text(query$id)) query$id else "unknown"
  rls <- if (is.list(query)) query$rls_columns else NULL
  rls_hatalari <- .pk_meta_validate_rls_columns(query_id, rls)

  gercek_girdi <- as.character(actual_columns %||% character(0))
  gecersiz_gercek <- gercek_girdi[is.na(gercek_girdi) | !nzchar(trimws(gercek_girdi))]
  gercek_ham <- gercek_girdi[!is.na(gercek_girdi) & nzchar(trimws(gercek_girdi))]
  # KARŞILAŞTIRMANIN İKİ TARAFI DA AYNI BİÇİMDE KIRPILIR. `sutun` (RLS) ve
  # `rls_beyan_edilen` zaten `trimws()` ile üretiliyordu; `gercek` ham kalınca
  # sürücünün baş/son boşluklu döndürdüğü bir sütun adı VAR OLDUĞU HÂLDE
  # `missing_rls` / `missing_declared` olarak raporlanıyor ve çağıran zararsız
  # bir sebeple kapalı başarısız oluyordu. Mükerrer denetimi de kırpılmış
  # değer üzerinden bakar; " PK " ile "PK" aynı sütundur.
  gercek_kirpik <- trimws(gercek_ham)
  tekrar_gercek <- unique(gercek_kirpik[duplicated(gercek_kirpik)])
  gercek <- unique(gercek_kirpik)

  eksik_rls <- character(0)
  if (!length(rls_hatalari) && is.list(rls)) {
    for (alan in names(rls)) {
      deger <- rls[[alan]]
      if (is.null(deger)) next
      sutun <- trimws(deger)
      if (!(sutun %in% gercek)) eksik_rls <- c(eksik_rls, sutun)
    }
  }

  beyan <- unique(c(
    names(meta$column_meta %||% list()),
    as.character(meta$grain_columns %||% character(0)),
    as.character(meta$default_group_by %||% character(0)),
    as.character(meta$default_measures %||% character(0)),
    if (.pk_meta_is_scalar_text(meta$primary_entity)) meta$primary_entity else character(0),
    .pk_meta_reference_columns(meta)
  ))
  beyan <- beyan[!is.na(beyan) & nzchar(trimws(beyan))]
  # Beyan tarafı da kırpılarak karşılaştırılır; raporlanan ad beyandaki hâlidir.
  eksik_beyan <- beyan[!(trimws(beyan) %in% gercek)]

  hatalar <- rls_hatalari
  if (length(gecersiz_gercek)) {
    hatalar <- c(hatalar, "Gercek sorgu sonucu bos veya NA sutun adi iceriyor.")
  }
  if (length(tekrar_gercek)) {
    hatalar <- c(hatalar, sprintf(
      "Gercek sorgu sonucunda tekrar eden sutun adi var: %s",
      paste(tekrar_gercek, collapse = ", ")
    ))
  }
  if (length(eksik_rls)) {
    hatalar <- c(hatalar, sprintf(
      "Beyan edilen RLS sutunu gercek sonucta yok: %s",
      paste(unique(eksik_rls), collapse = ", ")
    ))
  }
  if (length(eksik_beyan)) {
    hatalar <- c(hatalar, sprintf(
      "Beyan edilen metadata sutunu gercek sonucta yok: %s",
      paste(eksik_beyan, collapse = ", ")
    ))
  }

  # RLS sütun adları AYNI biçimde karşılaştırılmalıdır. `eksik_rls` yukarıda
  # trimws() ile karşılaştırıldığı için mükerrer-sütun çakışması da trimlenmiş
  # değer üzerinden bakılır. Aksi halde " PK " gibi boşluklu bir beyan, gerçek
  # sonuçtaki mükerrer "PK" sütunuyla eşleşmez ve fail_closed SESSİZCE FALSE
  # kalır; yani belirsiz bir RLS sütunu güvenli sayılır.
  rls_beyan_edilen <- unique(trimws(as.character(
    unlist(if (is.list(rls)) rls else list(), use.names = FALSE)
  )))

  # BOZUK SONUÇ ŞEKLİ HER MOTORDA KOŞULSUZ DURDURUR.
  #
  # Mükerrer ya da boş/NA GERÇEK sütun adı bir "metadata anlam uyuşmazlığı"
  # değil, sonucun KENDİSİNİN bozuk olmasıdır. v1 hattı tamamen AD TABANLIDIR
  # (`df[[col]]`, ada göre filtre kriteri, `summarize_columns_for_ai()` içinde
  # `names(df)` gezip `df[[col]]` okumak): aynı adı taşıyan iki sütunun İKİSİ de
  # ilk eşleşme olarak raporlanır/analiz edilir, ikinci değer sessizce yanlış
  # sunulur. Bu yüzden durdurma RLS kesişimine ya da motor bayrağına BAĞLI
  # DEĞİLDİR. Yalnızca "beyan edilen metadata sütunu sonuçta yok" durumu v1'de
  # uyarı olarak kalır (geçerli bir sonuç şekli + eksik beyan).
  list(
    ok = !length(hatalar),
    fail_closed = length(rls_hatalari) > 0L || length(eksik_rls) > 0L ||
      length(gecersiz_gercek) > 0L || length(tekrar_gercek) > 0L ||
      length(intersect(tekrar_gercek, rls_beyan_edilen)) > 0L,
    invalid_rls = rls_hatalari,
    missing_rls = unique(eksik_rls),
    missing_declared = eksik_beyan,
    errors = unique(hatalar)
  )
}

.pk_meta_reference_columns <- function(meta) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar)) return(character(0))

  out <- character(0)
  for (cmeta in sutunlar) {
    if (!is.list(cmeta)) next
    out <- c(
      out,
      as.character(cmeta$weight_by %||% character(0)),
      as.character(cmeta$latest_by %||% character(0)),
      as.character(cmeta$latest_tie_by %||% character(0))
    )
  }

  unique(out[!is.na(out) & nzchar(trimws(out))])
}
