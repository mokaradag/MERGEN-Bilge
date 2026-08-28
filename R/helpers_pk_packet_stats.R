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
#           KİMLİK ÇAKIŞMASI (inceleme bulgusu): olgu kimliği ASCII'ye
#           indirgenip 60 karaktere kırpılır. `A-B` ile `A B`, ya da ilk 60
#           normalleştirilmiş karakteri aynı olan iki uzun proje adı aynı
#           kimliği alırdı ve `pk_facts_index()` birini SESSİZCE ezerdi; doğru
#           alıntılanmış bir sayı yanlış ölçüye karşı doğrulanırdı. Kimliğin
#           sonuna, KIRPILMAMIŞ özgün kimlikten türetilen kararlı bir sağlama
#           eklenir.
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
PK_FACT_GRAIN_VIOLATION <- "grain_violation"
PK_FACT_PRECISION <- "unsupported_precision"
PK_FACT_NOT_FINITE_RESULT <- "non_finite_result"

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

  # PAY DA UZUNLUK DENETİMİNDEN GEÇER: `NULL` / uzunluğu sıfır bir pay
  # `numeric(0)` üretir ve `if (logical(0))` R'de HATA fırlatırdı; yazıcı tüm
  # paketi düşürürdü. `pk_fmt_number()` ile AYNI muhafız kullanılır.
  pay_num <- suppressWarnings(as.numeric(pay))
  if (length(pay_num) != 1L) return("?")

  oran <- pay_num / toplam
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
  # OLGU KİMLİĞİ ASCII OLMAK ZORUNDA.
  #
  # Bu noktada metin zaten ASCII'ye indirgenmiştir; ancak Türkçe yerelde
  # `tolower("I")` noktasız `ı` (ASCII DIŞI) üretir ve kimlik VM ile CI
  # arasında farklılaşır. Aynı olgu iki farklı `[fact:...]` kimliği alır,
  # modelin işareti doğrulamada bulunamaz ve geçerli sayı reddedilir.
  # Yerelden BAGIMSIZ ASCII kucuk harf; Turkce yerelde tolower("I") -> "i"
  # (noktasiz) uretir ve olgu kimligi VM ile CI arasinda FARKLILASIR.
  txt <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
  if (!nzchar(txt)) return("bilinmeyen")
  substr(txt, 1L, 60L)
}

#' Kimlik parçalarından kararlı, ASCII, çakışmaya dayanıklı sağlama
#'
#' Yeni bağımlılık eklenmemesi için saf tabanlı FNV-1a türevi kullanılır;
#' aritmetik 24 bitte tutulur (çift duyarlıkta tam olarak temsil edilir).
pk_fact_checksum <- function(parts) {
  ham <- enc2utf8(paste(as.character(parts %||% ""), collapse = ""))
  bayt <- as.integer(charToRaw(ham))

  h <- 2166136261 %% 16777216
  for (b in bayt) {
    h <- bitwXor(as.integer(h), b)
    h <- (h * 16777619) %% 16777216
  }

  sprintf("%06x", as.integer(h))
}

#' Bir olgu kimliğini kur (kayıt kurmadan)
#'
#' Paket kurucusu ile paket yazıcısı AYNI kimliği üretmek zorundadır: yazıcı
#' `[fact:...]` işaretini basar, doğrulayıcı ise kurucunun ürettiği indeksi
#' okur. Kimlik üretimi bu yüzden tek bir yerden gelir.
pk_fact_id <- function(identity, aggregation, group_keys = character(0)) {
  gruplar <- as.character(group_keys %||% character(0))
  grup_slug <- if (length(gruplar)) {
    paste(vapply(gruplar, pk_fact_slug, character(1)), collapse = "_")
  } else {
    "overall"
  }

  paste(c(pk_fact_slug(identity), pk_fact_slug(aggregation), grup_slug,
          pk_fact_checksum(c(identity, aggregation, gruplar))), collapse = ".")
}

#' GRUP kırılımı olgu kimliği (AD ALANLI)
#'
#' Grup kimliği eskiden `paste(group_by, collapse = "+")` idi. Tek sütunlu bir
#' kırılımda bu dize AYNI adı taşıyan KATEGORİK sütunun kimliğine eşit olur ve
#' `other_rows` gibi ortak toplama adlarında iki farklı olgu tek bir
#' `pk_fact_id()` paylaşır; kimliğe göre biriktirmede biri DÜŞER ve yazıcının
#' bastığı kategorik sayım GRUP değerine karşı doğrulanır. Ön ek çakışmayı
#' kaldırır ve HEM üretici HEM yazıcı bu tek kaynaktan okur.
.pk_group_fact_id <- function(group_by) {
  paste0("grup:", paste(as.character(group_by %||% character(0)), collapse = "+"))
}

#' Kapsam imzası — okunur ve deterministik
#'
#' Karma (hash) yerine okunur metin kullanılır: hem tanılamada işe yarar hem de
#' yeni bir bağımlılık gerektirmez. RLS ÖNCESİ satır sayısı BURAYA GİRMEZ.
pk_scope_signature <- function(authorized_rows = NULL, filtered_rows = NULL,
                               group_keys = character(0)) {
  # TAMSAYIYA ÇEVİRME YAPILMAZ: 2^31 üstündeki bir sayım `as.integer()` ile
  # `NA`ya çöker (üstelik uyarı üretir; sıkı pakette uyarı HATADIR) ve iki AYRI
  # kapsam `yetki=NA|filtre=NA` ile AYNI imzayı üretirdi.
  .say <- function(x) {
    v <- suppressWarnings(as.numeric(x)[1])
    if (length(v) != 1L || is.na(v) || !is.finite(v)) "?" else sprintf("%.0f", v)
  }
  parcalar <- c(
    sprintf("yetki=%s", if (is.null(authorized_rows)) "?" else .say(authorized_rows)),
    sprintf("filtre=%s", if (is.null(filtered_rows)) "?" else .say(filtered_rows))
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

  # Sağlama KIRPILMAMIŞ özgün kimlikten hesaplanır: normalleştirme/kırpma
  # yüzünden aynı slug'a düşen iki farklı ölçü/grup artık AYNI kimliği alamaz.
  fact_id <- pk_fact_id(cap %||% column, aggregation, group_keys)

  sayisal <- status %in% c(PK_FACT_OK, PK_FACT_SINGLE) &&
    is.numeric(value) && length(value) == 1L && is.finite(value)

  # KESİR TABANLI YÜZDELER OLGU KURULURKEN PUANA ÇEVRİLİR.
  #
  # Metadata `unit = "%"` ve `percent_scale = "fraction"` ilan ettiğinde ham
  # değer 0..1 aralığındadır. Satır içi tablo ve dışa aktarım yolları bunu ZATEN
  # 100 ile ölçekliyor; olgu yolu ölçeklemiyordu. Sonuç iki yönlü bozuktu: model
  # `0,6 %` gibi YANLIŞ bir olgu görüyordu ve kullanıcı doğru biçimde `%61,3`
  # yazdığında köken doğrulaması bunu değer uyuşmazlığı sayıp REDDEDİYORDU.
  # Kanonik değer ile gösterim artık aynı ölçekte üretilir.
  if (sayisal && identical(as.character(spec$unit %||% "")[1], "%") &&
      identical(as.character(spec$percent_scale %||% "")[1], "fraction")) {
    value <- as.numeric(value) * 100
    # ÖLÇEKLEME SONRASI SONLULUK YENİDEN DENETLENİR: `double.xmax / 100`
    # üstündeki bozuk bir değer çarpımdan `Inf` olarak çıkıyor ve `ok` durumlu
    # bir olgu `value = Inf` ile üretiliyordu.
    if (!is.finite(value)) {
      sayisal <- FALSE
      value <- NULL
      status <- PK_FACT_NOT_FINITE_RESULT
    }
  }

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

# SQL Server BIGINT sütunları çoğunlukla `bit64::integer64` olarak gelir.
# `as.numeric()` 2^53 ustundeki tam sayıyı temsil EDEMEZ; 9007199254740993
# sessizce 9007199254740992 olurdu. Böyle bir sütun hesaplanmaz, açıkça
# desteklenmeyen kesinlik olarak raporlanır.
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

# Sıralanabilir tipe indirge. Karakter bir damga ÜZERİNDE `max()` sözlük
# sırasına göre çalışır: "31.12.2025" > "01.01.2026" ve "9" > "10".
.pk_orderable <- function(x) {
  if (inherits(x, "Date") || inherits(x, "POSIXt") || is.numeric(x)) return(x)
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(NULL)

  dolu <- sum(!is.na(x))
  tarih <- suppressWarnings(tryCatch(as.Date(x), error = function(e) NULL))
  if (!is.null(tarih) && inherits(tarih, "Date") && sum(!is.na(tarih)) == dolu) {
    return(tarih)
  }

  sayi <- suppressWarnings(as.numeric(x))
  if (sum(!is.na(sayi)) == dolu) return(sayi)

  NULL
}

#' Bir sayısal ölçü sütunu için olgu kümesi
#'
#' Toplama YALNIZCA `additive = TRUE` iken üretilir. Ortalama ise beyan edilen
#' toplulaştırma FARKLI ve bağdaşmaz bir metrik dayattığında (ör.
#' `weighted_mean`, `latest`) ÜRETİLMEZ: ağırlıklı ortalama beyan eden bir ölçü
#' için düz satır ortalaması yayımlamak, sorgunun yanlış dediği sayıyı yetkili
#' olgu diye sunmaktır; metadata yokken (Tier-0) ikisi de üretilmez.
#' Dağılım istatistikleri (medyan, yüzdelik, min/maks, std sapma, uç değer)
#' DÖNEN SATIRLARI betimler; toplulaştırma iddiası taşımaz, Tier-0'da güvenlidir.
#'
#' @param aggregate_blocked Tanecikte mükerrer satır varsa TRUE; toplam ve ortalama çift sayılacağı için ÜRETİLMEZ.
pk_measure_facts <- function(values, column, spec = list(), scope = NULL,
                             group_keys = character(0), time_window = NULL,
                             aggregate_mode = "none", additive = FALSE,
                             aggregate_blocked = FALSE) {
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

  # `.pk_guarded()` NULL döndüğünde (taşan toplam, tanımsız std sapma) olgu
  # `ok` kalırsa pakette gerekçesiz "KULLANILAMAZ (ok)" görünürdü.
  guvenli <- function(agg, deger, durum, not = NULL) {
    if (is.null(deger)) {
      return(yap(agg, NULL, PK_FACT_NOT_FINITE_RESULT,
                 "Hesaplama sonlu bir deger uretmedi (tasma veya tanimsiz sonuc)."))
    }
    yap(agg, deger, durum, not)
  }

  if (.pk_precision_loss(values)) {
    return(list(yap("distribution", NULL, PK_FACT_PRECISION, paste(
      "Sutun 2^53 ustunde tam sayi tasiyor (BIGINT/integer64);",
      "cift duyarlikli hesaplama degeri DEGISTIRIRDI, olgu URETILMEDI."
    ))))
  }

  if (bol$n_finite == 0L) {
    return(list(yap("distribution", NULL, PK_FACT_NO_FINITE,
                    "Sonlu deger yok; toplam/ortalama/medyan URETILMEDI.")))
  }

  v <- bol$finite
  tekil <- bol$n_finite == 1L
  temel_durum <- if (tekil) PK_FACT_SINGLE else PK_FACT_OK
  agg_kip <- as.character(aggregate_mode %||% "none")[1]
  # Ortalamayı dışlayan beyanlar: bu ölçünün doğru metriği başka bir şeydir.
  ortalama_disi <- agg_kip %in% c("weighted_mean", "latest", "min", "max",
                                  "count", "count_distinct", "median")

  out <- list()

  if (isTRUE(aggregate_blocked)) {
    for (agg in c("sum", "mean")) {
      out[[length(out) + 1L]] <- yap(
        agg, NULL, PK_FACT_GRAIN_VIOLATION,
        "Beyan edilen tanecikte mukerrer satir var; cift sayim riski nedeniyle URETILMEDI."
      )
    }
  } else {
    if (isTRUE(additive)) {
      out[[length(out) + 1L]] <- guvenli("sum", .pk_guarded(sum(v)), temel_durum)
    } else {
      out[[length(out) + 1L]] <- yap(
        "sum", NULL, PK_FACT_INSUFFICIENT,
        "additive dogrulanmadi; toplam URETILMEDI (Tier-0 geri dususu)."
      )
    }

    if ((isTRUE(additive) || agg_kip %in% c("mean", "avg", "average")) && !ortalama_disi) {
      out[[length(out) + 1L]] <- guvenli("mean", .pk_guarded(mean(v)), temel_durum)
    } else {
      out[[length(out) + 1L]] <- yap(
        "mean", NULL, PK_FACT_INSUFFICIENT,
        sprintf("aggregate='%s' duz ortalamaya izin vermiyor; ortalama URETILMEDI.", agg_kip)
      )
    }
  }

  out[[length(out) + 1L]] <- guvenli("median", .pk_guarded(stats::median(v)), temel_durum)
  out[[length(out) + 1L]] <- guvenli("min", .pk_guarded(min(v)), temel_durum)
  out[[length(out) + 1L]] <- guvenli("max", .pk_guarded(max(v)), temel_durum)

  if (tekil) {
    for (agg in c("sd", "p05", "p25", "p75", "p95", "iqr_outliers")) {
      out[[length(out) + 1L]] <- yap(
        agg, NULL, PK_FACT_INSUFFICIENT,
        "Tek gozlem; yayilim/uc deger istatistigi hesaplanamaz."
      )
    }
    return(out)
  }

  out[[length(out) + 1L]] <- guvenli("sd", .pk_guarded(stats::sd(v)), PK_FACT_OK)

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

  # NOT DA OLGULARLA AYNI ÖLÇEKTE BASILIR.
  #
  # `pk_fact_record()` `unit = "%"` + `percent_scale = "fraction"` olduğunda
  # değeri 100 ile çarpar. Bu not ise çarpımdan ÖNCE kuruluyordu: paket aynı
  # sütun için `p25` değerini yüzde olarak, komşu aykırı-değer notunu ise 0..1
  # kesri olarak gösteriyordu. Model tek ölçü için İKİ farklı ölçek görüyor ve
  # aktardığı sınırın karşılığı olan bir olgu bulunmuyordu.
  not_olcegi <- if (identical(as.character(spec$unit %||% "")[1], "%") &&
                    identical(as.character(spec$percent_scale %||% "")[1], "fraction")) 100 else 1
  out[[length(out) + 1L]] <- yap(
    "iqr_outliers", sum(v < alt | v > ust), PK_FACT_OK,
    sprintf("Sinirlar: %s / %s", pk_fmt_number(alt * not_olcegi, spec$decimals),
            pk_fmt_number(ust * not_olcegi, spec$decimals))
  )

  out
}

#' `aggregate = "latest"` olgusu (§5.1 / §5.7)
#'
#' `latest_by` (sıralama sütunu) VE `latest_tie_by` (en yeni damgada satırı
#' benzersiz kılan sütun(lar)) İKİSİ DE zorunludur. `latest_by` SIRALANABİLİR
#' bir tipe indirgenemezse (ör. `"31.12.2025"` gibi yerel biçimli metin)
#' `ambiguous_latest` döner; sözlük sırasına göre "en yeni" seçmek sessizce
#' YANLIŞ satırı seçerdi. `latest_by` içinde `NA` olan satırlar dışlanır.
#'
#' EŞİTLİK BOZMA: en yeni damgada birden fazla satır varsa ve `latest_tie_by`
#' bu satırları BENZERSİZ kılıyorsa, eşitlik sütunları üzerinde yerelden
#' bağımsız (radix) artan sıralama uygulanır ve SON satır seçilir. Eşitlik
#' anahtarı eksik ya da mükerrerse hiçbir değer SEÇİLMEZ. Veritabanı dönüş
#' sırası ve "ilk satır" yedeği geçerli eşitlik bozucu DEĞİLDİR.
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

  damga <- .pk_orderable(data[[sirala]])
  if (is.null(damga)) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST, sprintf(
      "latest_by ('%s') siralanabilir bir tipe cevrilemedi; 'en yeni' SECILMEDI.", sirala
    )))
  }

  gecerli <- which(!is.na(damga))
  if (!length(gecerli)) {
    return(yap(NULL, PK_FACT_NO_FINITE, "latest_by tamamen bos; deger secilmedi."))
  }

  en_yeni <- max(damga[gecerli])
  aday <- gecerli[damga[gecerli] == en_yeni]

  # BENZERSİZLİK ANAHTARI ile SIRALAMA ANAHTARI AYRIDIR; SIRALAMA TİPİ KORUNUR.
  #
  # Uzunluk önekli seri hâl (`3:abc`) çakışmasız bir KİMLİKTİR ama SIRA
  # KORUYUCU DEĞİLDİR: `z` -> `1:z`, `aa` -> `2:aa` olur ve radix sıralaması
  # `aa`yı son sıraya koyar; oysa ham artan sıralamada son değer `z`dir.
  # Sayısal bir `latest_tie_by` sütununu karaktere çevirmek de `order()`u
  # SÖZLÜKSEL yapar: `2` ve `10` -> `"10", "2"` sıralanır ve SON satır olarak
  # `2` anahtarlı satır seçilip ölçüsü kanonik `latest` olgusu diye yayımlanır.
  # Her iki durumda da YANLIŞ satır "en yeni" sayılırdı. Sıralanabilir tipler
  # (sayısal/tarih/mantıksal) KENDİ tiplerinde tutulur; karakter kodlama ve
  # uzunluk öneki YALNIZCA benzersizlik/çakışma denetiminde kullanılır.
  # SÜTUNLAR TEK TEK `[[` İLE ALINIR (sınıf bağımsız).
  #
  # `data[esitlik]` bir `data.frame`de sütun seçimidir ama `data.table`de
  # `i` ifadesi (join) olarak yorumlanır; çağıran bir gün data.table geçirirse
  # sessizce YANLIŞ satırlar seçilirdi. `[[` her iki sınıfta da sütundur.
  tie_sutunlari <- vector("list", length(esitlik))
  names(tie_sutunlari) <- esitlik
  for (i in seq_along(esitlik)) tie_sutunlari[[i]] <- data[[esitlik[i]]]
  sira_tie <- lapply(tie_sutunlari, function(sutun) {
    dilim <- sutun[aday]
    kanonik <- .pk_orderable(dilim)
    if (!is.null(kanonik)) return(kanonik)
    as.character(dilim)
  })
  ham_tie <- lapply(tie_sutunlari, function(sutun) as.character(sutun)[aday])

  # Uzunluk öneki ÇAKIŞMASIZ bir KİMLİKTİR ama SIRA KORUYUCU DEĞİLDİR; bu
  # yüzden yalnızca benzersizlik denetiminde kullanılır, sıralamada DEĞİL.
  onekli <- ham_tie
  for (i in seq_along(onekli)) {
    ch <- onekli[[i]]
    yeni <- paste0(nchar(ch, type = "bytes"), ":", ch)
    yeni[is.na(ch)] <- "<NA>:"
    onekli[[i]] <- yeni
  }
  anahtar <- do.call(paste, c(onekli, list(sep = "|")))

  # BİLEŞİK anahtarın HERHANGİ bir sütununda eksik değer varsa anahtar
  # benzersiz sayılamaz. Eski denetim `^<NA>:` ile YALNIZCA İLK sütunu
  # görüyordu; ikinci/üçüncü tie sütunundaki NA fark edilmeden geçiyordu.
  eksik_var <- Reduce(`|`, lapply(ham_tie, is.na), init = rep(FALSE, length(aday)))

  if (any(eksik_var) || anyDuplicated(anahtar) > 0L) {
    return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST, sprintf(
      "En yeni damgada %d satir var ve latest_tie_by benzersiz degil; deger SECILMEDI.",
      length(aday)
    )))
  }

  secilen <- if (length(aday) == 1L) {
    aday
  } else {
    # SIRALAMA ANAHTARI DA BENZERSİZ OLMAK ZORUNDADIR.
    #
    # Sıfır dolgulu bir karakter `latest_tie_by` sütunu (`"01"` / `"1"`)
    # `.pk_orderable()` içinde SAYIYA çevrilir. Benzersizlik denetimi HAM
    # metinde geçer (`2:01` != `1:1`) ama sıralama anahtarı EŞİTLENİR ve
    # `order()` girdi sırasını korur; böylece veritabanı dönüş sırası sessizce
    # eşitlik bozucu olurdu. Sıralamadan SONRA eşitlik kalıyorsa değer SEÇİLMEZ.
    duzen <- do.call(order, c(sira_tie, list(method = "radix")))
    sirali <- do.call(paste, c(
      lapply(sira_tie, function(s) as.character(s)[duzen]),
      list(sep = "\u001f")
    ))
    if (anyDuplicated(sirali) > 0L) {
      return(yap(NULL, PK_FACT_AMBIGUOUS_LATEST, sprintf(
        "latest_tie_by siralama anahtari %d satirda AYNI degere dusuyor; deger SECILMEDI.",
        length(aday)
      )))
    }
    aday[duzen][length(aday)]
  }

  # integer64 KESİNLİK MUHAFAZASI "en yeni" olgusunda da geçerlidir.
  #
  # Ölçü istatistiklerinde `.pk_precision_loss()` uygulanıyordu ama bu yol
  # doğrudan `as.numeric()` çağırıyordu; 2^53 üstü bir BIGINT sessizce
  # yuvarlanıp GERÇEK olmayan bir sayı olgu olarak yayımlanabiliyordu.
  if (.pk_precision_loss(data[[column]][secilen])) {
    return(yap(NULL, PK_FACT_PRECISION, paste(
      "En yeni satirdaki deger 2^53 ustunde tam sayi tasiyor (BIGINT/integer64);",
      "kayipsiz temsil edilemedigi icin SECILMEDI."
    )))
  }

  deger <- .pk_guarded(suppressWarnings(as.numeric(data[[column]][secilen])))
  if (is.null(deger)) {
    return(yap(NULL, PK_FACT_NO_FINITE, "En yeni satirdaki deger sonlu degil."))
  }

  not <- if (length(aday) == 1L) {
    sprintf("En yeni %s = %s", sirala, as.character(en_yeni))
  } else {
    sprintf("En yeni %s = %s; %d esit satir arasindan latest_tie_by (%s) artan siralamada SON satir secildi.",
            sirala, as.character(en_yeni), length(aday), paste(esitlik, collapse = ", "))
  }

  yap(deger, PK_FACT_OK, not)
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

  if (.pk_precision_loss(values) || .pk_precision_loss(weights)) {
    return(yap(NULL, PK_FACT_PRECISION, paste(
      "Olcu veya agirlik 2^53 ustunde tam sayi tasiyor (BIGINT/integer64);",
      "agirlikli ortalama URETILMEDI."
    )))
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
