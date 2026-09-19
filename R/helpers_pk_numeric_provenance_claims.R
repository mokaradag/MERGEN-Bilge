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

#' Bir grubun işaretlerini adaylara eşle (konumsal, gerekirse uzlaştırılmış)
#'
#' Önce KONUMSAL eşleme denenir (model istem kuralına uyduğunda tek doğru
#' okuma budur). Yalnızca konumsal eşleme değer denetiminden geçemezse, AYNI
#' aday kümesi içinde her çiftin geçtiği birebir bir eşleme aranır. Hiçbir
#' değer ÜRETİLMEZ; eşleme bulunamazsa konumsal sıra korunur.
.pk_prov_group_pairing <- function(grup, jetonlar, index) {
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
  uygun <- matrix(FALSE, nrow = k, ncol = k)
  for (i in seq_len(k)) {
    for (j in seq_len(k)) {
      uygun[i, j] <- .pk_prov_value_fits(jetonlar[[adaylar[j]]], olgular[[i]])
    }
  }

  if (all(vapply(seq_len(k), function(i) isTRUE(uygun[i, i]), logical(1)))) {
    return(konumsal)
  }

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
    esleme <- .pk_prov_group_pairing(grup, jetonlar, index)
    onceki <- NA_integer_

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
      baglam <- pk_prov_token_context(masked, jetonlar, idx, grup$segment_start, onceki)
      onceki <- idx

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
    birim_ilk <- .pk_prov_unit_fold(sub("[[:space:]].*$", "", birim))
    taninan_birim <- nzchar(birim_ilk) && birim_ilk %in% .PK_PROV_KNOWN_UNITS_FOLDED
    yil_gibi <- !ayrac && !yuzde && haneler == 4L && !taninan_birim &&
      suppressWarnings(!is.na(as.integer(sade))) &&
      as.integer(sade) >= 1900L && as.integer(sade) <= 2100L
    if (isTRUE(yil_gibi)) next

    # BİRİM VARLIĞI TEK BAŞINA YETMEZ: "3 kez" / "2. madde" gibi sıradan
    # ifadeler veri iddiası değildir ve `block` kipinde geçerli yanıtları
    # düşürmemelidir. Ölçek işareti aranır: ayraç, yüzde, 4+ hane ya da TANINAN
    # bir ölçü birimi ("47 adet").
    veri_gibi <- ayrac || yuzde || haneler >= 4L || taninan_birim
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
