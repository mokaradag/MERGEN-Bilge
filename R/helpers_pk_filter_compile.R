# ==============================================================================
# Dosya Yolu: R/helpers_pk_filter_compile.R
# Açıklama: Proje ve Kaynak Analizi v2 filtre derleyicisi (D1 / D2 / D3).
#
#           Düzeltilen üç kusur:
#             D1 — v1 her filtreyi `dt <- dt[...]` ile ARD ARDA uyguluyordu;
#                  bu yüzden AYNI sütuna gelen iki filtre KESİŞİYORDU ve
#                  "ProjeAdi contains A" + "ProjeAdi contains B" garantili
#                  SIFIR satır döndürüyordu. Doğru anlam: sütun İÇİNDE VEYA,
#                  sütunlar ARASINDA VE; tamamlayıcı aralık sınırları ise aynı
#                  sütunda VE kalır (>= başlangıç VE <= bitiş).
#             D2 — v1 `as.character(val)[1]` ile çok değerli filtrelerin ilk
#                  değerinden sonrasını SESSİZCE atıyordu.
#             D3 — v1 `grepl(..., ignore.case = TRUE)` kullanıyordu; bu Türkçe
#                  İ/I/ı/i eşlemesini BİLMEZ ve C yerel ayarı ile Türkçe VM
#                  arasında farklı davranır. Karşılaştırma tek Türkçe katlama
#                  otoritesi olan `pk_tr_fold()` üzerinden yapılır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yalnızca MERGEN_PK_ENGINE=v2 altında çağrılır (master plan §10).
# ==============================================================================

# Eşdeğer/alternatif seçim üreten işlemler (sütun içinde VEYA'lanır).
PK_FILTER_ALTERNATIVE_OPS <- c("exact_match", "equals", "contains", "in", "starts_with")
# Aralık sınırı üreten işlemler (sütun içinde VE'lenir).
PK_FILTER_LOWER_OPS <- c("greater_than", "greater_or_equal", "from", "min")
PK_FILTER_UPPER_OPS <- c("less_than", "less_or_equal", "to", "max")
# Dışlama üreten işlemler (sütun içinde VE'lenen NOT).
PK_FILTER_EXCLUDE_OPS <- c("not_equals", "exclude", "not_in", "not_contains")

# İşlem adı gibi SAF ASCII belirteçleri için yerelden BAĞIMSIZ küçük harf.
#
# Burada `tolower()` KULLANILAMAZ: Türkçe Windows yerel ayarında `tolower("I")`
# noktasız `ı` üretir, yani LLM'den büyük harfle gelen `CONTAINS` sessizce
# `contaıns` olur, hiçbir işlem listesiyle eşleşmez ve alt dizge araması fark
# edilmeden TAM EŞLEŞMEYE düşerek yanlış (çoğunlukla boş) sonuç verir. Bu, tam
# olarak bu dosyanın düzelttiği D3 kusurunun kendisidir.
#
# `pk_tr_fold()` de kullanılamaz: o Türkçe metin katlamasıdır (İ/Ş/Ü/Ö/Ç ve
# boşluk sadeleştirme), işlem adı ise ASCII bir protokol belirtecidir. Burada
# `chartr()` doğru araçtır çünkü eşleme YALNIZCA A-Z ile sınırlıdır;
# R/helpers_pk_text_turkish.R başlığındaki "Türkçe katlama için chartr
# kullanma" uyarısı Türkçe harfler içindir ve ihlal edilmez.
.pk_filter_ascii_lower <- function(x) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

.pk_filter_fold <- function(x) {
  if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
    return(pk_tr_fold(x))
  }
  # Katlama otoritesi yoksa SESSİZCE tolower()'a düşülmez; bu, D3'ün ta
  # kendisidir. Çağıran tarafın kapalı başarısız olması için hata yükseltilir.
  stop("pk_tr_fold bulunamadi; Turkce karsilastirma guvenli yapilamaz.", call. = FALSE)
}

#' Ham filtre yaprağını normalleştir
#'
#' D2: `value` tek bir skaler, karakter vektörü veya liste olabilir; hepsi
#' korunur, hiçbiri kırpılmaz.
pk_filter_normalize_leaf <- function(f) {
  f <- if (is.list(f)) f else list()

  sutun <- as.character(f$column %||% "")[1]
  if (is.na(sutun)) sutun <- ""
  sutun <- trimws(sutun)

  islem <- as.character(f$operation %||% "exact_match")[1]
  if (is.na(islem) || !nzchar(trimws(islem))) islem <- "exact_match"
  islem <- .pk_filter_ascii_lower(trimws(islem))

  ham <- f$value
  if (is.list(ham)) ham <- unlist(ham, use.names = FALSE)
  degerler <- as.character(ham %||% character(0))
  degerler <- trimws(degerler[!is.na(degerler)])
  degerler <- degerler[nzchar(degerler)]

  list(
    column = sutun,
    operation = islem,
    values = degerler,
    ok = nzchar(sutun) && length(degerler) > 0L,
    reason = if (!nzchar(sutun)) {
      "filtre sutunu belirtilmemis"
    } else if (!length(degerler)) {
      "filtre degeri bos"
    } else {
      NA_character_
    }
  )
}

# Karakter/faktör sütun için bir yaprağın maskesi.
.pk_filter_mask_character <- function(col_vals, leaf) {
  metin <- .pk_filter_fold(as.character(col_vals))
  aranan <- .pk_filter_fold(leaf$values)
  metin[is.na(metin)] <- ""

  if (leaf$operation %in% c("contains", "not_contains")) {
    maske <- rep(FALSE, length(metin))
    for (deger in aranan) {
      # fixed = TRUE: katlanmış metinde arama yapılır, regex kaçışı gerekmez.
      maske <- maske | grepl(deger, metin, fixed = TRUE)
    }
    return(maske)
  }

  if (identical(leaf$operation, "starts_with")) {
    maske <- rep(FALSE, length(metin))
    for (deger in aranan) maske <- maske | startsWith(metin, deger)
    return(maske)
  }

  metin %in% aranan
}

# Sayısal sütun için bir yaprağın maskesi.
.pk_filter_mask_numeric <- function(col_vals, leaf) {
  sayilar <- suppressWarnings(as.numeric(leaf$values))
  sayilar <- sayilar[!is.na(sayilar)]
  if (!length(sayilar)) return(NULL)

  degerler <- as.numeric(col_vals)
  gecerli <- !is.na(degerler)

  maske <- switch(
    leaf$operation,
    greater_than     = degerler > min(sayilar),
    greater_or_equal = degerler >= min(sayilar),
    from             = degerler >= min(sayilar),
    min              = degerler >= min(sayilar),
    less_than        = degerler < max(sayilar),
    less_or_equal    = degerler <= max(sayilar),
    to               = degerler <= max(sayilar),
    max              = degerler <= max(sayilar),
    degerler %in% sayilar
  )

  maske & gecerli
}

# Tarih sütunu için bir yaprağın maskesi.
#
# `as.Date()` ayrıştırılamayan metin için UYARI değil HATA yükseltir
# ("character string is not in a standard unambiguous format"); bu yüzden
# `suppressWarnings()` tek başına yetmez. Filtre değerleri LLM üretimidir ve
# "geçen ay" gibi bir metin kolayca gelebilir. Korumasız hâlde bu hata
# `apply_smart_filters()` üzerinden dışarı sızar ve analiz, yaprağı düşürüp
# gerekçesini bildirmek yerine ham İngilizce R hatasıyla çöker.
.pk_filter_mask_date <- function(col_vals, leaf) {
  guvenli_tarih <- function(x) {
    suppressWarnings(tryCatch(as.Date(x), error = function(e) as.Date(NA)))
  }

  tarihler <- guvenli_tarih(leaf$values)
  tarihler <- tarihler[!is.na(tarihler)]
  if (!length(tarihler)) return(NULL)

  degerler <- guvenli_tarih(col_vals)
  if (!inherits(degerler, "Date") || length(degerler) != length(col_vals)) return(NULL)
  gecerli <- !is.na(degerler)

  maske <- switch(
    leaf$operation,
    greater_than     = degerler > min(tarihler),
    greater_or_equal = degerler >= min(tarihler),
    from             = degerler >= min(tarihler),
    min              = degerler >= min(tarihler),
    less_than        = degerler < max(tarihler),
    less_or_equal    = degerler <= max(tarihler),
    to               = degerler <= max(tarihler),
    max              = degerler <= max(tarihler),
    degerler %in% tarihler
  )

  maske & gecerli
}

#' Tek yaprağın satır maskesini üret
#'
#' @return list(ok, mask, reason)
pk_filter_leaf_mask <- function(data, leaf) {
  if (!isTRUE(leaf$ok)) {
    return(list(ok = FALSE, mask = NULL, reason = leaf$reason %||% "gecersiz filtre"))
  }
  if (!(leaf$column %in% names(data))) {
    return(list(ok = FALSE, mask = NULL, reason = "sütun veri kümesinde bulunamadı"))
  }

  col_vals <- data[[leaf$column]]

  maske <- if (is.character(col_vals) || is.factor(col_vals)) {
    .pk_filter_mask_character(col_vals, leaf)
  } else if (inherits(col_vals, "Date") || inherits(col_vals, "POSIXt")) {
    .pk_filter_mask_date(col_vals, leaf)
  } else if (is.numeric(col_vals)) {
    .pk_filter_mask_numeric(col_vals, leaf)
  } else if (is.logical(col_vals)) {
    mantik <- .pk_filter_ascii_lower(leaf$values) %in% c("true", "1", "evet")
    if (!length(leaf$values)) NULL else col_vals %in% unique(mantik)
  } else {
    NULL
  }

  if (is.null(maske)) {
    return(list(ok = FALSE, mask = NULL, reason = "değer sütun türüne dönüştürülemedi"))
  }

  maske[is.na(maske)] <- FALSE
  list(ok = TRUE, mask = maske, reason = NA_character_)
}

# Yaprakları rolüne göre ayır: alternatif / alt sınır / üst sınır / dışlama.
.pk_filter_leaf_role <- function(operation) {
  if (operation %in% PK_FILTER_EXCLUDE_OPS) return("exclude")
  if (operation %in% PK_FILTER_LOWER_OPS) return("lower")
  if (operation %in% PK_FILTER_UPPER_OPS) return("upper")
  if (operation %in% PK_FILTER_ALTERNATIVE_OPS) return("alternative")
  "alternative"
}

# Tek bir sütun grubunun maskesini kurar.
.pk_filter_column_group_mask <- function(data, leaves) {
  n <- nrow(data)
  alternatif <- NULL
  kisit <- rep(TRUE, n)
  uygulanan <- list()
  dusen <- list()
  alt_sinir_sayisi <- 0L
  ust_sinir_sayisi <- 0L

  for (leaf in leaves) {
    sonuc <- pk_filter_leaf_mask(data, leaf)
    if (!isTRUE(sonuc$ok)) {
      dusen[[length(dusen) + 1L]] <- list(leaf = leaf, reason = sonuc$reason)
      next
    }

    rol <- .pk_filter_leaf_role(leaf$operation)

    if (identical(rol, "alternative")) {
      # D1: AYNI sütundaki alternatifler VEYA'lanır, kesiştirilmez.
      alternatif <- if (is.null(alternatif)) sonuc$mask else (alternatif | sonuc$mask)
    } else if (identical(rol, "exclude")) {
      kisit <- kisit & !sonuc$mask
    } else {
      # Tamamlayıcı aralık sınırları VE'lenir; aksi halde ">= baslangic VEYA
      # <= bitis" neredeyse evrensel bir predikat olurdu.
      kisit <- kisit & sonuc$mask
      if (identical(rol, "lower")) alt_sinir_sayisi <- alt_sinir_sayisi + 1L
      if (identical(rol, "upper")) ust_sinir_sayisi <- ust_sinir_sayisi + 1L
    }

    uygulanan[[length(uygulanan) + 1L]] <- leaf
  }

  maske <- if (is.null(alternatif)) kisit else (alternatif & kisit)

  list(
    mask = maske,
    applied = uygulanan,
    dropped = dusen,
    contradictory_bounds = alt_sinir_sayisi > 1L || ust_sinir_sayisi > 1L
  )
}

#' Düz filtre listesini derle (v2)
#'
#' Normalleştirme kuralı yalnızca DÜZ liste için geçerlidir: yapraklar sütuna
#' göre gruplanır, sütun içinde VEYA / sınırlarda VE uygulanır, sütun grupları
#' arasında VE alınır.
#'
#' @return list(mask, groups, dropped, noop_columns, ok)
pk_filter_compile <- function(data, filters, noop_ratio = NULL) {
  n <- nrow(data)
  bos <- list(
    mask = rep(TRUE, n), groups = list(), dropped = list(),
    noop_columns = character(0), ok = TRUE
  )

  filters <- if (is.list(filters)) filters else list()
  if (!length(filters) || n == 0L) return(bos)

  if (is.null(noop_ratio) && exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    noop_ratio <- tryCatch(pk_config_resolve("MERGEN_PK_NOOP_FILTER_RATIO"), error = function(e) 0.95)
  }
  if (is.null(noop_ratio) || !is.finite(noop_ratio)) noop_ratio <- 0.95

  yapraklar <- lapply(filters, pk_filter_normalize_leaf)

  gecersiz <- Filter(function(x) !isTRUE(x$ok), yapraklar)
  gecerli <- Filter(function(x) isTRUE(x$ok), yapraklar)

  dusen <- lapply(gecersiz, function(x) list(leaf = x, reason = x$reason))

  if (!length(gecerli)) {
    # Düz atama; `utils::modifyList()` adsız listeleri (dropped) düşürür.
    bos$dropped <- dusen
    return(bos)
  }

  sutunlar <- unique(vapply(gecerli, function(x) x$column, character(1)))
  toplam_maske <- rep(TRUE, n)
  gruplar <- list()
  etkisiz <- character(0)

  for (sutun in sutunlar) {
    grup_yapraklari <- Filter(function(x) identical(x$column, sutun), gecerli)
    grup <- .pk_filter_column_group_mask(data, grup_yapraklari)
    dusen <- c(dusen, grup$dropped)

    if (!length(grup$applied)) next

    onceki <- sum(toplam_maske)
    toplam_maske <- toplam_maske & grup$mask
    sonraki <- sum(toplam_maske)
    grup_eslesme <- sum(grup$mask)

    if (grup_eslesme > 0L && (grup_eslesme / n) > noop_ratio) {
      etkisiz <- c(etkisiz, sutun)
    }

    gruplar[[length(gruplar) + 1L]] <- list(
      column = sutun,
      applied = grup$applied,
      rows_before = onceki,
      rows_after = sonraki,
      group_matches = grup_eslesme,
      zero_match = grup_eslesme == 0L,
      contradictory_bounds = isTRUE(grup$contradictory_bounds)
    )
  }

  list(
    mask = toplam_maske,
    groups = gruplar,
    dropped = dusen,
    noop_columns = etkisiz,
    ok = TRUE
  )
}
