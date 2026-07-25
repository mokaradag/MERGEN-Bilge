# ==============================================================================
# Dosya Yolu: R/helpers_file_ingestion_task.R
# Açıklama: Dosya alım (ingestion) hattının SAF planlama katmanı. Shiny, reaktif
#           değer, oturum, veritabanı ve ağ erişimi içermez; yalnızca düz
#           listelerle çalışır. Worker'a taşınacak görev anlık görüntüleri,
#           ucuz üstveri reddi ve sonuç/metrik özetleri burada üretilir.
#           Pahalı doğrulama (disk erişimi) ve kopyalama worker katmanındadır.
# ==============================================================================

# Yüklemeleri (Shiny fileInput data.frame'i veya tekil liste) düz listeye indirger.
file_ingestion_normalize_uploads <- function(uploads) {
  if (is.null(uploads)) return(list())

  if (is.data.frame(uploads)) {
    if (nrow(uploads) == 0L) return(list())

    return(lapply(seq_len(nrow(uploads)), function(i) {
      list(
        name = as.character(uploads$name[i] %||% ""),
        datapath = as.character(uploads$datapath[i] %||% ""),
        size = suppressWarnings(as.numeric(uploads$size[i] %||% NA_real_)),
        type = as.character(uploads$type[i] %||% "")
      )
    }))
  }

  if (is.list(uploads) && !is.null(uploads$name)) {
    return(list(list(
      name = as.character(uploads$name[1] %||% ""),
      datapath = as.character(uploads$datapath[1] %||% ""),
      size = suppressWarnings(as.numeric(uploads$size[1] %||% NA_real_)),
      type = as.character(uploads$type[1] %||% "")
    )))
  }

  if (is.list(uploads) && length(uploads) > 0L && is.list(uploads[[1]])) {
    return(lapply(uploads, function(item) {
      list(
        name = as.character(item$name %||% ""),
        datapath = as.character(item$datapath %||% item$path %||% ""),
        size = suppressWarnings(as.numeric(item$size %||% NA_real_)),
        type = as.character(item$type %||% "")
      )
    }))
  }

  list()
}

# Kalıcı depolama kökünü ANA SÜREÇTE çözer. R seçenekleri future worker'larına
# taşınmadığı için kök, görev anlık görüntüsüyle birlikte worker'a gönderilir;
# aksi halde worker farklı bir dizine kopyalayabilir.
file_ingestion_storage_base <- function() {
  base <- as.character(getOption("mergen.mcp_base_dir", ""))[1]
  if (is.na(base) || !nzchar(base)) {
    base <- as.character(Sys.getenv("MCP_FILES_BASE", ""))[1]
  }
  if (is.na(base)) "" else base
}

# Worker'a taşınacak tekil görev anlık görüntüsü. Yalnızca skaler/düz değerler.
file_ingestion_task_snapshot <- function(upload,
                                         user_id,
                                         max_size_mb = 25L,
                                         allowed_ext = NULL,
                                         batch_id = "",
                                         storage_base = file_ingestion_storage_base()) {
  list(
    batch_id = as.character(batch_id %||% "")[1],
    name = as.character(upload$name %||% "")[1],
    datapath = as.character(upload$datapath %||% "")[1],
    size = suppressWarnings(as.numeric(upload$size %||% NA_real_)[1]),
    type = as.character(upload$type %||% "")[1],
    user_id = as.character(user_id %||% "")[1],
    max_size_mb = suppressWarnings(as.numeric(max_size_mb %||% NA_real_)[1]),
    storage_base = as.character(storage_base %||% "")[1],
    allowed_ext = if (is.null(allowed_ext)) NULL else as.character(allowed_ext)
  )
}

# Kullanıcı kimliğinin kalıcı yazma için geçerli olup olmadığını denetler.
file_ingestion_valid_user_id <- function(user_id) {
  uid <- as.character(user_id %||% "")[1]
  if (is.na(uid) || !nzchar(uid)) return(FALSE)
  !uid %in% c("0", "unknown", "NA", "null")
}

# Toplu yükleme planı: yinelenen adlar, ucuz üstveri reddi ve worker görevleri.
# Bu aşamada DİSKE dokunulmaz; güvenlik doğrulamasının tamamı worker'da
# validate_uploaded_file() ile yapılır.
file_ingestion_plan_batch <- function(uploads,
                                      existing_names = character(),
                                      user_id = "",
                                      allowed_ext = NULL,
                                      max_size_mb = 25L,
                                      batch_id = "",
                                      storage_base = file_ingestion_storage_base()) {
  items <- file_ingestion_normalize_uploads(uploads)

  plan <- list(
    batch_id = as.character(batch_id %||% "")[1],
    tasks = list(),
    duplicate_names = character(),
    rejected = list()
  )

  if (!length(items)) return(plan)

  existing_names <- as.character(existing_names %||% character())
  normalized_ext <- if (is.null(allowed_ext)) NULL else tolower(gsub("^\\.+", "", as.character(allowed_ext)))
  limit_bytes <- suppressWarnings(as.numeric(max_size_mb) * 1024 * 1024)

  reject <- function(name, code, error) {
    plan$rejected[[length(plan$rejected) + 1L]] <<- list(name = name, code = code, error = error)
  }

  for (item in items) {
    name <- item$name

    if (!nzchar(name)) {
      reject(name, "bad_filename", "Dosya adı okunamadı.")
      next
    }

    if (name %in% existing_names) {
      plan$duplicate_names <- c(plan$duplicate_names, name)
      next
    }

    if (!nzchar(item$datapath)) {
      reject(name, "missing_path", "Yüklenen dosya yolu okunamadı.")
      next
    }

    if (!is.null(normalized_ext)) {
      ext <- tolower(tools::file_ext(name))
      if (!nzchar(ext) || !(ext %in% normalized_ext)) {
        reject(name, "ext_not_allowed", sprintf("Dosya uzantısı '%s' desteklenmiyor.", ext))
        next
      }
    }

    if (is.finite(limit_bytes) && limit_bytes > 0 &&
        is.finite(item$size) && item$size > limit_bytes) {
      reject(name, "too_large", sprintf(
        "Dosya boyutu sınırı aşıldı (%.1f MB > %.0f MB).",
        item$size / (1024 * 1024),
        as.numeric(max_size_mb)
      ))
      next
    }

    plan$tasks[[length(plan$tasks) + 1L]] <- file_ingestion_task_snapshot(
      upload = item,
      user_id = user_id,
      max_size_mb = max_size_mb,
      allowed_ext = allowed_ext,
      batch_id = batch_id,
      storage_base = storage_base
    )
  }

  plan$duplicate_names <- unique(plan$duplicate_names)
  plan
}

# Süreç genelinde tekil parti kimliği.
file_ingestion_new_batch_id <- function(prefix = "batch") {
  paste0(
    as.character(prefix %||% "batch")[1], "_",
    format(Sys.time(), "%Y%m%d%H%M%OS3"), "_",
    Sys.getpid(), "_",
    paste(sample(c(0:9, letters), 6L, replace = TRUE), collapse = "")
  )
}

# Worker sonuçlarını ana süreç için özetler.
file_ingestion_summarize_results <- function(results) {
  results <- results %||% list()

  ok_flags <- vapply(results, function(r) isTRUE(r$ok), logical(1))
  bytes <- vapply(results, function(r) {
    value <- suppressWarnings(as.numeric(r$size %||% 0))
    if (!is.finite(value)) 0 else value
  }, numeric(1))
  durations <- vapply(results, function(r) {
    value <- suppressWarnings(as.numeric(r$total_ms %||% 0))
    if (!is.finite(value)) 0 else value
  }, numeric(1))

  list(
    total = length(results),
    succeeded = sum(ok_flags),
    failed = sum(!ok_flags),
    total_bytes = sum(bytes[ok_flags]),
    total_ms = sum(durations)
  )
}

# Gizli değer içermeyen tek satırlık metrik kaydı üretir. Dosya adı ve yol
# yazılmaz; yalnızca sayısal/kategorik ölçümler raporlanır.
file_ingestion_metrics_line <- function(batch_id,
                                        summary,
                                        queue_wait_ms = 0,
                                        commit_ms = 0,
                                        index_ms = 0,
                                        queued_batches = 0,
                                        active_batches = 0) {
  sprintf(
    paste0(
      "[FILE INGEST] batch=%s files=%d ok=%d fail=%d bytes=%.0f ",
      "queue_wait_ms=%.0f worker_ms=%.0f index_ms=%.0f commit_ms=%.0f ",
      "active=%d queued=%d"
    ),
    as.character(batch_id %||% "")[1],
    as.integer(summary$total %||% 0L),
    as.integer(summary$succeeded %||% 0L),
    as.integer(summary$failed %||% 0L),
    as.numeric(summary$total_bytes %||% 0),
    as.numeric(queue_wait_ms %||% 0),
    as.numeric(summary$total_ms %||% 0),
    as.numeric(index_ms %||% 0),
    as.numeric(commit_ms %||% 0),
    as.integer(active_batches %||% 0L),
    as.integer(queued_batches %||% 0L)
  )
}
