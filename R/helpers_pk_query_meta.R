# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta.R
# Açıklama: Sorgu metadata KATMAN BİRLEŞTİRME (iskelet + üretilen + küre
#           edilmiş, küre edilmiş kazanır), yalnızca-alias yerel bindirmesi ve
#           başlangıç sözleşme doğrulaması. Master plan §5.1.
#
# Katman sırası ve sahiplik:
#   1) R/library_query_meta_auto.R   -> izlenen BOŞ iskelet (Tier-0 boot yolu)
#   2) R/library_query_meta_local.R  -> üretici çıktısı, gitignore'lu, VM'de
#   3) R/library_query_meta.R        -> insan küresyonu, izlenen, KAZANIR
#   4) R/library_query_aliases_local.R -> operatör alias'ları, gitignore'lu;
#      YALNIZCA `column_meta[[sutun]]$aliases` alanına dokunabilir.
#
# Bu ayrım zorunludur: üreticinin yeniden çalıştırılması insan küresyonunu ya
# da operatörün alias emeğini yok etmemelidir.
#
# Dosya SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur. Doğrulama sonucunda
# `stop()` etme kararı tek noktadadır: `pk_query_meta_attach()`.
# ==============================================================================

# Şema henüz yokken kaydedilen bekleyen kontrol etiketi.
PK_META_SCHEMA_PENDING <- "pending_no_schema"
PK_META_SCHEMA_VALIDATED <- "validated"

# Bir katmanı verilen ortamdan güvenle okur (izole testte ortam verilebilir).
.pk_meta_collect_layer <- function(name, envir, fallback = list()) {
  deger <- get0(name, envir = envir, inherits = TRUE, ifnotfound = NULL)
  if (is.null(deger) || !is.list(deger)) return(fallback)
  deger
}

# İki metadata listesini ALAN ALAN birleştirir; `ustun` kazanır.
#
# `utils::modifyList()` BİLİNÇLİ olarak kullanılmaz: adlara göre ÖZYİNELEMELİ
# birleştirir, bu yüzden üstün katmanda bilerek boşaltılmış bir liste alanı
# (`list()`) alttaki değeri sessizce korur ve adsız listeler düşer. Faz 0'da
# aynı tuzak (D9) hataya yol açmıştı.
.pk_meta_merge_one <- function(alt, ustun) {
  if (!is.list(alt)) alt <- list()
  if (!is.list(ustun)) ustun <- list()

  out <- alt

  for (alan in names(ustun)) {
    if (!nzchar(alan)) next

    ust_deger <- ustun[[alan]]
    alt_deger <- alt[[alan]]

    # column_meta sutun sutun, sonra alan alan birlestirilir.
    if (identical(alan, "column_meta") && is.list(ust_deger)) {
      birlesik <- if (is.list(alt_deger)) alt_deger else list()

      for (sutun in names(ust_deger)) {
        mevcut <- if (is.list(birlesik[[sutun]])) birlesik[[sutun]] else list()
        yeni <- if (is.list(ust_deger[[sutun]])) ust_deger[[sutun]] else list()

        for (calan in names(yeni)) {
          mevcut[[calan]] <- yeni[[calan]]
        }

        birlesik[[sutun]] <- mevcut
      }

      out[["column_meta"]] <- birlesik
      next
    }

    out[[alan]] <- ust_deger
  }

  out
}

#' Üç metadata katmanını birleştir (küre edilmiş kazanır)
pk_meta_merge_layers <- function(auto = list(), local = list(), curated = list()) {
  kimlikler <- unique(c(names(auto %||% list()), names(local %||% list()), names(curated %||% list())))
  kimlikler <- kimlikler[nzchar(kimlikler %||% "")]

  out <- list()

  for (id in kimlikler) {
    birlesik <- .pk_meta_merge_one(list(), auto[[id]])
    birlesik <- .pk_meta_merge_one(birlesik, local[[id]])
    birlesik <- .pk_meta_merge_one(birlesik, curated[[id]])
    out[[id]] <- birlesik
  }

  out
}

# Bir sütunun alias almasına izin var mı? Kod/kimlik sütunları varsayılan
# olarak alias ALMAZ; yalnızca küre edilmiş katmanda ayrıca gözden geçirilmiş
# `allow_aliases = TRUE` beyanı bunu açar (§5.1).
.pk_meta_alias_allowed <- function(cmeta) {
  if (!is.list(cmeta)) return(TRUE)
  if (isTRUE(cmeta$allow_aliases)) return(TRUE)

  if (identical(cmeta$role, "id")) return(FALSE)
  if (.pk_meta_is_scalar_text(cmeta$match) && identical(cmeta$match, "exact")) return(FALSE)

  TRUE
}

#' Yalnızca-alias yerel bindirmesini uygula
#'
#' Bindirme yetenek, grain, RLS, SQL ya da başka bir sözleşme alanını
#' DEĞİŞTİREMEZ; sadece `column_meta[[sutun]]$aliases` yazar.
#'
#' @return `list(meta = <birlesik metadata>, errors = <karakter>)`
pk_meta_apply_alias_overlay <- function(meta, overlay) {
  hatalar <- character(0)
  if (is.null(overlay) || !length(overlay)) return(list(meta = meta, errors = hatalar))

  if (!is.list(overlay)) {
    return(list(meta = meta, errors = "pk_query_aliases_local adlandirilmis liste olmalidir."))
  }

  for (id in names(overlay)) {
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

    for (sutun in names(sorgu_alias)) {
      cmeta <- meta[[id]]$column_meta[[sutun]]

      if (!is.list(cmeta)) {
        hatalar <- c(hatalar, sprintf(
          paste0(
            "[%s] alias bindirmesi beyan edilmemis '%s' sutununa yapiliyor. ",
            "Once metadata ureticisini calistirin ya da sutunu kure edin."
          ),
          id, sutun
        ))
        next
      }

      if (!.pk_meta_alias_allowed(cmeta)) {
        hatalar <- c(hatalar, sprintf(
          paste0(
            "[%s] column_meta['%s']: kod/kimlik sutunu alias alamaz. ",
            "Ayrica gozden gecirilmis allow_aliases=TRUE beyani gerekir."
          ),
          id, sutun
        ))
        next
      }

      katlama <- pk_meta_fold_alias_map(id, sutun, sorgu_alias[[sutun]])
      hatalar <- c(hatalar, katlama$errors)

      if (!length(katlama$errors)) {
        meta[[id]]$column_meta[[sutun]]$aliases <- katlama$aliases
        # Yerel bindirme kaynagi acikca isaretlenir; izlenen dosya denetimi
        # (audit) bu girdiyi Git'e sizmis saymaz.
        meta[[id]]$column_meta[[sutun]]$alias_provenance <- "local_overlay"
      }
    }
  }

  list(meta = meta, errors = hatalar)
}

#' Bir sorgunun metadata'sını doğrula (şemadan bağımsız, sütunlar arası dâhil)
pk_meta_validate_query <- function(query_id, meta, registry = NULL) {
  if (is.null(meta) || !length(meta)) return(character(0))

  if (!is.list(meta)) {
    return(.pk_meta_err(query_id, "metadata liste olmalidir."))
  }

  hatalar <- character(0)
  sutunlar <- meta$column_meta

  if (!is.null(sutunlar) && !is.list(sutunlar)) {
    return(.pk_meta_err(query_id, "column_meta liste olmalidir."))
  }

  if (is.list(sutunlar) && length(sutunlar)) {
    adlar <- names(sutunlar)
    if (is.null(adlar) || any(!nzchar(adlar))) {
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

  if (!is.null(meta$row_cap)) {
    tavan <- suppressWarnings(as.numeric(meta$row_cap[1]))
    if (length(tavan) != 1L || is.na(tavan) || tavan <= 0) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, "row_cap pozitif tam sayi olmalidir."))
    }
  }

  c(hatalar, .pk_meta_validate_query_refs(query_id, meta))
}

# Aynı yeteneği birden fazla sütun açığa çıkarıyorsa, açık ve deterministik
# bir varyant seçim kuralı ZORUNLUDUR; aksi hâlde kapı hangi sütunu kastettiğini
# bilemez ve planlanan/kalan işçilik gibi ayrımlar sessizce karışır.
.pk_meta_validate_capability_uniqueness <- function(query_id, meta) {
  sutunlar <- meta$column_meta
  eslesme <- list()

  for (sutun in names(sutunlar)) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$capability)) next
    cap <- trimws(cmeta$capability)
    eslesme[[cap]] <- c(eslesme[[cap]], sutun)
  }

  hatalar <- character(0)

  for (cap in names(eslesme)) {
    sahipler <- eslesme[[cap]]
    if (length(sahipler) < 2L) next

    tercih <- meta$capability_variants[[cap]]$prefer

    if (!.pk_meta_is_scalar_text(tercih) || !(tercih %in% sahipler)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        paste0(
          "capability '%s' ayni sorguda birden fazla sutunda: %s. ",
          "capability_variants[['%s']]$prefer ile deterministik varyant kurali beyan edin."
        ),
        cap, paste(sahipler, collapse = ", "), cap
      )))
    }
  }

  hatalar
}

# Sorgu içi sütun atıflarını doğrular (yalnızca column_meta beyan edilmişse;
# aksi hâlde bu kontrol şemaya bağlıdır ve ertelenir).
.pk_meta_validate_query_refs <- function(query_id, meta) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar)) return(character(0))

  beyan <- names(sutunlar)
  olculer <- beyan[vapply(
    sutunlar,
    function(cm) is.list(cm) && identical(cm$role, "measure"),
    logical(1)
  )]

  hatalar <- character(0)

  kontrol <- function(alan, degerler, izinli, etiket) {
    eksik <- setdiff(as.character(degerler %||% character(0)), izinli)
    eksik <- eksik[nzchar(eksik)]
    if (!length(eksik)) return(character(0))
    .pk_meta_err(query_id, sprintf(
      "%s beyan edilmemis %s: %s", alan, etiket, paste(eksik, collapse = ", ")
    ))
  }

  if (.pk_meta_is_scalar_text(meta$primary_entity)) {
    hatalar <- c(hatalar, kontrol("primary_entity", meta$primary_entity, beyan, "sutuna isaret ediyor"))
  }
  hatalar <- c(hatalar, kontrol("grain_columns", meta$grain_columns, beyan, "sutuna isaret ediyor"))
  hatalar <- c(hatalar, kontrol("default_group_by", meta$default_group_by, beyan, "sutuna isaret ediyor"))
  hatalar <- c(hatalar, kontrol("default_measures", meta$default_measures, olculer, "olcu sutununa isaret ediyor"))

  for (sutun in beyan) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta)) next

    if (identical(cmeta$aggregate, "weighted_mean")) {
      hatalar <- c(hatalar, kontrol(
        sprintf("column_meta['%s']$weight_by", sutun),
        cmeta$weight_by %||% NA_character_, olculer, "olcu sutununa isaret ediyor"
      ))
    }

    if (identical(cmeta$aggregate, "latest")) {
      if (!.pk_meta_is_scalar_text(cmeta$latest_by) ||
          !length(as.character(cmeta$latest_tie_by %||% character(0)))) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          "column_meta['%s']: aggregate='latest' icin latest_by ve latest_tie_by zorunludur.", sutun
        )))
      }
      hatalar <- c(hatalar, kontrol(
        sprintf("column_meta['%s']$latest_by", sutun), cmeta$latest_by %||% character(0),
        beyan, "sutuna isaret ediyor"
      ))
      hatalar <- c(hatalar, kontrol(
        sprintf("column_meta['%s']$latest_tie_by", sutun), cmeta$latest_tie_by %||% character(0),
        beyan, "sutuna isaret ediyor"
      ))
    }
  }

  hatalar
}

#' Şemaya BAĞLI doğrulama (yalnızca şema mevcutken)
#'
#' Şema yoksa doğrulama ertelenir ve `pending_no_schema` kaydedilir; bu asla
#' istek zamanı zorlamayı zayıflatmaz (bkz. `pk_meta_validate_actual_columns`).
pk_meta_validate_schema_dependent <- function(query_id, meta, schema, rls_columns = NULL) {
  if (is.null(schema) || !length(schema)) return(character(0))

  sema_sutunlari <- if (is.null(names(schema))) as.character(schema) else names(schema)
  sema_sutunlari <- sema_sutunlari[nzchar(sema_sutunlari)]

  hatalar <- character(0)

  eksik_meta <- setdiff(names(meta$column_meta %||% list()), sema_sutunlari)
  if (length(eksik_meta)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "column_meta sutunu semada yok: %s", paste(eksik_meta, collapse = ", ")
    )))
  }

  if (is.list(rls_columns)) {
    for (alan in names(rls_columns)) {
      deger <- rls_columns[[alan]]
      if (!.pk_meta_is_scalar_text(deger)) next
      if (!(trimws(deger) %in% sema_sutunlari)) {
        hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
          "rls_columns$%s = '%s' semada yok (D6 fail-open deligi).", alan, trimws(deger)
        )))
      }
    }
  }

  eksik_atif <- setdiff(.pk_meta_reference_columns(meta), sema_sutunlari)
  if (length(eksik_atif)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
      "metadata atifi semada yok: %s", paste(eksik_atif, collapse = ", ")
    )))
  }

  c(hatalar, .pk_meta_validate_schema_roles(query_id, meta, schema, sema_sutunlari))
}

# Beyan edilen rolün şemadaki yapısal tiple uyumunu kontrol eder. Bu kontrol
# YALNIZCA uyumsuzluğu reddeder; asla anlamsal yetenek ATAMAZ.
.pk_meta_validate_schema_roles <- function(query_id, meta, schema, sema_sutunlari) {
  if (is.null(names(schema))) return(character(0))

  hatalar <- character(0)

  for (sutun in intersect(names(meta$column_meta %||% list()), sema_sutunlari)) {
    cmeta <- meta$column_meta[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$role)) next

    yapisal <- .pk_meta_role_from_class(schema[[sutun]])

    if (identical(cmeta$role, "date") && !identical(yapisal, "date")) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "column_meta['%s']: role='date' ama semadaki tip '%s'.", sutun, as.character(schema[[sutun]])[1]
      )))
    }

    if (identical(cmeta$role, "measure") && !identical(yapisal, "measure")) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, sprintf(
        "column_meta['%s']: role='measure' ama semadaki tip '%s' sayisal degil.",
        sutun, as.character(schema[[sutun]])[1]
      )))
    }
  }

  hatalar
}

#' İzlenen (tracked) alias denetimi
#'
#' Git'te izlenen küre edilmiş katmandaki her alias haritası açık bir köken
#' etiketi taşımalıdır. Üretimden türetilmiş kanonik hedefler yalnızca
#' gitignore'lu yerel alias dosyasına yazılır; izlenen dosyaya sızmış bir
#' alias, tek bir `git add -A` ile kurumsal ad yayınlanması demektir.
#'
#' @return Onaysız alias taşıyan `"<sorgu>/<sutun>"` kayıtları.
pk_meta_tracked_alias_audit <- function(curated) {
  if (!is.list(curated) || !length(curated)) return(character(0))

  out <- character(0)

  for (id in names(curated)) {
    sutunlar <- curated[[id]]$column_meta
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

  out
}

#' Metadata sözleşmesini birleştir, doğrula ve sorgu kütüphanesine iliştir
#'
#' Başlangıç girişi budur ve `stop()` etme kararını veren TEK yerdir.
#' Şemadan bağımsız her geçersiz sözleşme başlangıcı düşürür; şemaya bağlı
#' kontroller şema yoksa `pending_no_schema` olarak kaydedilir ve sorgu
#' belgelenmiş Tier-0 yapısal yolundan boot eder.
pk_query_meta_attach <- function(query_library,
                                 auto = NULL,
                                 local = NULL,
                                 curated = NULL,
                                 aliases = NULL,
                                 registry = NULL,
                                 envir = globalenv()) {
  auto     <- auto     %||% .pk_meta_collect_layer("pk_query_meta_auto", envir)
  local    <- local    %||% .pk_meta_collect_layer("pk_query_meta_local", envir)
  curated  <- curated  %||% .pk_meta_collect_layer("pk_query_meta", envir)
  aliases  <- aliases  %||% .pk_meta_collect_layer("pk_query_aliases_local", envir)
  registry <- registry %||% .pk_meta_collect_layer("pk_capability_registry", envir)

  hatalar <- pk_meta_validate_capability_registry(registry)

  onaysiz <- pk_meta_tracked_alias_audit(curated)
  if (length(onaysiz)) {
    hatalar <- c(hatalar, sprintf(
      paste0(
        "Izlenen R/library_query_meta.R icinde onay etiketi olmayan alias: %s. ",
        "Uretimden turetilmis kanonik hedefler yalnizca gitignore'lu ",
        "R/library_query_aliases_local.R icine yazilir."
      ),
      paste(onaysiz, collapse = ", ")
    ))
  }

  birlesik <- pk_meta_merge_layers(auto = auto, local = local, curated = curated)

  bindirme <- pk_meta_apply_alias_overlay(birlesik, aliases)
  birlesik <- bindirme$meta
  hatalar <- c(hatalar, bindirme$errors)

  for (i in seq_along(query_library)) {
    q_item <- query_library[[i]]
    id <- as.character(q_item$id %||% "")[1]
    if (!nzchar(id)) next

    meta <- birlesik[[id]] %||% list()
    hatalar <- c(hatalar, pk_meta_validate_query(id, meta, registry))

    sema <- meta$result_schema
    if (is.null(sema) || !length(sema)) {
      meta$schema_validation <- PK_META_SCHEMA_PENDING
      # Sema yoksa sutun bilgisi Tier-0'da yapisal olarak uretilir; anlamsal
      # yetenek ATANMAZ, bu yuzden anlamsal gereksinimli istekler kapida durur.
      meta$tier <- meta$tier %||% 0L
    } else {
      hatalar <- c(hatalar, pk_meta_validate_schema_dependent(id, meta, sema, q_item$rls_columns))
      meta$schema_validation <- PK_META_SCHEMA_VALIDATED
    }

    query_library[[i]]$meta <- meta
  }

  if (length(hatalar)) {
    stop(
      sprintf(
        "[PK_META] Sorgu metadata sozlesmesi gecersiz (%d bulgu):\n  - %s",
        length(hatalar), paste(hatalar, collapse = "\n  - ")
      ),
      call. = FALSE
    )
  }

  query_library
}
