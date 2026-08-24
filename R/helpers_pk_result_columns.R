# ==============================================================================
# Dosya Yolu: R/helpers_pk_result_columns.R
# Açıklama: Faz 6 (§5.10) — ODBC SONUÇ METADATA'SININ sütun tip/genişlik
#           tanımlarına çevrilmesi.
#
# `R/helpers_pk_result_size.R` içinden BÖLÜNMÜŞTÜR: orası BOYUT MATEMATİĞİDİR
# (üst sınır, ön kontrol, parça planı, satır tavanı) ve dosya bakım bütçesine
# dayanmıştı. Sürücü metadata'sını yorumlamak ayrı bir sorumluluktur ve kendi
# tip-kodu tablolarını taşır.
#
# SAFTIR: SQL çalıştırmaz, DB'ye bağlanmaz, Shiny/reaktif okumaz.
# Manifest sırası ZORUNLUDUR: bu dosya `helpers_pk_result_size.R`'den ÖNCE
# yüklenir (boyut katmanı buradaki çıkarımı tüketir).
# ==============================================================================

# ------------------------------------------------------------------------------
# ODBC SONUÇ METADATA'SINDAN GÜVENLİ PARÇA BOYUTU
# ------------------------------------------------------------------------------
# `DBI::dbColumnInfo()` üretimdeki `odbc::OdbcResult` yolunda yalnızca `name` ve
# `type` döndürür ve `type` SQL Server tip ADI değil, metne çevrilmiş SAYISAL
# ODBC tip kodudur. Bu yüzden:
#
#   * tip adı regex'leri (nvarchar(max), xml, ...) üretimde ESLESMEZ; yalnızca
#     bir KOLON TAKMA ADI o kelimelerden biri olduğunda yanlışlıkla eşleşir —
#     yani kontrol hem yanlış-negatif hem yanlış-pozitif üretir;
#   * `name` alanı tip sınıflandırmasına HİÇ girmemelidir.
#
# Aşağıdaki eşleme SQL/ODBC tip kodlarını kullanır. Bilinmeyen kod "kanıtlanmış
# üst sınır YOK" demektir; bu bir REDDETME değil, ZORUNLU küçük-parça getirim
# sinyalidir.
.PK_ODBC_LOB_TYPE_CODES <- c(
  -1L,   # SQL_LONGVARCHAR  (text)
  -4L,   # SQL_LONGVARBINARY (image / varbinary(max))
  -10L,  # SQL_WLONGVARCHAR (ntext / nvarchar(max))
  -152L, # SQL_SS_XML
  -151L, # SQL_SS_UDT
  -370L  # SQL_SS_TABLE
)

# `sql_variant` (ODBC -98) SINIRSIZ DEĞİLDİR: tek bir değer en fazla 8.016
# bayttır ve bu, AYNI depodaki metadata üreticisi sözleşmesinde de kanıtlanmış
# üst sınır olarak modellenmiştir. LOB listesinde tutmak, sınırsız-LOB opt-in'i
# kapalıyken sınırlı bir sonucu getirmeden reddediyordu.
.PK_ODBC_SQL_VARIANT_CODE <- -98L
.PK_SQL_VARIANT_MAX_BYTES_RUNTIME <- 8016

# SINIRLI (fixed/bounded) ODBC tip kodları -> KANITLANMIŞ bayt üst sınırı.
#
# Bunlar olmadan her LOB-OLMAYAN sayısal kod `__unknown__` sayılıyor ve
# `pk_sql_plan_chunk_rows()` SIRADAN bir INT/VARCHAR/DATE sonucunda bile TEK
# SATIRLIK parçalara düşüyordu: 50 bin satırlık bir sorgu on binlerce
# `dbFetch()` çağrısına dönüşüp isteğin son tarihini sürücü gidiş-dönüşlerinde
# harcıyordu. Sabit genişlikli kodlar için üst sınır tipin KENDİSİNDEN bilinir;
# değişken genişlikli (VARCHAR/NVARCHAR/BINARY) kodlarda BEYAN EDİLEN uzunluk
# kullanılır ve beyan yoksa üst sınır KANITLANAMAZ.
.PK_ODBC_FIXED_TYPE_BYTES <- c(
  "1"    = 1,    # SQL_CHAR (bayt/karakter; beyan uzunluğuyla çarpılır)
  "-8"   = 2,    # SQL_WCHAR
  "12"   = 1,    # SQL_VARCHAR
  "-9"   = 2,    # SQL_WVARCHAR
  "-2"   = 1,    # SQL_BINARY
  "-3"   = 1,    # SQL_VARBINARY
  "2"    = 8,    # SQL_NUMERIC
  "3"    = 8,    # SQL_DECIMAL
  "4"    = 4,    # SQL_INTEGER
  "5"    = 2,    # SQL_SMALLINT
  "6"    = 8,    # SQL_FLOAT
  "7"    = 4,    # SQL_REAL
  "8"    = 8,    # SQL_DOUBLE
  "-6"   = 1,    # SQL_TINYINT
  "-5"   = 8,    # SQL_BIGINT
  "-7"   = 1,    # SQL_BIT
  "9"    = 8,    # SQL_DATETIME
  "91"   = 8,    # SQL_TYPE_DATE
  "92"   = 8,    # SQL_TYPE_TIME
  "93"   = 8,    # SQL_TYPE_TIMESTAMP
  "-154" = 8,    # SQL_SS_TIME2
  "-155" = 12,   # SQL_SS_TIMESTAMPOFFSET
  "-11"  = 16    # SQL_GUID
)

# DEĞİŞKEN genişlikli kodlar: üst sınır ancak BEYAN EDİLEN uzunlukla bilinir.
.PK_ODBC_VARIABLE_TYPE_CODES <- c("1", "-8", "12", "-9", "-2", "-3")

.pk_sql_metadata_field <- function(column_info, adaylar) {
  # YERELDEN BAĞIMSIZ KATLAMA ZORUNLUDUR.
  #
  # Türkçe yerelde `tolower("I")` NOKTASIZ `ı` üretir: `PRECISION` gibi bir
  # sürücü alan adı `precision` yerine `precısıon` olur, aday listesiyle
  # EŞLEŞMEZ ve `boyut` `NA` kalır. Değişken genişlikli sütun o zaman
  # `__unproven__` sınıflanır ve sınırlı yürütücü Türkçe VM'de aynı sorguyu
  # `too_large` diye reddederken CI'da başarılı olur.
  alanlar <- if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) {
    pk_ascii_lower(names(column_info))
  } else {
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
           as.character(names(column_info)))
  }
  idx <- which(alanlar %in% adaylar)
  if (!length(idx)) return(NULL)
  column_info[[idx[1L]]]
}

# ------------------------------------------------------------------------------
# SÜRÜCÜ TANIMLAYICI (DESCRIPTOR) SONDASI
# ------------------------------------------------------------------------------
# SQL Server ODBC arayüzü `varchar(max)`/`nvarchar(max)`/`varbinary(max)`
# sütunlarını SIRADAN `SQL_VARCHAR` (12) / `SQL_WVARCHAR` (-9) /
# `SQL_VARBINARY` (-3) kodlarıyla sunabilir; `dbColumnInfo()` yalnızca `name` ve
# sayısal `type` verdiği için SINIRLI bir VARCHAR ile MAX ayırt EDİLEMEZ
# (PR #703 incelemesi). "Bilinmeyen genişlik = tek satır getir" yaklaşımı da iki
# yönden yanlıştır: tek bir MAX hücresi zaten belleğe TAMAMEN alınır (güvenlik),
# sıradan metin sütunlu 50 bin satırlık bir sonuç ise on binlerce gidiş-dönüşe
# dönüşür (performans).
#
# Bu yüzden SQL Server'ın KENDİ tanımlayıcısı sorulur:
# `sys.dm_exec_describe_first_result_set` her sütun için `system_type_name`
# (ör. `varchar(max)`) ve `max_length` (bayt; MAX için `-1`) döndürür.
#
# Sonda BAŞARISIZ olursa sınıflandırma KAPALI BAŞARISIZ olur (aşağıya bakınız):
# kanıtlanamayan değişken genişlikli sütun `__unproven__` sayılır ve
# `pk_allow_unbounded_lob()` açıkça izin vermedikçe sonuç materyalizasyondan
# ÖNCE reddedilir.
pk_sql_result_schema_probe_enabled <- function() {
  ham <- Sys.getenv("MERGEN_PK_RESULT_SCHEMA_PROBE", unset = "")
  if (!nzchar(ham)) return(TRUE)
  !(tolower(trimws(ham)) %in% c("false", "f", "0", "no", "off", "hayir", "hayır", "kapali", "kapalı"))
}

#' Sonuç kümesi şemasını SQL Server tanımlayıcısından oku
#'
#' @param call_fn Bloklamayı sınırlayan sarmalayıcı: `function(fn)` ->
#'   `list(ok=, value=)`. Verilmezse çağrı doğrudan yapılır.
#' @return Sütun başına `list(name, system_type_name, max_length)` listesi veya
#'   `NULL` (sonda yapılamadı).
pk_sql_describe_result_schema <- function(conn, sql_text, call_fn = NULL) {
  if (!isTRUE(pk_sql_result_schema_probe_enabled())) return(NULL)
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) return(NULL)
  # SONDA YALNIZCA ODBC/SQL Server yolunda anlamlıdır: `dbColumnInfo()` yalnızca
  # orada sayısal tip kodlarına düşer. Diğer sürücüler (ör. testlerdeki SQLite)
  # tip ADI verdiği için sınıflandırma zaten kanıtlıdır ve gereksiz bir
  # gidiş-dönüş yapılmaz.
  if (!inherits(conn, "OdbcConnection") && !inherits(conn, "Microsoft SQL Server")) {
    return(NULL)
  }

  metin <- tryCatch(as.character(sql_text)[1], error = function(e) NA_character_)
  if (is.na(metin) || !nzchar(metin)) return(NULL)

  sorgu <- paste(
    "SELECT name, system_type_name, max_length",
    "FROM sys.dm_exec_describe_first_result_set(CAST(? AS NVARCHAR(MAX)), NULL, 0)",
    "ORDER BY column_ordinal"
  )
  cagir <- if (is.function(call_fn)) call_fn else function(fn) list(ok = TRUE, value = fn())
  sonuc <- tryCatch(cagir(function() DBI::dbGetQuery(conn, sorgu, params = list(metin))),
                    error = function(e) list(ok = FALSE, value = NULL))
  if (!isTRUE(sonuc$ok)) return(NULL)

  cerceve <- sonuc$value
  if (!is.data.frame(cerceve) || nrow(cerceve) == 0L) return(NULL)

  lapply(seq_len(nrow(cerceve)), function(i) {
    list(
      name = as.character(cerceve$name[i]),
      system_type_name = as.character(cerceve$system_type_name[i]),
      max_length = suppressWarnings(as.numeric(cerceve$max_length[i]))
    )
  })
}

# Tanımlayıcı satırından sütun tanımı üret.
#
# `max_length = -1` SQL Server'da MAX/`unlimited` demektir: KANITLANMIŞ üst sınır
# YOKTUR. `xml`/`text`/`ntext`/`image`/`sql_variant` da sınırsızdır.
.pk_sql_column_from_descriptor <- function(satir) {
  # `%||%` YALNIZCA `NULL` ATLAR. `sys.dm_exec_describe_first_result_set`
  # ifadeyi tam betimleyemediğinde `system_type_name` SQL NULL döner; DBI bunu
  # `NA_character_` yapar ve `grepl()` `NA` yayar. Sonraki `if (NA)`
  # "missing value where TRUE/FALSE needed" ile sınıflandırmayı DÜŞÜRÜRDÜ;
  # kanıtlanmamış tip zaten aşağıda güvenli tarafta ("text"/sınırsız) biter.
  tip <- suppressWarnings(as.character(satir$system_type_name %||% "")[1])
  if (length(tip) != 1L || is.na(tip)) tip <- ""
  # YERELDEN BAĞIMSIZ KATLAMA: Türkçe yerelde `tolower("INT")` noktasız `ı`
  # üretir ve aşağıdaki tip karşılaştırmalarının hiçbiri eşleşmezdi.
  tip <- if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) {
    pk_ascii_lower(tip)
  } else {
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", tip)
  }
  boyut <- suppressWarnings(as.numeric(satir$max_length %||% NA_real_)[1])

  # `sql_variant` KANITLANMIŞ 8.016 baytlık üst sınıra sahiptir (bkz. sabit).
  if (grepl("sql_variant", tip, fixed = TRUE)) {
    return(list(type = "__bounded__", max_length = .PK_SQL_VARIANT_MAX_BYTES_RUNTIME))
  }

  sinirsiz_tipler <- c("xml", "text", "ntext", "image", "hierarchyid")
  if (any(vapply(sinirsiz_tipler, function(t) grepl(t, tip, fixed = TRUE), logical(1)))) {
    return(list(type = "text", max_length = NA_real_))
  }
  if (grepl("(max)", tip, fixed = TRUE)) return(list(type = "text", max_length = NA_real_))
  if (length(boyut) == 1L && !is.na(boyut) && boyut < 0) {
    return(list(type = "text", max_length = NA_real_))
  }
  if (length(boyut) == 1L && !is.na(boyut) && is.finite(boyut) && boyut > 0) {
    # UNICODE GENİŞLİĞİ UTF-8 İÇİN ÖLÇEKLENİR.
    #
    # `sys.dm_exec_describe_first_result_set` `max_length` değerini SQL Server
    # SAKLAMA baytı olarak verir; `nchar`/`nvarchar` için bu UTF-16'dır.
    # `pk_column_width_upper_bound()` `__bounded__` genişlikleri AYNEN kullanır,
    # oysa R tarafındaki UTF-8 temsili daha geniş olabilir (en kötü durumda
    # 1,5 kat). Tip-adı yolu Unicode beyanlarını zaten 4 ile çarpar; burada
    # bayt cinsinden geldiği için 2 kat KORUYUCU üst sınırdır. Aksi hâlde
    # `pk_sql_plan_chunk_rows()` satır genişliğini OLDUĞUNDAN KÜÇÜK hesaplayıp
    # `MERGEN_PK_MAX_RESULT_MB` tavanının izin verdiğinden BÜYÜK bir parça seçer.
    unicode_tip <- grepl("nchar", tip, fixed = TRUE) ||
      grepl("nvarchar", tip, fixed = TRUE)
    if (isTRUE(unicode_tip)) boyut <- boyut * 2
    return(list(type = "__bounded__", max_length = boyut))
  }
  # Beyan yok: SABİT genişlikli tipler için tip adından türetilebilir.
  sabit <- c(bit = 1, tinyint = 1, smallint = 2, int = 4, bigint = 8, real = 4,
             float = 8, money = 8, smallmoney = 4, date = 8, time = 8,
             datetime = 8, datetime2 = 8, smalldatetime = 8,
             datetimeoffset = 12, uniqueidentifier = 16)
  for (ad in names(sabit)) {
    if (identical(tip, ad)) return(list(type = "__bounded__", max_length = sabit[[ad]]))
  }
  list(type = "__unproven__", max_length = NA_real_)
}

#' Sonuç metadata'sından sütun tip/genişlik tanımları çıkar
#'
#' `name` alanı BİLİNÇLİ OLARAK YOK SAYILIR: kolon takma adı bir tip adına
#' benzediği için sonuç reddedilmemelidir.
#'
#' @param schema `pk_sql_describe_result_schema()` çıktısı (varsa OTORİTEDİR).
pk_sql_columns_from_metadata <- function(column_info, schema = NULL) {
  # SÜRÜCÜ TANIMLAYICISI VARSA O KULLANILIR: sayısal ODBC kodları MAX ile
  # sınırlı değişken genişliği ayırt edemez, tanımlayıcı ayırt eder.
  if (is.list(schema) && length(schema) > 0L) {
    return(lapply(schema, .pk_sql_column_from_descriptor))
  }
  if (!is.data.frame(column_info) || nrow(column_info) == 0L) return(list())

  tipler <- .pk_sql_metadata_field(column_info, c("type", "data_type", "sql_type",
                                                  "type_name", "typename", "field.type"))
  boyutlar <- .pk_sql_metadata_field(column_info, c("max_length", "column_size",
                                                    "length", "precision"))

  lapply(seq_len(nrow(column_info)), function(i) {
    tip <- if (is.null(tipler)) NA_character_ else as.character(tipler[i])
    boyut <- if (is.null(boyutlar)) NA_real_ else suppressWarnings(as.numeric(boyutlar[i]))

    kod <- suppressWarnings(as.integer(tip))
    if (!is.na(kod)) {
      # Sayısal ODBC kodu: LOB kodları üst sınır ÜRETMEZ.
      # `sql_variant` (-98) KANITLANMIŞ 8.016 bayt üst sınırı taşır.
      if (identical(kod, .PK_ODBC_SQL_VARIANT_CODE)) {
        return(list(type = "__bounded__",
                    max_length = .PK_SQL_VARIANT_MAX_BYTES_RUNTIME))
      }

      if (kod %in% .PK_ODBC_LOB_TYPE_CODES) {
        return(list(type = "text", max_length = NA_real_))
      }

      anahtar <- as.character(kod)
      # `[[` DEĞİL `[`: adlandırılmış atomik vektörde OLMAYAN bir ad `[[` ile
      # "subscript out of bounds" fırlatır. Desteklenmeyen bir ODBC tip kodu bu
      # yüzden `__unknown__` dalına HİÇ ulaşamıyor, planlayıcı çağrısı da
      # tek-satır getirmeye düşmek yerine ABORT ediyordu.
      birim <- unname(.PK_ODBC_FIXED_TYPE_BYTES[anahtar])
      if (length(birim) == 1L && !is.na(birim)) {
        if (anahtar %in% .PK_ODBC_VARIABLE_TYPE_CODES) {
          # Değişken genişlik: BEYAN EDİLEN uzunluk zorunludur.
          #
          # Beyan yoksa (veya `-1`/`0` = sürücünün "sınırsız" sentinel'i) bu
          # sütun `varchar(max)`/`nvarchar(max)`/`varbinary(max)` OLABİLİR ve
          # tek bir hücresi işçiyi OOM edebilir. Bu KANITLANMAMIŞ durum
          # `__unknown__`'dan AYRI raporlanır (`__unproven__`): "bilinmeyen tip"
          # yalnızca granülariteyi düşürürken, kanıtlanmamış DEĞİŞKEN genişlik
          # açık izin olmadıkça REDDEDİLİR (PR #703 incelemesi).
          if (is.na(boyut) || !is.finite(boyut) || boyut <= 0) {
            return(list(type = "__unproven__", max_length = NA_real_))
          }
          return(list(type = "__bounded__", max_length = boyut * birim))
        }
        # Sabit genişlik: üst sınır tipin KENDİSİNDEN bilinir.
        return(list(type = "__bounded__", max_length = birim))
      }

      # Kod bilinmiyor: genişlik kanıtlanamaz (beyan uzunluğu tek başına
      # yeterli DEĞİLDİR; tipin bayt/karakter oranı bilinmiyor).
      return(list(type = "__unknown__", max_length = NA_real_))
    }

    list(type = tip, max_length = boyut)
  })
}
