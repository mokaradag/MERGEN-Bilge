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

# İşleyicilerin (pk_fmt_number / .pk_export_number_format) desteklediği AZAMİ
# ondalık hassasiyet. Metadata bundan fazlasını BEYAN EDEMEZ; aksi hâlde
# doğrulanmış bir sorgu, çıktısında sessizce daha az hassasiyet yayımlar.
PK_META_MAX_DECIMALS <- 9L
.PK_META_CAPABILITY_PATTERN <- "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"

#' Metadata alanını TAM ADLA okur (kısmi eşleşme YOK)
#'
#' `x$ad` R'de `x[[ad, exact = FALSE]]` ile eşdeğerdir ve KISMİ EŞLEŞME yapar.
#' Metadata izin listesi ÖNEK ÇAKIŞAN adlar içerir (`grain` / `grain_columns`,
#' `entity` / `entity_kind` / `entity_kinds`), bu yüzden yalnızca UZUN adı
#' bildiren bir kayıtta `meta$grain` sessizce `grain_columns` değerini,
#' `cmeta$entity` ise `entity_kinds` değerini döndürüyordu: geçerli küratör
#' metadata'sı yanlış bir başlangıç bulgusu ya da yanlış bir çalışma zamanı
#' değeri üretiyordu.
#'
#' Adsız listede `[[` "subscript out of bounds" fırlattığı için ad denetimi
#' burada yapılır ve yokluk `NULL` ile bildirilir.
.pk_meta_field <- function(x, name) {
  if (!is.list(x) || !length(x)) return(NULL)
  adlar <- names(x)
  if (is.null(adlar)) return(NULL)
  i <- match(as.character(name)[1], adlar)
  if (is.na(i)) return(NULL)
  x[[i]]
}

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
  if (!is.list(registry)) return("pk_capability_registry bir liste olmalıdır.")

  # BOŞ kayıt MEŞRU bir durumdur: hiçbir yetenek henüz küre edilmemiştir.
  # `names(list())` NULL döndüğü için bu erken çıkış olmadan aşağıdaki
  # "adlandırılmış olmalıdır" kontrolü boş kaydı HATA sayar ve başlangıcı
  # düşürür. Kardeş doğrulayıcılar (.pk_meta_validate_named_layer,
  # .pk_meta_validate_rls_columns) da boş girdiyi aynı şekilde kabul eder;
  # bu erken çıkışı kaldırmak o sözleşmeyi bozar.
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

# ------------------------------------------------------------------------------
# ALAN ADI SÖZLEŞMESİ (kapalı başarısız)
# ------------------------------------------------------------------------------
#
# Doğrulayıcılar yalnızca OKUDUKLARI alanları denetliyor, BEKLENMEYEN bir üst
# düzey anahtarı hiç reddetmiyordu. Katmanlar doğrulamadan ÖNCE birleştiği için
# küratörlü bindirmedeki bir yazım hatası (`filterble = FALSE`, `entitiy =
# "project"`) kullanılmayan bir alan olarak KALIYOR, alttaki katmanın
# `filterable`/`entity` değeri (ya da yokluğu) yürürlükte kalıyordu: açılış
# başarılı oluyor ama anlam küratörün yazdığından FARKLI oluyordu.
#
# Ayrıca R listeleri MÜKERRER ada sahip olabilir. `.pk_meta_merge_one()` içinde
# `yeni[[ad]]` her zaman İLK eşleşmeyi çözer, yani
# `list(filterable = TRUE, filterable = FALSE)` birleşmede `TRUE` olur ve ikinci
# beyan doğrulayıcıyı hiç görmez. Mükerrer ad bu yüzden BİRLEŞTİRMEDEN ÖNCE
# hatadır.
.pk_meta_validate_field_names <- function(query_id, onek, kayit, izinli) {
  if (!is.list(kayit) || !length(kayit)) return(character(0))

  adlar <- names(kayit)
  if (is.null(adlar) || length(adlar) != length(kayit) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(.pk_meta_err(query_id, onek, " tüm alanlar adlandırılmış olmalıdır."))
  }

  adlar <- trimws(adlar)
  hatalar <- character(0)

  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " tekrar eden alan adı: %s", paste(sort(tekrar), collapse = ", ")
    )))
  }

  bilinmeyen <- setdiff(unique(adlar), izinli)
  if (length(bilinmeyen)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " bilinmeyen alan: %s", paste(sort(bilinmeyen), collapse = ", ")
    )))
  }

  hatalar
}

# Sütun metadatasında izin verilen alanlar. Üreticiye ait/dahili alanlar da
# AÇIKÇA listelenir; aksi hâlde üretilen katman kendi çıktısıyla düşerdi.
PK_META_COLUMN_FIELDS <- c(
  "role", "label", "capability", "match", "match_mode", "filterable",
  "high_cardinality", "tier", "unit", "decimals", "percent_scale",
  "additive", "aggregate", "weight_by", "latest_by", "latest_tie_by",
  "domain", "entity", "entity_kind", "entity_kinds",
  "aliases", "allow_aliases", "alias_provenance",
  # Üretici/gözlem alanları (yalnızca üretilen katmanda görülür).
  "inferred_from", "source_type", "observed", "high_cardinality_proved"
)

pk_meta_validate_column <- function(query_id, column, cmeta, registry = NULL) {
  onek <- sprintf("column_meta['%s']:", column)
  if (!is.list(cmeta)) return(.pk_meta_err(query_id, onek, " liste olmalidir."))

  hatalar <- .pk_meta_validate_field_names(query_id, onek, cmeta, PK_META_COLUMN_FIELDS)
  if (!.pk_meta_is_scalar_text(cmeta$role) || !(cmeta$role %in% PK_META_ROLES)) {
    return(c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz role (izinli: %s).", paste(PK_META_ROLES, collapse = "/")
    ))))
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

  # `match_mode` KABUL EDİLEN AMA OKUNMAYAN BİR ALAN OLARAK KALAMAZ.
  #
  # Ad `PK_META_COLUMN_FIELDS` içinde izinli olduğu için bilinmeyen-alan
  # koruması susuyor, hiçbir doğrulayıcı değerini denetlemiyor ve
  # `pk_meta_match_mode()` de okumuyordu: `match_mode = "resolve"` yazan bir
  # küratör başlangıç doğrulamasını geçiyor ama varlık çözümlemesi SESSİZCE
  # `"none"` kalıyordu. Alan artık `match` takma adı olarak OKUNUR (bkz.
  # `pk_meta_match_mode()`) ve AYNI kümeye karşı doğrulanır.
  if (!is.null(cmeta$match_mode) &&
      (!.pk_meta_is_scalar_text(cmeta$match_mode) ||
       !(cmeta$match_mode %in% PK_META_MATCH_MODES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz match_mode (izinli: %s).", paste(PK_META_MATCH_MODES, collapse = "/")
    )))
  }
  if (!is.null(cmeta$match) && !is.null(cmeta$match_mode) &&
      !identical(as.character(cmeta$match)[1], as.character(cmeta$match_mode)[1])) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " match ve match_mode birlikte verildiginde AYNI degeri tasimalidir."))
  }

  .etkin_match <- if (.pk_meta_is_scalar_text(cmeta$match)) {
    cmeta$match
  } else if (.pk_meta_is_scalar_text(cmeta$match_mode)) {
    cmeta$match_mode
  } else {
    NULL
  }

  if (!is.null(.etkin_match) && .etkin_match %in% c("resolve", "contains") &&
      !identical(cmeta$role, "dimension")) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " role='%s' sutununda bulanik match kullanilamaz; resolve/contains yalnizca dimension icindir.",
      cmeta$role
    )))
  }

  # TAM AD OKUMASI: `cmeta$entity` yalnızca `entity_kinds` bildiren bir sütunda
  # o değeri KISMİ EŞLEŞMEYLE döndürüp geçerli metadata'yı `entity` beyanı
  # sayıyor ve sütunu haksız yere reddediyordu.
  cmeta_entity <- .pk_meta_field(cmeta, "entity")
  if (!is.null(cmeta_entity) && !(cmeta$role %in% c("id", "dimension"))) {
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
      " tier negatif olmayan tam sayı olmalıdır."))
  }

  # `decimals` DOĞRULAMASI, İŞLEYİCİLERİN GERÇEKTEN desteklediği hassasiyetle
  # SINIRLIDIR. `pk_fmt_number()` ve `.pk_export_number_format()` değeri
  # SESSİZCE 9'a kırpar; doğrulayıcı 10-15 arası bir beyanı kabul ederse sorgu
  # "doğrulanmış" görünür ama çıktısı beyandan DAHA AZ hassastır. Sözleşme ile
  # işleyici arasındaki bu sessiz uyuşmazlık KAPATILIR.
  if (!is.null(cmeta$decimals) &&
      !.pk_meta_is_whole_number(cmeta$decimals, min = 0, max = PK_META_MAX_DECIMALS)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " decimals 0 ile %d arasında tam sayı olmalıdır (işleyici sınırı).",
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
    # `latest` DE ÖLÇÜYE ÖZGÜDÜR.
    #
    # Denetim `sum`/`mean`/`weighted_mean` değerlerini reddediyor ama
    # `aggregate = "latest"` geçiyordu; üstelik bu beyan sonraki
    # `latest_by`/`latest_tie_by` referans denetimlerini de sağlayabildiği için
    # metadata GEÇERLİ görünüyordu. Oysa `pk_meta_aggregate_for()` ölçü
    # olmayan her rol için hemen `"none"` döner ve `pk_latest_fact()` sayısal
    # ölçü olgu yoludur: küratörün yazdığı `latest` SESSİZCE yok sayılırdı.
    if (.pk_meta_is_scalar_text(cmeta$aggregate) &&
        cmeta$aggregate %in% c("sum", "mean", "weighted_mean", "latest")) {
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
        (identical(cmeta$role, "id") ||
         identical(as.character(cmeta$match %||% cmeta$match_mode %||% "")[1], "exact"))) {
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
  # BOŞ yetenek kaydında `registry[[cap]]` "subscript out of bounds" FIRLATIR;
  # `bilinmeyen capability` bulgusu üretilemeden boot opak hatayla düşerdi.
  kayit_girisi <- .pk_meta_named_entry(registry, cap)
  if (!is.list(registry) || is.null(kayit_girisi)) {
    return(.pk_meta_err(query_id, onek, sprintf(
      " bilinmeyen capability '%s' (pk_capability_registry icinde tanimli degil).", cap
    )))
  }

  kayit <- kayit_girisi
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
