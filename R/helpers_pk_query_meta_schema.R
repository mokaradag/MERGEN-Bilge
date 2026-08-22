# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta_schema.R
# Açıklama: Sorgu metadata sözlüğü ve şemadan bağımsız doğrulayıcılar.
# ==============================================================================

PK_META_ROLES <- c("id", "dimension", "measure", "date")
PK_META_CAPABILITY_ROLES <- c("dimension", "measure", "date")
PK_META_AGGREGATES <- c("sum", "mean", "weighted_mean", "latest", "none")
PK_META_MATCH_MODES <- c("exact", "resolve", "contains", "none")
PK_META_PERCENT_SCALES <- c("points", "fraction")
PK_META_ALIAS_PROVENANCE <- c("synthetic", "approved")

# Isleyicilerin (pk_fmt_number / .pk_export_number_format) destekledigi AZAMI
# ondalik hassasiyet. Metadata bundan fazlasini BEYAN EDEMEZ; aksi halde
# dogrulanmis bir sorgu, ciktisinda sessizce daha az hassasiyet yayinlar.
PK_META_MAX_DECIMALS <- 9L
.PK_META_CAPABILITY_PATTERN <- "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"

.pk_meta_is_scalar_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

.pk_meta_is_scalar_flag <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

.pk_meta_is_scalar_logical_or_na <- function(x) {
  is.logical(x) && length(x) == 1L
}

.pk_meta_is_text_vector <- function(x, allow_empty = TRUE) {
  if (!is.character(x)) return(FALSE)
  if (!length(x)) return(isTRUE(allow_empty))
  all(!is.na(x) & nzchar(trimws(x)))
}

.pk_meta_is_whole_number <- function(x, min = NULL, max = NULL) {
  if (length(x) != 1L) return(FALSE)
  if (is.logical(x) || is.list(x)) return(FALSE)
  num <- suppressWarnings(as.numeric(as.character(x)))
  if (length(num) != 1L || is.na(num) || !is.finite(num) || num != trunc(num)) return(FALSE)
  if (!is.null(min) && num < min) return(FALSE)
  if (!is.null(max) && num > max) return(FALSE)
  TRUE
}

.pk_meta_err <- function(query_id, ...) {
  sprintf("[%s] %s", as.character(query_id)[1], paste0(...))
}

pk_meta_validate_capability_registry <- function(registry) {
  if (is.null(registry)) return(character(0))
  if (!is.list(registry)) return("pk_capability_registry bir liste olmalidir.")

  # BOŞ kayıt MEŞRU bir durumdur: hiçbir yetenek henüz küre edilmemiştir.
  # `names(list())` NULL döndügü icin bu erken cikis olmadan asagidaki
  # "adlandirilmis olmalidir" kontrolu bos kaydi HATA sayar ve baslangici
  # dusurur. Kardes dogrulayicilar (.pk_meta_validate_named_layer,
  # .pk_meta_validate_rls_columns) da bos girdiyi ayni sekilde kabul eder;
  # bu erken cikisi kaldirmak o sozlesmeyi bozar.
  if (!length(registry)) return(character(0))

  adlar <- names(registry)
  if (is.null(adlar) || length(adlar) != length(registry) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return("pk_capability_registry adlandirilmis bir liste olmalidir.")
  }

  hatalar <- character(0)
  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, sprintf(
      "pk_capability_registry icinde tekrar eden yetenek kimligi: %s",
      paste(tekrar, collapse = ", ")
    ))
  }

  gecersiz_ad <- adlar[!grepl(.PK_META_CAPABILITY_PATTERN, adlar)]
  if (length(gecersiz_ad)) {
    hatalar <- c(hatalar, sprintf(
      "pk_capability_registry: kararli olmayan yetenek kimligi: %s",
      paste(gecersiz_ad, collapse = ", ")
    ))
  }

  for (cap in adlar) {
    girdi <- registry[[cap]]
    if (!is.list(girdi)) {
      hatalar <- c(hatalar, sprintf("pk_capability_registry['%s'] liste olmalidir.", cap))
      next
    }

    if (!.pk_meta_is_scalar_text(girdi$role) || !(girdi$role %in% PK_META_CAPABILITY_ROLES)) {
      hatalar <- c(hatalar, sprintf(
        "pk_capability_registry['%s']: gecersiz role (izinli: %s).",
        cap, paste(PK_META_CAPABILITY_ROLES, collapse = "/")
      ))
    }

    if (!is.null(girdi$unit) && !.pk_meta_is_scalar_text(girdi$unit)) {
      hatalar <- c(hatalar, sprintf(
        "pk_capability_registry['%s']: unit ya NULL ya tek metin olmalidir.", cap
      ))
    }

    if (identical(girdi$role, "dimension") || identical(girdi$role, "date")) {
      if (!is.null(girdi$unit)) {
        hatalar <- c(hatalar, sprintf(
          "pk_capability_registry['%s']: %s rolunde unit tanimlanamaz.", cap, girdi$role
        ))
      }
    }
  }

  unique(hatalar)
}

pk_meta_validate_column <- function(query_id, column, cmeta, registry = NULL) {
  onek <- sprintf("column_meta['%s']:", column)
  if (!is.list(cmeta)) return(.pk_meta_err(query_id, onek, " liste olmalidir."))

  hatalar <- character(0)
  if (!.pk_meta_is_scalar_text(cmeta$role) || !(cmeta$role %in% PK_META_ROLES)) {
    return(.pk_meta_err(query_id, onek, sprintf(
      " gecersiz role (izinli: %s).", paste(PK_META_ROLES, collapse = "/")
    )))
  }

  for (alan in c("label", "entity", "unit")) {
    if (!is.null(cmeta[[alan]]) && !.pk_meta_is_scalar_text(cmeta[[alan]])) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
        " %s ya NULL ya tek bos olmayan metin olmalidir.", alan
      )))
    }
  }

  if (!is.null(cmeta$match) &&
      (!.pk_meta_is_scalar_text(cmeta$match) || !(cmeta$match %in% PK_META_MATCH_MODES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz match (izinli: %s).", paste(PK_META_MATCH_MODES, collapse = "/")
    )))
  }

  if (.pk_meta_is_scalar_text(cmeta$match) && cmeta$match %in% c("resolve", "contains") &&
      !identical(cmeta$role, "dimension")) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " role='%s' sutununda bulanik match kullanilamaz; resolve/contains yalnizca dimension icindir.",
      cmeta$role
    )))
  }

  if (!is.null(cmeta$entity) && !(cmeta$role %in% c("id", "dimension"))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " entity yalnizca role='id' veya role='dimension' sutununda tanimlanabilir."))
  }

  if (!is.null(cmeta$aggregate) &&
      (!.pk_meta_is_scalar_text(cmeta$aggregate) || !(cmeta$aggregate %in% PK_META_AGGREGATES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz aggregate (izinli: %s).", paste(PK_META_AGGREGATES, collapse = "/")
    )))
  }

  for (alan in c("additive", "filterable", "allow_aliases")) {
    if (!is.null(cmeta[[alan]]) && !.pk_meta_is_scalar_flag(cmeta[[alan]])) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
        " %s tek TRUE/FALSE olmalidir.", alan
      )))
    }
  }

  if (!is.null(cmeta$high_cardinality) &&
      !.pk_meta_is_scalar_logical_or_na(cmeta$high_cardinality)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " high_cardinality tek TRUE/FALSE/NA olmalidir."))
  }

  if (!is.null(cmeta$tier) &&
      !.pk_meta_is_whole_number(cmeta$tier, min = 0, max = .Machine$integer.max)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " tier negatif olmayan tam sayi olmalidir."))
  }

  # PR #705: `decimals` DOGRULAMASI, ISLEYICILERIN GERCEKTEN destekledigi
  # hassasiyetle SINIRLIDIR. `pk_fmt_number()` ve `.pk_export_number_format()`
  # degeri SESSIZCE 9'a kirpar; validator 10-15 arasi bir beyani kabul
  # ederse sorgu "dogrulanmis" gorunur ama ciktisi beyandan DAHA AZ hassastir.
  # Sozlesme ile isleyici arasindaki bu sessiz uyusmazlik KAPATILIR.
  if (!is.null(cmeta$decimals) &&
      !.pk_meta_is_whole_number(cmeta$decimals, min = 0, max = PK_META_MAX_DECIMALS)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " decimals 0 ile %d arasinda tam sayi olmalidir (isleyici siniri).",
      PK_META_MAX_DECIMALS
    )))
  }

  if (!is.null(cmeta$percent_scale) &&
      (!.pk_meta_is_scalar_text(cmeta$percent_scale) ||
       !(cmeta$percent_scale %in% PK_META_PERCENT_SCALES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz percent_scale (izinli: %s).", paste(PK_META_PERCENT_SCALES, collapse = "/")
    )))
  }

  if (.pk_meta_is_scalar_text(cmeta$unit) && identical(trimws(cmeta$unit), "%") &&
      (!.pk_meta_is_scalar_text(cmeta$percent_scale) ||
       !(cmeta$percent_scale %in% PK_META_PERCENT_SCALES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " unit='%%' iken percent_scale zorunludur (izinli: %s).",
      paste(PK_META_PERCENT_SCALES, collapse = "/")
    )))
  }

  if (!is.null(cmeta$percent_scale) &&
      (!.pk_meta_is_scalar_text(cmeta$unit) || !identical(trimws(cmeta$unit), "%"))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " percent_scale yalnizca unit='%' olan sutunda tanimlanabilir."))
  }

  if (!identical(cmeta$role, "measure")) {
    if (!is.null(cmeta$additive)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
        " additive yalnizca role='measure' sutununda tanimlanabilir."))
    }
    if (.pk_meta_is_scalar_text(cmeta$aggregate) &&
        cmeta$aggregate %in% c("sum", "mean", "weighted_mean")) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
        " aggregate='%s' yalnizca role='measure' sutununda kullanilabilir.", cmeta$aggregate
      )))
    }
  }

  if (identical(cmeta$aggregate, "sum") && !isTRUE(cmeta$additive)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " aggregate='sum' icin additive=TRUE zorunludur; aksi halde sessiz yanlis toplam uretilir."))
  }

  if (!is.null(cmeta$domain)) {
    if (!(cmeta$role %in% c("id", "dimension"))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
        " domain yalnizca role='id' veya role='dimension' sutununda tanimlanabilir."))
    }
    hatalar <- c(hatalar, pk_meta_validate_domain_map(query_id, column, cmeta$domain))
  }

  if (!is.null(cmeta$aliases)) {
    if (!(cmeta$role %in% c("id", "dimension"))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
        " aliases yalnizca role='id' veya role='dimension' sutununda tanimlanabilir."))
    }
    if (!isTRUE(cmeta$allow_aliases) &&
        (identical(cmeta$role, "id") || identical(cmeta$match, "exact"))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
        " kod/kimlik veya exact sutunu alias alamaz; allow_aliases=TRUE zorunludur."))
    }
    katlama <- pk_meta_fold_alias_map(query_id, column, cmeta$aliases)
    hatalar <- c(hatalar, katlama$errors)
  }

  c(
    unique(hatalar),
    .pk_meta_validate_column_capability(query_id, onek, cmeta, registry)
  )
}

.pk_meta_validate_column_capability <- function(query_id, onek, cmeta, registry) {
  if (is.null(cmeta$capability)) return(character(0))
  if (!.pk_meta_is_scalar_text(cmeta$capability)) {
    return(.pk_meta_err(query_id, onek, " capability tek metin olmalidir."))
  }

  cap <- trimws(cmeta$capability)
  if (!is.list(registry) || is.null(registry[[cap]])) {
    return(.pk_meta_err(query_id, onek, sprintf(
      " bilinmeyen capability '%s' (pk_capability_registry icinde tanimli degil).", cap
    )))
  }

  kayit <- registry[[cap]]
  hatalar <- character(0)
  if (!is.list(kayit)) {
    return(.pk_meta_err(query_id, onek, sprintf(
      " capability '%s' kaydi liste degil.", cap
    )))
  }

  if (!identical(cmeta$role, kayit$role)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " capability '%s' role='%s' bekler, sutun role='%s'.",
      cap, as.character(kayit$role)[1], as.character(cmeta$role)[1]
    )))
  }

  kayit_birim <- if (is.null(kayit$unit)) NA_character_ else trimws(as.character(kayit$unit)[1])
  sutun_birim <- if (is.null(cmeta$unit)) NA_character_ else trimws(as.character(cmeta$unit)[1])
  if (!identical(kayit_birim, sutun_birim)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " capability '%s' unit='%s' bekler, sutun unit='%s'.",
      cap,
      if (is.na(kayit_birim)) "NULL" else kayit_birim,
      if (is.na(sutun_birim)) "NULL" else sutun_birim
    )))
  }

  unique(hatalar)
}

pk_meta_validate_domain_map <- function(query_id, column, domain) {
  onek <- sprintf("column_meta['%s']$domain:", column)
  if (is.null(domain)) return(character(0))

  # BOŞ domain haritasi MEŞRUDUR (alan beyan edildi, henuz eslesme girilmedi).
  # `names(list())` / `names(character(0))` NULL oldugundan bu erken cikis
  # olmadan asagidaki "adlandirilmis harita olmalidir" kontrolu bos haritayi
  # HATA sayardi. pk_meta_fold_alias_map() bos alias haritasini zaten ayni
  # sekilde kabul ediyor; iki alan arasindaki bu tutarlilik korunmalidir.
  if (!length(domain)) return(character(0))

  if (!(is.character(domain) || is.list(domain)) || is.null(names(domain)) ||
      length(names(domain)) != length(domain)) {
    return(.pk_meta_err(query_id, onek,
      " adlandirilmis kanonik-deger -> etiket haritasi olmalidir."))
  }

  anahtarlar <- names(domain)
  hatalar <- character(0)
  if (any(is.na(anahtarlar) | !nzchar(trimws(anahtarlar)))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " bos veya NA kanonik anahtar iceremez."))
  }

  tekrar <- unique(anahtarlar[duplicated(anahtarlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " tekrar eden kanonik anahtar: %s", paste(tekrar, collapse = ", ")
    )))
  }

  etiketler <- vapply(domain, function(x) {
    if (!.pk_meta_is_scalar_text(x)) return(NA_character_)
    trimws(enc2utf8(as.character(x)[1]))
  }, character(1))
  if (any(is.na(etiketler))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " her etiket tek ve bos olmayan metin olmalidir."))
  }

  gecerli <- !is.na(etiketler)
  if (any(gecerli)) {
    katlanmis <- pk_tr_fold(etiketler[gecerli])
    for (etiket in unique(katlanmis)) {
      hedefler <- unique(anahtarlar[gecerli][katlanmis == etiket])
      if (!is.na(etiket) && nzchar(etiket) && length(hedefler) > 1L) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
          " '%s' etiketi birden fazla kanonik degere isaret ediyor: %s",
          etiket, paste(hedefler, collapse = " | ")
        )))
      }
    }
  }

  unique(hatalar)
}

pk_meta_fold_alias_map <- function(query_id, column, aliases) {
  bos <- structure(character(0), names = character(0))
  if (is.null(aliases) || length(aliases) == 0L) {
    return(list(aliases = bos, errors = character(0)))
  }

  onek <- sprintf("column_meta['%s']$aliases:", column)
  if (!is.character(aliases) || is.null(names(aliases)) ||
      length(names(aliases)) != length(aliases)) {
    return(list(
      aliases = bos,
      errors = .pk_meta_err(query_id, onek, " adlandirilmis karakter vektoru olmalidir.")
    ))
  }

  ham_ad <- names(aliases)
  hatalar <- character(0)
  katlanmis <- pk_tr_fold(ham_ad)
  gecersiz <- is.na(katlanmis) | !nzchar(katlanmis)
  if (any(gecersiz)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, " bos alias anahtari var."))
  }

  hedef <- trimws(enc2utf8(as.character(aliases)))
  hedef_bos <- is.na(hedef) | !nzchar(hedef)
  if (any(hedef_bos)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " bos kanonik hedef: %s", paste(ham_ad[hedef_bos], collapse = ", ")
    )))
  }

  tut <- !gecersiz & !hedef_bos
  katlanmis <- katlanmis[tut]
  hedef <- hedef[tut]

  for (anahtar in unique(katlanmis)) {
    degerler <- unique(hedef[katlanmis == anahtar])
    if (length(degerler) > 1L) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
        " '%s' alias'i birden fazla kanonik degere isaret ediyor: %s",
        anahtar, paste(degerler, collapse = " | ")
      )))
    }
  }

  benzersiz <- !duplicated(katlanmis)
  sonuc <- hedef[benzersiz]
  names(sonuc) <- katlanmis[benzersiz]

  list(aliases = sonuc, errors = unique(hatalar))
}
