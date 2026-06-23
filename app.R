# app.R

# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı başlatır.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Önce mevcut ve çalışan source() yolunu dener.
# Yalnızca kaynak yükleme encoding/parse hatası verirse kontrollü bir yedek
# çözüm devreye girer ve dosya farklı kodlamalarla okunup parse edilmeye çalışılır.
required_boot_files <- c(
  "R/utils_safe_source.R",
  "R/bootstrap_source_manifest.R",
  "R/config_source_manifest.R",
  "global.R",
  "ui.R",
  "server.R"
)

missing_boot_files <- required_boot_files[!file.exists(required_boot_files)]
if (length(missing_boot_files) > 0) {
  stop(sprintf(
    "Başlatma durduruldu. Eksik dosyalar: %s",
    paste(missing_boot_files, collapse = ", ")
  ))
}

boot_step <- function(step_name, expr) {
  tryCatch(
    force(expr),
    error = function(e) {
      stop(
        sprintf("Boot adımı başarısız [%s]: %s", step_name, conditionMessage(e)),
        call. = FALSE
      )
    }
  )
}

boot_step("utils_safe_source", {
  source("R/utils_safe_source.R", encoding = "UTF-8", local = globalenv())
})

boot_step("bootstrap_source_manifest", {
  safe_source("R/bootstrap_source_manifest.R", encoding = "UTF-8")
})

boot_step("global.R", {
  safe_source("global.R", encoding = "UTF-8")
})

boot_step("ui.R", {
  safe_source("ui.R", encoding = "UTF-8")
})

boot_step("server.R", {
  safe_source("server.R", encoding = "UTF-8")
})

safe_add_resource_path <- function(prefix, directory) {
  if (!dir.exists(directory)) {
    warning(sprintf("Kaynak yolu atlandı; klasör bulunamadı: %s", directory))
    return(invisible(FALSE))
  }

  withCallingHandlers({
    shiny::addResourcePath(prefix, directory)
  }, warning = function(w) {
    if (grepl("already", conditionMessage(w), ignore.case = TRUE)) {
      invokeRestart("muffleWarning")
    }
  })

  invisible(TRUE)
}

if (dir.exists("www")) {
  for (subdir in list.dirs("www", recursive = FALSE, full.names = FALSE)) {
    safe_add_resource_path(subdir, file.path("www", subdir))
  }
  safe_add_resource_path("img", "www")
} else {
  warning("www klasörü bulunamadı; statik kaynaklar kaydedilmedi.")
}

validate_boot_state <- function(app_env = globalenv()) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Boot doğrulaması başarısız: shiny paketi yüklü değil.", call. = FALSE)
  }

  if (!exists("safe_source", envir = app_env, mode = "function", inherits = FALSE)) {
    stop("Boot doğrulaması başarısız: safe_source yüklenmedi.", call. = FALSE)
  }

  if (!exists("ui", envir = app_env, inherits = FALSE)) {
    stop("Boot doğrulaması başarısız: ui nesnesi yüklenmedi.", call. = FALSE)
  }

  ui_obj <- get("ui", envir = app_env, inherits = FALSE)
  # Shiny UI'si statik bir etiket nesnesi VEYA bir function(req) olabilir.
  # Kök sayfa HTML önbelleği (R/helpers_index_page_cache.R) açıkken `ui` bir
  # fonksiyondur; bu da geçerli bir Shiny UI sözleşmesidir.
  if (!is.function(ui_obj) &&
      !inherits(ui_obj, c("shiny.tag", "shiny.tag.list", "html"))) {
	stop("Boot doğrulaması başarısız: ui nesnesi geçerli bir Shiny UI değil.", call. = FALSE)
  }

  if (!exists("server", envir = app_env, mode = "function", inherits = FALSE)) {
	stop("Boot doğrulaması başarısız: server fonksiyonu yüklenmedi.", call. = FALSE)
  }

  invisible(TRUE)
}

.env_flag_is_true <- function(value, default = FALSE) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  norm <- tolower(trimws(as.character(value[1])))
  if (!nzchar(norm)) {
    return(default)
  }

  if (norm %in% c("1", "true", "t", "yes", "y", "on")) {
    return(TRUE)
  }

  if (norm %in% c("0", "false", "f", "no", "n", "off")) {
    return(FALSE)
  }

  default
}

.normalize_mergen_port <- function(value, default = 8009L) {
  port <- suppressWarnings(as.integer(trimws(as.character(value[1]))))

  if (is.na(port) || port < 1L || port > 65535L) {
    return(as.integer(default))
  }

  as.integer(port)
}

# 5. Uygulamayı çalıştır.
create_mergen_app <- function() {
  validate_boot_state()

  shiny::shinyApp(
    ui = ui,
    server = server,
    onStart = function() {
      validate_boot_state()
      # İşlem-güvenli DB bağlantı havuzunu süreç ömrü boyunca BİR KEZ başlat.
      # Havuzlama varsayılan KAPALI; MERGEN_DB_POOL_ENABLED=TRUE değilse no-op'tur
      # (bulut/test/boot-smoke davranışı değişmez). Başlatma başarısızlığı boot'u
      # kırmaz (init_db_pool_once kendi içinde güvenli tryCatch kullanır).
      if (exists("init_db_pool_once", mode = "function", inherits = TRUE)) {
        try(init_db_pool_once("primary"), silent = TRUE)
      }
      # Uygulama durduğunda havuzu temiz biçimde kapat. shinyApp()'in onStop
      # parametresi yoktur; uygulama-seviyesi durdurma kancası onStart içinde
      # shiny::onStop() ile kaydedilir.
      if (exists("close_db_pool_once", mode = "function", inherits = TRUE)) {
        shiny::onStop(function() {
          try(close_db_pool_once(), silent = TRUE)
        })
      }
    }
  )
}

run_mergen_app <- function(
  host = Sys.getenv("MERGEN_HOST", "0.0.0.0"),
  port = Sys.getenv("MERGEN_PORT", "8009"),
  launch.browser = interactive(),
  quiet = TRUE
) {
  validate_boot_state()

  port <- .normalize_mergen_port(port)

  shiny::runApp(
    create_mergen_app(),
    host = host,
    port = port,
    launch.browser = launch.browser,
    quiet = quiet
  )
}

auto_run <- .env_flag_is_true(
  Sys.getenv("MERGEN_RUN_APP", if (interactive()) "true" else "false"),
  default = interactive()
)

if (isTRUE(auto_run)) {
  run_mergen_app()
}