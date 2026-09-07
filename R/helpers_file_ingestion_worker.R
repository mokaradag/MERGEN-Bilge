# ==============================================================================
# Dosya Yolu: R/helpers_file_ingestion_worker.R
# Açıklama: Dosya alım hattının WORKER katmanı. Pahalı iş (içerik doğrulama,
#           hash + kalıcı klasöre kopyalama, boyut/bütünlük doğrulaması) burada
#           yapılır ve future worker'ında çalışacak şekilde tasarlanmıştır.
#           Shiny oturumu, reaktif değer veya DB bağlantısı KULLANILMAZ; yalnızca
#           düz görev listeleri alınır ve düz sonuç listeleri döndürülür.
#           Kalıcı indeks yazımı bilinçli olarak ana süreçte kalır (bkz.
#           R/helpers_file_ingestion_runtime.R).
#           R/helpers_file_ingestion_task.R dosyasından sonra source edilmelidir.
# ==============================================================================

.file_ingestion_worker_cache <- new.env(parent = emptyenv())

# Tekil görev sonucu iskeleti; başarısız dallarda da aynı şekil döndürülür.
file_ingestion_task_result <- function(task, ok, dest = "", code = NULL, error = NULL,
                                       size = NA_real_, timings = list()) {
  list(
    ok = isTRUE(ok),
    batch_id = task$batch_id %||% "",
    name = task$name %||% "",
    source_path = task$datapath %||% "",
    dest = as.character(dest %||% "")[1],
    type = task$type %||% "",
    size = suppressWarnings(as.numeric(size)),
    code = code,
    error = error,
    validate_ms = as.numeric(timings$validate_ms %||% 0),
    copy_ms = as.numeric(timings$copy_ms %||% 0),
    verify_ms = as.numeric(timings$verify_ms %||% 0),
    total_ms = as.numeric(timings$total_ms %||% 0)
  )
}

# Tek dosyayı doğrular, kalıcı kullanıcı klasörüne kopyalar ve doğrular.
# Başarısızlıkta yarım kalan hedef dosya silinir (kısmi kayıt bırakılmaz).
file_ingestion_execute_task <- function(task) {
  started <- Sys.time()
  elapsed_ms <- function(from) as.numeric(difftime(Sys.time(), from, units = "secs")) * 1000

  # R seçenekleri worker'a taşınmaz; kalıcı depolama kökü ana süreçte çözülüp
  # görevle birlikte geldiği için burada geçici olarak zorlanır. Aksi halde
  # worker, ana süreçten FARKLI bir dizine kopyalayabilir.
  depo_koku <- as.character(task$storage_base %||% "")[1]
  if (!is.na(depo_koku) && nzchar(depo_koku)) {
    onceki_kok <- getOption("mergen.mcp_base_dir", NULL)
    options(mergen.mcp_base_dir = depo_koku)
    on.exit(options(mergen.mcp_base_dir = onceki_kok), add = TRUE)
  }

  if (!file_ingestion_valid_user_id(task$user_id)) {
    return(file_ingestion_task_result(
      task, FALSE,
      code = "invalid_user",
      error = "Geçersiz kullanıcı kimliği nedeniyle dosya kalıcı klasöre kaydedilemedi.",
      timings = list(total_ms = elapsed_ms(started))
    ))
  }

  validate_started <- Sys.time()
  if (exists("validate_uploaded_file", mode = "function", inherits = TRUE)) {
    decision <- tryCatch(
      validate_uploaded_file(
        path = task$datapath,
        filename = task$name,
        max_size_mb = task$max_size_mb,
        allowed_ext = task$allowed_ext
      ),
      error = function(e) list(ok = FALSE, error = conditionMessage(e), code = "validation_error")
    )

    if (!isTRUE(decision$ok)) {
      return(file_ingestion_task_result(
        task, FALSE,
        code = decision$code %||% "validation_error",
        error = decision$error %||% "Dosya doğrulanamadı.",
        timings = list(
          validate_ms = elapsed_ms(validate_started),
          total_ms = elapsed_ms(started)
        )
      ))
    }
  } else {
    # Doğrulayıcı worker'a taşınmadıysa yükleme fail-open kopyalanmaz.
    return(file_ingestion_task_result(
      task, FALSE,
      code = "validator_missing",
      error = "Dosya doğrulayıcı yüklenemedi; dosya kaydedilmedi.",
      timings = list(total_ms = elapsed_ms(started))
    ))
  }
  validate_ms <- elapsed_ms(validate_started)

  copy_started <- Sys.time()
  dest <- tryCatch(
    copy_to_mcp_base(
      list(name = task$name, datapath = task$datapath, size = task$size, type = task$type),
      task$user_id
    ),
    error = function(e) structure("", class = "file_ingestion_copy_error", message = conditionMessage(e))
  )
  copy_ms <- elapsed_ms(copy_started)

  if (inherits(dest, "file_ingestion_copy_error") || !nzchar(as.character(dest)[1])) {
    return(file_ingestion_task_result(
      task, FALSE,
      code = "copy_failed",
      error = attr(dest, "message") %||% "Dosya kalıcı klasöre kopyalanamadı.",
      timings = list(validate_ms = validate_ms, copy_ms = copy_ms, total_ms = elapsed_ms(started))
    ))
  }

  dest <- as.character(dest)[1]
  verify_started <- Sys.time()
  verification <- file_ingestion_verify_copy(task$datapath, dest)
  verify_ms <- elapsed_ms(verify_started)

  if (!isTRUE(verification$ok)) {
    file_ingestion_discard_dest(dest, task$datapath)
    return(file_ingestion_task_result(
      task, FALSE,
      code = verification$code %||% "verify_failed",
      error = verification$error %||% "Kopyalanan dosya doğrulanamadı.",
      timings = list(
        validate_ms = validate_ms, copy_ms = copy_ms,
        verify_ms = verify_ms, total_ms = elapsed_ms(started)
      )
    ))
  }

  file_ingestion_task_result(
    task, TRUE,
    dest = dest,
    size = verification$size,
    timings = list(
      validate_ms = validate_ms, copy_ms = copy_ms,
      verify_ms = verify_ms, total_ms = elapsed_ms(started)
    )
  )
}

# Hedef dosyanın gerçekten oluştuğunu ve boyutunun kaynakla tutarlı olduğunu
# denetler. Ağ paylaşımlarında file.info NA dönebildiği için varlık kontrolü
# gevşek yardımcı üzerinden yapılır.
file_ingestion_verify_copy <- function(src_path, dest_path) {
  var_mi <- if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
    isTRUE(path_exists_relaxed(dest_path))
  } else {
    file.exists(dest_path)
  }

  if (!var_mi) {
    return(list(ok = FALSE, code = "dest_missing", error = "Kopyalanan dosya hedefte bulunamadı."))
  }

  dest_size <- suppressWarnings(as.numeric(file.info(dest_path)$size[1]))
  src_size <- suppressWarnings(as.numeric(file.info(src_path)$size[1]))

  if (is.finite(dest_size) && is.finite(src_size) && dest_size != src_size) {
    return(list(
      ok = FALSE,
      code = "size_mismatch",
      error = sprintf("Kopyalanan dosya boyutu uyuşmuyor (%.0f != %.0f).", dest_size, src_size)
    ))
  }

  if (is.finite(dest_size) && dest_size == 0 && is.finite(src_size) && src_size > 0) {
    return(list(ok = FALSE, code = "empty_copy", error = "Kopyalanan dosya boş."))
  }

  list(ok = TRUE, size = if (is.finite(dest_size)) dest_size else src_size)
}

# Doğrulaması başarısız hedefi temizler. Kaynak dosya (Shiny geçici yükleme)
# asla silinmez.
file_ingestion_discard_dest <- function(dest_path, src_path = "") {
  dest_path <- as.character(dest_path %||% "")[1]
  if (!nzchar(dest_path)) return(invisible(FALSE))
  if (identical(normalizePath(dest_path, winslash = "/", mustWork = FALSE),
                normalizePath(as.character(src_path %||% "")[1], winslash = "/", mustWork = FALSE))) {
    return(invisible(FALSE))
  }

  try(unlink(dest_path, force = TRUE), silent = TRUE)
  invisible(TRUE)
}

# Bir partideki dosyaları SIRAYLA işler. Tek worker görevi kullanıldığı için
# dosya başına sınırsız future üretilmez; bir dosyanın hatası diğerlerini
# durdurmaz.
file_ingestion_execute_batch <- function(tasks) {
  tasks <- tasks %||% list()
  if (!length(tasks)) return(list())

  lapply(tasks, function(task) {
    tryCatch(
      file_ingestion_execute_task(task),
      error = function(e) file_ingestion_task_result(
        task, FALSE,
        code = "worker_error",
        error = conditionMessage(e)
      )
    )
  })
}

# Worker'a taşınacak global paketini üretir ve süreç ömrü boyunca önbelleğe alır.
# Bağımlılık taraması her gönderimde değil, yalnızca ilk kez yapılır; böylece
# gönderim maliyeti olay döngüsünde birikmez.
file_ingestion_worker_globals <- function(refresh = FALSE,
                                          envir = parent.env(environment())) {
  if (!isTRUE(refresh) && !is.null(.file_ingestion_worker_cache$globals)) {
    return(.file_ingestion_worker_cache$globals)
  }

  wanted <- c(
    "file_ingestion_execute_batch",
    "file_ingestion_execute_task",
    "file_ingestion_task_result",
    "file_ingestion_verify_copy",
    "file_ingestion_discard_dest",
    "file_ingestion_valid_user_id",
    "validate_uploaded_file",
    "copy_to_mcp_base",
    "path_exists_relaxed"
  )

  bundle <- list()
  for (nm in wanted) {
    obj <- get0(nm, envir = envir, inherits = TRUE)
    if (!is.null(obj)) bundle[[nm]] <- obj
  }

  if (exists("worker_monitor_expand_function_globals", mode = "function", inherits = TRUE)) {
    nested <- tryCatch(worker_monitor_expand_function_globals(bundle), error = function(e) list())
    for (nm in names(nested)) {
      if (!nm %in% names(bundle)) bundle[[nm]] <- nested[[nm]]
    }
  }

  .file_ingestion_worker_cache$globals <- bundle
  bundle
}
