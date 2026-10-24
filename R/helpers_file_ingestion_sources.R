# Kabulden önce geçici kaynakları işe bağlar; büyük bayt kopyası yapmaz.
file_ingestion_bind_sources <- function(job) {
  kaynaklar <- file.path(tempdir(), "mergen_ingest_sources", gsub("[^A-Za-z0-9_.-]", "_", job$id))
  if (dir.create(kaynaklar, recursive = TRUE, showWarnings = FALSE)) job$lease$sources <- kaynaklar
  gecici_kok <- normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
  job$tasks <- Map(function(task, i) {
    kaynak <- normalizePath(task$datapath %||% "", winslash = "/", mustWork = FALSE)
    if (!startsWith(kaynak, paste0(gecici_kok, "/"))) {
      # Windows eksik dosyanın kısa yolunu çözemez; mevcut üst dizini sınırla.
      ust <- normalizePath(dirname(task$datapath), winslash = "/", mustWork = FALSE)
      if ((!identical(ust, gecici_kok) && !startsWith(ust, paste0(gecici_kok, "/"))) ||
          file.exists(task$datapath)) return(task)
    }
    bag <- file.path(kaynaklar, as.character(i))
    hazir <- identical(job$lease$sources, kaynaklar)
    bagli <- hazir && isTRUE(suppressWarnings(tryCatch(file.link(task$datapath, bag),
      error = function(e) FALSE)))
    if (!bagli && hazir) {
      # Bağ desteklenmiyorsa aynı geçici birimde atomik sahiplik devri yapılır.
      bagli <- isTRUE(suppressWarnings(tryCatch(file.rename(task$datapath, bag),
        error = function(e) FALSE)))
      if (bagli) job$lease$source_moves <- c(job$lease$source_moves,
        list(list(from = task$datapath, to = bag)))
    }
    if (bagli) {
      task$datapath <- bag
    } else {
      task$source_error <- "Yüklenen dosyanın geçici kaynağı hazırlanamadı."
      file_ingestion_controller_debug(job$controller, "ingest_source_link_error", task$source_error)
      log_warn(task$source_error)
    }
    task
  }, job$tasks, seq_along(job$tasks))
  job
}

# Commit edilmeyen kaynak iade edilir; kapanmış yükleme dizini artık hedef değildir.
file_ingestion_restore_sources <- function(job) {
  for (move in job$lease$source_moves) {
    if (move$to %in% job$lease$committed_sources) next
    restored <- !file.exists(move$from) && isTRUE(suppressWarnings(tryCatch(
      file.rename(move$to, move$from), error = function(e) FALSE)))
    if (!restored && dir.exists(dirname(move$from))) {
      job$lease$retained_sources <- c(job$lease$retained_sources, move$to)
      file_ingestion_controller_debug(job$controller, "ingest_source_restore_error",
        "Kabul edilmeyen yüklemenin geçici kaynağı iade edilemedi; kopya korundu.")
    }
  }
  invisible(NULL)
}
