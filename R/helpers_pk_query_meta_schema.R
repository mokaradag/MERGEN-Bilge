# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta_schema.R
# Açıklama: Sorgu metadata sözleşmesinin SÖZLÜĞÜ ve ŞEMADAN BAĞIMSIZ
#           doğrulayıcıları. Master plan §5.1.
#
# Sözleşme:
#   * Bu dosya SAFTIR: Shiny/reactive/DB/ağ/dosya bağımlılığı yoktur.
#   * Doğrulayıcılar `stop()` ETMEZ; hata METİNLERİNDEN oluşan bir karakter
#     vektörü döner. Başlangıçta durdurma kararını tek bir yerde
#     (`pk_query_meta_attach()`) veren taraf verir; böylece aynı kurallar
#     testlerde ve üretici (generator) sağlık raporunda da çalıştırılabilir.
#   * Buradaki kontroller ŞEMADAN BAĞIMSIZDIR: sorgu çalıştırılmadan, yalnızca
#     metadata'nın kendi iç tutarlılığına bakarak yapılabilenlerdir. Gerçek
#     sonuç sütunlarına bakan kontroller şemaya bağlıdır ve
#     R/helpers_pk_query_meta_access.R içindedir.
# ==============================================================================

# Sütun rolleri. `role` özetlemeyi sürükler: `measure` toplanabilir mi diye
# sorulur, `date` zaman penceresi kurar, `dimension` gruplama/filtre adayıdır,
# `id` asla bulanık eşleşmez.
PK_META_ROLES <- c("id", "dimension", "measure", "date")

# Yetenek kaydında yalnızca ANLAMSAL roller bulunur; `id` bir yetenek değildir.
PK_META_CAPABILITY_ROLES <- c("dimension", "measure", "date")

# Toplama kipleri. `weighted_mean` ortalamaların ortalamasını engeller;
# `latest` sıralama sütunu ve kararlı eşitlik bozucu olmadan çalıştırılamaz.
PK_META_AGGREGATES <- c("sum", "mean", "weighted_mean", "latest", "none")

# Eşleşme kipleri. Kod/sicil sütunları `exact` kalmalı ve ASLA bulanık
# eşleştirilmemelidir.
PK_META_MATCH_MODES <- c("exact", "resolve", "contains", "none")

# Yüzde ölçeği. `unit = "%"` olan her ölçüde ZORUNLUDUR: aksi hâlde Excel'in
# `0.0%` biçimi 61.3 değerini %6130,0 yapar (§5.9).
PK_META_PERCENT_SCALES <- c("points", "fraction")

# İzlenen (tracked) dosyadaki alias haritaları için kabul edilen köken
# etiketleri. Üretimden türetilmiş kanonik hedefler Git'e giremez.
PK_META_ALIAS_PROVENANCE <- c("synthetic", "approved")

# Kararlı yetenek kimliği deseni: ASCII, küçük harf, noktayla ayrılmış.
.PK_META_CAPABILITY_PATTERN <- "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"

# --- KÜÇÜK ORTAK YARDIMCILAR ---------------------------------------------------

# Tek elemanlı, boş olmayan karakter değeri mi?
.pk_meta_is_scalar_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

# Tek elemanlı, NA olmayan mantıksal değer mi?
.pk_meta_is_scalar_flag <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

# Hata metinlerini tek biçimde üretir; mesajlar Türkçe ve ASCII tanımlayıcılıdır.
.pk_meta_err <- function(query_id, ...) {
  sprintf("[%s] %s", as.character(query_id)[1], paste0(...))
}

#' Yetenek kaydını doğrula
#'
#' @return Hata metinleri (boşsa kayıt geçerlidir).
pk_meta_validate_capability_registry <- function(registry) {
  if (is.null(registry)) return(character(0))

  if (!is.list(registry)) {
    return("pk_capability_registry bir liste olmalidir.")
  }

  adlar <- names(registry)
  if (is.null(adlar) || any(!nzchar(adlar))) {
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

    if (!.pk_meta_is_scalar_text(girdi$role) ||
        !(girdi$role %in% PK_META_CAPABILITY_ROLES)) {
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

    # Boyut ve tarih yeteneklerinin birimi olmaz.
    if (identical(girdi$role, "dimension") || identical(girdi$role, "date")) {
      if (!is.null(girdi$unit)) {
        hatalar <- c(hatalar, sprintf(
          "pk_capability_registry['%s']: %s rolunde unit tanimlanamaz.", cap, girdi$role
        ))
      }
    }
  }

  hatalar
}

#' Tek bir sütun metadata'sını doğrula (şemadan bağımsız)
pk_meta_validate_column <- function(query_id, column, cmeta, registry = NULL) {
  onek <- sprintf("column_meta['%s']:", column)

  if (!is.list(cmeta)) {
    return(.pk_meta_err(query_id, onek, " liste olmalidir."))
  }

  hatalar <- character(0)

  if (!.pk_meta_is_scalar_text(cmeta$role) || !(cmeta$role %in% PK_META_ROLES)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz role (izinli: %s).", paste(PK_META_ROLES, collapse = "/")
    )))
    # Rol bilinmeden role bagli kontroller anlamsizdir.
    return(hatalar)
  }

  if (!is.null(cmeta$match) &&
      (!.pk_meta_is_scalar_text(cmeta$match) || !(cmeta$match %in% PK_META_MATCH_MODES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz match (izinli: %s).", paste(PK_META_MATCH_MODES, collapse = "/")
    )))
  }

  # Kod/kimlik sutunlari bulanik eslestirilemez.
  if (identical(cmeta$role, "id") &&
      .pk_meta_is_scalar_text(cmeta$match) &&
      cmeta$match %in% c("resolve", "contains")) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek,
      " role='id' sutununda bulanik match kullanilamaz (exact/none olmalidir)."))
  }

  if (!is.null(cmeta$aggregate) &&
      (!.pk_meta_is_scalar_text(cmeta$aggregate) ||
       !(cmeta$aggregate %in% PK_META_AGGREGATES))) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
      " gecersiz aggregate (izinli: %s).", paste(PK_META_AGGREGATES, collapse = "/")
    )))
  }

  if (!is.null(cmeta$additive) && !.pk_meta_is_scalar_flag(cmeta$additive)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, " additive tek TRUE/FALSE olmalidir."))
  }

  if (!is.null(cmeta$filterable) && !.pk_meta_is_scalar_flag(cmeta$filterable)) {
    hatalar <- c(hatalar, .pk_meta_err(query_id, onek, " filterable tek TRUE/FALSE olmalidir."))
  }

  if (!is.null(cmeta$decimals)) {
    ondalik <- suppressWarnings(as.numeric(cmeta$decimals[1]))
    if (length(ondalik) != 1L || is.na(ondalik) || ondalik < 0) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, " decimals negatif olmayan sayi olmalidir."))
    }
  }

  # Yuzde olcegi: unit = "%" oldugunda ZORUNLU.
  if (.pk_meta_is_scalar_text(cmeta$unit) && identical(trimws(cmeta$unit), "%")) {
    if (!.pk_meta_is_scalar_text(cmeta$percent_scale) ||
        !(cmeta$percent_scale %in% PK_META_PERCENT_SCALES)) {
      hatalar <- c(hatalar, .pk_meta_err(query_id, onek, sprintf(
        " unit='%%' iken percent_scale zorunludur (izinli: %s).",
        paste(PK_META_PERCENT_SCALES, collapse = "/")
      )))
    }
  }

  c(hatalar, .pk_meta_validate_column_capability(query_id, onek, cmeta, registry))
}

# Sütunun yetenek kimliğini kayda karşı doğrular (rol ve birim tutarlılığı).
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

  hatalar
}

#' Alias haritasını katla ve doğrula
#'
#' Alias haritası ADLANDIRILMIŞ KARAKTER VEKTÖRÜDÜR: ad = kullanıcıya görünen
#' alias, değer = o sütunun kapalı sözlüğündeki kanonik değer. Anahtarlar
#' `pk_tr_fold()` ile normalleştirilir. Aynı normalleştirilmiş alias'ın FARKLI
#' kanonik değerlere işaret etmesi sert sözleşme hatasıdır; "son yazan kazanır"
#' davranışı YOKTUR.
#'
#' @return `list(aliases = <katlanmis adli vektor>, errors = <karakter>)`
pk_meta_fold_alias_map <- function(query_id, column, aliases) {
  bos <- structure(character(0), names = character(0))
  if (is.null(aliases) || length(aliases) == 0L) {
    return(list(aliases = bos, errors = character(0)))
  }

  onek <- sprintf("column_meta['%s']$aliases:", column)

  if (!is.character(aliases) || is.null(names(aliases))) {
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

  # Ayni alias -> ayni deger tekrari zararsizdir; farkli deger sert hatadir.
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

  list(aliases = sonuc, errors = hatalar)
}
