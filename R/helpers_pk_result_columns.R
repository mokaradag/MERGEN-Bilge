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
  -98L,  # SQL Server sql_variant (sürücüye göre)
  -370L  # SQL_SS_TABLE
)

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
  alanlar <- tolower(names(column_info))
  idx <- which(alanlar %in% adaylar)
  if (!length(idx)) return(NULL)
  column_info[[idx[1L]]]
}

#' Sonuç metadata'sından sütun tip/genişlik tanımları çıkar
#'
#' `name` alanı BİLİNÇLİ OLARAK YOK SAYILIR: kolon takma adı bir tip adına
#' benzediği için sonuç reddedilmemelidir.
pk_sql_columns_from_metadata <- function(column_info) {
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
      if (kod %in% .PK_ODBC_LOB_TYPE_CODES) {
        return(list(type = "text", max_length = NA_real_))
      }

      anahtar <- as.character(kod)
      birim <- .PK_ODBC_FIXED_TYPE_BYTES[[anahtar]]
      if (!is.null(birim)) {
        if (anahtar %in% .PK_ODBC_VARIABLE_TYPE_CODES) {
          # Değişken genişlik: BEYAN EDİLEN uzunluk zorunludur. Beyan yoksa
          # (veya `-1` = max) üst sınır KANITLANAMAZ.
          if (is.na(boyut) || !is.finite(boyut) || boyut <= 0) {
            return(list(type = "__unknown__", max_length = NA_real_))
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
