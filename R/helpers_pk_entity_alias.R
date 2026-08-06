# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_alias.R
# Açıklama: Faz 4 — onaylı alias kayıt defteri indeksi (master plan §5.4,
#           Katman 2). R/helpers_pk_entity_score.R içinden AYRILDI; alias
#           çözümlemesi kendi başına bir doğrulama/çakışma sorunudur.
#
#           KAYIT DEFTERİ SÖZLEŞMESİ (Faz 3a): anahtarlar YALNIZCA
#           `pk_tr_fold()` ile normalleştirilir; hedefler `trimws(enc2utf8())`
#           biçimindedir. Bu dosya AYNI anahtarı kullanır — normalleştirme
#           hattının kayıplı `fold` anahtarını DEĞİL. Aksi hâlde kayıtta
#           `eh/se` duran onaylı bir alias, yazılan `EH/SE` (kayıplı anahtarda
#           `eh se`) ile eşleşmez ve alias katmanı sessizce atlanır.
#
#           ÜÇ AYRI KAPALI BAŞARISIZLIK:
#             1) Aynı katlanmış anahtarın FARKLI kanonik hedeflere işaret
#                etmesi yapılandırma hatasıdır; `match()` ile ilki sessizce
#                seçilmez.
#             2) ASCII yedek anahtarı birden çok kanonik hedefe çökerse
#                netleştirme gerekir; rastgele biri seçilmez.
#             3) Onaylı bir alias'ın hedefi kapalı sözlükte YOKSA bu bir
#                veri/yapılandırma tutarsızlığıdır ve ilgisiz bulanık
#                adaylarla devam edilmez.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

#' Alias kayıt defterinden aranabilir indeks üret
#'
#' @param aliases `pk_meta_fold_alias_map()` çıktısı: adları KATLANMIŞ alias
#'   anahtarı, değerleri kanonik hedef olan adlandırılmış karakter vektörü.
#' @return `list(valid, errors, fold, ascii, targets)`.
#'   `fold`  : katlanmış anahtar -> kanonik hedef (tekil).
#'   `ascii` : ASCII yedek anahtar -> kanonik hedef(ler) listesi.
pk_entity_alias_index <- function(aliases) {
  bos <- list(
    valid = TRUE, errors = character(0),
    fold = structure(character(0), names = character(0)),
    ascii = list(),
    targets = character(0)
  )

  if (is.null(aliases) || !length(aliases)) return(bos)

  adlar <- names(aliases)
  if (is.null(adlar) || length(adlar) != length(aliases)) {
    bos$valid <- FALSE
    bos$errors <- "Alias kaydı adlandırılmış karakter vektörü olmalıdır."
    return(bos)
  }

  anahtar <- pk_tr_fold(adlar)
  hedef <- trimws(enc2utf8(as.character(aliases)))

  tut <- !is.na(anahtar) & nzchar(anahtar) & !is.na(hedef) & nzchar(hedef)
  anahtar <- anahtar[tut]
  hedef <- hedef[tut]

  if (!length(anahtar)) return(bos)

  hatalar <- character(0)

  # (1) Aynı katlanmış anahtar / farklı hedef -> yapılandırma hatası.
  benzersiz <- unique(anahtar)
  tekil_hedef <- character(0)
  for (a in benzersiz) {
    degerler <- unique(hedef[anahtar == a])
    if (length(degerler) > 1L) {
      hatalar <- c(hatalar, sprintf(
        "'%s' alias anahtarı birden fazla kanonik değere işaret ediyor: %s",
        a, paste(degerler, collapse = " | ")
      ))
      next
    }
    tekil_hedef[[a]] <- degerler[1]
  }

  ascii_anahtar <- pk_entity_ascii_key(names(tekil_hedef))
  ascii_index <- list()
  for (i in seq_along(tekil_hedef)) {
    ak <- ascii_anahtar[i]
    if (is.na(ak) || !nzchar(ak)) next
    ascii_index[[ak]] <- unique(c(ascii_index[[ak]], unname(tekil_hedef[i])))
  }

  list(
    valid = !length(hatalar),
    errors = hatalar,
    fold = tekil_hedef,
    ascii = ascii_index,
    targets = unname(tekil_hedef)
  )
}

#' Kullanıcı ifadesi için alias hedefini çöz
#'
#' Sıra: kesin katlanmış anahtar -> kayıplı (noktalama sadeleştirilmiş) anahtar
#' -> ASCII yedek anahtarı. Son iki yol KAYIPLIDIR ve `lossy = TRUE` ile
#' işaretlenir; çakışma hâlinde `ambiguous = TRUE` döner ve çağıran taraf
#' netleştirme ister.
#'
#' @param index `pk_entity_alias_index()` çıktısı.
#' @param user_norm `pk_entity_normalize()` çıktısı.
pk_entity_alias_lookup <- function(index, user_norm) {
  bos <- list(target = NULL, targets = character(0), lossy = FALSE,
              ambiguous = FALSE)

  if (is.null(index) || !length(index$fold)) return(bos)
  if (is.null(user_norm) || isTRUE(user_norm$blank)) return(bos)

  anahtarlar <- names(index$fold)

  # 1) Kayıt defterinin KENDİ anahtarı (kayıplı olmayan).
  idx <- match(user_norm$fold_only, anahtarlar)
  if (!is.na(idx)) {
    return(list(target = unname(index$fold[idx]), targets = unname(index$fold[idx]),
                lossy = FALSE, ambiguous = FALSE))
  }

  # 2) Noktalama sadeleştirilmiş anahtar (kayıplı).
  idx <- match(user_norm$fold, anahtarlar)
  if (!is.na(idx)) {
    return(list(target = unname(index$fold[idx]), targets = unname(index$fold[idx]),
                lossy = TRUE, ambiguous = FALSE))
  }

  # 3) ASCII yedek anahtarı (kayıplı). Kullanıcı Türkçe harf yazmadıysa
  #    onaylı `ŞAHİN -> ...` alias'ı `sahin` yazımıyla da bulunmalıdır.
  ascii_anahtar <- pk_entity_ascii_key(user_norm$fold_only)
  hedefler <- index$ascii[[ascii_anahtar]]
  if (is.null(hedefler) || !length(hedefler)) {
    hedefler <- index$ascii[[user_norm$ascii]]
  }
  if (is.null(hedefler) || !length(hedefler)) return(bos)

  if (length(hedefler) > 1L) {
    return(list(target = NULL, targets = hedefler, lossy = TRUE, ambiguous = TRUE))
  }

  list(target = hedefler[1], targets = hedefler, lossy = TRUE, ambiguous = FALSE)
}
