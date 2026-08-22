# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_statements.R
# Açıklama: Maskelenmiş SQL metni üzerinde İFADE YAPISI çözümlemesi.
#
#           `pk_sql_classify_readonly()` salt-okunur KAPISININ ihtiyaç duyduğu
#           tek şey, metnin BİRDEN FAZLA üst düzey ifade içerip içermediğidir.
#           T-SQL ifadeler arasında `;` ZORUNLU KILMAZ, bu yüzden tespit
#           parantez DERİNLİĞİ farkındalığı ister ve kendi başına bir
#           sorumluluktur.
#
#           Dosya bilerek SAFTIR: Shiny/reaktif/DB/ağ/LLM bağımlılığı YOKTUR ve
#           yalnızca `pk_sql_mask_literals()` çıktısı üzerinde çalışır.
#
#           Yükleme sırası: bu dosya `R/helpers_pk_sql_readonly.R` dosyasından
#           ÖNCE yüklenmelidir.
# ==============================================================================

# Derinlik-0 jetonlarını sırayla üretir (maskelenmiş metin üzerinde).
#
# Metin `pk_sql_mask_literals()` çıktısıdır: dizeler, tırnaklı/köşeli adlar ve
# yorumlar ZATEN boşluğa çevrilmiştir; bu yüzden yalnızca parantez derinliği
# izlenir.
.pk_sql_top_level_words <- function(masked) {
  metin <- as.character(masked %||% "")[1]
  if (is.na(metin) || !nzchar(metin)) return(character(0))

  konumlar <- gregexpr("[A-Za-z_][A-Za-z0-9_]*", metin, perl = TRUE)[[1]]
  if (identical(konumlar[1], -1L)) return(character(0))
  boylar <- attr(konumlar, "match.length")

  # Her jetonun BAŞLANGICINDAKİ parantez derinliği.
  karakterler <- strsplit(metin, "", fixed = TRUE)[[1]]
  derinlik <- integer(length(karakterler))
  d <- 0L
  for (i in seq_along(karakterler)) {
    ch <- karakterler[i]
    if (identical(ch, "(")) d <- d + 1L
    derinlik[i] <- d
    if (identical(ch, ")")) d <- max(0L, d - 1L)
  }

  kelimeler <- character(0)
  for (i in seq_along(konumlar)) {
    bas <- konumlar[i]
    if (bas > length(derinlik) || derinlik[bas] != 0L) next
    # BUYUK HARFE CEVIRME YERELDEN BAGIMSIZ OLMALIDIR.
    #
    # Turkce `LC_CTYPE` altinda `toupper("intersect")` noktali `İ` uretir ve
    # `INTERSECT` kume islecine ESLESMEZ; mesru bir `SELECT ... INTERSECT
    # SELECT ...` sorgusu "ikinci ifade" sanilip REDDEDILIRDI. Anahtar
    # kelimeler saf ASCII oldugundan `chartr()` dogru ve yeterlidir.
    kelimeler <- c(kelimeler, chartr("abcdefghijklmnopqrstuvwxyz",
                                     "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                                     substr(metin, bas, bas + boylar[i] - 1L)))
  }
  kelimeler
}

# İkinci bir üst düzey ifade var mı? Varsa jeton adını döndürür, yoksa `NULL`.
.pk_sql_extra_top_level_statement <- function(masked) {
  kelimeler <- .pk_sql_top_level_words(masked)
  if (length(kelimeler) < 2L) return(NULL)

  kume_islecleri <- c("UNION", "EXCEPT", "INTERSECT")
  select_goruldu <- FALSE

  for (i in seq_along(kelimeler)) {
    kelime <- kelimeler[i]
    if (!identical(kelime, "SELECT")) next

    if (!select_goruldu) {
      select_goruldu <- TRUE
      next
    }

    onceki <- if (i > 1L) kelimeler[i - 1L] else ""
    onceki_iki <- if (i > 2L) kelimeler[i - 2L] else ""
    kume_sonrasi <- onceki %in% kume_islecleri ||
      (identical(onceki, "ALL") && onceki_iki %in% kume_islecleri)
    if (!isTRUE(kume_sonrasi)) return("select")
  }

  NULL
}
