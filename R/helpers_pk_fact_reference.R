# ==============================================================================
# Dosya Yolu: R/helpers_pk_fact_reference.R
# Açıklama: ANLAMSAL OLGU REFERANSI çözümleyicisi (master plan §5.11).
#
#           MİMARİ: model SAYIYI YAZMAZ. Model, sayının durması gereken yere
#           bir YUVA jetonu koyar:
#
#               "Özellikle {{fact:activity_late_count.sum.overall.ab12cd}}
#                geciken aktivite dikkat çekiyor."
#
#           R o yuvayı olgu kataloğundaki KANONİK gösterimle doldurur:
#
#               "Özellikle 15.448 geciken aktivite dikkat çekiyor."
#
#           Böylece "modelin yazdığı sayıyı düzyazıda bulup hangi olguya ait
#           olduğunu GERİYE DOĞRU tahmin etme" problemi ORTADAN KALKAR. Kimlik
#           AÇIKTIR; değer, birim, binlik/ondalık ayracı ve yüzde biçimi R'ye
#           aittir.
#
#           Çözümleme TEK GEÇİŞTİR ve yerine konan gösterim YENİDEN TARANMAZ:
#           bir veri değerine sızmış sahte yuva jetonu genişletilemez.
#
#           Kapalı başarısızlık: çözülemeyen bir referans ASLA değer basmaz.
#           Yetkisiz ya da başka bir isteğe ait bir kimlik, model onu yazsa
#           bile bu indekste bulunmaz ve `unknown_fact` olur.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

# Kanonik yuva jetonu. İç boşluğa TOLERANSLIDIR (`{{ fact : x }}`): boşluk
# toleransı kimlik ÇIKARIMI değildir, yalnızca modelin biçim gürültüsünü
# gereksiz bir bozulmaya çevirmemek içindir.
PK_FACT_REF_PATTERN <-
  "\\{\\{[[:space:]]*fact[[:space:]]*:[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*\\}\\}"

# Yuva GİBİ görünen ama kanonik OLMAYAN jeton (`{{fact:}}`, `{{olgu:x}}`).
# Yapısal protokol ihlalidir: değer basılmaz, yerine nötr metin konur.
PK_FACT_REF_MALFORMED_PATTERN <- "\\{\\{[^{}]{0,160}\\}\\}"

# SONLANDIRILMAMIŞ yuva açıcısı (`{{fact:bogus` — kapanış yok). Kanonik ya da
# bozuk jeton desenlerinin hiçbirine uymadığı için metinde HAM kalıyordu; model
# o noktaya bir değer koymak istediğinden iddia da denetimsiz yayımlanıyordu.
# Açıcı SATIR SONUNA kadar (CRLF dâhil) bir protokol ihlali olarak tanınır.
PK_FACT_REF_OPEN_PATTERN <- "\\{\\{[^{}\r\n]{0,160}(?=[\r\n]|$)"

# ESKİ ALINTI SÖZ DİZİMİ (`[fact:x]`). Önceki mimaride model sayıyı yazıp
# yanına bu işareti koyardı. Artık jeton SAYININ KENDİSİDİR; eski biçim
# yapısal bir protokol ihlali olarak raporlanır ve SİLİNİR. Modelin yazdığı
# sayı bu yolla ASLA doğrulanmış gibi yayımlanmaz (sayı, sayı tarayıcısının
# ayrı bulgusudur).
PK_FACT_REF_LEGACY_PATTERN <- "\\[fact:[A-Za-z0-9_.]*\\]"

# YALNIZCA `fact` ÖNEKLİ bozuk/sonlandırılmamış yuvalar. Doğrulayıcının hiç
# çalışmadığı yollarda (bayat istek, eksik kayıt) PK dışı sıradan bir yanıt da
# bu kapıdan geçer; oradaki şablon söz dizimi (`{{ ad }}`) KORUNMALIDIR.
.PK_FACT_REF_FACT_MALFORMED_PATTERN <- "\\{\\{[[:space:]]*fact[[:space:]]*:[^{}]{0,160}\\}\\}"
.PK_FACT_REF_FACT_OPEN_PATTERN <- "\\{\\{[[:space:]]*fact[[:space:]]*:[^{}\r\n]{0,160}(?=[\r\n]|$)"

# KIRIK `fact` AÇICISI: tek kapanışlı (`{{fact:x}`) ya da 160 karakterden uzun
# bir satırda kapanışsız kalan (`{{fact:bogus ...`) açıcı yukarıdaki desenlerin
# hiçbirine uymuyor ve HAM söz dizimi kullanıcıya ulaşıyordu. Kanonik ve bozuk
# desenlerden SONRA uygulanır; onların kapsadığı aralıklar yeniden işlenmez.
PK_FACT_REF_BROKEN_OPENER_PATTERN <- "\\{\\{[[:space:]]*fact[[:space:]]*:[A-Za-z0-9_.]*\\}?"

# Çözülemeyen bir referansın yerine geçen NÖTR metin. Bir değer İDDİA ETMEZ;
# cümlenin geri kalanı okunur kalır ve tek bir bozuk referans 30 geçerli
# cümleyi düşürmez.
PK_FACT_REF_UNRESOLVED_TR <- "(değer yok)"

# Satır başı madde öneki: madde imleri ve "1." / "2)" numaraları (iç içe dâhil).
.PK_FACT_REF_ITEM_PREFIX <- "^[[:space:]]*(?:(?:[-*+>]|[0-9]{1,3}[.)])[[:space:]]+)+"

# Sorunlu noktaları işaretleyen iç nöbetçi. Kullanıcıya ASLA ulaşmaz: `block`
# kipinde cümle ayıklamasından sonra, diğer kiplerde doğrudan silinir.
.PK_FACT_REF_SENTINEL <- intToUtf8(2L)

.pk_fact_ref_scalar <- function(x) {
  txt <- suppressWarnings(as.character(x %||% "")[1])
  if (length(txt) != 1L || is.na(txt)) "" else txt
}

#' Olgu referanslarını DEĞER BASMADAN nötrle (tek sahip)
#'
#' Çözümleyicinin ÇALIŞMADIĞI her yol (bozulma, bayat istek, tüketilmiş kayıt)
#' ham model metnini döndürüyordu; yuva jetonları kullanıcıya iç söz dizimi
#' olarak ulaşıyordu. Kanonik jetonun yerine nötr metin konur, eski alıntı
#' işareti silinir.
#'
#' @param strict `TRUE` ise her `{{...}}` çifti ihlaldir (metnin v2 yanıtı
#'   olduğu BİLİNİR). `FALSE` yalnızca `fact` önekli biçimlere dokunur.
pk_fact_reference_neutralize <- function(text, strict = FALSE) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) return(text)
  if (!grepl("{{", text, fixed = TRUE) && !grepl("[fact:", text, fixed = TRUE)) {
    return(text)
  }
  desenler <- if (isTRUE(strict)) {
    c(PK_FACT_REF_PATTERN, PK_FACT_REF_MALFORMED_PATTERN, PK_FACT_REF_OPEN_PATTERN,
      PK_FACT_REF_BROKEN_OPENER_PATTERN)
  } else {
    c(PK_FACT_REF_PATTERN, .PK_FACT_REF_FACT_MALFORMED_PATTERN,
      .PK_FACT_REF_FACT_OPEN_PATTERN, PK_FACT_REF_BROKEN_OPENER_PATTERN)
  }
  # Bu yardımcı HATA FIRLATMAZ: çağıranlar hata yakalayıcıların İÇİNDEDİR ve
  # geçersiz kodlamalı bir metin `gsub(perl = TRUE)` ile düşebilir.
  tryCatch({
    notr <- text
    for (desen in desenler) {
      notr <- gsub(desen, PK_FACT_REF_UNRESOLVED_TR, notr, perl = TRUE)
    }
    gsub(PK_FACT_REF_LEGACY_PATTERN, "", notr, perl = TRUE)
  }, error = function(e) text)
}

#' Bir olgu kimliğinin YUVA jetonu (tek sahip)
#'
#' Paket yazıcısı bu jetonu basar, model onu kopyalar, çözümleyici onu okur.
#' Üç yol da AYNI kaynaktan geldiği için söz dizimi zamanla ayrışamaz.
pk_fact_reference_token <- function(fact_id) {
  sprintf("{{fact:%s}}", .pk_fact_ref_scalar(fact_id))
}

#' Olguları kimliğe göre indeksle
#'
#' Aynı kimliğe iki FARKLI olgu düşerse İKİSİ DE çözülemez sayılır: sessizce
#' birini seçmek, bir yuvayı YANLIŞ ölçünün değeriyle doldurmak demekti.
pk_facts_index <- function(facts) {
  out <- list()
  for (olgu in (facts %||% list())) {
    if (!is.list(olgu) || !is.character(olgu$fact_id) ||
        length(olgu$fact_id) != 1L || is.na(olgu$fact_id) ||
        !nzchar(olgu$fact_id)) {
      next
    }

    mevcut <- out[[olgu$fact_id]]
    if (is.null(mevcut)) {
      out[[olgu$fact_id]] <- olgu
      next
    }
    if (identical(mevcut$value, olgu$value) &&
        identical(mevcut$display, olgu$display) &&
        identical(mevcut$column, olgu$column) &&
        identical(mevcut$aggregation, olgu$aggregation)) {
      next
    }

    belirsiz <- mevcut
    belirsiz$value <- NULL
    belirsiz$display <- NA_character_
    belirsiz$status <- "ambiguous_fact_id"
    belirsiz$note <- "Ayni kimlige birden fazla olgu dustu; cozumlenemez."
    out[[olgu$fact_id]] <- belirsiz
  }
  out
}

#' Bir olgunun KULLANICIYA BASILABİLİR gösterimi
#'
#' Tek sözleşme: gösterim tek ögeli, `NA` olmayan, boş olmayan bir karakterdir
#' VE olgu belirsiz değildir. Değer taşımayan olguların (`insufficient_data`,
#' `unavailable_no_finite_values`) gösterimi `NA_character_`tir; uydurma bir
#' sayının basılması bu yüzden YAPISAL OLARAK imkânsızdır.
pk_fact_display_value <- function(olgu) {
  if (!is.list(olgu)) return(NA_character_)
  if (identical(as.character(olgu$status %||% "")[1], "ambiguous_fact_id")) {
    return(NA_character_)
  }
  gosterim <- suppressWarnings(as.character(olgu$display %||% NA_character_)[1])
  if (length(gosterim) != 1L || is.na(gosterim) || !nzchar(trimws(gosterim))) {
    return(NA_character_)
  }
  # Gösterim tek satıra indirgenir ve yuva söz dizimi taşıyamaz; aksi hâlde
  # veriden gelen bir gösterim kullanıcıya görünen metnin yapısını bozabilir.
  gosterim <- gsub("[[:cntrl:]]+", " ", gosterim)
  gosterim <- gsub("[{}]", "", gosterim)
  trimws(gsub("[[:space:]]+", " ", gosterim))
}

# Metindeki tüm jeton eşleşmelerini konumlarıyla bulur.
.pk_fact_ref_matches <- function(txt, pattern) {
  konum <- gregexpr(pattern, txt, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())
  uzunluk <- attr(konum, "match.length")
  lapply(seq_along(konum), function(i) {
    list(start = as.integer(konum[i]),
         end = as.integer(konum[i]) + as.integer(uzunluk[i]) - 1L)
  })
}

# Kanonik jetonun kimliğini çıkarır (desen ZATEN doğrulanmıştır).
.pk_fact_ref_id <- function(jeton) {
  esle <- regmatches(jeton, regexec(PK_FACT_REF_PATTERN, jeton, perl = TRUE))[[1]]
  if (length(esle) < 2L) return("")
  esle[2]
}

# Tek bir düzenleme kaydı.
#
# `sentinel` YALNIZCA `block` kipindeki cümle ayıklamasını sürer; bulgu
# raporlaması ondan BAĞIMSIZDIR. Ayrım bilinçlidir: R'nin değeri bastığı ve
# hiçbir yanlış sayının yayımlanmadığı KURTARILABİLİR bir protokol sorunu
# telemetriye girer ama geçerli bir cümleyi düşürmez.
.pk_fact_ref_edit <- function(start, end, kept, sentinel, reason, category,
                              fact_id = NA_character_) {
  list(start = start, end = end, kept = kept, sentinel = isTRUE(sentinel),
       reason = reason, category = category, fact_id = fact_id)
}

# Yuvanın hemen ardına modelin İLİŞTİRDİĞİ birim, olgunun kendi birimiyle
# çelişiyor mu?
#
# Kimlik doğru olsa bile anlam değişebilir: birimsiz bir satır sayımı
# "{{fact:...}} TL" yazılarak makul ama YANLIŞ bir bütçe iddiasına dönüşüyor ve
# hiçbir kipte bulgu üretmiyordu. Denetim YAPISALDIR: yalnızca araya sözcük
# girmeyen, ÖLÇEK TAŞIYAN bir birim okunur; mesafe/tolerans hesabı yoktur.
.pk_fact_ref_unit_conflict <- function(txt, son, olgu) {
  if (!exists("pk_fact_unit_after", mode = "function", inherits = TRUE)) return(FALSE)
  komsu <- pk_fact_unit_after(txt, son)
  if (!nzchar(komsu)) return(FALSE)

  olgu_birim <- pk_fact_unit_key(as.character(olgu$unit %||% "")[1])
  if (identical(komsu, olgu_birim)) return(FALSE)
  # KULLANICI KRİTERİ bir ölçü DEĞİLDİR: uygulanan filtre değeri birim taşımaz
  # ("butce > 1000000") ve modelin eşiğe sütunun birimini eklemesi ("... TL
  # üzeri") ölçüyü değiştirmez; güven bulgusu sayılması geçerli cümleyi düşürürdü.
  if (!nzchar(olgu_birim) &&
      identical(as.character(olgu$kind %||% "")[1], "request_input")) {
    return(FALSE)
  }
  # Birimsiz olguya yalnızca PARA/YÜZDE iliştirmek ölçüyü değiştirir; "gün",
  # "adet" gibi sözcükler cümlenin doğal parçası olabilir.
  if (!nzchar(olgu_birim)) return(komsu %in% c("%", "tl", "try", "usd", "eur"))
  TRUE
}

# Olgu gösterimi birimi ZATEN taşır ("18.420,5 saat", "%61,3"). Modelin yuvanın
# hemen ardına (ya da yüzde/para simgesini hemen önüne) yazdığı AYNI birim
# ikinci kez basılmaz ("100 saat saat", "%%61,3"). Silme AYRI bir düzenlemedir:
# yuvanın kendi aralığı genişletilmez, böylece örtüşme hiçbir koşulda yuvayı
# çözümsüz bırakamaz. Kurtarılabilir biçim gürültüsüdür; bulgu üretmez.
.pk_fact_ref_unit_echo_edits <- function(txt, vurus, olgu) {
  if (!exists("pk_fact_unit_span", mode = "function", inherits = TRUE)) return(list())
  birim <- pk_fact_unit_key(as.character(olgu$unit %||% "")[1])
  if (!nzchar(birim)) return(list())
  out <- list()
  onde <- pk_fact_unit_span(txt, vurus$start, "before")
  if (identical(onde$key, birim) && onde$length > 0L) {
    out[[1L]] <- .pk_fact_ref_edit(vurus$start - onde$length, vurus$start - 1L, "",
                                   FALSE, "duplicate_unit", "ok")
  }
  sonra <- pk_fact_unit_span(txt, vurus$end, "after")
  if (identical(sonra$key, birim) && sonra$length > 0L) {
    out[[length(out) + 1L]] <- .pk_fact_ref_edit(vurus$end + 1L, vurus$end + sonra$length,
                                                 "", FALSE, "duplicate_unit", "ok")
  }
  out
}

# Kanonik referansları çöz; her biri için bir düzenleme üret. Yinelenen birim
# silmeleri `unit_edits` içinde AYRI döner (komşuluk denetimine girmez).
.pk_fact_ref_reference_edits <- function(txt, index) {
  duzenlemeler <- list()
  birim_silme <- list()
  cozulen <- 0L
  for (vurus in .pk_fact_ref_matches(txt, PK_FACT_REF_PATTERN)) {
    kimlik <- .pk_fact_ref_id(substr(txt, vurus$start, vurus$end))
    olgu <- if (nzchar(kimlik)) index[[kimlik]] else NULL
    gosterim <- if (is.null(olgu)) NA_character_ else pk_fact_display_value(olgu)

    if (is.null(olgu) || is.na(gosterim)) {
      neden <- if (is.null(olgu)) {
        "unknown_fact"
      } else if (identical(as.character(olgu$status %||% "")[1], "ambiguous_fact_id")) {
        "ambiguous_fact"
      } else {
        "unavailable_fact"
      }
      duzenlemeler[[length(duzenlemeler) + 1L]] <- .pk_fact_ref_edit(
        vurus$start, vurus$end, PK_FACT_REF_UNRESOLVED_TR, TRUE,
        neden, "trust", kimlik
      )
      next
    }

    cozulen <- cozulen + 1L
    catisma <- .pk_fact_ref_unit_conflict(txt, vurus$end, olgu)
    duzenlemeler[[length(duzenlemeler) + 1L]] <- .pk_fact_ref_edit(
      vurus$start, vurus$end, gosterim, catisma,
      if (catisma) "unit_conflict" else "resolved",
      if (catisma) "trust" else "ok", kimlik
    )
    if (!catisma) birim_silme <- c(birim_silme, .pk_fact_ref_unit_echo_edits(txt, vurus, olgu))
  }
  list(edits = duzenlemeler, unit_edits = birim_silme, resolved = cozulen)
}

# Kanonik olmayan yuva jetonları ve eski alıntı işaretleri: YAPISAL ihlal.
.pk_fact_ref_protocol_edits <- function(txt, kanonik) {
  kapsanan <- function(bas, son) {
    length(kanonik) > 0L &&
      any(vapply(kanonik, function(d) bas >= d$start && son <= d$end, logical(1)))
  }

  duzenlemeler <- list()
  ortulu <- function(bas, son) {
    length(duzenlemeler) > 0L &&
      any(vapply(duzenlemeler, function(d) bas >= d$start && son <= d$end, logical(1)))
  }

  for (desen in c(PK_FACT_REF_MALFORMED_PATTERN, PK_FACT_REF_OPEN_PATTERN,
                  PK_FACT_REF_BROKEN_OPENER_PATTERN)) {
    for (vurus in .pk_fact_ref_matches(txt, desen)) {
      if (kapsanan(vurus$start, vurus$end) || ortulu(vurus$start, vurus$end)) next
      # Model o noktaya bir DEĞER koymak istemişti; sağlayamıyoruz. Nötr metin
      # konur ve `block` kipinde cümle ayıklanır. Kapanışı yazılmamış bir açıcı
      # da aynı ihlaldir: ham jeton kullanıcıya ulaşmaz.
      duzenlemeler[[length(duzenlemeler) + 1L]] <- .pk_fact_ref_edit(
        vurus$start, vurus$end, PK_FACT_REF_UNRESOLVED_TR, TRUE,
        "malformed_reference", "protocol"
      )
    }
  }
  for (vurus in .pk_fact_ref_matches(txt, PK_FACT_REF_LEGACY_PATTERN)) {
    # Eski işaret bir ALINTI idi: yanındaki sayıyı MODEL yazmıştı ve hangi
    # olguya dayandığı DOĞRULANAMAZ. İşaret silinir, iddia ise `block` kipinde
    # ayıklanır; aksi hâlde "47 proje [fact:bogus]" kaynaksız yayımlanıyordu.
    # Çözülmüş bir yuvaya SIFIR MESAFEDE duran işaret ise değeri R'nin bastığı
    # bir YİNELEMEDİR: silinmesi yeter, geçerli cümle düşürülmez.
    yineleme <- .pk_fact_ref_adjacent(txt, vurus, kanonik)
    duzenlemeler[[length(duzenlemeler) + 1L]] <- .pk_fact_ref_edit(
      vurus$start, vurus$end, "", !yineleme, "legacy_reference", "protocol"
    )
  }
  duzenlemeler
}

# Düzenlemeleri metne uygular. İKİ çıktı üretilir:
#   * `kept`    -> düzenlemeler uygulanmış, sorunlu noktalar NÖTRLENMİŞ metin,
#   * `flagged` -> sorunlu noktalarda nöbetçi taşıyan sürüm (`block` ayıklaması).
# Yerine konan metin YENİDEN TARANMAZ (tek geçiş sözleşmesi).
.pk_fact_ref_apply_edits <- function(txt, duzenlemeler) {
  if (!length(duzenlemeler)) return(list(kept = txt, flagged = txt))

  duzenlemeler <- duzenlemeler[order(
    vapply(duzenlemeler, function(d) d$start, integer(1))
  )]

  tutulan <- character(0)
  isaretli <- character(0)
  imlec <- 1L
  for (d in duzenlemeler) {
    if (d$start < imlec) next  # örtüşen eşleşme: dıştaki/ilk olan kazanır
    onceki <- if (d$start > imlec) substr(txt, imlec, d$start - 1L) else ""
    son <- d$end

    # BOŞ YERİNE KOYMA ÇİFT BOŞLUK BIRAKMAZ. Jeton iki boşluk arasından
    # silindiğinde ("Toplam 15.448 {{fact:x}} aktivite") okunur metinde
    # kalıntı boşluk oluşuyordu; izleyen tek boşluk da yutulur.
    if (!nzchar(d$kept) && grepl("[ \u00a0]$", onceki, perl = TRUE) &&
        grepl("^[ \u00a0]$", substr(txt, son + 1L, son + 1L), perl = TRUE)) {
      son <- son + 1L
    }

    tutulan <- c(tutulan, onceki, d$kept)
    isaretli <- c(isaretli, onceki,
                  if (d$sentinel) paste0(.PK_FACT_REF_SENTINEL, d$kept) else d$kept)
    imlec <- son + 1L
  }
  kuyruk <- if (imlec <= nchar(txt)) substr(txt, imlec, nchar(txt)) else ""

  list(kept = paste0(paste(tutulan, collapse = ""), kuyruk),
       flagged = paste0(paste(isaretli, collapse = ""), kuyruk))
}

# Nöbetçi TAŞIYAN cümleleri ayıklar (`block` kipi, İDDİA DÜZEYİNDE ayıklama).
#
# Ayıklama SATIR SATIR yapılır: bir madde imi satırı ya da başlık kendi
# bağlamıdır. R'ye ait değerler zaten YERİNE KONMUŞ olduğu için binlik ayracı
# cümle sonu sanılmaz (`15.448` içindeki noktayı boşluk izlemez).
.pk_fact_ref_drop_flagged <- function(txt) {
  if (!grepl(.PK_FACT_REF_SENTINEL, txt, fixed = TRUE)) return(txt)

  satirlar <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  tut <- rep(TRUE, length(satirlar))

  for (i in seq_along(satirlar)) {
    if (!grepl(.PK_FACT_REF_SENTINEL, satirlar[i], fixed = TRUE)) next

    # MADDE ÖNEKİ ("1. ", "- ", "2) ") cümle DEĞİLDİR: bölücü onu ayrı bir
    # "cümle" sayıyor, işaretli madde düşünce kullanıcı yetim bir "1." satırı
    # görüyordu. Önek ayrılır; madde gövdesi boşalırsa satır tümüyle düşer.
    onek <- regmatches(satirlar[i], regexpr(.PK_FACT_REF_ITEM_PREFIX, satirlar[i], perl = TRUE))
    onek <- if (length(onek)) onek[1] else ""
    govde <- substr(satirlar[i], nchar(onek) + 1L, nchar(satirlar[i]))
    parcalar <- .pk_fact_ref_sentences(govde)
    kalan <- parcalar[!grepl(.PK_FACT_REF_SENTINEL, parcalar, fixed = TRUE)]
    # MARKDOWN YAPISI KORUNUR: yalnızca AYIKLAMA sonucu boşalan satır düşer.
    # Özgün boş satırlar (paragraf sınırı) KORUNUR; aksi hâlde başlık, madde
    # listesi ve paragraf birbirine yapışıp yanıtın biçimi bozuluyordu.
    if (!length(kalan) || !nzchar(trimws(paste(kalan, collapse = "")))) {
      tut[i] <- FALSE
      next
    }
    satirlar[i] <- paste0(onek, trimws(paste(kalan, collapse = ""), which = "right"))
  }

  kalanlar <- satirlar[tut]
  if (!length(kalanlar) || !nzchar(trimws(paste(kalanlar, collapse = "")))) return("")
  paste(kalanlar, collapse = "\n")
}

# Satırı cümlelere böler. `strsplit()` sıfır genişlikli desenlerde güvenilir
# değildir, bu yüzden sınırlar AÇIKÇA taranır: cümle sonu noktalaması + boşluk.
.pk_fact_ref_sentences <- function(satir) {
  if (!nzchar(satir)) return(character(0))
  konum <- gregexpr("[.!?]+[[:space:]]+", satir, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(satir)

  uzunluk <- attr(konum, "match.length")
  out <- character(0)
  bas <- 1L
  for (i in seq_along(konum)) {
    son <- as.integer(konum[i]) + as.integer(uzunluk[i]) - 1L
    out <- c(out, substr(satir, bas, son))
    bas <- son + 1L
  }
  if (bas <= nchar(satir)) out <- c(out, substr(satir, bas, nchar(satir)))
  out
}

.pk_fact_ref_strip_sentinels <- function(txt) {
  gsub(.PK_FACT_REF_SENTINEL, "", txt, fixed = TRUE)
}

# Bir sayı jetonu bir referans yuvasına SIFIR MESAFEDE komşu mu?
#
# "Sıfır mesafe" katıdır: aradaki metin yalnızca boşluk ve markdown vurgusu
# olabilir. Tek bir sözcük bile araya girerse komşuluk YOKTUR; böylece konumsal
# bir eşleştirme sezgisi geri gelmez. Amaç kimlik çıkarımı DEĞİL, R'nin bastığı
# değerin yanında duran YİNELEMENİN temizlenmesidir.
.pk_fact_ref_adjacent <- function(txt, jeton, referanslar) {
  bosluk <- "^[[:space:]\u00a0*_`~]*$"
  for (d in referanslar) {
    if (!identical(d$category, "ok") && !identical(d$category, "trust")) next
    ara <- if (d$start > jeton$end) {
      if (d$start > jeton$end + 1L) substr(txt, jeton$end + 1L, d$start - 1L) else ""
    } else if (d$end < jeton$start) {
      if (jeton$start > d$end + 1L) substr(txt, d$end + 1L, jeton$start - 1L) else ""
    } else {
      next
    }
    if (grepl(bosluk, ara, perl = TRUE)) return(TRUE)
  }
  FALSE
}

# GÜVENİLİR İSTEK DEĞERİ KENDİ YUVASININ YANINDA YİNELENİRSE: paket istek
# girdisini "6 ay {{yuva}}" biçiminde gösterir; model ikisini birden kopyalarsa
# "Son 6 ay 6 içinde" basılıyordu. Değer kullanıcının kendi değeridir ve tam
# anahtarla (sayı + birim) eşleşmiştir; bu yüzden modelin sözcükleri KORUNUR,
# yalnızca yinelenen yuva gösterimi boşaltılır. Başka bir olgunun yuvasına komşu
# güvenilir değer ("Son 30 günde {{gecikme}}") ASLA silinmez; anlam değişirdi.
.pk_fact_ref_trusted_echo <- function(txt, duzenlemeler, guvenli, index) {
  for (jeton in (guvenli %||% list())) {
    for (i in seq_along(duzenlemeler)) {
      d <- duzenlemeler[[i]]
      if (!identical(d$category, "ok") || !nzchar(as.character(d$fact_id %||% "")[1])) next
      olgu <- index[[d$fact_id]]
      if (!identical(as.character(olgu$kind %||% "")[1], "request_input")) next
      if (!(jeton$key %in% pk_fact_trusted_input_keys(list(olgu)))) next
      if (!.pk_fact_ref_adjacent(txt, jeton, list(d))) next
      duzenlemeler[[i]]$kept <- ""
      duzenlemeler[[i]]$reason <- "duplicate_numeric_literal"
      duzenlemeler[[i]]$category <- "protocol"
      break
    }
  }
  duzenlemeler
}

# Yinelenen sayısal iddiada silinecek aralığın sonu: ölçek taşıyan birim jetona
# dâhilse jetonun sonu, değilse rakam dizisinin sonu.
.pk_fact_ref_literal_end <- function(jeton) {
  if (nzchar(as.character(jeton$scale_unit %||% "")[1])) return(jeton$end)
  son <- suppressWarnings(as.integer(jeton$number_end %||% NA_integer_))
  if (length(son) != 1L || is.na(son) || son < jeton$start || son > jeton$end) {
    return(jeton$end)
  }
  son
}

#' Model metnindeki anlamsal olgu referanslarını çöz ve kanonik değerleri bas
#'
#' @param text Model düzyazısı (yuva jetonları içerir).
#' @param index `pk_facts_index()` çıktısı.
#' @param literals `pk_fact_literal_scan()` çıktısı; `NULL` ise yalnızca
#'   referanslar işlenir.
#' @return `list(kept=, strict=, resolved=, references=, findings=)`.
#'   `kept` her kipte kullanılabilir metindir; `strict` sorunlu cümleleri
#'   AYIKLANMIŞ sürümdür (`block`); `findings` tipli bulgu listesidir.
pk_fact_reference_render <- function(text, index = list(), literals = NULL) {
  txt <- .pk_fact_ref_scalar(text)
  index <- if (is.list(index)) index else list()

  if (!nzchar(txt)) {
    return(list(kept = "", strict = "", resolved = 0L, references = 0L,
                findings = list()))
  }

  ref <- .pk_fact_ref_reference_edits(txt, index)
  duzenlemeler <- .pk_fact_ref_trusted_echo(txt, ref$edits, literals$trusted, index)

  # BEKLENMEYEN SAYISAL MATERYAL: modelin kendi yazdığı, hiçbir olguya
  # karşılık gelmeyen veri görünümlü sayı. Hangi olguya ait olduğu TAHMİN
  # EDİLMEZ; yalnızca yapısal ihlal olarak işaretlenir.
  for (jeton in (literals$tokens %||% list())) {
    yineleme <- .pk_fact_ref_adjacent(txt, jeton, duzenlemeler)
    duzenlemeler[[length(duzenlemeler) + 1L]] <- if (yineleme) {
      # YİNELEME SİLİNİRKEN SIRADAN SÖZCÜK KORUNUR. Jeton bir izleyen sözcüğü
      # de kapsayabiliyor ("15.448 aktivite"); tüm aralığı silmek cümleden
      # "aktivite"yi düşürüyordu. Yalnızca rakam aralığı, ölçek taşıyan bir
      # birim varsa onunla birlikte silinir.
      .pk_fact_ref_edit(jeton$start, .pk_fact_ref_literal_end(jeton), "", FALSE,
                        "duplicate_numeric_literal", "protocol")
    } else {
      .pk_fact_ref_edit(jeton$start, jeton$end, jeton$raw, TRUE,
                        "model_numeric_literal", "protocol")
    }
  }

  duzenlemeler <- c(duzenlemeler, .pk_fact_ref_protocol_edits(txt, ref$edits),
                    ref$unit_edits)
  uygulanan <- .pk_fact_ref_apply_edits(txt, duzenlemeler)

  # `recoverable`: R değeri bastı ve yanlış bir sayı yayımlanmadı (nöbetçisiz
  # düzenleme). Telemetriye girer ama kullanıcıya "bağlanamadı" denmez.
  bulgular <- lapply(
    Filter(function(d) !identical(d$category, "ok"), duzenlemeler),
    function(d) list(reason = d$reason, category = d$category, fact_id = d$fact_id,
                     recoverable = !isTRUE(d$sentinel))
  )

  list(
    kept = .pk_fact_ref_strip_sentinels(uygulanan$kept),
    strict = .pk_fact_ref_strip_sentinels(
      .pk_fact_ref_drop_flagged(uygulanan$flagged)
    ),
    resolved = ref$resolved,
    references = length(ref$edits),
    findings = bulgular
  )
}
