# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Aciklama: Claude Code CLI ile etkilesim icin arka plan isci fonksiyonlari.
#           processx paketi ile alt surec yonetimi, CLI otomatik tespiti,
#           settings.json okuma, oturum yonetimi ve dosya sistemi islemleri.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLI YOLU OTOMATIK TESPITI
# Windows'ta npm global kurulumlar .cmd uzantili dosya olusturur.
# processx bu uzantiyi kendisi cozemez, acikca belirtilmelidir.
# ------------------------------------------------------------------------------

#' Claude Code CLI yolunu otomatik tespit eder
#'
#' @param kullanici_yolu Kullanicinin elle girdigi yol (bos olabilir)
#' @return Gecerli CLI yolu veya NULL (bulunamadiysa)
resolve_claude_cli_path <- function(kullanici_yolu = "") {
  # Kullanici bir yol verdiyse oncelikle onu dene

  if (nzchar(kullanici_yolu)) {
    # Windows'ta .cmd uzantisi yoksa ekle
    if (.Platform$OS.type == "windows" && !grepl("\\.(cmd|exe|bat)$", kullanici_yolu, ignore.case = TRUE)) {
      cmd_yolu <- paste0(kullanici_yolu, ".cmd")
      if (file.exists(cmd_yolu)) {
        return(normalizePath(cmd_yolu, winslash = "/"))
      }
    }
    # Yol dogrudan mevcut mu?
    if (file.exists(kullanici_yolu)) {
      return(normalizePath(kullanici_yolu, winslash = "/"))
    }
  }

  # Otomatik tespit: Sys.which ile PATH'te ara
  if (.Platform$OS.type == "windows") {
    # Windows'ta claude.cmd'yi ara
    cmd_yolu <- Sys.which("claude.cmd")
    if (nzchar(cmd_yolu)) return(normalizePath(cmd_yolu, winslash = "/"))

    # Tipik npm global kurulum dizinini kontrol et
    npm_dizini <- file.path(Sys.getenv("APPDATA"), "npm")
    npm_claude <- file.path(npm_dizini, "claude.cmd")
    if (file.exists(npm_claude)) return(normalizePath(npm_claude, winslash = "/"))
  } else {
    # Linux/macOS: PATH'te claude'u ara
    cli_yolu <- Sys.which("claude")
    if (nzchar(cli_yolu)) return(normalizePath(cli_yolu))
  }

  return(NULL)
}

# ------------------------------------------------------------------------------
# SETTINGS.JSON OKUMA
# Claude Code'un kendi ayar dosyasini okuyarak model listesini ve
# varsayilan modeli alir. Bu dosya ~/.claude/settings.json konumundadir.
# ------------------------------------------------------------------------------

#' Claude Code settings.json dosyasini okur
#'
#' @return Liste: models (model isimleri), default_model, base_url, raw (ham veri)
read_claude_settings_json <- function() {
  # settings.json konumu
  if (.Platform$OS.type == "windows") {
    ayar_yolu <- file.path(Sys.getenv("USERPROFILE"), ".claude", "settings.json")
  } else {
    ayar_yolu <- file.path(Sys.getenv("HOME"), ".claude", "settings.json")
  }

  sonuc <- list(
    models = character(0),
    default_model = "",
    base_url = "",
    raw = NULL,
    dosya_yolu = ayar_yolu
  )

  if (!file.exists(ayar_yolu)) {
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json bulunamadi:", ayar_yolu))
    return(sonuc)
  }

  tryCatch({
    icerik <- jsonlite::fromJSON(ayar_yolu, simplifyVector = FALSE)
    sonuc$raw <- icerik

    # Varsayilan model
    if (!is.null(icerik$model) && nzchar(icerik$model)) {
      sonuc$default_model <- icerik$model
    }

    # Ortam degiskenleri icerisindeki modelleri topla
    model_listesi <- c()

    if (!is.null(icerik$env)) {
      env <- icerik$env

      # ANTHROPIC_BASE_URL
      if (!is.null(env$ANTHROPIC_BASE_URL)) {
        sonuc$base_url <- env$ANTHROPIC_BASE_URL
      }

      # ANTHROPIC_DEFAULT_*_MODEL degiskenlerini tara
      model_anahtarlari <- grep("^ANTHROPIC_DEFAULT_.*_MODEL$", names(env), value = TRUE)
      for (anahtar in model_anahtarlari) {
        model_adi <- env[[anahtar]]
        if (!is.null(model_adi) && nzchar(model_adi)) {
          # Anahtar adindan etiketi cikar (OPUS, SONNET, HAIKU, vb.)
          etiket <- gsub("^ANTHROPIC_DEFAULT_(.+)_MODEL$", "\\1", anahtar)
          model_listesi <- c(model_listesi, setNames(model_adi, etiket))
        }
      }
    }

    # Varsayilan model listeye dahil degilse ekle
    if (nzchar(sonuc$default_model) && !(sonuc$default_model %in% model_listesi)) {
      model_listesi <- c(setNames(sonuc$default_model, "VARSAYILAN"), model_listesi)
    }

    sonuc$models <- model_listesi

    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okundu.",
                   length(model_listesi), "model bulundu.",
                   "Varsayilan:", sonuc$default_model))

  }, error = function(e) {
    log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okunamadi:", conditionMessage(e)))
  })

  return(sonuc)
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI CALISTIRMA
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu arka planda calistir
#'
#' @param prompt Kullanicinin gonderdigi komut/soru metni
#' @param workdir Calisma dizini (proje klasoru)
#' @param model Kullanilacak model adi (bos ise varsayilan kullanilir)
#' @param timeout_sec Zaman asimi suresi (saniye)
#' @param session_id Oturum kimligi (izolasyon icin)
#' @param cli_path Claude Code CLI calistirilabilir dosya yolu
#' @return Liste: success (mantiksal), output (metin), error (hata metni), duration (sure)
run_claude_code <- function(prompt,
                            workdir = getwd(),
                            model = NULL,
                            timeout_sec = 300L,
                            session_id = NULL,
                            cli_path = NULL) {

  baslangic <- Sys.time()

  # Girdi dogrulamasi
  if (!nzchar(trimws(prompt))) {
    return(list(
      success = FALSE,
      output = "",
      error = "Komut metni bos olamaz.",
      duration = 0
    ))
  }

  # CLI yolunu cozumle (verilmediyse otomatik tespit et)
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  }
  if (is.null(cli_path)) {
    return(list(
      success = FALSE,
      output = "",
      error = "Claude Code CLI bulunamadi. Lutfen CLI yolunu kontrol edin.",
      duration = 0
    ))
  }

  # Calisma dizini kontrolu
  if (!dir.exists(workdir)) {
    return(list(
      success = FALSE,
      output = "",
      error = paste0("Calisma dizini bulunamadi: ", workdir),
      duration = 0
    ))
  }

  # CLI argumanlari olustur
  # --print: interaktif olmayan mod, ciktiyi dogrudan yazdir
  # --output-format text: duz metin cikti
  args <- c(
    "--print",
    "--output-format", "text"
  )

  # Model belirtilmisse ekle
  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  # Komutu (prompt) arguman olarak ekle
  args <- c(args, prompt)

  # processx ile calistir
  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI calistiriliyor:",
                   cli_path, paste(args[1:min(3, length(args))], collapse = " "), "..."))

    result <- processx::run(
      command = cli_path,
      args = args,
      wd = workdir,
      timeout = timeout_sec,
      error_on_status = FALSE,
      stderr_to_stdout = FALSE,
      env = c("current", TERM = "dumb")
    )

    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

    if (result$status == 0) {
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Basarili - Sure:",
                     round(sure, 1), "sn"))
      list(
        success = TRUE,
        output = result$stdout,
        error = "",
        duration = round(sure, 1)
      )
    } else {
      hata_mesaji <- if (nzchar(result$stderr)) result$stderr else result$stdout
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Hata kodu:", result$status,
                     "- Mesaj:", substr(hata_mesaji, 1, 200)))
      list(
        success = FALSE,
        output = result$stdout,
        error = hata_mesaji,
        duration = round(sure, 1)
      )
    }

  }, error = function(e) {
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
    hata_metni <- conditionMessage(e)

    # Zaman asimi kontrolu
    if (grepl("timeout|timed out", hata_metni, ignore.case = TRUE)) {
      log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Zaman asimi:", timeout_sec, "sn"))
      return(list(
        success = FALSE,
        output = "",
        error = paste0("Islem zaman asimina ugradi (", timeout_sec, " saniye). ",
                       "Daha kisa bir komut deneyin veya zaman asimi suresini artirin."),
        duration = round(sure, 1)
      ))
    }

    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI hatasi:", hata_metni))
    list(
      success = FALSE,
      output = "",
      error = paste0("Claude Code calistirilirken hata olustu: ", hata_metni),
      duration = round(sure, 1)
    )
  })
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI DURUM KONTROLU
# ------------------------------------------------------------------------------

#' Claude Code CLI'nin kurulu ve erisilebilir olup olmadigini kontrol eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @return Liste: installed (mantiksal), version (surum metni), path (bulunan yol), error (hata)
check_claude_code_status <- function(cli_path = NULL) {
  # CLI yolunu cozumle
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  } else {
    cli_path <- resolve_claude_cli_path(cli_path)
  }

  if (is.null(cli_path)) {
    return(list(
      installed = FALSE,
      version = "",
      path = "",
      error = "Claude Code CLI bulunamadi. npm ile kurulu oldugundan emin olun."
    ))
  }

  tryCatch({
    result <- processx::run(
      command = cli_path,
      args = c("--version"),
      timeout = 10,
      error_on_status = FALSE,
      stderr_to_stdout = TRUE
    )

    if (result$status == 0) {
      surum <- trimws(result$stdout)
      list(installed = TRUE, version = surum, path = cli_path, error = "")
    } else {
      list(installed = FALSE, version = "", path = cli_path, error = result$stdout)
    }
  }, error = function(e) {
    list(
      installed = FALSE,
      version = "",
      path = cli_path,
      error = paste0("Claude Code calistirilamadi: ", conditionMessage(e))
    )
  })
}

# ------------------------------------------------------------------------------
# BAGLANTI TESTi
# ------------------------------------------------------------------------------

#' API baglantisini test eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @param model Test edilecek model (opsiyonel)
#' @param workdir Calisma dizini
#' @return Liste: success, message, details
test_claude_code_connection <- function(cli_path = NULL,
                                        model = NULL,
                                        workdir = tempdir()) {
  # Oncelikle CLI kontrolu yap
  durum <- check_claude_code_status(cli_path)
  if (!durum$installed) {
    return(list(
      success = FALSE,
      message = "Claude Code CLI bulunamadi veya erisilemez.",
      details = durum$error
    ))
  }

  # Basit bir test komutu gonder (kisa ve hizli)
  test_sonuc <- run_claude_code(
    prompt = "Sadece 'OK' yaz, baska bir sey yazma.",
    workdir = workdir,
    model = model,
    timeout_sec = 60L,
    cli_path = durum$path
  )

  if (test_sonuc$success) {
    list(
      success = TRUE,
      message = paste0("Baglanti basarili! Claude Code v", durum$version),
      details = paste0("CLI: ", durum$path, " | Yanit suresi: ", test_sonuc$duration, " sn")
    )
  } else {
    list(
      success = FALSE,
      message = "Claude Code CLI calisiyor ancak API baglantisi basarisiz.",
      details = test_sonuc$error
    )
  }
}

# ------------------------------------------------------------------------------
# KULLANICI CALISMA DiZiNi YONETIMI
# ------------------------------------------------------------------------------

#' Kullanici icin izole bir calisma alani olusturur veya mevcut olani dondurur
#'
#' @param user_id Kullanici kimligi
#' @param base_dir Temel dizin (varsayilan: tempdir altinda)
#' @return Calisma dizini yolu
get_user_workspace <- function(user_id, base_dir = NULL) {
  if (is.null(base_dir) || !nzchar(base_dir)) {
    base_dir <- file.path(tempdir(), "claude_code_workspaces")
  }

  user_dir <- file.path(base_dir, paste0("user_", user_id))

  if (!dir.exists(user_dir)) {
    dir.create(user_dir, recursive = TRUE, showWarnings = FALSE)
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Kullanici calisma alani olusturuldu:",
                   user_dir))
  }

  return(normalizePath(user_dir, mustWork = FALSE))
}

# ------------------------------------------------------------------------------
# DIZIN LISTELEME
# ------------------------------------------------------------------------------

#' Belirtilen dizindeki dosya ve klasorleri listeler
#'
#' @param path Dizin yolu
#' @param max_items Maksimum oge sayisi
#' @return Dosya/klasor bilgileri listesi
list_directory_contents <- function(path, max_items = 100L) {
  if (!dir.exists(path)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadi: ", path)
    ))
  }

  tryCatch({
    dosyalar <- list.files(path, full.names = TRUE, all.files = FALSE)
    dosyalar <- head(dosyalar, max_items)

    ogeler <- lapply(dosyalar, function(f) {
      bilgi <- file.info(f)
      list(
        ad = basename(f),
        yol = f,
        tip = if (bilgi$isdir) "klasor" else "dosya",
        boyut = if (!bilgi$isdir) bilgi$size else NA_real_,
        degistirilme = as.character(bilgi$mtime)
      )
    })

    list(
      success = TRUE,
      items = ogeler,
      error = "",
      toplam = length(list.files(path, all.files = FALSE))
    )
  }, error = function(e) {
    list(
      success = FALSE,
      items = list(),
      error = conditionMessage(e)
    )
  })
}

# ------------------------------------------------------------------------------
# CIKTI BICIMLENDIRME
# ------------------------------------------------------------------------------

#' Claude Code ciktisini HTML formatina donusturur
#'
#' @param output Ham cikti metni
#' @return HTML formatli metin
format_claude_code_output <- function(output) {
  if (is.null(output) || !nzchar(output)) {
    return("")
  }

  # Markdown'i HTML'e donustur (commonmark paketi ile)
  tryCatch({
    html <- commonmark::markdown_html(output, extensions = TRUE)
    return(html)
  }, error = function(e) {
    # Donusum basarisiz olursa ham metni dondur
    escaped <- htmltools::htmlEscape(output)
    return(paste0("<pre>", escaped, "</pre>"))
  })
}

# ------------------------------------------------------------------------------
# RASTGELE DUSUNME MESAJI SEC
# ------------------------------------------------------------------------------

#' Aktif karaktere gore rastgele bir dusunme mesaji dondurur
#'
#' @param karakter_id Aktif karakter kimligi (mergen, ulgen, kayra, erlik, umay)
#' @return Dusunme mesaji metni
get_thinking_message <- function(karakter_id = "mergen") {
  # Karakter mesajlarini al
  karakter_mesajlari <- claude_code_thinking_messages[[karakter_id]]

  # Genel mesajlarla birlestir
  tum_mesajlar <- c(
    claude_code_thinking_messages[["genel"]],
    if (!is.null(karakter_mesajlari)) karakter_mesajlari
  )

  # Rastgele sec
  sample(tum_mesajlar, 1)
}
