# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_normalize.R
# Açıklama: Faz 4 — varlık çözümleme normalleştirme hattı (master plan §5.4).
#
#           Kullanıcı ifadesini ve kapalı sözlükteki kanonik değerleri AYNI
#           boru hattından geçirir ve ÜÇ AYRI anahtar üretir:
#
#             exact   : pk_tr_fold() + kesme işareti biçim birleştirme
#                       NOKTALAMA KORUNUR  -> Katman 1 (100 puan)
#             fold    : exact + Türkçe kesme ekleri + noktalama sadeleştirme
#                       KAYIPLI            -> Katman 4/5/6 ve `punct_key`
#             compact : fold + tüm boşlukların kaldırılması
#                       KAYIPLI            -> `compact_key` (F16 <-> F-16)
#
#           Noktalama neden korunuyor: `A+B` ile `A/B` ayrı kanonik
#           varlıklardır ve her ikisi de `a b`ye çökerse kullanıcı YANLIŞ
#           varlığı sessizce filtreler. Aynı gerekçeyle `PRJ 001` ile
#           `PRJ-001` kesin (id/exact) sütunlarda ASLA eşleşmez.
#
#           Türkçe katlama TEK KAYNAKTAN gelir: R/helpers_pk_text_turkish.R
#           içindeki `pk_tr_fold()`. Bu dosya katlamayı ne kopyalar ne de
#           yeniden tanımlar (§5.4 açık kuralı). Sonek/çoğul biçimbirim
#           mantığı R/helpers_pk_entity_morph.R dosyasındadır.
#
# ÖLÇÜLMÜŞ UYARI — `chartr()` veya elle kod noktası eşlemesi KULLANILMAZ; her
#   ikisi de bu depoda denendi ve UTF-8 olmayan yerelde bayt bazlı çalışıp
#   mojibake ürettiği için reddedildi. ASCII ikincil anahtarı da bu yüzden
#   ICU tabanlı `stringi::stri_replace_all_fixed()` ile üretilir.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Türkçe'de özel adlara gelen ekler kesme işaretiyle ayrılır. Tüm yaygın
# kesme işareti biçimleri (düz, tipografik SOL ve SAĞ, harf-kesme, aksan)
# kapsanır: kopyalanan metin çoğu zaman sol tipografik tırnak taşır.
.PK_ENTITY_APOSTROPHES <- c(
  "'",
  intToUtf8(0x2018L),  # tipografik sol kesme
  intToUtf8(0x2019L),  # tipografik sağ kesme
  intToUtf8(0x02BCL),  # harf olarak kesme
  intToUtf8(0x00B4L),  # aksan
  "`"
)

# TÜRKÇE SABİTLER YÜKLEME ANINDA UTF-8'E SABİTLENİR (`enc2utf8`).
#
# `R/helpers_pk_entity_morph.R` başlığındaki ölçülen arıza burada da geçerlidir:
# Windows VM'de `source(dosya, encoding = "UTF-8")` içeriği YERELE
# (WINDOWS-1254) çevirir ve sabitler "native" işaretli olur; karşılaştırılan
# belirteçler ise `pk_tr_fold()`/`pk_entity_normalize()` yolundan UTF-8 işaretli
# gelir. `%in%`, `identical()` ve `stri_replace_all_fixed()` o durumda native
# tarafı GÜNCEL yerele göre çevirir; yerel `C` iken çeviri başarısız olur ve
# eşleşme SESSİZCE kaybolur. UTF-8 işaretli dizelerde `enc2utf8()` işlemsizdir.

# ASCII ikincil anahtar eşlemesi (§5.4). Kullanıcılar Türkçe karakter
# yazmadan arama yapar: "kalip" -> "kalıp", "sure" -> "sûre".
# Katlama zaten küçük harfe indirdiği için yalnızca küçük harf biçimleri gerekir.
# Şapkalı ünlüler de dâhildir: kurumsal adlarda `SÛRE`, `KÂĞIT`, `HÂKİM` gibi
# biçimler vardır ve klavyeden `sure`, `kagit`, `hakim` yazılır.
.PK_ENTITY_TR_CHARS <- enc2utf8(c(
  "ı", "ş", "ğ", "ü", "ö", "ç",
  "â", "î", "û", "ê", "ô"
))
.PK_ENTITY_ASCII_CHARS <- c(
  "i", "s", "g", "u", "o", "c",
  "a", "i", "u", "e", "o"
)

# Bu karakterlerden biri kullanıcı ifadesinde GEÇİYORSA kullanıcı Türkçe'yi
# AÇIKÇA yazmıştır ve ASCII katlaması artık "eksik harfi tamamlama" değil
# BİLGİ SİLME olur (KİR ile KIR ayrı varlıklardır). Bu durumda ASCII katmanı
# kayıplı olarak işaretlenir ve otomatik kabule uygun sayılmaz.
#
# ASCII `I`/`i` BİLEREK DIŞARIDADIR: TAMAMI BÜYÜK HARF ASCII bir sözlük
# değeri (`ELEKTRONIK`) Türkçe katlamada `elektronık` olur ve kullanıcının
# yazdığı `elektronik` ile ASCII katmanında buluşması GEREKİR (tasarım
# kararı E3). `İ` ise küçük harfe `i` olarak indiği için katlanmış metinde
# görünmez; bu yüzden HAM girdide ayrıca aranır.
# ŞAPKALI ÜNLÜLERİN TAMAMI LİSTEDE OLMALIDIR.
#
# `.PK_ENTITY_TR_CHARS` on bir harfi ASCII'ye katlar (`ê` ve `ô` dâhil). Bu
# vektör dokuzunu listelediği için, ifadedeki TEK Türkçeye özgü harf `ê` ya da
# `ô` olduğunda `has_turkish` FALSE kalıyor, `.pk_entity_tier_of()` katmanı
# `ascii_key` + 90 puan olarak `ascii_lossy` BAYRAĞI OLMADAN döndürüyor ve
# kural 4 adayı OTOMATİK kabul ediyordu: kullanıcı yalnızca o aksanla ayrılan
# BAŞKA bir varlığı teyit istemeden filtreleyebilirdi.
.PK_ENTITY_TR_ONLY_CHARS <- enc2utf8(c(
  "ı", "ş", "ğ", "ü", "ö", "ç", "â", "î", "û", "ê", "ô"
))
.PK_ENTITY_TR_DOTTED_I <- c(
  intToUtf8(0x0130L),                       # İ
  paste0("i", intToUtf8(0x0307L)),          # i + birleşik nokta
  paste0("I", intToUtf8(0x0307L))           # I + birleşik nokta
)

# Çoğulluk sinyali veren belirteçler (§5.4 kural 3). ASCII yazımları da
# listededir: kullanıcı Türkçe karakter yazmayabilir ve o durumda çoğul niyet
# sessizce kaybolursa istek tekil kural 4/5 yoluna düşer.
#
# `list`, `listele`, `listesi` BİLEREK YOKTUR: bunlar komut/ad belirteçleridir,
# birden çok kanonik değer istendiğini KANITLAMAZLAR ("KAYNAK LİSTESİ" tekil
# bir kanonik addır).
.PK_ENTITY_PLURAL_WORDS <- enc2utf8(c(
  "tüm", "tum", "tümü", "tumu", "tümünü", "tumunu",
  "bütün", "butun",
  "hepsi", "hepsini",
  "her", "herhangi",
  "çeşitli", "cesitli",
  "farklı", "farkli",
  "birden", "birkaç", "birkac",
  "bazı", "bazi"
))

# `-lar/-ler` BİÇİMBİRİM sinyali YALNIZCA varlık adı olabilecek belirteçlerden
# okunur. Genel sıfat-fiiller ("olanlar", "bulunanlar") satır daraltmasıdır,
# birden çok KANONİK DEĞER istendiğinin kanıtı değildir: "sadece aktif olanlar"
# tek bir varlığın kayıtlarını daraltır, iki varlığı birleştirmez.
.PK_ENTITY_NON_ENTITY_PLURALS <- enc2utf8(c(
  "olanlar", "olanları", "olanlari",
  "bulunanlar", "bulunanları", "bulunanlari",
  "yapılanlar", "yapilanlar",
  "kalanlar", "gelenler", "gidenler", "verilenler", "alınanlar", "alinanlar"
))

.pk_entity_require_stringi <- function() {
  if (!requireNamespace("stringi", quietly = TRUE)) {
    stop(
      paste0(
        "pk_entity_normalize: 'stringi' paketi bulunamadı. Yerelden bağımsız ",
        "normalleştirme yalnızca stringi ile yapılabilir."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

.pk_entity_apostrophe_class <- function() {
  paste0("[", paste0("\\Q", .PK_ENTITY_APOSTROPHES, "\\E", collapse = ""), "]")
}

# Kesme işaretinden sonraki harf dizisinin TAMAMI bilinen Türkçe eklerden
# oluşuyor mu? Oluşmuyorsa dizi ekin kendisi DEĞİLDİR ve kanonik adın parçası
# olarak KORUNUR.
#
# Bu, "her kesme işaretinden sonrasını sil" davranışının düzeltmesidir:
# `O'NEIL RADAR` ile `O'BRIEN RADAR` aynı anahtara çökerse görünmeyen adayı
# yazan kullanıcı 100 puanla YANLIŞ varlığı sessizce filtreler.
.pk_entity_run_is_suffix_chain <- function(run) {
  if (is.na(run) || !nzchar(run)) return(FALSE)

  ekler <- c(.PK_ENTITY_SUFFIXES, .PK_MORPH_VOCAB_ONLY_SUFFIXES)
  ekler <- ekler[order(-nchar(ekler), ekler, method = "radix")]

  kalan <- run
  for (tur in seq_len(.PK_MORPH_MAX_STRIP_CEILING)) {
    if (!nzchar(kalan)) return(TRUE)

    eslesen <- NULL
    for (ek in ekler) {
      if (identical(substring(kalan, 1L, nchar(ek)), ek)) {
        eslesen <- ek
        break
      }
    }

    if (is.null(eslesen)) return(FALSE)
    kalan <- substring(kalan, nchar(eslesen) + 1L)
  }

  !nzchar(kalan)
}

.pk_entity_strip_clitics_one <- function(metin) {
  if (is.na(metin) || !nzchar(metin)) return(metin)

  desen <- paste0("(", .pk_entity_apostrophe_class(), ")(\\p{L}*)")
  konumlar <- stringi::stri_locate_all_regex(metin, desen)[[1]]
  if (!length(konumlar) || all(is.na(konumlar[, 1]))) return(metin)

  parcalar <- stringi::stri_match_all_regex(metin, desen)[[1]]

  # Sondan başa doğru silinir; böylece konum indeksleri kaymaz.
  for (i in rev(seq_len(nrow(konumlar)))) {
    if (is.na(konumlar[i, 1])) next
    kuyruk <- parcalar[i, 3]
    if (is.na(kuyruk) || !.pk_entity_run_is_suffix_chain(kuyruk)) next

    metin <- paste0(
      substring(metin, 1L, konumlar[i, 1] - 1L),
      substring(metin, konumlar[i, 2] + 1L)
    )
  }

  metin
}

#' Kesme işareti EKLERİNİ at ("ANKA'nın" -> "ANKA", "O'NEIL" -> "O'NEIL")
#'
#' Kesme işaretinden sonraki dizi yalnızca BİLİNEN Türkçe eklerden oluşuyorsa
#' ek sayılır ve kesme işaretiyle birlikte silinir. Aksi hâlde dizi kanonik
#' adın parçasıdır ve KORUNUR.
pk_entity_strip_clitics <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- vapply(metin, .pk_entity_strip_clitics_one, character(1), USE.NAMES = FALSE)
  metin[na_maskesi] <- NA_character_
  metin
}

# Ayırıcıyla bağlanmış ekler ("ANKA-da") noktalama SADELEŞTİRİLMEDEN ÖNCE
# soyulur. Aksi hâlde `anka` / `da` iki ayrı belirteç olur, `da` gövde
# soymaya girmeyecek kadar kısadır ve Jaccard 1/2'ye düşerek kanonik `ANKA`
# adayıyla eşleşme kaybolur.
.pk_entity_strip_separator_suffixes_one <- function(metin) {
  if (is.na(metin) || !nzchar(metin)) return(metin)

  # EK BELİRTECİN SONUNDADIR, arada YALNIZCA noktalama kalabilir: bakış
  # `A-SAVUNMA`yı eşleştirmemeli ama "ANKA-da?" ifadesini de kaçırmamalıdır.
  desen <- "([\\p{L}\\p{N}])[\\-\\x{2010}-\\x{2015}_.](\\p{L}+)(?=[^\\p{L}\\p{N}]*(?:\\s|$))"
  for (tur in seq_len(.PK_MORPH_MAX_STRIP_CEILING)) {
    # SOLDAN İLK EŞLEŞME BİR EK ZİNCİRİ OLMAYABİLİR (`HAVA-SAVUNMA-da` içindeki
    # `A-SAVUNMA`); döngü orada DURDURULUNCA sondaki gerçek `-da` eki hiç
    # soyulmuyor ve tam eşleşecek varlık kaçırılıyordu. Eşleşmelerin TAMAMI
    # taranır; ek zinciri OLMAYANLAR atlanır ve SON ek zinciri soyulur.
    parcalar <- stringi::stri_match_all_regex(metin, desen)[[1]]
    if (!is.matrix(parcalar) || nrow(parcalar) == 0L || is.na(parcalar[1, 1])) break

    zincir <- vapply(seq_len(nrow(parcalar)),
                     function(i) .pk_entity_run_is_suffix_chain(parcalar[i, 3]),
                     logical(1))
    if (!any(zincir)) break
    hedef <- max(which(zincir))

    yerler <- stringi::stri_locate_all_regex(metin, desen)[[1]]
    metin <- paste0(
      stringi::stri_sub(metin, 1L, yerler[hedef, 1] - 1L),
      parcalar[hedef, 2],
      stringi::stri_sub(metin, yerler[hedef, 2] + 1L, nchar(metin))
    )
  }

  metin
}

#' Noktalama ve simgeleri tek boşluğa indir
#'
#' Unicode farkındalıdır: Türkçe harfler `\p{L}`, rakamlar `\p{N}` altında
#' korunur; ayırıcı, tire, parantez ve benzeri her şey boşluğa döner.
pk_entity_collapse_punct <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- stringi::stri_replace_all_regex(metin, "[^\\p{L}\\p{N}]+", " ")
  metin <- stringi::stri_replace_all_regex(metin, "\\s+", " ")
  metin <- trimws(metin)

  metin[na_maskesi] <- NA_character_
  metin
}

#' ASCII ikincil anahtar (§5.4)
#'
#' Girdi ZATEN katlanmış olmalıdır; bu fonksiyon yalnızca Türkçe'ye özgü
#' harfleri (şapkalılar dâhil) ASCII karşılığına eşler.
pk_entity_ascii_key <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  .pk_entity_require_stringi()

  metin <- enc2utf8(as.character(x))
  na_maskesi <- is.na(metin)
  metin[na_maskesi] <- ""

  metin <- stringi::stri_replace_all_fixed(
    metin,
    .PK_ENTITY_TR_CHARS,
    .PK_ENTITY_ASCII_CHARS,
    vectorize_all = FALSE
  )

  metin[na_maskesi] <- NA_character_
  metin
}

#' Eşleştirme belirteç kümesi
#'
#' Sonek soyma HER İKİ tarafa da (kullanıcı ifadesi ve kanonik aday) aynı
#' şekilde uygulanır; asimetrik soyma sessiz kaçırmalara yol açar.
#'
#' ÇOKLUK KORUNUR (`unique()` YOKTUR). `BORA BORA` ile `BORA` farklı kanonik
#' varlıklardır; tekilleştirme ikisini ayırt edilemez hâle getirir ve
#' kapsama katmanı yanlış varlığı otomatik seçer.
#'
#' @param vocab Kapalı sözlükteki belirteçler; verilirse soyma sözlükle
#'   doğrulanır ve `heuristic` bayrağı düşer.
#' @return Boş olmayan belirteçlerden oluşan karakter vektörü.
pk_entity_tokens <- function(x, stem = TRUE, vocab = character(0)) {
  kayit <- pk_entity_token_record(x, stem = stem, vocab = vocab)
  kayit$tokens
}

#' Belirteçler + soyma kaynağı bilgisi
#'
#' @return `tokens` ve `heuristic` (en az bir belirteç sözlükle DOĞRULANMADAN
#'   soyulduysa TRUE).
pk_entity_token_record <- function(x, stem = TRUE, vocab = character(0)) {
  bos <- list(tokens = character(0), heuristic = FALSE)
  if (is.null(x) || !length(x)) return(bos)

  metin <- as.character(x)[1]
  if (is.na(metin) || !nzchar(metin)) return(bos)

  parcalar <- strsplit(metin, " ", fixed = TRUE)[[1]]
  parcalar <- parcalar[!is.na(parcalar) & nzchar(parcalar)]
  if (!length(parcalar)) return(bos)

  if (!isTRUE(stem)) return(list(tokens = parcalar, heuristic = FALSE))

  sezgisel <- FALSE
  govdeler <- character(length(parcalar))
  for (i in seq_along(parcalar)) {
    kayit <- pk_entity_stem_token_record(parcalar[i], vocab = vocab)
    govdeler[i] <- kayit$stem
    if (isTRUE(kayit$heuristic)) sezgisel <- TRUE
  }

  govdeler <- govdeler[!is.na(govdeler) & nzchar(govdeler)]
  list(tokens = govdeler, heuristic = sezgisel)
}

#' Tam normalleştirme kaydı
#'
#' @return `exact` (noktalama KORUNAN kesin anahtar, Katman 1), `fold`
#'   (noktalama sadeleştirilmiş kayıplı anahtar), `compact` (boşluksuz kayıplı
#'   anahtar), `ascii`/`ascii_compact` (ikincil anahtarlar), `tokens` (soyulmuş
#'   belirteçler), `tokens_raw` (soyulmamış), `has_turkish` (kullanıcı Türkçe'ye
#'   özgü harf yazdı mı), `raw` ve `blank`.
#'
#' NOT — `exact` anahtarı sonek SOYMAZ ve noktalamayı SİLMEZ. 100 puanlık
#' otomatik kabul yolunu sezgisel/kayıplı bir adıma bağlamak yanlış olurdu.
#' Soyma, puanı 89 ile sınırlı olan belirteç katmanlarında çalışır.
pk_entity_normalize <- function(x, vocab = character(0)) {
  ham <- if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]

  katlanmis <- pk_tr_fold(ham)
  if (!length(katlanmis)) katlanmis <- NA_character_

  # Kesme işareti BİÇİMLERİ tek forma indirilir; işaretin KENDİSİ korunur.
  kesin <- katlanmis
  if (!is.na(kesin) && nzchar(kesin)) {
    .pk_entity_require_stringi()
    kesin <- stringi::stri_replace_all_fixed(
      kesin, .PK_ENTITY_APOSTROPHES, rep("'", length(.PK_ENTITY_APOSTROPHES)),
      vectorize_all = FALSE
    )
    kesin <- trimws(stringi::stri_replace_all_regex(kesin, "\\s+", " "))
  }

  # Türkçe ek soyma KAYIPLI DEĞİLDİR: her iki taraf aynı boru hattından geçer
  # ve "ANKA'nın" ile "ANKA" gerçekten aynı varlıktır. Bu yüzden `clitic`
  # anahtarı hâlâ 100 puanlık kesin katman için kullanılabilir. KAYIPLI olan
  # adım noktalama sadeleştirmesidir ve o ayrı bir anahtarda tutulur.
  eksiz <- kesin
  if (!is.na(eksiz) && nzchar(eksiz)) {
    eksiz <- .pk_entity_strip_clitics_one(eksiz)
    eksiz <- .pk_entity_strip_separator_suffixes_one(eksiz)
    eksiz <- trimws(stringi::stri_replace_all_regex(eksiz, "\\s+", " "))
  }

  kayipli <- if (is.na(eksiz) || !nzchar(eksiz)) eksiz else pk_entity_collapse_punct(eksiz)

  bos <- is.na(kesin) || !nzchar(kesin) || is.na(kayipli) || !nzchar(kayipli)

  if (bos) {
    return(list(
      raw = ham, exact = NA_character_, clitic = NA_character_,
      fold = NA_character_, fold_only = NA_character_,
      compact = NA_character_, ascii = NA_character_,
      ascii_compact = NA_character_, tokens = character(0),
      tokens_raw = character(0), tokens_ascii = character(0),
      has_turkish = FALSE, stem_heuristic = FALSE, blank = TRUE
    ))
  }

  ascii <- pk_entity_ascii_key(kayipli)
  belirtec <- pk_entity_token_record(kayipli, stem = TRUE, vocab = vocab)

  list(
    raw = ham,
    exact = kesin,
    clitic = eksiz,
    fold = kayipli,
    # Alias kayıt defterinin anahtar sözleşmesi: YALNIZCA `pk_tr_fold()`.
    # Kesme birleştirme/noktalama sadeleştirme UYGULANMAZ; aksi hâlde
    # kayıtta `eh/se` olarak duran onaylı alias, yazılan `EH/SE` ile
    # eşleşmez ve alias katmanı sessizce atlanır.
    fold_only = katlanmis,
    compact = gsub(" ", "", kayipli, fixed = TRUE),
    ascii = ascii,
    ascii_compact = gsub(" ", "", ascii, fixed = TRUE),
    tokens = belirtec$tokens,
    tokens_raw = pk_entity_tokens(kayipli, stem = FALSE),
    tokens_ascii = pk_entity_tokens(ascii, stem = TRUE, vocab = pk_entity_ascii_key(vocab)),
    # HAM GİRDİDE ARANIR, KATLANMIŞ METİNDE DEĞİL: Türkçe katlama ASCII büyük `I` harfini NOKTASIZ `ı`ya çevirir; katlanmış metinde arama, TAMAMI BÜYÜK HARF ASCII bir ifadeyi (`ELEKTRONIK`) "Türkçe yazılmış" sayar, `ascii_lossy` katmanı eklenir ve E3 otomatik kabulü GEREKSİZ yere onaya düşerdi.
    has_turkish = (!is.na(ham) && any(vapply(
      .PK_ENTITY_TR_ONLY_CHARS,
      function(ch) grepl(ch, enc2utf8(ham), fixed = TRUE),
      logical(1)
    ))) || (!is.na(ham) && any(vapply(
      .PK_ENTITY_TR_DOTTED_I,
      function(ch) grepl(ch, enc2utf8(ham), fixed = TRUE),
      logical(1)
    ))),
    stem_heuristic = isTRUE(belirtec$heuristic),
    blank = FALSE
  )
}

#' İfade açıkça çoğul mu? (§5.4 kural 3)
#'
#' Sezgiseldir ve BİLEREK güvenli yöndedir: yanlış pozitif yalnızca kullanıcıya
#' onay sorulmasına yol açar, sessiz bir birleşime değil. Buna rağmen üç
#' ölçülmüş yanlış-pozitif kaynağı kapatılmıştır:
#'
#'   * Çoğul eki ünlü uyumuna uymak zorundadır (`SOLAR` çoğul DEĞİLDİR).
#'   * Komut/ad belirteçleri (`listesi`) ipucu sayılmaz.
#'   * Kesme işaretiyle ayrılmış çoğul (`F-16'lar`, `TV'ler`) ek SOYULMADAN
#'     ÖNCE yakalanır; aksi hâlde sinyal kaybolur ve tekil aday sessizce
#'     otomatik seçilir.
#'
#' İfadenin kanonik bir değerle TAM eşleşmesi hâlinde ipucunun bastırılması
#' çağıran karar politikasının sorumluluğundadır (`pk_entity_resolve()`).
pk_entity_phrase_is_plural <- function(x) {
  ham <- if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]
  katlanmis <- pk_tr_fold(ham)
  if (!length(katlanmis) || is.na(katlanmis) || !nzchar(katlanmis)) return(FALSE)

  .pk_entity_require_stringi()

  # 1) Kesme işaretiyle ayrılmış çoğul: "F-16'lar", "TV'ler".
  kesme_cogul <- paste0(.pk_entity_apostrophe_class(), "(lar|ler)")
  if (stringi::stri_detect_regex(katlanmis, kesme_cogul)) return(TRUE)

  # 2) Kesme ekleri SOYULMADAN belirteçlere ayrılır.
  belirtecler <- pk_entity_tokens(pk_entity_collapse_punct(katlanmis), stem = FALSE)
  if (!length(belirtecler)) return(FALSE)

  ascii_belirtecler <- pk_entity_ascii_key(belirtecler)
  if (any(belirtecler %in% .PK_ENTITY_PLURAL_WORDS) ||
      any(ascii_belirtecler %in% .PK_ENTITY_PLURAL_WORDS)) {
    return(TRUE)
  }

  aday <- belirtecler[!(belirtecler %in% .PK_ENTITY_NON_ENTITY_PLURALS)]
  if (!length(aday)) return(FALSE)

  any(vapply(aday, pk_entity_token_is_plural, logical(1), USE.NAMES = FALSE))
}
