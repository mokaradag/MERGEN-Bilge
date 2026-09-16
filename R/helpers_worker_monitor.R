# ==============================================================================
# Dosya Yolu: R/helpers_worker_monitor.R
# Açıklama: Future tabanlı asenkron işleri izlemek için merkezi işçi/iş defteri.
#           Toplam işçi sayısını cluster'dan alır; aktif işleri uygulama düzeyinde
#           takip ederek sağlık ekranında kullanılabilecek metrikler üretir.
# ==============================================================================

# İşçi izleme defterini başlat
init_worker_monitor <- function() {
  if (!exists(".mergen_worker_monitor", envir = .GlobalEnv, inherits = FALSE)) {
    monitor_env <- new.env(parent = emptyenv())
    monitor_env$tasks <- new.env(parent = emptyenv())
    monitor_env$started_at <- Sys.time()

    assign(".mergen_worker_monitor", monitor_env, envir = .GlobalEnv)
  }

  get(".mergen_worker_monitor", envir = .GlobalEnv)
}

# Tekil görev sıra numarası üretir.
# Not: Bellek içi sayaç yalnızca bu R süreci içindir; PID + zaman + random parça
# ile birlikte kullanıldığında görev kimliği çakışma ihtimali pratikte sıfıra iner.
.next_worker_task_sequence <- local({
  counter <- 0L

  function() {
    counter <<- counter + 1L
    if (counter >= .Machine$integer.max) {
      counter <<- 1L
    }
    counter
  }
})

# Tekil görev kimliği üret.
# Üretim VM'inde aynı milisaniyede çok sayıda future işi oluştuğunda bile
# sessiz çakışma/overwrite riskini azaltır.
create_worker_task_id <- function(task_type = "generic") {
  raw_type <- as.character(task_type %||% "generic")[1]
  raw_type <- enc2utf8(raw_type)

  # Görev tipini log/dosya/HTML açısından güvenli ASCII etikete indir.
  safe_type <- iconv(raw_type, from = "", to = "ASCII//TRANSLIT", sub = "")
  safe_type <- gsub("[^A-Za-z0-9_.-]+", "_", safe_type, perl = TRUE)
  safe_type <- gsub("^_+|_+$", "", safe_type, perl = TRUE)
  if (!nzchar(safe_type)) {
    safe_type <- "generic"
  }

  random_part <- paste(sample(c(0:9, letters), 8, replace = TRUE), collapse = "")

  paste0(
    safe_type, "_",
    format(Sys.time(), "%Y%m%d%H%M%OS6"),
    "_pid", Sys.getpid(),
    "_seq", .next_worker_task_sequence(),
    "_", random_part
  )
}

# Yeni bir asenkron işi kaydet
register_worker_task <- function(task_id,
                                 task_type = "generic",
                                 session_token = NULL,
                                 meta = list()) {
  monitor_env <- init_worker_monitor()

  if (exists(task_id, envir = monitor_env$tasks, inherits = FALSE)) {
    stop(
      sprintf("Worker görev kimliği zaten kayıtlı: %s", task_id),
      call. = FALSE
    )
  }

  monitor_env$tasks[[task_id]] <- list(
    task_id = task_id,
    task_type = task_type,
    session_token = session_token %||% NA_character_,
    status = "running",
    started_at = Sys.time(),
    meta = meta
  )

  invisible(task_id)
}

# Bir işi tamamlandı olarak işaretle ve defterden kaldır
finish_worker_task <- function(task_id) {
  monitor_env <- init_worker_monitor()

  if (exists(task_id, envir = monitor_env$tasks, inherits = FALSE)) {
    rm(list = task_id, envir = monitor_env$tasks)
  }

  invisible(NULL)
}

# Eski veya bozulmuş kayıtları temizle
cleanup_worker_tasks <- function(max_age_secs = 86400) {
  monitor_env <- init_worker_monitor()
  current_time <- Sys.time()
  task_ids <- ls(envir = monitor_env$tasks)

  if (!length(task_ids)) {
    return(invisible(NULL))
  }

  for (task_id in task_ids) {
    item <- tryCatch(monitor_env$tasks[[task_id]], error = function(e) NULL)

    if (is.null(item) || is.null(item$started_at)) {
      try(rm(list = task_id, envir = monitor_env$tasks), silent = TRUE)
      next
    }

    age_secs <- as.numeric(difftime(current_time, item$started_at, units = "secs"))
    if (is.na(age_secs) || age_secs > max_age_secs) {
      try(rm(list = task_id, envir = monitor_env$tasks), silent = TRUE)
    }
  }

  invisible(NULL)
}

# Görev tiplerine göre özet çıkar
summarize_worker_tasks_by_type <- function() {
  monitor_env <- init_worker_monitor()
  cleanup_worker_tasks()

  task_ids <- ls(envir = monitor_env$tasks)
  if (!length(task_ids)) {
    return(list())
  }

  task_types <- vapply(task_ids, function(task_id) {
    item <- tryCatch(monitor_env$tasks[[task_id]], error = function(e) NULL)
    as.character(item$task_type %||% "generic")
  }, character(1))

  counts <- table(task_types)
  as.list(as.integer(counts)) |>
    stats::setNames(names(counts))
}

# Sağlık ekranı için izleme bilgisi üret
get_worker_monitor_info <- function() {
  cleanup_worker_tasks()

  total_workers <- tryCatch({
    as.integer(future::nbrOfWorkers())
  }, error = function(e) {
    NA_integer_
  })

  if (is.na(total_workers) || total_workers < 1) {
    total_workers <- 1L
  }

  monitor_env <- init_worker_monitor()
  task_ids <- ls(envir = monitor_env$tasks)
  active_jobs <- length(task_ids)

  active_workers <- min(active_jobs, total_workers)
  free_workers <- max(total_workers - active_workers, 0L)
  queued_jobs <- max(active_jobs - total_workers, 0L)
  usage_pct <- if (total_workers > 0) round((active_workers / total_workers) * 100, 1) else 0

  list(
    total_workers = total_workers,
    active_jobs = as.integer(active_jobs),
    active_workers = as.integer(active_workers),
    free_workers = as.integer(free_workers),
    queued_jobs = as.integer(queued_jobs),
    usage_pct = usage_pct,
    task_type_breakdown = summarize_worker_tasks_by_type(),
    note = paste(
      "Bu metrikler, uygulamanın future_promise ile başlattığı asenkron işleri izler.",
      "Doğrudan cluster içi düşük seviye worker telemetrisi değil, uygulama düzeyi iş yükü görünümüdür."
    )
  )
}

# İşçi fonksiyonunun gövdesindeki serbest değişkenleri ve bağlı paketleri
# otomatik olarak tespit et. Böylece call_llm_worker(), generate_image()
# gibi global yardımcılar worker tarafına her çağrıda taşınır.
# NOT: Bu tarama .GlobalEnv büyüdükçe pahalıdır; açılış kritik yolundaki
# görevler bunun yerine dependency_mode="explicit" kullanmalıdır.
worker_monitor_detect_task_deps <- function(task_fn) {
  tryCatch({
    gp <- future::getGlobalsAndPackages(
      expr = body(task_fn),
      envir = environment(task_fn),
      globals = TRUE
    )

    list(
      globals = if (!is.null(gp$globals)) as.list(gp$globals) else list(),
      packages = gp$packages %||% character(0)
    )
  }, error = function(e) {
    list(
      globals = list(),
      packages = character(0)
    )
  })
}

# Bir fonksiyon worker'a global olarak taşınıyorsa, o fonksiyonun
# global ortamdan kullandığı yardımcıları da özyinelemeli olarak topla.
worker_monitor_collect_nested_globals <- function(fn_obj, seen = character()) {
  if (!is.function(fn_obj)) {
    return(list())
  }

  fn_global_names <- tryCatch(
    codetools::findGlobals(fn_obj, merge = TRUE),
    error = function(e) character(0)
  )

  if (!length(fn_global_names)) {
    return(list())
  }

  available_names <- intersect(
    fn_global_names,
    ls(envir = .GlobalEnv, all.names = TRUE)
  )
  available_names <- setdiff(available_names, seen)

  if (!length(available_names)) {
    return(list())
  }

  collected <- mget(available_names, envir = .GlobalEnv, inherits = TRUE)
  # `seen` kümesi özyineleme DALLARI ARASINDA paylaşılır; her dala aynı
  # başlangıç kümesini vermek aynı fonksiyonun tekrar tekrar açılmasına
  # (yoğun çağrı grafiğinde üstel maliyet) yol açıyordu.
  next_seen <- unique(c(seen, available_names))

  nested <- list()
  for (nm in names(collected)) {
    obj <- collected[[nm]]
    if (!is.function(obj)) next

    deeper <- worker_monitor_collect_nested_globals(obj, seen = next_seen)
    next_seen <- unique(c(next_seen, names(deeper)))
    if (!length(deeper)) next

    for (deep_nm in names(deeper)) {
      if (!deep_nm %in% names(collected) && !deep_nm %in% names(nested)) {
        nested[[deep_nm]] <- deeper[[deep_nm]]
      }
    }
  }

  c(collected, nested)
}

# Açıkça verilen veya otomatik yakalanan fonksiyonların kullandığı
# yardımcıları da worker'a ekle.
worker_monitor_expand_function_globals <- function(promise_globals) {
  expanded_globals <- list()
  base_global_names <- names(promise_globals)

  for (nm in base_global_names) {
    obj <- promise_globals[[nm]]
    if (!is.function(obj)) next

    nested <- worker_monitor_collect_nested_globals(
      obj,
      seen = unique(c(base_global_names, names(expanded_globals)))
    )

    for (nested_nm in names(nested)) {
      if (!nested_nm %in% names(promise_globals) &&
          !nested_nm %in% names(expanded_globals)) {
        expanded_globals[[nested_nm]] <- nested[[nested_nm]]
      }
    }
  }

  expanded_globals
}

.worker_monitor_trace_enabled <- function() {
  isTRUE(tolower(Sys.getenv("MERGEN_STARTUP_PERF_TRACE", "false")) %in%
           c("true", "1", "yes", "on"))
}

# Future promise çağrısını izlemeli şekilde sarmala.
# dependency_mode:
#   - "auto" (varsayılan): mevcut davranış; görev gövdesinin bağımlılıkları
#     otomatik taranır ve iç içe fonksiyon yardımcıları .GlobalEnv'den toplanır.
#   - "explicit": HİÇBİR otomatik tarama yapılmaz; yalnızca çağıranın verdiği
#     globals + packages worker'a taşınır. Görev fonksiyonunun ortamı, oturum
#     çerçeve zincirinin worker'a serileştirilmesini önlemek için verilen
#     globals'ı içeren izole bir ortama yeniden bağlanır. Açılış kritik
#     yolundaki görevler bu modu kullanmalıdır (bkz. CLAUDE.md 8A).
tracked_future_promise <- function(task_fn,
                                   task_type = "generic",
                                   session_token = NULL,
                                   meta = list(),
                                   globals = NULL,
                                   dependency_mode = c("auto", "explicit"),
                                   packages = NULL) {
  if (!is.function(task_fn)) {
    stop("tracked_future_promise() için 'task_fn' bir fonksiyon olmalıdır.")
  }

  dependency_mode <- match.arg(dependency_mode)

  task_id <- create_worker_task_id(task_type = task_type)

  register_worker_task(
    task_id = task_id,
    task_type = task_type,
    session_token = session_token,
    meta = meta
  )

  promise_globals <- globals %||% list()
  extra_packages <- unique(as.character(packages %||% character(0)))

  schedule_started <- Sys.time()
  detect_ms <- 0
  expand_ms <- 0

  if (identical(dependency_mode, "explicit")) {
    future_packages <- extra_packages

    # Kapanış zinciri (observer/oturum ortamları) worker'a serileştirilmesin:
    # görev fonksiyonu yalnızca verilen globals'ı gören izole ortama bağlanır.
    fn_env <- new.env(parent = globalenv())
    for (nm in names(promise_globals)) {
      if (nzchar(nm)) assign(nm, promise_globals[[nm]], envir = fn_env)
    }
    environment(task_fn) <- fn_env
  } else {
    detect_started <- Sys.time()
    detected_future_deps <- worker_monitor_detect_task_deps(task_fn)
    detect_ms <- as.numeric(difftime(Sys.time(), detect_started, units = "secs")) * 1000

    # Çağıran taraftan açıkça verilen globals öncelikli kalsın.
    if (length(detected_future_deps$globals) > 0) {
      for (nm in names(detected_future_deps$globals)) {
        if (!nzchar(nm) || nm %in% names(promise_globals)) next
        promise_globals[[nm]] <- detected_future_deps$globals[[nm]]
      }
    }

    expand_started <- Sys.time()
    expanded_globals <- worker_monitor_expand_function_globals(promise_globals)
    expand_ms <- as.numeric(difftime(Sys.time(), expand_started, units = "secs")) * 1000

    if (length(expanded_globals) > 0) {
      promise_globals <- c(promise_globals, expanded_globals)
    }

    future_packages <- unique(c(detected_future_deps$packages, extra_packages))
  }

  promise_globals$task_fn <- task_fn

  dispatch_started <- Sys.time()
  p <- tryCatch({
    promises::future_promise(
      {
        task_fn()
      },
      globals = promise_globals,
      packages = future_packages
    )
  }, error = function(e) {
    finish_worker_task(task_id)
    stop(e)
  })

  dispatch_ms <- as.numeric(difftime(Sys.time(), dispatch_started, units = "secs")) * 1000
  total_ms <- as.numeric(difftime(Sys.time(), schedule_started, units = "secs")) * 1000

  # 1 sn üzeri senkron planlama, olay döngüsünü bloklayan gerçek bir üretim
  # sinyalidir; iz açık olmasa da tek satır loglanır (değer içermez).
  if (.worker_monitor_trace_enabled() || total_ms > 1000) {
    cat(sprintf(
      "[STARTUP PERF] worker_dispatch task_type=%s mode=%s detect_ms=%.0f expand_ms=%.0f dispatch_ms=%.0f total_ms=%.0f globals=%d packages=%d\n",
      as.character(task_type %||% "generic")[1],
      dependency_mode,
      detect_ms,
      expand_ms,
      dispatch_ms,
      total_ms,
      length(promise_globals),
      length(future_packages)
    ))
  }

  promises::then(
    p,
    onFulfilled = function(value) {
      finish_worker_task(task_id)
      value
    },
    onRejected = function(error) {
      finish_worker_task(task_id)
      stop(error)
    }
  )
}

cleanup_worker_tasks_for_session <- function(session_token) {
  if (is.null(session_token) || !nzchar(session_token)) {
    return(invisible(NULL))
  }

  monitor_env <- init_worker_monitor()
  task_ids <- ls(envir = monitor_env$tasks)

  for (task_id in task_ids) {
    item <- tryCatch(monitor_env$tasks[[task_id]], error = function(e) NULL)

    if (is.null(item)) next

    if (identical(item$session_token, session_token)) {
      try(rm(list = task_id, envir = monitor_env$tasks), silent = TRUE)
    }
  }

  invisible(NULL)
}