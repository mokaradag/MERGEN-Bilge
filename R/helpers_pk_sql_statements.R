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
    # BÜYÜK HARFE ÇEVİRME YERELDEN BAĞIMSIZ OLMALIDIR.
    #
    # Türkçe `LC_CTYPE` altında `toupper("intersect")` noktalı `İ` üretir ve
    # `INTERSECT` küme işlecine EŞLEŞMEZ; meşru bir `SELECT ... INTERSECT
    # SELECT ...` sorgusu "ikinci ifade" sanılıp REDDEDİLİRDİ. Anahtar
    # kelimeler saf ASCII olduğundan `chartr()` doğru ve yeterlidir.
    kelimeler <- c(kelimeler, chartr("abcdefghijklmnopqrstuvwxyz",
                                     "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                                     substr(metin, bas, bas + boylar[i] - 1L)))
  }
  kelimeler
}

# İKİNCİ ÜST DÜZEY İFADE YALNIZCA "İKİNCİ BİR SELECT" DEĞİLDİR.
#
# Eski sürüm SADECE ikinci bir `SELECT` arıyordu; T-SQL ise noktalı virgül
# istemediği için `SELECT 1 AS a\nDISABLE TRIGGER ALL ON DATABASE` tek bir dize
# olarak geliyor, `DISABLE`/`TRIGGER` denylist'te bulunmadığı için hiçbir yasak
# kelime taraması onu reddetmiyor ve salt-okunur kapı bir DURUM DEĞİŞTİREN
# batch'i onaylıyordu.
#
# Aşağıdaki liste SADECE T-SQL'de AYRILMIŞ (reserved) olan ifade başlatıcılarını
# içerir: ayrılmış oldukları için köşeli parantez olmadan sütun/takma ad
# OLAMAZLAR, dolayısıyla meşru bir kütüphane SELECT'ini yanlışlıkla
# REDDETMEZLER. `PK_SQL_FORBIDDEN_KEYWORDS` taramasında zaten bulunanlar burada
# tekrarlanmaz; bu liste denylist'in AÇIĞINI kapatır.
#
# `FETCH` ve `NEXT` BİLEREK YOKTUR: `ORDER BY ... OFFSET n ROWS FETCH NEXT m
# ROWS ONLY` meşru ve yaygın bir SELECT sayfalama biçimidir.
.pk_sql_ascii_lower <- function(x) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
}

.PK_SQL_RESERVED_STATEMENT_STARTERS <- c(
  "BREAK", "CHECKPOINT", "CLOSE", "CONTINUE", "DEALLOCATE", "GOTO", "IF",
  "OPEN", "READTEXT", "RETURN", "REVERT", "SETUSER", "UPDATETEXT", "WHILE",
  "WRITETEXT"
)

# AYRILMAMIŞ ama tek başına çalışabilen yan etkili ifadeler yalnızca İKİLİ
# biçimleriyle aranır; böylece `Enable` adlı bir sütun takma adı yanlışlıkla
# reddedilmez.
.PK_SQL_STATEMENT_STARTER_PAIRS <- list(
  c("DISABLE", "TRIGGER"),
  c("ENABLE", "TRIGGER")
)

# İkinci bir üst düzey ifade var mı? Varsa jeton adını döndürür, yoksa `NULL`.
.pk_sql_extra_top_level_statement <- function(masked) {
  kelimeler <- .pk_sql_top_level_words(masked)
  if (length(kelimeler) < 2L) return(NULL)

  kume_islecleri <- c("UNION", "EXCEPT", "INTERSECT")
  select_goruldu <- FALSE

  for (i in seq_along(kelimeler)) {
    kelime <- kelimeler[i]

    # İLK jeton bu ifadenin KENDİ başlangıcıdır; "ikinci ifade" sayılmaz.
    # Sınıflandırıcı zaten metnin SELECT/WITH/(SELECT ile başlamasını ayrıca
    # zorunlu kılar.
    if (i > 1L) {
      # `tolower()` YERELE BAĞLIDIR: Türkçe `LC_CTYPE` altında "IF" -> "ıf"
      # üretir ve rapor edilen `kind` değeri platforma göre DEĞİŞİRDİ.
      if (kelime %in% .PK_SQL_RESERVED_STATEMENT_STARTERS) {
        return(.pk_sql_ascii_lower(kelime))
      }
      sonraki <- if (i < length(kelimeler)) kelimeler[i + 1L] else ""
      for (ikili in .PK_SQL_STATEMENT_STARTER_PAIRS) {
        if (identical(kelime, ikili[1]) && identical(sonraki, ikili[2])) {
          return(.pk_sql_ascii_lower(paste(ikili, collapse = "_")))
        }
      }
    }

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
