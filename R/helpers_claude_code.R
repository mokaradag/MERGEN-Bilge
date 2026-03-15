# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Açıklama: Claude Code CLI ile etkileşim için arka plan işçi fonksiyonları.
#           processx paketi ile alt süreç yönetimi, CLI otomatik tespiti,
#           settings.json okuma, oturum yönetimi ve dosya sistemi işlemleri.
#           JSON çıktı desteği ile araç kullanımı ve kabuk komutlarını ayrıştırır.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLI YOLU OTOMATİK TESPİTİ
# Windows'ta npm global kurulumlar .cmd uzantılı dosya oluşturur.
# processx bu uzantıyı kendisi çözemez, açıkça belirtilmelidir.
# ------------------------------------------------------------------------------

#' Claude Code CLI yolunu otomatik tespit eder
#'
#' @param kullanici_yolu Kullanıcının elle girdiği yol (boş olabilir)
#' @return Geçerli CLI yolu veya NULL (bulunamadıysa)
resolve_claude_cli_path <- function(kullanici_yolu = "") {
  # Kullanıcı bir yol verdiyse öncelikle onu dene

  if (nzchar(kullanici_yolu)) {
    # Windows'ta .cmd uzantısı yoksa ekle
    if (.Platform$OS.type == "windows" && !grepl("\\.(cmd|exe|bat)$", kullanici_yolu, ignore.case = TRUE)) {
      cmd_yolu <- paste0(kullanici_yolu, ".cmd")
      if (file.exists(cmd_yolu)) {
        return(normalizePath(cmd_yolu, winslash = "/"))
      }
    }
    # Yol doğrudan mevcut mu?
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
# Claude Code'un kendi ayar dosyasını okuyarak model listesini ve
# varsayılan modeli alır. Bu dosya ~/.claude/settings.json konumundadır.
# ------------------------------------------------------------------------------

#' Claude Code settings.json dosyasını okur
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
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json bulunamadı:", ayar_yolu))
    return(sonuc)
  }

  tryCatch({
    icerik <- jsonlite::fromJSON(ayar_yolu, simplifyVector = FALSE)
    sonuc$raw <- icerik

    # Varsayılan model
    if (!is.null(icerik$model) && nzchar(icerik$model)) {
      sonuc$default_model <- icerik$model
    }

    # Ortam değişkenleri içerisindeki modelleri topla
    model_listesi <- c()

    if (!is.null(icerik$env)) {
      env <- icerik$env

      # ANTHROPIC_BASE_URL
      if (!is.null(env$ANTHROPIC_BASE_URL)) {
        sonuc$base_url <- env$ANTHROPIC_BASE_URL
      }

      # ANTHROPIC_DEFAULT_*_MODEL değişkenlerini tara
      model_anahtarlari <- grep("^ANTHROPIC_DEFAULT_.*_MODEL$", names(env), value = TRUE)
      for (anahtar in model_anahtarlari) {
        model_adi <- env[[anahtar]]
        if (!is.null(model_adi) && nzchar(model_adi)) {
          # Anahtar adından etiketi çıkar (OPUS, SONNET, HAIKU, vb.)
          etiket <- gsub("^ANTHROPIC_DEFAULT_(.+)_MODEL$", "\\1", anahtar)
          model_listesi <- c(model_listesi, setNames(model_adi, etiket))
        }
      }
    }

    # Varsayılan model listeye dahil değilse ekle
    if (nzchar(sonuc$default_model) && !(sonuc$default_model %in% model_listesi)) {
      model_listesi <- c(setNames(sonuc$default_model, "VARSAYILAN"), model_listesi)
    }

    sonuc$models <- model_listesi

    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okundu.",
                   length(model_listesi), "model bulundu.",
                   "Varsayılan:", sonuc$default_model))

  }, error = function(e) {
    log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okunamadı:", conditionMessage(e)))
  })

  return(sonuc)
}

# ------------------------------------------------------------------------------
# MODEL KATMAN EŞLEŞTİRME
# settings.json'daki teknik model adlarını kullanıcı dostu etiketlerle eşleştirir
# ------------------------------------------------------------------------------

#' Model listesini kullanıcı dostu katman etiketleriyle eşleştirir
#'
#' @param model_listesi Adlandırılmış karakter vektörü (anahtar=etiket, değer=model_id)
#' @return Adlandırılmış liste: her eleman list(etiket, ikon, aciklama, deger)
build_model_tier_choices <- function(model_listesi) {
  if (length(model_listesi) == 0) {
    return(list(list(
      etiket = claude_code_varsayilan_etiket,
      ikon = "fa-cog",
      ikon_unicode = "⚙",
      aciklama = "Yapılandırma dosyasındaki varsayılan model",
      deger = ""
    )))
  }

  katmanlar <- claude_code_model_tiers
  sonuc <- list()

  for (i in seq_along(model_listesi)) {
    model_id <- unname(model_listesi[i])
    anahtar <- names(model_listesi)[i]

    # Katman eşleştirmesi yap (anahtar adındaki desene göre)
    eslesme <- NULL
    for (katman in katmanlar) {
      if (grepl(katman$anahtar_deseni, anahtar, ignore.case = TRUE)) {
        eslesme <- katman
        break
      }
    }

    if (is.null(eslesme)) {
      # Eşleşme bulunamadıysa varsayılan etiket kullan
      sonuc[[length(sonuc) + 1]] <- list(
        etiket = paste0(claude_code_varsayilan_etiket, " (", anahtar, ")"),
        ikon = "fa-cog",
        ikon_unicode = "⚙",
        aciklama = paste("Model:", model_id),
        deger = model_id
      )
    } else {
      sonuc[[length(sonuc) + 1]] <- list(
        etiket = eslesme$etiket,
        ikon = eslesme$ikon,
        ikon_unicode = eslesme$ikon_unicode %||% "",
        aciklama = eslesme$aciklama,
        deger = model_id
      )
    }
  }

  # Sıralama: Hızlı -> Dengeli -> Güçlü -> Diğer
  siralama <- c("Hızlı", "Dengeli", "Güçlü")
  sonuc <- sonuc[order(match(
    sapply(sonuc, function(x) x$etiket),
    siralama,
    nomatch = length(siralama) + 1
  ))]

  return(sonuc)
}

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
      tool_uses = list()
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
      tool_uses = list()
    ))
  }

  # Çalışma dizini kontrolü
  if (!dir.exists(workdir)) {
    return(list(
      success = FALSE,
      output = "",
      error = paste0("Çalışma dizini bulunamadı: ", workdir),
      duration = 0,
      tool_uses = list()
    ))
  }

  # CLI argümanları oluştur
  # --print: interaktif olmayan mod, çıktıyı doğrudan yazdır
  # --output-format json: yapılandırılmış çıktı (araç kullanımlarını da içerir)
  args <- c(
    "--print",
    "--output-format", "json"
  )

  # Model belirtilmişse ekle
  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  # Komutu (prompt) argüman olarak ekle
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

      # JSON çıktısını ayrıştır
      ayristirma <- parse_claude_code_json_output(result$stdout)

      list(
        success = TRUE,
        output = ayristirma$text_output,
        error = "",
        duration = round(sure, 1),
        tool_uses = ayristirma$tool_uses
      )
    } else {
      hata_mesaji <- if (nzchar(result$stderr)) result$stderr else result$stdout
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Hata kodu:", result$status,
                     "- Mesaj:", substr(hata_mesaji, 1, 200)))
      list(
        success = FALSE,
        output = result$stdout,
        error = hata_mesaji,
        duration = round(sure, 1),
        tool_uses = list()
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
        duration = round(sure, 1),
        tool_uses = list()
      ))
    }

    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI hatası:", hata_metni))
    list(
      success = FALSE,
      output = "",
      error = paste0("Claude Code çalıştırılırken hata oluştu: ", hata_metni),
      duration = round(sure, 1),
      tool_uses = list()
    )
  })
}

# ------------------------------------------------------------------------------
# JSON ÇIKTI AYRIŞTIRMA
# Claude Code'un --output-format json çıktısını ayrıştırır.
# Her satır ayrı bir JSON nesnesidir (JSONL formatı).
# ------------------------------------------------------------------------------

#' Claude Code JSON çıktısını ayrıştırır
#'
#' @param ham_cikti CLI'dan gelen ham çıktı metni
#' @return Liste: text_output (metin çıktısı), tool_uses (araç kullanımları listesi)
parse_claude_code_json_output <- function(ham_cikti) {
  sonuc <- list(text_output = "", tool_uses = list())

  if (is.null(ham_cikti) || !nzchar(ham_cikti)) return(sonuc)

  # JSONL satırlarını ayrıştır
  satirlar <- strsplit(ham_cikti, "\n")[[1]]
  metin_parcalari <- c()

  for (satir in satirlar) {
    satir <- trimws(satir)
    if (!nzchar(satir)) next

    tryCatch({
      nesne <- jsonlite::fromJSON(satir, simplifyVector = FALSE)

      tur <- nesne$type %||% ""

      if (tur == "text") {
        # Metin bloğu
        metin_parcalari <- c(metin_parcalari, nesne$content %||% "")

      } else if (tur == "tool_use") {
        # Araç kullanımı (bash komutu, dosya okuma/yazma, vb.)
        arac <- list(
          id = nesne$id %||% "",
          name = nesne$name %||% "",
          input = nesne$input %||% list()
        )
        sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))

      } else if (tur == "tool_result") {
        # Araç sonucu - ilgili araç kullanımına ekle
        arac_id <- nesne$tool_use_id %||% ""
        icerik <- nesne$content %||% ""
        for (j in seq_along(sonuc$tool_uses)) {
          if (identical(sonuc$tool_uses[[j]]$id, arac_id)) {
            sonuc$tool_uses[[j]]$result <- icerik
            break
          }
        }

      } else if (tur == "result") {
        # Son sonuç bloğu
        metin_parcalari <- c(metin_parcalari, nesne$result %||% "")

      } else if (tur == "assistant") {
        # Asistan mesajı - içerik bloklarını işle
        if (!is.null(nesne$content) && is.list(nesne$content)) {
          for (blok in nesne$content) {
            blok_tur <- blok$type %||% ""
            if (blok_tur == "text") {
              metin_parcalari <- c(metin_parcalari, blok$text %||% "")
            } else if (blok_tur == "tool_use") {
              arac <- list(
                id = blok$id %||% "",
                name = blok$name %||% "",
                input = blok$input %||% list()
              )
              sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))
            }
          }
        }
      }

    }, error = function(e) {
      # JSON ayrıştırma başarısız olursa ham satırı metin olarak ekle
      metin_parcalari <<- c(metin_parcalari, satir)
    })
  }

  sonuc$text_output <- paste(metin_parcalari, collapse = "\n")
  return(sonuc)
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI DURUM KONTROLÜ
# ------------------------------------------------------------------------------

#' Claude Code CLI'nin kurulu ve erişilebilir olup olmadığını kontrol eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @return Liste: installed (mantıksal), version (sürüm metni), path (bulunan yol), error (hata)
check_claude_code_status <- function(cli_path = NULL) {
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
      error = paste0("Claude Code çalıştırılamadı: ", conditionMessage(e))
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
  durum <- check_claude_code_status(cli_path)
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