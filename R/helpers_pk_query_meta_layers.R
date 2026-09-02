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
# TAM ADLANDIRILMAMIŞ KAYIT SESSİZCE DÜŞMEZ.
#
# `.pk_meta_merge_one()` `names(ustun)` üzerinde döner: adsız bir kayıtta bu
# döngü HİÇ çalışmaz, kısmen adlandırılmışta ise boş adlar atlanır. Örneğin
# `list("project", filterable = TRUE)` katman doğrulamasından geçiyor, adsız öge
# birleştirme sırasında HATASIZ atılıyor ve küratörün yazdığı anlam kayboluyordu.
.pk_meta_dup_field_names <- function(baglam, kayit) {
  if (!is.list(kayit) || !length(kayit)) return(character(0))
  adlar <- names(kayit)
  if (is.null(adlar) || length(adlar) != length(kayit) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(sprintf("%s içindeki tüm alanlar adlandırılmış olmalıdır.", baglam))
  }
  adlar <- trimws(adlar)
  tekrar <- unique(adlar[duplicated(adlar) & nzchar(adlar) & !is.na(adlar)])
  if (!length(tekrar)) return(character(0))
  sprintf("%s içinde tekrar eden alan adı: %s", baglam, paste(sort(tekrar), collapse = ", "))
}

.pk_meta_validate_named_layer <- function(name, layer) {
  if (is.null(layer)) return(character(0))
  if (!is.list(layer)) return(sprintf("%s adlandırılmış liste olmalıdır.", name))
  if (!length(layer)) return(character(0))

  adlar <- names(layer)
  if (is.null(adlar) || length(adlar) != length(layer) ||
      any(is.na(adlar) | !nzchar(trimws(adlar)))) {
    return(sprintf("%s adlandırılmış liste olmalıdır.", name))
  }

  hatalar <- character(0)
  tekrar <- unique(adlar[duplicated(adlar)])
  if (length(tekrar)) {
    hatalar <- c(hatalar, sprintf(
      "%s içinde tekrar eden kimlik: %s", name, paste(tekrar, collapse = ", ")
    ))
  }

  liste_olmayan <- adlar[!vapply(layer, is.list, logical(1))]
  if (length(liste_olmayan)) {
    hatalar <- c(hatalar, sprintf(
      "%s içindeki her sorgu girdisi liste olmalıdır: %s",
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
    if (!is.null(sutunlar) && !is.list(sutunlar)) {
      yerel <- c(yerel, sprintf(
        "%s['%s'] column_meta adlandırılmış liste olmalıdır.", name, id
      ))
    } else if (is.list(sutunlar) && length(sutunlar)) {
      # `column_meta` GİRDİLERİ DE TAM ADLANDIRILMIŞ OLMALIDIR: adsız/kısmen
      # adlandırılmış girdiler doğrulamada atlanıyor ve birleştirmede sessizce
      # düşüyordu; sütun rolleri ve kısıtları kayboluyordu.
      sutun_adlari <- names(sutunlar)
      if (is.null(sutun_adlari) || length(sutun_adlari) != length(sutunlar) ||
          any(is.na(sutun_adlari) | !nzchar(trimws(sutun_adlari)))) {
        yerel <- c(yerel, sprintf(
          "%s['%s'] column_meta girdilerinin TAMAMI adlandırılmış olmalıdır.", name, id
        ))
      } else {
        # MÜKERRER SÜTUN ADI DA BİRLEŞTİRMEDEN ÖNCE YAKALANIR: `[[` yalnızca
        # İLK eşleşmeyi çözer ve ikinci beyan (ör. aynı sütun için farklı bir
        # `role`) sessizce düşerdi. Birleşme kanıtı yok ettiği için denetim
        # BURADA yapılmalıdır.
        tekrar_sutun <- unique(sutun_adlari[duplicated(trimws(sutun_adlari))])
        if (length(tekrar_sutun)) {
          yerel <- c(yerel, sprintf(
            "%s['%s'] column_meta içinde tekrar eden sütun adı: %s", name, id,
            paste(sort(tekrar_sutun), collapse = ", ")
          ))
        }
        for (sutun in sutun_adlari) {
          # SÜTUN GİRDİSİ DE LİSTE OLMALIDIR. `.pk_meta_dup_field_names()`
          # liste olmayan bir kayıt için `character(0)` döndürdüğü için
          # `column_meta = list(ProjeKodu = "dimension")` DOĞRULAMAYI GEÇİYOR,
          # `.pk_meta_merge_one()` skaleri birleşik metadata'ya kopyalıyor ve
          # `role`/`label`/`capability` okuyan tüketiciler o sütunun beyan
          # edilmiş anlamını HATASIZ biçimde KAYBEDİYORDU. Katman sözleşmesi
          # `column_meta`nın kendisi için bu kuralı zaten uygular.
          if (!is.list(sutunlar[[sutun]])) {
            yerel <- c(yerel, sprintf(
              "%s['%s'] column_meta['%s'] adlandırılmış liste olmalıdır.", name, id, sutun
            ))
            next
          }
          yerel <- c(yerel, .pk_meta_dup_field_names(
            sprintf("%s['%s'] column_meta['%s']", name, id, sutun), sutunlar[[sutun]]
          ))
        }
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
    # `[[` KARAKTER ALT SİMGESİ BOŞ/ADSIZ listede `NULL` DÖNDÜRMEZ, "subscript
    # out of bounds" FIRLATIR; üç katmanın da meşru bir BOŞ durumu vardır (boş
    # `pk_query_meta_auto` iskeleti, hiç yerel katman olmaması, boş curated).
    birlesik <- .pk_meta_merge_one(list(), .pk_meta_named_entry(auto, id))
    birlesik <- .pk_meta_merge_one(birlesik, .pk_meta_named_entry(local, id))
    birlesik <- .pk_meta_merge_one(birlesik, .pk_meta_named_entry(curated, id))
    out[[id]] <- birlesik
  }
  out
}
