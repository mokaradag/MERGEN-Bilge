# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Açıklama: Claude Code CLI ile etkileşim için arka plan işçi fonksiyonları.
#           processx süreç/komut/UTF-8/JSON çıktı yardımcıları
#           R/helpers_claude_code_process.R içindedir. Model/settings yardımcıları
#           R/helpers_claude_code_model_config.R içindedir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI ÇALIŞTIRMA (JSON ÇIKTI DESTEKLİ)
# --output-format json ile araç kullanımı ve kabuk komutlarını ayrıştırır
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu arka planda çalıştır
#'
#' @param prompt Kullanıcının gönderdiği komut/soru metni
#' @param workdir Çalışma dizini (proje klasörü)
#' @param model Kullanılacak model adı (boş ise varsayılan kullanılır)
#' @param timeout_sec Zaman aşımı süresi (saniye)
#' @param session_id Oturum kimliği (izolasyon için)
#' @param cli_path Claude Code CLI çalıştırılabilir dosya yolu
#' @return Liste: success, output, error, duration, tool_uses (araç kullanımları)
run_claude_code <- function(prompt,
                            workdir = getwd(),
                            model = NULL,
                            timeout_sec = 300L,
                            session_id = NULL,
                            cli_path = NULL) {

  baslangic <- Sys.time()

  # Girdi doğrulaması
  if (!nzchar(trimws(prompt))) {
    return(list(
      success = FALSE,
      output = "",
      error = "Komut metni boş olamaz.",
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  # CLI yolunu çözümle (verilmediyse otomatik tespit et)
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  }
  if (is.null(cli_path)) {
    return(list(
      success = FALSE,
      output = "",
      error = "Claude Code CLI bulunamadı. Lütfen CLI yolunu kontrol edin.",
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  # Çalışma dizini kontrolü
  workdir_policy <- cc_policy_validate_workdir(
    workdir,
    allow_system_temp = TRUE
  )
  if (!isTRUE(workdir_policy$ok)) {
    return(list(
      success = FALSE,
      output = "",
      error = workdir_policy$error,
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }
  workdir <- workdir_policy$path

  # CLI argümanları merkezi güvenlik ilkesinden oluştur
  args <- cc_policy_build_cli_args(
    prompt = prompt,
    output_format = "json",
    model = model,
    session_id = session_id
  )

  komut <- build_processx_command(cli_path, args, workdir = workdir)

  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI çalıştırılıyor:",
                   cli_path, paste(args[1:min(3, length(args))], collapse = " "), "..."))

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = komut$wd %||% workdir,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )

    proc$wait(timeout = timeout_sec * 1000)

    if (proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
      log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Zaman aşımı:", timeout_sec, "sn"))
      return(list(
        success = FALSE,
        output = "",
        error = paste0(
          "İşlem zaman aşımına uğradı (", timeout_sec, " saniye). ",
          "Daha kısa bir komut deneyin veya zaman aşımı süresini artırın."
        ),
        duration = round(sure, 1),
        tool_uses = list(),
        session_id = NULL
      ))
    }

    stdout_metin <- ensure_utf8(proc$read_all_output())
    stderr_metin <- ensure_utf8(proc$read_all_error())
    cikis_kodu <- proc$get_exit_status()

    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

    if (identical(cikis_kodu, 0L)) {
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Başarılı - Süre:",
                     round(sure, 1), "sn"))

      ayristirma <- parse_claude_code_json_output(stdout_metin)

      list(
        success = TRUE,
        output = ayristirma$text_output,
        error = "",
        duration = round(sure, 1),
        tool_uses = ayristirma$tool_uses,
        session_id = ayristirma$session_id
      )
    } else {
      hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else stdout_metin
      temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Hata kodu:", cikis_kodu,
                     "- Mesaj:", temiz_log))

      list(
        success = FALSE,
        output = stdout_metin,
        error = hata_mesaji,
        duration = round(sure, 1),
        tool_uses = list(),
        session_id = NULL
      )
    }

  }, error = function(e) {
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
    hata_metni <- conditionMessage(e)

    temiz_hata <- gsub("[{}]", "", hata_metni)
    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI hatası:", temiz_hata))

    list(
      success = FALSE,
      output = "",
      error = paste0("Claude Code çalıştırılırken hata oluştu: ", hata_metni),
      duration = round(sure, 1),
      tool_uses = list(),
      session_id = NULL
    )
  })
}

#' Claude Code CLI'nin kurulu ve erişilebilir olup olmadığını kontrol eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @return Liste: installed (mantıksal), version (sürüm metni), path (bulunan yol), error (hata)
check_claude_code_status <- function(cli_path = NULL, workdir = NULL) {
  # CLI yolunu çözümle
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
      error = "Claude Code CLI bulunamadı. npm ile kurulu olduğundan emin olun."
    ))
  }

  tryCatch({
    # Windows UNC yolundan çalışırken cmd.exe hata verdiği için
    # durum kontrolünde güvenli yerel bir çalışma dizini kullan
    komut <- build_processx_command(cli_path, c("--version"), workdir = workdir)
    guvenli_wd <- get_safe_claude_cli_workdir(workdir)

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = komut$wd %||% guvenli_wd,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )
	
    proc$wait(timeout = 10000)

    if (proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      return(list(installed = FALSE, version = "", path = cli_path,
                  error = "CLI zaman aşımına uğradı"))
    }

    # Windows'ta processx yerel kodlama kullanır; UTF-8'e dönüştür
    stdout_metin <- ensure_utf8(proc$read_all_output())
    cikis_kodu <- proc$get_exit_status()

    if (identical(cikis_kodu, 0L)) {
      surum <- trimws(stdout_metin)
      list(installed = TRUE, version = surum, path = cli_path, error = "")
    } else {
      stderr_metin <- ensure_utf8(proc$read_all_error())
      hata_detay <- paste0(
        "Çıkış kodu: ", cikis_kodu,
        " | stdout: ", substr(stdout_metin, 1, 200),
        " | stderr: ", substr(stderr_metin, 1, 200)
      )
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "CLI durum hatası:", gsub("[{}]", "", hata_detay)))
      list(installed = FALSE, version = "", path = cli_path, error = hata_detay)
    }
  }, error = function(e) {
    hata_metni <- conditionMessage(e)
    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI başlatma hatası:",
                    gsub("[{}]", "", hata_metni), "| Yol:", cli_path %||% "NULL"))
    list(
      installed = FALSE,
      version = "",
      path = cli_path,
      error = paste0("Claude Code çalıştırılamadı: ", hata_metni)
    )
  })
}

# ------------------------------------------------------------------------------
# BAĞLANTI TESTİ
# ------------------------------------------------------------------------------

#' API bağlantısını test eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @param model Test edilecek model (opsiyonel)
#' @param workdir Çalışma dizini
#' @return Liste: success, message, details
test_claude_code_connection <- function(cli_path = NULL,
                                        model = NULL,
                                        workdir = tempdir()) {
  # Öncelikle CLI kontrolü yap
  durum <- check_claude_code_status(cli_path, workdir = workdir)
  if (!durum$installed) {
    return(list(
      success = FALSE,
      message = "Claude Code CLI bulunamadı veya erişilemez.",
      details = durum$error
    ))
  }

  # Basit bir test komutu gönder (kısa ve hızlı)
  test_sonuc <- run_claude_code(
    prompt = "Sadece 'OK' yaz, başka bir şey yazma.",
    workdir = workdir,
    model = model,
    timeout_sec = 60L,
    cli_path = durum$path
  )

  if (test_sonuc$success) {
    list(
      success = TRUE,
      message = paste0("Bağlantı başarılı! Claude Code v", durum$version),
      details = paste0("CLI: ", durum$path, " | Yanıt süresi: ", test_sonuc$duration, " sn")
    )
  } else {
    list(
      success = FALSE,
      message = "Claude Code CLI çalışıyor ancak API bağlantısı başarısız.",
      details = test_sonuc$error
    )
  }
}

# ------------------------------------------------------------------------------
# KULLANICI ÇALIŞMA DİZİNİ YÖNETİMİ
# ------------------------------------------------------------------------------
# Kullanıcı çalışma alanı ve Windows/UNC/Unicode runtime workdir aynalama
# yardımcıları R/helpers_claude_code_runtime_workdir.R dosyasına taşınmıştır.

# ------------------------------------------------------------------------------
# DİZİN LİSTELEME
# ------------------------------------------------------------------------------
# Dizin listeleme ve görünen ad çözümleme yardımcıları
# R/helpers_claude_code_directory_listing.R dosyasına taşınmıştır.

# ------------------------------------------------------------------------------
# ÇIKTI BİÇİMLENDİRME
# ------------------------------------------------------------------------------

#' Claude Code çıktısını HTML formatına dönüştürür
#'
#' @param output Ham çıktı metni
#' @return HTML formatlı metin
format_claude_code_output <- function(output) {
  if (is.null(output) || !nzchar(output)) {
    return("")
  }

  # Markdown'ı HTML'e dönüştür (commonmark paketi ile)
  # NOT: Mojibake düzeltmesi JavaScript tarafında yapılır (fixHtmlMojibake)
  tryCatch({
    html <- commonmark::markdown_html(output, extensions = TRUE)
    return(html)
  }, error = function(e) {
    # Dönüşüm başarısız olursa ham metni döndür
    escaped <- htmltools::htmlEscape(output)
    return(paste0("<pre>", escaped, "</pre>"))
  })
}

# ------------------------------------------------------------------------------
# ARAÇ KULLANIMI HTML BİÇİMLENDİRME
# Araç kullanımlarını (bash, dosya okuma/yazma) okunabilir HTML bloklarına çevirir
# ------------------------------------------------------------------------------

#' Araç kullanımlarını HTML formatına dönüştürür
#'
#' @param tool_uses Araç kullanımları listesi
#' @return HTML formatlı metin
format_tool_uses_html <- function(tool_uses) {
  if (length(tool_uses) == 0) return("")

  html_parcalari <- lapply(tool_uses, function(arac) {
    arac_adi <- arac$name %||% "bilinmeyen"
    girdi <- arac$input %||% list()
    sonuc_metni <- arac$result %||% ""

    # Araç türüne göre ikon ve başlık belirle
    if (grepl("bash|execute|shell", arac_adi, ignore.case = TRUE)) {
      ikon <- "terminal"
      baslik <- "Kabuk Komutu"
      komut <- girdi$command %||% girdi$cmd %||% ""
      icerik <- if (nzchar(komut)) {
        paste0('<code class="cc-tool-command">', htmltools::htmlEscape(komut), '</code>')
      } else ""
    } else if (grepl("read|file_read", arac_adi, ignore.case = TRUE)) {
      ikon <- "file-code"
      baslik <- "Dosya Okuma"
      dosya <- girdi$path %||% girdi$file_path %||% ""
      icerik <- if (nzchar(dosya)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(dosya), '</span>')
      } else ""
    } else if (grepl("write|file_write|edit", arac_adi, ignore.case = TRUE)) {
      ikon <- "pen"
      baslik <- "Dosya Yazma"
      dosya <- girdi$path %||% girdi$file_path %||% ""
      icerik <- if (nzchar(dosya)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(dosya), '</span>')
      } else ""
    } else if (grepl("search|grep|glob", arac_adi, ignore.case = TRUE)) {
      ikon <- "search"
      baslik <- "Arama"
      desen <- girdi$pattern %||% girdi$query %||% ""
      icerik <- if (nzchar(desen)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(desen), '</span>')
      } else ""
    } else {
      ikon <- "cog"
      baslik <- arac_adi
      icerik <- ""
    }

    # Sonuç metnini kısalt (çok uzunsa)
    sonuc_html <- ""
    if (nzchar(sonuc_metni)) {
      sonuc_kisaltilmis <- if (nchar(sonuc_metni) > 500) {
        paste0(substr(sonuc_metni, 1, 500), "...")
      } else {
        sonuc_metni
      }
      sonuc_html <- paste0(
        '<div class="cc-tool-result"><pre>',
        htmltools::htmlEscape(sonuc_kisaltilmis),
        '</pre></div>'
      )
    }

    paste0(
      '<div class="cc-tool-block">',
      '<div class="cc-tool-header">',
      '<i class="fas fa-', ikon, '"></i> ',
      '<span class="cc-tool-title">', htmltools::htmlEscape(baslik), '</span>',
      '</div>',
      if (nzchar(icerik)) paste0('<div class="cc-tool-content">', icerik, '</div>') else "",
      sonuc_html,
      '</div>'
    )
  })

  paste(html_parcalari, collapse = "\n")
}

# ------------------------------------------------------------------------------
# RASTGELE DÜŞÜNME MESAJI SEÇ
# ------------------------------------------------------------------------------

#' Aktif karaktere göre rastgele bir düşünme mesajı döndürür
#'
#' @param karakter_id Aktif karakter kimliği (mergen, ulgen, kayra, erlik, umay)
#' @return Düşünme mesajı metni
get_thinking_message <- function(karakter_id = "mergen") {
  # Karakter mesajlarını al
  karakter_mesajlari <- claude_code_thinking_messages[[karakter_id]]

  # Genel mesajlarla birleştir
  tum_mesajlar <- c(
    claude_code_thinking_messages[["genel"]],
    if (!is.null(karakter_mesajlari)) karakter_mesajlari
  )

  # Rastgele seç
  sample(tum_mesajlar, 1)
}