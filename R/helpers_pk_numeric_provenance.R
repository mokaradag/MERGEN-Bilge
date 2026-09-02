# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance.R
# Açıklama: Sayısal köken (numeric provenance) doğrulaması — master plan §5.11.
#
#           Çıplak jeton karşılaştırması YETERSİZDİR: paket `47` sayısını
#           "farklı kişi sayısı" olarak içeriyorsa, düzyazıdaki "tamamlanma %47"
#           ifadesi jeton olarak eşleşse bile YANLIŞTIR. Bu yüzden paket, her
#           sayı için yapılandırılmış bir olgu (fact) yayımlar ve kompozisyon
#           istemi her sayısal iddianın yanına makine tarafından okunabilir bir
#           `[fact:...]` referansı koymak zorundadır. Doğrulayıcı hem DEĞERİ hem
#           de ANLAMSAL kullanımı (birim/kullanılabilirlik) denetler; referans
#           işaretleri gösterimden ancak doğrulamadan SONRA silinir.
#
#           Kipler (`MERGEN_PK_NUMERIC_PROVENANCE_MODE`):
#             off   -> kapalı (yalnızca işaretler temizlenir)
#             log   -> uyuşmazlıklar KAYDEDİLİR; kullanıcıya görünen yanıt
#                      değişmez. KALİBRASYON kipidir ve varsayılandır.
#             warn  -> doğrulanamayan sayılar görünür biçimde işaretlenir
#             block -> düzyazı reddedilir; deterministik özet gösterilir
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

PK_PROV_MODES <- c("off", "log", "warn", "block")

# Düzyazıdaki sayı + (isteğe bağlı) yüzde/birim + `[fact:...]` referansı.
.PK_PROV_MARKER <- "\\[fact:([A-Za-z0-9_.]+)\\]"

pk_numeric_provenance_mode <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return("log")
  kip <- tryCatch(
    pk_config_resolve("MERGEN_PK_NUMERIC_PROVENANCE_MODE", query_meta = query_meta),
    error = function(e) "log"
  )
  if (!is.character(kip) || length(kip) != 1L || !(kip %in% PK_PROV_MODES)) return("log")
  kip
}

#' Türkçe veya sade biçimli bir sayıyı ayrıştır
#'
#' "18.420,5" -> 18420.5 · "61,3" -> 61.3 · "18420.5" -> 18420.5
#' Belirsiz gruplama (ör. "1.234,56.7") reddedilir.
#' Bir sayı metninin OLASI tüm yorumları
#'
#' `18.420` Türkçe binlik gruplamadır (18420), `0.613` ise nokta-ondalıktır.
#' Tek bir yorumu sessizce seçmek doğru bir iddiayı bloklayabilir (`0.613`ü
#' 613 sanmak), bu yüzden GERÇEKTEN belirsiz biçimler için birden çok aday
#' döner ve doğrulayıcı olguyla eşleşen yorumu kabul eder.
#'
#' TÜRKÇE GRUPLAMA BİÇİMİ BELİRSİZ SAYILMAZ (PR incelemesi, P1).
#'
#' `N.NNN` kalıbı (tam olarak üç basamaklı tek grup) Türkçe düzyazıda BİNLİK
#' gruplamadır: kullanıcı `1.250` metnini 1250 olarak OKUR. Kesirli okumayı
#' (1,25) da kabul etmek, model 1,25 değeri için `1.250` yazdığında BİN KAT
#' hatalı bir sayının doğrulanmış gibi yayımlanmasına yol açıyordu; `block`
#' kipi tam da bunu engellemek için vardır. Bu yüzden bu biçimde YALNIZCA
#' binlik okuması aday olur. Nokta-ondalık gösterimler (`0.613`, `1.5`,
#' `12.34`) gruplama kalıbına UYMADIĞI için etkilenmez.
pk_parse_number_candidates <- function(txt) {
  ham <- as.character(txt %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(numeric(0))

  ham <- gsub("[[:space:] ]", "", ham)
  negatif <- startsWith(ham, "-")
  if (negatif || startsWith(ham, "+")) ham <- substring(ham, 2L)

  if (!grepl("^[0-9.,]+$", ham)) return(numeric(0))

  virgul <- gregexpr(",", ham, fixed = TRUE)[[1]]
  virgul_sayisi <- if (identical(virgul[1], -1L)) 0L else length(virgul)
  if (virgul_sayisi > 1L) return(numeric(0))

  adaylar <- character(0)

  if (virgul_sayisi == 1L) {
    # Virgül varsa ondalık ayraçtır; nokta yalnızca gruplama olabilir.
    parcalar <- strsplit(ham, ",", fixed = TRUE)[[1]]
    tam <- parcalar[1]
    kesir <- if (length(parcalar) > 1L) parcalar[2] else ""
    if (grepl(".", kesir, fixed = TRUE)) return(numeric(0))
    if (grepl(".", tam, fixed = TRUE) && !grepl("^[0-9]{1,3}(\\.[0-9]{3})+$", tam)) {
      return(numeric(0))
    }
    tam <- gsub(".", "", tam, fixed = TRUE)
    adaylar <- if (nzchar(kesir)) paste0(tam, ".", kesir) else tam
  } else {
    nokta <- lengths(regmatches(ham, gregexpr(".", ham, fixed = TRUE)))
    gruplama <- grepl("^[1-9][0-9]{0,2}(\\.[0-9]{3})+$", ham)

    if (gruplama) {
      # Türkçe gruplama biçiminde YALNIZCA binlik okuması geçerlidir
      # (gerekçe: fonksiyon başlığı).
      adaylar <- gsub(".", "", ham, fixed = TRUE)
    } else if (nokta > 1L) {
      return(numeric(0))
    } else {
      # "0.613" gruplama OLAMAZ (binlik grup sıfırla başlamaz); sade ondalıktır.
      adaylar <- ham
    }
  }

  num <- suppressWarnings(as.numeric(adaylar))
  num <- num[!is.na(num) & is.finite(num)]
  if (!length(num)) return(numeric(0))
  if (negatif) num <- -num
  unique(num)
}

#' Türkçe veya sade biçimli bir sayıyı ayrıştır (birincil yorum)
pk_parse_number_tr <- function(txt) {
  adaylar <- pk_parse_number_candidates(txt)
  if (!length(adaylar)) return(NULL)
  adaylar[1]
}

# İddia edilen sayının ondalık basamak sayısı -> yuvarlama toleransı.
#
# Ayrım kritiktir: "18.420" Türkçe binlik gruplamadır ve ondalık basamak
# TAŞIMAZ. Noktayı ondalık ayraç sanmak toleransı 0,0005'e düşürür ve tam
# sayıya yuvarlanmış meşru bir alıntı yanlışlıkla uyuşmazlık sayılır.
.pk_prov_decimals <- function(gosterim) {
  txt <- gsub("[[:space:]]", "", as.character(gosterim %||% "")[1])
  if (is.na(txt) || !nzchar(txt)) return(0L)

  if (grepl(",", txt, fixed = TRUE)) {
    kesir <- sub("^.*,", "", txt)
    return(if (grepl("^[0-9]+$", kesir)) nchar(kesir) else 0L)
  }

  # Yalnızca binlik gruplama: ondalık basamak yok.
  if (grepl("^-?[0-9]{1,3}(\\.[0-9]{3})+$", txt)) return(0L)

  if (grepl(".", txt, fixed = TRUE)) {
    kesir <- sub("^.*\\.", "", txt)
    return(if (grepl("^[0-9]+$", kesir)) nchar(kesir) else 0L)
  }

  0L
}

# Tolerans İKİ sınırın küçüğüdür:
#   1. iddia edilen gösterimin yuvarlama adımı (`18.420` -> ±0,5), ve
#   2. MADDİYET sınırı: olgunun büyüklüğünün binde biri.
#
# Yalnızca (1) kullanılırsa iddianın KABALIĞI doğrulamayı zayıflatır: model
# `%61,34` bir olguyu `61`, `0,49` bir olguyu `0` yazıp geçerdi. Yalnızca (2)
# kullanılırsa meşru yuvarlanmış alıntılar reddedilirdi. İkisinin küçüğü, hem
# `18.420,5` -> `18.420` alıntısını kabul eder hem de `61,34` -> `61` iddiasını
# reddeder.
#
# Eski göreli terim (`abs(value) * 1e-9`) büyüklükle büyüyordu: 1e12'de ±1.000,
# 1e15'te ±1.000.000 hataya izin veriyordu; maddi olarak yanlış bir bütçe/maliyet
# iddiası bu yüzden köken doğrulamasından geçebilirdi.
# KABALIK EŞİĞİ: iddia edilen gösterimin yuvarlama adımı, olgunun
# büyüklüğünün bu oranından KÜÇÜKSE alıntı "yeterince hassas" sayılır ve kendi
# yuvarlama adımı tolerans olur. Daha kaba alıntılarda maddiyet sınırı yeniden
# devreye girer.
#
# Neden gerekli: `min(yuvarlama, maddiyet)` KÜÇÜK değerlerde meşru yuvarlamayı
# reddediyordu. `3,456` olgusunu `3,46` diye alıntılamak geçerli bir 2 ondalık
# yuvarlamadır (fark 0,004) ama maddiyet 0,003456'ya düşüyor ve doğru alıntı
# `value_mismatch` sayılıyordu; `block` kipinde DOĞRU bir yanıt deterministik
# yedekle değiştiriliyordu. Adım oranı 0,145% olduğu için artık kabul edilir.
# `61,34` -> `61` iddiasının adım oranı 0,815%'tir; eşiğin ÜSTÜNDE kaldığı için
# maddiyet sınırı uygulanmaya devam eder ve iddia yine REDDEDİLİR.
.PK_PROV_COARSE_STEP_RATIO <- 5e-3

.pk_prov_tolerance <- function(gosterim, gercek, olgu = NULL) {
  buyukluk <- abs(as.numeric(gercek))
  yuvarlama <- 0.5 * 10^(-.pk_prov_decimals(gosterim))
  maddiyet <- max(buyukluk * 1e-3, .Machine$double.eps * 16)

  temel <- if (is.finite(buyukluk) && buyukluk > 0 &&
               yuvarlama <= buyukluk * .PK_PROV_COARSE_STEP_RATIO) {
    yuvarlama
  } else {
    min(yuvarlama, maddiyet)
  }

  temel + buyukluk * .Machine$double.eps * 16
}

# Birim karşılaştırması yerelden bağımsız katlanır ("Saat" == "saat").
# BİÇİMLENDİRME AYRACI SAYININ KÖKENİNİ SİLMEZ.
#
# ÜRETİM BULGUSU: model doğru sayıyı doğru işaretle alıntıladığı hâlde
# `Geciken Aktivite Sayisi: **15.574 adet** [fact:...]` gibi bir satırda
# doğrulayıcı sayıyı GÖREMİYORDU. Neden: sayı+birim örüntüsü bağlam
# penceresinin SONUNA sabitlenir (`\\s*$`) ve markdown vurgusu (`**`, `_`),
# kapanış parantezi, tırnak, noktalama ya da Türkçe kesme eki (`adet'tir`)
# araya girdiğinde eşleşme kurulamıyordu. Sonuç ÇİFT hataydı: aynı sayı hem
# `no_number` hem de (işaretin nöbetçisi ulaşılamadığı için)
# `missing_fact_marker` sayılıp payı VE paydayı şişiriyordu.
#
# Bu jetonlar ANLAM TAŞIMAZ: rakam, `%`, birim harfi ya da ayraç değildirler.
# Silinmeleri hiçbir gerçek denetimi zayıflatmaz — sayı, birim, değer ve
# toplulaştırma denetimleri aynen çalışır.
.PK_PROV_EMPHASIS <- "[*_`~]"

# Markdown vurgusu ve bölünemez boşluk, sayı ile birimi/işaretini AYIRIR ama
# hiçbir anlam taşımaz. Doğrulama KOPYASI üzerinde BOŞLUKLA değiştirilir
# (silinmez: `5*3` gibi bir ifade tek sayıya birleşmemelidir). `_` burada
# DEĞİŞTİRİLMEZ çünkü olgu kimliklerinde geçerlidir; pencere kırpıcıları onu
# zaten ele alır. Kullanıcıya GÖSTERİLEN metin bu dönüşümden etkilenmez.
.pk_prov_normalize_markup <- function(txt) {
  metin <- as.character(txt %||% "")[1]
  if (is.na(metin)) return("")
  metin <- gsub("[*`~]", " ", metin, perl = TRUE)
  gsub("\u00a0", " ", metin, perl = TRUE)
}
.PK_PROV_TRAILING <- "[[:space:]\u00a0)\\]}>\"'’”»,.;:!?…\\-]"

# SAYI İLE NÖBETÇİ ARASINA GİREN ÖLÇÜLEN VARLIK ADI (PR #705 incelemesi, P2).
#
# Prompt kuralı işareti sayının ARDINA koydurur, ama model doğal Türkçe yazınca
# araya ölçülen varlığın adı girer: `Toplam 15.574 geciken aktivite [fact:f].`
# Alıntı tarayıcısı sona dayalı desenle eşleşemeyip `no_number`, köken-siz
# tarayıcı ise nöbetçiyi bulamayıp `missing_fact_marker` kaydediyordu; TEK bir
# doğru alıntı için `checked = 2, mismatches = 2` üretiliyordu ve `block`
# kipinde DOĞRU yanıt yedekle değiştiriliyordu.
#
# Boşluk SINIRLIDIR ve yalnızca RAKAM İÇERMEYEN sözcüklerden oluşabilir: araya
# başka bir SAYI girerse alıntı yine köken-siz sayılır.
.PK_PROV_MAX_GAP_WORDS <- 3L
.PK_PROV_GAP_WORD <- "[A-Za-zÇĞİÖŞÜçğıöşü][A-Za-zÇĞİÖŞÜçğıöşü]{0,23}"

.pk_prov_trim_tail <- function(txt) {
  metin <- as.character(txt %||% "")[1]
  if (is.na(metin)) return("")

  # Vurgu imleri metnin İÇİNDE de olabilir (`**15.574** adet`).
  metin <- gsub(.PK_PROV_EMPHASIS, "", metin, perl = TRUE)

  onceki <- ""
  while (!identical(onceki, metin)) {
    onceki <- metin
    # Türkçe kesme eki: `adet'tir`, `saat’te`.
    metin <- sub("['’][A-Za-zÇĞİÖŞÜçğıöşü]*$", "", metin, perl = TRUE)
    metin <- sub(paste0(.PK_PROV_TRAILING, "+$"), "", metin, perl = TRUE)
  }
  metin
}

.pk_prov_unit_fold <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (length(txt) != 1L || is.na(txt)) return("")
  # KÜÇÜK HARFLİ Türkçe harfler de katlanır. Yalnızca büyük harfler
  # katlandığında `"gün"` (olgu birimi) ile `"gun"` (yanıt metni) FARKLI
  # kalıyordu: iki taraf da sözlükte tanınıyor ama karşılaştırma `unit_mismatch`
  # üretiyordu ve `block` kipinde DOĞRU bir yanıt gizleniyordu.
  txt <- chartr("ÇĞİIÖŞÜçğıöşü", "cgiiosucgiosu", txt)
  txt <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
  trimws(sub("[.]+$", "", txt))
}

# Birimsiz bir olguya uydurulmuş birim eklendiğini ancak GERÇEK bir birim
# sözlüğüne karşı söyleyebiliriz: "47 farkli kaynak" ifadesindeki "farkli"
# birim değildir ve işaretlenmemelidir; "47 saat" ise işaretlenmelidir.
.PK_PROV_KNOWN_UNITS <- c("%", "tl", "try", "usd", "eur", "saat", "gun", "gün",
                          "adet", "kisi", "kişi", "ay", "yil", "yıl", "m2", "m²",
                          "adam-saat", "kisi/saat", "kişi/saat")

# BOYUTSUZ SAYIM BİRİMLERİ. Bir sayım olgusunun ölçeği birimden GELMEZ; "adet"
# yalnızca "kaç tane" der. Bu yüzden düzyazıda YAZILMAMASI ölçek kaybı
# DEĞİLDİR ("15.574 geciken aktivite" tamamen açıktır). Ölçek taşıyan birimler
# (%/TL/saat/gün) bu listede YOKTUR ve onların atlanması işaretlenmeye devam
# eder.
.PK_PROV_COUNT_UNITS <- c("adet", "kayit", "kayıt", "tane")

# Sözlük, karşılaştırma yapılacak biçimde (katlanmış) bir kez hazırlanır.
.PK_PROV_KNOWN_UNITS_FOLDED <- unique(vapply(.PK_PROV_KNOWN_UNITS,
                                             .pk_prov_unit_fold, character(1),
                                             USE.NAMES = FALSE))

.pk_prov_unit_vocabulary <- function(index) {
  bilinen <- vapply(index, function(o) .pk_prov_unit_fold(o$unit %||% ""), character(1))
  unique(c(.PK_PROV_KNOWN_UNITS, bilinen[nzchar(bilinen)]))
}

# BİRİMİN EKLİ BİÇİMİ DE BİRİMDİR (PR #705 inceleme, P3).
#
# `.pk_prov_unit_fold()` Türkçe TÜRETME EKLERİNİ atmaz; `saatlik`, `gunluk`,
# `adetlik` sözlükte YOKTUR ve birim kapısı onları "birim değil" sayıp
# SIFIRLIYORDU. Olgu ölçek taşıyan bir birim beyan ettiğinde iddia o zaman
# `unit_missing` üretiyor, `block` kipinde DOĞRU bir model yanıtı deterministik
# yedekle değiştiriliyor, `warn` kipinde doğru bir sayı "doğrulanmadı" diye
# işaretleniyordu.
#
# YALNIZCA AÇIK TÜRETME EKLERİ kabul edilir. Serbest önek eşleşmesi
# (`ayrica` -> `ay`, `ayni` -> `ay`) sıradan Türkçe sözcükleri birim sanıp YENİ
# yanlış pozitifler üretirdi; bu liste bilinçli olarak dardır.
.PK_PROV_UNIT_DERIV_SUFFIXES <- c("lik", "luk", "li", "lu")

.pk_prov_unit_root <- function(folded, vocabulary) {
  if (!nzchar(folded)) return("")
  for (birim in vocabulary) {
    uf <- .pk_prov_unit_fold(birim)
    if (!nzchar(uf) || nchar(uf) < 2L) next
    if (identical(folded, uf)) return(uf)
    if (startsWith(folded, uf) &&
        substring(folded, nchar(uf) + 1L) %in% .PK_PROV_UNIT_DERIV_SUFFIXES) {
      return(uf)
    }
  }
  ""
}

# Türkçe toplulaştırma sözcükleri -> olgu toplulaştırması. Yalnızca AÇIKÇA
# tanınan bir sözcük, alıntılanan olgunun toplulaştırmasıyla ÇELİŞTİĞİNDE
# işaretlenir; bu, "bir toplamı ortalama diye sunmak" durumunu yakalar.
.PK_PROV_AGG_WORDS <- list(
  sum = c("toplam", "toplami", "toplamı"),
  mean = c("ortalama", "ortalamasi", "ortalaması"),
  weighted_mean = c("agirlikli ortalama", "ağırlıklı ortalama"),
  median = c("medyan", "ortanca"),
  max = c("en yuksek", "en yüksek", "maksimum", "azami"),
  min = c("en dusuk", "en düşük", "minimum", "asgari"),
  latest = c("en yeni", "en guncel", "en güncel")
)

.pk_prov_claimed_aggregation <- function(context) {
  txt <- .pk_prov_unit_fold(context)
  if (!nzchar(txt)) return(NULL)

  # İDDİAYA EN YAKIN TOPLULAŞTIRMA SÖZCÜĞÜ KAZANIR.
  #
  # Eskiden pencerede birden fazla FARKLI toplulaştırma sözcüğü geçtiğinde
  # `NULL` dönülüyor ve denetim TAMAMEN atlanıyordu. Bu, denetimi atlatmak için
  # yeterliydi: "Toplam 100 [fact:mean]" doğru biçimde reddedilirken
  # "Önce ortalama incelendi. Toplam 100 [fact:mean]" geçiyordu. Sözcüğün
  # KONUMU kullanılır; iddiaya en yakın (en sağdaki) terim iddianın terimidir.
  en_yakin <- NULL
  en_yakin_kalip <- NULL
  en_yakin_konum <- -1L

  for (agg in names(.PK_PROV_AGG_WORDS)) {
    for (sozcuk in .PK_PROV_AGG_WORDS[[agg]]) {
      kalip <- .pk_prov_unit_fold(sozcuk)
      konumlar <- gregexpr(kalip, txt, fixed = TRUE)[[1]]
      baslangic <- max(as.integer(konumlar))
      if (is.na(baslangic) || baslangic < 1L) next

      # BİLEŞİK İFADE, İÇİNDEKİ KISA İFADEYE YENİLEMEZ.
      #
      # Karşılaştırma BAŞLANGIÇ konumuna göre yapıldığında "ağırlıklı ortalama"
      # içindeki "ortalama" DAHA SAĞDA başladığı için kazanıyor ve geçerli bir
      # `weighted_mean` alıntısı `mean` sanılıp toplulaştırma uyuşmazlığı
      # üretiyordu (`block` kipinde model anlatısı düşerdi). BİTİŞ konumu
      # kullanılır: iç içe eşleşmeler AYNI yerde biter ve o zaman daha UZUN
      # (daha özgül) ifade kazanır. İddiaya yakınlık semantiği korunur.
      son <- baslangic + nchar(kalip) - 1L
      if (son > en_yakin_konum ||
          (son == en_yakin_konum && nchar(kalip) > nchar(.pk_prov_unit_fold(en_yakin_kalip %||% "")))) {
        en_yakin_konum <- son
        en_yakin <- agg
        en_yakin_kalip <- kalip
      }
    }
  }

  en_yakin
}

#' Olguları kimliğe göre indeksle
#'
#' Aynı kimliğe iki farklı olgu düşerse İKİSİ DE kullanılamaz sayılır: sessizce
#' birini ezmek, doğru alıntılanmış bir sayının YANLIŞ ölçüye karşı
#' doğrulanması demekti.
pk_facts_index <- function(facts) {
  out <- list()
  for (olgu in (facts %||% list())) {
    if (!is.list(olgu) || !is.character(olgu$fact_id) || !nzchar(olgu$fact_id)) next

    mevcut <- out[[olgu$fact_id]]
    if (is.null(mevcut)) {
      out[[olgu$fact_id]] <- olgu
      next
    }
    if (identical(mevcut$value, olgu$value) && identical(mevcut$column, olgu$column) &&
        identical(mevcut$aggregation, olgu$aggregation)) {
      next
    }

    belirsiz <- mevcut
    belirsiz$value <- NULL
    belirsiz$status <- "ambiguous_fact_id"
    belirsiz$note <- "Ayni kimlige birden fazla olgu dustu; alintilanamaz."
    out[[olgu$fact_id]] <- belirsiz
  }
  out
}

#' Sayısal iddiaları olgulara karşı doğrula
#'
#' @return `list(checked=, mismatches=, rate=, claims=)`
pk_numeric_provenance_validate <- function(text, facts) {
  index <- pk_facts_index(facts)
  # Doğrulama, biçimlendirmeden ARINDIRILMIŞ bir kopya üzerinde çalışır; her
  # iki tarayıcı (alıntılı ve alıntısız) AYNI metni görmelidir, aksi hâlde
  # aynı sayı bir tarayıcıda alıntılı, diğerinde köksüz görünür.
  metin <- .pk_prov_normalize_markup(text)
  iddialar <- .pk_prov_claims(metin)
  sozluk <- .pk_prov_unit_vocabulary(index)
  uyusmazliklar <- list()

  ekle <- function(...) {
    uyusmazliklar[[length(uyusmazliklar) + 1L]] <<- list(...)
    invisible(NULL)
  }

  for (iddia in iddialar) {
    olgu <- index[[iddia$fact_id]]

    if (is.null(olgu)) {
      ekle(fact_id = iddia$fact_id, reason = "unknown_fact", claimed = iddia$number_text)
      next
    }

    # DEĞER SONLU SKALER OLMAK ZORUNDADIR: `numeric(0)` YANLIŞ gerekçe (`value_mismatch`) üretiyor, çok ögeli değer ise geri dönüşümlü karşılaştırma yüzünden BELİRSİZ bir olguya yapılan alıntıyı KABUL ediyordu -- bu doğrulayıcının tam da reddetmesi gereken durum.
    olgu_deger <- suppressWarnings(as.numeric(olgu$value %||% NA_real_))
    if (is.null(olgu$value) || length(olgu_deger) != 1L || is.na(olgu_deger) || !is.finite(olgu_deger)) {
      ekle(fact_id = iddia$fact_id, reason = "unavailable_fact", claimed = iddia$number_text, status = olgu$status)
      next
    }

    adaylar <- iddia$candidates %||% numeric(0)
    if (!length(adaylar)) {
      ekle(fact_id = iddia$fact_id, reason = "no_number", claimed = iddia$raw)
      next
    }

    # Belirsiz nokta biçimlerinde olguyla eşleşen yorum kabul edilir; hiçbiri
    # eşleşmiyorsa iddia yine reddedilir.
    tolerans <- .pk_prov_tolerance(iddia$number_text, olgu_deger, olgu)
    if (!any(abs(adaylar - olgu_deger) <= tolerans)) {
      ekle(fact_id = iddia$fact_id, reason = "value_mismatch", claimed = iddia$number_text, actual = olgu_deger)
      next
    }

    # Anlamsal denetim: doğru sayı YANLIŞ ölçü için alıntılanamaz.
    olgu_birimi <- .pk_prov_unit_fold(olgu$unit %||% "")
    iddia_birimi <- .pk_prov_unit_fold(iddia$unit)

    # SAYIDAN SONRAKİ HER SÖZCÜK BİRİM DEĞİLDİR.
    #
    # Örüntü, sayıyı izleyen TEK jetonu "iddia edilen birim" olarak alıyordu.
    # `15.574 aktivite [fact:...]` gibi tamamen doğru bir cümlede "aktivite"
    # ÖLÇÜLEN ŞEYDİR, birim değildir; olgunun birimi "adet" olduğu için bu
    # sıradan Türkçe ad `unit_mismatch` üretiyordu (üretimde ölçülen yanlış
    # pozitif). Ters yön (birimsiz olguya uydurulmuş birim) ZATEN sözlük
    # üyeliği istiyordu; iki yön artık SİMETRİKTİR. Gerçek bir yanlış birim
    # (ör. "saat" yerine "adet") sözlükte olduğu için hâlâ yakalanır.
    # EKLİ BİÇİM ÖNCE KÖKÜNE İNDİRGENİR (bkz. `.pk_prov_unit_root()`); sözlükte
    # karşılığı olmayan jeton yine SIFIRLANIR ve eski simetri korunur.
    if (nzchar(iddia_birimi) && !(iddia_birimi %in% sozluk)) {
      iddia_birimi <- .pk_prov_unit_root(iddia_birimi, sozluk)
    }

    if (isTRUE(iddia$percent) && !identical(olgu_birimi, "%")) {
      ekle(fact_id = iddia$fact_id, reason = "unit_mismatch",
           claimed = "%", actual = olgu_birimi)
      next
    }

    if (!isTRUE(iddia$percent) && identical(olgu_birimi, "%") && nzchar(iddia_birimi)) {
      ekle(fact_id = iddia$fact_id, reason = "unit_mismatch",
           claimed = iddia$unit, actual = olgu_birimi)
      next
    }

    if (nzchar(iddia_birimi) && nzchar(olgu_birimi) &&
        !identical(iddia_birimi, olgu_birimi)) {
      ekle(fact_id = iddia$fact_id, reason = "unit_mismatch",
           claimed = iddia$unit, actual = olgu_birimi)
      next
    }

    # OLGU BİR BİRİM BEYAN EDİYORSA, İDDİA ONU ATLAYAMAZ.
    #
    # Eski denetimlerin hepsi `nzchar(iddia_birimi)` koşuluna bağlıydı; yani
    # birimi HİÇ yazmamak doğrulamayı sessizce geçiyordu. Yüzde bir olgu
    # "%61,3" yerine yalnızca "61,3" diye sunulduğunda okuyucu bunu mutlak bir
    # sayı sanar. Aynı şey para/saat gibi beyan edilmiş birimler için de
    # geçerlidir: birimsiz sunulan bir tutar ölçek bilgisini kaybeder.
    if (nzchar(olgu_birimi) && !nzchar(iddia_birimi) && !isTRUE(iddia$percent) &&
        !(olgu_birimi %in% .PK_PROV_COUNT_UNITS)) {
      ekle(fact_id = iddia$fact_id, reason = "unit_missing",
           claimed = "(birimsiz)", actual = olgu_birimi)
      next
    }

    # BİRİMSİZ bir olguya birim UYDURULAMAZ. Sıradan düzyazı sözcükleri
    # ("47 farkli kaynak") işaretlenmesin diye yalnızca GERÇEK bir birim
    # sözlüğüne düşen jetonlar uyuşmazlık sayılır.
    # SAYIM OLGUSUNA "adet" YAZMAK BİRİM UYDURMAK DEĞİLDİR.
    #
    # Bağlam olguları (satır sayısı, farklı değer sayısı, kategori/tarih
    # sayısı, grup satırı) `unit` beyan etmez; modelin doğal Türkçesi ise
    # "50.045 adet" der. Bu, birimsiz bir ölçüye ölçek uydurmak DEĞİLDİR:
    # sayımın boyutsuz birimidir. Ölçek taşıyan bir birim (saat/TL/%) yine
    # uyuşmazlıktır.
    sayim_olgusu <- identical(as.character(olgu$kind %||% "")[1], "context") ||
      identical(as.character(olgu$aggregation %||% "")[1], "count") ||
      grepl("count|rows|duplicates", as.character(olgu$aggregation %||% "")[1], perl = TRUE)

    if (!nzchar(olgu_birimi) && nzchar(iddia_birimi) &&
        !(isTRUE(sayim_olgusu) && iddia_birimi %in% .PK_PROV_COUNT_UNITS) &&
        (isTRUE(iddia$percent) || iddia_birimi %in% sozluk)) {
      ekle(fact_id = iddia$fact_id, reason = "unit_mismatch",
           claimed = iddia$unit, actual = "(birimsiz)")
      next
    }

    # Toplulaştırma denetimi: bir TOPLAM "ortalama" diye sunulamaz. Yalnızca
    # açıkça tanınan bir toplulaştırma sözcüğü, olgunun toplulaştırmasıyla
    # çeliştiğinde işaretlenir.
    iddia_agg <- .pk_prov_claimed_aggregation(iddia$context)
    olgu_agg <- as.character(olgu$aggregation %||% "")[1]
    if (!is.null(iddia_agg) && nzchar(olgu_agg) && !identical(iddia_agg, olgu_agg) &&
        olgu_agg %in% names(.PK_PROV_AGG_WORDS)) {
      ekle(fact_id = iddia$fact_id, reason = "aggregation_mismatch",
           claimed = iddia_agg, actual = olgu_agg)
    }
  }

  # İŞARETSİZ SAYISAL İDDİALAR DA UYUŞMAZLIKTIR.
  #
  # Bunlar `iddialar` içinde YER ALMAZ (bir olguya bağlı değiller), bu yüzden
  # hem `checked` hem de payda onları KAPSAYACAK biçimde genişletilir; aksi
  # hâlde tamamı işaretsiz bir yanıtta `rate` sıfır çıkar ve eşik tabanlı
  # kipler hiçbir şey yakalamaz.
  kokensizler <- .pk_prov_uncited_claims(metin)
  for (k in kokensizler) {
    ekle(fact_id = NA_character_, reason = "missing_fact_marker",
         claimed = k$raw, actual = NA_character_)
  }

  toplam <- length(iddialar) + length(kokensizler)

  list(
    checked = toplam,
    mismatches = uyusmazliklar,
    rate = if (toplam) length(uyusmazliklar) / toplam else 0,
    claims = iddialar,
    uncited = kokensizler
  )
}

#' Referans işaretlerini gösterimden temizle
pk_numeric_provenance_strip <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt)) return("")
  txt <- gsub(paste0("[[:space:]]*", .PK_PROV_MARKER), "", txt, perl = TRUE)
  txt
}

#' Doğrulamayı uygula ve gösterilecek metni üret
#'
#' `block` kipinde düzyazı REDDEDİLİR: yeniden üretim isteği çağıranın
#' sorumluluğundadır; bu fonksiyon deterministik yedek metni döndürür.
#'
#' @param fallback_text `block` kipinde gösterilecek deterministik metin.
pk_numeric_provenance_apply <- function(text, facts, mode = NULL, fallback_text = NULL) {
  kip <- as.character(mode %||% pk_numeric_provenance_mode())[1]
  if (!(kip %in% PK_PROV_MODES)) kip <- "log"

  ham <- as.character(text %||% "")[1]
  if (is.na(ham)) ham <- ""

  if (identical(kip, "off")) {
    return(list(text = pk_numeric_provenance_strip(ham), mode = kip,
                checked = 0L, mismatches = list(), rate = 0, blocked = FALSE))
  }

  # KAPALI BAŞARISIZLIK: bozuk bir olgu/metadata uç durumu doğrulayıcıyı
  # düşürürse çağıran ham model metnini gösterirdi — `block` kipinde bile.
  # Hata, `block` davranışının aynısına (deterministik yedek) indirgenir.
  sonuc <- tryCatch(pk_numeric_provenance_validate(ham, facts), error = function(e) {
    cat(sprintf("[PK_ANALIZ] Sayisal koken dogrulamasi hata verdi: %s\n",
                conditionMessage(e)))
    NULL
  })

  if (is.null(sonuc)) {
    # KALİBRASYON KİPLERİ KULLANICIYA GÖRÜNEN YANITI DEĞİŞTİRMEZ. Dosya
    # başlığındaki sözleşme açıktır: `log` VARSAYILANDIR ve "uyuşmazlıklar
    # KAYDEDİLİR, yanıt değişmez" demektir. Bu dal kipi hiç okumadan reddetme
    # metnini ve `blocked = TRUE` döndürüyordu; yani doğrulayıcıdaki tek bir uç
    # durum (bozuk olgu kaydı, beklenmeyen `unit`/`aggregation` şekli),
    # ZORLAMAYI HİÇ AÇMAMIŞ her kurulumda model açıklamasını kullanıcıdan
    # gizliyor ve kalibrasyon kipini fiilen `block` gibi çalıştırıyordu.
    # Kapalı başarısızlık YALNIZCA zorlama kiplerinde (`warn`/`block`) sürer;
    # hata her kipte `mismatches` üzerinden kaydedilmeye devam eder.
    if (kip %in% c("off", "log")) {
      return(list(
        text = pk_numeric_provenance_strip(ham), mode = kip, checked = 0L,
        mismatches = list(list(reason = "validator_error")), rate = 1,
        blocked = FALSE
      ))
    }

    yedek <- as.character(fallback_text %||% "")[1]
    return(list(
      text = paste0(
        "\U000026A0\U0000FE0F **Yanıt doğrulanamadı:** Sayısal köken denetimi ",
        "beklenmeyen bir hatayla karşılaştı; açıklama gösterilmiyor. Aşağıdaki ",
        "değerler R tarafından hesaplanmıştır.",
        if (!is.na(yedek) && nzchar(yedek)) paste0("\n\n", yedek) else ""
      ),
      mode = kip, checked = 0L,
      mismatches = list(list(reason = "validator_error")), rate = 1, blocked = TRUE
    ))
  }

  temiz <- pk_numeric_provenance_strip(ham)

  if (identical(kip, "warn") && length(sonuc$mismatches)) {
    parcalar <- vapply(sonuc$mismatches, function(m) {
      sprintf("%s (%s)", as.character(m$claimed %||% "?")[1], m$reason)
    }, character(1))
    temiz <- paste0(
      temiz,
      "\n\n\U000026A0\U0000FE0F **Doğrulanamayan sayılar:** ",
      paste(unique(parcalar), collapse = ", "),
      ". Bu değerler hesaplanan olgularla eşleştirilemedi; lütfen ekteki ",
      "deterministik tabloyu esas alın."
    )
  }

  engellendi <- identical(kip, "block") && length(sonuc$mismatches) > 0L
  if (engellendi) {
    yedek <- as.character(fallback_text %||% "")[1]
    temiz <- paste0(
      "\U000026A0\U0000FE0F **Yanıt doğrulanamadı:** Üretilen açıklamadaki sayılar ",
      "hesaplanan olgularla eşleşmedi; açıklama gösterilmiyor. Aşağıdaki ",
      "değerler R tarafından hesaplanmıştır.",
      if (nzchar(yedek) && !is.na(yedek)) paste0("\n\n", yedek) else ""
    )
  }

  list(
    text = temiz, mode = kip, checked = sonuc$checked,
    mismatches = sonuc$mismatches, rate = sonuc$rate, blocked = engellendi
  )
}

#' Ölçülen uyuşmazlık oranını sunucu tarafında raporla (sırsız)
#'
#' Yalnızca sayaç/oran ve uyuşmazlık nedenleri yazılır; düzyazı, soru metni ya
#' da herhangi bir veri değeri LOGA GİRMEZ.
pk_numeric_provenance_report <- function(result, query_id = NULL) {
  if (!is.list(result)) return(invisible(NULL))

  nedenler <- vapply(result$mismatches %||% list(),
                     function(m) as.character(m$reason %||% "?")[1], character(1))
  ozet <- if (length(nedenler)) paste(sort(unique(nedenler)), collapse = ",") else "-"

  cat(sprintf(
    "[PK_ANALIZ] Sayisal koken | kip=%s | sorgu=%s | iddia=%d | uyusmazlik=%d | oran=%.3f | nedenler=%s\n",
    result$mode %||% "?", as.character(query_id %||% "?")[1],
    as.integer(result$checked %||% 0L), length(result$mismatches %||% list()),
    as.numeric(result$rate %||% 0), ozet
  ))

  invisible(result)
}
