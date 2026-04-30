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

# Windows cmd.exe için problem çıkarabilecek yol mu?
is_problematic_windows_workdir <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

  unc_mi <- grepl("^//", aday)
  ascii_disi_var_mi <- grepl("[^ -~]", enc2utf8(aday), perl = TRUE)

  isTRUE(unc_mi || ascii_disi_var_mi)
}

# Dizin içeriğini yerel çalışma alanına aynala
mirror_directory_to_local_workspace <- function(source_dir, target_dir) {
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  }

  ogeler <- tryCatch(
    list.files(
      source_dir,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE,
      include.dirs = TRUE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) {
    return(invisible(TRUE))
  }

  kopya_ok <- tryCatch(
    file.copy(
      from = ogeler,
      to = target_dir,
      overwrite = TRUE,
      recursive = TRUE,
      copy.mode = TRUE,
      copy.date = TRUE
    ),
    error = function(e) rep(FALSE, length(ogeler))
  )

  if (any(!kopya_ok)) {
    for (i in seq_along(ogeler)) {
      if (isTRUE(kopya_ok[i])) next

      kaynak <- ogeler[i]
      hedef <- file.path(target_dir, basename(kaynak))

      tryCatch({
        if (dir.exists(kaynak)) {
          if (dir.exists(hedef)) unlink(hedef, recursive = TRUE, force = TRUE)
          fs::dir_copy(kaynak, hedef, overwrite = TRUE)
        } else {
          fs::file_copy(kaynak, hedef, overwrite = TRUE)
        }
      }, error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Yerel aynalama sırasında öge kopyalanamadı:",
          basename(kaynak),
          "-",
          conditionMessage(e)
        ))
      })
    }
  }

  invisible(TRUE)
}

# Problemli ağ/Unicode dizinlerini yerel ASCII çalışma klasörüne taşır
prepare_claude_runtime_workdir <- function(workdir, user_id = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  source_dir <- tryCatch(
    normalize_mcp_path(workdir, must_exist = FALSE),
    error = function(e) as.character(workdir)
  )

  dir_ok <- tryCatch(
    isTRUE(dir.exists(source_dir)) || isTRUE(fs::dir_exists(source_dir)),
    error = function(e) FALSE
  )

  if (!isTRUE(dir_ok)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  if (!is_problematic_windows_workdir(source_dir)) {
    return(list(
      runtime_workdir = source_dir,
      source_workdir = source_dir,
      mirrored = FALSE
    ))
  }

  local_base <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    "active_dir"
  )

  if (dir.exists(local_base)) {
    unlink(local_base, recursive = TRUE, force = TRUE)
  }

  dir.create(local_base, recursive = TRUE, showWarnings = FALSE)

  mirror_directory_to_local_workspace(source_dir, local_base)

  local_base <- normalizePath(local_base, winslash = "/", mustWork = FALSE)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Problemli çalışma dizini yerel alana aynalandı:",
    source_dir,
    "->",
    local_base
  ))

  list(
    runtime_workdir = local_base,
    source_workdir = source_dir,
    mirrored = TRUE
  )
}

# Yerel çalışma alanındaki değişiklikleri kaynak dizine geri senkronlar
sync_claude_runtime_workdir_back <- function(runtime_workdir, source_workdir) {
  if (is.null(runtime_workdir) || !nzchar(runtime_workdir)) return(invisible(FALSE))
  if (is.null(source_workdir) || !nzchar(source_workdir)) return(invisible(FALSE))
  if (!dir.exists(runtime_workdir)) return(invisible(FALSE))
  if (!dir.exists(source_workdir)) return(invisible(FALSE))

  mirror_directory_to_local_workspace(runtime_workdir, source_workdir)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Yerel çalışma alanı kaynak dizine geri senkronlandı:",
    runtime_workdir,
    "->",
    source_workdir
  ))

  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# DİZİN LİSTELEME
# ------------------------------------------------------------------------------

#' Belirtilen dizindeki dosya ve klasörleri listeler
#'
#' @param path Dizin yolu
#' @param max_items Maksimum öğe sayısı
#' @return Dosya/klasör bilgileri listesi
list_directory_contents <- function(path, max_items = 100L, user_id = NULL) {
  if (is.null(path) || !nzchar(path)) {
    return(list(
      success = FALSE,
      items = list(),
      error = "Dizin yolu boş."
    ))
  }

  # UNC/ağ paylaşımı/kodlama farkları için aynı dizinin olası varyasyonlarını üret
  build_dir_variants <- function(dir_path) {
    dir_chr <- gsub("\\\\", "/", as.character(dir_path %||% ""), fixed = TRUE)
    if (!nzchar(dir_chr)) return(character(0))

    unique(Filter(nzchar, c(
      dir_chr,
      enc2utf8(dir_chr),
      enc2native(dir_chr),
      if (grepl("^/[^/]", dir_chr)) paste0("/", dir_chr) else NULL
    )))
  }

  # Aynı dizini hem base R hem fs ile listelemeyi dene
  list_dir_relaxed <- function(dir_path) {
    files_base <- tryCatch(
      list.files(
        dir_path,
        full.names = TRUE,
        recursive = FALSE,
        all.files = FALSE
      ),
      error = function(e) character(0)
    )

    if (length(files_base) > 0) {
      return(unique(files_base))
    }

    dirs_fs <- tryCatch(
      as.character(fs::dir_ls(dir_path, recurse = FALSE, type = "directory")),
      error = function(e) character(0)
    )

    files_fs <- tryCatch(
      as.character(fs::dir_ls(dir_path, recurse = FALSE, type = "file")),
      error = function(e) character(0)
    )

    unique(c(dirs_fs, files_fs))
  }

  aday_dizinler <- build_dir_variants(path)

  if (!length(aday_dizinler)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
    ))
  }

  calisan_dizin <- NULL
  tum_ogeler <- character(0)

  for (aday in aday_dizinler) {
    dizin_var_mi <- tryCatch(path_exists_relaxed(aday), error = function(e) FALSE)

    if (!isTRUE(dizin_var_mi)) {
      dizin_var_mi <- tryCatch(
        isTRUE(dir.exists(aday)) || isTRUE(fs::dir_exists(aday)),
        error = function(e) FALSE
      )
    }

    if (!isTRUE(dizin_var_mi)) next

    bulunan_ogeler <- list_dir_relaxed(aday)

    # En azından çalışan dizini kaydet
    if (is.null(calisan_dizin)) {
      calisan_dizin <- aday
    }

    # İçerik bulduysak bunu tercih et
    if (length(bulunan_ogeler) > 0) {
      calisan_dizin <- aday
      tum_ogeler <- bulunan_ogeler
      break
    }
  }

  if (is.null(calisan_dizin)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
    ))
  }

  tum_ogeler <- unique(tum_ogeler)
  gosterilecek_ogeler <- head(tum_ogeler, max_items)

  idx_cache <- tryCatch(.load_index(), error = function(e) list())

  gorunen_ad_getir <- function(dosya_yolu, klasor_mu) {
    if (isTRUE(klasor_mu)) {
      return(basename(dosya_yolu))
    }

    tryCatch(
      mergen_resolve_display_name(
        dosya_yolu,
        user_id = user_id,
        idx = idx_cache
      ),
      error = function(e) basename(dosya_yolu)
    )
  }

  ogeler <- lapply(gosterilecek_ogeler, function(f) {
    f_norm <- tryCatch(
      normalize_mcp_path(f, must_exist = FALSE),
      error = function(e) as.character(f)
    )

    bilgi <- tryCatch(file.info(f_norm), error = function(e) NULL)

    klasor_mu <- tryCatch(isTRUE(bilgi$isdir[1]), error = function(e) FALSE)
    if (is.null(bilgi) || is.na(klasor_mu)) {
      klasor_mu <- tryCatch(
        isTRUE(dir.exists(f_norm)) || isTRUE(fs::dir_exists(f_norm)),
        error = function(e) FALSE
      )
    }

    boyut <- if (isTRUE(klasor_mu)) {
      NA_real_
    } else {
      suppressWarnings(as.numeric(tryCatch(bilgi$size[1], error = function(e) NA_real_)))
    }

    degistirilme <- tryCatch(as.character(bilgi$mtime[1]), error = function(e) "")

    list(
      ad = basename(f_norm),
      gorunen_ad = gorunen_ad_getir(f_norm, klasor_mu),
      yol = f_norm,
      tip = if (isTRUE(klasor_mu)) "klasor" else "dosya",
      boyut = boyut,
      degistirilme = degistirilme
    )
  })

  # Klasörleri üstte, ardından ada göre sırala
  if (length(ogeler) > 1) {
    siralama <- order(
      vapply(ogeler, function(x) x$tip != "klasor", logical(1)),
      tolower(vapply(ogeler, function(x) x$gorunen_ad %||% x$ad %||% "", character(1)))
    )
    ogeler <- ogeler[siralama]
  }

  list(
    success = TRUE,
    items = ogeler,
    error = "",
    toplam = length(tum_ogeler),
    resolved_path = tryCatch(
      normalize_mcp_path(calisan_dizin, must_exist = FALSE),
      error = function(e) calisan_dizin
    )
  )
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