# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_schema.R
# Aciklama: Faz 3b metadata ureticisi -- sema cikarimi ve KANIT KURALLARI (SAF).
#
# BU DOSYA CALISMA ZAMANI KODU DEGILDIR; kaynak manifestine EKLENMEZ.
#
# SAFTIR: DB'ye baglanmaz, SQL calistirmaz, dosya yazmaz. Girdi olarak surucu
# tanimlayicisini ya da getirilmis bir data.frame'i alir, cikti olarak sema ve
# GOZLEM listesi uretir.
#
# KANIT SINIRI (master plan §5.1 "Generation strategy"):
#   * YAPI cikarilabilir: sutun adi, tip, tipten turetilen structural role.
#   * ANLAM cikarilamaz: hangi tarihin baslangic hangisinin bitis oldugu,
#     hangi sayinin planlanan hangisinin kalan isgucu oldugu, bir sutunun
#     birincil varlik olup olmadigi. Bunlar Tier-3 insan kuresyonudur.
#   * ONEK (prefix) ORNEGI TEK YONLUDUR: gozlenen bir mukerrer benzersizligi
#     CURUTUR; mukerrer GORMEMEK benzersizligi KANITLAMAZ. Esik ustu farkli
#     deger yuksek kardinaliteyi KANITLAR; esik alti hicbir sey kanitlamaz.
# ==============================================================================

.pkgs_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# SQL Server `system_type_name` -> R SINIF ADI.
#
# NEDEN R SINIFI: `result_schema` tuketicileri (`.pk_meta_role_from_class()`,
# `pk_meta_tier0_column_meta()`) R sinif adlari bekler. Ham SQL tip adi
# yazilsaydi `datetime2` ve `bigint` gibi tipler sessizce "dimension" rolune
# duserdi (tarih ve olcu KAYBI). Ayrica `sample` kipi dogal olarak R sinifi
# uretir; iki kipin AYNI temsili uretmesi sarttir, aksi halde kip degistirmek
# rolleri degistirirdi.
.PKGS_SQL_TYPE_TO_R_CLASS <- c(
  # Tam sayilar
  "int" = "integer", "integer" = "integer", "smallint" = "integer",
  "tinyint" = "integer",
  # 64 bit: odbc varsayilan olarak double dondurur.
  "bigint" = "numeric",
  # Ondalik / kayan nokta
  "decimal" = "numeric", "numeric" = "numeric", "money" = "numeric",
  "smallmoney" = "numeric", "float" = "numeric", "real" = "numeric",
  # Mantiksal
  "bit" = "logical",
  # Tarih / zaman
  "date" = "Date",
  "datetime" = "POSIXct", "datetime2" = "POSIXct", "smalldatetime" = "POSIXct",
  "datetimeoffset" = "POSIXct",
  # Gun ici saat bir TARIH DEGILDIR; bilincli olarak "date" rolune girmez.
  "time" = "difftime",
  # Metin
  "char" = "character", "varchar" = "character", "nchar" = "character",
  "nvarchar" = "character", "text" = "character", "ntext" = "character",
  "xml" = "character", "uniqueidentifier" = "character",
  "sysname" = "character", "sql_variant" = "character",
  # Ikili
  "binary" = "raw", "varbinary" = "raw", "image" = "raw"
)

# Kanitlanmis ust siniri OLMAYAN (LOB) tipler. Sema uretimini engellemezler;
# yalnizca saglik raporunda operatore bildirilirler.
.PKGS_UNBOUNDED_TYPES <- c("text", "ntext", "image", "xml", "sql_variant")

#' SQL Server tip adini R sinifina cevir
#'
#' @return list(r_class, base_type, unbounded, mapped)
#'   `mapped = FALSE` ise tip BILINMIYOR demektir. O durumda EN MUHAFAZAKAR
#'   yapiya (`character` -> `dimension`) dusulur: bir olcu sanip toplamak
#'   sessiz yanlis sayi uretir, bir boyut saymak yalnizca yetenegi kisitlar.
#'   Bu dusus saglik raporunda ACIKCA bildirilir; sessizce yutulmaz.
pkgs_sql_type_to_r_class <- function(system_type_name) {
  ham <- if (length(system_type_name) == 1L && !is.na(system_type_name)) {
    trimws(as.character(system_type_name))
  } else {
    ""
  }

  if (!nzchar(ham)) {
    return(list(r_class = "character", base_type = NA_character_,
                unbounded = TRUE, mapped = FALSE))
  }

  kucuk <- .pkgs_ascii_lower(ham)
  # `varchar(max)`, `decimal(18,2)` -> temel tip adi.
  taban <- trimws(sub("\\(.*$", "", kucuk))
  sinirsiz <- taban %in% .PKGS_UNBOUNDED_TYPES ||
    grepl("(max)", kucuk, fixed = TRUE)

  # `.PKGS_SQL_TYPE_TO_R_CLASS` ADLANDIRILMIS KARAKTER VEKTORUDUR: eksik bir ada
  # `[[` ile erismek NULL DEGIL, "subscript out of bounds" HATASI verir (liste
  # davranisindan farkli). Bu yuzden varlik once `%in% names()` ile sinanir --
  # depoda ayni tuzak `local_model_endpoint_map` icin de belgelenmistir.
  if (!(taban %in% names(.PKGS_SQL_TYPE_TO_R_CLASS))) {
    return(list(r_class = "character", base_type = taban,
                unbounded = sinirsiz, mapped = FALSE))
  }

  list(r_class = unname(.PKGS_SQL_TYPE_TO_R_CLASS[taban]),
       base_type = taban, unbounded = sinirsiz, mapped = TRUE)
}

#' `describe` kipi: surucu tanimlayicisindan sema uret
#'
#' @param descriptor `pk_sql_describe_result_schema()` ciktisi: sutun basina
#'   `list(name, system_type_name, max_length)`.
#' @return list(schema, source_types, unmapped, unbounded) ya da hata durumunda
#'   `NULL`. `schema` adlandirilmis karakter vektorudur (ad = sutun, deger = R
#'   sinifi) -- `pk_meta_validate_schema_dependent()` bu bicimi kabul eder.
pkgs_schema_from_descriptor <- function(descriptor) {
  if (!is.list(descriptor) || !length(descriptor)) return(NULL)

  adlar <- character(0)
  siniflar <- character(0)
  ham_tipler <- character(0)
  eslenmeyen <- character(0)
  sinirsiz <- character(0)

  for (satir in descriptor) {
    if (!is.list(satir)) next
    ad <- if (length(satir$name) == 1L && !is.na(satir$name)) {
      trimws(as.character(satir$name))
    } else {
      ""
    }
    if (!nzchar(ad)) next

    tip <- pkgs_sql_type_to_r_class(satir$system_type_name)
    adlar <- c(adlar, ad)
    siniflar <- c(siniflar, tip$r_class)
    ham_tipler <- c(ham_tipler, as.character(satir$system_type_name %||% NA_character_)[1])
    if (!isTRUE(tip$mapped)) eslenmeyen <- c(eslenmeyen, ad)
    if (isTRUE(tip$unbounded)) sinirsiz <- c(sinirsiz, ad)
  }

  if (!length(adlar)) return(NULL)

  sema <- stats::setNames(siniflar, adlar)
  kaynak <- stats::setNames(ham_tipler, adlar)

  list(
    schema = sema,
    source_types = kaynak,
    unmapped = unique(eslenmeyen),
    unbounded = unique(sinirsiz)
  )
}

#' `sample` kipi: getirilmis data.frame'den sema uret
#'
#' Tip bilgisi R'in KENDI sinifidir; cevrim gerekmez.
pkgs_schema_from_dataframe <- function(df) {
  if (!is.data.frame(df) || !ncol(df)) return(NULL)

  adlar <- names(df)
  if (is.null(adlar) || any(is.na(adlar) | !nzchar(trimws(adlar)))) return(NULL)

  siniflar <- vapply(df, function(s) class(s)[1], character(1))
  sema <- stats::setNames(as.character(siniflar), adlar)

  list(
    schema = sema,
    source_types = stats::setNames(as.character(siniflar), adlar),
    unmapped = character(0),
    unbounded = character(0)
  )
}

#' TEK YONLU ornek gozlemleri
#'
#' Bir onek (prefix) ornegi yalnizca CURUTEBILIR ya da ALT SINIR kanitlayabilir:
#'
#'   * gozlenen mukerrer  -> benzersizlik CURUTULUR (`unique_disproved = TRUE`)
#'   * gozlenen NULL      -> "null yok" CURUTULUR (`null_observed = TRUE`)
#'   * esik ustu farkli   -> `high_cardinality = TRUE` KANITLANIR
#'
#' Mukerrer/NULL GORMEMEK ya da esik alti farkli deger gormek HICBIR SEY
#' kanitlamaz; bu durumlarda alanlar `NA` kalir. `high_cardinality` yalnizca
#' TRUE'ya yukselir, asla FALSE'a dusmez.
#'
#' @param method Ornekleme yontemi. "prefix" disindaki bir yontem TEMSILI
#'   sayilir; bu depoda uretim SQL'i yeniden yazilmadigi icin su an her zaman
#'   "prefix" uretilir ve bu DURUST bir sinirdir.
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
      # Kanit sinirini SATIR SATIR kaydet: rapor okuyucusu her bir alanin
      # neden `NA` oldugunu goruntuden anlayabilmelidir.
      evidence = if (temsili) "representative" else "prefix_one_sided"
    )

    if (n > 0L) {
      null_sayisi <- sum(is.na(deger))
      gozlem$null_observed <- null_sayisi > 0L

      farkli <- tryCatch(length(unique(deger[!is.na(deger)])), error = function(e) NA_integer_)
      gozlem$distinct_observed <- farkli

      if (!is.na(farkli)) {
        gozlem$unique_disproved <- farkli < sum(!is.na(deger))
        # TEK YONLU: yalnizca TRUE'ya yukselir.
        if (farkli > esik) {
          gozlem$high_cardinality_proved <- TRUE
        }
      }
    }

    out[[sutun]] <- gozlem
  }

  out
}

#' Gozlemleri Tier-0 `column_meta` uzerine SINIRLI olarak uygula
#'
#' Yalnizca KANITLANMIS tek yonlu sonuclar yazilir. `high_cardinality` alani
#' `pk_meta_validate_column()` sozlesmesi geregi TRUE/FALSE/NA olmalidir; burada
#' yalnizca TRUE atanabilir, aksi halde `NA` (bilinmiyor) korunur.
pkgs_apply_observations <- function(column_meta, observations) {
  if (!is.list(column_meta) || !length(column_meta)) return(column_meta)
  if (!is.list(observations) || !length(observations)) return(column_meta)

  for (sutun in names(column_meta)) {
    gozlem <- observations[[sutun]]
    if (!is.list(gozlem)) next

    # Ham gozlem KAYIT olarak saklanir (operatorun kuresyon karari icin), ama
    # sozlesme alanlarini KENDILIGINDEN degistirmez.
    column_meta[[sutun]]$observed <- gozlem

    if (isTRUE(gozlem$high_cardinality_proved)) {
      column_meta[[sutun]]$high_cardinality <- TRUE
    }
  }

  column_meta
}

#' Uretilen sema uzerinden Tier-0 `column_meta` insa et
#'
#' `pk_meta_tier0_column_meta()` CALISMA ZAMANI sozlesmesidir ve YENIDEN
#' YAZILMAZ; uretici onu OLDUGU GIBI kullanir ve yalnizca koken alanlari ekler.
#' Boylece uretilen dosya ile Tier-0 boot yolu ayni yapisal cikarimi paylasir.
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
