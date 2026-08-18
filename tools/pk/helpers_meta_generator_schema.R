# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_schema.R
# Açıklama: Faz 3b metadata üreticisi -- şema çıkarımı ve KANIT KURALLARI (SAF).
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# SAFTIR: DB'ye bağlanmaz, SQL çalıştırmaz, dosya yazmaz. Girdi olarak sürücü
# tanımlayıcısını ya da getirilmiş bir data.frame'i alır, çıktı olarak şema ve
# GÖZLEM listesi üretir.
#
# KANIT SINIRI (master plan §5.1 "Generation strategy"):
#   * YAPI çıkarılabilir: sütun adı, tip, tipten türetilen structural role.
#   * ANLAM çıkarılamaz: hangi tarihin başlangıç hangisinin bitiş olduğu,
#     hangi sayının planlanan hangisinin kalan işgücü olduğu, bir sütunun
#     birincil varlık olup olmadığı. Bunlar Tier-3 insan küresyonudur.
#   * ÖNEK (prefix) ÖRNEĞİ TEK YÖNLÜDÜR: gözlenen bir mükerrer benzersizliği
#     ÇÜRÜTÜR; mükerrer GÖRMEMEK benzersizliği KANITLAMAZ. Eşik üstü farklı
#     değer yüksek kardinaliteyi KANITLAR; eşik altı hiçbir şey kanıtlamaz.
#
# DESCRIBE/SAMPLE EŞLİĞİ: iki kip AYNI temsili üretmelidir. Aksi hâlde yalnızca
# kip değiştirmek `result_schema` değerlerini değiştirir ve metadata gereksiz
# yere çalkalanır. Bu yüzden tip eşleme tablosu, odbc'nin GERÇEKTE döndürdüğü
# R sınıflarını hedefler (`bigint` -> integer64, `time` -> hms).
# ==============================================================================

.pkgs_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# Veritabanından gelen metin, Türkçe Windows istemci kod sayfası yolunda ham
# baytlarla gelebilir. `describe` ve `sample` AYNI bayt temsilini üretmelidir;
# aksi hâlde sütun ADI iki kipte farklı anahtarlanır ve yanlış "eksik sütun"
# bulgusu üretilir. Metin DEĞİŞTİRİLMEZ (kırpma/yeniden adlandırma YOK);
# yalnızca UTF-8 olarak işaretlenir.
.pkgs_utf8 <- function(x) {
  if (length(x) != 1L || is.na(x)) return(NA_character_)
  enc2utf8(as.character(x))
}

# SQL Server `system_type_name` -> R SINIF ADI.
#
# NEDEN R SINIFI: `result_schema` tüketicileri (`.pk_meta_role_from_class()`,
# `pk_meta_tier0_column_meta()`) R sınıf adları bekler. Ham SQL tip adı
# yazılsaydı `datetime2` ve `bigint` gibi tipler sessizce "dimension" rolüne
# düşerdi (tarih ve ölçü KAYBI). Ayrıca `sample` kipi doğal olarak R sınıfı
# üretir; iki kipin AYNI temsili üretmesi şarttır, aksi hâlde kip değiştirmek
# rolleri değiştirirdi.
.PKGS_SQL_TYPE_TO_R_CLASS <- c(
  # Tam sayılar
  "int" = "integer", "integer" = "integer", "smallint" = "integer",
  "tinyint" = "integer",
  # 64 bit: `odbc` VARSAYILAN olarak bit64::integer64 döndürür ve
  # `get_connection()` `bigint` argümanını geçersiz kılmaz. `numeric` yazmak
  # describe/sample eşliğini bozardı. `.pk_meta_role_from_class()` integer64'u
  # zaten "measure" sayar, dolayısıyla ölçü rolü KORUNUR.
  "bigint" = "integer64",
  # Ondalık / kayan nokta
  "decimal" = "numeric", "numeric" = "numeric", "money" = "numeric",
  "smallmoney" = "numeric", "float" = "numeric", "real" = "numeric",
  # Mantıksal
  "bit" = "logical",
  # Tarih / zaman
  "date" = "Date",
  "datetime" = "POSIXct", "datetime2" = "POSIXct", "smalldatetime" = "POSIXct",
  "datetimeoffset" = "POSIXct",
  # Gün içi saat bir TARİH DEĞİLDİR; bilinçli olarak "date" rolüne girmez.
  # `odbc` SQL TIME değerlerini `hms` olarak döndürür; sample kipi de bunu
  # görür, bu yüzden describe kipi de "hms" yazar.
  "time" = "hms",
  # Metin
  "char" = "character", "varchar" = "character", "nchar" = "character",
  "nvarchar" = "character", "text" = "character", "ntext" = "character",
  "xml" = "character", "uniqueidentifier" = "character",
  "sysname" = "character", "sql_variant" = "character",
  # İkili. `rowversion` (eski adı `timestamp`) 8 baytlık İKİLİ bir tiptir;
  # bir TARİH/ZAMAN tipi DEĞİLDİR ve öyle eşlenmemelidir.
  "binary" = "raw", "varbinary" = "raw", "image" = "raw",
  "rowversion" = "raw", "timestamp" = "raw"
)

# Kanıtlanmış üst sınırı OLMAYAN (LOB) tipler. Şema üretimini engellemezler;
# yalnızca sağlık raporunda operatöre bildirilirler.
#
# `sql_variant` BU LİSTEDE DEĞİLDİR: SQL Server'da 8.016 baytlık KANITLANMIŞ bir
# üst sınırı vardır; sınırsız saymak her `sql_variant` sütunu için yanlış
# `unbounded_lob_column` bulgusu üretirdi.
.PKGS_UNBOUNDED_TYPES <- c("text", "ntext", "image", "xml")

#' SQL Server tip adını R sınıfına çevir
#'
#' @param max_length Tanımlayıcıdan gelen `max_length` (varsa). SQL Server'da
#'   NEGATİF değer (`-1`) "MAX/sınırsız" demektir. Spatial/CLR UDT gibi bazı
#'   tipler adlarında `(max)` TAŞIMADAN `-1` bildirir; bu yüzden sınırsızlık
#'   yalnızca tip adından değil, beyan edilen uzunluktan da türetilir.
#'
#' @return list(r_class, base_type, unbounded, mapped)
#'   `mapped = FALSE` ise tip BİLİNMİYOR demektir. O durumda EN MUHAFAZAKÂR
#'   yapıya (`character` -> `dimension`) düşülür: bir ölçü sanıp toplamak
#'   sessiz yanlış sayı üretir, bir boyut saymak yalnızca yeteneği kısıtlar.
#'   Bu düşüş sağlık raporunda AÇIKÇA bildirilir; sessizce yutulmaz.
pkgs_sql_type_to_r_class <- function(system_type_name, max_length = NA) {
  ham <- if (length(system_type_name) == 1L && !is.na(system_type_name)) {
    trimws(as.character(system_type_name))
  } else {
    ""
  }

  uzunluk <- suppressWarnings(as.numeric(max_length)[1])
  uzunluk_sinirsiz <- length(uzunluk) == 1L && !is.na(uzunluk) &&
    is.finite(uzunluk) && uzunluk < 0

  if (!nzchar(ham)) {
    return(list(r_class = "character", base_type = NA_character_,
                unbounded = TRUE, mapped = FALSE))
  }

  kucuk <- .pkgs_ascii_lower(ham)
  # `varchar(max)`, `decimal(18,2)` -> temel tip adı.
  taban <- trimws(sub("\\(.*$", "", kucuk))
  sinirsiz <- taban %in% .PKGS_UNBOUNDED_TYPES ||
    grepl("(max)", kucuk, fixed = TRUE) ||
    uzunluk_sinirsiz

  # `.PKGS_SQL_TYPE_TO_R_CLASS` ADLANDIRILMIŞ KARAKTER VEKTÖRÜDÜR: eksik bir ada
  # `[[` ile erişmek NULL DEĞİL, "subscript out of bounds" HATASI verir (liste
  # davranışından farklı). Bu yüzden varlık önce `%in% names()` ile sınanır --
  # depoda aynı tuzak `local_model_endpoint_map` için de belgelenmiştir.
  if (!(taban %in% names(.PKGS_SQL_TYPE_TO_R_CLASS))) {
    return(list(r_class = "character", base_type = taban,
                unbounded = sinirsiz, mapped = FALSE))
  }

  list(r_class = unname(.PKGS_SQL_TYPE_TO_R_CLASS[taban]),
       base_type = taban, unbounded = sinirsiz, mapped = TRUE)
}

#' `describe` kipi: sürücü tanımlayıcısından şema üret
#'
#' @param descriptor `pk_sql_describe_result_schema()` çıktısı: sütun başına
#'   `list(name, system_type_name, max_length)`.
#' @return list(ok, schema, source_types, unmapped, unbounded, invalid) ya da
#'   hata durumunda `NULL`. `schema` adlandırılmış karakter vektörüdür
#'   (ad = sütun, değer = R sınıfı) -- `pk_meta_validate_schema_dependent()` bu
#'   biçimi kabul eder.
#'
#'   SÜTUN ADI ASLA KIRPILMAZ ve ADI OLMAYAN SÜTUN SESSİZCE ATLANMAZ.
#'   `sys.dm_exec_describe_first_result_set` adsız bir ifade için `name = NULL`
#'   döndürebilir; böyle bir sütunu düşerek "kısmi" bir şema yazmak, başlangıç
#'   doğrulamasını GEÇEN ama gerçek DBI sonucuyla UYUŞMAYAN metadata üretirdi.
#'   Bu durumda `invalid` doldurulur ve çağıran sorguyu geri çeker.
pkgs_schema_from_descriptor <- function(descriptor) {
  if (!is.list(descriptor) || !length(descriptor)) return(NULL)

  adlar <- character(0)
  siniflar <- character(0)
  ham_tipler <- character(0)
  eslenmeyen <- list()
  sinirsiz <- character(0)
  gecersiz <- character(0)

  for (i in seq_along(descriptor)) {
    satir <- descriptor[[i]]
    if (!is.list(satir)) {
      gecersiz <- c(gecersiz, sprintf("sutun_%d (tanimlayici satiri liste degil)", i))
      next
    }

    ad_ham <- if (length(satir$name) == 1L && !is.na(satir$name)) {
      .pkgs_utf8(satir$name)
    } else {
      NA_character_
    }

    # Kırpma YOK: `[ Kod ]` gibi bilinçli boşluklu bir takma ad gerçek sonuçta
    # da boşluklu döner; kırpılmış bir anahtar o sütunu ISKALAR.
    if (is.na(ad_ham) || !nzchar(ad_ham)) {
      gecersiz <- c(gecersiz, sprintf("sutun_%d (adsiz sonuc sutunu)", i))
      next
    }

    tip <- pkgs_sql_type_to_r_class(satir$system_type_name, satir$max_length)
    adlar <- c(adlar, ad_ham)
    siniflar <- c(siniflar, tip$r_class)
    ham_tip <- .pkgs_utf8(satir$system_type_name %||% NA_character_)
    ham_tipler <- c(ham_tipler, ham_tip)
    if (!isTRUE(tip$mapped)) {
      # Hangi NATİF tipin eşlenemediği sağlık raporunda görünmelidir; yalnızca
      # sütun adı yazmak operatöre hangi eşlemenin ekleneceğini SÖYLEMEZ.
      eslenmeyen[[length(eslenmeyen) + 1L]] <- list(
        column = ad_ham,
        source_type = if (is.na(ham_tip)) "<bilinmiyor>" else ham_tip
      )
    }
    if (isTRUE(tip$unbounded)) sinirsiz <- c(sinirsiz, ad_ham)
  }

  if (length(gecersiz)) {
    return(list(ok = FALSE, invalid = unique(gecersiz), schema = NULL))
  }
  if (!length(adlar)) return(NULL)

  sema <- stats::setNames(siniflar, adlar)
  kaynak <- stats::setNames(ham_tipler, adlar)

  list(
    ok = TRUE,
    invalid = character(0),
    schema = sema,
    source_types = kaynak,
    unmapped = eslenmeyen,
    unbounded = unique(sinirsiz)
  )
}

#' `sample` kipi: getirilmiş data.frame'den şema üret
#'
#' Tip bilgisi R'in KENDİ sınıfıdır; çevrim gerekmez.
#'
#' @param column_types Varsa sürücü tanımlayıcısından gelen NATİF tip adları
#'   (ad = sütun). R sınıfı `nvarchar(max)`, `xml` ya da eşlenmeyen bir tipi
#'   AYIRT EDEMEZ; bu yüzden yapısal bulgular natif tipten türetilir.
pkgs_schema_from_dataframe <- function(df, column_types = NULL) {
  if (!is.data.frame(df) || !ncol(df)) return(NULL)

  adlar <- names(df)
  if (is.null(adlar) || any(is.na(adlar) | !nzchar(trimws(adlar)))) return(NULL)
  adlar <- vapply(adlar, .pkgs_utf8, character(1), USE.NAMES = FALSE)

  siniflar <- vapply(df, function(s) class(s)[1], character(1), USE.NAMES = FALSE)
  sema <- stats::setNames(as.character(siniflar), adlar)

  eslenmeyen <- list()
  sinirsiz <- character(0)
  kaynak <- stats::setNames(as.character(siniflar), adlar)

  if (is.character(column_types) && length(column_types) && !is.null(names(column_types))) {
    for (sutun in adlar) {
      if (!(sutun %in% names(column_types))) next
      natif <- .pkgs_utf8(column_types[[sutun]])
      if (is.na(natif) || !nzchar(natif)) next
      kaynak[[sutun]] <- natif
      tip <- pkgs_sql_type_to_r_class(natif)
      if (!isTRUE(tip$mapped)) {
        eslenmeyen[[length(eslenmeyen) + 1L]] <- list(column = sutun, source_type = natif)
      }
      if (isTRUE(tip$unbounded)) sinirsiz <- c(sinirsiz, sutun)
    }
  }

  list(
    ok = TRUE,
    invalid = character(0),
    schema = sema,
    source_types = kaynak,
    unmapped = eslenmeyen,
    unbounded = unique(sinirsiz)
  )
}

# DBI blob/list sütunlarında SQL NULL bir `NULL` ÖGESİ olarak gelir ve
# `is.na(NULL)` `logical(0)`, bir liste ögesi için ise FALSE üretir. Düz
# `is.na()` kullanan bir kanıt yolu böyle bir sütunda "NULL görülmedi" der ve
# tekrar eden NULL'ları MÜKERRER DEĞER sayar. Bu yüzden eksiklik açıkça
# hesaplanır.
.pkgs_missing_mask <- function(deger) {
  if (is.list(deger)) {
    return(vapply(deger, function(oge) {
      is.null(oge) || (length(oge) == 1L && is.atomic(oge) && is.na(oge)) ||
        length(oge) == 0L
    }, logical(1)))
  }
  eksik <- tryCatch(is.na(deger), error = function(e) rep(FALSE, length(deger)))
  if (length(eksik) != length(deger)) return(rep(FALSE, length(deger)))
  eksik
}

.pkgs_distinct_count <- function(deger, eksik) {
  tryCatch({
    kalan <- deger[!eksik]
    if (is.list(kalan)) {
      return(length(unique(vapply(kalan, function(o) {
        paste(as.character(o), collapse = "")
      }, character(1)))))
    }
    length(unique(kalan))
  }, error = function(e) NA_integer_)
}

#' TEK YÖNLÜ örnek gözlemleri
#'
#' Bir önek (prefix) örneği yalnızca ÇÜRÜTEBİLİR ya da ALT SINIR kanıtlayabilir:
#'
#'   * gözlenen mükerrer  -> benzersizlik ÇÜRÜTÜLÜR (`unique_disproved = TRUE`)
#'   * gözlenen NULL      -> "null yok" ÇÜRÜTÜLÜR (`null_observed = TRUE`)
#'   * eşik üstü farklı   -> `high_cardinality = TRUE` KANITLANIR
#'
#' Mükerrer/NULL GÖRMEMEK ya da eşik altı farklı değer görmek HİÇBİR ŞEY
#' kanıtlamaz; bu durumlarda alanlar `NA` kalır. `high_cardinality` yalnızca
#' TRUE'ya yükselir, asla FALSE'a düşmez.
#'
#' @param method Örnekleme yöntemi. "prefix" dışındaki bir yöntem TEMSİLİ
#'   sayılır; bu depoda üretim SQL'i yeniden yazılmadığı için şu an her zaman
#'   "prefix" üretilir ve bu DÜRÜST bir sınırdır.
pkgs_sample_observations <- function(df, high_cardinality_threshold = 50L,
                                     method = "prefix") {
  bos <- list()
  if (!is.data.frame(df) || !ncol(df)) return(bos)

  temsili <- !identical(as.character(method)[1], "prefix")
  esik <- suppressWarnings(as.integer(high_cardinality_threshold)[1])
  if (length(esik) != 1L || is.na(esik) || esik < 2L) esik <- 50L

  out <- list()
  for (sutun in names(df)) {
    deger <- df[[sutun]]
    n <- length(deger)

    gozlem <- list(
      sample_method = as.character(method)[1],
      sample_rows_seen = n,
      # Kanıt sınırını SATIR SATIR kaydet: rapor okuyucusu her bir alanın
      # neden `NA` olduğunu görüntüden anlayabilmelidir.
      evidence = if (temsili) "representative" else "prefix_one_sided"
    )

    if (n > 0L) {
      eksik <- .pkgs_missing_mask(deger)
      gozlem$null_observed <- any(eksik)

      farkli <- .pkgs_distinct_count(deger, eksik)
      gozlem$distinct_observed <- farkli

      if (!is.na(farkli)) {
        gozlem$unique_disproved <- farkli < sum(!eksik)
        # TEK YÖNLÜ: yalnızca TRUE'ya yükselir.
        if (farkli > esik) {
          gozlem$high_cardinality_proved <- TRUE
        }
      }
    }

    out[[sutun]] <- gozlem
  }

  out
}

#' Gözlemleri Tier-0 `column_meta` üzerine SINIRLI olarak uygula
#'
#' Yalnızca KANITLANMIŞ tek yönlü sonuçlar yazılır. `high_cardinality` alanı
#' `pk_meta_validate_column()` sözleşmesi gereği TRUE/FALSE/NA olmalıdır; burada
#' yalnızca TRUE atanabilir, aksi hâlde `NA` (bilinmiyor) korunur.
pkgs_apply_observations <- function(column_meta, observations) {
  if (!is.list(column_meta) || !length(column_meta)) return(column_meta)
  if (!is.list(observations) || !length(observations)) return(column_meta)

  for (sutun in names(column_meta)) {
    gozlem <- observations[[sutun]]
    if (!is.list(gozlem)) next

    # Ham gözlem KAYIT olarak saklanır (operatörün küresyon kararı için), ama
    # sözleşme alanlarını KENDİLİĞİNDEN değiştirmez.
    column_meta[[sutun]]$observed <- gozlem

    if (isTRUE(gozlem$high_cardinality_proved)) {
      column_meta[[sutun]]$high_cardinality <- TRUE
    }
  }

  column_meta
}

#' Üretilen şema üzerinden Tier-0 `column_meta` inşa et
#'
#' `pk_meta_tier0_column_meta()` ÇALIŞMA ZAMANI sözleşmesidir ve YENİDEN
#' YAZILMAZ; üretici onu OLDUĞU GİBİ kullanır ve yalnızca köken alanları ekler.
#' Böylece üretilen dosya ile Tier-0 boot yolu aynı yapısal çıkarımı paylaşır.
pkgs_build_column_meta <- function(schema, source_types = NULL, mode = "describe") {
  if (!exists("pk_meta_tier0_column_meta", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] pk_meta_tier0_column_meta bulunamadi; R/helpers_pk_query_meta_access.R yuklenmeli.",
         call. = FALSE)
  }

  cmeta <- pk_meta_tier0_column_meta(schema)
  if (!length(cmeta)) return(cmeta)

  for (sutun in names(cmeta)) {
    cmeta[[sutun]]$inferred_from <- sprintf("generator_%s", as.character(mode)[1])
    if (!is.null(source_types) && !is.null(source_types[[sutun]])) {
      ham <- as.character(source_types[[sutun]])[1]
      if (!is.na(ham) && nzchar(trimws(ham))) cmeta[[sutun]]$source_type <- trimws(ham)
    }
  }

  cmeta
}
