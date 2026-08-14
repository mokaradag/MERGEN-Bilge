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

# Eşdeğer/alternatif seçim üreten işlemler.
PK_FILTER_ALTERNATIVE_OPS <- c("exact_match", "equals", "contains", "in", "starts_with")
# Aralık sınırı üreten işlemler (sütun içinde VE'lenir).
PK_FILTER_LOWER_OPS <- c("greater_than", "greater_or_equal", "from", "min")
PK_FILTER_UPPER_OPS <- c("less_than", "less_or_equal", "to", "max")
# Dışlama üreten işlemler (sütun içinde VE'lenen NOT).
PK_FILTER_EXCLUDE_OPS <- c("not_equals", "exclude", "not_in", "not_contains")

# İZİN VERİLEN İŞLEMLERİN TEK LİSTESİ.
#
# Bu liste KAPALIDIR: burada olmayan bir işlem adı SESSİZCE eşitliğe
# düşürülmez, yaprak DÜŞÜRÜLÜR. Eski davranışta `switch(...)`'in varsayılan
# dalı ve `.pk_filter_leaf_role()`'un "alternative" yedeği, LLM'den gelen
# tanınmayan bir işlemi (örn. `regex`, `between`, `like`) fark edilmeden TAM
# EŞLEŞMEYE çeviriyordu; kullanıcı "1000'den büyük" derken sistem "== 1000"
# uyguluyor ve yanlış bir kümeyi doğruymuş gibi raporluyordu.
PK_FILTER_KNOWN_OPS <- c(
  PK_FILTER_ALTERNATIVE_OPS,
  PK_FILTER_LOWER_OPS,
  PK_FILTER_UPPER_OPS,
  PK_FILTER_EXCLUDE_OPS
)

# Sütun içi birleştirme YALNIZCA açıkça beyan edildiğinde VEYA olur.
#
# Eski davranış aynı sütuna gelen her alternatifi otomatik VEYA'lıyordu; bu,
# "birden çok yüklem aynı sütuna değiniyor" gözleminden VEYA anlamı ÇIKARMAK
# demektir ve kullanıcının "hem X hem Y içeren" isteğini sessizce "X veya Y"
# hâline getirir. Tek bir yaprağın çok değerli olması (`values` vektörü) zaten
# AÇIK bir VEYA'dır (D2) ve o davranış korunur; AYRI yapraklar ise açık bir
# `logic = "or"` beyanı olmadıkça VE'lenir.
PK_FILTER_OR_TOKENS <- c("or", "veya", "any", "herhangi")
PK_FILTER_AND_TOKENS <- c("and", "ve", "all", "tumu", "hepsi")

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
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) {
    return(pk_ascii_lower(x))
  }
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# Mantıksal sütunlar için KAPALI sözlük. Sözlükte olmayan bir değer FALSE'a
# çevrilmez; yaprak düşürülür (aksi hâlde "Durum = belirsiz" sessizce
# "Durum = FALSE" olur ve yanlış bir alt küme doğruymuş gibi raporlanır).
.PK_FILTER_TRUE_TOKENS <- c("true", "t", "1", "evet", "e", "yes", "y", "aktif", "var")
.PK_FILTER_FALSE_TOKENS <- c("false", "f", "0", "hayir", "h", "no", "n", "pasif", "yok")

# bit64::integer64 sütunlarını KAYIPSIZ karşılaştır.
#
# `as.numeric()` 2^53 üstü BIGINT değerlerini bozar; iki farklı kimlik aynı
# double'a düşer ve filtre yanlış satırı seçer. Değerler bu yüzden integer64
# uzayında karşılaştırılır ve dönüştürülemeyen bir değer sessizce eşitliğe
# düşmek yerine yaprağı düşürür.
.pk_filter_is_integer64 <- function(x) inherits(x, "integer64")

.pk_filter_as_integer64 <- function(x) {
  if (!requireNamespace("bit64", quietly = TRUE)) return(NULL)
  out <- suppressWarnings(tryCatch(bit64::as.integer64(x), error = function(e) NULL))
  if (is.null(out)) return(NULL)
  out
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

  # Sütun içi birleştirme AÇIK beyandan okunur; beyan yoksa VE.
  birlesim <- .pk_filter_ascii_lower(trimws(as.character(
    f$logic %||% f$combine %||% f$join %||% ""
  )[1]))
  if (is.na(birlesim)) birlesim <- ""
  birlesim <- if (birlesim %in% PK_FILTER_OR_TOKENS) "or" else "and"

  bilinen_islem <- islem %in% PK_FILTER_KNOWN_OPS

  list(
    column = sutun,
    operation = islem,
    values = degerler,
    logic = birlesim,
    ok = nzchar(sutun) && length(degerler) > 0L && bilinen_islem,
    reason = if (!nzchar(sutun)) {
      "filtre sutunu belirtilmemis"
    } else if (!length(degerler)) {
      "filtre degeri bos"
    } else if (!bilinen_islem) {
      # Tanınmayan işlem SESSİZCE eşitliğe düşürülmez.
      sprintf("desteklenmeyen filtre islemi: '%s'", islem)
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

# Bir sıralı/karşılaştırılabilir sütun için ortak maske üretimi.
#
# `degerler` sütun değerleri, `sinirlar` filtre değerleridir; ikisi de AYNI
# uzayda (numeric / integer64 / Date / POSIXct) olmalıdır. Bilinmeyen işlem
# buraya ULAŞMAZ (yaprak normalleştirmede reddedilir); yine de savunmacı
# olarak NULL döner.
.pk_filter_compare_mask <- function(degerler, sinirlar, operation) {
  gecerli <- !is.na(degerler)

  maske <- switch(
    operation,
    greater_than     = degerler >  min(sinirlar),
    greater_or_equal = degerler >= min(sinirlar),
    from             = degerler >= min(sinirlar),
    min              = degerler >= min(sinirlar),
    less_than        = degerler <  max(sinirlar),
    less_or_equal    = degerler <= max(sinirlar),
    to               = degerler <= max(sinirlar),
    max              = degerler <= max(sinirlar),
    exact_match      = degerler %in% sinirlar,
    equals           = degerler %in% sinirlar,
    `in`             = degerler %in% sinirlar,
    not_equals       = degerler %in% sinirlar,
    not_in           = degerler %in% sinirlar,
    exclude          = degerler %in% sinirlar,
    NULL
  )

  if (is.null(maske)) return(NULL)
  as.logical(maske) & gecerli
}

# Sayısal sütun için bir yaprağın maskesi.
#
# İki kapalı-başarısız kural:
#   * BİR değer bile sayıya çevrilemiyorsa yaprak DÜŞÜRÜLÜR (NULL). Eskiden
#     çevrilemeyen değerler sessizce atılıyor ve kalan alt küme uygulanıyordu;
#     "bütçesi 1000'den büyük ve 'yüksek' olanlar" isteği fark edilmeden
#     yalnızca 1000 sınırına indirgeniyordu.
#   * integer64 sütunlar double'a DÜŞÜRÜLMEZ; 2^53 üstü kimlikler çakışır.
.pk_filter_mask_numeric <- function(col_vals, leaf) {
  if (!length(leaf$values)) return(NULL)

  if (.pk_filter_is_integer64(col_vals)) {
    sinirlar <- .pk_filter_as_integer64(leaf$values)
    if (is.null(sinirlar) || anyNA(sinirlar)) return(NULL)
    return(.pk_filter_compare_mask(col_vals, sinirlar, leaf$operation))
  }

  sayilar <- suppressWarnings(as.numeric(leaf$values))
  if (anyNA(sayilar)) return(NULL)

  .pk_filter_compare_mask(as.numeric(col_vals), sayilar, leaf$operation)
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
  # Kapalı başarısız: bir değer bile tarihe çevrilemiyorsa yaprak düşürülür.
  if (!length(tarihler) || anyNA(tarihler)) return(NULL)

  degerler <- guvenli_tarih(col_vals)
  if (!inherits(degerler, "Date") || length(degerler) != length(col_vals)) return(NULL)

  .pk_filter_compare_mask(degerler, tarihler, leaf$operation)
}

# POSIXct/POSIXlt sütunu için maske — GÜN İÇİ SAAT KORUNUR.
#
# Eskiden zaman damgalı sütunlar da `as.Date()` üzerinden geçiyordu; bu, günü
# 00:00'a yuvarlar. "16:00'dan sonra" gibi bir sınır tamamen kaybolur ve
# `less_than "2024-05-01"` sorgusu 2024-05-01 00:30'daki kaydı YANLIŞLIKLA
# dışarıda bırakır (ya da `greater_or_equal` onu yanlışlıkla içeri alır).
#
# Filtre değeri yalnızca tarih içeriyorsa (saat yoksa) sınır o günün
# başlangıcı/sonu olarak yorumlanır; böylece "1 Mayıs'a kadar" isteği o günün
# tamamını kapsar ve gün içi bilgi de kaybolmaz.
.pk_filter_mask_posix <- function(col_vals, leaf) {
  if (!length(leaf$values)) return(NULL)

  tz <- attr(col_vals, "tzone")
  if (is.null(tz) || !nzchar(tz[1])) tz <- ""

  yalniz_tarih <- grepl("^\\d{4}-\\d{2}-\\d{2}$", trimws(leaf$values))

  ayrist <- function(metin, gun_sonu) {
    suppressWarnings(tryCatch({
      if (grepl("^\\d{4}-\\d{2}-\\d{2}$", trimws(metin))) {
        temel <- as.POSIXct(paste0(trimws(metin), " 00:00:00"), tz = tz)
        if (isTRUE(gun_sonu)) temel <- temel + 86399.999
        temel
      } else {
        as.POSIXct(trimws(metin), tz = tz)
      }
    }, error = function(e) as.POSIXct(NA)))
  }

  # Üst sınır işlemlerinde yalnız-tarih değeri GÜN SONU olarak yorumlanır.
  gun_sonu <- leaf$operation %in% PK_FILTER_UPPER_OPS

  sinirlar <- do.call(c, lapply(seq_along(leaf$values), function(i) {
    ayrist(leaf$values[i], gun_sonu && yalniz_tarih[i])
  }))

  if (is.null(sinirlar) || !length(sinirlar) || anyNA(sinirlar)) return(NULL)

  degerler <- as.POSIXct(col_vals)
  .pk_filter_compare_mask(degerler, sinirlar, leaf$operation)
}

#' Tek yaprağın satır maskesini üret
#'
#' @return list(ok, mask, reason)
pk_filter_leaf_mask <- function(data, leaf, query = NULL) {
  if (!isTRUE(leaf$ok)) {
    return(list(ok = FALSE, mask = NULL, reason = leaf$reason %||% "gecersiz filtre"))
  }
  if (!(leaf$column %in% names(data))) {
    return(list(ok = FALSE, mask = NULL, reason = "sütun veri kümesinde bulunamadı"))
  }

  # METADATA `filterable` KAPISI (kapalı başarısız).
  #
  # `pk_meta_is_filterable()` vardı ama derleyici onu HİÇ çağırmıyordu; yani
  # metadata "bu sütun filtrelenemez" dese bile üretim yolu filtreyi yine de
  # uyguluyordu. Kapı yalnızca metadata GERÇEKTEN sütun tanımı taşıdığında
  # uygulanır; Tier-0 / metadata'sız sorgularda davranış değişmez.
  if (!is.null(query) && exists("pk_meta_is_filterable", mode = "function", inherits = TRUE)) {
    kapali <- tryCatch(.pk_filter_meta_blocks(query, leaf$column), error = function(e) FALSE)
    if (isTRUE(kapali)) {
      return(list(
        ok = FALSE, mask = NULL,
        reason = "sütun metadata tarafından filtrelenebilir işaretlenmemiş"
      ))
    }
  }

  col_vals <- data[[leaf$column]]

  # TÜR/İŞLEM UYUMU KAPISI (kapalı başarısız).
  #
  # `PK_FILTER_KNOWN_OPS` işlemin GENEL olarak tanınıp tanınmadığını denetler;
  # ancak genel olarak geçerli bir işlem, ÇALIŞMA ZAMANI sütun türünde
  # UYGULANAMIYOR olabilir. Metin/faktör sütununda `greater_than` gibi bir
  # aralık işlemi `.pk_filter_mask_character()` içindeki son `%in%` dalına
  # düşer ve istek SESSİZCE eşitliğe dönerdi; mantıksal sütunda da işlem
  # tamamen yok sayılıyordu. Bu, dosyanın başındaki "tanınmayan işlem sessizce
  # eşitliğe düşürülmez" kuralının TÜR düzeyindeki karşılığıdır: yüklem anlamı
  # değiştirilmez, yaprak DÜŞÜRÜLÜR ve gerekçesi ifşa edilir.
  metinsel <- is.character(col_vals) || is.factor(col_vals)
  mantiksal <- is.logical(col_vals)
  if (metinsel || mantiksal) {
    if (leaf$operation %in% c(PK_FILTER_LOWER_OPS, PK_FILTER_UPPER_OPS)) {
      return(list(
        ok = FALSE, mask = NULL,
        reason = sprintf(
          "'%s' araliksal islemi bu sutun turunde uygulanamaz", leaf$operation
        )
      ))
    }
  }
  if (mantiksal && leaf$operation %in% c("contains", "not_contains", "starts_with")) {
    return(list(
      ok = FALSE, mask = NULL,
      reason = sprintf(
        "'%s' metinsel islemi mantiksal sutunda uygulanamaz", leaf$operation
      )
    ))
  }

  maske <- if (is.character(col_vals) || is.factor(col_vals)) {
    .pk_filter_mask_character(col_vals, leaf)
  } else if (inherits(col_vals, "POSIXt")) {
    .pk_filter_mask_posix(col_vals, leaf)
  } else if (inherits(col_vals, "Date")) {
    .pk_filter_mask_date(col_vals, leaf)
  } else if (is.logical(col_vals)) {
    .pk_filter_mask_logical(col_vals, leaf)
  } else if (is.numeric(col_vals) || .pk_filter_is_integer64(col_vals)) {
    .pk_filter_mask_numeric(col_vals, leaf)
  } else {
    NULL
  }

  if (is.null(maske)) {
    return(list(ok = FALSE, mask = NULL, reason = "değer sütun türüne dönüştürülemedi"))
  }

  maske[is.na(maske)] <- FALSE
  list(ok = TRUE, mask = maske, reason = NA_character_)
}

# Metadata sütun tanımı taşıyorsa ve sütun filtrelenebilir değilse TRUE.
.pk_filter_meta_blocks <- function(query, column) {
  meta <- if (is.list(query)) (query$meta %||% query) else NULL
  sutunlar <- if (is.list(meta)) meta$column_meta else NULL
  if (!is.list(sutunlar) || !length(sutunlar)) return(FALSE)
  if (!(column %in% names(sutunlar))) return(FALSE)
  !isTRUE(pk_meta_is_filterable(query, column))
}

# Mantıksal sütun maskesi — sözlük dışı değer FALSE'a ÇEVRİLMEZ.
.pk_filter_mask_logical <- function(col_vals, leaf) {
  if (!length(leaf$values)) return(NULL)

  belirtec <- .pk_filter_ascii_lower(trimws(leaf$values))
  dogru <- belirtec %in% .PK_FILTER_TRUE_TOKENS
  yanlis <- belirtec %in% .PK_FILTER_FALSE_TOKENS

  # Tanınmayan bir mantıksal değer varsa yaprak düşürülür.
  if (any(!(dogru | yanlis))) return(NULL)

  col_vals %in% unique(dogru)
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
#
# Birleştirme kuralı:
#   * Aralık sınırları (lower/upper) her zaman VE'lenir.
#   * Dışlamalar her zaman VE'lenen NOT'tur.
#   * Alternatifler VARSAYILAN OLARAK VE'lenir; yalnızca yaprak açıkça
#     `logic = "or"` beyan ettiyse kendi aralarında VEYA'lanır. Tek bir
#     yaprağın çok değerli olması zaten VEYA'dır ve maske üretiminde ele alınır.
.pk_filter_column_group_mask <- function(data, leaves, query = NULL) {
  n <- nrow(data)
  veya_havuzu <- NULL
  kisit <- rep(TRUE, n)
  uygulanan <- list()
  dusen <- list()
  alt_sinir_sayisi <- 0L
  ust_sinir_sayisi <- 0L

  for (leaf in leaves) {
    sonuc <- pk_filter_leaf_mask(data, leaf, query = query)
    if (!isTRUE(sonuc$ok)) {
      dusen[[length(dusen) + 1L]] <- list(leaf = leaf, reason = sonuc$reason)
      next
    }

    rol <- .pk_filter_leaf_role(leaf$operation)

    if (identical(rol, "exclude")) {
      kisit <- kisit & !sonuc$mask
    } else if (identical(rol, "alternative") && identical(leaf$logic, "or")) {
      veya_havuzu <- if (is.null(veya_havuzu)) sonuc$mask else (veya_havuzu | sonuc$mask)
    } else {
      kisit <- kisit & sonuc$mask
      if (identical(rol, "lower")) alt_sinir_sayisi <- alt_sinir_sayisi + 1L
      if (identical(rol, "upper")) ust_sinir_sayisi <- ust_sinir_sayisi + 1L
    }

    uygulanan[[length(uygulanan) + 1L]] <- leaf
  }

  maske <- if (is.null(veya_havuzu)) kisit else (veya_havuzu & kisit)

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
pk_filter_compile <- function(data, filters, noop_ratio = NULL, query = NULL) {
  n <- nrow(data)
  bos <- list(
    mask = rep(TRUE, n), groups = list(), dropped = list(),
    noop_columns = character(0), ok = TRUE, requested = 0L, all_dropped = FALSE
  )

  filters <- if (is.list(filters)) filters else list()
  if (!length(filters) || n == 0L) return(bos)

  # AÇIK MANTIK GRUPLARI (inert veri yapısı).
  #
  # `filter_expression` (çalıştırılabilir R metni) kaldırıldığı için iç içe
  # VEYA/VE gereksinimi burada VERİ olarak temsil edilir:
  #   list(operator = "or", children = list(<yaprak>, <yaprak veya grup>))
  # Hiçbir aşamada `parse()`/`eval()` yoktur; yalnızca izin verilen işlemler
  # değerlendirilir.
  gruplar_agac <- Filter(.pk_filter_is_group_node, filters)
  filters <- Filter(function(x) !.pk_filter_is_group_node(x), filters)

  agac_maskesi <- rep(TRUE, n)
  agac_dusen <- list()
  agac_uygulanan <- list()
  for (dugum in gruplar_agac) {
    sonuc <- .pk_filter_eval_group(data, dugum, query = query)
    agac_dusen <- c(agac_dusen, sonuc$dropped)
    agac_uygulanan <- c(agac_uygulanan, sonuc$applied)
    if (!is.null(sonuc$mask)) agac_maskesi <- agac_maskesi & sonuc$mask
  }

  if (!length(filters)) {
    if (!length(gruplar_agac)) return(bos)
    bos$mask <- agac_maskesi
    bos$dropped <- agac_dusen
    bos$requested <- length(agac_uygulanan) + length(agac_dusen)
    bos$all_dropped <- !length(agac_uygulanan) && length(agac_dusen) > 0L
    if (length(agac_uygulanan)) {
      bos$groups <- list(list(
        column = "__group__", applied = agac_uygulanan,
        rows_before = n, rows_after = sum(agac_maskesi),
        group_matches = sum(agac_maskesi), zero_match = sum(agac_maskesi) == 0L,
        contradictory_bounds = FALSE
      ))
    }
    return(bos)
  }

  if (is.null(noop_ratio) && exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    noop_ratio <- tryCatch(pk_config_resolve("MERGEN_PK_NOOP_FILTER_RATIO"), error = function(e) 0.95)
  }
  if (is.null(noop_ratio) || !is.finite(noop_ratio)) noop_ratio <- 0.95

  yapraklar <- lapply(filters, pk_filter_normalize_leaf)

  gecersiz <- Filter(function(x) !isTRUE(x$ok), yapraklar)
  gecerli <- Filter(function(x) isTRUE(x$ok), yapraklar)

  dusen <- c(agac_dusen, lapply(gecersiz, function(x) list(leaf = x, reason = x$reason)))
  istenen <- length(yapraklar) + length(agac_uygulanan) + length(agac_dusen)

  if (!length(gecerli)) {
    # Düz atama; `utils::modifyList()` adsız listeleri (dropped) düşürür.
    bos$mask <- agac_maskesi
    bos$dropped <- dusen
    bos$requested <- istenen
    # HİÇBİR yaprak uygulanamadı: çağıran taraf bunu "filtre yoktu" ile
    # KARIŞTIRMAMALIDIR; politika katmanı bu bayrağı görüp reddeder.
    bos$all_dropped <- !length(agac_uygulanan)
    return(bos)
  }

  sutunlar <- unique(vapply(gecerli, function(x) x$column, character(1)))
  toplam_maske <- agac_maskesi
  gruplar <- list()
  etkisiz <- character(0)
  uygulanan_sayisi <- length(agac_uygulanan)

  for (sutun in sutunlar) {
    grup_yapraklari <- Filter(function(x) identical(x$column, sutun), gecerli)
    grup <- .pk_filter_column_group_mask(data, grup_yapraklari, query = query)
    dusen <- c(dusen, grup$dropped)

    if (!length(grup$applied)) next
    uygulanan_sayisi <- uygulanan_sayisi + length(grup$applied)

    onceki <- sum(toplam_maske)
    toplam_maske <- toplam_maske & grup$mask
    sonraki <- sum(toplam_maske)
    grup_eslesme <- sum(grup$mask)

    # ETKİSİZLİK (no-op) HAYATTA KALAN SATIRLARA GÖRE ÖLÇÜLÜR.
    #
    # Eskiden oran TÜM veri kümesine (`n`) bölünüyordu. Diğer filtreler
    # kümeyi 5 satıra indirdiğinde, o 5 satırın hepsini koruyan bir filtre
    # 5/1000 = %0.5 hesaplanıyor ve GERÇEKTEN etkisiz olduğu hâlde etkili
    # sayılıyordu; ifşa hattı da bu yüzden sessiz kalıyordu.
    payda <- max(onceki, 1L)
    if (onceki > 0L && sonraki > 0L && (sonraki / payda) > noop_ratio) {
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
    ok = TRUE,
    requested = istenen,
    all_dropped = uygulanan_sayisi == 0L && length(dusen) > 0L
  )
}
