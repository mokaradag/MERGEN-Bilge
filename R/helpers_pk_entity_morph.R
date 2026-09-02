# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_morph.R
# Açıklama: Faz 4 — Türkçe biçimbirim (morfoloji) katmanı: sonek soyma ve
#           çoğulluk sinyali. R/helpers_pk_entity_normalize.R içinden AYRILDI;
#           normalleştirme dosyası anahtar üretimine, bu dosya yalnızca
#           Türkçe eklere odaklanır.
#
#           KRİTİK TASARIM — burada yapılan soyma SEZGİSELDİR ve kayıplıdır.
#           Bu yüzden iki ayrı güvenlik önlemi vardır:
#
#             1) Sözlük farkındalı soyma: önerilen gövde kapalı sözlükte
#                GERÇEKTEN varsa kısa gövdelere ve tek harfli eklere izin
#                verilir (İHAlar -> iha, kitabı -> kitap).
#             2) Sözlükle doğrulanmamış her soyma `heuristic` olarak
#                işaretlenir; puanlayıcı bu bayrağı taşır ve karar politikası
#                bayraklı eşleşmeyi ASLA otomatik kabul etmez (yalnızca onay
#                ister). Böylece "Mersin -> mers" gibi bir soyma sessiz yanlış
#                varlık seçemez.
#
#           Türkçe katlama TEK KAYNAKTAN gelir: `pk_tr_fold()`. Bu dosya
#           katlamayı ne kopyalar ne de yeniden tanımlar (§5.4 açık kuralı).
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# TÜRKÇE SABİTLER YÜKLEME ANINDA UTF-8'E SABİTLENİR (`enc2utf8`).
#
# NEDEN: Windows VM'de `source(dosya, encoding = "UTF-8")` içeriği YERELE
# (WINDOWS-1254) çevirir, sabitler "native" işaretli olur; karşılaştırılan metin
# ise `pk_tr_fold()`/`stringi` yolundan UTF-8 işaretli gelir. `identical()` ve
# `%in%` bu durumda native tarafı GÜNCEL yerele göre çevirir; yerel `C` iken
# çeviri BAŞARISIZ olur, ek eşleşmesi sessizce kaybolur ve "ANKA'nın" -> "anka"
# yerine "anka nın" üretilir. Yükleme anında yerel DOĞRU olduğu için dönüşümü
# burada bir kez yapmak sabitleri sonraki yerel değişikliklerinden bağımsız
# kılar; UTF-8 işaretli dizelerde `enc2utf8()` işlemsizdir (bayt düzeyinde AYNI).

# Türkçe ünlüler; ünlü uyumu denetimi için gereklidir.
.PK_MORPH_BACK_VOWELS  <- enc2utf8(c("a", "ı", "o", "u"))   # a, ı, o, u
.PK_MORPH_FRONT_VOWELS <- enc2utf8(c("e", "i", "ö", "ü"))   # e, i, ö, ü
.PK_MORPH_VOWELS <- c(.PK_MORPH_BACK_VOWELS, .PK_MORPH_FRONT_VOWELS)

# Türkçe'ye ÖZGÜ harfler; girdinin saf ASCII olup olmadığını sınamak için.
.PK_MORPH_TR_ONLY_CHARS <- enc2utf8(c("ı", "ş", "ğ", "ü", "ö", "ç"))

# Eşleştirme amaçlı sonek listesi; UZUNDAN KISAYA sıralıdır ki "sinde" soneki
# "de"den, "deki" soneki "de"den önce denensin.
#
# TAMPON ÜNSÜZLER MODELLENİR (kusur: `projesinde` -> `projes`). Türkçe iyelik +
# hâl zincirleri araya tampon `n`/`s`/`y` alır ("proje-si-n-de"); ham kuyruk
# silme bunu modelleyemez. Bu yüzden tampon başlangıçlı yüzey biçimleri
# (`sinde`, `sini`, `yi`, `yle`, `miz`, `niz` ...) listeye AÇIKÇA girer.
#
# BİLEREK DIŞARIDA BIRAKILANLAR:
#   * tek harfli ekler (-i, -ı, -u, -ü, -a, -e): "proje" -> "proj" gibi yıkıcı
#     soymalara yol açar. Bunlar YALNIZCA sözlük doğrulamalı yolda denenir
#     (bkz. `.pk_morph_vocab_stem()`), genel soyma listesinde yer almaz.
#   * iyelik -ım/-im/-um/-üm: "bakım", "onarım", "tasarım", "yatırım" gibi
#     yaygın adlarla çakışır.
# Bu dışarıda bırakmalar ölçülerek seçildi; listeyi genişletmeden önce
# tests/testthat/test-pk-entity-normalize-behavior.R içindeki yanlış-soyma
# vakalarını genişletin.
.PK_ENTITY_SUFFIXES <- enc2utf8(c(
  # 1./2. kişi iyelik zincirleri (uzun, üretken, görece tekil).
  "ımız", "imiz", "umuz", "ümüz",   # -ımız/-imiz/-umuz/-ümüz
  "ınız", "iniz", "unuz", "ünüz",   # -ınız/-iniz/-unuz/-ünüz
  # 3. kişi iyelik + hâl (tampon n/y ile).
  "sinden", "sından", "sunden", "sünden",
  "sinde", "sında", "sunda", "sünde",
  "sine", "sına", "suna", "süne",
  "sini", "sını", "sunu", "sünü",
  "siyle", "sıyla", "suyla", "süyle",
  # Ünlüden sonra gelen 1./2. kişi iyelik yüzeyleri.
  "mız", "miz", "muz", "müz",
  "nız", "niz", "nuz", "nüz",
  # Bulunma + ilgi ("-deki").
  "deki", "dakı", "daki", "teki", "takı", "taki",
  # Tamlayan.
  "nin", "nın", "nun", "nün",
  # Ayrılma.
  "den", "dan", "ten", "tan",
  # Çoğul.
  "lar", "ler",
  # Tamlayan (ünsüzden sonra).
  "in", "ın", "un", "ün",
  # Bulunma.
  "de", "da", "te", "ta",
  # 3. kişi iyelik (ünlüden sonra).
  "si", "sı", "su", "sü",
  # Tampon y'li belirtme ve vasıta.
  "yi", "yı", "yu", "yü",
  "yle", "yla",
  # Yönelme ve vasıta.
  "ye", "ya", "le", "la"
))

# Sözlük doğrulamalı yolda denenen TEK HARFLİ ekler. Genel listede yoktur;
# yalnızca sonuç gövdesi kapalı sözlükte gerçekten bulunursa kabul edilir.
.PK_MORPH_VOCAB_ONLY_SUFFIXES <- enc2utf8(c("i", "ı", "u", "ü", "e", "a"))

# Türkçe ünsüz yumuşaması: son ünsüz ünlüyle başlayan ek aldığında yumuşar
# (kitap -> kitabı, ağaç -> ağacı, kanat -> kanadı, ekmek -> ekmeği).
# Soyma YÖNÜ terstir: yumuşamış biçimden sert biçime geri döneriz.
.PK_MORPH_SOFTENED <- enc2utf8(c("b", "c", "d", "ğ", "g"))
.PK_MORPH_HARDENED <- lapply(
  list(
    b = "p",
    c = "ç",
    d = "t",
    "ğ" = c("k", "g"),
    g = "k"
  ),
  enc2utf8
)
# AD da katalog anahtarıdır: `[[son]]` araması ADLARI karşılaştırır, bu yüzden
# adlar da UTF-8'e sabitlenmelidir.
names(.PK_MORPH_HARDENED) <- enc2utf8(names(.PK_MORPH_HARDENED))

# Soyma sonrası gövde bu uzunluğun altına düşerse sonek SÖZLÜK DOĞRULAMASI
# OLMADAN soyulmaz. "hatta" -> "hat" (3) ve "yolda" -> "yol" (3) gibi yıkıcı
# soymaları engeller. Sözlükte doğrulanan gövdeler için alt sınır ayrıdır.
.PK_ENTITY_MIN_STEM_NCHAR <- 4L
.PK_MORPH_MIN_VOCAB_STEM_NCHAR <- 2L

# Türkçe eklemeli bir dildir ("proje-ler-in-de-ki-ler"); tek geçiş yetmez ve
# sabit üç geçiş de yetmez (kusur: `projelerindekiler`). Üst sınır artık
# GİRDİ UZUNLUĞUNA bağlıdır: her sonek en az iki harf götürdüğü için
# nchar/2 geçiş her meşru zinciri kapsar ve yine de sonludur.
.PK_MORPH_MAX_STRIP_CEILING <- 8L

.pk_morph_max_strips <- function(token) {
  n <- nchar(token)
  if (is.na(n) || n <= 0L) return(0L)
  as.integer(min(.PK_MORPH_MAX_STRIP_CEILING, max(1L, n %/% 2L)))
}

.pk_morph_last_vowel <- function(x) {
  harfler <- strsplit(x, "", fixed = TRUE)[[1]]
  unluler <- harfler[harfler %in% .PK_MORPH_VOWELS]
  if (!length(unluler)) return(NA_character_)
  unluler[length(unluler)]
}

# Çoğul gövdesi bu uzunluğun altındaysa `-lar/-ler` bitişi ek DEĞİL, adın
# kendi parçasıdır: `SOLAR` (gövde "so"), `DOLAR`, `POLAR`.
.PK_MORPH_MIN_PLURAL_STEM <- 3L

# Çoğul eki ünlü uyumuna UYMAK ZORUNDADIR. "SOLAR" gibi çoğul olmayan adların
# `-lar` ile bitmesi bu yüzden yeterli sinyal değildir (kusur: her -lar/-ler
# ekini çoğul saymak).
#
# TEK İSTİSNA — SAF ASCII girdi. Kullanıcı Türkçe karakter yazmadığında
# `kaliplar` biçiminde `ı` ile `i` ayrımı KAYBOLMUŞTUR ve ünlü uyumu
# uygulanamaz; bu durumda uyum denetimi atlanır. Gövde uzunluğu kuralı
# yürürlükte kaldığı için `SOLAR`/`DOLAR` yine çoğul sayılmaz.
.pk_morph_plural_suffix_of <- function(token) {
  if (is.na(token) || nchar(token) < 5L) return(NA_character_)

  son <- substring(token, nchar(token) - 2L)
  if (!identical(son, "lar") && !identical(son, "ler")) return(NA_character_)

  govde <- substring(token, 1L, nchar(token) - 3L)
  if (nchar(govde) < .PK_MORPH_MIN_PLURAL_STEM) return(NA_character_)

  unlu <- .pk_morph_last_vowel(govde)
  if (is.na(unlu)) return(NA_character_)

  # Girdide Türkçe'ye özgü hiçbir harf yoksa uyum bilgisi yoktur.
  saf_ascii <- !any(vapply(
    .PK_MORPH_TR_ONLY_CHARS,
    function(ch) grepl(ch, token, fixed = TRUE),
    logical(1)
  ))
  # BİLİNEN SINIR (PR #705): ASCII girdide `Miller`/`Seller` gibi yabancı ÖZEL ADLAR da çoğul raporlanır; ünlü uyumu bunu AYIRT EDEMEZ, çünkü `diller`/`gunler` gibi GERÇEK Türkçe çoğullar aynı ASCII şekle sahiptir. Uyumu ASCII'de zorlamak meşru çoğulları düşürür (daha zararlı bir yanlış negatif). Ayırt etmek SÖZLÜK kanıtı ister (`.pk_morph_vocab_stem()`); sonuç en fazla bir netleştirme sorusudur, veri kaybı DEĞİL.
  if (saf_ascii) return(son)

  if (identical(son, "lar") && unlu %in% .PK_MORPH_BACK_VOWELS) return("lar")
  if (identical(son, "ler") && unlu %in% .PK_MORPH_FRONT_VOWELS) return("ler")

  NA_character_
}

#' Belirteç (ya da onun hâl ekleri soyulmuş biçimlerinden biri) çoğul mu?
#'
#' Çoğul eki hâl/iyelik eklerinden ÖNCE gelir ("proje-ler-de", "kalıp-lar-dan"),
#' bu yüzden yalnızca son üç harfe bakmak yetmez: sonekler tek tek soyulurken
#' HER ARA BİÇİMDE çoğul sinyali aranır.
pk_entity_token_is_plural <- function(token) {
  if (is.null(token) || !length(token)) return(FALSE)
  token <- as.character(token)[1]
  if (is.na(token) || !nzchar(token)) return(FALSE)

  # Sinyal ARAMASI olduğu için burada tek harfli ekler de soyulur
  # ("projeleri" = proje + ler + i). Bu bir GÖVDE üretimi değildir; sonuç
  # yalnızca "bu ifadede çoğul eki var mı" sorusuna cevap verir.
  ekler <- c(.PK_ENTITY_SUFFIXES, .PK_MORPH_VOCAB_ONLY_SUFFIXES)

  govde <- token
  for (tur in seq_len(.pk_morph_max_strips(token))) {
    if (!is.na(.pk_morph_plural_suffix_of(govde))) return(TRUE)

    soyuldu <- FALSE
    for (ek in ekler) {
      ek_n <- nchar(ek)
      if (nchar(govde) - ek_n < .PK_ENTITY_MIN_STEM_NCHAR) next
      if (!identical(substring(govde, nchar(govde) - ek_n + 1L), ek)) next

      govde <- substring(govde, 1L, nchar(govde) - ek_n)
      soyuldu <- TRUE
      break
    }

    if (!soyuldu) break
  }

  !is.na(.pk_morph_plural_suffix_of(govde))
}

# Yumuşamış son ünsüzü sertleştirerek olası gövdeleri üretir
# (kitab -> kitap, ağac -> ağaç, kanad -> kanat, ekmeğ -> ekmek).
.pk_morph_harden_variants <- function(stem) {
  if (is.na(stem) || nchar(stem) < 2L) return(character(0))

  son <- substring(stem, nchar(stem))
  if (!(son %in% .PK_MORPH_SOFTENED)) return(character(0))

  sert <- .PK_MORPH_HARDENED[[son]]
  if (is.null(sert) || !length(sert)) return(character(0))

  paste0(substring(stem, 1L, nchar(stem) - 1L), sert)
}

# Sözlük farkındalı soyma. `vocab` kapalı sözlükteki belirteçlerin kümesidir.
# Önerilen gövde bu kümede GERÇEKTEN varsa kabul edilir; bu yüzden kısa
# akronimler (İHAlar -> iha) ve ünsüz yumuşamalı biçimler (kitabı -> kitap)
# çözülebilir, ama uydurma gövdeler üretilmez.
.pk_morph_vocab_stem <- function(token, vocab) {
  if (!length(vocab)) return(NULL)

  adaylar <- character(0)
  ekler <- c(.PK_ENTITY_SUFFIXES, .PK_MORPH_VOCAB_ONLY_SUFFIXES)

  for (ek in ekler) {
    ek_n <- nchar(ek)
    kalan_n <- nchar(token) - ek_n
    if (kalan_n < .PK_MORPH_MIN_VOCAB_STEM_NCHAR) next
    if (!identical(substring(token, nchar(token) - ek_n + 1L), ek)) next

    govde <- substring(token, 1L, kalan_n)
    adaylar <- c(adaylar, govde, .pk_morph_harden_variants(govde))
  }

  adaylar <- unique(adaylar[nzchar(adaylar)])
  if (!length(adaylar)) return(NULL)

  bulunan <- adaylar[adaylar %in% vocab]
  if (!length(bulunan)) return(NULL)

  # En uzun eşleşen gövde en az kayıplı olandır.
  bulunan[order(-nchar(bulunan), bulunan, method = "radix")][1]
}

#' Tek bir belirteçten sonek soy
#'
#' @param token Katlanmış tek belirteç.
#' @param vocab Kapalı sözlükteki belirteçler (isteğe bağlı). Verilirse önce
#'   sözlük doğrulamalı soyma denenir ve sonuç `heuristic = FALSE` olur.
#' @return `list(stem, heuristic)`. `heuristic = TRUE`, gövdenin sözlükle
#'   DOĞRULANMADIĞINI ve puanın otomatik kabule uygun OLMADIĞINI bildirir.
pk_entity_stem_token_record <- function(token, vocab = character(0)) {
  if (is.null(token) || !length(token)) {
    return(list(stem = token, heuristic = FALSE))
  }
  token <- as.character(token)[1]
  if (is.na(token) || !nzchar(token)) {
    return(list(stem = token, heuristic = FALSE))
  }

  if (token %in% vocab) return(list(stem = token, heuristic = FALSE))

  dogrulanmis <- .pk_morph_vocab_stem(token, vocab)
  if (!is.null(dogrulanmis)) return(list(stem = dogrulanmis, heuristic = FALSE))

  govde <- token
  sezgisel <- FALSE

  for (tur in seq_len(.pk_morph_max_strips(token))) {
    soyuldu <- FALSE

    for (ek in .PK_ENTITY_SUFFIXES) {
      ek_n <- nchar(ek)
      if (nchar(govde) - ek_n < .PK_ENTITY_MIN_STEM_NCHAR) next
      if (!identical(substring(govde, nchar(govde) - ek_n + 1L), ek)) next

      govde <- substring(govde, 1L, nchar(govde) - ek_n)
      soyuldu <- TRUE
      sezgisel <- TRUE
      break
    }

    if (!soyuldu) break

    # Ara gövde sözlükte bulunduysa zinciri orada kes: doğrulanmış gövde
    # sezgisel gövdeden her zaman iyidir.
    if (govde %in% vocab) return(list(stem = govde, heuristic = FALSE))
  }

  list(stem = govde, heuristic = sezgisel)
}

#' Geriye dönük uyumlu sade soyma yüzeyi
#'
#' Yalnızca gövdeyi döndürür; `heuristic` bayrağına ihtiyaç duymayan çağıranlar
#' (ör. testler) bunu kullanır.
pk_entity_stem_token <- function(token, vocab = character(0)) {
  pk_entity_stem_token_record(token, vocab = vocab)$stem
}
