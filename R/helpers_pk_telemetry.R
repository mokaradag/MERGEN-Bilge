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

# Gözlem zenginleştirme: filtre gözlemi, motor etiketi, durum ve bozulmalar.
# FAIL-SOFT'tur; hata verirse çağıran yine de yanıtı teslim eder.
.pk_observation_enrich <- function(session, info) {
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

    # Tüm filtreler düşürüldüyse sonuç bozulmuştur. "ok_no_filter" da buraya
    # dâhildir: yalnızca filter_expression dönen ve değerlendirmesi başarısız
    # olan istekte alt bilgi aksi halde hem "soru genel olarak yorumlandı" der
    # hem de düşürülen filtre uyarısı gösterirdi; FiltreDurumu ise meşru bir
    # filtresiz sonuç gibi yazılırdı. timeout/error/stopped/not_reached/disabled
    # daha özgül bilgidir ve ezilmez.
    if (length(info$filters %||% list()) == 0L &&
        length(filter_observation$dropped_filters %||% list()) > 0L &&
        isTRUE(info$filter_status %in% c("ok_filtered", "ok_no_filter"))) {
      info$filter_status <- "malformed"
    }
  }

  query_meta <- .pk_observation_query_meta(info, filter_observation)
  # Çağıran motoru açıkça bildirdiyse (modül `pk_engine_v2` değerini çözmüştür)
  # o değer korunur; aksi hâlde yapılandırmadan çözülür.
  if (!is.character(info$engine) || !nzchar(as.character(info$engine)[1]) ||
      identical(as.character(info$engine)[1], "v1")) {
    cozulen <- tryCatch(
      pk_config_resolve("MERGEN_PK_ENGINE", query_meta = query_meta),
      error = function(e) NULL
    )
    if (is.character(cozulen) && nzchar(cozulen[1]) &&
        !identical(as.character(info$engine %||% "")[1], "v2")) {
      info$engine <- cozulen[1]
    }
  }

  status <- pk_filter_status_normalize(info$filter_status)
  list(
    info = info,
    status = status,
    degradations = c(pk_degradations_from_filter_status(status), dropped_degradations),
    provenance_mode = tryCatch(pk_numeric_provenance_mode(query_meta), error = function(e) NULL)
  )
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
#'   4. motor etiketi çağıranın çözdüğü değer -> sorgu metadata -> ortam ->
#'      option -> varsayılan önceliğiyle çözülür.
#'
#' ZORUNLU TESLİM ile FAIL-SOFT TELEMETRİ AYRIDIR: eskiden tek bir dış
#' `tryCatch` filtre gözlemini, alt bilgi kurulumunu, saklamayı ve telemetriyi
#' birlikte sarıyordu; saklamadan ÖNCEKİ herhangi bir hata boş dize döndürüyor
#' ve istek devam ederken R'ye ait tablo/ek eklenmiyor, sayısal köken hiç
#' uygulanmıyor, `[fact:...]` işaretleri ham düzyazıda kalabiliyordu.
pk_analysis_observe <- function(session, conn, info) {
  info <- if (is.list(info)) info else list()

  zengin <- tryCatch(.pk_observation_enrich(session, info), error = function(e) NULL)
  if (!is.list(zengin)) {
    zengin <- list(info = info,
                   status = tryCatch(pk_filter_status_normalize(info$filter_status),
                                     error = function(e) info$filter_status),
                   degradations = list(), provenance_mode = NULL)
  }
  info <- zengin$info
  status <- zengin$status

  blok <- as.character(info$answer_block %||% "")[1]
  if (is.na(blok)) blok <- ""

  footer <- tryCatch(pk_build_provenance_footer(list(
    query_id        = info$query_id,
    query_name      = info$query_name,
    filter_status   = status,
    filters         = info$filters %||% list(),
    authorized_rows = info$authorized_rows,
    filtered_rows   = info$filtered_rows,
    degradations    = zengin$degradations,
    # Ek KARTI zaten R'ye ait blokta yer alıyorsa alt bilgiye TEKRAR yazılmaz;
    # aksi hâlde her ek-kipli v2 yanıtında aynı indirme/ret iki kez görünürdü.
    attachment      = if (nzchar(blok)) NULL else info$attachment
  )), error = function(e) "")

  if (!is.character(footer) || length(footer) != 1L || is.na(footer)) footer <- ""

  # Faz 2: R'ye ait yanıt bloğu (tablo/önizleme + ek kartı) alt bilginin
  # ÖNÜNE eklenir; olgular ve deterministik yedek metin ise §5.11 sayısal
  # köken doğrulaması için birlikte saklanır. Alt bilgi kurulamasa BİLE blok
  # teslim edilir.
  if (nzchar(footer) || nzchar(blok)) {
    try(pk_provenance_stash(
      session, paste0(blok, footer),
      request_id = info$request_id,
      facts = info$facts,
      fallback_text = info$fallback_text,
      query_id = info$query_id,
      mode = zengin$provenance_mode
    ), silent = TRUE)
  }

  info$filter_status <- status
  info$filter_count <- length(info$filters %||% list())
  info$degradation_codes <- vapply(
    zengin$degradations,
    function(d) as.character(d$code)[1],
    character(1)
  )

  try(pk_telemetry_log_analysis(info, conn), silent = TRUE)

  invisible(footer)
}
