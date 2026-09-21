# ==============================================================================
# Dosya Yolu: R/helpers_pk_fact_reference_scan.R
# Açıklama: BEKLENMEYEN MODEL SAYISI tarayıcısı (master plan §5.11).
#
#           Yeni mimaride model analitik sayı YAZMAZ; sayının yerine bir yuva
#           jetonu koyar ve değeri R basar. Dolayısıyla modelin düzyazısında
#           veri görünümlü bir sayı kalması YAPISAL bir protokol ihlalidir.
#
#           BU DOSYA BİR EŞLEŞTİRİCİ DEĞİLDİR. Bulduğu sayının hangi olguya ait
#           olabileceğini ARAMAZ; tolerans, birim uyumu, toplulaştırma sözcüğü,
#           sözcük mesafesi ya da işaret gruplaması HESAPLAMAZ. Eski mimarinin
#           tüm ters eşleştirme makinesi bu yüzden SİLİNMİŞTİR.
#
#           Kapsam bilinçli olarak DARDIR; yanlış pozitif üretmemek, eksik
#           yakalamaktan daha pahalıdır. Birincil koruma, sayıyı en baştan
#           modelin yazmıyor olmasıdır.
#
#           GÜVENİLİR İSTEK DEĞERLERİ kapsam dışıdır: kullanıcının kendi
#           yazdığı eşik ("30 günden az") bir veritabanı ölçüsü DEĞİLDİR ve
#           aynı kökenlilik yolundan geçmez. Bu değerler pakette `request_input`
#           türünde olgular olarak AÇIKÇA taşınır; tarayıcı onları tahminle
#           değil, taşınan kümeye karşı TAM eşleşmeyle tanır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

.PK_SCAN_TL_SIGN <- intToUtf8(0x20BA)
.PK_SCAN_EUR_SIGN <- intToUtf8(0x20AC)
.PK_SCAN_CURRENCY <- paste0(.PK_SCAN_TL_SIGN, "$", .PK_SCAN_EUR_SIGN)

# Sayı jetonu: isteğe bağlı yüzde/para öneki + rakamlar + isteğe bağlı birim
# sözcüğü. Türkçe harfler birim adayına dâhildir ("47 saat", "%61,3").
.PK_SCAN_NUMBER_PATTERN <- paste0(
  "(%[[:space:]]*)?[", .PK_SCAN_CURRENCY, "]?[[:space:]]*",
  "-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?[[:space:]]*",
  "(%|[A-Za-zÇĞİÖŞÜçğıöşü",
  .PK_SCAN_CURRENCY, "][A-Za-z0-9ÇĞİÖŞÜçğıöşü",
  .PK_SCAN_CURRENCY, "/.-]{0,15})?"
)

# ÖLÇEK TAŞIYAN birimler. Liste bilinçli olarak KISADIR: birim varlığı yalnızca
# ek bir "veri gibi" sinyalidir, olgu eşleştirmesinde KULLANILMAZ.
.PK_SCAN_SCALE_UNITS <- c("%", "tl", "try", "usd", "eur", "saat", "gun", "adet",
                          "kisi", "ay", "yil", "adam-saat", "m2")

# Madde numarası satırı: "1. " / "2) " gibi önekler ölçü DEĞİLDİR.
.PK_SCAN_LIST_PREFIX <- "^[[:space:]\u00a0*`_>-]*$"

# Yerelden BAĞIMSIZ ASCII katlama + Türkçe harflerin ASCII karşılığı. Yalnızca
# birim jetonu için kullanılır; kullanıcıya görünen metin ETKİLENMEZ.
.pk_scan_fold <- function(x) {
  txt <- suppressWarnings(as.character(x %||% "")[1])
  if (length(txt) != 1L || is.na(txt)) return("")
  txt <- chartr("ÇĞİIÖŞÜçğıöşü",
                "cgiiosucgiosu", txt)
  txt <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
  trimws(sub("[.]+$", "", txt))
}

# Jetonu parçalarına ayırır: rakam metni, birim, yüzde bayrağı.
.pk_scan_parse_token <- function(ham) {
  yuzde <- grepl("%", ham, fixed = TRUE)
  govde <- trimws(gsub("%", "", ham))
  govde <- trimws(sub(paste0("^[", .PK_SCAN_CURRENCY, "]"), "", govde, perl = TRUE))

  rakam <- regmatches(govde, regexpr("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?", govde,
                                     perl = TRUE))
  rakam <- if (length(rakam)) sub("[.,]+$", "", rakam[1]) else ""
  birim <- trimws(sub("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?[[:space:]]*", "", govde,
                      perl = TRUE))

  list(number_text = rakam, unit = birim, percent = yuzde)
}

# Bir konumun satır başlangıcı (madde numarası denetimi için).
.pk_scan_line_start <- function(txt, konum) {
  if (konum <= 1L) return(1L)
  kesme <- gregexpr("[\n\r]", substr(txt, 1L, konum - 1L), perl = TRUE)[[1]]
  if (identical(kesme[1], -1L)) 1L else as.integer(kesme[length(kesme)]) + 1L
}

# Referans jetonlarını AYNI UZUNLUKTA bir nöbetçiyle maskeler: olgu kimlikleri
# rakam içerir ve maskelenmezse sayı tarayıcısı işaretin İÇİNİ sayı sanardı.
# Maskeleme karakter sayısını KORUR, böylece konumlar özgün metinle hizalıdır.
.pk_scan_mask_references <- function(txt) {
  maskeli <- txt
  for (desen in c(PK_FACT_REF_MALFORMED_PATTERN, PK_FACT_REF_LEGACY_PATTERN)) {
    konum <- gregexpr(desen, maskeli, perl = TRUE)[[1]]
    if (identical(konum[1], -1L)) next
    uzunluk <- attr(konum, "match.length")
    karakterler <- strsplit(maskeli, "", fixed = TRUE)[[1]]
    for (i in seq_along(konum)) {
      bas <- as.integer(konum[i])
      son <- bas + as.integer(uzunluk[i]) - 1L
      karakterler[bas:son] <- intToUtf8(1L)
    }
    maskeli <- paste0(karakterler, collapse = "")
  }
  maskeli
}

# GÜVENİLİR İSTEK DEĞERLERİ: yalnızca RAKAMLARA indirgenmiş karşılaştırma
# anahtarı. "1.000" ile "1000" aynı anahtara düşer; biçim farkı bir ihlal
# değildir. Karşılaştırma TAM eşleşmedir, bulanık değildir.
.pk_scan_digit_key <- function(txt) {
  ham <- suppressWarnings(as.character(txt %||% "")[1])
  if (length(ham) != 1L || is.na(ham)) return("")
  eksi <- grepl("^[[:space:]]*-", ham, perl = TRUE)
  haneler <- gsub("[^0-9]", "", ham)
  haneler <- sub("^0+(?=[0-9])", "", haneler, perl = TRUE)
  if (!nzchar(haneler)) return("")
  paste0(if (eksi) "-" else "", haneler)
}

#' Paketteki GÜVENİLİR İSTEK değerlerinin karşılaştırma anahtarları
#'
#' Yalnızca `kind == "request_input"` olguları sayılır. Analitik ölçü olguları
#' BİLEREK dışarıdadır: modelin bir ölçü değerini elle yazması tam da bu
#' mimarinin ortadan kaldırdığı davranıştır.
pk_fact_trusted_input_keys <- function(facts) {
  anahtarlar <- character(0)
  for (olgu in (facts %||% list())) {
    if (!is.list(olgu)) next
    if (!identical(as.character(olgu$kind %||% "")[1], "request_input")) next
    ham <- c(as.character(olgu$request_values %||% character(0)),
             as.character(olgu$display %||% character(0)),
             as.character(olgu$value %||% character(0)))
    for (parca in ham) {
      anahtar <- .pk_scan_digit_key(parca)
      if (nzchar(anahtar)) anahtarlar <- c(anahtarlar, anahtar)
    }
  }
  unique(anahtarlar)
}

#' Model düzyazısındaki BEKLENMEYEN sayısal materyali yapısal olarak bul
#'
#' @param text Model metni (referans jetonları hâlâ yerinde).
#' @param trusted_keys `pk_fact_trusted_input_keys()` çıktısı.
#' @return `list(tokens = list(list(start=, end=, raw=)))` — konumlar ÖZGÜN
#'   metin koordinatlarındadır.
pk_fact_literal_scan <- function(text, trusted_keys = character(0)) {
  txt <- suppressWarnings(as.character(text %||% "")[1])
  if (length(txt) != 1L || is.na(txt) || !nzchar(txt)) return(list(tokens = list()))

  maskeli <- .pk_scan_mask_references(txt)
  konum <- gregexpr(.PK_SCAN_NUMBER_PATTERN, maskeli, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list(tokens = list()))

  uzunluk <- attr(konum, "match.length")
  guvenilir <- as.character(trusted_keys %||% character(0))
  out <- list()

  for (i in seq_along(konum)) {
    bas <- as.integer(konum[i])
    son <- bas + as.integer(uzunluk[i]) - 1L

    # Eşleşme sondaki boşluğu da yutabilir; jeton ANLAMLI karakterlerle sınırlanır.
    tam <- substr(maskeli, bas, son)
    sol <- sub("^[[:space:]\u00a0]+", "", tam)
    sag <- sub("[[:space:]\u00a0]+$", "", sol)
    bas <- bas + (nchar(tam) - nchar(sol))
    son <- bas + nchar(sag) - 1L
    if (son < bas || !nzchar(sag)) next

    ayrisik <- .pk_scan_parse_token(sag)
    rakam <- ayrisik$number_text
    if (!nzchar(rakam)) next

    # Sondaki noktalama jetonun parçası değildir (`15.448.` -> `15.448`).
    kuyruk <- regmatches(sag, regexpr("[.,]+$", sag, perl = TRUE))
    if (length(kuyruk) && nzchar(kuyruk[1]) && !grepl("[.,]$", rakam, perl = TRUE)) {
      son <- son - nchar(kuyruk[1])
      sag <- substr(sag, 1L, nchar(sag) - nchar(kuyruk[1]))
      if (son < bas || !nzchar(sag)) next
    }

    if (.pk_scan_is_exempt(maskeli, bas, son, sag, ayrisik, guvenilir)) next

    out[[length(out) + 1L]] <- list(start = bas, end = son,
                                    raw = substr(txt, bas, son))
  }

  list(tokens = out)
}

# Bir jeton veri iddiası SAYILMAZ mı? (muafiyetler + "veri gibi" kapısı)
#
# Muafiyetler: güvenilir istek değeri, tarih, çıplak yıl, madde numarası.
# Kapı: ayraç / yüzde / bilimsel gösterim / 4+ hane / ölçek taşıyan birim.
.pk_scan_is_exempt <- function(maskeli, bas, son, ham, ayrisik, guvenilir) {
  rakam <- ayrisik$number_text
  yuzde <- isTRUE(ayrisik$percent)

  # GÜVENİLİR İSTEK DEĞERİ: kullanıcının kendi kriteri ihlal değildir.
  anahtar <- .pk_scan_digit_key(rakam)
  if (nzchar(anahtar) && anahtar %in% guvenilir) return(TRUE)

  # Tarih (gg.aa.yyyy / yyyy.aa.gg) bir ölçü değildir.
  if (!yuzde && (grepl("^[0-9]{1,2}[.][0-9]{1,2}[.][0-9]{4}$", rakam, perl = TRUE) ||
                 grepl("^[0-9]{4}[.][0-9]{1,2}[.][0-9]{1,2}$", rakam, perl = TRUE))) {
    return(TRUE)
  }

  ayrac <- grepl("[.,]", rakam, perl = TRUE)
  bilimsel <- grepl("[eE][+-]?[0-9]+$", rakam, perl = TRUE)
  sade <- gsub("[^0-9]", "", rakam)
  haneler <- nchar(sade)
  birim <- .pk_scan_fold(sub("[[:space:]].*$", "", ayrisik$unit))
  taninan_birim <- nzchar(birim) && birim %in% .PK_SCAN_SCALE_UNITS

  # Madde numarası satır başındadır ve ölçü DEĞİLDİR.
  satir_bas <- .pk_scan_line_start(maskeli, bas)
  onek <- if (bas > satir_bas) substr(maskeli, satir_bas, bas - 1L) else ""
  if (grepl(.PK_SCAN_LIST_PREFIX, onek, perl = TRUE) &&
      grepl("^[0-9]{1,2}[.)]?$", ham, perl = TRUE)) {
    sonraki <- if (son < nchar(maskeli)) substr(maskeli, son + 1L, son + 1L) else ""
    if (grepl("^[.)[:space:]]$", sonraki, perl = TRUE)) return(TRUE)
  }

  # Çıplak yıl (1900-2100) bir ölçü değildir; ölçek taşıyan birim yorumu bozar.
  yil_gibi <- !grepl("^-", rakam, perl = TRUE) && !bilimsel && !ayrac && !yuzde &&
    haneler == 4L && !taninan_birim &&
    suppressWarnings(!is.na(as.integer(sade))) &&
    as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
  if (isTRUE(yil_gibi)) return(TRUE)

  veri_gibi <- ayrac || yuzde || bilimsel || haneler >= 4L || taninan_birim
  !veri_gibi
}
