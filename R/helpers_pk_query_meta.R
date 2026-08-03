# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta.R
# Açıklama: Metadata katman birleştirme, alias bindirme ve başlangıç doğrulama.
# ==============================================================================

PK_META_SCHEMA_PENDING <- "pending_no_schema"
PK_META_SCHEMA_VALIDATED <- "validated"

.pk_meta_collect_layer <- function(name, envir, fallback = list()) {
  if (!exists(name, envir = envir, inherits = TRUE)) return(fallback)
  get(name, envir = envir, inherits = TRUE)
}

.pk_meta_validate_named_layer <- function(name, layer) {
  if (is.null(layer)) return(character(0))
  if (!is.list(layer)) return(sprintf("%s adlandirilmis liste olmalidir.", name))
  if (!length(layer)) return(character(0))

  adlar <- names(layer)
  if (is.null(adlar) || length(adlar) != length(layer) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(sprintf("%s adlandirilmis liste olmalidir.", name))
  }

  hatalar <- character(0)
  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, sprintf(
      "%s icinde tekrar eden kimlik: %s", name, paste(tekrar, collapse = ", ")
    ))
  }

  liste_olmayan <- adlar[!vapply(layer, is.list, logical(1))]
  if (length(liste_olmayan)) {
    hatalar <- c(hatalar, sprintf(
      "%s icindeki her sorgu girdisi liste olmalidir: %s",
      name, paste(liste_olmayan, collapse = ", ")
    ))
  }

  unique(hatalar)
}

.pk_meta_merge_one <- function(alt, ustun) {
  if (!is.list(alt)) alt <- list()
  if (!is.list(ustun)) return(alt)

  out <- alt
  for (alan in names(ustun)) {
    if (is.na(alan) || !nzchar(alan)) next
    ust_deger <- ustun[[alan]]
    alt_deger <- alt[[alan]]

    if (identical(alan, "column_meta") && is.list(ust_deger)) {
      birlesik <- if (is.list(alt_deger)) alt_deger else list()
      for (sutun in names(ust_deger)) {
        if (is.na(sutun) || !nzchar(sutun)) next
        yeni <- ust_deger[[sutun]]
        if (!is.list(yeni)) {
          birlesik[[sutun]] <- yeni
          next
        }

        mevcut <- if (is.list(birlesik[[sutun]])) birlesik[[sutun]] else list()
        for (calan in names(yeni)) {
          if (is.na(calan) || !nzchar(calan)) next
          mevcut[[calan]] <- yeni[[calan]]
        }
        birlesik[[sutun]] <- mevcut
      }
      out[[alan]] <- birlesik
    } else {
      out[[alan]] <- ust_deger
    }
  }

  out
}

pk_meta_merge_layers <- function(auto = list(), local = list(), curated = list()) {
  auto <- if (is.list(auto)) auto else list()
  local <- if (is.list(local)) local else list()
  curated <- if (is.list(curated)) curated else list()

  kimlikler <- unique(c(names(auto), names(local), names(curated)))
  kimlikler <- kimlikler[!is.na(kimlikler) & nzchar(trimws(kimlikler))]

  out <- list()
  for (id in kimlikler) {
    birlesik <- .pk_meta_merge_one(list(), auto[[id]])
    birlesik <- .pk_meta_merge_one(birlesik, local[[id]])
    birlesik <- .pk_meta_merge_one(birlesik, curated[[id]])
    out[[id]] <- birlesik
  }
  out
}

.pk_meta_alias_allowed <- function(cmeta) {
  if (!is.list(cmeta)) return(TRUE)
  if (isTRUE(cmeta$allow_aliases)) return(TRUE)
  if (identical(cmeta$role, "id")) return(FALSE)
  if (.pk_meta_is_scalar_text(cmeta$match) && identical(cmeta$match, "exact")) return(FALSE)
  TRUE
}

# Birleşmiş katmanlardaki alias'ları da aynı sözleşmeyle katlar.
pk_meta_normalize_aliases <- function(meta) {
  hatalar <- character(0)
  if (!is.list(meta) || !length(meta)) return(list(meta = meta, errors = hatalar))

  for (id in names(meta)) {
    sutunlar <- meta[[id]]$column_meta
    if (!is.list(sutunlar) || !length(sutunlar)) next

    for (sutun in names(sutunlar)) {
      cmeta <- sutunlar[[sutun]]
      if (!is.list(cmeta) || is.null(cmeta$aliases)) next

      katlama <- pk_meta_fold_alias_map(id, sutun, cmeta$aliases)
      hatalar <- c(hatalar, katlama$errors)
      if (!length(katlama$errors)) meta[[id]]$column_meta[[sutun]]$aliases <- katlama$aliases
    }
  }

  list(meta = meta, errors = unique(hatalar))
}

pk_meta_apply_alias_overlay <- function(meta, overlay) {
  hatalar <- character(0)
  if (is.null(overlay) || !length(overlay)) return(list(meta = meta, errors = hatalar))
  if (!is.list(overlay)) {
    return(list(meta = meta, errors = "pk_query_aliases_local adlandirilmis liste olmalidir."))
  }

  adlar <- names(overlay)
  if (is.null(adlar) || length(adlar) != length(overlay) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(list(meta = meta, errors = "pk_query_aliases_local adlandirilmis liste olmalidir."))
  }
  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, sprintf(
      "pk_query_aliases_local icinde tekrar eden sorgu kimligi: %s",
      paste(tekrar, collapse = ", ")
    ))
  }

  for (id in adlar) {
    sorgu_alias <- overlay[[id]]
    if (is.null(meta[[id]])) {
      hatalar <- c(hatalar, sprintf(
        "[%s] alias bindirmesi tanimsiz sorgu kimligine yapiliyor (R/library_query_aliases_local.R).",
        id
      ))
      next
    }

    if (!is.list(sorgu_alias)) {
      hatalar <- c(hatalar, sprintf("[%s] alias bindirmesi sutun -> alias listesi olmalidir.", id))
      next
    }

    sutun_adlari <- names(sorgu_alias)
    if (length(sorgu_alias) &&
        (is.null(sutun_adlari) || length(sutun_adlari) != length(sorgu_alias) ||
         any(is.na(sutun_adlari) | !nzchar(trimws(sutun_adlari))))) {
      hatalar <- c(hatalar, sprintf("[%s] alias bindirmesi adlandirilmis sutun listesi olmalidir.", id))
      next
    }

    sutun_tekrar <- unique(sutun_adlari[duplicated(sutun_adlari)])
    if (length(sutun_tekrar)) {
      hatalar <- c(hatalar, sprintf(
        "[%s] alias bindirmesinde tekrar eden sutun: %s", id, paste(sutun_tekrar, collapse = ", ")
      ))
    }

    for (sutun in sutun_adlari) {
      cmeta <- meta[[id]]$column_meta[[sutun]]
      if (!is.list(cmeta)) {
        hatalar <- c(hatalar, sprintf(
          paste0(
            "[%s] alias bindirmesi beyan edilmemis '%s' sutununa yapiliyor. ",
            "Once metadata ureticisini calistirin ya da sutunu kure edin."
          ), id, sutun
        ))
        next
      }

      if (!.pk_meta_alias_allowed(cmeta)) {
        hatalar <- c(hatalar, sprintf(
          paste0(
            "[%s] column_meta['%s']: kod/kimlik sutunu alias alamaz. ",
            "Ayrica gozden gecirilmis allow_aliases=TRUE beyani gerekir."
          ), id, sutun
        ))
        next
      }

      mevcut <- cmeta$aliases
      if (is.null(mevcut)) mevcut <- structure(character(0), names = character(0))
      yeni <- sorgu_alias[[sutun]]
      birlesik_alias <- tryCatch(
        c(mevcut, yeni),
        error = function(e) NULL
      )

      if (is.null(birlesik_alias)) {
        hatalar <- c(hatalar, .pk_meta_err(id, sprintf(
          "column_meta['%s']$aliases: mevcut ve yerel alias haritalari birlestirilemedi.", sutun
        )))
        next
      }

      katlama <- pk_meta_fold_alias_map(id, sutun, birlesik_alias)
      hatalar <- c(hatalar, katlama$errors)
      if (!length(katlama$errors)) {
        meta[[id]]$column_meta[[sutun]]$aliases <- katlama$aliases
        meta[[id]]$column_meta[[sutun]]$alias_provenance <- "local_overlay"
      }
    }
  }

  list(meta = meta, errors = unique(hatalar))
}

pk_meta_validate_query <- function(query_id, meta, registry = NULL) {
  if (is.null(meta) || !length(meta)) return(character(0))
  if (!is.list(meta)) return(.pk_meta_err(query_id, "metadata liste olmalidir."))

  hatalar <- character(0)
  sutunlar <- meta$column_meta

  if (!is.null(meta$grain) && !.pk_meta_is_scalar_text(meta$grain)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, "grain tek bos olmayan metin olmalidir."))
  }
  if (!is.null(meta$primary_entity) && !.pk_meta_is_scalar_text(meta$primary_entity)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, "primary_entity tek bos olmayan metin olmalidir."))
  }
  if (!is.null(meta$entity) && !.pk_meta_is_scalar_text(meta$entity)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, "entity tek bos olmayan metin olmalidir."))
  }

  for (alan in c("keywords", "sample_questions", "intents", "not_for")) {
    if (!is.null(meta[[alan]]) && !.pk_meta_is_text_vector(meta[[alan]], allow_empty = TRUE)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "%s bos olmayan metinlerden olusan karakter vektoru olmalidir.", alan
      )))
    } else if (is.character(meta[[alan]]) && anyDuplicated(meta[[alan]])) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "%s tekrar eden deger iceremez.", alan
      )))
    }
  }

  for (alan in c("grain_columns", "default_group_by", "default_measures")) {
    if (!is.null(meta[[alan]]) && !.pk_meta_is_text_vector(meta[[alan]], allow_empty = TRUE)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "%s bos olmayan metinlerden olusan karakter vektoru olmalidir.", alan
      )))
    } else if (is.character(meta[[alan]]) && anyDuplicated(meta[[alan]])) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "%s tekrar eden sutun iceremez.", alan
      )))
    }
  }

  if (!is.null(meta$grain) &&
      !.pk_meta_is_text_vector(meta$grain_columns, allow_empty = FALSE)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id,
      "grain beyan edildiginde bos olmayan grain_columns zorunludur."))
  }

  if (!is.null(meta$row_cap) &&
      !.pk_meta_is_whole_number(meta$row_cap, min = 1, max = .Machine$integer.max)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, "row_cap pozitif tam sayi olmalidir."))
  }
  if (!is.null(meta$tier) &&
      !.pk_meta_is_whole_number(meta$tier, min = 0, max = .Machine$integer.max)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, "tier negatif olmayan tam sayi olmalidir."))
  }

  if (!is.null(sutunlar) && !is.list(sutunlar)) {
    return(unique(c(hatalar, .pk_meta_err(query_id, "column_meta liste olmalidir."))))
  }

  if (is.list(sutunlar) && length(sutunlar)) {
    adlar <- names(sutunlar)
    if (is.null(adlar) || length(adlar) != length(sutunlar) ||
        any(is.na(adlar) | !nzchar(trimws(adlar)))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, "column_meta adlandirilmis olmalidir."))
    } else {
      tekrar <- unique(adlar[duplicated(adlar)])
      if (length(tekrar)) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          "column_meta icinde tekrar eden sutun: %s", paste(tekrar, collapse = ", ")
        )))
      }

      for (sutun in adlar) {
        hatalar <- c(hatalar, pk_meta_validate_column(query_id, sutun, sutunlar[[sutun]], registry))
      }
      hatalar <- c(hatalar, .pk_meta_validate_capability_uniqueness(query_id, meta))
    }
  }

  unique(c(hatalar, .pk_meta_validate_query_refs(query_id, meta)))
}

.pk_meta_validate_capability_uniqueness <- function(query_id, meta) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar) || is.null(names(sutunlar))) return(character(0))

  eslesme <- list()
  for (sutun in names(sutunlar)) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$capability)) next
    cap <- trimws(cmeta$capability)
    eslesme[[cap]] <- c(eslesme[[cap]], sutun)
  }

  varyantlar <- meta$capability_variants
  hatalar <- character(0)
  if (!is.null(varyantlar)) {
    if (!is.list(varyantlar)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, "capability_variants adlandirilmis liste olmalidir."))
      varyantlar <- list()
    } else if (length(varyantlar)) {
      adlar <- names(varyantlar)
      if (is.null(adlar) || length(adlar) != length(varyantlar) ||
          any(is.na(adlar) | !nzchar(trimws(adlar)))) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, "capability_variants adlandirilmis liste olmalidir."))
        varyantlar <- list()
      }
    }
  } else {
    varyantlar <- list()
  }

  bilinmeyen <- setdiff(names(varyantlar), names(eslesme))
  if (length(bilinmeyen)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "capability_variants tanimsiz capability iceriyor: %s", paste(bilinmeyen, collapse = ", ")
    )))
  }

  for (cap in names(eslesme)) {
    sahipler <- unique(eslesme[[cap]])
    varyant <- varyantlar[[cap]]
    tercih <- if (is.list(varyant)) varyant$prefer else NULL

    if (!is.null(varyant) && !is.list(varyant)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "capability_variants[['%s']] liste olmalidir.", cap
      )))
    }

    if (!is.null(varyant) && (!.pk_meta_is_scalar_text(tercih) || !(tercih %in% sahipler))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "capability_variants[['%s']]$prefer bu capability'yi tasiyan bir sutun olmalidir.", cap
      )))
    }

    if (length(sahipler) > 1L &&
        (!.pk_meta_is_scalar_text(tercih) || !(tercih %in% sahipler))) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        paste0(
          "capability '%s' ayni sorguda birden fazla sutunda: %s. ",
          "capability_variants[['%s']]$prefer ile deterministik varyant kurali beyan edin."
        ), cap, paste(sahipler, collapse = ", "), cap
      )))
    }
  }

  unique(hatalar)
}

.pk_meta_validate_query_refs <- function(query_id, meta) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar) || is.null(names(sutunlar))) return(character(0))

  beyan <- names(sutunlar)
  olculer <- beyan[vapply(
    sutunlar,
    function(cm) is.list(cm) && identical(cm$role, "measure"),
    logical(1)
  )]
  tarihler <- beyan[vapply(
    sutunlar,
    function(cm) is.list(cm) && identical(cm$role, "date"),
    logical(1)
  )]
  varliklar <- beyan[vapply(
    sutunlar,
    function(cm) is.list(cm) && .pk_meta_is_scalar_text(cm$role) &&
      cm$role %in% c("id", "dimension"),
    logical(1)
  )]
  gruplanabilir <- beyan[vapply(
    sutunlar,
    function(cm) is.list(cm) && .pk_meta_is_scalar_text(cm$role) &&
      cm$role %in% c("id", "dimension", "date"),
    logical(1)
  )]
  hatalar <- character(0)

  kontrol <- function(alan, degerler, izinli, etiket) {
    if (is.null(degerler) || !length(degerler)) return(character(0))
    if (!is.character(degerler) || any(is.na(degerler) | !nzchar(trimws(degerler)))) {
      return(.pk_meta_err(query_id, sprintf("%s bos olmayan metin olmalidir.", alan)))
    }
    eksik <- setdiff(degerler, izinli)
    if (!length(eksik)) return(character(0))
    .pk_meta_err(query_id, sprintf(
      "%s beyan edilmemis %s: %s", alan, etiket, paste(eksik, collapse = ", ")
    ))
  }

  if (.pk_meta_is_scalar_text(meta$primary_entity)) {
    hatalar <- c(hatalar, kontrol(
      "primary_entity", meta$primary_entity, varliklar,
      "id veya dimension sutununa isaret ediyor"
    ))
  }
  hatalar <- c(hatalar, kontrol("grain_columns", meta$grain_columns, beyan, "sutuna isaret ediyor"))
  hatalar <- c(hatalar, kontrol(
    "default_group_by", meta$default_group_by, gruplanabilir,
    "id, dimension veya date sutununa isaret ediyor"
  ))
  hatalar <- c(hatalar, kontrol("default_measures", meta$default_measures, olculer, "olcu sutununa isaret ediyor"))

  for (sutun in beyan) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta)) next

    if (identical(cmeta$aggregate, "weighted_mean")) {
      if (!.pk_meta_is_scalar_text(cmeta$weight_by)) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          "column_meta['%s']: aggregate='weighted_mean' icin weight_by tek olcu sutunu olmalidir.", sutun
        )))
      } else {
        hatalar <- c(hatalar, kontrol(
          sprintf("column_meta['%s']$weight_by", sutun),
          cmeta$weight_by, olculer, "olcu sutununa isaret ediyor"
        ))
      }
    }

    if (identical(cmeta$aggregate, "latest")) {
      tie_gecerli <- .pk_meta_is_text_vector(cmeta$latest_tie_by, allow_empty = FALSE) &&
        !anyDuplicated(cmeta$latest_tie_by)
      if (!.pk_meta_is_scalar_text(cmeta$latest_by) || !tie_gecerli) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          paste0(
            "column_meta['%s']: aggregate='latest' icin latest_by ve latest_tie_by zorunludur; ",
            "latest_tie_by bos olmayan ve tekrarsiz olmalidir."
          ), sutun
        )))
      }
      if (.pk_meta_is_scalar_text(cmeta$latest_by)) {
        hatalar <- c(hatalar, kontrol(
          sprintf("column_meta['%s']$latest_by", sutun), cmeta$latest_by,
          beyan, "sutuna isaret ediyor"
        ))
      }
      if (.pk_meta_is_text_vector(cmeta$latest_tie_by, allow_empty = FALSE)) {
        hatalar <- c(hatalar, kontrol(
          sprintf("column_meta['%s']$latest_tie_by", sutun), cmeta$latest_tie_by,
          beyan, "sutuna isaret ediyor"
        ))
      }
    }
  }

  unique(hatalar)
}

.pk_meta_schema_parts <- function(schema) {
  if (is.data.frame(schema)) {
    tipler <- vapply(schema, function(s) class(s)[1], character(1))
    return(list(columns = names(schema), types = stats::setNames(tipler, names(schema))))
  }
  if (is.character(schema)) {
    if (is.null(names(schema))) return(list(columns = schema, types = NULL))
    return(list(columns = names(schema), types = schema))
  }
  if (is.list(schema) && !is.null(names(schema))) {
    tipler <- vapply(schema, function(x) {
      if (length(x) != 1L) return(NA_character_)
      txt <- tryCatch(as.character(x)[1], error = function(e) NA_character_)
      if (is.na(txt) || !nzchar(trimws(txt))) return(NA_character_)
      trimws(txt)
    }, character(1))
    return(list(columns = names(schema), types = stats::setNames(tipler, names(schema))))
  }
  NULL
}

pk_meta_validate_schema_dependent <- function(query_id, meta, schema, rls_columns = NULL) {
  hatalar <- .pk_meta_validate_rls_columns(query_id, rls_columns)
  if (is.null(schema) || !length(schema)) return(hatalar)

  parcalar <- .pk_meta_schema_parts(schema)
  if (is.null(parcalar)) {
    return(unique(c(hatalar, .pk_meta_err(query_id,
      "result_schema adlandirilmis karakter vektoru veya data.frame olmalidir."))))
  }

  sema_ham <- parcalar$columns
  sema_gecersiz <- sema_ham[is.na(sema_ham) | !nzchar(trimws(sema_ham))]
  sema_tekrar <- unique(sema_ham[!is.na(sema_ham) & duplicated(sema_ham)])
  sema_sutunlari <- unique(sema_ham)
  sema_sutunlari <- sema_sutunlari[!is.na(sema_sutunlari) & nzchar(trimws(sema_sutunlari))]
  if (length(sema_gecersiz)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id,
      "result_schema bos veya NA sutun adi iceremez."))
  }
  if (length(sema_tekrar)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "result_schema icinde tekrar eden sutun adi: %s", paste(sema_tekrar, collapse = ", ")
    )))
  }
  if (!is.null(parcalar$types)) {
    tipler <- as.character(parcalar$types)
    gecersiz_tip <- names(parcalar$types)[is.na(tipler) | !nzchar(trimws(tipler))]
    if (length(gecersiz_tip)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "result_schema gecersiz/bos tip iceriyor: %s", paste(gecersiz_tip, collapse = ", ")
      )))
    }
  }

  eksik_meta <- setdiff(names(meta$column_meta %||% list()), sema_sutunlari)
  if (length(eksik_meta)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "column_meta sutunu semada yok: %s", paste(eksik_meta, collapse = ", ")
    )))
  }

  if (!length(.pk_meta_validate_rls_columns(query_id, rls_columns)) && is.list(rls_columns)) {
    for (alan in names(rls_columns)) {
      deger <- rls_columns[[alan]]
      if (is.null(deger)) next
      if (!(trimws(deger) %in% sema_sutunlari)) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          "rls_columns$%s = '%s' semada yok (D6 fail-open deligi).", alan, trimws(deger)
        )))
      }
    }
  }

  top_atif <- unique(c(
    if (.pk_meta_is_scalar_text(meta$primary_entity)) meta$primary_entity else character(0),
    if (is.character(meta$grain_columns)) meta$grain_columns else character(0),
    if (is.character(meta$default_group_by)) meta$default_group_by else character(0),
    if (is.character(meta$default_measures)) meta$default_measures else character(0),
    .pk_meta_reference_columns(meta)
  ))
  top_atif <- top_atif[!is.na(top_atif) & nzchar(trimws(top_atif))]
  eksik_atif <- setdiff(top_atif, sema_sutunlari)
  if (length(eksik_atif)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "metadata atifi semada yok: %s", paste(eksik_atif, collapse = ", ")
    )))
  }

  unique(c(hatalar, .pk_meta_validate_schema_roles(query_id, meta, parcalar$types, sema_sutunlari)))
}

.pk_meta_validate_schema_roles <- function(query_id, meta, schema_types, sema_sutunlari) {
  if (is.null(schema_types) || is.null(names(schema_types))) return(character(0))
  hatalar <- character(0)

  for (sutun in intersect(names(meta$column_meta %||% list()), sema_sutunlari)) {
    cmeta <- meta$column_meta[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$role)) next
    if (!.pk_meta_is_scalar_text(schema_types[[sutun]])) next
    yapisal <- .pk_meta_role_from_class(schema_types[[sutun]])

    if (identical(cmeta$role, "date") && !identical(yapisal, "date")) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "column_meta['%s']: role='date' ama semadaki tip '%s'.",
        sutun, as.character(schema_types[[sutun]])[1]
      )))
    }
    if (identical(cmeta$role, "measure") && !identical(yapisal, "measure")) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "column_meta['%s']: role='measure' ama semadaki tip '%s' sayisal degil.",
        sutun, as.character(schema_types[[sutun]])[1]
      )))
    }
  }

  unique(hatalar)
}

pk_meta_tracked_alias_audit <- function(curated) {
  if (!is.list(curated) || !length(curated)) return(character(0))
  out <- character(0)

  for (id in names(curated)) {
    girdi <- curated[[id]]
    if (!is.list(girdi)) next
    sutunlar <- girdi$column_meta
    if (!is.list(sutunlar)) next

    for (sutun in names(sutunlar)) {
      cmeta <- sutunlar[[sutun]]
      if (!is.list(cmeta) || !length(cmeta$aliases %||% NULL)) next
      koken <- cmeta$alias_provenance
      if (!.pk_meta_is_scalar_text(koken) || !(koken %in% PK_META_ALIAS_PROVENANCE)) {
        out <- c(out, sprintf("%s/%s", id, sutun))
      }
    }
  }

  unique(out)
}

.pk_meta_validate_query_library <- function(query_library, metadata_ids = character(0)) {
  if (!is.list(query_library)) return("query_library liste olmalidir.")

  hatalar <- character(0)
  ids <- character(0)
  for (i in seq_along(query_library)) {
    q_item <- query_library[[i]]
    if (!is.list(q_item)) {
      hatalar <- c(hatalar, sprintf("query_library[[%d]] liste olmalidir.", i))
      next
    }
    if (!.pk_meta_is_scalar_text(q_item$id)) {
      hatalar <- c(hatalar, sprintf("query_library[[%d]] kararlı, bos olmayan tek id tasimalidir.", i))
      next
    }
    ids <- c(ids, trimws(q_item$id))
    if (!.pk_meta_is_scalar_text(q_item$sql)) {
      hatalar <- c(hatalar, sprintf(
        "query_library[[%d]] (%s) bos olmayan SQL tasimalidir.", i, trimws(q_item$id)
      ))
    }
  }

  tekrar <- unique(ids[duplicated(ids)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, sprintf(
      "query_library icinde tekrar eden sorgu id: %s", paste(tekrar, collapse = ", ")
    ))
  }

  bilinmeyen <- setdiff(metadata_ids, unique(ids))
  if (length(bilinmeyen)) {
    hatalar <- c(hatalar, sprintf(
      "metadata katmaninda query_library icinde bulunmayan sorgu id: %s",
      paste(bilinmeyen, collapse = ", ")
    ))
  }

  unique(hatalar)
}

pk_query_meta_attach <- function(query_library,
                                 auto = NULL,
                                 local = NULL,
                                 curated = NULL,
                                 aliases = NULL,
                                 registry = NULL,
                                 envir = globalenv()) {
  auto <- auto %||% .pk_meta_collect_layer("pk_query_meta_auto", envir)
  local <- local %||% .pk_meta_collect_layer("pk_query_meta_local", envir)
  curated <- curated %||% .pk_meta_collect_layer("pk_query_meta", envir)
  aliases <- aliases %||% .pk_meta_collect_layer("pk_query_aliases_local", envir)
  registry <- registry %||% .pk_meta_collect_layer("pk_capability_registry", envir)

  hatalar <- c(
    .pk_meta_validate_named_layer("pk_query_meta_auto", auto),
    .pk_meta_validate_named_layer("pk_query_meta_local", local),
    .pk_meta_validate_named_layer("pk_query_meta", curated),
    .pk_meta_validate_named_layer("pk_query_aliases_local", aliases),
    pk_meta_validate_capability_registry(registry)
  )

  onaysiz <- pk_meta_tracked_alias_audit(curated)
  if (length(onaysiz)) {
    hatalar <- c(hatalar, sprintf(
      paste0(
        "Izlenen R/library_query_meta.R icinde onay etiketi olmayan alias: %s. ",
        "Uretimden turetilmis kanonik hedefler yalnizca gitignore'lu ",
        "R/library_query_aliases_local.R icine yazilir."
      ), paste(onaysiz, collapse = ", ")
    ))
  }

  auto_safe <- if (is.list(auto)) auto else list()
  local_safe <- if (is.list(local)) local else list()
  curated_safe <- if (is.list(curated)) curated else list()
  aliases_safe <- if (is.list(aliases)) aliases else list()
  registry_safe <- if (is.list(registry)) registry else list()

  birlesik <- pk_meta_merge_layers(auto_safe, local_safe, curated_safe)
  hatalar <- c(hatalar, .pk_meta_validate_query_library(query_library, names(birlesik)))

  normal <- pk_meta_normalize_aliases(birlesik)
  birlesik <- normal$meta
  hatalar <- c(hatalar, normal$errors)

  bindirme <- pk_meta_apply_alias_overlay(birlesik, aliases_safe)
  birlesik <- bindirme$meta
  hatalar <- c(hatalar, bindirme$errors)

  for (id in names(birlesik)) {
    hatalar <- c(hatalar, pk_meta_validate_query(id, birlesik[[id]], registry_safe))
  }

  kutuphane_safe <- if (is.list(query_library)) query_library else list()
  for (i in seq_along(kutuphane_safe)) {
    q_item <- kutuphane_safe[[i]]
    if (!is.list(q_item) || !.pk_meta_is_scalar_text(q_item$id)) next
    id <- trimws(q_item$id)
    meta <- birlesik[[id]] %||% list()

    hatalar <- c(hatalar, .pk_meta_validate_rls_columns(id, q_item$rls_columns))
    if (is.null(meta$result_schema) || !length(meta$result_schema)) {
      meta$schema_validation <- PK_META_SCHEMA_PENDING
      meta$tier <- meta$tier %||% 0L
    } else {
      hatalar <- c(hatalar, pk_meta_validate_schema_dependent(
        id, meta, meta$result_schema, q_item$rls_columns
      ))
      meta$schema_validation <- PK_META_SCHEMA_VALIDATED
    }

    kutuphane_safe[[i]]$meta <- meta
  }

  hatalar <- unique(hatalar[nzchar(hatalar)])
  if (length(hatalar)) {
    stop(
      sprintf(
        "[PK_META] Sorgu metadata sozlesmesi gecersiz (%d bulgu):\n  - %s",
        length(hatalar), paste(hatalar, collapse = "\n  - ")
      ),
      call. = FALSE
    )
  }

  kutuphane_safe
}
