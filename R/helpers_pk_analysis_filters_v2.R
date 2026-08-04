# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters_v2.R
# Açıklama: Proje ve Kaynak Analizi v2 filtre yürütücüsü.
#
#           Derleyici (helpers_pk_filter_compile.R) ve politika
#           (helpers_pk_filter_policy.R) saf katmanlardır; bu dosya ikisini
#           birleştirip v1 ile AYNI dönüş şeklini üretir. Böylece modül tarafı
#           tek bir `apply_smart_filters()` sözleşmesiyle çalışmaya devam eder.
#
#           v1'den ayrılan noktalar (tümü MERGEN_PK_ENGINE=v2 arkasında):
#             * D5 — `filter_expression` ASLA değerlendirilmez; `eval(parse())`
#                    yolu yoktur. Alan gelirse tipli bir düşürme kaydı üretilir.
#             * D12 — ölü "genel soru" muhafızı yoktur.
#             * D1/D2/D3 — derleyici üzerinden.
#             * D4 — politika üzerinden; karar öznitelik olarak taşınır.
# ==============================================================================

# Politika kararı ve köken bilgisi çağırana ÖZNİTELİK ile taşınır; dönüş tipi
# (data.frame) v1 ile birebir aynı kalır.
PK_FILTER_V2_ATTR <- "pk_filter_v2"

#' v2 filtre yürütmesi
#'
#' @return v1 ile aynı şekilde bir data.frame; `attr(x, PK_FILTER_V2_ATTR)`
#'   politika kararını, ifşaları ve köken kayıtlarını taşır.
pk_apply_smart_filters_v2 <- function(data, filter_instructions, query = NULL) {
  filter_instructions <- if (is.list(filter_instructions)) filter_instructions else list()

  filters <- filter_instructions$filters %||% list()
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column

  sonuc_ekle <- function(df, matched_rows, karar) {
    attr(df, PK_FILTER_V2_ATTR) <- karar
    df
  }

  bos_karar <- list(
    action = "proceed", refusal_message = NULL, disclosures = character(0),
    dropped = list(), noop_columns = character(0), applied = list(),
    matched_rows = 0L, primary_column = NULL
  )

  if (nrow(data) == 0L) {
    return(sonuc_ekle(data.frame(), 0L, bos_karar))
  }

  # D5: filter_expression bilerek YOK SAYILIR. v1'de bu alan
  # `subset(dt, eval(parse(text = expr_str)))` ile çalıştırılıyordu; ifade
  # metni LLM üretimi olduğundan bu, prompt enjeksiyonuyla erişilebilen
  # RCE biçimli bir yoldu.
  ifade_dusurmesi <- list()
  ifade <- filter_instructions$filter_expression
  if (!is.null(ifade) && nzchar(as.character(ifade)[1])) {
    ifade_dusurmesi <- list(list(
      leaf = list(column = "filter_expression", values = character(0)),
      reason = "çalıştırılabilir ifade v2 motorunda kabul edilmez"
    ))
    cat("[SMART_FILTER_V2] filter_expression yok sayildi (D5: eval(parse) kaldirildi).\n")
  }

  derleme <- pk_filter_compile(data, filters)
  politika <- pk_filter_zero_match_policy(data, filters, derleme, query)

  # Sıfır eşleşme nedeniyle DÜŞÜRÜLEN ikincil sütunlar da köken kaydına girer;
  # böylece Faz 0'ın gözlem hattı bunları kullanıcıya görünen alt bilgide
  # "düşürülen filtre" uyarısı olarak yayımlar.
  sifir_dusurmeleri <- list()
  if (identical(politika$action, "dropped_secondary")) {
    sifir_dusurmeleri <- lapply(politika$dropped_columns, function(sutun) {
      list(
        leaf = list(column = sutun, values = character(0)),
        reason = "hiçbir kayıtla eşleşmediği için uygulanmadı"
      )
    })
  }

  dusenler <- c(derleme$dropped, ifade_dusurmesi, sifir_dusurmeleri)

  karar <- list(
    action = politika$action,
    refusal_message = politika$refusal_message,
    disclosures = politika$disclosures,
    dropped = dusenler,
    dropped_columns = politika$dropped_columns,
    noop_columns = derleme$noop_columns,
    primary_column = politika$primary_column,
    applied = unlist(lapply(derleme$groups, function(g) g$applied), recursive = FALSE) %||% list(),
    groups = derleme$groups
  )

  if (identical(politika$action, "refuse")) {
    karar$matched_rows <- 0L
    return(sonuc_ekle(data[0, , drop = FALSE], 0L, karar))
  }

  maske <- politika$mask
  if (is.null(maske)) maske <- rep(TRUE, nrow(data))
  filtrelenmis <- data[maske, , drop = FALSE]
  eslesen <- nrow(filtrelenmis)
  karar$matched_rows <- eslesen

  cat(sprintf(
    "[SMART_FILTER_V2] Filtre grubu: %d | eslesen satir: %d / %d\n",
    length(derleme$groups), eslesen, nrow(data)
  ))

  if (!is.null(aggregation)) {
    agg <- tolower(as.character(aggregation)[1])

    if (identical(agg, "count")) {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(sonuc_ekle(
        data.frame(Sonuc = aciklama, Adet = eslesen, stringsAsFactors = FALSE),
        eslesen, karar
      ))
    }

    if (identical(agg, "sum")) {
      sayisal <- names(filtrelenmis)[vapply(filtrelenmis, is.numeric, logical(1))]
      if (length(sayisal) > 0) {
        toplamlar <- lapply(sayisal, function(nc) sum(filtrelenmis[[nc]], na.rm = TRUE))
        names(toplamlar) <- sayisal
        return(sonuc_ekle(as.data.frame(toplamlar, stringsAsFactors = FALSE), eslesen, karar))
      }
    }

    if (identical(agg, "group_by") && !is.null(group_col) && group_col %in% names(filtrelenmis)) {
      dt <- data.table::as.data.table(filtrelenmis)
      return(sonuc_ekle(as.data.frame(dt[, .N, by = group_col]), eslesen, karar))
    }
  }

  sonuc_ekle(as.data.frame(filtrelenmis), eslesen, karar)
}
