# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_plugins.R
# Açıklama: Claude Code Plugin sistemi için CLI etkileşim fonksiyonları.
#           Plugin listeleme, kurulum, kaldırma, marketplace yönetimi ve
#           plugin bilgi ayrıştırma işlemlerini kapsar.
#           build_processx_command() ile aynı CLI çağırma desenini kullanır.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLI ÜZERİNDEN PLUGIN KOMUTLARI ÇALIŞTIRMA
# Tüm plugin işlemleri `claude` CLI'ın alt komutlarına dayanır.
# processx ile senkron çalıştırılır, sonuçlar JSON olarak ayrıştırılır.
# ------------------------------------------------------------------------------

#' Claude Code CLI üzerinden bir plugin komutunu senkron çalıştırır
#'
#' @param cli_path Claude Code CLI'ın çözümlenmiş yolu
#' @param plugin_args Plugin alt komutuna iletilecek argümanlar (karakter vektörü)
#' @param timeout_sec Zaman aşımı (saniye)
#' @return Liste: success (mantıksal), output (karakter), error (karakter)
run_plugin_command <- function(cli_path, plugin_args, timeout_sec = NULL) {
  if (is.null(timeout_sec)) {
    timeout_sec <- claude_code_plugins_config$operation_timeout
  }

  if (is.null(cli_path) || !nzchar(cli_path)) {
    return(list(
      success = FALSE,
      output  = "",
      error   = "Claude Code CLI yolu belirtilmedi."
    ))
  }

  tryCatch({
    komut <- build_processx_command(cli_path, plugin_args)

    proc <- processx::process$new(
      command = komut$command,
      args    = komut$args,
      env     = komut$env,
      wd      = komut$wd %||% tempdir(),
      stdout  = "|",
      stderr  = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )

    proc$wait(timeout = timeout_sec * 1000L)

    if (proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      return(list(
        success = FALSE,
        output  = "",
        error   = paste0("Plugin komutu zaman aşımına uğradı (", timeout_sec, "s).")
      ))
    }

    stdout_metin <- tryCatch(ensure_utf8(proc$read_all_output()), error = function(e) "")
    stderr_metin <- tryCatch(ensure_utf8(proc$read_all_error()),  error = function(e) "")
    cikis_kodu   <- proc$get_exit_status()

    if (identical(cikis_kodu, 0L)) {
      list(success = TRUE, output = trimws(stdout_metin), error = "")
    } else {
      list(
        success = FALSE,
        output  = trimws(stdout_metin),
        error   = trimws(stderr_metin)
      )
    }
  }, error = function(e) {
    list(
      success = FALSE,
      output  = "",
      error   = conditionMessage(e)
    )
  })
}

# ------------------------------------------------------------------------------
# YÜKLÜ PLUGIN LİSTELEME
# `claude plugin list` komutu ile mevcut pluginleri sorgular.
# ------------------------------------------------------------------------------

#' Yüklü pluginlerin listesini döndürür
#'
#' @param cli_path Claude Code CLI'ın çözümlenmiş yolu
#' @return Liste: success, plugins (data.frame veya liste), error
list_installed_plugins <- function(cli_path) {
  sonuc <- run_plugin_command(cli_path, c("plugin", "list", "--json"))

  if (!sonuc$success) {
    # JSON formatı desteklenmiyorsa düz metin formatında dene
    sonuc_duz <- run_plugin_command(cli_path, c("plugin", "list"))
    if (sonuc_duz$success) {
      return(parse_plugin_list_text(sonuc_duz$output))
    }
    return(list(success = FALSE, plugins = list(), error = sonuc$error))
  }

  # JSON çıktıyı ayrıştır
  tryCatch({
    plugin_veri <- jsonlite::fromJSON(sonuc$output, simplifyVector = FALSE)
    list(success = TRUE, plugins = plugin_veri, error = "")
  }, error = function(e) {
    # JSON ayrıştırma başarısız olursa düz metin olarak dene
    parse_plugin_list_text(sonuc$output)
  })
}

#' Düz metin plugin listesini ayrıştırır
#'
#' @param metin CLI'dan gelen düz metin çıktı
#' @return Liste: success, plugins, error
parse_plugin_list_text <- function(metin) {
  if (is.null(metin) || !nzchar(metin)) {
    return(list(success = TRUE, plugins = list(), error = ""))
  }

  satirlar <- strsplit(metin, "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[nzchar(trimws(satirlar))]

  # Başlık satırlarını atla
  satirlar <- satirlar[!grepl("^(Name|Plugin|---)", satirlar, ignore.case = TRUE)]

  plugins <- lapply(satirlar, function(satir) {
    parcalar <- trimws(strsplit(satir, "\\s{2,}")[[1]])
    if (length(parcalar) >= 1) {
      list(
        name        = parcalar[1],
        version     = if (length(parcalar) >= 2) parcalar[2] else "",
        description = if (length(parcalar) >= 3) parcalar[3] else "",
        enabled     = TRUE
      )
    } else {
      NULL
    }
  })

  plugins <- Filter(Negate(is.null), plugins)
  list(success = TRUE, plugins = plugins, error = "")
}

# ------------------------------------------------------------------------------
# PLUGIN KURULUM
# `claude plugin install <plugin>@<marketplace>` komutu ile kurulum yapar.
# ------------------------------------------------------------------------------

#' Bir plugin'i marketplace'ten kurar
#'
#' @param cli_path Claude Code CLI yolu
#' @param plugin_name Plugin adı (ör: "code-review")
#' @param marketplace_name Marketplace adı (boş ise varsayılan marketplace kullanılır)
#' @return Liste: success, output, error
install_plugin <- function(cli_path, plugin_name, marketplace_name = NULL) {
  if (!isTRUE(claude_code_plugins_config$allow_install)) {
    return(list(
      success = FALSE,
      output  = "",
      error   = "Plugin kurulumu yönetici tarafından devre dışı bırakılmıştır."
    ))
  }

  # Plugin spesifikasyonunu oluştur
  plugin_spec <- if (!is.null(marketplace_name) && nzchar(marketplace_name)) {
    paste0(plugin_name, "@", marketplace_name)
  } else {
    plugin_name
  }

  log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kuruluyor:", plugin_spec))
  sonuc <- run_plugin_command(cli_path, c("plugin", "install", plugin_spec))

  if (sonuc$success) {
    log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kuruldu:", plugin_spec))
  } else {
    log_warn(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kurulum hatası:",
                   plugin_spec, "-", sonuc$error))
  }

  sonuc
}

# ------------------------------------------------------------------------------
# PLUGIN KALDIRMA
# `claude plugin uninstall <plugin>` komutu ile kaldırır.
# ------------------------------------------------------------------------------

#' Bir plugin'i kaldırır
#'
#' @param cli_path Claude Code CLI yolu
#' @param plugin_name Plugin adı
#' @return Liste: success, output, error
uninstall_plugin <- function(cli_path, plugin_name) {
  if (!isTRUE(claude_code_plugins_config$allow_uninstall)) {
    return(list(
      success = FALSE,
      output  = "",
      error   = "Plugin kaldırma yönetici tarafından devre dışı bırakılmıştır."
    ))
  }

  log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kaldırılıyor:", plugin_name))
  sonuc <- run_plugin_command(cli_path, c("plugin", "uninstall", plugin_name))

  if (sonuc$success) {
    log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kaldırıldı:", plugin_name))
  } else {
    log_warn(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin kaldırma hatası:",
                   plugin_name, "-", sonuc$error))
  }

  sonuc
}

# ------------------------------------------------------------------------------
# MARKETPLACE YÖNETİMİ
# `claude plugin marketplace add/list` komutları ile marketplace ekler/listeler.
# ------------------------------------------------------------------------------

#' Kayıtlı marketplace'leri listeler
#'
#' @param cli_path Claude Code CLI yolu
#' @return Liste: success, marketplaces, error
list_marketplaces <- function(cli_path) {
  sonuc <- run_plugin_command(cli_path, c("plugin", "marketplace", "list"))

  if (!sonuc$success) {
    return(list(success = FALSE, marketplaces = list(), error = sonuc$error))
  }

  # Çıktıyı ayrıştır
  satirlar <- strsplit(sonuc$output, "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[nzchar(trimws(satirlar))]
  satirlar <- satirlar[!grepl("^(Name|Marketplace|---)", satirlar, ignore.case = TRUE)]

  marketplaces <- lapply(satirlar, function(satir) {
    parcalar <- trimws(strsplit(satir, "\\s{2,}")[[1]])
    list(
      name = if (length(parcalar) >= 1) parcalar[1] else "",
      url  = if (length(parcalar) >= 2) parcalar[2] else ""
    )
  })

  marketplaces <- Filter(function(m) nzchar(m$name), marketplaces)
  list(success = TRUE, marketplaces = marketplaces, error = "")
}

#' Yeni bir marketplace ekler
#'
#' @param cli_path Claude Code CLI yolu
#' @param marketplace_url Marketplace URL'si (git repo adresi)
#' @return Liste: success, output, error
add_marketplace <- function(cli_path, marketplace_url) {
  if (is.null(marketplace_url) || !nzchar(marketplace_url)) {
    return(list(success = FALSE, output = "", error = "Marketplace URL'si belirtilmedi."))
  }

  log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Marketplace ekleniyor:", marketplace_url))
  sonuc <- run_plugin_command(cli_path, c("plugin", "marketplace", "add", marketplace_url))

  if (sonuc$success) {
    log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Marketplace eklendi:", marketplace_url))
  } else {
    log_warn(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Marketplace ekleme hatası:",
                   marketplace_url, "-", sonuc$error))
  }

  sonuc
}

# ------------------------------------------------------------------------------
# PLUGIN DETAY BİLGİSİ
# Bir plugin hakkında detaylı bilgi döndürür.
# ------------------------------------------------------------------------------

#' Plugin hakkında detaylı bilgi alır
#'
#' @param cli_path Claude Code CLI yolu
#' @param plugin_name Plugin adı
#' @return Liste: success, info (plugin detayları), error
get_plugin_info <- function(cli_path, plugin_name) {
  # Önce JSON formatında dene
  sonuc <- run_plugin_command(cli_path, c("plugin", "info", plugin_name, "--json"))

  if (sonuc$success && nzchar(sonuc$output)) {
    tryCatch({
      bilgi <- jsonlite::fromJSON(sonuc$output, simplifyVector = FALSE)
      return(list(success = TRUE, info = bilgi, error = ""))
    }, error = function(e) NULL)
  }

  # JSON yoksa düz metin formatını dene
  sonuc_duz <- run_plugin_command(cli_path, c("plugin", "info", plugin_name))
  if (sonuc_duz$success) {
    return(list(
      success = TRUE,
      info    = list(name = plugin_name, raw_output = sonuc_duz$output),
      error   = ""
    ))
  }

  list(success = FALSE, info = list(), error = sonuc_duz$error)
}

# ------------------------------------------------------------------------------
# PLUGIN ETKİNLEŞTİRME / DEVRE DIŞI BIRAKMA
# Plugin'i aktif/pasif yapma işlemleri.
# ------------------------------------------------------------------------------

#' Bir plugin'i etkinleştirir veya devre dışı bırakır
#'
#' @param cli_path Claude Code CLI yolu
#' @param plugin_name Plugin adı
#' @param enable TRUE = etkinleştir, FALSE = devre dışı bırak
#' @return Liste: success, output, error
toggle_plugin <- function(cli_path, plugin_name, enable = TRUE) {
  if (!isTRUE(claude_code_plugins_config$allow_toggle)) {
    return(list(
      success = FALSE,
      output  = "",
      error   = "Plugin etkinleştirme/devre dışı bırakma yönetici tarafından kısıtlanmıştır."
    ))
  }

  alt_komut <- if (isTRUE(enable)) "enable" else "disable"
  log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin", alt_komut, ":", plugin_name))

  sonuc <- run_plugin_command(cli_path, c("plugin", alt_komut, plugin_name))

  if (sonuc$success) {
    log_info(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin", alt_komut, "başarılı:", plugin_name))
  } else {
    log_warn(paste(CLAUDE_CODE_PLUGINS_LOG_PREFIX, "Plugin", alt_komut, "hatası:",
                   plugin_name, "-", sonuc$error))
  }

  sonuc
}

# ------------------------------------------------------------------------------
# MARKETPLACE'TEN PLUGIN KEŞFETME
# Marketplace'teki mevcut pluginleri keşfeder.
# ------------------------------------------------------------------------------

#' Marketplace'teki pluginleri keşfeder
#'
#' @param cli_path Claude Code CLI yolu
#' @param search_term Arama terimi (opsiyonel)
#' @return Liste: success, plugins, error
discover_plugins <- function(cli_path, search_term = NULL) {
  args <- c("plugin", "discover")
  if (!is.null(search_term) && nzchar(search_term)) {
    args <- c(args, "--search", search_term)
  }

  sonuc <- run_plugin_command(cli_path, args)

  if (!sonuc$success) {
    # Discover komutu yoksa listeyi düz çıktıdan ayrıştır
    return(list(success = FALSE, plugins = list(), error = sonuc$error))
  }

  # Çıktıyı ayrıştırmaya çalış
  tryCatch({
    plugin_veri <- jsonlite::fromJSON(sonuc$output, simplifyVector = FALSE)
    list(success = TRUE, plugins = plugin_veri, error = "")
  }, error = function(e) {
    parse_plugin_list_text(sonuc$output)
  })
}

# ------------------------------------------------------------------------------
# YEREL PLUGIN KLASÖRÜ TARAMA
# bilge_yolac_plugins/ dizinindeki yerel pluginleri tarar.
# ------------------------------------------------------------------------------

#' Yerel plugin dizinini tarar ve mevcut pluginleri listeler
#'
#' @param plugins_dir Plugin dizini yolu (varsayılan: bilge_yolac_plugins/)
#' @return Liste: success, plugins (liste), error
scan_local_plugins <- function(plugins_dir = NULL) {
  if (is.null(plugins_dir)) {
    # Uygulama kök dizininden bilge_yolac_plugins/ dizinini bul
    kok_dizin <- getwd()
    plugins_dir <- file.path(kok_dizin, "bilge_yolac_plugins")
  }

  if (!dir.exists(plugins_dir)) {
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
        path        = dizin,
        local       = TRUE,
        components  = bilesenler
      )
    })

    plugins <- Filter(Negate(is.null), plugins)
    list(success = TRUE, plugins = plugins, error = "")
  }, error = function(e) {
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

  # Kancalar (hooks/ dizini veya hooks alanı plugin.json'da)
  if (dir.exists(file.path(plugin_dir, "hooks"))) {
    bilesenler <- c(bilesenler, "hooks")
  }

  # MCP Sunucuları (mcp/ dizini)
  if (dir.exists(file.path(plugin_dir, "mcp"))) {
    bilesenler <- c(bilesenler, "mcp_servers")
  }

  bilesenler
}
