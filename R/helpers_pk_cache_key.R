# ==============================================================================
# Dosya Yolu: R/helpers_pk_cache_key.R
# Açıklama: Faz 6 (§5.10) — PK sonuç önbelleğinin ANAHTAR ÜRETİMİ ve YETKİ
#           KAPSAMI İMZASI.
#
# `R/helpers_pk_cache.R` içinden BÖLÜNMÜŞTÜR: orası DEPO/tahliye/muhasebe
# katmanıdır ve 24-fonksiyon bakım tavanına dayanmıştı. Anahtar üretimi ayrı
# ve GÜVENLİK-KRİTİK bir sorumluluktur: bir kullanıcının RLS öncesi çerçevesi
# farklı yetki kapsamına sahip başka bir kullanıcıya ASLA yeniden
# kullandırılmamalıdır.
#
# SAFTIR: depo durumu OKUMAZ/YAZMAZ; yalnızca girdiden kararlı metin üretir.
# Manifest sırası ZORUNLUDUR: bu dosya `helpers_pk_cache.R`'den ÖNCE yüklenir.
# ==============================================================================

.pk_cache_scalar <- function(x, default = "") {
  ham <- tryCatch(as.character(x)[1], error = function(e) NA_character_)
  if (is.null(ham) || length(ham) == 0L || is.na(ham)) return(default)
  ham
}

#' Önbellek anahtarı üret
#'
#' Sonucu etkileyebilen HER boyut anahtara girer. `rls_signature` yetki
#' kapsamının kararlı özetidir; onu dışarıda bırakmak kullanıcılar arası
#' sızıntı demektir. `query_version` ise sorgu tanımı/SQL değiştiğinde
#' deterministik geçersizleştirme sağlar.
#'
#' @return Tek elemanlı karakter anahtar.
pk_cache_key <- function(query_id, rls_signature, filter_signature,
                         query_version = "", engine = "", extra = NULL) {
  parcalar <- c(
    paste0("q=", .pk_cache_scalar(query_id, "?")),
    paste0("v=", .pk_cache_scalar(query_version)),
    paste0("e=", .pk_cache_scalar(engine)),
    # Yetki kapsamı: ASLA çıkarılmaz.
    paste0("r=", .pk_cache_scalar(rls_signature, "__no_scope__")),
    paste0("f=", .pk_cache_scalar(filter_signature))
  )

  if (!is.null(extra) && length(extra) > 0L) {
    adlar <- names(extra)
    if (is.null(adlar)) adlar <- paste0("x", seq_along(extra))
    sira <- order(adlar, method = "radix")
    for (i in sira) {
      parcalar <- c(parcalar, paste0(adlar[i], "=", .pk_cache_scalar(extra[[i]])))
    }
  }

  paste(parcalar, collapse = "|")
}

#' Yetki kapsamı imzası (RLS bilgisinden kararlı özet)
#'
#' Anahtara ham yetki listesi gömmek yerine kararlı bir özet kullanılır; imza
#' hem kısa hem de kapsam değiştiğinde kesin olarak değişir. Kullanıcı adı
#' TEK BAŞINA yeterli değildir: aynı kullanıcının yetkisi DB'de değişebilir.
pk_cache_rls_signature <- function(rls_info) {
  if (!is.list(rls_info)) return("__no_scope__")
  if (!isTRUE(rls_info$authorized)) return("__unauthorized__")

  alanlar <- setdiff(names(rls_info), c("conn", "connection", "session"))
  alanlar <- sort(alanlar, method = "radix")

  # KANONİK, UZUNLUK ÖN EKLİ serileştirme. Alanları `,`/`;`/`=` ile düz metne
  # birleştirmek AYIRT EDİCİ DEĞİLDİR: `c("a,b", "c")` ile `c("a", "b,c")`
  # AYNI ham metni üretir ve en güçlü karma bile iki FARKLI yetki kapsamını
  # ayıramaz — yani önbellek BAŞKA bir kapsamın RLS öncesi çerçevesini yeniden
  # kullanabilirdi. Her parça `<uzunluk>:<içerik>` olarak yazıldığında bu
  # belirsizlik YAPISAL olarak imkânsızdır.
  ham <- .pk_cache_canonical_encode(rls_info, alanlar)

  # ÇARPIŞMAYA DAYANIKLI KARMA ZORUNLUDUR (yetki sınırı). Ağırlıklı karakter
  # toplamı gibi DOĞRUSAL bir sağlama toplamı, aynı uzunlukta birbirini
  # götüren farklarla kolayca çakıştırılabilir ve iki farklı kapsam aynı
  # anahtara düşerdi. `openssl` uygulamanın ZORUNLU bağımlılığıdır; `digest`
  # de kabul edilir. İkisi de yoksa KAPALI BAŞARISIZ olunur: her çağrı BENZERSİZ
  # bir imza döndürür, yani önbellek hiç isabet vermez (yavaş ama GÜVENLİ).
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(paste0("h:", paste(as.character(openssl::sha256(charToRaw(ham))), collapse = "")))
  }
  if (requireNamespace("digest", quietly = TRUE)) {
    return(paste0("h:", digest::digest(ham, algo = "sha256")))
  }

  paste0("nohash:", .pk_cache_unique_token())
}

# Kanonik kodlama: her parça `<bayt uzunluğu>:<içerik>` biçimindedir, bu yüzden
# ayırıcı içeren değerler farklı bir yapıyı TAKLİT EDEMEZ.
.pk_cache_canonical_encode <- function(rls_info, alanlar) {
  parca <- function(metin) {
    ham <- tryCatch(enc2utf8(as.character(metin)[1]), error = function(e) "<bad>")
    if (is.na(ham)) ham <- "<na>"
    paste0(nchar(ham, type = "bytes"), ":", ham)
  }

  bolumler <- vapply(alanlar, function(ad) {
    deger <- rls_info[[ad]]
    if (is.function(deger) || is.environment(deger)) {
      return(paste0(parca(ad), parca("<opaque>")))
    }
    ogeler <- tryCatch(as.character(unlist(deger, use.names = FALSE)),
                       error = function(e) "<unserializable>")
    if (!length(ogeler)) ogeler <- character(0)
    paste0(
      parca(ad),
      parca(as.character(length(ogeler))),
      paste(vapply(ogeler, parca, character(1), USE.NAMES = FALSE), collapse = "")
    )
  }, character(1), USE.NAMES = FALSE)

  paste0(parca(as.character(length(alanlar))), paste(bolumler, collapse = ""))
}

# Karma kütüphanesi yokken KAPALI BAŞARISIZ olmak için benzersiz jeton.
.pk_cache_unique_token <- function() {
  paste0(as.numeric(Sys.time()), "-", sample.int(.Machine$integer.max, 1L))
}