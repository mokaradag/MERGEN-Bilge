# Tarayıcı yüklemesinin kaynağı yalnızca Shiny'nin BU oturuma verdiği yükleme
# işidir. Shiny değeri sunucuda uploadInit/uploadEnd ile data.frame olarak kurar
# (iş kimlikleri oturuma özeldir) ve dosyayı <kök>/<iş kimliği>/<sıra>.<uzantı>
# düzenine yazar; istemcinin setInputValue ile gönderebildiği değer ise JSON
# liste olarak gelir. Bu kaynağa uymayan satır bir dosya yolu iddiasıdır ve
# reddedilir. Sunucu içi aktarımlar bu kapıdan geçmez.
file_ingestion_shiny_uploads <- function(uploads, upload_root = tempdir()) {
  sutunlar <- c("name", "size", "type", "datapath")
  bos <- data.frame(name = character(), size = numeric(), type = character(),
                    datapath = character(), stringsAsFactors = FALSE)
  if (is.null(uploads)) return(list(uploads = bos, rejected = 0L))
  if (!is.data.frame(uploads) || !all(sutunlar %in% names(uploads))) {
    return(list(uploads = bos, rejected = max(1L, NROW(uploads))))
  }
  if (nrow(uploads) == 0L) return(list(uploads = bos, rejected = 0L))

  windows <- identical(.Platform$OS.type, "windows")
  kanonik <- function(yol) {
    yol <- normalizePath(yol, winslash = "/", mustWork = FALSE)
    if (windows) tolower(yol) else yol
  }
  kok <- kanonik(upload_root)
  kabul <- vapply(seq_len(nrow(uploads)), function(i) {
    yol <- uploads$datapath[i]
    if (!is.character(yol) || length(yol) != 1L || is.na(yol) || !nzchar(yol)) return(FALSE)
    is_dizini <- dirname(yol)
    grepl("^[0-9]+(\\.[[:alnum:]]+)?$", basename(yol)) &&
      grepl("^[0-9A-Fa-f]{16,64}$", basename(is_dizini)) &&
      identical(kanonik(dirname(is_dizini)), kok) &&
      isTRUE(file.exists(yol)) && !isTRUE(dir.exists(yol)) &&
      !nzchar(Sys.readlink(yol)) && !nzchar(Sys.readlink(is_dizini))
  }, logical(1))

  list(uploads = uploads[kabul, sutunlar, drop = FALSE], rejected = sum(!kabul))
}

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
          file.exists(task$datapath)) {
        # Yükleme alanı dışındaki kaynak asla okunmaz/kopyalanmaz (fail-closed).
        task$source_error <- "Yüklenen dosyanın kaynağı geçici yükleme alanında değil."
        file_ingestion_controller_debug(job$controller, "ingest_source_outside_upload_root", task$source_error)
        log_warn(task$source_error)
        return(task)
      }
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
