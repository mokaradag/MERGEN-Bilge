# ==============================================================================
# Dosya Yolu: R/helpers_pk_packet_stats.R
# Açıklama: Proje ve Kaynak Analizi v2 analiz paketinin SAYISAL ÇEKİRDEĞİ
#           (master plan §5.7 / §5.11).
#
#           Bu dosya iki şeyi sahiplenir:
#             1. Yerelden bağımsız, bilimsel gösterim ÜRETMEYEN sayı biçimleme
#                (D19 — eski kod `capture.output(print(...))` kullanıyordu ve
#                bir bütçe modele `1.234568e+09` olarak ulaşıyordu).
#             2. Yapılandırılmış "olgu" (fact) kaydı: her sayının kimliği,
#                ölçü yeteneği, birimi, toplulaştırma türü, kapsamı ve
#                gözlem sayısı yanında taşınır. §5.11 sayısal köken
#                doğrulaması bu kayıtları tüketir; çıplak bir sayı yeterli
#                bir sözleşme DEĞİLDİR.
#
#           Seyrek/sonlu-olmayan ölçü sözleşmesi (§5.7):
#             n_finite == 0 -> `unavailable_no_finite_values`; hiçbir sayısal
#                              olgu üretilmez. `sum(x, na.rm = TRUE) == 0`
#                              ASLA olgusal sıfıra dönüşmez.
#             n_finite == 1 -> toplam/ortalama/medyan/min/maks `single_observation`;
#                              std sapma, yüzdelik, IQR ve uç değer olguları
#                              `insufficient_data` ve DEĞER TAŞIMAZ.
#             n_finite >= 2 -> her istatistik korumalı hesaplanır; sonlu
#                              olmayan sonuç NA/NaN/Inf olarak değil,
#                              kullanılamaz durum olarak raporlanır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yalnızca MERGEN_PK_ENGINE=v2 altında çağrılır.
# ==============================================================================

# Olgu durumları. Kullanıcıya görünen metinde değil, olgu kaydında taşınır.
PK_FACT_OK <- "ok"
PK_FACT_SINGLE <- "single_observation"
PK_FACT_INSUFFICIENT <- "insufficient_data"
PK_FACT_NO_FINITE <- "unavailable_no_finite_values"
PK_FACT_INVALID_WEIGHTS <- "invalid_weight_set"
PK_FACT_WEIGHTED_UNAVAILABLE <- "weighted_mean_unavailable"
PK_FACT_AMBIGUOUS_LATEST <- "ambiguous_latest"

# Sayı biçimleme ---------------------------------------------------------------

#' Yerelden bağımsız Türkçe sayı biçimi
#'
#' `format()` / `formatC()` binlik ayracı olarak "." istendiğinde ondalık ayraç
#' `getOption("OutDec")` ile çakışabilir ve katı test paketinde hataya dönüşen
#' uyarı üretir. Bu yüzden gruplama ELLE yapılır. Bilimsel gösterim hiçbir
#' koşulda oluşmaz (D19).
pk_fmt_number <- function(x, decimals = NULL, unit = NULL) {
  if (is.null(x) || length(x) != 1L) return("?")

  num <- suppressWarnings(as.numeric(x))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return("?")

  ondalik <- suppressWarnings(as.integer(decimals %||% NA_integer_))
  if (is.na(ondalik) || ondalik < 0L) {
    ondalik <- if (isTRUE(all.equal(num, trunc(num))) && abs(num) < 1e15) 0L else 2L
  }
  ondalik <- min(ondalik, 9L)

  ham <- formatC(num, format = "f", digits = ondalik, big.mark = "", decimal.mark = ".")
  ham <- sub("^\\s+", "", ham)

  negatif <- startsWith(ham, "-")
  if (negatif) ham <- substring(ham, 2L)

  parcalar <- strsplit(ham, ".", fixed = TRUE)[[1]]
  tam <- parcalar[1]
  kesir <- if (length(parcalar) > 1L) parcalar[2] else ""

  tam <- gsub("(?<=[0-9])(?=([0-9]{3})+$)", ".", tam, perl = TRUE)

  out <- if (nzchar(kesir)) paste0(tam, ",", kesir) else tam
  if (negatif) out <- paste0("-", out)

  birim <- as.character(unit %||% "")[1]
  if (!is.na(birim) && nzchar(birim)) out <- paste0(out, " ", birim)

  out
}

#' Yüzde payı biçimi (0-1 arası orandan "%12,3")
pk_fmt_share <- function(pay, toplam) {
  if (is.null(toplam) || length(toplam) != 1L) return("?")
  toplam <- suppressWarnings(as.numeric(toplam))
  if (is.na(toplam) || !is.finite(toplam) || toplam <= 0) return("?")

  oran <- suppressWarnings(as.numeric(pay)) / toplam
  if (is.na(oran) || !is.finite(oran)) return("?")

  paste0("%", pk_fmt_number(oran * 100, decimals = 1L))
}

# Olgu kimliği -----------------------------------------------------------------

#' Olgu kimliği için ASCII güvenli parça
#'
#' Sütun adları Türkçe olabilir; olgu kimliği ise protokol jetonudur ve
#' Windows/VM ayrıştırıcı dayanıklılığı için ASCII kalmalıdır (CLAUDE.md §1A).
pk_fact_slug <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return("bilinmeyen")

  # Türkçe harfler ASCII karşılıklarına indirilir; bu YALNIZCA kimlik jetonu
  # içindir, kullanıcıya görünen metinde asla Latinleştirme yapılmaz.
  txt <- chartr(
    "çğıöşüÇĞİIÖŞÜ",
    "cgiosuCGIIOSU",
    txt
  )
  txt <- gsub("[^A-Za-z0-9]+", "_", txt)
  txt <- gsub("^_+|_+$", "", txt)
  txt <- tolower(txt)
  if (!nzchar(txt)) return("bilinmeyen")
  substr(txt, 1L, 60L)
}

#' Kapsam imzası — okunur ve deterministik
#'
#' Karma (hash) yerine okunur metin kullanılır: hem tanılamada işe yarar hem de
#' yeni bir bağımlılık gerektirmez. RLS ÖNCESİ satır sayısı BURAYA GİRMEZ.
pk_scope_signature <- function(authorized_rows = NULL, filtered_rows = NULL,
                               group_keys = character(0)) {
  parcalar <- c(
    sprintf("yetki=%s", if (is.null(authorized_rows)) "?" else as.integer(authorized_rows)),
    sprintf("filtre=%s", if (is.null(filtered_rows)) "?" else as.integer(filtered_rows))
  )

  gruplar <- as.character(group_keys %||% character(0))
  gruplar <- gruplar[!is.na(gruplar) & nzchar(gruplar)]
  if (length(gruplar)) {
    parcalar <- c(parcalar, sprintf("grup=%s", paste(gruplar, collapse = "+")))
  }

  paste(parcalar, collapse = "|")
}

#' Tek bir yapılandırılmış olgu kaydı
#'
#' `value` yalnızca `status == "ok"` veya `single_observation` iken sayısaldır;
#' diğer durumlarda NULL'dur ve prose bu sayıyı ASLA alıntılayamaz.
pk_fact_record <- function(kind, column, aggregation, value = NULL, spec = list(),
                           status = PK_FACT_OK, scope = NULL, group_keys = character(0),
                           time_window = NULL, n_finite = NA_integer_,
                           n_excluded = NA_integer_, note = NULL) {
  spec <- if (is.list(spec)) spec else list()

  cap <- spec$capability
  cap <- if (is.character(cap) && length(cap) == 1L && !is.na(cap) && nzchar(cap)) cap else NULL

  kimlik_kok <- pk_fact_slug(cap %||% column)
  grup_slug <- if (length(group_keys)) {
    paste(vapply(as.character(group_keys), pk_fact_slug, character(1)), collapse = "_")
  } else {
    "overall"
  }
  fact_id <- paste(c(kimlik_kok, pk_fact_slug(aggregation), grup_slug), collapse = ".")

  sayisal <- status %in% c(PK_FACT_OK, PK_FACT_SINGLE) &&
    is.numeric(value) && length(value) == 1L && is.finite(value)

  list(
    fact_id = fact_id,
    kind = as.character(kind)[1],
    column = as.character(column)[1],
    label = as.character(spec$label %||% column)[1],
    measure_capability = cap,
    aggregation = as.character(aggregation)[1],
    value = if (sayisal) as.numeric(value) else NULL,
    unit = spec$unit,
    decimals = spec$decimals,
    status = as.character(status)[1],
    scope = scope,
    group_keys = as.character(group_keys %||% character(0)),
    time_window = time_window,
    n_finite = suppressWarnings(as.integer(n_finite)),
    n_excluded = suppressWarnings(as.integer(n_excluded)),
    note = note,
    display = if (sayisal) pk_fmt_number(value, spec$decimals, spec$unit) else NA_character_
  )
}

# Sayısal ölçü istatistikleri --------------------------------------------------

.pk_finite_split <- function(values) {
  ham <- suppressWarnings(as.numeric(values))
  sonlu <- ham[!is.na(ham) & is.finite(ham)]

  list(
    finite = sonlu,
    n_finite = length(sonlu),
    n_excluded = length(ham) - length(sonlu)
  )
}

# Sonlu olmayan bir sonuç olgu DEĞİL, kullanılamaz durumdur.
.pk_guarded <- function(expr) {
  out <- tryCatch(suppressWarnings(expr), error = function(e) NA_real_)
  if (length(out) != 1L) return(NULL)
  out <- suppressWarnings(as.numeric(out))
  if (is.na(out) || !is.finite(out)) return(NULL)
  out
}

#' Bir sayısal ölçü sütunu için olgu kümesi
#'
#' Toplama YALNIZCA `additive = TRUE` iken üretilir; ortalama yalnızca
#' `aggregate` toplama/ortalama izni verdiğinde üretilir. Metadata yokken
#' (Tier-0) ikisi de üretilmez — Faz 3a'nın adlandırılmış geri düşüşü budur:
#' "additive yok -> toplama YAPILMAZ". Dağılım istatistikleri (medyan, yüzdelik,
#' min/maks, std sapma, uç değer) DÖNEN SATIRLARI betimler; varlık düzeyinde
#' toplulaştırma iddiası taşımaz ve bu yüzden Tier-0'da da güvenlidir.
pk_measure_facts <- function(values, column, spec = list(), scope = NULL,
                             group_keys = character(0), time_window = NULL,
                             aggregate_mode = "none", additive = FALSE) {
  spec <- if (is.list(spec)) spec else list()
  bol <- .pk_finite_split(values)

  # Uç değer SAYISI bir adettir; ölçünün birimini/ondalığını TAŞIMAZ. Aksi
  # hâlde "IQR uc deger sayisi: 0,0 saat" gibi anlamsız bir olgu üretilir.
  sayim_spec <- spec
  sayim_spec$unit <- NULL
  sayim_spec$decimals <- 0L

  yap <- function(agg, deger, durum = PK_FACT_OK, not = NULL) {
    pk_fact_record(
      kind = "measure", column = column, aggregation = agg, value = deger,
      spec = if (identical(agg, "iqr_outliers")) sayim_spec else spec,
      status = durum, scope = scope, group_keys = group_keys,
      time_window = time_window, n_finite = bol$n_finite,
      n_excluded = bol$n_excluded, note = not
    )
  }

  if (bol$n_finite == 0L) {
    return(list(yap("distribution", NULL, PK_FACT_NO_FINITE,
                    "Sonlu deger yok; toplam/ortalama/medyan URETILMEDI.")))
  }

  v <- bol$finite
  tekil <- bol$n_finite == 1L
  temel_durum <- if (tekil) PK_FACT_SINGLE else PK_FACT_OK

  out <- list()

  if (isTRUE(additive)) {
    out[[length(out) + 1L]] <- yap("sum", .pk_guarded(sum(v)), temel_durum)
  } else {
    out[[length(out) + 1L]] <- yap(
      "sum", NULL, PK_FACT_INSUFFICIENT,
      "additive dogrulanmadi; toplam URETILMEDI (Tier-0 geri dususu)."
    )
  }

  if (isTRUE(additive) || aggregate_mode %in% c("sum", "mean")) {
    out[[length(out) + 1L]] <- yap("mean", .pk_guarded(mean(v)), temel_durum)
  } else {
    out[[length(out) + 1L]] <- yap(
      "mean", NULL, PK_FACT_INSUFFICIENT,
      "aggregate ortalamaya izin vermiyor; ortalama URETILMEDI."
    )
  }

  out[[length(out) + 1L]] <- yap("median", .pk_guarded(stats::median(v)), temel_durum)
  out[[length(out) + 1L]] <- yap("min", .pk_guarded(min(v)), temel_durum)
  out[[length(out) + 1L]] <- yap("max", .pk_guarded(max(v)), temel_durum)

  if (tekil) {
    for (agg in c("sd", "p05", "p25", "p75", "p95", "iqr_outliers")) {
      out[[length(out) + 1L]] <- yap(
        agg, NULL, PK_FACT_INSUFFICIENT,
        "Tek gozlem; yayilim/uc deger istatistigi hesaplanamaz."
      )
    }
    return(out)
  }

  out[[length(out) + 1L]] <- yap("sd", .pk_guarded(stats::sd(v)), PK_FACT_OK)

  q <- tryCatch(
    suppressWarnings(stats::quantile(v, probs = c(0.05, 0.25, 0.75, 0.95),
                                     na.rm = TRUE, names = FALSE)),
    error = function(e) rep(NA_real_, 4L)
  )
  adlar <- c("p05", "p25", "p75", "p95")
  for (i in seq_along(adlar)) {
    deger <- .pk_guarded(q[i])
    out[[length(out) + 1L]] <- if (is.null(deger)) {
      yap(adlar[i], NULL, PK_FACT_INSUFFICIENT, "Yuzdelik hesaplanamadi.")
    } else {
      yap(adlar[i], deger, PK_FACT_OK)
    }
  }

  q1 <- .pk_guarded(q[2])
  q3 <- .pk_guarded(q[3])
  if (is.null(q1) || is.null(q3)) {
    out[[length(out) + 1L]] <- yap("iqr_outliers", NULL, PK_FACT_INSUFFICIENT,
                                   "IQR hesaplanamadi.")
    return(out)
  }

  iqr <- q3 - q1
  alt <- q1 - 1.5 * iqr
  ust <- q3 + 1.5 * iqr
  out[[length(out) + 1L]] <- yap(
    "iqr_outliers", sum(v < alt | v > ust), PK_FACT_OK,
    sprintf("Sinirlar: %s / %s", pk_fmt_number(alt, spec$decimals),
            pk_fmt_number(ust, spec$decimals))
  )

  out
}

#' `aggregate = "latest"` olgusu (§5.1 / §5.7)
#'
#' `latest_by` (sıralama sütunu) VE `latest_tie_by` (en yeni damgada satırı
#' benzersiz kılan sütun(lar)) İKİSİ DE zorunludur. `latest_by` içinde `NA`
#' olan satırlar dışlanır. En yeni damgada `latest_tie_by` mükerrer veya eksikse
#' bir değer SEÇİLMEZ; `ambiguous_latest` döner. Veritabanı dönüş sırası,
#' `grain_columns` sırası ve "ilk satır" yedeği geçerli eşitlik bozucu DEĞİLDİR.
pk_latest_fact <- function(data, column, spec = list(), scope = NULL,
                           group_keys = character(0), time_window = NULL) {
  spec <- if (is.list(spec)) spec else list()

  yap <- function(deger, durum, not) {
    pk_fact_record(
      kind = "measure", column = column, aggregation = "latest", value = deger,
      spec = spec, status = durum, scope = scope, group_keys = group_keys,
      time_window = time_window, note = not
    )
  }

  sirala <- as.character(spec$latest_by %||% "")[1]
  esitlik <- as.character(spec$latest_tie_by %||% character(0))
  esitlik <- esitlik[!is.na(esitlik) & nzchar(esitlik)]

  if (is.na(sirala) || !nzchar(sirala) || !length(esitlik)) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST,
               "latest icin latest_by VE latest_tie_by beyani zorunludur."))
  }
  if (!(sirala %in% names(data)) || !all(esitlik %in% names(data))) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST,
               "latest_by veya latest_tie_by sutunu sonucta yok."))
  }

  damga <- data[[sirala]]
  gecerli <- which(!is.na(damga))
  if (!length(gecerli)) {
    return(yap(NULL, PK_FACT_NO_FINITE, "latest_by tamamen bos; deger secilmedi."))
  }

  en_yeni <- max(damga[gecerli])
  aday <- gecerli[damga[gecerli] == en_yeni]

  anahtar <- do.call(paste, c(lapply(esitlik, function(s) as.character(data[[s]])[aday]),
                              list(sep = "")))
  if (any(is.na(anahtar)) || any(!nzchar(anahtar)) || anyDuplicated(anahtar) > 0L) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST, sprintf(
      "En yeni damgada %d satir var ve latest_tie_by benzersiz degil; deger SECILMEDI.",
      length(aday)
    )))
  }

  if (length(aday) != 1L) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST,
               "En yeni damgada birden fazla benzersiz satir var; deger SECILMEDI."))
  }

  deger <- .pk_guarded(suppressWarnings(as.numeric(data[[column]][aday])))
  if (is.null(deger)) {
    return(yap(NULL, PK_FACT_NO_FINITE, "En yeni satirdaki deger sonlu degil."))
  }

  yap(deger, PK_FACT_OK, sprintf("En yeni %s = %s", sirala, as.character(en_yeni)))
}

#' Ağırlıklı ortalama olgusu (§5.7 geçersiz ağırlık sözleşmesi)
#'
#' Yalnızca ölçü VE ağırlığın ikisi de sonlu ve ağırlığın kesin pozitif olduğu
#' çiftler kullanılır. Negatif/sonsuz ağırlık `invalid_weight_set` döndürür;
#' pozitif çift kalmazsa `weighted_mean_unavailable` döner. Ağırlıksız
#' ortalamaya, sıfıra veya NaN'a SESSİZCE düşülmez.
pk_weighted_mean_fact <- function(values, weights, column, spec = list(),
                                  scope = NULL, group_keys = character(0),
                                  time_window = NULL, weight_column = NULL) {
  spec <- if (is.list(spec)) spec else list()

  olcu <- suppressWarnings(as.numeric(values))
  agirlik <- suppressWarnings(as.numeric(weights))

  yap <- function(deger, durum, not, n_finite = NA_integer_, n_excluded = NA_integer_) {
    pk_fact_record(
      kind = "measure", column = column, aggregation = "weighted_mean",
      value = deger, spec = spec, status = durum, scope = scope,
      group_keys = group_keys, time_window = time_window,
      n_finite = n_finite, n_excluded = n_excluded, note = not
    )
  }

  if (length(olcu) != length(agirlik)) {
    return(yap(NULL, PK_FACT_INVALID_WEIGHTS,
               "Olcu ve agirlik uzunluklari uyusmuyor."))
  }

  # Negatif veya sonsuz ağırlık, ağırlık kümesinin tamamını geçersiz kılar.
  bozuk <- !is.na(agirlik) & (!is.finite(agirlik) | agirlik < 0)
  if (any(bozuk)) {
    return(yap(NULL, PK_FACT_INVALID_WEIGHTS, sprintf(
      "%d satirda negatif/sonlu olmayan agirlik var; agirlikli ortalama URETILMEDI.",
      sum(bozuk)
    )))
  }

  gecerli <- !is.na(olcu) & is.finite(olcu) & !is.na(agirlik) &
    is.finite(agirlik) & agirlik > 0
  disarida <- length(olcu) - sum(gecerli)

  if (!any(gecerli)) {
    return(yap(NULL, PK_FACT_WEIGHTED_UNAVAILABLE, sprintf(
      "Pozitif agirlikli sonlu cift kalmadi (%d satir disarida).", disarida
    ), n_finite = 0L, n_excluded = disarida))
  }

  toplam_agirlik <- .pk_guarded(sum(agirlik[gecerli]))
  if (is.null(toplam_agirlik) || toplam_agirlik <= 0) {
    return(yap(NULL, PK_FACT_WEIGHTED_UNAVAILABLE,
               "Toplam agirlik pozitif degil.", n_finite = sum(gecerli),
               n_excluded = disarida))
  }

  deger <- .pk_guarded(sum(olcu[gecerli] * agirlik[gecerli]) / toplam_agirlik)
  if (is.null(deger)) {
    return(yap(NULL, PK_FACT_WEIGHTED_UNAVAILABLE,
               "Agirlikli ortalama sonlu bir deger uretmedi.",
               n_finite = sum(gecerli), n_excluded = disarida))
  }

  not <- sprintf("Agirlik sutunu: %s. Disarida birakilan satir: %d.",
                 as.character(weight_column %||% "?")[1], disarida)
  yap(deger, if (sum(gecerli) == 1L) PK_FACT_SINGLE else PK_FACT_OK, not,
      n_finite = sum(gecerli), n_excluded = disarida)
}
