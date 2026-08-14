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
#' `18.420` Türkçe binlik gruplamadır (18420), ama `0.613` nokta-ondalıktır ve
#' `12.345` ikisi de olabilir. Tek bir yorumu sessizce seçmek ya doğru bir
#' iddiayı bloklar (`0.613`ü 613 sanmak) ya da yanlış ölçekli bir iddiayı
#' onaylar. Bu yüzden belirsiz biçimde İKİ aday da döner; doğrulayıcı olguyla
#' eşleşen yorumu kabul eder, eşleşen yoksa iddia yine reddedilir.
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

    if (gruplama && nokta == 1L) {
      # Belirsiz: "12.345" hem 12345 hem 12,345 olabilir.
      adaylar <- c(gsub(".", "", ham, fixed = TRUE), ham)
    } else if (gruplama) {
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
.pk_prov_tolerance <- function(gosterim, gercek, olgu = NULL) {
  buyukluk <- abs(as.numeric(gercek))
  yuvarlama <- 0.5 * 10^(-.pk_prov_decimals(gosterim))
  maddiyet <- max(buyukluk * 1e-3, .Machine$double.eps * 16)

  min(yuvarlama, maddiyet) + buyukluk * .Machine$double.eps * 16
}

# Birim karşılaştırması yerelden bağımsız katlanır ("Saat" == "saat").
.pk_prov_unit_fold <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (length(txt) != 1L || is.na(txt)) return("")
  txt <- chartr("ÇĞİIÖŞÜ", "cgiiosu", txt)
  txt <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
  trimws(sub("[.]+$", "", txt))
}

# Birimsiz bir olguya uydurulmuş birim eklendiğini ancak GERÇEK bir birim
# sözlüğüne karşı söyleyebiliriz: "47 farkli kaynak" ifadesindeki "farkli"
# birim değildir ve işaretlenmemelidir; "47 saat" ise işaretlenmelidir.
.PK_PROV_KNOWN_UNITS <- c("%", "tl", "try", "usd", "eur", "saat", "gun", "gün",
                          "adet", "kisi", "kişi", "ay", "yil", "yıl", "m2", "m²",
                          "adam-saat", "kisi/saat", "kişi/saat")

.pk_prov_unit_vocabulary <- function(index) {
  bilinen <- vapply(index, function(o) .pk_prov_unit_fold(o$unit %||% ""), character(1))
  unique(c(.PK_PROV_KNOWN_UNITS, bilinen[nzchar(bilinen)]))
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
  en_yakin_konum <- -1L

  for (agg in names(.PK_PROV_AGG_WORDS)) {
    for (sozcuk in .PK_PROV_AGG_WORDS[[agg]]) {
      kalip <- .pk_prov_unit_fold(sozcuk)
      konumlar <- gregexpr(kalip, txt, fixed = TRUE)[[1]]
      son <- max(as.integer(konumlar))
      if (is.na(son) || son < 1L) next
      # Eşit konumda daha UZUN eşleşme daha özgüldür ("agirlikli ortalama"
      # yalnız "ortalama"yı yener).
      if (son > en_yakin_konum ||
          (son == en_yakin_konum && nchar(kalip) > nchar(.pk_prov_unit_fold(en_yakin %||% "")))) {
        en_yakin_konum <- son
        en_yakin <- agg
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
    yakin <- substr(onceki, max(1L, nchar(onceki) - 60L), nchar(onceki))

    # Birim yalnızca 1-12 harf değildir: `kişi/saat`, `adam-saat`, `m²`, `₺`
    # gibi bileşik/simgesel birimler de olgunun gösteriminde geçebilir.
    eslesme <- regmatches(
      yakin,
      gregexpr(paste0("(%\\s*)?-?[0-9][0-9.,]*\\s*",
                      "(%|[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac]",
                      "[A-Za-zÇĞİÖŞÜçğıöşü\u20ba\u00b2\u00b3$\u20ac/.-]{0,23})?\\s*$"),
               yakin, perl = TRUE)
    )[[1]]

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

  desen <- paste0("(%\\s*)?-?[0-9][0-9.,]*\\s*",
                  "(%|[A-Za-zÇĞİÖŞÜçğıöşü₺²³$€]",
                  "[A-Za-zÇĞİÖŞÜçğıöşü₺²³$€/.-]{0,23})?")

  konum <- gregexpr(desen, maskeli, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())
  uzunluk <- attr(konum, "match.length")

  out <- list()
  for (i in seq_along(konum)) {
    ham <- trimws(substr(maskeli, konum[i], konum[i] + uzunluk[i] - 1L))
    if (!nzchar(ham)) next

    # Hemen ARDINDAN gelen nobetci bu sayinin ALINTILANDIGI anlamina gelir.
    kuyruk <- substr(maskeli, konum[i] + uzunluk[i],
                     min(nchar(maskeli), konum[i] + uzunluk[i] + 4L))
    if (startsWith(trimws(kuyruk), nobetci)) next

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

    # Yıl gibi görünen çıplak sayı: veri iddiası sayılmaz.
    # Yil, ARDINDAN bir sozcuk gelse de ("2024 yilinda") yil sayilir.
    yil_gibi <- !ayrac && !yuzde && haneler == 4L &&
      suppressWarnings(!is.na(as.integer(sade))) &&
      as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
    if (isTRUE(yil_gibi)) next

    # BIRIM VARLIGI TEK BASINA YETMEZ: "3 kez" / "2. madde" gibi sıradan
    # ifadeler veri iddiasi degildir ve `block` kipinde gecerli yanitlari
    # dusurmemelidir. Olcek isareti aranir: ayrac, yuzde ya da 4+ hane.
    veri_gibi <- ayrac || yuzde || haneler >= 4L
    if (!veri_gibi) next

    out[[length(out) + 1L]] <- list(raw = ham, number = rakam, unit = birim,
                                    percent = yuzde)
  }
  out
}

#' Sayısal iddiaları olgulara karşı doğrula
#'
#' @return `list(checked=, mismatches=, rate=, claims=)`
pk_numeric_provenance_validate <- function(text, facts) {
  index <- pk_facts_index(facts)
  iddialar <- .pk_prov_claims(text)
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

    if (is.null(olgu$value)) {
      ekle(fact_id = iddia$fact_id, reason = "unavailable_fact",
           claimed = iddia$number_text, status = olgu$status)
      next
    }

    adaylar <- iddia$candidates %||% numeric(0)
    if (!length(adaylar)) {
      ekle(fact_id = iddia$fact_id, reason = "no_number", claimed = iddia$raw)
      next
    }

    # Belirsiz nokta biçimlerinde olguyla eşleşen yorum kabul edilir; hiçbiri
    # eşleşmiyorsa iddia yine reddedilir.
    tolerans <- .pk_prov_tolerance(iddia$number_text, olgu$value, olgu)
    if (!any(abs(adaylar - olgu$value) <= tolerans)) {
      ekle(fact_id = iddia$fact_id, reason = "value_mismatch",
           claimed = iddia$number_text, actual = olgu$value)
      next
    }

    # Anlamsal denetim: doğru sayı YANLIŞ ölçü için alıntılanamaz.
    olgu_birimi <- .pk_prov_unit_fold(olgu$unit %||% "")
    iddia_birimi <- .pk_prov_unit_fold(iddia$unit)

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
    if (nzchar(olgu_birimi) && !nzchar(iddia_birimi) && !isTRUE(iddia$percent)) {
      ekle(fact_id = iddia$fact_id, reason = "unit_missing",
           claimed = "(birimsiz)", actual = olgu_birimi)
      next
    }

    # BİRİMSİZ bir olguya birim UYDURULAMAZ. Sıradan düzyazı sözcükleri
    # ("47 farkli kaynak") işaretlenmesin diye yalnızca GERÇEK bir birim
    # sözlüğüne düşen jetonlar uyuşmazlık sayılır.
    if (!nzchar(olgu_birimi) && nzchar(iddia_birimi) &&
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
  kokensizler <- .pk_prov_uncited_claims(text)
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
