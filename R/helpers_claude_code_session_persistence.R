# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_session_persistence.R
# Açıklama: Bilge Yolaç çalışma alanı runtime'ı ile kalıcı oturum DB katmanı
#           (R/helpers_db_claude_code_sessions.R) arasındaki köprü.
#
# Sözleşmeler:
#   * Persist yolu HİÇBİR ZAMAN canlı ajan yanıtını riske atmaz: tüm DB
#     çağrıları güvenli değerlendirme altındadır; başarısızlık yalnızca log
#     uyarısı üretir.
#   * Tablolar yoksa (aşamalı devreye alma) rv$claude_session_persistence_available
#     FALSE olarak işaretlenir ve Bilge Yolaç bellek-içi modda devam eder.
#   * "Çıktıyı Temizle" / model değişimi / workdir değişimi kalıcı geçmişi
#     SİLMEZ; yalnızca aktif oturum bağını koparır (detach). Arşivleme/silme
#     yalnızca Oturumlar sayfasındaki açık kullanıcı eylemiyle yapılır.
#   * Bu katman gizli değer (API anahtarı, token, ortam değişkeni) saklamaz;
#     araç kullanımı ve üretilen dosyalar için yalnızca kısaltılmış metadata
#     kalıcılaştırılır.
# ==============================================================================

.cc_persist_log_warn <- function(...) {
  msg <- paste(..., collapse = " ")
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn(gsub("[{}]", "", msg))
  } else {
    warning(msg, call. = FALSE)
  }
  invisible(NULL)
}

# Sessiz güvenli değerlendirme: hata durumunda fallback döner; uyarı metni
# verilmişse loglar. Anonim tryCatch handler sayısını tek noktada toplar.
.cc_persist_try <- function(expr, fallback = NULL, uyari = NULL) {
  tryCatch(expr, error = function(e) {
    if (!is.null(uyari)) {
      .cc_persist_log_warn(uyari, conditionMessage(e))
    }
    fallback
  })
}

# Skaler karakter güvenli okuma: NULL/NA/uzunluk-0 girişlerde "" döner.
.cc_persist_chr <- function(x) {
  deger <- .cc_persist_try(as.character(x %||% "")[1], fallback = "")
  if (length(deger) != 1L || is.na(deger)) "" else deger
}


# Kalıcılaştırılan araç metinlerinde yaygın gizli değer desenlerini maskeleyerek
# transient tool çıktılarındaki anahtar/token/parola değerlerinin DB'ye çıplak
# yazılmasını engeller. Bu, en iyi çaba redaksiyonudur; raw stream ayrıca hiç
# saklanmaz.
.cc_persist_redact_secrets <- function(x) {
  metin <- .cc_persist_chr(x)
  if (!nzchar(metin)) {
    return(metin)
  }

  desenler <- c(
    "(?i)(api[_-]?key|token|secret|password|passwd|pwd|authorization|bearer)(\\s*[:=]\\s*)([^\\s,;]+)",
    "(?i)(sk-[A-Za-z0-9_-]{12,})",
    "(?i)(gh[pousr]_[A-Za-z0-9_]{12,})",
    "(?i)(xox[baprs]-[A-Za-z0-9-]{12,})"
  )

  metin <- gsub(desenler[1], "\\1\\2[[MERGEN-REDACTED]]", metin, perl = TRUE)
  for (desen in desenler[-1]) {
    metin <- gsub(desen, "[[MERGEN-REDACTED]]", metin, perl = TRUE)
  }

  metin
}

# Uzun metinleri kalıcılaştırma öncesi açık işaretle kısaltır.
.cc_persist_kisalt <- function(x, sinir) {
  metin <- .cc_persist_chr(x)
  if (nchar(metin) > sinir) {
    metin <- paste0(substr(metin, 1L, sinir), "\n[[MERGEN-TRUNCATED]]")
  }
  metin
}

#' Kalıcılaştırma kullanılabilir mi? Sonucu rv üzerinde önbelleğe alır ve
#' kullanılamıyorsa oturum başına yalnızca bir kez uyarı loglar.
cc_persist_enabled <- function(rv) {
  mevcut <- .cc_persist_try(rv$claude_session_persistence_available)
  if (!is.null(mevcut)) {
    return(isTRUE(mevcut))
  }

  ok <- .cc_persist_try(
    exists("cc_db_claude_tables_available", mode = "function", inherits = TRUE) &&
      cc_db_claude_tables_available(),
    fallback = FALSE
  )

  rv$claude_session_persistence_available <- isTRUE(ok)

  if (!isTRUE(ok)) {
    .cc_persist_log_warn(
      "MB_ClaudeCode_Sessions/MB_ClaudeCode_Runs tabloları erişilebilir değil;",
      "Bilge Yolaç oturumları bu oturumda bellek-içi modda çalışacak.",
      "Kurulum: docs/sql/2026-07-bilge-yolac-sessions.sql"
    )
  }

  isTRUE(ok)
}

#' Aktif çalışma için kalıcı oturum kaydını garanti eder.
#'
#' İlk çalıştırmada MB_ClaudeCode_Sessions satırı oluşturur ve rv üzerine
#' bağlar; sonraki çalıştırmalarda mevcut kayıt kimliğini döndürür.
#' Başarısızlık çalıştırmayı ENGELLEMEZ (NULL döner).
cc_persist_session_begin <- function(rv,
                                     user_id,
                                     prompt,
                                     workdir = NULL,
                                     source_workdir = NULL,
                                     runtime_workdir = NULL,
                                     model = NULL,
                                     runtime_model = NULL,
                                     character_id = NULL) {
  if (!cc_persist_enabled(rv)) {
    return(NULL)
  }

  mevcut_id <- .cc_persist_try(rv$claude_session_record_id)
  if (!is.null(mevcut_id)) {
    return(mevcut_id)
  }

  baslik <- cc_db_generate_session_title(prompt)

  kayit_id <- .cc_persist_try(
    cc_db_create_session(
      user_id = user_id,
      title = baslik,
      workdir = workdir,
      source_workdir = source_workdir,
      runtime_workdir = runtime_workdir,
      model = model,
      runtime_model = runtime_model,
      character_id = character_id,
      metadata = list(created_from = "workbench")
    ),
    fallback = NULL,
    uyari = "Bilge Yolaç kalıcı oturum kaydı açılamadı:"
  )

  if (!is.null(kayit_id)) {
    rv$claude_session_record_id <- kayit_id
    rv$claude_session_title <- baslik
    rv$claude_session_loaded <- FALSE
  }

  kayit_id
}

#' Aktif oturum bağını koparır; kalıcı geçmişe DOKUNMAZ.
#'
#' Çıktıyı Temizle, model değişimi ve workdir değişimi bu yolu kullanır:
#' bir sonraki çalıştırma yeni bir kalıcı oturum kaydı açar, eski kayıt
#' Oturumlar sayfasında erişilebilir kalır.
cc_persist_detach_session <- function(rv) {
  rv$claude_session_record_id <- NULL
  rv$claude_session_title <- NULL
  rv$claude_session_loaded <- FALSE
  invisible(TRUE)
}

# Tek bir araç kullanımını kalıcılaştırma için küçültür.
.cc_persist_slim_one_tool <- function(arac, max_input_chars, max_result_chars) {
  girdi <- arac$input %||% list()
  girdi_slim <- list()

  if (is.list(girdi) && length(girdi)) {
    for (ad in names(girdi)) {
      deger <- girdi[[ad]]
      if (is.character(deger) || is.numeric(deger) || is.logical(deger)) {
        girdi_slim[[ad]] <- .cc_persist_kisalt(.cc_persist_redact_secrets(deger), max_input_chars)
      }
    }
  }

  list(
    name = .cc_persist_chr(arac$name),
    id = .cc_persist_chr(arac$id),
    input = girdi_slim,
    result = .cc_persist_kisalt(.cc_persist_redact_secrets(arac$result %||% ""), max_result_chars)
  )
}

#' Araç kullanımı listesini kalıcılaştırma için küçültür: yalnızca ad, girdi
#' (uzun stringler kısaltılır) ve kısaltılmış sonuç metni saklanır.
cc_persist_slim_tool_uses <- function(tool_uses,
                                      max_input_chars = 2000L,
                                      max_result_chars = 4000L) {
  if (is.null(tool_uses) || !length(tool_uses)) {
    return(list())
  }

  lapply(
    tool_uses,
    .cc_persist_slim_one_tool,
    max_input_chars = max_input_chars,
    max_result_chars = max_result_chars
  )
}

# Tek bir üretilen dosya kaydını güvenli metadata alanlarına indirger.
.cc_persist_slim_one_download <- function(dosya) {
  list(
    display_name = .cc_persist_chr(dosya$display_name %||% dosya$download_name),
    download_name = .cc_persist_chr(dosya$download_name),
    download_path = .cc_persist_chr(dosya$download_path),
    url = .cc_persist_chr(dosya$url),
    size = suppressWarnings(as.numeric(dosya$size %||% NA_real_)[1]),
    size_label = .cc_persist_chr(dosya$size_label)
  )
}

#' Üretilen dosya kayıtlarını kalıcılaştırma için küçültür: yalnızca güvenli
#' metadata alanları saklanır (ikili içerik asla saklanmaz).
cc_persist_slim_downloads <- function(downloads) {
  if (is.null(downloads) || !length(downloads)) {
    return(list())
  }

  lapply(downloads, .cc_persist_slim_one_download)
}

#' Akış tamamlandığında çalıştırmayı kalıcılaştırır ve oturum başlığını günceller.
#'
#' Başarılı VE başarısız çalıştırmalar kaydedilir. Persist hatası kullanıcıya
#' görünen canlı yanıtı asla etkilemez.
cc_persist_run_result <- function(rv,
                                  env,
                                  status,
                                  final_output = "",
                                  exit_code = NULL,
                                  duration = NULL,
                                  tool_uses = list(),
                                  downloads = list(),
                                  cli_session_id = NULL) {
  kayit_id <- .cc_persist_try(rv$claude_session_record_id)
  if (is.null(kayit_id) || !cc_persist_enabled(rv)) {
    return(invisible(FALSE))
  }

  sonuc <- .cc_persist_try({
    # env$tum_satirlar ham stream-json payload'ıdır ve tool-result içeriğinde
    # env/.Renviron/komut çıktısı gibi gizli değerler bulunabilir. MB_ClaudeCode
    # tablo sözleşmesi gereği bu transient ham akış DB'ye yazılmaz; yalnızca
    # redakte edilmiş/kısaltılmış tool metadata'sı saklanır.
    run_id <- cc_db_save_run(
      session_record_id = kayit_id,
      prompt = .cc_persist_try(env$prompt, fallback = ""),
      final_output = final_output,
      status = status,
      exit_code = exit_code,
      duration_seconds = duration,
      tool_uses = cc_persist_slim_tool_uses(tool_uses),
      generated_downloads = cc_persist_slim_downloads(downloads),
      raw_stream_jsonl = NULL
    )

    kaynak_dizin <- .cc_persist_try(env$kaynak_calisma_dizini)
    runtime_dizin <- .cc_persist_try(env$calisma_dizini)

    cc_db_update_session_resume_state(
      session_record_id = kayit_id,
      cli_session_id = cli_session_id,
      workdir = kaynak_dizin %||% runtime_dizin,
      source_workdir = kaynak_dizin,
      runtime_workdir = runtime_dizin,
      runtime_model = .cc_persist_try(rv$current_runtime_model),
      status = status
    )

    !is.null(run_id)
  },
  fallback = FALSE,
  uyari = "Bilge Yolaç çalıştırması kalıcılaştırılamadı:")

  invisible(isTRUE(sonuc))
}


.cc_hydrate_safe_output_html <- function(run_output, format_output_fn = NULL) {
  ham <- .cc_persist_chr(run_output)
  if (!nzchar(ham)) {
    return("")
  }

  if (exists("render_safe_markdown_html", mode = "function", inherits = TRUE)) {
    return(.cc_persist_try(
      render_safe_markdown_html(ham),
      fallback = htmltools::htmlEscape(ham)
    ))
  }

  # İzole test/debug yüklemelerinde güvenli renderer henüz kaynaklanmamışsa,
  # formatlayıcıya ham HTML değil kaçışlanmış markdown verilir. Böylece
  # cc-hydrate-session -> addMessage(innerHTML) yolu depolanmış markup'ı
  # çalıştırılabilir HTML olarak yeniden canlandırmaz.
  guvenli_markdown <- if (exists("mergen_escape_raw_html_for_markdown", mode = "function", inherits = TRUE)) {
    mergen_escape_raw_html_for_markdown(ham)
  } else {
    gsub(">", "&gt;", gsub("<", "&lt;", ham, fixed = TRUE), fixed = TRUE)
  }
  if (is.function(format_output_fn)) {
    return(.cc_persist_try(
      format_output_fn(guvenli_markdown),
      fallback = htmltools::htmlEscape(ham)
    ))
  }

  htmltools::htmlEscape(ham)
}

#' Kayıtlı bir oturumdan çalışma alanı hidrasyon planı üretir (test edilebilir).
#'
#' @param record cc_db_load_session() çıktısı: list(session=..., runs=df)
#' @param format_output_fn Asistan çıktısı HTML biçimleyici
#' @param tool_uses_html_fn Araç kullanımı HTML biçimleyici
#' @param downloads_html_fn İndirme kartı HTML biçimleyici
#' @param dir_exists_fn Dizin varlık kontrolü (test enjeksiyonu için)
#' @param file_exists_fn Dosya varlık kontrolü (test enjeksiyonu için)
#' @return list(messages, conversation_context, resume, workdir_restore,
#'              warnings, title)
cc_session_hydration_plan <- function(record,
                                      format_output_fn = NULL,
                                      tool_uses_html_fn = NULL,
                                      downloads_html_fn = NULL,
                                      dir_exists_fn = dir.exists,
                                      file_exists_fn = file.exists) {
  bos_plan <- list(
    messages = list(),
    conversation_context = list(),
    resume = list(ok = FALSE, cli_session_id = NULL, runtime_workdir = NULL,
                  source_workdir = NULL, reason = "kayit_yok"),
    workdir_restore = NULL,
    warnings = character(0),
    title = NULL
  )

  if (is.null(record) || is.null(record$session)) {
    return(bos_plan)
  }

  oturum <- record$session
  runs <- record$runs

  cli_id <- .cc_persist_chr(oturum$ClaudeCliSessionID)
  runtime_dir <- .cc_persist_chr(oturum$RuntimeWorkdir)
  source_dir <- .cc_persist_chr(oturum$SourceWorkdir)
  workdir <- .cc_persist_chr(oturum$Workdir)

  uyarilar <- character(0)

  # --- Devam (resume) güvenlik kontrolü -------------------------------------
  # Claude CLI --resume metadatası, CLI'nin çalıştığı (runtime) klasöre
  # bağlıdır. Klasör silinmiş/erişilemezse resume denemek "No conversation
  # found with session ID" hatası üretir; bu durumda geçmiş görünür kalır
  # ama CLI oturumu taze başlar.
  etkin_calisma_dizini <- if (nzchar(runtime_dir)) runtime_dir else workdir

  resume_ok <- nzchar(cli_id) &&
    nzchar(etkin_calisma_dizini) &&
    isTRUE(.cc_persist_try(dir_exists_fn(etkin_calisma_dizini), fallback = FALSE))

  resume <- list(
    ok = isTRUE(resume_ok),
    cli_session_id = if (isTRUE(resume_ok)) cli_id else NULL,
    runtime_workdir = if (isTRUE(resume_ok) && nzchar(runtime_dir)) runtime_dir else NULL,
    source_workdir = if (isTRUE(resume_ok) && nzchar(source_dir)) source_dir else NULL,
    reason = if (isTRUE(resume_ok)) {
      "uygun"
    } else if (!nzchar(cli_id)) {
      "cli_oturum_kimligi_yok"
    } else {
      "calisma_dizini_bulunamadi"
    }
  )

  if (nzchar(cli_id) && !isTRUE(resume_ok)) {
    uyarilar <- c(
      uyarilar,
      paste(
        "Oturumun çalışma dizini artık erişilebilir değil;",
        "geçmiş görüntülenecek ancak takip soruları yeni bir CLI oturumu başlatacak."
      )
    )
  }

  # --- Workdir geri yükleme --------------------------------------------------
  workdir_aday <- if (nzchar(source_dir)) source_dir else workdir
  workdir_restore <- NULL

  if (nzchar(workdir_aday)) {
    if (isTRUE(.cc_persist_try(dir_exists_fn(workdir_aday), fallback = FALSE))) {
      workdir_restore <- workdir_aday
    } else {
      uyarilar <- c(
        uyarilar,
        paste0("Proje dizini bulunamadı: ", workdir_aday,
               " - mevcut dizin korunuyor.")
      )
    }
  }

  # --- Mesaj yeniden oynatma planı -------------------------------------------
  mesajlar <- list()
  baglam <- list()

  if (is.data.frame(runs) && nrow(runs) > 0L) {
    for (i in seq_len(nrow(runs))) {
      run_prompt <- .cc_persist_chr(runs$Prompt[i])
      run_output <- .cc_persist_chr(runs$FinalOutput[i])
      run_status <- .cc_persist_chr(runs$Status[i])
      run_zaman <- .cc_persist_chr(runs$CreatedAt[i])
      run_sure <- suppressWarnings(as.numeric(runs$DurationSeconds[i]))

      zaman_etiketi <- if (nchar(run_zaman) >= 16L) {
        substr(run_zaman, 1L, 16L)
      } else {
        run_zaman
      }

      mesajlar[[length(mesajlar) + 1L]] <- list(
        type = "user",
        content = htmltools::htmlEscape(run_prompt),
        timestamp = zaman_etiketi
      )

      baglam[[length(baglam) + 1L]] <- list(role = "user", content = run_prompt)

      arac_html <- ""
      if ("ToolUsesJson" %in% names(runs)) {
        arac_html <- .cc_hydrate_tool_uses_html(
          runs$ToolUsesJson[i],
          tool_uses_html_fn = tool_uses_html_fn
        )
      }

      indirme_html <- ""
      if ("GeneratedDownloadsJson" %in% names(runs)) {
        indirme_html <- .cc_hydrate_downloads_html(
          runs$GeneratedDownloadsJson[i],
          downloads_html_fn = downloads_html_fn,
          file_exists_fn = file_exists_fn
        )
      }

      if (identical(run_status, "failed")) {
        mesajlar[[length(mesajlar) + 1L]] <- list(
          type = "error",
          content = paste0(htmltools::htmlEscape(run_output), indirme_html),
          toolContent = arac_html,
          timestamp = zaman_etiketi
        )
        next
      }

      icerik <- .cc_hydrate_safe_output_html(
        run_output,
        format_output_fn = format_output_fn
      )

      mesajlar[[length(mesajlar) + 1L]] <- list(
        type = "assistant",
        content = paste0(icerik, indirme_html),
        toolContent = arac_html,
        timestamp = zaman_etiketi,
        duration = if (!is.na(run_sure)) run_sure else NULL
      )

      baglam[[length(baglam) + 1L]] <- list(role = "assistant", content = run_output)
    }
  }

  list(
    messages = mesajlar,
    conversation_context = baglam,
    resume = resume,
    workdir_restore = workdir_restore,
    warnings = uyarilar,
    title = .cc_persist_chr(oturum$SessionTitle)
  )
}

# Kalıcı ToolUsesJson metnini güvenli HTML'e çevirir; hata olursa boş döner.
.cc_hydrate_tool_uses_html <- function(tool_uses_json, tool_uses_html_fn = NULL) {
  json_metin <- .cc_persist_chr(tool_uses_json)
  if (!nzchar(json_metin) || identical(json_metin, "[]")) {
    return("")
  }

  arac_listesi <- .cc_persist_try(
    jsonlite::fromJSON(json_metin, simplifyVector = FALSE)
  )

  if (is.null(arac_listesi) || !length(arac_listesi)) {
    return("")
  }

  fmt <- tool_uses_html_fn
  if (!is.function(fmt) &&
      exists("format_tool_uses_html_enhanced", mode = "function", inherits = TRUE)) {
    fmt <- format_tool_uses_html_enhanced
  }

  if (!is.function(fmt)) {
    return("")
  }

  .cc_persist_try(fmt(arac_listesi), fallback = "")
}

# Kalıcı GeneratedDownloadsJson metnini indirme kartlarına çevirir; yalnızca
# fiziksel olarak hala var olan dosyalar için kart üretir.
.cc_hydrate_downloads_html <- function(downloads_json,
                                       downloads_html_fn = NULL,
                                       file_exists_fn = file.exists) {
  json_metin <- .cc_persist_chr(downloads_json)
  if (!nzchar(json_metin) || identical(json_metin, "[]")) {
    return("")
  }

  indirmeler <- .cc_persist_try(
    jsonlite::fromJSON(json_metin, simplifyVector = FALSE)
  )

  if (is.null(indirmeler) || !length(indirmeler)) {
    return("")
  }

  mevcutlar <- list()
  for (dosya in indirmeler) {
    yol <- .cc_persist_chr(dosya$download_path)
    if (nzchar(yol) &&
        isTRUE(.cc_persist_try(file_exists_fn(yol), fallback = FALSE))) {
      mevcutlar[[length(mevcutlar) + 1L]] <- dosya
    }
  }

  if (!length(mevcutlar)) {
    return("")
  }

  fmt <- downloads_html_fn
  if (!is.function(fmt) &&
      exists("format_claude_code_generated_downloads_html", mode = "function", inherits = TRUE)) {
    fmt <- format_claude_code_generated_downloads_html
  }

  if (!is.function(fmt)) {
    return("")
  }

  .cc_persist_try(fmt(mevcutlar), fallback = "")
}
