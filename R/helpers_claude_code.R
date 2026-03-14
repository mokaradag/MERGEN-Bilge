# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Açıklama: Claude Code CLI ile etkileşim için arka plan işçi fonksiyonları.
#           processx paketi ile alt süreç yönetimi, çıktı akışı okuma,
#           oturum yönetimi ve dosya sistemi işlemlerini içerir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI ÇALIŞTIRMA
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu arka planda çalıştır
#'
#' @param prompt Kullanıcının gönderdiği komut/soru metni
#' @param workdir Çalışma dizini (proje klasörü)
#' @param max_tokens Maksimum token sayısı
#' @param model Kullanılacak model adı (boş ise varsayılan kullanılır)
#' @param timeout_sec Zaman aşımı süresi (saniye)
#' @param session_id Oturum kimliği (izolasyon için)
#' @param cli_path Claude Code CLI çalıştırılabilir dosya yolu
#' @return Liste: success (mantıksal), output (metin), error (hata metni), duration (süre)
run_claude_code <- function(prompt,
                            workdir = getwd(),
                            max_tokens = 4096L,
                            model = NULL,
                            timeout_sec = 300L,
                            session_id = NULL,
                            cli_path = "claude") {

  baslangic <- Sys.time()

  # Girdi doğrulaması

  if (!nzchar(trimws(prompt))) {
    return(list(
      success = FALSE,
      output = "",
      error = "Komut metni boş olamaz.",
      duration = 0
    ))
  }

  # Çalışma dizini kontrolü
  if (!dir.exists(workdir)) {
    return(list(
      success = FALSE,
      output = "",
      error = paste0("Çalışma dizini bulunamadı: ", workdir),
      duration = 0
    ))
  }

  # CLI argümanları oluştur
  args <- c(
    "--print",           # İnteraktif olmayan mod, çıktıyı doğrudan yazdır
    "--output-format", "text"  # Metin formatında çıktı
  )

  # Model belirtilmişse ekle
  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  # Maksimum token
  if (!is.null(max_tokens) && max_tokens > 0) {
    args <- c(args, "--max-tokens", as.character(max_tokens))
  }

  # Komutu ekle
  args <- c(args, prompt)

  # processx ile çalıştır
  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI çalıştırılıyor:",
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
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Başarılı - Süre:",
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

    # Zaman aşımı kontrolü
    if (grepl("timeout|timed out", hata_metni, ignore.case = TRUE)) {
      log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Zaman aşımı:", timeout_sec, "sn"))
      return(list(
        success = FALSE,
        output = "",
        error = paste0("İşlem zaman aşımına uğradı (", timeout_sec, " saniye). ",
                       "Daha kısa bir komut deneyin veya zaman aşımı süresini artırın."),
        duration = round(sure, 1)
      ))
    }

    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI hatası:", hata_metni))
    list(
      success = FALSE,
      output = "",
      error = paste0("Claude Code çalıştırılırken hata oluştu: ", hata_metni),
      duration = round(sure, 1)
    )
  })
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI DURUM KONTROLÜ
# ------------------------------------------------------------------------------

#' Claude Code CLI'nin kurulu ve erişilebilir olup olmadığını kontrol eder
#'
#' @param cli_path Claude Code CLI yolu
#' @return Liste: installed (mantıksal), version (sürüm metni), error (hata metni)
check_claude_code_status <- function(cli_path = "claude") {
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
      list(installed = TRUE, version = surum, error = "")
    } else {
      list(installed = FALSE, version = "", error = result$stdout)
    }
  }, error = function(e) {
    list(
      installed = FALSE,
      version = "",
      error = paste0("Claude Code bulunamadı: ", conditionMessage(e))
    )
  })
}

# ------------------------------------------------------------------------------
# BAĞLANTI TESTİ
# ------------------------------------------------------------------------------

#' API bağlantısını test eder
#'
#' @param cli_path Claude Code CLI yolu
#' @param model Test edilecek model (opsiyonel)
#' @param workdir Çalışma dizini
#' @return Liste: success, message, details
test_claude_code_connection <- function(cli_path = "claude",
                                        model = NULL,
                                        workdir = tempdir()) {
  # Öncelikle CLI kontrolü yap
  durum <- check_claude_code_status(cli_path)
  if (!durum$installed) {
    return(list(
      success = FALSE,
      message = "Claude Code CLI bulunamadı veya erişilemez.",
      details = durum$error
    ))
  }

  # Basit bir test komutu gönder
  test_sonuc <- run_claude_code(
    prompt = "Merhaba, bu bir bağlantı testidir. Sadece 'Bağlantı başarılı' yaz.",
    workdir = workdir,
    max_tokens = 100L,
    model = model,
    timeout_sec = 30L,
    cli_path = cli_path
  )

  if (test_sonuc$success) {
    list(
      success = TRUE,
      message = paste0("Bağlantı başarılı! Claude Code v", durum$version),
      details = paste0("Yanıt süresi: ", test_sonuc$duration, " saniye")
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

#' Kullanıcı için izole bir çalışma alanı oluşturur veya mevcut olanı döndürür
#'
#' @param user_id Kullanıcı kimliği
#' @param base_dir Temel dizin (varsayılan: tempdir altında)
#' @return Çalışma dizini yolu
get_user_workspace <- function(user_id, base_dir = NULL) {
  if (is.null(base_dir) || !nzchar(base_dir)) {
    base_dir <- file.path(tempdir(), "claude_code_workspaces")
  }

  user_dir <- file.path(base_dir, paste0("user_", user_id))

  if (!dir.exists(user_dir)) {
    dir.create(user_dir, recursive = TRUE, showWarnings = FALSE)
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Kullanıcı çalışma alanı oluşturuldu:",
                   user_dir))
  }

  return(normalizePath(user_dir, mustWork = FALSE))
}

# ------------------------------------------------------------------------------
# DİZİN LİSTELEME
# ------------------------------------------------------------------------------

#' Belirtilen dizindeki dosya ve klasörleri listeler
#'
#' @param path Dizin yolu
#' @param max_items Maksimum öğe sayısı
#' @return Dosya/klasör bilgileri listesi
list_directory_contents <- function(path, max_items = 100L) {
  if (!dir.exists(path)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
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
