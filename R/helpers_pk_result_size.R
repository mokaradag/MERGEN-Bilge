# ==============================================================================
# Dosya Yolu: R/helpers_pk_result_size.R
# Açıklama: Faz 6 (§5.10) — MUHAFAZAKÂR sonuç-boyutu ön kontrolü, sınırlı-parça
#           (chunk) getirim kararı ve YETKİ FARKINDA satır tavanı planı.
#
# İki ayrı ve KARIŞTIRILMAMASI gereken sorun çözülür:
#
#   1) BELLEK: tek geniş bir sorgu, materyalize edilirken işçinin belleğini
#      tüketebilir. Karar frame YÜKLENMEDEN ÖNCE verilmelidir; önbellek bayt
#      bütçesi yalnızca materyalizasyondan SONRA geçerlidir.
#
#   2) DOĞRULUK: `TOP n` YETKİLENDİRMEDEN ÖNCE uygulanırsa, mevcut kullanıcının
#      yetkili satırları listenin ilerisinde olsa bile keyfî bir önek kalır.
#      O önek üzerinden hesaplanan istatistikler, tavan bildirimi ne kadar
#      belirgin olursa olsun, basitçe YANLIŞTIR.
#
# Bu dosya SAFTIR: SQL çalıştırmaz, DB'ye bağlanmaz, Shiny/reaktif okumaz.
# Yalnızca KARAR üretir; yürütmeyi çağıran yapar.
# ==============================================================================

.PK_RESULT_MB <- 1024 * 1024

# Değişken genişlikli metin/ikili tipler. Beyan edilmiş MAKSİMUM uzunluk
# VARSA üst sınır üretebilirler; yoksa (veya `-1` = MAX ise) üretmezler.
.PK_VARWIDTH_TYPES <- c(
  "varchar", "nvarchar", "char", "nchar", "varbinary", "binary"
)

# HER ZAMAN sınırsız tipler. Katalogda bir `max_length` değeri görünse bile
# bu tipler gerçekte 2^31-1'e kadar veri taşıyabilir (`text` için bildirilen
# uzunluk bir üst sınır DEĞİLDİR), dolayısıyla materyalizasyonu
# yetkilendiremezler.
.PK_ALWAYS_UNBOUNDED_TYPES <- c(
  "text", "ntext", "image", "xml", "sql_variant", "json", "geography", "geometry"
)

# Sabit genişlikli tiplerin muhafazakâr bayt maliyeti (R tarafı, sürücü yükü
# hariç; yük ayrı çarpanla eklenir).
.PK_FIXED_TYPE_BYTES <- list(
  bit = 4L, tinyint = 4L, smallint = 4L, int = 4L, integer = 4L,
  bigint = 8L, real = 8L, float = 8L, double = 8L,
  decimal = 8L, numeric = 8L, money = 8L, smallmoney = 8L,
  date = 8L, datetime = 8L, datetime2 = 8L, smalldatetime = 8L,
  datetimeoffset = 8L, time = 8L, timestamp = 8L,
  uniqueidentifier = 36L
)

.pk_result_type_key <- function(sql_type) {
  ham <- tryCatch(as.character(sql_type)[1], error = function(e) NA_character_)
  if (is.null(ham) || length(ham) == 0L || is.na(ham)) return("")

  # Yerelden BAĞIMSIZ küçültme: Türkçe yerelde tolower("INT") noktasız "ınt"
  # üretir ve tip eşleşmesi sessizce ıskalanır.
  temiz <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", trimws(ham))
  sub("\\(.*$", "", temiz)
}

#' Tek bir sütun için KANITLANMIŞ bayt üst sınırı
#'
#' Beyan edilmiş SQL tipi tek başına üst sınır DEĞİLDİR: `varchar(max)`,
#' `nvarchar(max)`, `varbinary(max)` ve uzunluğu bilinmeyen her tip sınırsızdır.
#' Gözlemlenen örnek genişlikleri, ortalamalar ve sezgiseller de üst sınır
#' değildir — bir örnek 40 karakter görüp 4000 karakterlik satırları ıskalayabilir.
#'
#' @param sql_type SQL tip adı (ör. "nvarchar").
#' @param max_length Beyan edilmiş maksimum karakter/bayt uzunluğu. SQL
#'   Server'da `-1` `MAX` demektir ve üst sınır ÜRETMEZ.
#' @return Bayt üst sınırı, ya da kanıtlanamıyorsa `NA_real_`.
pk_column_width_upper_bound <- function(sql_type, max_length = NA) {
  tip <- .pk_result_type_key(sql_type)
  if (!nzchar(tip)) return(NA_real_)

  sabit <- .PK_FIXED_TYPE_BYTES[[tip]]
  if (!is.null(sabit)) return(as.numeric(sabit))

  if (tip %in% .PK_ALWAYS_UNBOUNDED_TYPES) return(NA_real_)

  if (!(tip %in% .PK_VARWIDTH_TYPES)) {
    # Bilinmeyen tip: üst sınır İDDİA EDİLMEZ.
    return(NA_real_)
  }

  uzunluk <- suppressWarnings(as.numeric(max_length)[1])
  if (length(uzunluk) != 1L || is.na(uzunluk) || !is.finite(uzunluk) || uzunluk <= 0) {
    # `-1` (MAX), NA, 0 veya negatif: sınırsız.
    return(NA_real_)
  }

  # Unicode tipler karakter başına 2 bayt beyan eder; R tarafında UTF-8 en fazla
  # 4 bayt/karakter olabilir. Muhafazakâr taraf 4'tür.
  bayt_carpani <- if (tip %in% c("nvarchar", "nchar", "ntext")) 4 else 1
  as.numeric(uzunluk) * bayt_carpani
}

#' Satır başına KANITLANMIŞ bayt üst sınırı
#'
#' TEK bir sütun sınırsızsa TÜM sonuç sınırsızdır. Sınırsız sütunu atlayıp
#' kalanı toplamak bir üst sınır DEĞİL, alt sınırdır — ve tam olarak
#' materyalizasyona izin vermemesi gereken durumda izin verirdi.
#'
#' @param columns `list(list(type=, max_length=), ...)` veya isimli liste.
#' @return `list(bounded = TRUE/FALSE, bytes_per_row = <num>, unbounded_columns = <chr>)`.
pk_result_width_upper_bound <- function(columns) {
  if (!is.list(columns) || length(columns) == 0L) {
    return(list(bounded = FALSE, bytes_per_row = NA_real_, unbounded_columns = character(0)))
  }

  adlar <- names(columns)
  if (is.null(adlar)) adlar <- rep(NA_character_, length(columns))

  toplam <- 0
  sinirsiz <- character(0)

  for (i in seq_along(columns)) {
    sutun <- columns[[i]]
    ad <- adlar[i]
    if (is.na(ad) || !nzchar(ad)) {
      ad <- as.character(sutun$name %||% paste0("col_", i))[1]
    }

    sinir <- pk_column_width_upper_bound(sutun$type, sutun$max_length %||% NA)
    if (is.na(sinir)) {
      sinirsiz <- c(sinirsiz, ad)
      next
    }
    toplam <- toplam + sinir
  }

  if (length(sinirsiz) > 0L) {
    return(list(bounded = FALSE, bytes_per_row = NA_real_, unbounded_columns = sinirsiz))
  }

  list(bounded = TRUE, bytes_per_row = toplam, unbounded_columns = character(0))
}

#' Materyalizasyon ön kontrolü
#'
#' `COUNT(*) x estimated_width` YALNIZCA `estimated_width` kanıtlanmış bir üst
#' sınır olduğunda kabul edilir. Aksi hâlde ZORUNLU sınırlı-parça getirim
#' yoluna düşülür — "tahmini geniş değil, muhtemelen sığar" bir karar değildir.
#'
#' @param row_count `COUNT(*)` sonucu (bilinmiyorsa `NA`).
#' @param width `pk_result_width_upper_bound()` çıktısı.
#' @param max_result_mb Aktif sonuç tavanı (MB).
#' @param overhead_factor R/sürücü nesne yükü için muhafazakâr çarpan.
#' @return `list(decision = "materialize"|"chunk_required"|"refuse",
#'   estimated_bytes = <num>, reason = <chr>)`.
pk_result_size_preflight <- function(row_count, width, max_result_mb,
                                     overhead_factor = 2.5) {
  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(list(decision = "chunk_required", estimated_bytes = NA_real_,
                reason = "ceiling_unresolved"))
  }
  tavan_bayt <- tavan_mb * .PK_RESULT_MB

  yuk <- suppressWarnings(as.numeric(overhead_factor)[1])
  if (length(yuk) != 1L || is.na(yuk) || !is.finite(yuk) || yuk < 1) yuk <- 2.5

  if (!is.list(width) || !isTRUE(width$bounded)) {
    # Kanıtlanmış üst sınır yok: tam materyalizasyon YETKİLENDİRİLEMEZ.
    return(list(decision = "chunk_required", estimated_bytes = NA_real_,
                reason = "width_not_provably_bounded"))
  }

  satir <- suppressWarnings(as.numeric(row_count)[1])
  if (length(satir) != 1L || is.na(satir) || !is.finite(satir) || satir < 0) {
    return(list(decision = "chunk_required", estimated_bytes = NA_real_,
                reason = "row_count_unknown"))
  }

  tahmin <- satir * as.numeric(width$bytes_per_row) * yuk

  if (tahmin > tavan_bayt) {
    return(list(decision = "refuse", estimated_bytes = tahmin,
                reason = "exceeds_max_result_mb"))
  }

  list(decision = "materialize", estimated_bytes = tahmin, reason = "bounded_within_ceiling")
}

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
      # Kod bilinen bir LOB değil ama tip adı da yok: genişlik kanıtlanamaz.
      return(list(type = "__unknown__", max_length = boyut))
    }

    list(type = tip, max_length = boyut)
  })
}

#' Bir parçada GÜVENLE getirilebilecek satır sayısını planla
#'
#' Satır sayısını sınırlamak TEK BAŞINA yetmez: onlarca `nvarchar(4000)` sütunu
#' olan bir sonuçta 5.000 satırlık tek bir `dbFetch()` tavanı aşabilir ve
#' reddetme kararı verilmeden ÖNCE belleği tüketebilir. Bu yüzden parça boyutu
#' KANITLANMIŞ satır genişliğinden türetilir.
#'
#' Genişlik kanıtlanamıyorsa (LOB veya bilinmeyen tip) sonuç REDDEDİLMEZ —
#' materyalizasyon granülaritesi bir satıra indirilir; birikimli bayt kapısı
#' gerçekten aşıldığında durur. Tipin tek başına "çok büyük" sayılması, tek
#' satırlık kısa bir `nvarchar(max)` sonucunu da reddederdi.
#'
#' @return `list(rows = <int>, bounded = TRUE/FALSE, bytes_per_row = <num>,
#'   reason = <chr>)`.
pk_sql_plan_chunk_rows <- function(column_info, chunk_rows = 5000L,
                                   max_result_mb = 512, overhead_factor = 2.5) {
  istenen <- suppressWarnings(as.integer(chunk_rows)[1])
  if (length(istenen) != 1L || is.na(istenen) || istenen < 1L) istenen <- 5000L

  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(list(rows = 1L, bounded = FALSE, bytes_per_row = NA_real_,
                reason = "ceiling_unresolved"))
  }

  sutunlar <- pk_sql_columns_from_metadata(column_info)
  if (!length(sutunlar)) {
    return(list(rows = istenen, bounded = FALSE, bytes_per_row = NA_real_,
                reason = "metadata_unavailable"))
  }

  genislik <- pk_result_width_upper_bound(sutunlar)
  if (!isTRUE(genislik$bounded)) {
    return(list(rows = 1L, bounded = FALSE, bytes_per_row = NA_real_,
                reason = "width_not_provably_bounded"))
  }

  yuk <- suppressWarnings(as.numeric(overhead_factor)[1])
  if (length(yuk) != 1L || is.na(yuk) || !is.finite(yuk) || yuk < 1) yuk <- 2.5

  satir_bayt <- max(1, as.numeric(genislik$bytes_per_row) * yuk)
  # Parça bütçesi tavanın YARISIDIR: birikmiş frame ile yeni parça bir an için
  # AYNI ANDA bellekte bulunur.
  guvenli <- floor((tavan_mb * .PK_RESULT_MB / 2) / satir_bayt)
  if (!is.finite(guvenli) || guvenli < 1) guvenli <- 1

  list(rows = as.integer(min(istenen, guvenli)), bounded = TRUE,
       bytes_per_row = satir_bayt, reason = "bounded_by_declared_width")
}

#' Sınırlı-parça getiriminde bir parçayı kabul et/reddet
#'
#' Tavanı AŞACAK parça KABUL EDİLMEDEN ÖNCE durulur. Uygulama, tam frame ile
#' sınırsız bir hazırlık kopyasını AYNI ANDA tutmamalıdır; bu yüzden karar
#' "birikmiş bayt + gelen parça baytı" üzerinden verilir.
#'
#' @return `list(action = "accept"|"abort", total_bytes = <num>, reason = <chr>)`.
pk_chunk_accumulate_decision <- function(bytes_so_far, chunk_bytes, max_result_mb) {
  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(list(action = "abort", total_bytes = NA_real_, reason = "ceiling_unresolved"))
  }
  tavan_bayt <- tavan_mb * .PK_RESULT_MB

  birikmis <- suppressWarnings(as.numeric(bytes_so_far)[1])
  if (length(birikmis) != 1L || is.na(birikmis) || !is.finite(birikmis) || birikmis < 0) {
    birikmis <- 0
  }

  parca <- suppressWarnings(as.numeric(chunk_bytes)[1])
  if (length(parca) != 1L || is.na(parca) || !is.finite(parca) || parca < 0) {
    return(list(action = "abort", total_bytes = birikmis, reason = "chunk_bytes_unknown"))
  }

  toplam <- birikmis + parca
  if (toplam > tavan_bayt) {
    return(list(action = "abort", total_bytes = toplam, reason = "would_exceed_max_result_mb"))
  }

  list(action = "accept", total_bytes = toplam, reason = "within_ceiling")
}

# Kullanıcıya görünen Türkçe reddetme mesajı. §5.10: net bir reddetme, keyfî bir
# önek üzerinden hesaplanmış kendinden emin bir yanıttan İYİDİR.
PK_RESULT_TOO_LARGE_MESSAGE <- paste0(
  "\U0001F50D **Sonuç Kümesi Çok Büyük:** Sonuç kümesi güvenli bellek sınırını ",
  "aşıyor, lütfen sorunuzu daraltın. Kısmi bir önek üzerinden istatistik ",
  "üretmek yanıltıcı olacağı için analiz sürdürülmedi."
)

PK_ROW_CAP_STRATEGIES <- c(
  # 1) RLS/filtre SQL'e itildi; tavan zaten yetkili+filtreli kümeye uygulanır.
  "sql_cap_after_authorization",
  # 2) İstatistikler tam yetkili küme üzerinde; yalnızca detay satırları kırpıldı.
  "aggregate_full_cap_detail",
  # 3) Hiçbiri mümkün değil ve tavan aşıldı: açık reddetme.
  "refuse",
  # Tavan hiç gerekmedi (sonuç tavanın altında).
  "none"
)

#' Satır tavanı stratejisini seç
#'
#' @param row_cap Çözülmüş satır tavanı (sorgu metadata > env > options > default).
#' @param authorized_rows Yetkilendirme (ve varsa SQL filtresi) SONRASI satır
#'   sayısı. Bilinmiyorsa `NA`.
#' @param rls_pushdown Yetki yüklemi SQL'e itilebiliyor mu?
#' @param aggregates_over_full_set Toplamlar tam yetkili küme üzerinden
#'   hesaplanabiliyor mu (yalnızca detay satırları kırpılacak)?
#' @return `list(strategy=, cap=, applies=TRUE/FALSE, truncated=TRUE/FALSE,
#'   delivered_rows=, reason=)`.
pk_row_cap_plan <- function(row_cap, authorized_rows = NA,
                            rls_pushdown = FALSE,
                            aggregates_over_full_set = TRUE) {
  tavan <- suppressWarnings(as.numeric(row_cap)[1])
  if (length(tavan) != 1L || is.na(tavan) || !is.finite(tavan) || tavan < 1) {
    # Tavan çözülemedi: KESME YAPILMAZ. Geçersiz bir tavanı "0 satır" gibi
    # yorumlamak, yetkili veriyi yok saymak olurdu.
    return(list(
      strategy = "none", cap = NA_real_, applies = FALSE, truncated = FALSE,
      delivered_rows = suppressWarnings(as.numeric(authorized_rows)[1]),
      reason = "cap_unresolved"
    ))
  }

  satir <- suppressWarnings(as.numeric(authorized_rows)[1])
  satir_bilinir <- length(satir) == 1L && !is.na(satir) && is.finite(satir) && satir >= 0

  if (satir_bilinir && satir <= tavan) {
    return(list(
      strategy = "none", cap = tavan, applies = FALSE, truncated = FALSE,
      delivered_rows = satir, reason = "under_cap"
    ))
  }

  if (isTRUE(rls_pushdown)) {
    # Tavan zaten YETKİLİ kümeye uygulanır; önek yanlılığı yoktur.
    return(list(
      strategy = "sql_cap_after_authorization", cap = tavan, applies = TRUE,
      truncated = satir_bilinir,
      delivered_rows = if (satir_bilinir) min(satir, tavan) else tavan,
      reason = "rls_pushed_to_sql"
    ))
  }

  if (isTRUE(aggregates_over_full_set)) {
    # İstatistikler TAM yetkili küme üzerinde kalır; yalnızca örnek/ek satırlar
    # sınırlanır. Bu, doğruluğu koruyan ikinci tercihtir.
    return(list(
      strategy = "aggregate_full_cap_detail", cap = tavan, applies = TRUE,
      truncated = satir_bilinir,
      delivered_rows = if (satir_bilinir) min(satir, tavan) else tavan,
      reason = "statistics_over_full_authorized_set"
    ))
  }

  list(
    strategy = "refuse", cap = tavan, applies = FALSE, truncated = FALSE,
    delivered_rows = 0,
    reason = "no_safe_capping_strategy"
  )
}

#' Kesme notu (kullanıcıya GÖRÜNÜR)
#'
#' Yorumu etkileyebilecek her kesme yanıtta görünmelidir (§5.11). Not,
#' istatistiklerin hangi küme üzerinde hesaplandığını AÇIKÇA söyler; aksi hâlde
#' kullanıcı kırpılmış detayı tam popülasyon sanır.
#'
#' @return Tek satırlık Türkçe not; kesme yoksa `""`.
pk_row_cap_truncation_note <- function(plan) {
  if (!is.list(plan) || !isTRUE(plan$applies) || !isTRUE(plan$truncated)) return("")

  tavan <- suppressWarnings(as.numeric(plan$cap)[1])
  toplam <- suppressWarnings(as.numeric(plan$delivered_rows)[1])
  tavan_txt <- if (is.na(tavan)) "?" else format(tavan, scientific = FALSE, trim = TRUE)
  toplam_txt <- if (is.na(toplam)) "?" else format(toplam, scientific = FALSE, trim = TRUE)

  if (identical(plan$strategy, "aggregate_full_cap_detail")) {
    return(paste0(
      "Satır tavanı (", tavan_txt, ") uygulandı: **istatistikler yetkiniz ",
      "dahilindeki TÜM satırlar üzerinden** hesaplandı, yalnızca gösterilen ",
      "detay satırları ", toplam_txt, " satıra sınırlandı."
    ))
  }

  paste0(
    "Satır tavanı (", tavan_txt, ") uygulandı: tavan yetki ve filtre ",
    "uygulandıktan SONRA çalıştığı için sonuç yetkili kümenin ilk ",
    toplam_txt, " satırıdır."
  )
}

# ------------------------------------------------------------------------------
# SATIR TAVANI — YETKİ VE FİLTRE SONRASI AŞAMA
# ------------------------------------------------------------------------------
# Tavan `apply_rls_to_data()` İÇİNDE ÇALIŞMAZ. İki ayrı nedenle:
#
#   1) DOĞRULUK: RLS'ten hemen sonra ölçmek, kullanıcının sorusunun kümeyi
#      birkaç satıra indireceği durumlarda bile geniş bir yetkili kümeyi
#      reddederdi. Tavan, filtreler UYGULANDIKTAN SONRA anlamlıdır.
#   2) GERİ ALMA: `apply_rls_to_data()` senkron yolun da ortak yardımcısıdır;
#      tavanı oraya koymak, `MERGEN_PK_ASYNC=false` iken de çalışma zamanı
#      davranışını değiştirir ve ilan edilen tek adımlık geri almayı bozardı.
#
# Sonuç TİPLİDİR: tavan aşımı bir "modül hatası" değil, bir KAYNAK SINIRI
# sonucudur ve boru hattı tarafından öyle raporlanmalıdır.
pk_row_cap_stage <- function(data, query_meta = NULL, active = NULL) {
  bos <- list(status = "ok", data = data, plan = NULL, note = "")
  if (!is.data.frame(data) || nrow(data) == 0L) return(bos)
  if (!exists("pk_row_cap_plan", mode = "function", inherits = TRUE)) return(bos)

  etkin <- if (is.null(active)) {
    exists("pk_async_mode_active", mode = "function", inherits = TRUE) &&
      isTRUE(tryCatch(pk_async_mode_active(query_meta), error = function(e) FALSE))
  } else {
    isTRUE(active)
  }
  if (!isTRUE(etkin)) return(bos)

  row_cap <- if (exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    tryCatch(pk_config_resolve("MERGEN_PK_ROW_CAP", query_meta), error = function(e) 50000L)
  } else {
    50000L
  }

  plan <- pk_row_cap_plan(
    row_cap = row_cap,
    authorized_rows = nrow(data),
    rls_pushdown = FALSE,
    aggregates_over_full_set = FALSE
  )

  if (identical(plan$strategy, "refuse")) {
    return(list(status = "too_large", data = NULL, plan = plan, note = ""))
  }

  not <- if (exists("pk_row_cap_truncation_note", mode = "function", inherits = TRUE)) {
    tryCatch(pk_row_cap_truncation_note(plan), error = function(e) "")
  } else {
    ""
  }
  list(status = "ok", data = data, plan = plan, note = as.character(not)[1])
}

#' Tavan reddini KULLANICIYA GÖRÜNEN metne çevir
pk_row_cap_refuse_message <- function() {
  get0("PK_ROW_CAP_REFUSE_MESSAGE", inherits = TRUE,
       ifnotfound = "Sonuç kümesi çok büyük; lütfen sorunuzu daraltın.")
}

# Güvenli bir tavan stratejisi bulunamadığında kullanıcıya dönen mesaj.
PK_ROW_CAP_REFUSE_MESSAGE <- paste0(
  "\U0001F50D **Sonuç Kümesi Çok Büyük:** Sonuç kümesi çok büyük, lütfen ",
  "sorunuzu daraltın. Yetkilendirme öncesinde keyfî bir kesit almak yanlış ",
  "istatistik üreteceği için analiz sürdürülmedi."
)
