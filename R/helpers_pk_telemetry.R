# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry.R
# Açıklama: Telemetri DB katmanı için uyumluluk yüzeyi. Temel fail-soft yazım
#           helpers_pk_telemetry_base.R içinde korunur; bu dosya gözlem anında
#           gerçek filtre yürütme bilgisini, kullanıcı kimliğini ve
#           yapılandırılmış motoru uygular.
# ==============================================================================

# Standart çalışma zamanında temel dosya kaynak manifesti tarafından bu
# dosyadan önce yüklenir. İzole source()/testthat çalıştırmalarında ise mevcut
# çalışma dizinine güvenmeden, bu dosyanın kendi konumundaki kardeş dosya yüklenir.
if (!exists("pk_telemetry_log_analysis", mode = "function", inherits = FALSE)) {
  # 1) Bu dosyayı source eden çerçevedeki ofile üzerinden kardeş dosyayı bul.
  #    testthat yığınında source çerçevesi sys.frame(1) DEĞİLDİR; bu yüzden tüm
  #    çerçeveler içten dışa taranır. Mutlak yolla source edilen izole testler
  #    (getwd() tempdir()) yalnızca bu adayla çözülür.
  .pk_telemetry_sibling <- NULL
  for (.pk_telemetry_i in rev(seq_len(sys.nframe()))) {
    .pk_telemetry_of <- tryCatch(
      get("ofile", envir = sys.frame(.pk_telemetry_i), inherits = FALSE),
      error = function(e) NULL
    )
    if (is.character(.pk_telemetry_of) && length(.pk_telemetry_of) == 1L &&
        !is.na(.pk_telemetry_of) && nzchar(.pk_telemetry_of)) {
      .pk_telemetry_try <- file.path(
        dirname(normalizePath(.pk_telemetry_of, winslash = "/", mustWork = FALSE)),
        "helpers_pk_telemetry_base.R"
      )
      if (isTRUE(tryCatch(file.exists(.pk_telemetry_try), error = function(e) FALSE))) {
        .pk_telemetry_sibling <- .pk_telemetry_try
        break
      }
    }
  }

  # 2) Çalışma dizininden bağımsız aday yollar: repo kökü, tests/testthat, MERGEN_REPO_ROOT.
  .pk_telemetry_base_candidates <- c(
    .pk_telemetry_sibling,
    file.path("R", "helpers_pk_telemetry_base.R"),
    file.path("..", "..", "R", "helpers_pk_telemetry_base.R"),
    file.path("..", "R", "helpers_pk_telemetry_base.R"),
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", "helpers_pk_telemetry_base.R")
    } else {
      NULL
    }
  )

  .pk_telemetry_base_path <- NULL
  for (.pk_telemetry_cand in .pk_telemetry_base_candidates) {
    if (!is.null(.pk_telemetry_cand) && nzchar(.pk_telemetry_cand) &&
        isTRUE(tryCatch(file.exists(.pk_telemetry_cand), error = function(e) FALSE))) {
      .pk_telemetry_base_path <- .pk_telemetry_cand
      break
    }
  }

  if (is.null(.pk_telemetry_base_path)) {
    stop("helpers_pk_telemetry_base.R bulunamadı.", call. = FALSE)
  }

  source(.pk_telemetry_base_path, encoding = "UTF-8", local = environment())

  # Source-time geçici değişkenler yalnızca var olduklarında silinir (warning-free).
  for (.pk_telemetry_tmp in c(".pk_telemetry_sibling", ".pk_telemetry_i",
                              ".pk_telemetry_of", ".pk_telemetry_try",
                              ".pk_telemetry_base_candidates",
                              ".pk_telemetry_base_path", ".pk_telemetry_cand")) {
    if (exists(.pk_telemetry_tmp, inherits = FALSE)) rm(list = .pk_telemetry_tmp)
  }
  rm(.pk_telemetry_tmp)
}

.pk_observation_query_meta <- function(info, filter_observation = NULL) {
  if (is.list(info$query_meta)) return(info$query_meta)
  if (is.list(filter_observation$query_meta)) return(filter_observation$query_meta)
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

.pk_observation_session_user_id <- function(session) {
  value <- tryCatch(session$userData$user_id, error = function(e) NULL)
  if (is.null(value) || length(value) == 0L) return(NULL)

  value <- suppressWarnings(as.integer(value)[1])
  if (is.na(value)) NULL else value
}

#' Bir analiz isteğini gözlemle: alt bilgiyi hazırla + telemetriyi yaz
#'
#' Bu bağdaştırıcı şu doğruluk garantilerini verir:
#'   1. toplulaştırılmış çıktı satırı yerine toplulaştırma öncesi eşleşen kayıt
#'      sayısını kullanır;
#'   2. yalnızca gerçekten uygulanan filtreleri gösterir ve düşürülenleri açıkça
#'      kullanıcıya/telemetriye bildirir;
#'   3. çağıran unutsa bile oturumdaki kimlik doğrulanmış user_id değerini
#'      KullaniciID alanına taşır;
#'   4. motor etiketi sorgu metadata -> ortam -> option -> varsayılan önceliğiyle
#'      çözülür.
pk_analysis_observe <- function(session, conn, info) {
  tryCatch({
    info <- if (is.list(info)) info else list()

    if (is.null(info$user_id) || length(info$user_id) == 0L ||
        is.na(suppressWarnings(as.integer(info$user_id)[1]))) {
      info$user_id <- .pk_observation_session_user_id(session)
    }

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

      if (length(info$filters %||% list()) > 0L &&
          identical(info$filter_status, "ok_no_filter")) {
        info$filter_status <- "ok_filtered"
      }

      if (length(info$filters %||% list()) == 0L &&
          length(filter_observation$dropped_filters %||% list()) > 0L &&
          identical(info$filter_status, "ok_filtered")) {
        info$filter_status <- "malformed"
      }
    }

    query_meta <- .pk_observation_query_meta(info, filter_observation)
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
