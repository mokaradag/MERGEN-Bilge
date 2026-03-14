# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Aciklama: Claude Code CLI ile etkilesim icin arka plan isci fonksiyonlari.
#           processx paketi ile alt surec yonetimi, cikti akisi okuma,
#           oturum yonetimi ve dosya sistemi islemlerini icerir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI CALISTIRMA
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu arka planda calistir
#'
#' @param prompt Kullanicinin gonderdigi komut/soru metni
#' @param workdir Calisma dizini (proje klasoru)
#' @param max_tokens Maksimum token sayisi
#' @param model Kullanilacak model adi (bos ise varsayilan kullanilir)
#' @param timeout_sec Zaman asimi suresi (saniye)
#' @param session_id Oturum kimligi (izolasyon icin)
#' @param cli_path Claude Code CLI calistirilabilir dosya yolu
#' @return Liste: success (mantiksal), output (metin), error (hata metni), duration (sure)
run_claude_code <- function(prompt,
                            workdir = getwd(),
                            max_tokens = 4096L,
                            model = NULL,
                            timeout_sec = 300L,
                            session_id = NULL,
                            cli_path = "claude") {

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
  args <- c(
    "--print",           # Interaktif olmayan mod, ciktiyi dogrudan yazdir
    "--output-format", "text"  # Metin formatinda cikti
  )

  # Model belirtilmisse ekle
  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  # Maksimum token
  if (!is.null(max_tokens) && max_tokens > 0) {
    args <- c(args, "--max-tokens", as.character(max_tokens))
  }

  # Komutu ekle
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
#' @param cli_path Claude Code CLI yolu
#' @return Liste: installed (mantiksal), version (surum metni), error (hata metni)
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
      error = paste0("Claude Code bulunamadi: ", conditionMessage(e))
    )
  })
}

# ------------------------------------------------------------------------------
# BAGLANTI TESTi
# ------------------------------------------------------------------------------

#' API baglantisini test eder
#'
#' @param cli_path Claude Code CLI yolu
#' @param model Test edilecek model (opsiyonel)
#' @param workdir Calisma dizini
#' @return Liste: success, message, details
test_claude_code_connection <- function(cli_path = "claude",
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

  # Basit bir test komutu gonder
  test_sonuc <- run_claude_code(
    prompt = "Merhaba, bu bir baglanti testidir. Sadece 'Baglanti basarili' yaz.",
    workdir = workdir,
    max_tokens = 100L,
    model = model,
    timeout_sec = 30L,
    cli_path = cli_path
  )

  if (test_sonuc$success) {
    list(
      success = TRUE,
      message = paste0("Baglanti basarili! Claude Code v", durum$version),
      details = paste0("Yanit suresi: ", test_sonuc$duration, " saniye")
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