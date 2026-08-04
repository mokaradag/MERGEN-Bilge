# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_packet.R
# Açıklama: Proje ve Kaynak Analizi v2 ANALİZ PAKETİ (master plan §5.7).
#
#           `generate_statistical_summary()`in yerini alır ve şu kusurları
#           kapatır:
#             D17 — Eski özet her kategorik sütun için `top5` hesaplayıp
#                   yalnızca `top5[1]`i kullanıyordu ve SADECE İLK BEŞ
#                   kategorik sütunu özetliyordu (`head(cat_cols, 5)`),
#                   üstelik sessizce. Paket TÜM boyut sütunlarını, ilk-K değeri
#                   adet VE pay ile birlikte, "Diğer (N)" toplamasıyla verir;
#                   bütçe nedeniyle bir şey düşerse bunu SÖYLER.
#             D18 — Eski örnek satır kümesi `head(data, 500)` idi; yani SQL'in
#                   döndürdüğü sıraya göre KONUMSAL YANLI bir örnekti. Paket
#                   ilk-N + son-N + uç değer + SABİT TOHUMLU TABAKALI örnek
#                   kullanır.
#             D19 — Sayılar `capture.output(print(...))` ile bilimsel gösterime
#                   düşüyordu. Paketteki her sayı `pk_fmt_number()` ile
#                   biçimlenir.
#
#           İstatistikler TÜM satırlar üzerinden hesaplanır; örneklem değildir.
#           Modele giden pakette RLS ÖNCESİ satır sayısı BULUNMAZ; yalnızca
#           yetkili popülasyon ve filtre sonrası popülasyon vardır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yalnızca MERGEN_PK_ENGINE=v2 altında çağrılır.
# ==============================================================================

.pk_packet_cfg <- function(key, query_meta = NULL, fallback) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
  tryCatch(pk_config_resolve(key, query_meta = query_meta), error = function(e) fallback)
}

.pk_packet_column_spec <- function(meta, column) {
  cmeta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta[[column]] else NULL
  if (!is.list(cmeta)) cmeta <- list()

  list(
    label = if (is.character(cmeta$label) && nzchar(cmeta$label %||% "")) cmeta$label else column,
    unit = cmeta$unit,
    decimals = cmeta$decimals,
    capability = cmeta$capability,
    role = cmeta$role,
    additive = isTRUE(cmeta$additive),
    aggregate = cmeta$aggregate,
    weight_by = cmeta$weight_by,
    percent_scale = cmeta$percent_scale
  )
}

.pk_packet_meta <- function(query) {
  if (is.list(query) && is.list(query$meta)) return(query$meta)
  list()
}

# Rol sınıflandırması: metadata varsa ona, yoksa R sınıfına göre.
.pk_packet_roles <- function(data, meta) {
  out <- list(measure = character(0), dimension = character(0),
              date = character(0), id = character(0))

  for (sutun in names(data)) {
    cmeta <- if (is.list(meta$column_meta)) meta$column_meta[[sutun]] else NULL
    rol <- if (is.list(cmeta) && is.character(cmeta$role) && length(cmeta$role) == 1L) {
      cmeta$role
    } else if (inherits(data[[sutun]], "Date") || inherits(data[[sutun]], "POSIXt")) {
      "date"
    } else if (is.numeric(data[[sutun]])) {
      "measure"
    } else {
      "dimension"
    }

    if (!rol %in% names(out)) rol <- "dimension"
    out[[rol]] <- c(out[[rol]], sutun)
  }

  out
}

# Kapsama: sütun bazlı boş oranı + beyan edilen grain'de mükerrer satır sayısı.
pk_packet_coverage <- function(data, meta) {
  toplam <- nrow(data)
  bos_oranlari <- lapply(names(data), function(sutun) {
    bos <- sum(is.na(data[[sutun]]))
    list(column = sutun, missing = bos,
         share = if (toplam > 0) bos / toplam else NA_real_)
  })

  grain_sutunlari <- as.character(meta$grain_columns %||% character(0))
  grain_sutunlari <- grain_sutunlari[grain_sutunlari %in% names(data)]

  mukerrer <- if (length(grain_sutunlari)) {
    anahtar <- do.call(paste, c(lapply(grain_sutunlari, function(s) as.character(data[[s]])),
                                list(sep = "")))
    sum(duplicated(anahtar))
  } else {
    NA_integer_
  }

  list(
    rows = toplam,
    columns = length(data),
    missing = bos_oranlari,
    grain_columns = grain_sutunlari,
    duplicate_rows_at_grain = mukerrer
  )
}

# Kategorik özet: TÜM boyut sütunları, ilk-K değer adet VE pay ile (D17).
pk_packet_categorical <- function(data, meta, columns, top_k = 10L) {
  top_k <- max(1L, suppressWarnings(as.integer(top_k)))
  toplam <- nrow(data)

  lapply(columns, function(sutun) {
    degerler <- as.character(data[[sutun]])
    gecerli <- degerler[!is.na(degerler)]
    tablo <- sort(table(gecerli), decreasing = TRUE)

    ilk <- utils::head(tablo, top_k)
    kalan_adet <- max(0L, length(tablo) - length(ilk))
    kalan_satir <- if (kalan_adet > 0L) sum(tablo) - sum(ilk) else 0L

    list(
      column = sutun,
      label = .pk_packet_column_spec(meta, sutun)$label,
      distinct = length(tablo),
      missing = sum(is.na(degerler)),
      total = toplam,
      top = lapply(seq_along(ilk), function(i) {
        list(value = names(ilk)[i], count = as.integer(ilk[i]),
             share = if (toplam > 0) as.numeric(ilk[i]) / toplam else NA_real_)
      }),
      other_values = kalan_adet,
      other_rows = as.integer(kalan_satir)
    )
  })
}

# Tarih özeti: aralık + aya göre satır histogramı.
pk_packet_dates <- function(data, meta, columns, max_buckets = 24L) {
  lapply(columns, function(sutun) {
    degerler <- data[[sutun]]
    gecerli <- degerler[!is.na(degerler)]
    if (!length(gecerli)) {
      return(list(column = sutun, label = .pk_packet_column_spec(meta, sutun)$label,
                  n = 0L, from = NA_character_, to = NA_character_, buckets = list()))
    }

    aylar <- format(as.Date(gecerli), "%Y-%m")
    tablo <- table(aylar)
    tablo <- tablo[order(names(tablo))]
    kirpildi <- length(tablo) > max_buckets
    if (kirpildi) tablo <- utils::tail(tablo, max_buckets)

    list(
      column = sutun,
      label = .pk_packet_column_spec(meta, sutun)$label,
      n = length(gecerli),
      from = as.character(min(as.Date(gecerli))),
      to = as.character(max(as.Date(gecerli))),
      truncated = kirpildi,
      buckets = lapply(seq_along(tablo), function(i) {
        list(bucket = names(tablo)[i], count = as.integer(tablo[i]))
      })
    )
  })
}

# Örnek satırlar: ilk-N + son-N + uç değer + SABİT TOHUMLU TABAKALI örnek (D18).
pk_packet_examples <- function(data, meta, measure_column = NULL,
                               stratify_column = NULL, n = 30L, seed = 42L) {
  n <- max(1L, suppressWarnings(as.integer(n)))
  toplam <- nrow(data)
  if (toplam == 0L) return(list(rows = data, method = "empty", requested = n))

  if (toplam <= n) {
    return(list(rows = data, method = "tam_kume", requested = n,
                indices = seq_len(toplam)))
  }

  secilen <- integer(0)
  yontemler <- character(0)

  if (!is.null(measure_column) && measure_column %in% names(data) &&
      is.numeric(data[[measure_column]])) {
    v <- suppressWarnings(as.numeric(data[[measure_column]]))
    sirali <- order(v, decreasing = TRUE, na.last = NA)
    pay <- max(1L, floor(n / 5))
    secilen <- c(secilen, utils::head(sirali, pay), utils::tail(sirali, pay))
    yontemler <- c(yontemler, "en_yuksek", "en_dusuk")

    sonlu <- v[!is.na(v) & is.finite(v)]
    if (length(sonlu) >= 4L) {
      q <- suppressWarnings(stats::quantile(sonlu, c(0.25, 0.75), na.rm = TRUE, names = FALSE))
      iqr <- q[2] - q[1]
      if (is.finite(iqr)) {
        uc <- which(!is.na(v) & is.finite(v) & (v < q[1] - 1.5 * iqr | v > q[2] + 1.5 * iqr))
        if (length(uc)) {
          secilen <- c(secilen, utils::head(uc, pay))
          yontemler <- c(yontemler, "uc_deger")
        }
      }
    }
  }

  kalan <- setdiff(seq_len(toplam), unique(secilen))
  kota <- n - length(unique(secilen))

  if (kota > 0L && length(kalan)) {
    # RNG durumu korunur: sabit tohum yalnızca bu örneklemeyi etkiler.
    eski_tohum <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      get(".Random.seed", envir = globalenv())
    } else {
      NULL
    }
    on.exit({
      if (is.null(eski_tohum)) {
        suppressWarnings(rm(".Random.seed", envir = globalenv()))
      } else {
        assign(".Random.seed", eski_tohum, envir = globalenv())
      }
    }, add = TRUE)

    set.seed(as.integer(seed))

    tabaka <- if (!is.null(stratify_column) && stratify_column %in% names(data)) {
      as.character(data[[stratify_column]])[kalan]
    } else {
      rep("tek_tabaka", length(kalan))
    }
    tabaka[is.na(tabaka)] <- "(bos)"

    gruplar <- split(kalan, tabaka)
    # Tabaka başına en az bir satır; kota bitene kadar dönüşümlü seçim.
    havuz <- lapply(gruplar, function(idx) sample(idx, length(idx)))
    yontemler <- c(yontemler, if (length(havuz) > 1L) "tabakali_ornek" else "rastgele_ornek")

    i <- 1L
    while (kota > 0L && length(havuz)) {
      isim <- names(havuz)[((i - 1L) %% length(havuz)) + 1L]
      if (!length(havuz[[isim]])) {
        havuz[[isim]] <- NULL
        next
      }
      secilen <- c(secilen, havuz[[isim]][1])
      havuz[[isim]] <- havuz[[isim]][-1]
      kota <- kota - 1L
      i <- i + 1L
    }
  }

  secilen <- unique(secilen)
  secilen <- utils::head(secilen[order(secilen)], n)

  list(
    rows = data[secilen, , drop = FALSE],
    method = paste(unique(yontemler), collapse = "+"),
    requested = n,
    indices = secilen
  )
}

# Grup kırılımı: default_group_by x default_measures, ilk-N + "Diğer".
pk_packet_groups <- function(data, meta, scope = NULL, top_n = 15L) {
  gruplar <- as.character(meta$default_group_by %||% character(0))
  olculer <- as.character(meta$default_measures %||% character(0))
  gruplar <- gruplar[gruplar %in% names(data)]
  olculer <- olculer[olculer %in% names(data)]

  if (!length(gruplar) || !length(olculer)) return(list())

  anahtar <- do.call(paste, c(lapply(gruplar, function(s) as.character(data[[s]])),
                              list(sep = " | ")))
  bolum <- split(seq_len(nrow(data)), anahtar)
  buyukluk <- vapply(bolum, length, integer(1))
  sirali <- names(bolum)[order(buyukluk, decreasing = TRUE)]
  gorunur <- utils::head(sirali, max(1L, suppressWarnings(as.integer(top_n))))

  satirlar <- lapply(gorunur, function(ad) {
    idx <- bolum[[ad]]
    olgular <- lapply(olculer, function(olcu) {
      spec <- .pk_packet_column_spec(meta, olcu)
      pk_measure_facts(
        data[[olcu]][idx], olcu, spec, scope = scope, group_keys = ad,
        aggregate_mode = spec$aggregate %||% "none", additive = spec$additive
      )
    })
    list(group = ad, rows = length(idx), facts = unlist(olgular, recursive = FALSE))
  })

  digerler <- setdiff(sirali, gorunur)
  list(
    group_by = gruplar,
    measures = olculer,
    top = satirlar,
    other_groups = length(digerler),
    other_rows = if (length(digerler)) sum(buyukluk[digerler]) else 0L
  )
}

#' Analiz paketini kur (§5.7)
#'
#' @param data Yetki VE kullanıcı filtresi UYGULANMIŞ veri çerçevesi.
#' @param query Seçilen sorgu tanımı (`meta` alanı Faz 3a sözleşmesindedir).
#' @param context `list(authorized_rows=, filtered_rows=, filters=,
#'   filter_status=, degradations=, pre_aggregated_columns=)`
pk_packet_build <- function(data, query, context = list()) {
  meta <- .pk_packet_meta(query)
  context <- if (is.list(context)) context else list()
  if (!is.data.frame(data)) data <- data.frame()

  yetkili <- context$authorized_rows
  filtreli <- context$filtered_rows %||% nrow(data)
  kapsam <- pk_scope_signature(yetkili, filtreli)

  roller <- .pk_packet_roles(data, meta)
  onceden_toplu <- as.character(context$pre_aggregated_columns %||% character(0))
  olcu_sutunlari <- setdiff(roller$measure, onceden_toplu)

  top_k <- .pk_packet_cfg("MERGEN_PK_TOPK_CATEGORIES", meta, 10L)
  grup_n <- .pk_packet_cfg("MERGEN_PK_GROUP_TOPN", meta, 15L)
  ornek_n <- .pk_packet_cfg("MERGEN_PK_SAMPLE_ROWS", meta, 30L)
  tohum <- .pk_packet_cfg("MERGEN_PK_SAMPLE_SEED", meta, 42L)

  zaman_penceresi <- NULL
  if (length(roller$date)) {
    ilk_tarih <- data[[roller$date[1]]]
    gecerli <- ilk_tarih[!is.na(ilk_tarih)]
    if (length(gecerli)) {
      zaman_penceresi <- list(column = roller$date[1],
                              from = as.character(min(as.Date(gecerli))),
                              to = as.character(max(as.Date(gecerli))))
    }
  }

  olgular <- list()
  sinirliliklar <- character(0)

  for (sutun in olcu_sutunlari) {
    spec <- .pk_packet_column_spec(meta, sutun)
    olgular <- c(olgular, pk_measure_facts(
      data[[sutun]], sutun, spec, scope = kapsam, time_window = zaman_penceresi,
      aggregate_mode = spec$aggregate %||% "none", additive = spec$additive
    ))

    if (identical(spec$aggregate, "latest")) {
      cmeta <- if (is.list(meta$column_meta)) meta$column_meta[[sutun]] else list()
      spec$latest_by <- cmeta$latest_by
      spec$latest_tie_by <- cmeta$latest_tie_by
      olgular <- c(olgular, list(pk_latest_fact(
        data, sutun, spec, scope = kapsam, time_window = zaman_penceresi
      )))
    }

    if (identical(spec$aggregate, "weighted_mean")) {
      agirlik <- spec$weight_by
      if (is.character(agirlik) && length(agirlik) == 1L && agirlik %in% names(data)) {
        olgular <- c(olgular, list(pk_weighted_mean_fact(
          data[[sutun]], data[[agirlik]], sutun, spec, scope = kapsam,
          time_window = zaman_penceresi, weight_column = agirlik
        )))
      } else {
        sinirliliklar <- c(sinirliliklar, sprintf(
          "'%s' agirlikli ortalama istiyor ama agirlik sutunu (%s) sonucta yok; agirlikli ortalama URETILMEDI.",
          sutun, as.character(agirlik %||% "tanimsiz")[1]
        ))
      }
    }
  }

  if (length(onceden_toplu)) {
    sinirliliklar <- c(sinirliliklar, sprintf(
      "Onceden toplulastirilmis sutunlar istatistik disi birakildi: %s.",
      paste(intersect(onceden_toplu, names(data)), collapse = ", ")
    ))
  }

  if (!length(meta$column_meta %||% list())) {
    sinirliliklar <- c(sinirliliklar, paste(
      "Bu sorgu icin anlamsal metadata (Tier-0) yok:",
      "additive dogrulanmadigi icin TOPLAM ve ORTALAMA uretilmedi;",
      "grain bilinmedigi icin mukerrer satir elemesi yapilmadi."
    ))
  }

  birincil_olcu <- {
    toplanabilir <- Filter(function(s) .pk_packet_column_spec(meta, s)$additive, olcu_sutunlari)
    if (length(toplanabilir)) toplanabilir[1] else if (length(olcu_sutunlari)) olcu_sutunlari[1] else NULL
  }
  tabaka <- {
    aday <- as.character(meta$default_group_by %||% character(0))
    aday <- aday[aday %in% names(data)]
    if (length(aday)) aday[1] else if (length(roller$dimension)) roller$dimension[1] else NULL
  }

  list(
    scope = list(
      query_id = query$id %||% NA_character_,
      query_name = query$name %||% NA_character_,
      grain = meta$grain,
      grain_columns = as.character(meta$grain_columns %||% character(0)),
      tier = if (length(meta$column_meta %||% list())) 3L else 0L,
      authorized_rows = yetkili,
      filtered_rows = filtreli,
      scope_signature = kapsam,
      time_window = zaman_penceresi
    ),
    filters = list(
      status = context$filter_status,
      applied = context$filters %||% list(),
      degradations = context$degradations %||% list(),
      user_filter_applied = !is.null(yetkili) && !is.null(filtreli) &&
        as.integer(yetkili) > as.integer(filtreli)
    ),
    coverage = pk_packet_coverage(data, meta),
    facts = olgular,
    categorical = pk_packet_categorical(data, meta, roller$dimension, top_k),
    dates = pk_packet_dates(data, meta, roller$date),
    groups = pk_packet_groups(data, meta, kapsam, grup_n),
    examples = pk_packet_examples(data, meta, birincil_olcu, tabaka, ornek_n, tohum),
    limitations = sinirliliklar,
    roles = roller
  )
}
