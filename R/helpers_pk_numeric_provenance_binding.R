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
#
# ÖNEK PARA BİRİMİ VE ÜSTEL GÖSTERİM DESENE DAHİLDİR (PR #719 inceleme, P2).
# Eski desen `\u20ba100` / `$100` jetonunu yalnızca `100` olarak, `1e6` jetonunu
# ise `1` + tanınmayan `e6` birimi olarak görüyordu. Her iki durumda da veri
# görünümü kapısı (ayraç/yüzde/birim/4+ hane) kapanıyor ve alıntılanmamış sayı
# `warn`/`block` kiplerinde `missing_fact_marker` ÜRETMEDEN yayımlanıyordu.
.PK_PROV_NUMBER_PATTERN <- paste0(
  "(%\\s*)?[\u20ba$\u20ac]?\\s*-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?\\s*",
  "(%|[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac]",
  "[A-Za-z0-9ÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac/.-]{0,23})?"
)

# Sayının ÖNÜNDE yazılan para birimi -> sözlükteki kanonik birim adı. Eşleme
# bilinçli olarak DARDIR: yalnızca `.PK_PROV_KNOWN_UNITS` içinde karşılığı olan
# simgeler taşınır, aksi hâlde tanınmayan bir birim uydurmuş oluruz.
.PK_PROV_PREFIX_CURRENCIES <- c("\u20ba" = "TL", "$" = "USD", "\u20ac" = "EUR")

# Sayı ile işaret arasındaki EN BÜYÜK sözcük mesafesi. Doğal Türkçe düzyazıda
# üretimde ölçülen en uzun geçerli aralık altı sözcüktür
# ("46.978 ile toplam aktivitelerin buyuk bolumunu olusturuyor [fact:f]");
# tavan bunun üstünde tutulur ama SINIRSIZ DEĞİLDİR: sınır olmadan uzun bir
# cümlenin BAŞINDAKİ ilgisiz yıl ("2024 yilinda ... dikkat cekicidir
# [fact:geciken]") işarete bağlanıp `value_mismatch` üretiyor ve `block`
# kipinde GEÇERLİ yanıtı düşürüyordu.
.PK_PROV_MAX_GAP_WORDS <- 12L

# Madde imi satırı: işaretin önünde yalnızca bu karakterler varsa satır başıdır.
.PK_PROV_LIST_PREFIX <- "^[[:space:]\u00a0*`_>\\-]*$"
.PK_PROV_LIST_NUMBER <- "^[0-9]+[.)][[:space:]\u00a0]"

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

  # ÖNEK PARA BİRİMİ SAYININ PARÇASIDIR. Eski ayrıştırıcı `^-?[0-9]` beklediği
  # için `\u20ba100` gövdesinden hiç rakam çıkaramıyor, jeton tamamen
  # düşüyordu; alıntılanmamış bir tutar böylece köken denetimini ATLIYORDU.
  onek <- ""
  onek_esle <- regmatches(govde, regexpr("^[\u20ba$\u20ac]", govde))
  if (length(onek_esle) && nzchar(onek_esle[1])) {
    # `[[` eşleşmeyen bir adda HATA fırlatır; `[` NA döndürür ve NA burada
    # "birim yok" demektir (desen ile eşleme tablosu ayrışırsa fail-safe).
    onek <- unname(.PK_PROV_PREFIX_CURRENCIES[onek_esle[1]])
    if (length(onek) != 1L || is.na(onek)) onek <- ""
    govde <- trimws(substring(govde, nchar(onek_esle[1]) + 1L))
  }

  birim <- trimws(sub("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?\\s*", "", govde))
  rakam <- regmatches(govde, regexpr("^-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?", govde))
  rakam <- if (length(rakam)) sub("[.,]+$", "", rakam[1]) else ""
  if (!nzchar(birim)) birim <- onek
  list(raw = ham, number_text = rakam, unit = birim, percent = yuzde)
}

#' Bir aralıktaki sözcük sayısını say (bitişiklik denetimi için)
#'
#' İşaret nöbetçisi (U+0001) ve noktalama sözcük SAYILMAZ; yalnızca harf/rakam
#' taşıyan kümeler sayılır.
.pk_prov_gap_words <- function(masked, bas, son) {
  if (son < bas || bas < 1L) return(0L)
  parca <- substr(masked, bas, son)

  # AYRAÇ YALNIZCA BOŞLUKTUR, "ASCII OLMAYAN HER ŞEY" DEĞİL.
  #
  # PCRE'de `[:alnum:]` varsayılan olarak YALNIZCA ASCII eşler (`(*UCP)` yok).
  # Türkçe harfleri ayraç sayan bir bölme `gecikme egilimi` ifadesini DÖRT
  # yerine BEŞ sözcük sayıyor, mesafe tavanı Türkçe düzyazıda sistematik olarak
  # DARALIYOR ve bu PR'ın kapattığı yanlış pozitif geri gelebiliyordu.
  parcalar <- strsplit(parca, "[[:space:]\u00a0\u0001]+", perl = TRUE)[[1]]
  parcalar <- parcalar[nzchar(parcalar)]

  # Salt noktalama (`,` `-` `:`) sözcük SAYILMAZ; harf/rakam taşıması gerekir.
  # ASCII olmayan harfler (Türkçe) açıkça sözcük karakteri sayılır.
  sum(grepl("[[:alnum:]]|[^\\x00-\\x7F]", parcalar, perl = TRUE))
}

#' Aday sayıları BİTİŞİKLİK kuralına göre ele
#'
#' Adaylar işarete EN YAKINDAN başlayarak kabul edilir; bir aday ile bir sonraki
#' kabul edilen öge (ya da işaret grubunun kendisi) arasındaki sözcük mesafesi
#' tavanı aşarsa o aday ve ONDAN ÖNCEKİLERİN TAMAMI düşer. Aksi hâlde uzun bir
#' cümlenin başındaki ilgisiz bir sayı (tipik olarak bir yıl) işarete bağlanır.
.pk_prov_adjacent_candidates <- function(masked, adaylar, jetonlar, grup_basi) {
  if (!length(adaylar)) return(integer(0))

  kabul <- integer(0)
  capa <- grup_basi
  for (i in rev(seq_along(adaylar))) {
    idx <- adaylar[i]
    mesafe <- .pk_prov_gap_words(masked, jetonlar[[idx]]$end + 1L, capa - 1L)
    if (mesafe > .PK_PROV_MAX_GAP_WORDS) break
    kabul <- c(idx, kabul)
    capa <- jetonlar[[idx]]$start
  }
  kabul
}

#' Bir konumun bulunduğu satırın başlangıç indeksi
.pk_prov_line_start <- function(masked, konum) {
  if (konum <= 1L) return(1L)
  kesme <- gregexpr("[\n\r]", substr(masked, 1L, konum - 1L), perl = TRUE)[[1]]
  if (identical(kesme[1], -1L)) 1L else as.integer(kesme[length(kesme)]) + 1L
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

    # MADDE NUMARASI DESENİN İÇİNE SIZABİLİR (PR #719 inceleme, P2).
    #
    # Desen sayıyı izleyen sözcüğü de yutar: "1. Öneri: 5.000 TL" satırında
    # jeton `1. Öneri` olur, `^[0-9]+[.)]?$` kalıbı artık TUTMAZ ve madde
    # numarası bir olguya BAĞLANABİLİR hâle gelirdi. Bu yüzden satır ÖNEKİ
    # ayrıca sınanır: satır başında `1.`/`1)` + boşluk bir listedir.
    satir_bas <- .pk_prov_line_start(masked, bas)
    onek <- if (bas > satir_bas) substr(masked, satir_bas, bas - 1L) else ""
    satir_basi <- grepl(.PK_PROV_LIST_PREFIX, onek, perl = TRUE)

    madde <- satir_basi && (
      (grepl("^[0-9]+[.)]?$", ham, perl = TRUE) &&
         grepl("^[.)]$", sonraki, perl = TRUE)) ||
        (grepl("^[0-9]{1,2}[.)]$", ham, perl = TRUE) &&
           grepl("^[[:space:]\u00a0]$", sonraki, perl = TRUE)) ||
        grepl(.PK_PROV_LIST_NUMBER, ham, perl = TRUE)
    )
    if (isTRUE(madde)) next

    # SONDAKİ NOKTALAMA JETONUN PARÇASI DEĞİLDİR.
    #
    # `15.574. [fact:f]` biçiminde desen sondaki noktayı da yutar; ayrıştırıcı
    # onu `number_text` içinden atar ama KAYITLI BİTİŞ konumu noktayı içermeye
    # devam ederdi. Segment sınırı kuyruğu kırptığı için jeton içerilme
    # denetiminden düşüyor, işaret sayısız kalıyor ve `15.574` alıntılanmamış
    # sayılıyordu.
    kuyruk <- regmatches(ham, regexpr("[.,]+$", ham, perl = TRUE))
    if (length(kuyruk) && nzchar(kuyruk[1]) &&
        !grepl("[.,]$", ayrisik$number_text, perl = TRUE)) {
      kirpilan <- nchar(kuyruk[1])
      son <- son - kirpilan
      ham <- substr(ham, 1L, nchar(ham) - kirpilan)
      if (son < bas || !nzchar(ham)) next
      ayrisik$raw <- ham
    }

    # RAKAMLARIN BİTİŞİ AYRICA KAYDEDİLİR. Eşleşme, sayıyı izleyen JETONU da
    # (birim adayı) içerir; bir sonraki sayının bağlamı yalnızca `end` sonrasından
    # başlatılırsa o sözcük GİZLENİR ve "Toplam 50.367, ortalama 57" ifadesinde
    # ikinci sayının toplulaştırma sözcüğü hiç görünmezdi.
    rakam_konumu <- regexpr("-?[0-9][0-9.,]*([eE][+-]?[0-9]+)?", ham, perl = TRUE)
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
      # BİTİŞİKLİK TAVANI: parça sınırı tek başına yeterli değildir. Uzun bir
      # cümlenin başındaki ilgisiz sayı (çoğunlukla bir yıl) aynı parçada
      # kalır ve işarete bağlanıp `value_mismatch` üretirdi.
      adaylar <- .pk_prov_adjacent_candidates(masked, icinde, jetonlar,
                                              grup$start)
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
