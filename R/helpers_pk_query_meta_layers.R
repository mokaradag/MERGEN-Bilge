# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta_layers.R
# Açıklama: Sorgu metadata KATMANLARININ doğrulanması ve birleştirilmesi
#           (auto -> local -> curated).
#
#           `R/helpers_pk_query_meta.R` İÇİNDEN AYRILDI (bakım ratchet'i, 800
#           satır tavanı). Katman sınırı kendi başına bir sözleşmedir: mükerrer
#           kimlik/alan adları BİRLEŞTİRMEDEN ÖNCE yakalanmalıdır, çünkü
#           birleştirme `[[` ile ilk eşleşmeyi çözerek kanıtı yok eder.
#
#           Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı YOKTUR. Kaynak
#           manifesti bu dosyayı `helpers_pk_query_meta.R` dosyasından ÖNCE
#           yükler; doğrulama/iliştirme katmanı buradaki yardımcıları ÇAĞIRIR.
# ==============================================================================

# Tek bir metadata kaydındaki MÜKERRER alan adlarını raporlar.
.pk_meta_dup_field_names <- function(baglam, kayit) {
  if (!is.list(kayit) || !length(kayit)) return(character(0))
  adlar <- names(kayit)
  if (is.null(adlar) || length(adlar) != length(kayit)) return(character(0))
  adlar <- trimws(adlar)
  tekrar <- unique(adlar[duplicated(adlar) & nzchar(adlar) & !is.na(adlar)])
  if (!length(tekrar)) return(character(0))
  sprintf("%s icinde tekrar eden alan adi: %s", baglam, paste(sort(tekrar), collapse = ", "))
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

  # MÜKERRER ALAN ADI KATMAN BİRLEŞTİRMEDEN ÖNCE YAKALANIR.
  #
  # R listeleri aynı adı birden çok kez taşıyabilir; `.pk_meta_merge_one()`
  # içindeki `ustun[[alan]]` her zaman İLK eşleşmeyi çözer. Bu yüzden
  # `list(filterable = TRUE, filterable = FALSE)` birleşmede sessizce `TRUE`
  # olur ve ikinci beyan doğrulayıcıyı HİÇ görmez: açılış geçerli görünürken
  # anlam küratörün yazdığından farklıdır. Denetim BİRLEŞTİRMEDEN ÖNCE
  # yapılmalıdır, çünkü birleşme kanıtı yok eder.
  hatalar <- c(hatalar, unlist(lapply(adlar, function(id) {
    girdi <- layer[[id]]
    if (!is.list(girdi)) return(character(0))
    yerel <- .pk_meta_dup_field_names(sprintf("%s['%s']", name, id), girdi)
    sutunlar <- girdi$column_meta
    if (is.list(sutunlar) && length(sutunlar) && !is.null(names(sutunlar))) {
      for (sutun in names(sutunlar)) {
        if (is.na(sutun) || !nzchar(sutun)) next
        yerel <- c(yerel, .pk_meta_dup_field_names(
          sprintf("%s['%s'] column_meta['%s']", name, id, sutun), sutunlar[[sutun]]
        ))
      }
    }
    yerel
  }), use.names = FALSE))

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
