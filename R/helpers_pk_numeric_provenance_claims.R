# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance_claims.R
# Açıklama: Düzyazıdaki SAYISAL İDDİA tarayıcıları — master plan §5.11.
#
#           `R/helpers_pk_numeric_provenance.R` dosyasından AYRILDI: doğrulayıcı
#           katmanı (kip çözümleme, sayı ayrıştırma, tolerans, doğrulama/uygulama
#           ve raporlama) ile düzyazı TARAMA katmanı ayrı sorumluluklardır ve tek
#           dosyada 800 satır bakım ratchet'ini aşıyordu.
#
#           Bu dosya İKİ tarayıcı içerir ve ikisi AYNI bitişiklik kuralını
#           uygular (PR #705 incelemesi, P2): sayı ile `[fact:...]` işareti
#           arasında RAKAM İÇERMEYEN en fazla `.PK_PROV_MAX_GAP_WORDS` sözcük
#           bulunabilir. Kural yalnızca birinde uygulanırsa TEK bir doğru alıntı
#           iki ayrı uyuşmazlık olarak sayılır ve `block` kipinde DOĞRU yanıt
#           deterministik yedekle değiştirilir.
#
#           Yükleme sırası: bu dosya `R/helpers_pk_numeric_provenance.R`
#           dosyasından SONRA yüklenir; tarayıcılar orada tanımlanan
#           `.PK_PROV_*` sabitlerini ve `pk_parse_number_*()` /
#           `.pk_prov_*()` yardımcılarını ÇAĞRI ANINDA çözer.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

# Metindeki her `[fact:...]` referansını ve hemen ÖNCESİNDEKİ sayıyı çıkarır.
.pk_prov_claims <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(list())

  konum <- gregexpr(.PK_PROV_MARKER, txt, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())

  uzunluk <- attr(konum, "match.length")
  out <- list()

  for (i in seq_along(konum)) {
    isaret <- substr(txt, konum[i], konum[i] + uzunluk[i] - 1L)
    fact_id <- sub("^\\[fact:", "", sub("\\]$", "", isaret))

    # Bağlam penceresi hem sayıyı hem de iddia edilen toplulaştırma sözcüğünü
    # ("toplam", "ortalama", ...) yakalayacak kadar geniştir.
    onceki <- substr(txt, max(1L, konum[i] - 160L), konum[i] - 1L)
    # PENCERE ÖNCEKİ İDDİANIN SINIRINDA KESİLİR.
    #
    # 160 karakterlik pencere iddia sınırlarını aşabiliyordu: "Ortalama süre 5
    # saat [fact:mean]. Bütçe 100 TL [fact:sum]" metninde ikinci iddianın kendi
    # toplulaştırma sözcüğü yoktur ve pencerede bulunan en sağdaki terim
    # `Ortalama` olduğu için DOĞRU `sum` olgusu `aggregation_mismatch`
    # bildiriyordu; `block` kipinde geçerli yanıt düşüyordu. Pencere önce
    # ÖNCEKİ İŞARETTE, sonra son cümle sınırında kesilir.
    if (i > 1L) {
      onceki_son <- konum[i - 1L] + uzunluk[i - 1L] - 1L
      if (onceki_son >= max(1L, konum[i] - 160L)) {
        onceki <- substr(txt, onceki_son + 1L, konum[i] - 1L)
      }
    }
    # CÜMLE SONU DESENİ ONDALIK/BİNLİK NOKTAYI SAYMAZ: `18.420` içindeki nokta
    # sınır sayılsaydı iddia edilen değer `420` olur ve DOĞRU alıntı
    # `value_mismatch` bildirilirdi. Sınır, ardından boşluk/son gelen `.!?`.
    cumle <- gregexpr("[.!?](?=\\s|$)", onceki, perl = TRUE)[[1]]
    if (!identical(cumle[1], -1L)) {
      onceki <- substr(onceki, cumle[length(cumle)] + 1L, nchar(onceki))
    }
    yakin <- .pk_prov_trim_tail(substr(onceki, max(1L, nchar(onceki) - 60L), nchar(onceki)))

    # Birim yalnızca 1-12 harf değildir: `kişi/saat`, `adam-saat`, `m²`, `TL`
    # gibi bileşik/simgesel birimler de olgunun gösteriminde geçebilir.
    #
    # DEVAM SINIFI RAKAM DA İÇERİR. `.PK_PROV_KNOWN_UNITS` `m2` biçimini kabul
    # ederken devam sınıfında `0-9` yoktu; `12 m2 [fact:...]` metninde sona
    # dayalı desen "12 m2" ile eşleşemiyor, geriye dönüp yalnızca sondaki `2`
    # ile eşleşiyordu. Doğrulayıcı da iddia edilen değeri `2` sanıp
    # `value_mismatch` bildiriyor, `block` kipinde DOĞRU yanıt yedekle
    # değiştiriliyordu. Birimin İLK karakteri hâlâ rakam OLAMAZ (aksi hâlde
    # "12 34" ifadesinde `34` birim sanılırdı).
    sayi_deseni <- paste0("(%\\s*)?-?[0-9][0-9.,]*\\s*",
                          "(%|[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac]",
                          "[A-Za-z0-9ÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac/.-]{0,23})?\\s*$")
    eslesme <- regmatches(yakin, gregexpr(sayi_deseni, yakin, perl = TRUE))[[1]]

    # ÖNCE mevcut (bitişik) davranış denenir; birim yakalaması KORUNUR. Yalnızca
    # hiç sayı bulunamadığında araya giren en fazla `.PK_PROV_MAX_GAP_WORDS`
    # sözcük tek tek kırpılıp yeniden denenir. Kırpılan sözcükler RAKAM
    # İÇERMEZ, bu yüzden araya giren ikinci bir sayı bu yolu AÇMAZ.
    if (!length(eslesme) || !nzchar(trimws(eslesme[length(eslesme)]))) {
      kalan <- yakin
      for (adim in seq_len(.PK_PROV_MAX_GAP_WORDS)) {
        kirpik <- sub(paste0("\\s+", .PK_PROV_GAP_WORD,
                             "[.,;:!?]*\\s*$"), "", kalan, perl = TRUE)
        if (identical(kirpik, kalan)) break
        kalan <- kirpik
        eslesme <- regmatches(kalan, gregexpr(sayi_deseni, kalan, perl = TRUE))[[1]]
        if (length(eslesme) && nzchar(trimws(eslesme[length(eslesme)]))) break
      }
    }

    ham <- if (length(eslesme)) trimws(eslesme[length(eslesme)]) else ""
    yuzde <- grepl("%", ham, fixed = TRUE)
    sayi_metni <- trimws(gsub("%", "", ham))
    birim <- sub("^-?[0-9][0-9.,]*\\s*", "", sayi_metni)
    sayi_metni <- regmatches(sayi_metni, regexpr("^-?[0-9][0-9.,]*", sayi_metni))
    sayi_metni <- if (length(sayi_metni)) sayi_metni[1] else ""

    out[[length(out) + 1L]] <- list(
      fact_id = fact_id,
      marker = isaret,
      raw = ham,
      number_text = sayi_metni,
      value = pk_parse_number_tr(sayi_metni),
      candidates = pk_parse_number_candidates(sayi_metni),
      percent = yuzde,
      unit = trimws(birim),
      context = onceki
    )
  }

  out
}

# İŞARETSİZ (KÖKENSİZ) SAYISAL İDDİALARI BUL.
#
# `.pk_prov_claims()` YALNIZCA bir `[fact:...]` işaretinin ÖNÜNDEKİ sayıyı
# görür. Model istem kuralını yok sayıp `Toplam 99.999 saat` yazdığında iddia
# kümesi BOŞ kalıyor, doğrulayıcı "uyuşmazlık yok" diyor ve `warn`/`block`
# kipleri bile halüsinasyon sayıyı DEĞİŞMEDEN yayımlıyordu; yani yapılandırılan
# köken zorunluluğu bozuk model çıktısıyla ATLATILABİLİYORDU.
#
# Yanlış pozitiften kaçınmak için yalnızca VERİ görünümlü sayılar sayılır:
# ondalık/binlik ayraç taşıyanlar, yüzde işaretliler, birim ekli olanlar ya da
# dört haneden uzun tam sayılar. Yıl (1900-2100), madde numarası ve birimsiz
# küçük tam sayılar KAPSAM DIŞIDIR.
.pk_prov_uncited_claims <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(list())

  # Isaretin kendisi taranmaz, ancak YERI korunur: bir sayinin ARDINDAN
  # gelen nobetci, o sayinin ALINTILANDIGINI gosterir.
  nobetci <- intToUtf8(1L)
  maskeli <- gsub(.PK_PROV_MARKER, nobetci, txt, perl = TRUE)

  # ALT ÇİZGİ VURGUSU MASKELİ KOPYADA NÖTRLENİR: işaretler yukarıda nöbetçiye
  # çevrildiği için `_` artık hiçbir olgu kimliğinin parçası değildir.
  # Korunduğunda alt çizgiyle vurgulanmış DOĞRU alıntılanmış bir sayı hem
  # geçerli sayılıyor hem `missing_fact_marker` kaydediliyordu (`block` kipinde
  # doğru yanıt yedekle değiştirilirdi). Silinmez, boşlukla değiştirilir.
  maskeli <- gsub("_", " ", maskeli, fixed = TRUE)

  # DEVAM SINIFI RAKAM DA İÇERİR (alıntılı taramayla AYNI sınıf). Aksi hâlde
  # `1.234 m2 [fact:alan]` eşleşmesi `1.234 m` ile duruyor, artakalan `2`
  # nöbetçi denetimini bloke ediyor ve DOĞRU alıntılanmış bir sayı
  # `missing_fact_marker` kaydediliyordu; `block` kipinde geçerli yanıt yedekle
  # değiştiriliyordu.
  desen <- paste0("(%\\s*)?-?[0-9][0-9.,]*\\s*",
                  "(%|[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac]",
                  "[A-Za-z0-9ÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac/.-]{0,23})?")

  konum <- gregexpr(desen, maskeli, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())
  uzunluk <- attr(konum, "match.length")

  out <- list()
  for (i in seq_along(konum)) {
    ham <- trimws(substr(maskeli, konum[i], konum[i] + uzunluk[i] - 1L))
    if (!nzchar(ham)) next

    # Hemen ARDINDAN gelen nobetci bu sayinin ALINTILANDIGI anlamina gelir.
    #
    # Pencere BILEREK genistir ve anlamsiz ayraclar (markdown vurgusu, kapanis
    # parantezi, noktalama, Turkce kesme eki) atlanir: `**15.574 adet**[fact:x]`
    # dogru bicimde ALINTILANMISTIR ve `missing_fact_marker` sayilamaz. Sadece
    # ayraclar atlanir; araya baska bir SAYI ya da harf girerse nobetci
    # bulunamaz ve iddia yine kokensiz sayilir.
    # Pencere, araya girebilecek en fazla `.PK_PROV_MAX_GAP_WORDS` sözcüğü de
    # kapsayacak kadar geniştir; sözcük atlama aşağıda AYRICA sınırlanır.
    kuyruk <- substr(maskeli, konum[i] + uzunluk[i],
                     min(nchar(maskeli),
                         konum[i] + uzunluk[i] + 24L +
                           .PK_PROV_MAX_GAP_WORDS * 26L))
    .prov_kirp <- function(x) {
      x <- gsub(.PK_PROV_EMPHASIS, "", x, perl = TRUE)
      x <- sub("^['’][A-Za-zÇĞİÖŞÜçğıöşü]*", "", x, perl = TRUE)
      sub(paste0("^", .PK_PROV_TRAILING, "+"), "", x, perl = TRUE)
    }
    kuyruk <- .prov_kirp(kuyruk)

    # ARAYA GİREN İSİM ÖBEĞİ NÖBETÇİYİ GİZLEMEZ (PR #705 incelemesi, P2).
    #
    # Alıntı tarayıcısıyla AYNI bitişiklik kuralı uygulanır: rakam içermeyen en
    # fazla `.PK_PROV_MAX_GAP_WORDS` sözcük atlanır. Araya başka bir SAYI
    # girerse desen eşleşmez ve iddia köken-siz sayılmaya DEVAM eder.
    if (!startsWith(kuyruk, nobetci)) {
      atlanan <- kuyruk
      for (adim in seq_len(.PK_PROV_MAX_GAP_WORDS)) {
        yeni <- sub(paste0("^", .PK_PROV_GAP_WORD), "", atlanan, perl = TRUE)
        if (identical(yeni, atlanan)) break
        atlanan <- .prov_kirp(yeni)
        if (startsWith(atlanan, nobetci)) break
      }
      kuyruk <- atlanan
    }
    if (startsWith(kuyruk, nobetci)) next

    yuzde <- grepl("%", ham, fixed = TRUE)
    sayi_metni <- trimws(gsub("%", "", ham))
    birim <- trimws(sub("^-?[0-9][0-9.,]*\\s*", "", sayi_metni))
    rakam <- regmatches(sayi_metni, regexpr("^-?[0-9][0-9.,]*", sayi_metni))
    rakam <- if (length(rakam)) rakam[1] else ""
    if (!nzchar(rakam)) next

    # Sondaki nokta/virgul AYRAC DEGILDIR: "1." bir madde numarasidir.
    rakam <- sub("[.,]+$", "", rakam)
    if (!nzchar(rakam)) next

    ayrac <- grepl("[.,]", rakam, perl = TRUE)
    sade <- gsub("[^0-9]", "", rakam)
    haneler <- nchar(sade)

    # TARİH VERİ İDDİASI DEĞİLDİR: noktalı tarih ayraç taşıdığından `veri_gibi`
    # TRUE oluyor, yıl kapısı ise `!ayrac` istediğinden devreye girmiyordu.
    # Pakette tarihin olgusu YOKTUR; `block` kipinde geçerli yanıt yedekle
    # değiştiriliyordu. Türkçe binlik ayracı ÜÇ haneli gruplar kullanır: 2+2+4
    # geçerli sayı biçimi değildir, gerçek ölçü yanlışlıkla elenmez.
    tarih_gibi <- !yuzde && (
      grepl("^[0-9]{1,2}[.][0-9]{1,2}[.][0-9]{4}$", rakam, perl = TRUE) ||
        grepl("^[0-9]{4}[.][0-9]{1,2}[.][0-9]{1,2}$", rakam, perl = TRUE)
    )
    if (isTRUE(tarih_gibi)) next

    # Yıl gibi görünen çıplak sayı: veri iddiası sayılmaz.
    # Yil, ARDINDAN bir sozcuk gelse de ("2024 yilinda") yil sayilir.
    #
    # ANCAK TANINAN BİR ÖLÇÜ BİRİMİ YIL YORUMUNU BOZAR: "Toplam 2024 saat"
    # 1900-2100 aralığında olduğu için köken taramasından KAÇIYOR ve işaretsiz
    # sayı `warn`/`block` kipinde uyuşmazlık üretmeden yayımlanıyordu.
    birim_ilk_yil <- .pk_prov_unit_fold(sub("[[:space:]].*$", "", birim))
    yil_gibi <- !ayrac && !yuzde && haneler == 4L &&
      !(nzchar(birim_ilk_yil) && birim_ilk_yil %in% .PK_PROV_KNOWN_UNITS_FOLDED) &&
      suppressWarnings(!is.na(as.integer(sade))) &&
      as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
    if (isTRUE(yil_gibi)) next

    # BİRİM VARLIĞI TEK BAŞINA YETMEZ: "3 kez" / "2. madde" gibi sıradan
    # ifadeler veri iddiası değildir ve `block` kipinde geçerli yanıtları
    # düşürmemelidir. Ölçek işareti aranır: ayraç, yüzde ya da 4+ hane.
    #
    # ANCAK TANINAN BİR ÖLÇÜ BİRİMİ DE ÖLÇEK İŞARETİDİR. "47 adet" ayraç, yüzde
    # ya da dört hane taşımaz; eski kapı onu veri DIŞI sayıyordu. Sonuç: `block`
    # kipinde köksüz bir sayı HİÇ uyuşmazlık üretmeden yayımlanıyor, yapılandırılan
    # köken zorlaması tam da hedeflediği durumda atlanıyordu. Sıra sayıları
    # ("2. madde") ve "kez" sözlükte YOKTUR; dışarıda kalmaya devam ederler.
    birim_ilk <- birim_ilk_yil
    veri_gibi <- ayrac || yuzde || haneler >= 4L ||
      (nzchar(birim_ilk) && birim_ilk %in% .PK_PROV_KNOWN_UNITS_FOLDED)
    if (!veri_gibi) next

    out[[length(out) + 1L]] <- list(raw = ham, number = rakam, unit = birim,
                                    percent = yuzde)
  }
  out
}
