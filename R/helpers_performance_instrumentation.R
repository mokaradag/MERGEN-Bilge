# ==============================================================================
# Dosya Yolu: R/helpers_performance_instrumentation.R
# Açıklama: Hafif, sır-redakteli performans ölçüm yardımcıları.
# ==============================================================================

mergen_perf_enabled <- function() {
  value <- Sys.getenv("MERGEN_PERF_LOG", unset = "")
  if (!nzchar(value)) {
    return(isTRUE(getOption("mergen.perf_log", FALSE)))
  }

  tolower(trimws(value)) %in% c("1", "true", "t", "yes", "y", "on")
}

mergen_perf_now <- function() {
  proc.time()[["elapsed"]]
}

mergen_perf_elapsed_ms <- function(start) {
  elapsed <- (mergen_perf_now() - as.numeric(start)[1]) * 1000
  if (!is.finite(elapsed) || elapsed < 0) elapsed <- NA_real_
  round(elapsed, 1)
}

mergen_perf_safe_field <- function(x, max_chars = 80L) {
  if (is.null(x) || length(x) == 0L) return("")
  value <- as.character(x)[1]
  if (is.na(value)) return("")
  value <- gsub("[\r\n\t]+", " ", value, perl = TRUE)
  value <- substr(value, 1L, max_chars)
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    value <- redact_sensitive_text(value)
  }
  value
}

mergen_perf_log <- function(event, start = NULL, fields = list(), level = "info") {
  if (!mergen_perf_enabled()) return(invisible(NULL))

  elapsed_part <- ""
  if (!is.null(start)) {
    elapsed_part <- sprintf(" elapsed_ms=%s", as.character(mergen_perf_elapsed_ms(start)))
  }

  field_part <- ""
  if (length(fields) > 0L) {
    keys <- names(fields)
    if (is.null(keys)) keys <- rep("field", length(fields))
    safe_pairs <- vapply(seq_along(fields), function(i) {
      key <- gsub("[^A-Za-z0-9_.-]", "_", as.character(keys[[i]]))
      sprintf("%s=%s", key, mergen_perf_safe_field(fields[[i]]))
    }, character(1))
    field_part <- paste0(" ", paste(safe_pairs, collapse = " "))
  }

  msg <- sprintf(
    "[PERF] event=%s%s%s",
    mergen_perf_safe_field(event, max_chars = 60L),
    elapsed_part,
    field_part
  )

  log_fun <- if (identical(level, "warn")) log_warn else log_info
  try(log_fun(msg), silent = TRUE)
  invisible(NULL)
}

mergen_perf_time <- function(event, expr, fields = list(), level = "info") {
  start <- mergen_perf_now()
  ok <- FALSE
  on.exit({
    extra <- fields
    extra$success <- ok
    mergen_perf_log(event, start = start, fields = extra, level = level)
  }, add = TRUE)

  value <- force(expr)
  ok <- TRUE
  value
}

# LLM istek tam dökümünün açık olup olmadığını belirler. Varsayılan KAPALI.
# MERGEN_LLM_REQUEST_DEBUG (1/true/on...) veya genel MERGEN_DEBUG açıkken tam
# döküm üretilir; aksi halde yalnızca hafif sayım/boyut özeti yazılır.
mergen_llm_request_debug_enabled <- function() {
  flag <- Sys.getenv("MERGEN_LLM_REQUEST_DEBUG", unset = "")
  if (nzchar(flag)) {
    return(tolower(trimws(flag)) %in% c("1", "true", "t", "yes", "y", "on"))
  }
  isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))
}

# LLM isteği tanılama logu: KRİTİK YOL dostu. İlk-token gecikmesini düşürmek için
# varsayılan davranış yalnızca hafif sayım/boyut özeti yazar (tam istem/ayar
# gövdesini diske SERİLEŞTİRMEZ). Tam döküm yalnızca açık tanılama bayrağıyla
# (MERGEN_LLM_REQUEST_DEBUG / MERGEN_DEBUG) üretilir; o durumda da Shiny oturumu
# çıkarılır ve dbg_dump içindeki sır redaksiyonu korunur. Sır/istem gövdesi
# varsayılan olarak loglanmaz.
mergen_log_llm_request_debug <- function(label, model, messages = list(), settings = list()) {
  msg_list <- if (is.list(messages)) messages else list()
  msg_count <- length(msg_list)

  total_chars <- tryCatch(
    sum(vapply(msg_list, function(m) {
      nchar(as.character(m$content %||% "")[1] %||% "")
    }, numeric(1)), na.rm = TRUE),
    error = function(e) NA_real_
  )

  max_tokens <- tryCatch(
    as.numeric(settings$max_output_tokens %||% NA_real_)[1],
    error = function(e) NA_real_
  )

  # Hafif özet: sır yok, tam gövde yok. Kritik yolu yavaşlatmaz.
  try(log_info(sprintf(
    "[CHAT PERF] LLM istek ozeti - etiket=%s model=%s mesaj=%d toplam_karakter=%s max_token=%s",
    as.character(label %||% "")[1],
    as.character(model %||% "")[1],
    msg_count,
    if (is.finite(total_chars)) as.character(total_chars) else "NA",
    if (is.finite(max_tokens)) as.character(max_tokens) else "NA"
  )), silent = TRUE)

  # Tam döküm yalnızca açık tanılama bayrağıyla ve sır-redakteli (dbg_dump).
  if (mergen_llm_request_debug_enabled() &&
      exists("dbg_dump", mode = "function", inherits = TRUE)) {
    safe_settings <- if (is.list(settings)) settings else list()
    safe_settings$shiny_session <- NULL
    try(dbg_dump(label, list(model = model, messages = msg_list, settings = safe_settings)), silent = TRUE)
  }

  invisible(NULL)
}

# Tek satırlık birleşik sohbet performans özeti. İstek başına bir satır;
# kullanıcının algıladığı ilk-token metriklerini (akıl yürütme/yanıt/UI) ve
# toplam süreyi tek yerde toplar. Sır içermez; istem gövdesi yazmaz. Eksik/NA
# metrikler "NA" olarak yazılır.
mergen_log_chat_perf_summary <- function(request_id,
                                         model,
                                         path,
                                         first_reasoning_ms = NA_real_,
                                         first_answer_ms = NA_real_,
                                         first_ui_ms = NA_real_,
                                         total_ms = NA_real_) {
  num_field <- function(value) {
    num <- suppressWarnings(as.numeric(value %||% NA_real_)[1])
    if (is.null(num) || length(num) == 0L || !is.finite(num)) "NA" else sprintf("%.0f", num)
  }

  try(log_info(sprintf(
    "[CHAT PERF SUMMARY] req=%s model=%s path=%s first_reasoning_ms=%s first_answer_ms=%s first_ui_ms=%s total_ms=%s",
    as.character(request_id %||% "")[1],
    as.character(model %||% "")[1],
    as.character(path %||% "")[1],
    num_field(first_reasoning_ms),
    num_field(first_answer_ms),
    num_field(first_ui_ms),
    num_field(total_ms)
  )), silent = TRUE)

  invisible(NULL)
}
