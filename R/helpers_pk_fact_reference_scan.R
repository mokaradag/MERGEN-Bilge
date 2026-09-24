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
#           modelin yazmıyor olmasıdır. Muafiyetler bu yüzden YAPISALDIR:
#           tarih, saat, çıplak yıl, madde numarası ve teknik kimlik içindeki
#           rakamlar ölçü değildir.
#
#           GÜVENİLİR İSTEK DEĞERLERİ kapsam dışıdır: kullanıcının kendi
#           yazdığı eşik ("30 günden az") bir veritabanı ölçüsü DEĞİLDİR ve
#           aynı kökenlilik yolundan geçmez. Bu değerler pakette `request_input`
#           türünde olgular olarak AÇIKÇA taşınır; tarayıcı onları tahminle
#           değil, taşınan kümeye karşı TAM eşleşmeyle tanır. Eşleşme SAYI VE
#           BİRİM ikilisidir: istekteki `1000` eşiği, modelin yazdığı
#           `1.000 saat` iddiasını muaf KILMAZ.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

.PK_SCAN_TL_SIGN <- intToUtf8(0x20BA)
.PK_SCAN_EUR_SIGN <- intToUtf8(0x20AC)
.PK_SCAN_CURRENCY <- paste0(.PK_SCAN_TL_SIGN, "$", .PK_SCAN_EUR_SIGN)

# Üstsimge alan/hacim ekleri (`m²`, `m³`). Kaynak dosya native kodlamaya bağlı
# ters-bölü kaçışı TAŞIMAZ; simgeler kod noktasından üretilir.
.PK_SCAN_SUPERSCRIPT <- intToUtf8(c(0x00B2, 0x00B3))

# Sayı jetonu: isteğe bağlı yüzde/para öneki + rakamlar + isteğe bağlı birim
# sözcüğü. Türkçe harfler ve üstsimgeler birim adayına dâhildir ("47 saat",
# "%61,3", "47 m²").
.PK_SCAN_NUMBER_PATTERN <- paste0(
  "(%[[:space:]]*)?[", .PK_SCAN_CURRENCY, "]?[[:space:]]*",
  "-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?[[:space:]]*",
  "(%|[A-Za-zÇĞİÖŞÜçğıöşü",
  .PK_SCAN_CURRENCY, "][A-Za-z0-9ÇĞİÖŞÜçğıöşü",
  .PK_SCAN_CURRENCY, .PK_SCAN_SUPERSCRIPT, "/.-]{0,15})?"
)

# Rakamların ölçü DEĞİL kimlik parçası olduğu bağlam (`P1234`, `ISO9001`).
.PK_SCAN_IDENT_CHAR <- "[A-Za-z0-9ÇĞİÖŞÜçğıöşü_]"

# ÖLÇEK TAŞIYAN birimler. Liste bilinçli olarak KISADIR: birim varlığı yalnızca
# ek bir "veri gibi" sinyalidir, olgu eşleştirmesinde KULLANILMAZ. Türkçe
# büyüklük sözcükleri de buradadır; "47 milyon TL" küçük bir tam sayı değildir.
.PK_SCAN_SCALE_UNITS <- c("%", "tl", "try", "usd", "eur", "saat", "gun", "adet",
                          "kisi", "ay", "yil", "adam-saat", "m2", "m3",
                          "bin", "milyon", "milyar", "trilyon")

# Para birimi simgesinin kanonik kodu; birim karşılaştırması simge/kod farkına
# takılmaz.
.PK_SCAN_CURRENCY_CODES <- stats::setNames(
  c("tl", "usd", "eur"),
  c(.PK_SCAN_TL_SIGN, "$", .PK_SCAN_EUR_SIGN)
)

# Madde numarası satırı: "1. " / "2) " gibi önekler ölçü DEĞİLDİR.
.PK_SCAN_LIST_PREFIX <- "^[[:space:]\u00a0*`_>-]*$"

# Bağlam denetimlerinin baktığı pencere (tarih/oran dizileri için yeterli).
.PK_SCAN_CONTEXT_WINDOW <- 12L

# Yerelden BAĞIMSIZ ASCII katlama + Türkçe harflerin ve üstsimgelerin ASCII
# karşılığı. Yalnızca birim jetonu için kullanılır; kullanıcıya görünen metin
# ETKİLENMEZ.
.pk_scan_fold <- function(x) {
  txt <- suppressWarnings(as.character(x %||% "")[1])
  if (length(txt) != 1L || is.na(txt)) return("")
  txt <- chartr(.PK_SCAN_SUPERSCRIPT, "23", txt)
  txt <- chartr("ÇĞİIÖŞÜçğıöşü",
                "cgiiosucgiosu", txt)
  txt <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
  trimws(sub("[.]+$", "", txt))
}

# Jetonu parçalarına ayırır: rakam metni, birim, yüzde ve para birimi bayrağı.
#
# ÖNEK PARA BİRİMİ KAYBOLMAZ: `$47` simgesi silinip geriye iki haneli çıplak
# bir tam sayı kalınca tutar muafiyete düşüyordu; simge artık kanonik koduyla
# taşınır ve ölçek taşıyan bir sinyal sayılır.
.pk_scan_parse_token <- function(ham) {
  yuzde <- grepl("%", ham, fixed = TRUE)
  govde <- trimws(gsub("%", "", ham))

  onek <- regmatches(govde, regexpr(paste0("^[", .PK_SCAN_CURRENCY, "]"), govde,
                                    perl = TRUE))
  govde <- trimws(sub(paste0("^[", .PK_SCAN_CURRENCY, "]"), "", govde, perl = TRUE))

  rakam <- regmatches(govde, regexpr("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?", govde,
                                     perl = TRUE))
  rakam <- if (length(rakam)) sub("[.,]+$", "", rakam[1]) else ""
  birim <- trimws(sub("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?[[:space:]]*", "", govde,
                      perl = TRUE))

  simge <- if (length(onek) && nzchar(onek[1])) onek[1] else substr(birim, 1L, 1L)
  kod <- if (nzchar(simge) && simge %in% names(.PK_SCAN_CURRENCY_CODES)) {
    unname(.PK_SCAN_CURRENCY_CODES[[simge]])
  } else {
    ""
  }

  list(number_text = rakam, unit = birim, percent = yuzde, currency_code = kod)
}

#' Bir jetonun ÖLÇEK TAŞIYAN birim anahtarı ("" ise birim yok)
#'
#' Yüzde, tanınan birim sözcüğü ve para birimi simgesi AYNI anahtar uzayına
#' düşer; böylece istek değeriyle model iddiası simetrik karşılaştırılır.
pk_fact_unit_key <- function(ayrisik) {
  if (!is.list(ayrisik)) return(.pk_scan_unit_from_text(ayrisik))
  if (isTRUE(ayrisik$percent)) return("%")
  birim <- .pk_scan_fold(sub("[[:space:]].*$", "", as.character(ayrisik$unit %||% "")[1]))
  if (nzchar(birim) && birim %in% .PK_SCAN_SCALE_UNITS) return(birim)
  as.character(ayrisik$currency_code %||% "")[1]
}

# Serbest bir birim metninin ("saat", "TL", "%") anahtarı.
.pk_scan_unit_from_text <- function(x) {
  ham <- suppressWarnings(as.character(x %||% "")[1])
  if (length(ham) != 1L || is.na(ham) || !nzchar(ham)) return("")
  if (identical(trimws(ham), "%")) return("%")
  if (trimws(ham) %in% names(.PK_SCAN_CURRENCY_CODES)) {
    return(unname(.PK_SCAN_CURRENCY_CODES[[trimws(ham)]]))
  }
  birim <- .pk_scan_fold(sub("[[:space:]].*$", "", ham))
  if (nzchar(birim) && birim %in% .PK_SCAN_SCALE_UNITS) birim else ""
}

#' Yuvadan HEMEN SONRA gelen ölçek taşıyan birim ("" ise yok)
#'
#' Yalnızca araya sözcük girmeyen komşuluk okunur; amaç kimlik çıkarımı değil,
#' R'nin bastığı kanonik gösterime model tarafından İLİŞTİRİLEN birimi görmek.
pk_fact_unit_after <- function(txt, pos) {
  pk_fact_unit_span(txt, pos, "after")$key
}

#' Yuvaya bitişik ölçek birimi: anahtar ve (boşluk dâhil) karakter uzunluğu
#'
#' `after`: `pos` konumundan SONRA gelen birim sözcüğü/simgesi. `before`: `pos`
#' konumundan ÖNCE gelen yüzde/para SİMGESİ (`%{{fact:x}}`). Birim komşu bir
#' SAYIYA aitse (`%5`, `61,3 %`) uzunluk 0 döner: silinmesi sayıyı bozardı.
pk_fact_unit_span <- function(txt, pos, yon = c("after", "before")) {
  yon <- match.arg(yon)
  bos <- list(key = "", length = 0L)
  metin <- suppressWarnings(as.character(txt %||% "")[1])
  if (length(metin) != 1L || is.na(metin)) return(bos)
  if (identical(yon, "after")) {
    kuyruk <- substr(metin, pos + 1L, min(nchar(metin), pos + 24L))
    desen <- paste0("^[[:space:]\u00a0]*(%|[A-Za-zÇĞİÖŞÜçğıöşü", .PK_SCAN_CURRENCY,
                    "][A-Za-z0-9ÇĞİÖŞÜçğıöşü", .PK_SCAN_SUPERSCRIPT, "-]{0,15})")
    esle <- regmatches(kuyruk, regexpr(desen, kuyruk, perl = TRUE))
    if (!length(esle) || !nzchar(esle[1])) return(bos)
    sonraki <- substr(kuyruk, nchar(esle[1]) + 1L, nchar(kuyruk))
    uzunluk <- if (grepl("^[[:space:]\u00a0]*[0-9]", sonraki, perl = TRUE)) 0L else nchar(esle[1])
    return(list(key = .pk_scan_unit_from_text(trimws(esle[1])), length = uzunluk))
  }
  bas <- max(1L, pos - 4L)
  on <- if (pos > 1L) substr(metin, bas, pos - 1L) else ""
  esle <- regmatches(on, regexpr(paste0("[%", .PK_SCAN_CURRENCY, "][[:space:]\u00a0]*$"),
                                 on, perl = TRUE))
  if (!length(esle) || !nzchar(esle[1])) return(bos)
  sol <- substr(metin, 1L, pos - nchar(esle[1]) - 1L)
  if (grepl("[0-9][[:space:]\u00a0]*$", sol, perl = TRUE)) return(bos)
  list(key = .pk_scan_unit_from_text(substr(esle[1], 1L, 1L)), length = nchar(esle[1]))
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
#
# KANONİK DESEN DE MASKELENİR: bozuk-jeton deseni gövdeyi 160 karakterle
# sınırlar, oysa geçerli bir olgu kimliği (ad alanı + uzun grup dilimleri) bu
# sınırı aşabilir. Maskeleme yalnızca sınırlı desene dayandığında böyle bir
# jetonun İÇİ model sayısı sanılıyordu.
.pk_scan_mask_references <- function(txt) {
  maskeli <- txt
  for (desen in c(PK_FACT_REF_PATTERN, PK_FACT_REF_MALFORMED_PATTERN,
                  PK_FACT_REF_OPEN_PATTERN, PK_FACT_REF_LEGACY_PATTERN,
                  PK_FACT_REF_BROKEN_OPENER_PATTERN)) {
    konum <- gregexpr(desen, maskeli, perl = TRUE)[[1]]
    if (identical(konum[1], -1L)) next
    uzunluk <- attr(konum, "match.length")
    karakterler <- strsplit(maskeli, "", fixed = TRUE)[[1]]
    for (i in seq_along(konum)) {
      bas <- as.integer(konum[i])
      son <- bas + as.integer(uzunluk[i]) - 1L
      if (son < bas) next
      karakterler[bas:son] <- intToUtf8(1L)
    }
    maskeli <- paste0(karakterler, collapse = "")
  }
  maskeli
}

#' Sayısal bir metnin KANONİK karşılaştırma anahtarı ("" ise sayı değil)
#'
#' Binlik ayracı ile ondalık ayracı AYIRT EDİLİR: `1.000` -> `1000`,
#' `1,5` -> `1.5`, `12.500` -> `12500`. Rakam dışındaki her şeyi silen eski
#' anahtar `P15` ile `15`i, `1,5` ile `15`i aynı kovaya düşürüyordu; ilgisiz
#' bir istek değeri model iddiasını muaf kılabiliyordu.
pk_fact_number_key <- function(txt) {
  ham <- suppressWarnings(as.character(txt %||% "")[1])
  if (length(ham) != 1L || is.na(ham)) return("")
  ham <- gsub("[[:space:]\u00a0]", "", ham, perl = TRUE)
  eksi <- grepl("^-", ham, perl = TRUE)
  ham <- sub("^[+-]", "", ham)
  if (!grepl("^[0-9][0-9.,]*$", ham, perl = TRUE)) return("")

  # Binlik gruplu sayı `0` ile başlamaz: `0,125` / `0.500` ondalıktır.
  if (grepl("^[1-9][0-9]{0,2}([.][0-9]{3})+([,][0-9]+)?$", ham, perl = TRUE)) {
    ham <- gsub(".", "", ham, fixed = TRUE)
  } else if (grepl("^[1-9][0-9]{0,2}([,][0-9]{3})+([.][0-9]+)?$", ham, perl = TRUE)) {
    ham <- gsub(",", "", ham, fixed = TRUE)
  }
  ham <- sub(",", ".", ham, fixed = TRUE)
  if (!grepl("^[0-9]+([.][0-9]+)?$", ham, perl = TRUE)) return("")

  # Kanonik biçim METİNDEN üretilir: `as.numeric()` yerel `OutDec` ayarına ve
  # bilimsel gösterime bağımlıdır, anahtar ise deterministik olmalıdır.
  parcalar <- strsplit(ham, ".", fixed = TRUE)[[1]]
  tam <- sub("^0+(?=[0-9])", "", parcalar[1], perl = TRUE)
  kesir <- if (length(parcalar) > 1L) sub("0+$", "", parcalar[2]) else ""
  anahtar <- if (nzchar(kesir)) paste0(tam, ".", kesir) else tam
  if (identical(anahtar, "0")) return("0")
  paste0(if (eksi) "-" else "", anahtar)
}

# İstek değeri / model jetonu için ortak arama anahtarı ("1000" ya da
# "1000|saat"). Birim taşıyan bir iddia, birimi olmayan bir eşikle eşleşmez.
.pk_scan_lookup_keys <- function(anahtar, birim) {
  if (!nzchar(anahtar)) return(character(0))
  if (nzchar(birim)) c(anahtar, paste0(anahtar, "|", birim)) else anahtar
}

#' Paketteki GÜVENİLİR İSTEK değerlerinin karşılaştırma anahtarları
#'
#' Yalnızca `kind == "request_input"` olguları sayılır. Analitik ölçü olguları
#' BİLEREK dışarıdadır: modelin bir ölçü değerini elle yazması tam da bu
#' mimarinin ortadan kaldırdığı davranıştır.
#'
#' Anahtarlar YALNIZCA ham istek METNİNDEN üretilir. Ayrıştırılmış sayısal alan
#' binlik ayracını kaybedip (`12.500` -> `12,5`) ilgisiz bir anahtar üretiyordu.
pk_fact_trusted_input_keys <- function(facts) {
  anahtarlar <- character(0)
  for (olgu in (facts %||% list())) {
    if (!is.list(olgu)) next
    if (!identical(as.character(olgu$kind %||% "")[1], "request_input")) next
    ham <- c(as.character(olgu$request_values %||% character(0)),
             as.character(olgu$display %||% character(0)))
    for (parca in ham) {
      ayrisik <- .pk_scan_parse_token(trimws(parca))
      anahtar <- pk_fact_number_key(ayrisik$number_text)
      if (!nzchar(anahtar)) next
      anahtarlar <- c(anahtarlar,
                      .pk_scan_lookup_keys(anahtar, pk_fact_unit_key(ayrisik)))
    }
  }
  unique(anahtarlar)
}

#' Model düzyazısındaki BEKLENMEYEN sayısal materyali yapısal olarak bul
#'
#' @param text Model metni (referans jetonları hâlâ yerinde).
#' @param trusted_keys `pk_fact_trusted_input_keys()` çıktısı.
#' @return `list(tokens = list(list(start=, end=, raw=, number_end=,
#'   scale_unit=)), trusted = list(...))` — konumlar ÖZGÜN metin
#'   koordinatlarındadır. `number_end` rakam dizisinin son konumudur; yinelenen
#'   bir iddia silinirken jetona iliştirilmiş sıradan sözcük KORUNSUN diye ayrı
#'   taşınır. `trusted` güvenilir istek değeriyle eşleşen jetonlardır (ihlal
#'   DEĞİL; eşleşen anahtar `key` alanındadır).
pk_fact_literal_scan <- function(text, trusted_keys = character(0)) {
  txt <- suppressWarnings(as.character(text %||% "")[1])
  if (length(txt) != 1L || is.na(txt) || !nzchar(txt)) return(list(tokens = list()))

  maskeli <- .pk_scan_mask_references(txt)
  konum <- gregexpr(.PK_SCAN_NUMBER_PATTERN, maskeli, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list(tokens = list()))

  uzunluk <- attr(konum, "match.length")
  guvenilir <- as.character(trusted_keys %||% character(0))
  out <- list()
  guvenli <- list()

  for (i in seq_along(konum)) {
    jeton <- .pk_scan_token_at(maskeli, as.integer(konum[i]),
                               as.integer(konum[i]) + as.integer(uzunluk[i]) - 1L)
    if (is.null(jeton)) next

    kayit <- list(
      start = jeton$start, end = jeton$end,
      number_end = jeton$number_end,
      scale_unit = pk_fact_unit_key(jeton$parsed),
      raw = substr(txt, jeton$start, jeton$end)
    )
    # GÜVENİLİR İSTEK DEĞERİ ihlal değildir ama AYRI taşınır: kendi yuvasının
    # yanında yinelenirse ("Son 6 ay {{yuva}}") çözücü yinelemeyi temizler.
    anahtar <- .pk_scan_trusted_key(jeton, guvenilir)
    if (nzchar(anahtar)) {
      kayit$key <- anahtar
      guvenli[[length(guvenli) + 1L]] <- kayit
      next
    }
    if (.pk_scan_is_exempt(maskeli, jeton)) next

    out[[length(out) + 1L]] <- kayit
  }

  list(tokens = out, trusted = guvenli)
}

# Jeton kullanıcının güvenilir bir istek değeriyle mi eşleşiyor? Birim de
# karşılaştırmaya girer; `1000` eşiği `1.000 saat` iddiasını kapsamaz.
# Eşleşen anahtarı, yoksa "" döndürür.
.pk_scan_trusted_key <- function(jeton, guvenilir) {
  if (!length(guvenilir)) return("")
  anahtar <- pk_fact_number_key(jeton$parsed$number_text)
  if (!nzchar(anahtar)) return("")
  birim <- pk_fact_unit_key(jeton$parsed)
  aranan <- if (nzchar(birim)) paste0(anahtar, "|", birim) else anahtar
  if (aranan %in% guvenilir) aranan else ""
}

# Ham eşleşmeyi ANLAMLI sınırlara oturtur ve parçalarını çözer. `NULL` dönerse
# eşleşme bir sayı jetonu değildir.
.pk_scan_token_at <- function(maskeli, bas, son) {
  # Eşleşme sondaki boşluğu da yutabilir; jeton ANLAMLI karakterlerle sınırlanır.
  tam <- substr(maskeli, bas, son)
  sol <- sub("^[[:space:]\u00a0]+", "", tam)
  sag <- sub("[[:space:]\u00a0]+$", "", sol)
  bas <- bas + (nchar(tam) - nchar(sol))
  son <- bas + nchar(sag) - 1L
  if (son < bas || !nzchar(sag)) return(NULL)

  ayrisik <- .pk_scan_parse_token(sag)
  rakam <- ayrisik$number_text
  if (!nzchar(rakam)) return(NULL)

  # Sondaki noktalama jetonun parçası değildir (`15.448.` -> `15.448`).
  kuyruk <- regmatches(sag, regexpr("[.,]+$", sag, perl = TRUE))
  if (length(kuyruk) && nzchar(kuyruk[1]) && !grepl("[.,]$", rakam, perl = TRUE)) {
    son <- son - nchar(kuyruk[1])
    sag <- substr(sag, 1L, nchar(sag) - nchar(kuyruk[1]))
    if (son < bas || !nzchar(sag)) return(NULL)
  }

  rk <- regexpr("-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?", sag, perl = TRUE)
  if (identical(as.integer(rk), -1L)) return(NULL)
  rakam_bas <- bas + as.integer(rk) - 1L

  list(start = bas, end = son, number_start = rakam_bas,
       number_end = rakam_bas + nchar(rakam) - 1L, text = sag, parsed = ayrisik)
}

# Bir jeton veri iddiası SAYILMAZ mı? (muafiyetler + "veri gibi" kapısı)
#
# Muafiyetler: teknik kimlik, tarih, çıplak yıl, madde numarası (güvenilir
# istek değeri `.pk_scan_trusted_key()` ile AYRICA ele alınır). Kapı: ayraç /
# yüzde / para birimi / bilimsel gösterim / 4+ hane / ölçek taşıyan birim /
# oran biçimi.
.pk_scan_is_exempt <- function(maskeli, jeton) {
  ayrisik <- jeton$parsed
  rakam <- ayrisik$number_text
  yuzde <- isTRUE(ayrisik$percent)
  birim <- pk_fact_unit_key(ayrisik)

  # TEKNİK KİMLİK: `P1234`, `A1000`, `ISO9001` içindeki rakam bir ölçü değildir.
  onceki <- if (jeton$start > 1L) substr(maskeli, jeton$start - 1L, jeton$start - 1L) else ""
  if (nzchar(onceki) && grepl(paste0("^", .PK_SCAN_IDENT_CHAR, "$"), onceki, perl = TRUE)) {
    return(TRUE)
  }
  # NOKTALI/TİRELİ KOD (`P.01.02`, `A-12`): ayraçtan önce kimlik karakteri var.
  if (onceki %in% c(".", "-", "/") && jeton$start > 2L &&
      grepl(paste0("^", .PK_SCAN_IDENT_CHAR, "$"),
            substr(maskeli, jeton$start - 2L, jeton$start - 2L), perl = TRUE)) {
    return(TRUE)
  }
  # ÇOK AYRAÇLI SAYI OLMAYAN DİZİ (`1.2.3` WBS kodu, `10.0.0.1`) bir ölçü değildir.
  # Binlik gruplu geçerli sayı (`1.234.567`) kanonik anahtar ürettiği için MUAF
  # DEĞİLDİR; yüzde ve bilimsel gösterim de muaf değildir.
  if (!isTRUE(ayrisik$percent) && !grepl("[eE]", rakam) &&
      lengths(regmatches(rakam, gregexpr("[.,]", rakam))) >= 2L &&
      !nzchar(pk_fact_number_key(rakam))) {
    return(TRUE)
  }

  # Tarih (gg.aa.yyyy / gg-aa-yyyy / yyyy-aa-gg) bir ölçü değildir.
  if (!yuzde && .pk_scan_date_context(maskeli, jeton$number_start, jeton$number_end)) {
    return(TRUE)
  }

  if (.pk_scan_list_marker(maskeli, jeton, rakam, yuzde)) return(TRUE)

  ayrac <- grepl("[.,]", rakam, perl = TRUE)
  bilimsel <- grepl("[eE][+-]?[0-9]+$", rakam, perl = TRUE)
  sade <- gsub("[^0-9]", "", rakam)
  haneler <- nchar(sade)

  # Çıplak yıl (1900-2100) bir ölçü değildir; ölçek taşıyan birim yorumu bozar.
  yil_gibi <- !grepl("^-", rakam, perl = TRUE) && !bilimsel && !ayrac && !yuzde &&
    haneler == 4L && !nzchar(birim) &&
    suppressWarnings(!is.na(as.integer(sade))) &&
    as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
  if (isTRUE(yil_gibi)) return(TRUE)

  veri_gibi <- ayrac || yuzde || bilimsel || haneler >= 4L || nzchar(birim) ||
    .pk_scan_ratio_context(maskeli, jeton$number_start, jeton$number_end)
  !veri_gibi
}

# Madde numarası mı? Denetim RAKAM DİZİSİNE ve onu izleyen ayraca bakar; jetona
# iliştirilmiş birim sözcüğü ("1. saat planlamasi") önekten kopmaz.
.pk_scan_list_marker <- function(maskeli, jeton, rakam, yuzde) {
  if (yuzde || !grepl("^[0-9]{1,2}$", rakam, perl = TRUE)) return(FALSE)

  satir_bas <- .pk_scan_line_start(maskeli, jeton$start)
  onek <- if (jeton$start > satir_bas) {
    substr(maskeli, satir_bas, jeton$start - 1L)
  } else {
    ""
  }
  if (!grepl(.PK_SCAN_LIST_PREFIX, onek, perl = TRUE)) return(FALSE)

  ayrac <- substr(maskeli, jeton$number_end + 1L, jeton$number_end + 1L)
  if (!grepl("^[.)]$", ayrac, perl = TRUE)) return(FALSE)
  sonraki <- substr(maskeli, jeton$number_end + 2L, jeton$number_end + 2L)
  !nzchar(sonraki) || grepl("^[[:space:]\u00a0]$", sonraki, perl = TRUE)
}

# Rakam dizisi bir TARİH dizisinin parçası mı? Noktalı biçim zaten muaftı;
# tireli gün-önce biçimi (`31-12-2024`) ayrıştırıcıda `-2024` gibi NEGATİF bir
# ölçü gibi görünüyor ve `block` kipinde cümleyi düşürüyordu.
.pk_scan_date_context <- function(maskeli, bas, son) {
  desenler <- c("(?<![0-9])[0-9]{1,2}[-.][0-9]{1,2}[-.][0-9]{4}(?![0-9])",
                "(?<![0-9])[0-9]{4}[-.][0-9]{1,2}[-.][0-9]{1,2}(?![0-9])")
  .pk_scan_window_hit(maskeli, bas, son, desenler, function(dizi) TRUE)
}

# Rakam dizisi bir ORAN biçiminin (`1/2`, `3:2`) parçası mı? Saat ve bölü
# biçimli tarih HARİÇTİR; oran modelin yaptığı bir aritmetik iddiadır.
.pk_scan_ratio_context <- function(maskeli, bas, son) {
  .pk_scan_window_hit(
    maskeli, bas, son, "(?<![0-9])[0-9]+(?:[/:][0-9]+)+(?![0-9])",
    function(dizi) {
      saat <- grepl("^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", dizi, perl = TRUE)
      tarih <- grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$", dizi, perl = TRUE) ||
        grepl("^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}$", dizi, perl = TRUE)
      !saat && !tarih
    }
  )
}

# `bas..son` aralığını KAPSAYAN bir bağlam dizisi var mı? Pencere sınırlıdır;
# tüm metin taranmaz.
.pk_scan_window_hit <- function(maskeli, bas, son, desenler, kabul) {
  pencere_bas <- max(1L, bas - .PK_SCAN_CONTEXT_WINDOW)
  pencere_son <- min(nchar(maskeli), son + .PK_SCAN_CONTEXT_WINDOW)
  if (pencere_son < pencere_bas) return(FALSE)
  pencere <- substr(maskeli, pencere_bas, pencere_son)

  for (desen in desenler) {
    konum <- gregexpr(desen, pencere, perl = TRUE)[[1]]
    if (identical(konum[1], -1L)) next
    uzunluk <- attr(konum, "match.length")
    for (i in seq_along(konum)) {
      b <- pencere_bas + as.integer(konum[i]) - 1L
      s <- b + as.integer(uzunluk[i]) - 1L
      if (son < b || bas > s) next
      if (isTRUE(kabul(substr(maskeli, b, s)))) return(TRUE)
    }
  }
  FALSE
}
