# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance_binding.R
# Açıklama: Sayısal iddia BAĞLAMA katmanı — master plan §5.11.
#
#           ÜRETİM KUSURU (bu dosyanın var oluş nedeni): doğru sayılar taşıyan
#           9.551 karakterlik bir analiz yanıtı `block` kipinde
#           `iddia=116 | uyusmazlik=36` ile REDDEDİLİYORDU. Model doğal Türkçe
#           yazdığında değerleri sıralayıp işaretleri SONA topluyor:
#
#             "... zamanında bitenler 27.707, gecikenler 15.448, erken bitenler
#              3.823 olarak gözleniyor [fact:a][fact:b][fact:c]."
#
#           Eski tarayıcı yalnızca İLK işareti bir sayıya bağlıyor, o sayıyı da
#           YANLIŞ seçiyordu (en sağdaki `3.823`); kalan iki işaret boş pencere
#           görüp `no_number`, önceki iki sayı ise `missing_fact_marker`
#           sayılıyordu. TEK bir doğru cümle 1 `value_mismatch` + 2 `no_number`
#           + 2 `missing_fact_marker` üretiyordu.
#
#           ÇÖZÜM: metin TEK BİR geçişte çözümlenir. Bitişik işaretler bir GRUP
#           oluşturur ve grup, kendinden önceki AYNI cümle parçasındaki son `k`
#           sayıya SIRAYLA bağlanır (k = gruptaki işaret sayısı). Böylece:
#             * her sayı KENDİ olgusuna karşı doğrulanır (değer denetimi aynen
#               çalışır; yanlış sayı yine yakalanır),
#             * bağlanan sayı köken-siz sayılamaz (çift sayım yapısal olarak
#               biter; iki ayrı tarayıcının bitişiklik kuralı ARTIK YOKTUR).
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yükleme sırası: `R/helpers_pk_numeric_provenance.R` dosyasından
#           SONRA, `R/helpers_pk_numeric_provenance_claims.R` dosyasından ÖNCE.
# ==============================================================================

# Bağlama penceresi: taban + her ek işaret için pay. Cümle sınırı ve önceki
# işaret grubu zaten kesici sınırlardır; bu yalnızca üst bir tavan koyar.
.PK_PROV_SEGMENT_BASE_CHARS <- 320L
.PK_PROV_SEGMENT_PER_MARKER_CHARS <- 80L

# Bir grupta yeniden eşleştirme denenecek en büyük işaret sayısı. Gruplar
# pratikte 2-4 işarettir; tavan, patolojik bir girdinin arama maliyetini bağlar.
.PK_PROV_MAX_GROUP <- 8L

# İki işaret arasında YALNIZCA bu karakterler varsa işaretler AYNI gruptadır.
# `.`/`!`/`?` BİLEREK dışarıdadır: onlar cümle sınırıdır ve iki ayrı iddiayı
# birbirine bağlamamalıdır.
.PK_PROV_GROUP_JOINER <- "^[[:space:]\u00a0*`~_,;:\\-]*$"

# Sayı jetonu deseni. Alıntılı ve alıntısız tarama AYNI deseni kullanır; iki
# tarayıcının ayrışması üretimde çift sayımın kaynağıydı.
.PK_PROV_NUMBER_PATTERN <- paste0(
  "(%\\s*)?-?[0-9][0-9.,]*\\s*",
  "(%|[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac]",
  "[A-Za-z0-9ÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac/.-]{0,23})?"
)

#' İşaretleri aynı uzunlukta bir nöbetçiyle maskele
#'
#' Olgu kimlikleri RAKAM içerir (`...3b150a`, `...217683`); maskelenmezse sayı
#' tarayıcısı işaretin İÇİNİ sayı sanardı. Maskeleme KARAKTER SAYISINI korur,
#' böylece konumlar özgün metinle birebir hizalı kalır.
.pk_prov_mask_markers <- function(txt) {
  konum <- gregexpr(.PK_PROV_MARKER, txt, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) {
    return(list(masked = txt, starts = integer(0), ends = integer(0),
                ids = character(0)))
  }

  uzunluk <- attr(konum, "match.length")
  karakterler <- strsplit(txt, "", fixed = TRUE)[[1]]
  nobetci <- intToUtf8(1L)
  ids <- character(length(konum))

  for (i in seq_along(konum)) {
    bas <- konum[i]
    son <- bas + uzunluk[i] - 1L
    isaret <- paste0(karakterler[bas:son], collapse = "")
    ids[i] <- sub("^\\[fact:", "", sub("\\]$", "", isaret))
    karakterler[bas:son] <- nobetci
  }

  list(masked = paste0(karakterler, collapse = ""),
       starts = as.integer(konum),
       ends = as.integer(konum) + as.integer(uzunluk) - 1L,
       ids = ids)
}

#' Bitişik işaretleri gruplara ayır
#'
#' Aralarında yalnızca boşluk/vurgu/virgül bulunan işaretler TEK bir iddia
#' kümesidir; cümle sonu noktalaması grubu KAPATIR.
.pk_prov_marker_groups <- function(txt, isaretler) {
  n <- length(isaretler$starts)
  if (!n) return(list())

  gruplar <- list()
  ilk <- 1L

  for (i in seq_len(n)) {
    son_grup <- i == n
    if (!son_grup) {
      ara <- substr(txt, isaretler$ends[i] + 1L, isaretler$starts[i + 1L] - 1L)
      if (grepl(.PK_PROV_GROUP_JOINER, ara, perl = TRUE)) next
    }
    gruplar[[length(gruplar) + 1L]] <- list(
      indices = ilk:i,
      ids = isaretler$ids[ilk:i],
      start = isaretler$starts[ilk],
      end = isaretler$ends[i]
    )
    ilk <- i + 1L
  }

  gruplar
}

#' Bir sayı jetonunu ayrıştır
#'
#' Sondaki `.`/`,` AYRAÇ DEĞİLDİR (`27.707,` -> `27.707`); bu kırpma iki
#' tarayıcıda da AYNI yapılmalıdır, aksi hâlde aynı sayı iki farklı değere
#' çözülür.
.pk_prov_parse_token <- function(ham) {
  yuzde <- grepl("%", ham, fixed = TRUE)
  govde <- trimws(gsub("%", "", ham))
  birim <- trimws(sub("^-?[0-9][0-9.,]*\\s*", "", govde))
  rakam <- regmatches(govde, regexpr("^-?[0-9][0-9.,]*", govde))
  rakam <- if (length(rakam)) sub("[.,]+$", "", rakam[1]) else ""
  list(raw = ham, number_text = rakam, unit = birim, percent = yuzde)
}

#' Maskelenmiş metindeki tüm sayı jetonlarını konumlarıyla bul
#'
#' Madde numarası (`1.` satır başında) bir ÖLÇÜ değildir ve bağlama adayı
#' sayılmaz; aksi hâlde "1. Öneri: 5.000 TL [fact:a][fact:b]" gibi bir satırda
#' madde numarası bir olguya bağlanırdı.
.pk_prov_number_tokens <- function(masked) {
  konum <- gregexpr(.PK_PROV_NUMBER_PATTERN, masked, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())
  uzunluk <- attr(konum, "match.length")

  out <- list()
  for (i in seq_along(konum)) {
    bas <- konum[i]
    son <- bas + uzunluk[i] - 1L
    ham <- trimws(substr(masked, bas, son))
    if (!nzchar(ham)) next

    # JETON UZANTISI ANLAMLI KARAKTERLERLE SINIRLIDIR. Desendeki `\\s*`
    # açgözlüdür ve eşleşmeye SONDAKİ boşluğu da katar; kaydedilen bitiş konumu
    # o boşluğu içerdiğinde jeton, parça sınırının (boşluğu kırpılmış) DIŞINDA
    # kalıyor ve DOĞRU bir alıntı "işaret var, sayı yok" sayılıyordu.
    tam <- substr(masked, bas, son)
    sol <- sub("^[[:space:]\u00a0]+", "", tam)
    sag <- sub("[[:space:]\u00a0]+$", "", sol)
    bas <- bas + (nchar(tam) - nchar(sol))
    son <- bas + nchar(sag) - 1L
    ham <- sag
    if (son < bas || !nzchar(ham)) next

    ayrisik <- .pk_prov_parse_token(ham)
    if (!nzchar(ayrisik$number_text)) next

    onceki <- if (bas > 1L) substr(masked, bas - 1L, bas - 1L) else "\n"
    sonraki <- if (son < nchar(masked)) substr(masked, son + 1L, son + 1L) else ""
    madde <- grepl("^[\n\r]?$", onceki, perl = TRUE) &&
      grepl("^[0-9]+[.)]?$", ham, perl = TRUE) &&
      grepl("^[.)]$", sonraki, perl = TRUE)
    if (isTRUE(madde)) next

    # RAKAMLARIN BİTİŞİ AYRICA KAYDEDİLİR. Eşleşme, sayıyı izleyen JETONU da
    # (birim adayı) içerir; bir sonraki sayının bağlamı yalnızca `end` sonrasından
    # başlatılırsa o sözcük GİZLENİR ve "Toplam 50.367, ortalama 57" ifadesinde
    # ikinci sayının toplulaştırma sözcüğü hiç görünmezdi.
    rakam_konumu <- regexpr("-?[0-9][0-9.,]*", ham, perl = TRUE)
    rakam_sonu <- if (rakam_konumu[1] > 0L) {
      bas + rakam_konumu[1] + attr(rakam_konumu, "match.length") - 2L
    } else {
      son
    }

    out[[length(out) + 1L]] <- c(ayrisik,
                                 list(start = bas, end = son, number_end = rakam_sonu))
  }
  out
}

#' Yalnızca SONDAN kırp (konum hizası korunur)
#'
#' Vurgu imleri, noktalama ve Türkçe kesme eki anlam taşımaz; ancak segment
#' sınırı karakter konumuyla hesaplandığı için metnin İÇİ değiştirilemez.
.pk_prov_trim_tail_only <- function(txt) {
  metin <- as.character(txt %||% "")[1]
  if (is.na(metin)) return("")

  kuyruk <- paste0("(", .PK_PROV_EMPHASIS, "|", .PK_PROV_TRAILING, ")+$")
  onceki <- ""
  while (!identical(onceki, metin)) {
    onceki <- metin
    metin <- sub("['’][A-Za-zÇĞİÖŞÜçğıöşü]*$",
                 "", metin, perl = TRUE)
    metin <- sub(kuyruk, "", metin, perl = TRUE)
  }
  metin
}

#' Bir işaret grubunun bağlama parçasını (segment) çöz
#'
#' Sınırlar: önceki grubun SONU, son cümle sınırı ve karakter tavanı. Cümle
#' sınırı ondalık/binlik noktayı SAYMAZ (`18.420` -> `420` olurdu).
.pk_prov_segment_bounds <- function(masked, grup, onceki_son) {
  tavan <- .PK_PROV_SEGMENT_BASE_CHARS +
    .PK_PROV_SEGMENT_PER_MARKER_CHARS * length(grup$ids)
  bas <- max(1L, onceki_son + 1L, grup$start - tavan)
  son <- grup$start - 1L
  if (son < bas) return(NULL)

  parca <- substr(masked, bas, son)
  # Kuyruk ÖNCE kırpılır, cümle sınırı SONRA aranır: işarete komşu nokta
  # (`... bulundu. [fact:f]`) cümle sınırı sayılırsa pencere boşalır.
  #
  # KIRPMA YALNIZCA SONDANDIR. `.pk_prov_trim_tail()` vurgu imlerini metnin
  # İÇİNDEN de siler; uzunluk farkı konum hizasını bozar ve segment sınırı
  # yanlış yere düşer.
  kirpik <- .pk_prov_trim_tail_only(parca)
  son <- bas + nchar(kirpik) - 1L
  if (son < bas) return(NULL)

  cumle <- gregexpr("[.!?](?=\\s|$)", kirpik, perl = TRUE)[[1]]
  if (!identical(cumle[1], -1L)) {
    bas <- bas + cumle[length(cumle)]
  }
  if (son < bas) return(NULL)
  list(start = bas, end = son)
}

#' Metni TEK geçişte çözümle: işaret grupları, sayı jetonları ve bağlama
#'
#' @return `list(groups=, tokens=, bound=)` — `groups` her biri `ids` ve
#'   `tokens` (sıralı aday sayı indeksleri) taşır; `bound` bağlanan jeton
#'   indekslerinin kümesidir.
pk_prov_bind_text <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) {
    return(list(groups = list(), tokens = list(), bound = integer(0)))
  }

  isaretler <- .pk_prov_mask_markers(txt)
  masked <- isaretler$masked
  jetonlar <- .pk_prov_number_tokens(masked)
  gruplar <- .pk_prov_marker_groups(txt, isaretler)

  baslangiclar <- vapply(jetonlar, function(j) j$start, integer(1))
  bitisler <- vapply(jetonlar, function(j) j$end, integer(1))

  bagli <- integer(0)
  onceki_son <- 0L
  cikti <- list()

  for (grup in gruplar) {
    sinir <- .pk_prov_segment_bounds(masked, grup, onceki_son)
    onceki_son <- grup$end

    adaylar <- integer(0)
    if (!is.null(sinir) && length(jetonlar)) {
      icinde <- which(baslangiclar >= sinir$start & bitisler <= sinir$end)
      # Gruptaki işaret sayısı kadar SON aday alınır: daha geniş bir küme,
      # aynı cümledeki alıntılanmamış bir sayının sessizce "kabul edilmesine"
      # yol açardı (köken zorunluluğu tam da bunu engeller).
      if (length(icinde) > length(grup$ids)) {
        icinde <- utils::tail(icinde, length(grup$ids))
      }
      adaylar <- icinde
    }

    bagli <- c(bagli, adaylar)
    cikti[[length(cikti) + 1L]] <- list(
      ids = grup$ids,
      tokens = adaylar,
      segment_start = if (is.null(sinir)) grup$start else sinir$start
    )
  }

  list(groups = cikti, tokens = jetonlar, bound = unique(bagli))
}

#' Bir jetonun toplulaştırma bağlamını üret
#'
#' Bağlam, bu sayıdan ÖNCEKİ ve bir önceki adaydan SONRAKİ metindir; böylece
#' "proje başına ortalama 149, medyan 57" ifadesinde her sayı KENDİ
#' toplulaştırma sözcüğünü görür. Ortak pencere kullanıldığında en sağdaki
#' sözcük hepsini eziyordu.
pk_prov_token_context <- function(masked, jetonlar, idx, segment_start, onceki_idx = NA_integer_) {
  bas <- segment_start
  if (!is.na(onceki_idx) && onceki_idx >= 1L) {
    bas <- max(bas, jetonlar[[onceki_idx]]$number_end + 1L)
  }
  son <- jetonlar[[idx]]$start - 1L
  if (son < bas) return("")
  substr(masked, bas, son)
}

#' Grup içi kısıtlı yeniden eşleştirme (tam eşleme arayışı)
#'
#' Model işaretleri değerlerden FARKLI sırada yazdığında konumsal eşleme tüm
#' grubu reddeder; oysa her sayı yine de KENDİ olgusuna eşittir. Bu, biçim/
#' sıralama kusurudur, sayısal hata DEĞİLDİR. Uzlaştırma HİÇBİR değer üretmez:
#' yalnızca AYNI aday kümesi ile AYNI işaret kümesi arasında, her çiftin değer
#' denetiminden GEÇTİĞİ bir birebir eşleme arar. Böyle bir eşleme yoksa
#' konumsal eşleme korunur ve gerçek uyuşmazlıklar raporlanır.
pk_prov_repair_pairing <- function(uygun) {
  k <- nrow(uygun)
  if (!is.matrix(uygun) || k == 0L || ncol(uygun) != k) return(NULL)

  eslesme <- rep(NA_integer_, k)   # aday -> işaret
  durum <- new.env(parent = emptyenv())

  dene <- function(i) {
    for (j in seq_len(k)) {
      if (!isTRUE(uygun[i, j]) || isTRUE(durum$ziyaret[j])) next
      durum$ziyaret[j] <- TRUE
      if (is.na(eslesme[j]) || dene(eslesme[j])) {
        eslesme[j] <<- i
        return(TRUE)
      }
    }
    FALSE
  }

  for (i in seq_len(k)) {
    durum$ziyaret <- rep(FALSE, k)
    if (!dene(i)) return(NULL)
  }

  # işaret -> aday yönüne çevir
  sonuc <- rep(NA_integer_, k)
  for (j in seq_len(k)) sonuc[eslesme[j]] <- j
  sonuc
}
