# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance_claims.R
# Açıklama: Düzyazıdaki SAYISAL İDDİA tarayıcısı — master plan §5.11.
#
#           `R/helpers_pk_numeric_provenance.R` dosyasından AYRILDI: doğrulayıcı
#           katmanı (kip çözümleme, sayı ayrıştırma, tolerans, doğrulama/uygulama
#           ve raporlama) ile düzyazı TARAMA katmanı ayrı sorumluluklardır ve tek
#           dosyada 800 satır bakım ratchet'ini aşıyordu.
#
#           TEK GEÇİŞ SÖZLEŞMESİ: eskiden İKİ bağımsız tarayıcı vardı (alıntılı
#           ve alıntısız) ve ikisi de bitişikliğe KENDİ kuralıyla karar
#           veriyordu. Kurallar ayrıştığında AYNI doğru sayı bir tarayıcıda
#           alıntılı, diğerinde köksüz görünüyor; tek iddia hem PAYI hem PAYDAYI
#           şişiriyordu. Artık bağlama `pk_prov_bind_text()` içinde BİR KEZ
#           yapılır: bağlanan jeton alıntıdır, bağlanmayan jeton köken adayıdır.
#           İki kümenin kesişimi yapısal olarak BOŞTUR.
#
#           Yükleme sırası: bu dosya `R/helpers_pk_numeric_provenance.R` ve
#           `R/helpers_pk_numeric_provenance_binding.R` dosyalarından SONRA
#           yüklenir; sabitleri ve yardımcıları ÇAĞRI ANINDA çözer.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

#' Bir aday sayının olguya UYGUN olup olmadığını söyle (yalnızca DEĞER denetimi)
#'
#' Birim/toplulaştırma denetimleri doğrulayıcıda kalır; yeniden eşleştirme
#' yalnızca değer uyumuna bakar, çünkü çözdüğü sorun işaret SIRASIDIR.
.pk_prov_value_fits <- function(jeton, olgu) {
  if (is.null(olgu)) return(FALSE)
  deger <- suppressWarnings(as.numeric(olgu$value %||% NA_real_))
  if (is.null(olgu$value) || length(deger) != 1L || is.na(deger) || !is.finite(deger)) {
    return(FALSE)
  }
  adaylar <- pk_parse_number_candidates(jeton$number_text)
  if (!length(adaylar)) return(FALSE)
  any(abs(adaylar - deger) <= .pk_prov_tolerance(jeton$number_text, deger, olgu))
}

#' Bir adayın olguya ANLAMSAL olarak da uyup uymadığını söyle
#'
#' Değer denetimi tek başına AYRIM YAPAMAZ: aynı değeri taşıyan iki olgu
#' (ör. `100 TL` toplam ile `100` ortalama) arasında yeniden eşleştirme
#' rastgele bir geçerli eşleme seçebilir ve doğrulayıcı sonradan DOĞRU bir
#' yanıtı `unit_mismatch`/`aggregation_mismatch` ile reddederdi. Bu yüzden
#' uzlaştırma ÖNCE birim ve toplulaştırma uyumunu arar.
.pk_prov_semantics_fit <- function(jeton, baglam, olgu, sozluk) {
  if (is.null(olgu)) return(FALSE)

  olgu_birimi <- .pk_prov_unit_fold(olgu$unit %||% "")
  iddia_birimi <- .pk_prov_unit_fold(jeton$unit %||% "")
  if (nzchar(iddia_birimi) && !(iddia_birimi %in% sozluk)) {
    iddia_birimi <- .pk_prov_unit_root(iddia_birimi, sozluk)
  }

  if (!identical(isTRUE(jeton$percent), identical(olgu_birimi, "%"))) {
    return(FALSE)
  }
  if (nzchar(iddia_birimi) && nzchar(olgu_birimi) &&
      !identical(iddia_birimi, olgu_birimi)) {
    return(FALSE)
  }

  iddia_agg <- .pk_prov_claimed_aggregation(baglam)
  olgu_agg <- as.character(olgu$aggregation %||% "")[1]
  if (!is.null(iddia_agg) && nzchar(olgu_agg) &&
      !identical(iddia_agg, olgu_agg) &&
      olgu_agg %in% names(.PK_PROV_AGG_WORDS)) {
    return(FALSE)
  }
  TRUE
}

#' Grup adaylarının toplulaştırma bağlamlarını METİN SIRASINDA üret
#'
#' Bağlam, jetonun METİNDEKİ bir öncekinden sonra başlar. Uzlaştırma işaret
#' sırasını değiştirebildiği için bağlamı "önceki İŞARET" üzerinden kurmak
#' yanlıştı: "Toplam 100, 50 [fact:sum50][fact:mean100]" örneğinde ilk işaret
#' ikinci jetona eşlenince sonraki jetonun bağlamı BOŞ kalıyor ve `100`
#' sayısının toplam diye sunulduğu hiç fark edilmiyordu.
.pk_prov_group_contexts <- function(masked, jetonlar, grup) {
  out <- list()
  sirali <- sort(unique(grup$tokens %||% integer(0)))
  onceki <- NA_integer_
  for (idx in sirali) {
    out[[as.character(idx)]] <- pk_prov_token_context(masked, jetonlar, idx,
                                                      grup$segment_start, onceki)
    onceki <- idx
  }
  out
}

#' Bir grubun işaretlerini adaylara eşle (konumsal, gerekirse uzlaştırılmış)
#'
#' Önce KONUMSAL eşleme denenir (model istem kuralına uyduğunda tek doğru
#' okuma budur). Yalnızca konumsal eşleme değer denetiminden geçemezse, AYNI
#' aday kümesi içinde her çiftin geçtiği birebir bir eşleme aranır. Hiçbir
#' değer ÜRETİLMEZ; eşleme bulunamazsa konumsal sıra korunur.
.pk_prov_group_pairing <- function(grup, jetonlar, index, baglamlar = list()) {
  k <- length(grup$ids)
  adaylar <- grup$tokens
  konumsal <- rep(NA_integer_, k)
  if (length(adaylar)) {
    n <- min(k, length(adaylar))
    konumsal[seq_len(n)] <- adaylar[seq_len(n)]
  }

  if (is.null(index) || length(adaylar) != k || k < 2L || k > .PK_PROV_MAX_GROUP) {
    return(konumsal)
  }

  olgular <- lapply(grup$ids, function(id) index[[id]])
  sozluk <- .pk_prov_unit_vocabulary(index)

  # İKİ MATRİS: `uygun` yalnızca DEĞER uyumudur, `tam` birim ve toplulaştırmayı
  # da ister. Eşit değerli olgular ancak `tam` ile ayrışabilir.
  uygun <- matrix(FALSE, nrow = k, ncol = k)
  tam <- matrix(FALSE, nrow = k, ncol = k)
  for (j in seq_len(k)) {
    jeton <- jetonlar[[adaylar[j]]]
    baglam <- as.character(baglamlar[[as.character(adaylar[j])]] %||% "")[1]
    for (i in seq_len(k)) {
      uygun[i, j] <- .pk_prov_value_fits(jeton, olgular[[i]])
      tam[i, j] <- isTRUE(uygun[i, j]) &&
        .pk_prov_semantics_fit(jeton, baglam, olgular[[i]], sozluk)
    }
  }

  kosegen <- function(m) {
    all(vapply(seq_len(k), function(i) isTRUE(m[i, i]), logical(1)))
  }

  # ÖNCELİK SIRASI: anlamsal köşegen -> anlamsal uzlaştırma -> değer köşegeni ->
  # değer uzlaştırması. Böylece eşit değerli ama farklı birimli/toplulaştırmalı
  # olgularda KEYFİ bir geçerli eşleme seçilmez.
  if (kosegen(tam)) return(konumsal)
  esleme <- pk_prov_repair_pairing(tam)
  if (!is.null(esleme)) return(adaylar[esleme])

  if (kosegen(uygun)) return(konumsal)
  esleme <- pk_prov_repair_pairing(uygun)
  if (is.null(esleme)) return(konumsal)
  adaylar[esleme]
}

#' Alıntılı (işaretli) sayısal iddiaları çıkar
#'
#' @param binding `pk_prov_bind_text()` çıktısı.
#' @param index Olgu indeksi; verildiğinde grup içi uzlaştırma etkinleşir.
.pk_prov_claims_from_binding <- function(masked, binding, index = NULL) {
  jetonlar <- binding$tokens
  out <- list()

  for (grup in binding$groups) {
    # BAĞLAM METİN SIRASINDA hesaplanır, eşleme SONRA uygulanır. Ters sırada
    # kurulduğunda uzlaştırılmış bir grubun ikinci jetonu BOŞ bağlam alıyordu.
    baglamlar <- .pk_prov_group_contexts(masked, jetonlar, grup)
    esleme <- .pk_prov_group_pairing(grup, jetonlar, index, baglamlar)

    for (i in seq_along(grup$ids)) {
      idx <- esleme[i]
      if (is.na(idx)) {
        # İşaret var, sayı yok. Bu bir SAYISAL hata değildir (uydurulmuş bir
        # değer yayımlanmaz); niteliksel bir cümle de bir olguya atıf yapabilir.
        # Tanılama için ayrı raporlanır, uyuşmazlık sayılmaz.
        out[[length(out) + 1L]] <- list(
          fact_id = grup$ids[i], marker = paste0("[fact:", grup$ids[i], "]"),
          raw = "", number_text = "", value = NULL, candidates = numeric(0),
          percent = FALSE, unit = "", context = "", numberless = TRUE
        )
        next
      }

      jeton <- jetonlar[[idx]]
      baglam <- as.character(baglamlar[[as.character(idx)]] %||% "")[1]

      out[[length(out) + 1L]] <- list(
        fact_id = grup$ids[i],
        marker = paste0("[fact:", grup$ids[i], "]"),
        raw = jeton$raw,
        number_text = jeton$number_text,
        value = pk_parse_number_tr(jeton$number_text),
        candidates = pk_parse_number_candidates(jeton$number_text),
        percent = jeton$percent,
        unit = jeton$unit,
        context = baglam,
        numberless = FALSE
      )
    }
  }

  out
}

# İŞARETSİZ (KÖKENSİZ) SAYISAL İDDİALARI BUL.
#
# Model istem kuralını yok sayıp `Toplam 99.999 saat` yazdığında iddia kümesi
# BOŞ kalıyor, doğrulayıcı "uyuşmazlık yok" diyor ve `warn`/`block` kipleri bile
# halüsinasyon sayıyı DEĞİŞMEDEN yayımlıyordu; yani yapılandırılan köken
# zorunluluğu bozuk model çıktısıyla ATLATILABİLİYORDU.
#
# Yanlış pozitiften kaçınmak için yalnızca VERİ görünümlü sayılar sayılır:
# ondalık/binlik ayraç taşıyanlar, yüzde işaretliler, tanınan bir ölçü birimi
# taşıyanlar ya da dört haneden uzun tam sayılar. Yıl (1900-2100), tarih, madde
# numarası ve birimsiz küçük tam sayılar KAPSAM DIŞIDIR.
.pk_prov_uncited_from_binding <- function(binding) {
  jetonlar <- binding$tokens
  if (!length(jetonlar)) return(list())
  bagli <- binding$bound %||% integer(0)

  out <- list()
  for (i in seq_along(jetonlar)) {
    if (i %in% bagli) next
    jeton <- jetonlar[[i]]

    rakam <- jeton$number_text
    if (!nzchar(rakam)) next

    yuzde <- isTRUE(jeton$percent)
    birim <- jeton$unit
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

    # Yıl gibi görünen çıplak sayı: veri iddiası sayılmaz. Yıl, ARDINDAN bir
    # sözcük gelse de ("2024 yilinda") yıl sayılır. ANCAK TANINAN BİR ÖLÇÜ
    # BİRİMİ YIL YORUMUNU BOZAR: "Toplam 2024 saat" işaretsiz kalırsa
    # uyuşmazlık üretmeden yayımlanırdı.
    # BİRİM TANIMA ALINTILI YOLLA AYNI SÖZLÜĞÜ KULLANIR.
    #
    # Alıntılı yol hem ölçek taşıyan hem de boyutsuz sayım birimlerini tanır ve
    # EKLİ biçimleri (`saatlik`, `adetlik`) köküne indirir. Alıntısız tarayıcı
    # yalnızca ölçek sözlüğünün TAM girdilerine bakınca "47 saatlik" ve
    # "47 kayit" gibi işaretsiz iddialar düşüyor, `warn`/`block` kiplerinde
    # doğrulanmadan yayımlanıyordu.
    birim_ilk <- .pk_prov_unit_fold(sub("[[:space:]].*$", "", birim))
    birim_koku <- if (nzchar(birim_ilk)) {
      .pk_prov_unit_root(birim_ilk, .PK_PROV_UNCITED_UNITS)
    } else {
      ""
    }
    taninan_birim <- nzchar(birim_ilk) &&
      (birim_ilk %in% .PK_PROV_UNCITED_UNITS_FOLDED || nzchar(birim_koku))

    # ÜSTEL GÖSTERİM ÖLÇEK İŞARETİDİR: `1e6` ayraç/yüzde taşımaz ve sade hâli
    # kısa görünür, ama büyüklük iddiasıdır ve doğrulanmadan yayımlanamaz.
    bilimsel <- grepl("[eE][+-]?[0-9]+$", rakam, perl = TRUE)

    # İŞARETLİ SAYI YIL DEĞİLDİR: `gsub("[^0-9]", ...)` eksi imini SİLİYOR,
    # böylece `-2024` yıl muafiyetine düşüp köken denetimini atlıyordu.
    yil_gibi <- !grepl("^-", rakam, perl = TRUE) && !bilimsel &&
      !ayrac && !yuzde && haneler == 4L && !taninan_birim &&
      suppressWarnings(!is.na(as.integer(sade))) &&
      as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
    if (isTRUE(yil_gibi)) next

    # BİRİM VARLIĞI TEK BAŞINA YETMEZ: "3 kez" / "2. madde" gibi sıradan
    # ifadeler veri iddiası değildir ve `block` kipinde geçerli yanıtları
    # düşürmemelidir. Ölçek işareti aranır: ayraç, yüzde, 4+ hane ya da TANINAN
    # bir ölçü birimi ("47 adet").
    veri_gibi <- ayrac || yuzde || bilimsel || haneler >= 4L || taninan_birim
    if (!veri_gibi) next

    out[[length(out) + 1L]] <- list(raw = jeton$raw, number = rakam,
                                    unit = birim, percent = yuzde)
  }
  out
}

#' Metni TEK geçişte tara: alıntılı iddialar + köken-siz sayılar
#'
#' @return `list(claims=, uncited=)`
pk_prov_scan_claims <- function(text, index = NULL) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(list(claims = list(), uncited = list()))

  binding <- pk_prov_bind_text(txt)
  masked <- .pk_prov_mask_markers(txt)$masked

  list(
    claims = .pk_prov_claims_from_binding(masked, binding, index),
    uncited = .pk_prov_uncited_from_binding(binding)
  )
}
