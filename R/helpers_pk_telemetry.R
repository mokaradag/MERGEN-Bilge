# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry.R
# Açıklama: Telemetri DB katmanı için uyumluluk yüzeyi. Temel fail-soft yazım
#           helpers_pk_telemetry_base.R içinde korunur; bu dosya gözlem anında
#           gerçek filtre yürütme bilgisini ve yapılandırılmış motoru uygular.
# ==============================================================================

.pk_telemetry_base_path <- file.path("R", "helpers_pk_telemetry_base.R")
if (!file.exists(.pk_telemetry_base_path)) {
  stop(sprintf("%s bulunamadı.", .pk_telemetry_base_path), call. = FALSE)
}
source(.pk_telemetry_base_path, encoding = "UTF-8", local = environment())
rm(.pk_telemetry_base_path)

.pk_observation_query_meta <- function(info) {
  if (is.list(info$query_meta)) return(info$query_meta)
  if (!exists("query_library", inherits = TRUE)) return(NULL)

  library <- get("query_library", inherits = TRUE)
  if (!is.list(library) || length(library) == 0L) return(NULL)

  query_id <- as.character(info$query_id %||% "")[1]
  query_name <- as.character(info$query_name %||% "")[1]

  for (candidate in library) {
    if (!is.list(candidate)) next

    candidate_id <- as.character(candidate$id %||% "")[1]
    candidate_name <- as.character(candidate$name %||% "")[1]

    if ((nzchar(query_id) && identical(candidate_id, query_id)) ||
        (nzchar(query_name) && identical(candidate_name, query_name))) {
      return(candidate)
    }
  }

  NULL
}

.pk_dropped_filter_degradations <- function(dropped_filters) {
  if (!is.list(dropped_filters) || length(dropped_filters) == 0L) return(list())

  details <- vapply(dropped_filters, function(item) {
    filter <- item$filter %||% list()
    column <- as.character(filter$column %||% "?")[1]
    value <- paste(as.character(filter$value %||% ""), collapse = ", ")
    reason <- as.character(item$reason %||% "uygulanamadı")[1]
    sprintf("%s=\"%s\" (%s)", column, value, reason)
  }, character(1))

  list(list(
    code = "filter_dropped",
    message = paste0(
      "Bazı filtreler veri kümesine uygulanamadı ve analizden çıkarıldı: ",
      paste(details, collapse = " · "),
      "."
    )
  ))
}

#' Bir analiz isteğini gözlemle: alt bilgiyi hazırla + telemetriyi yaz
#'
#' Bu bağdaştırıcı iki doğruluk garantisi ekler:
#'   1. toplulaştırılmış çıktı satırı yerine toplulaştırma öncesi eşleşen kayıt
#'      sayısını kullanır;
#'   2. yalnızca gerçekten uygulanan filtreleri gösterir ve düşürülenleri açıkça
#'      kullanıcıya/telemetriye bildirir.
#' Ayrıca motor etiketi sabit koddan değil, sorgu metadata -> ortam -> option ->
#' varsayılan önceliğiyle çözülür.
pk_analysis_observe <- function(session, conn, info) {
  tryCatch({
    info <- if (is.list(info)) info else list()

    filter_observation <- if (exists("pk_filter_observation_take", mode = "function", inherits = TRUE)) {
      tryCatch(pk_filter_observation_take(info), error = function(e) NULL)
    } else {
      NULL
    }

    dropped_degradations <- list()
    if (is.list(filter_observation)) {
      info$filtered_rows <- filter_observation$matched_rows %||% info$filtered_rows
      info$filters <- filter_observation$applied_filters %||% list()
      dropped_degradations <- .pk_dropped_filter_degradations(
        filter_observation$dropped_filters %||% list()
      )

      if (length(info$filters %||% list()) == 0L &&
          length(filter_observation$dropped_filters %||% list()) > 0L &&
          identical(info$filter_status, "ok_filtered")) {
        info$filter_status <- "malformed"
      }
    }

    query_meta <- .pk_observation_query_meta(info)
    info$engine <- tryCatch(
      pk_config_resolve("MERGEN_PK_ENGINE", query_meta = query_meta),
      error = function(e) "v1"
    )

    status <- pk_filter_status_normalize(info$filter_status)
    degradations <- c(
      pk_degradations_from_filter_status(status),
      dropped_degradations
    )

    footer <- pk_build_provenance_footer(list(
      query_id        = info$query_id,
      query_name      = info$query_name,
      filter_status   = status,
      filters         = info$filters %||% list(),
      authorized_rows = info$authorized_rows,
      filtered_rows   = info$filtered_rows,
      degradations    = degradations
    ))

    if (nzchar(footer)) {
      pk_provenance_stash(session, footer, request_id = info$request_id)
    }

    info$filter_status <- status
    info$filter_count <- length(info$filters %||% list())
    info$degradation_codes <- vapply(
      degradations,
      function(d) as.character(d$code)[1],
      character(1)
    )

    pk_telemetry_log_analysis(info, conn)

    invisible(footer)
  }, error = function(e) invisible(""))
}
