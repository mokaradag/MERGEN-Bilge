# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters.R
# Açıklama: AI filtre motoru için uyumluluk yüzeyi ve Faz 0 gözlem bağdaştırıcısı.
#           Karar veren v1 motoru helpers_pk_analysis_filters_base.R içinde
#           korunur. Bu dosya, filtre yürütmesini TEK GEÇİŞTE gözlemler; aynı R
#           ifadesini telemetri amacıyla ikinci kez değerlendirmez.
# ==============================================================================

# Standart çalışma zamanında temel dosya kaynak manifesti tarafından bu dosyadan
# önce yüklenir ve bu blok hiç çalışmaz. İzole source()/testthat çalıştırmalarında
# ise çalışma dizininden bağımsız aday yollar sırayla denenir: repo kökü,
# tests/testthat ve MERGEN_REPO_ROOT. sys.frame(1)$ofile tek başına yeterli
# değildir; testthat çağrı yığınının derininde ofile taşımayan bir çerçeve olur.
if (!exists("extract_filter_criteria_from_prompt", mode = "function", inherits = FALSE)) {
  # 1) Bu dosyayı source eden çerçevedeki ofile üzerinden kardeş dosyayı bul.
  #    testthat yığınında source çerçevesi sys.frame(1) DEĞİLDİR; bu yüzden tüm
  #    çerçeveler içten dışa taranır. Mutlak yolla source edilen izole testler
  #    (getwd() tempdir()) yalnızca bu adayla çözülür.
  .pk_filter_sibling <- NULL
  for (.pk_filter_i in rev(seq_len(sys.nframe()))) {
    .pk_filter_of <- tryCatch(
      get("ofile", envir = sys.frame(.pk_filter_i), inherits = FALSE),
      error = function(e) NULL
    )
    if (is.character(.pk_filter_of) && length(.pk_filter_of) == 1L &&
        !is.na(.pk_filter_of) && nzchar(.pk_filter_of)) {
      .pk_filter_try <- file.path(
        dirname(normalizePath(.pk_filter_of, winslash = "/", mustWork = FALSE)),
        "helpers_pk_analysis_filters_base.R"
      )
      if (isTRUE(tryCatch(file.exists(.pk_filter_try), error = function(e) FALSE))) {
        .pk_filter_sibling <- .pk_filter_try
        break
      }
    }
  }

  # 2) Çalışma dizininden bağımsız aday yollar: repo kökü, tests/testthat, MERGEN_REPO_ROOT.
  .pk_filter_base_candidates <- c(
    .pk_filter_sibling,
    file.path("R", "helpers_pk_analysis_filters_base.R"),
    file.path("..", "..", "R", "helpers_pk_analysis_filters_base.R"),
    file.path("..", "R", "helpers_pk_analysis_filters_base.R"),
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", "helpers_pk_analysis_filters_base.R")
    } else {
      NULL
    }
  )

  .pk_filter_base_path <- NULL
  for (.pk_filter_cand in .pk_filter_base_candidates) {
    if (!is.null(.pk_filter_cand) && nzchar(.pk_filter_cand) &&
        isTRUE(tryCatch(file.exists(.pk_filter_cand), error = function(e) FALSE))) {
      .pk_filter_base_path <- .pk_filter_cand
      break
    }
  }

  if (is.null(.pk_filter_base_path)) {
    stop("helpers_pk_analysis_filters_base.R bulunamadı.", call. = FALSE)
  }

  source(.pk_filter_base_path, encoding = "UTF-8", local = environment())

  # Source-time geçici değişkenler yalnızca var olduklarında silinir (warning-free).
  for (.pk_filter_tmp in c(".pk_filter_sibling", ".pk_filter_i", ".pk_filter_of",
                           ".pk_filter_try", ".pk_filter_base_candidates",
                           ".pk_filter_base_path", ".pk_filter_cand")) {
    if (exists(.pk_filter_tmp, inherits = FALSE)) rm(list = .pk_filter_tmp)
  }
  rm(.pk_filter_tmp)
}

if (!exists(".pk_filter_observation_state", inherits = FALSE) ||
    !is.environment(.pk_filter_observation_state)) {
  .pk_filter_observation_state <- new.env(parent = emptyenv())
}

.pk_filter_observation_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  out <- as.character(x)[1]
  if (is.na(out)) "" else out
}

.pk_filter_observation_key <- function(request_id, query_id, query_name, question) {
  paste(
    .pk_filter_observation_scalar(request_id),
    .pk_filter_observation_scalar(query_id),
    .pk_filter_observation_scalar(query_name),
    .pk_filter_observation_scalar(question),
    sep = "\u001f"
  )
}

.pk_filter_observation_context <- function(user_prompt) {
  request_id <- NULL
  query_meta <- NULL
  session_obj <- NULL

  for (fr in rev(sys.frames())) {
    if (is.null(request_id) && exists("pk_request_id", envir = fr, inherits = FALSE)) {
      request_id <- get("pk_request_id", envir = fr, inherits = FALSE)
    }

    if (is.null(query_meta)) {
      for (nm in c("selected_query", "query")) {
        if (exists(nm, envir = fr, inherits = FALSE)) {
          candidate <- get(nm, envir = fr, inherits = FALSE)
          if (is.list(candidate)) {
            query_meta <- candidate
            break
          }
        }
      }
    }

    if (is.null(session_obj) && exists("session", envir = fr, inherits = FALSE)) {
      candidate_session <- get("session", envir = fr, inherits = FALSE)
      if (!is.null(candidate_session)) session_obj <- candidate_session
    }
  }

  if ((is.null(request_id) || !nzchar(.pk_filter_observation_scalar(request_id))) &&
      !is.null(session_obj) &&
      exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    request_id <- tryCatch(
      pk_provenance_current_request_id(session_obj),
      error = function(e) NULL
    )
  }

  list(
    request_id = request_id,
    query_id = query_meta$id %||% NULL,
    query_name = query_meta$name %||% NULL,
    query_meta = query_meta,
    question = user_prompt
  )
}

.pk_filter_dropped <- function(filter, reason) {
  list(filter = filter %||% list(), reason = as.character(reason)[1])
}

.pk_filter_observation_store <- function(context, observation) {
  key <- .pk_filter_observation_key(
    context$request_id,
    context$query_id,
    context$query_name,
    context$question
  )
  observation$query_meta <- context$query_meta
  assign(key, observation, envir = .pk_filter_observation_state)
  invisible(observation)
}

pk_filter_observation_take <- function(info) {
  info <- if (is.list(info)) info else list()
  key <- .pk_filter_observation_key(
    info$request_id,
    info$query_id,
    info$query_name,
    info$question
  )

  if (!exists(key, envir = .pk_filter_observation_state, inherits = FALSE)) return(NULL)

  observation <- get(key, envir = .pk_filter_observation_state, inherits = FALSE)
  rm(list = key, envir = .pk_filter_observation_state)
  observation
}

#' Filtreleri uygula ve aynı yürütme sırasında gözlem bilgisini kaydet
#'
#' Kritik sözleşme: filter_expression yalnızca bir kez değerlendirilir. Uygulanan
#' filtreler, düşürülen filtreler ve toplulaştırma öncesi eşleşen satır sayısı,
#' gerçek motor geçişinden alınır; telemetri için kod yeniden çalıştırılmaz.
apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Baslangic satir: %d\n", nrow(data)))

  context <- .pk_filter_observation_context(user_prompt)
  applied <- list()
  dropped <- list()

  finish <- function(result, matched_rows) {
    try(
      .pk_filter_observation_store(context, list(
        matched_rows = as.integer(matched_rows),
        applied_filters = applied,
        dropped_filters = dropped
      )),
      silent = TRUE
    )
    result
  }

  if (nrow(data) == 0) return(finish(data.frame(), 0L))

  dt <- data.table::as.data.table(data)

  filters <- filter_instructions$filters
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column

  genel_soru_kaliplari <- c(
    "kaç", "toplam", "sayı", "adet", "hangi", "dağılım", "özet",
    "analiz", "liste", "göster", "tüm", "hepsi", "en fazla",
    "en az", "ortalama", "maksimum", "minimum"
  )

  prompt_lower <- tolower(user_prompt)
  genel_soru_mu <- any(sapply(genel_soru_kaliplari, function(pattern) {
    grepl(pattern, prompt_lower, fixed = TRUE)
  }))

  spesifik_varlik_var <- grepl("\\b[A-Z][0-9]{3,}\\b|\\b[A-Z]{1,3}[0-9]{1,}\\b", user_prompt, perl = TRUE) ||
    grepl("[A-ZÜĞIŞÖÇ][a-züğışöç]+ [A-ZÜĞIŞÖÇ][a-züğışöç]+", user_prompt, perl = TRUE)

  if (genel_soru_mu && !spesifik_varlik_var && (is.null(filters) || length(filters) == 0)) {
    cat("[SMART_FILTER] GENEL SORU tespit edildi, filtre UYGULANMAYACAK.\n")
    filters <- list()
  }

  cat(sprintf(
    "[SMART_FILTER] Filtre sayisi: %d (Genel soru: %s, Spesifik varlik: %s)\n",
    length(filters %||% list()),
    genel_soru_mu,
    spesifik_varlik_var
  ))

  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d\n", length(filters %||% list())))
  if (length(filters) > 0) {
    for (i in seq_along(filters)) {
      f <- filters[[i]]
      cat(sprintf(
        "[SMART_FILTER] Filtre #%d: sutun='%s', deger='%s', islem='%s'\n",
        i,
        f$column %||% "NULL",
        f$value %||% "NULL",
        f$operation %||% "NULL"
      ))
    }
  }

  applied_expression_success <- FALSE

  if (!is.null(filter_instructions$filter_expression) &&
      nzchar(as.character(filter_instructions$filter_expression)[1])) {
    expr_str <- as.character(filter_instructions$filter_expression)[1]
    cat(sprintf("[SMART_FILTER] Kompleks İfade Tespit Edildi: %s\n", expr_str))

    tryCatch({
      # Bu ifade gerçek motor geçişidir ve yalnızca burada değerlendirilir.
      dt <- subset(dt, eval(parse(text = expr_str)))
      cat(sprintf("[SMART_FILTER] İfade başarıyla uygulandı. Kalan satır: %d\n", nrow(dt)))
      applied_expression_success <- TRUE
      applied <- list(list(
        column = "filter_expression",
        value = expr_str,
        operation = "expression"
      ))
    }, error = function(e) {
      cat(sprintf("[SMART_FILTER] HATA: İfade uygulanamadı (%s). Standart filtre listesine (AND) dönülüyor.\n", e$message))
      dropped[[length(dropped) + 1L]] <<- .pk_filter_dropped(
        list(column = "filter_expression", value = expr_str, operation = "expression"),
        paste0("ifade uygulanamadı: ", conditionMessage(e))
      )
      applied_expression_success <<- FALSE
    })
  }

  if (!applied_expression_success) {
    if (!is.null(filters) && length(filters) > 0) {
      cat("[SMART_FILTER] Standart filtre listesi uygulanıyor (AND mantığı)...\n")

      for (f in filters) {
        col <- .pk_filter_observation_scalar(f$column)
        val <- f$value
        op <- .pk_filter_observation_scalar(f$operation %||% "exact_match")
        if (!nzchar(op)) op <- "exact_match"

        if (!nzchar(col) || !(col %in% names(dt))) {
          dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
            f, "sütun veri kümesinde bulunamadı"
          )
          next
        }

        col_vals <- dt[[col]]
        val_str <- .pk_filter_observation_scalar(val)

        if (is.character(col_vals) || is.factor(col_vals)) {
          val_regex <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", val_str)
          col_vals_char <- as.character(col_vals)

          if (op == "exact_match") {
            dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
          } else if (op == "contains") {
            dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
          } else {
            dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
          }
          applied[[length(applied) + 1L]] <- f
          next
        }

        if (is.numeric(col_vals)) {
          val_num <- suppressWarnings(as.numeric(val_str))
          if (is.na(val_num)) {
            dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
              f, "değer sayısal biçime dönüştürülemedi"
            )
            next
          }

          if (op == "greater_than") {
            dt <- dt[col_vals > val_num, ]
          } else if (op == "less_than") {
            dt <- dt[col_vals < val_num, ]
          } else {
            dt <- dt[col_vals == val_num, ]
          }
          applied[[length(applied) + 1L]] <- f
          next
        }

        dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
          f, "sütun türü filtreleme için desteklenmiyor"
        )
      }
    } else {
      if (is.null(aggregation) || !tolower(aggregation) %in% c("count", "sum", "group_by")) {
        cat(sprintf(
          "[SMART_FILTER] Ne filtre ne aggregation var. GENEL SORU olarak işleniyor - tüm veri döndürülecek (%d satır).\n",
          nrow(dt)
        ))
      } else {
        cat("[SMART_FILTER] Aggregation mevcut, filtre yok - tüm veri üzerinde aggregation yapılacak\n")
      }
    }
  }

  # Toplulaştırma bu noktadan sonra yapılır. Köken/telemetri için korunması
  # gereken sayı, çıktı satırı değil burada eşleşen gerçek kayıt sayısıdır.
  matched_rows <- nrow(dt)

  if (!is.null(aggregation)) {
    agg_str <- tolower(aggregation)

    if (agg_str == "count") {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(finish(data.frame(Sonuc = aciklama, Adet = matched_rows), matched_rows))
    } else if (agg_str == "sum") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        sums <- lapply(num_cols, function(nc) sum(dt[[nc]], na.rm = TRUE))
        return(finish(as.data.frame(sums), matched_rows))
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
      return(finish(as.data.frame(dt[, .N, by = group_col]), matched_rows))
    }
  }

  finish(as.data.frame(dt), matched_rows)
}
