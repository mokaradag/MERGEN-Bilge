# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_plugins.R
# Açıklama: Claude Code Plugin sistemi için yerel tarama fonksiyonları.
#           bilge_yolac_plugins/ dizinindeki gömülü pluginleri tespit eder,
#           plugin.json okur, bileşen yapısını analiz eder.
#           İnternet veya CLI bağımlılığı yoktur.
# ==============================================================================

# ------------------------------------------------------------------------------
# YEREL PLUGIN KLASÖRÜ TARAMA
# bilge_yolac_plugins/ dizinindeki yerel pluginleri tarar.
# Uygulama kök dizini app.R'nin konumundan çözümlenir.
# ------------------------------------------------------------------------------

#' Uygulama kök dizinini güvenli şekilde çözümler
#'
#' app.R dosyasının bulunduğu dizini bulur. Shiny çalışma zamanında
#' getwd() her zaman güvenilir olmayabilir, bu yüzden birden fazla
#' yedek strateji uygulanır.
#'
#' @return Uygulama kök dizini yolu (karakter)
resolve_app_root <- function() {
  # Strateji 1: Shiny'nin kendi app dizini (varsa)
  shiny_dir <- tryCatch({
    app <- shiny::getShinyOption("appDir")
    if (!is.null(app) && nzchar(app) && dir.exists(app)) return(app)
    NULL
  }, error = function(e) NULL)
  if (!is.null(shiny_dir)) return(shiny_dir)

  # Strateji 2: Bilinen bir dosya ile doğrulanan getwd()
  wd <- getwd()
  if (file.exists(file.path(wd, "app.R")) || file.exists(file.path(wd, "global.R"))) {
    return(wd)
  }

  # Strateji 3: Bu dosyanın (helpers_claude_code_plugins.R) kendi konumundan türet
  # R/ dizininin bir üst dizini uygulama köküdür
  bu_dosya <- tryCatch(
    normalizePath(sys.frame(1)$ofile %||% "", winslash = "/", mustWork = FALSE),
    error = function(e) ""
  )
  if (nzchar(bu_dosya) && grepl("/R/", bu_dosya)) {
    kok <- dirname(dirname(bu_dosya))
    if (dir.exists(kok)) return(kok)
  }

  # Son çare: getwd() kullan
  wd
}

#' Yerel plugin dizinini tarar ve mevcut pluginleri listeler
#'
#' @param plugins_dir Plugin dizini yolu (varsayılan: bilge_yolac_plugins/)
#' @return Liste: success, plugins (liste), error
scan_local_plugins <- function(plugins_dir = NULL) {
  if (is.null(plugins_dir)) {
    kok_dizin <- resolve_app_root()
    plugins_dir <- file.path(kok_dizin, "bilge_yolac_plugins")
  }

  if (!dir.exists(plugins_dir)) {
    log_info(paste(
      CLAUDE_CODE_PLUGINS_LOG_PREFIX,
      "Plugin dizini bulunamadı:", plugins_dir
    ))
    return(list(success = TRUE, plugins = list(), error = ""))
  }

  tryCatch({
    alt_dizinler <- list.dirs(plugins_dir, full.names = TRUE, recursive = FALSE)

    plugins <- lapply(alt_dizinler, function(dizin) {
      plugin_json <- file.path(dizin, "plugin.json")
      if (!file.exists(plugin_json)) return(NULL)

      bilgi <- tryCatch({
        jsonlite::fromJSON(plugin_json, simplifyVector = FALSE)
      }, error = function(e) {
        list(name = basename(dizin))
      })

      # Bileşenleri tespit et
      bilesenler <- detect_plugin_components(dizin)

      list(
        name        = bilgi$name %||% basename(dizin),
        description = bilgi$description %||% "",
        version     = bilgi$version %||% "",
        path        = normalizePath(dizin, winslash = "/", mustWork = FALSE),
        local       = TRUE,
        components  = bilesenler
      )
    })

    plugins <- Filter(Negate(is.null), plugins)

    log_info(paste(
      CLAUDE_CODE_PLUGINS_LOG_PREFIX,
      length(plugins), "yerel plugin bulundu:", plugins_dir
    ))

    list(success = TRUE, plugins = plugins, error = "")
  }, error = function(e) {
    log_warn(paste(
      CLAUDE_CODE_PLUGINS_LOG_PREFIX,
      "Plugin tarama hatası:", conditionMessage(e)
    ))
    list(success = FALSE, plugins = list(), error = conditionMessage(e))
  })
}

#' Plugin dizinindeki bileşenleri tespit eder
#'
#' @param plugin_dir Plugin'in kök dizini
#' @return Bileşen adlarının karakter vektörü
detect_plugin_components <- function(plugin_dir) {
  bilesenler <- character(0)

  # Komutlar (commands/ dizini)
  if (dir.exists(file.path(plugin_dir, "commands"))) {
    bilesenler <- c(bilesenler, "commands")
  }

  # Ajanlar (agents/ dizini)
  if (dir.exists(file.path(plugin_dir, "agents"))) {
    bilesenler <- c(bilesenler, "agents")
  }

  # Yetenekler (skills/ dizini)
  if (dir.exists(file.path(plugin_dir, "skills"))) {
    bilesenler <- c(bilesenler, "skills")
  }

  # Kancalar (hooks/ dizini)
  if (dir.exists(file.path(plugin_dir, "hooks"))) {
    bilesenler <- c(bilesenler, "hooks")
  }

  # MCP Sunucuları (mcp/ dizini)
  if (dir.exists(file.path(plugin_dir, "mcp"))) {
    bilesenler <- c(bilesenler, "mcp_servers")
  }

  bilesenler
}
