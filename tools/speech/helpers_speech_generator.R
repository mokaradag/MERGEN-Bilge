# tools/speech/helpers_speech_generator.R
# Konuşma varlığı üreticisinin iç yardımcıları. Operatör API'si
# tools/speech/generate_voxcpm2_assets.R içindedir; bu dosya plan kurma,
# yeniden deneme, atomik yazma, durum/kilit dosyaları ve raporlamayı taşır.
# Çalışma zamanı yardımcıları (R/config_speech_assets.R zinciri) TEK kaynak
# olarak source edilir; sayı/harita burada kopyalanmaz. Shiny gerektirmez.

# --- TTS API anahtarı çözümü ---
# LOCAL_TTS_API_KEY tanımlı ama BOŞ olduğunda R'ın Sys.getenv(name, fallback)
# çağrısı fallback'e DÜŞMEZ; var olan boş dizeyi döndürür. `.Renviron.example`
# LOCAL_TTS_API_KEY'i boş opsiyonel geçiş olarak tanımlar; bu yüzden TTS'e özgü
# değer nzchar() değilse belgelenen LOCAL_LLM_API_KEY yedeğine açıkça düşülür.
speech_gen_resolve_tts_api_key <- function() {
  tts_key <- Sys.getenv("LOCAL_TTS_API_KEY", "")
  if (nzchar(tts_key)) return(tts_key)
  Sys.getenv("LOCAL_LLM_API_KEY", "")
}

# --- Kilit dosyası: iki üretici aynı varlık ağacına eşzamanlı yazamaz ---

#' Kilit sahibi bilgi dosyası: kilit dizini içinde (üretici teşhis metni).
.speech_gen_lock_owner_path <- function(lock_path) {
  file.path(lock_path, "owner.txt")
}

# dir.create() işletim sistemi düzeyinde ATOMİKTİR (tek bir mkdir sistem
# çağrısı): iki süreç aynı anda çağırırsa yalnızca BİRİ TRUE alır, diğeri
# FALSE. Eski desen file.exists() KONTROLÜ + writeLines() YAZIMI arasında
# TOCTOU (kontrol-sonra-eylem) yarışına açıktı: iki operatör/RStudio oturumu
# neredeyse aynı anda başlarsa ikisi de kilidi "boş" görüp belgelenmiş kilide
# rağmen aynı varlık ağacına eşzamanlı yazabiliyordu. Kilit artık bir
# DİZİNDİR; sahip bilgisi dizin içindeki owner.txt dosyasındadır.
speech_gen_acquire_lock <- function(root = mergen_speech_root(),
                                    stale_minutes = 120) {
  lock_path <- mergen_speech_generator_lock_path(root)
  dir.create(dirname(lock_path), recursive = TRUE, showWarnings = FALSE)

  acquired <- isTRUE(dir.create(lock_path, showWarnings = FALSE))

  if (!acquired) {
    if (!dir.exists(lock_path)) {
      stop(sprintf("Üretici kilit dizini oluşturulamadı: %s", lock_path), call. = FALSE)
    }

    # Yaş, KİLİT DİZİNİNİN değil SAHİP DOSYASININ mtime'ından hesaplanır:
    # speech_gen_run() her üretilen WAV'dan sonra speech_gen_lock_heartbeat()
    # ile owner.txt'yi yeniden yazıp mtime'ını tazeler. Yaş dizin mtime'ından
    # (yalnızca oluşturulduğunda kurulur) hesaplansaydı, stale_minutes'i aşan
    # uzun/yavaş bir koşu hâlâ aktifken bile bayat sayılıp ikinci bir
    # oturumun devralmasına (ve aynı ağaca eşzamanlı yazmasına) izin verirdi.
    owner_path <- .speech_gen_lock_owner_path(lock_path)
    heartbeat_mtime <- if (file.exists(owner_path)) {
      file.info(owner_path)$mtime
    } else {
      file.info(lock_path)$mtime
    }
    age_mins <- suppressWarnings(as.numeric(difftime(
      Sys.time(), heartbeat_mtime, units = "mins"
    )))
    if (is.na(age_mins) || age_mins < stale_minutes) {
      lock_info <- tryCatch(
        readLines(.speech_gen_lock_owner_path(lock_path), warn = FALSE),
        error = function(e) ""
      )
      stop(sprintf(
        paste0("Üretici kilidi aktif: %s (sahip: %s). Başka bir üretici koşuyor ",
               "olabilir. Bayat olduğundan eminseniz speech_gen_release_lock() çağırın."),
        lock_path, paste(lock_info, collapse = " ")
      ), call. = FALSE)
    }

    # Bayat kilidi devral: sil, sonra TEKRAR atomik oluşturmayı dene. Bu
    # ikinci deneme de dir.create()'in atomikliğinden yararlanır; iki süreç
    # aynı anda devralmaya çalışırsa yine yalnızca biri kazanır ve diğeri
    # burada güvenle hata verir (sessizce üzerine yazmaz).
    message(sprintf("Bayat üretici kilidi (%.0f dk) devralınıyor: %s", age_mins, lock_path))
    unlink(lock_path, recursive = TRUE, force = TRUE)
    if (!isTRUE(dir.create(lock_path, showWarnings = FALSE))) {
      stop(sprintf(
        "Üretici kilidi devralınamadı (başka bir süreç aynı anda kazandı): %s",
        lock_path
      ), call. = FALSE)
    }
  }

  writeLines(sprintf("pid=%s host=%s at=%s", Sys.getpid(),
                     Sys.info()[["nodename"]], format(Sys.time())),
            .speech_gen_lock_owner_path(lock_path))
  invisible(lock_path)
}

#' Kilit sahip dosyasını yeniden yaz (mtime'ını tazeler). Uzun süren üretim
#' koşuları sırasında speech_gen_run() döngüsünde periyodik çağrılır ki
#' speech_gen_acquire_lock()'un yaşa dayalı bayatlık kontrolü hâlâ aktif bir
#' koşuyu bayat sanıp devralmasın. Kilit bu köke ait değilse (henüz
#' alınmamış/serbest bırakılmış) sessizce hiçbir şey yapmaz.
speech_gen_lock_heartbeat <- function(root = mergen_speech_root()) {
  lock_path <- mergen_speech_generator_lock_path(root)
  if (!dir.exists(lock_path)) return(invisible(FALSE))
  writeLines(sprintf("pid=%s host=%s at=%s", Sys.getpid(),
                     Sys.info()[["nodename"]], format(Sys.time())),
            .speech_gen_lock_owner_path(lock_path))
  invisible(TRUE)
}

speech_gen_release_lock <- function(root = mergen_speech_root()) {
  unlink(mergen_speech_generator_lock_path(root), recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

# --- Ortam ve metin ağacı doğrulaması ---

speech_gen_env_check <- function(root = mergen_speech_root(), verbose = TRUE) {
  problems <- character(0)

  for (pkg in c("httr", "jsonlite", "openssl", "base64enc", "curl")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      problems <- c(problems, sprintf("Gerekli paket eksik: %s", pkg))
    }
  }

  endpoint <- mergen_voxcpm2_endpoint_url()
  if (!nzchar(endpoint)) {
    problems <- c(problems, "LOCAL_TTS_ENDPOINT tanımlı değil (.Renviron kontrol edin).")
  }

  api_key <- speech_gen_resolve_tts_api_key()
  if (!nzchar(api_key)) {
    problems <- c(
      problems,
      paste0(
        "TTS API anahtarı bulunamadı. ",
        "LOCAL_TTS_API_KEY, LOCAL_LLM_API_KEY veya ",
        "MERGEN_SPEECH_API_KEY_USER ayarını kontrol edin."
      )
    )
  }

  tree <- speech_gen_validate_script_tree(root)
  problems <- c(problems, tree$problems)

  if (isTRUE(verbose)) {
    if (length(problems) == 0) {
      message(sprintf(
        "Ortam kontrolü BAŞARILI: uç nokta yapılandırılmış, API anahtarı mevcut (%d karakter), %d ortak metin doğrulandı.",
        nchar(api_key), nrow(tree$scripts)
      ))
    } else {
      message("Ortam kontrolü SORUNLAR buldu:")
      for (p in problems) message("  - ", p)
    }
  }

  invisible(list(ok = length(problems) == 0, problems = problems, scripts = tree$scripts))
}

speech_gen_validate_script_tree <- function(root = mergen_speech_root()) {
  problems <- character(0)
  expected <- mergen_speech_expected_assets(root)

  for (i in seq_len(nrow(expected))) {
    path <- expected$script_path[i]
    if (!file.exists(path)) {
      problems <- c(problems, sprintf("Metin dosyası eksik: %s", path))
      next
    }
    txt <- .speech_read_utf8_text(path)
    if (is.null(txt)) {
      problems <- c(problems, sprintf("Metin UTF-8 olarak okunamadı (mojibake?): %s", path))
    } else if (!nzchar(txt)) {
      problems <- c(problems, sprintf("Metin boş: %s", path))
    } else if (grepl("\\x{00C3}|\\x{00C4}|\\x{00C5}", txt, perl = TRUE)) {
      problems <- c(problems, sprintf("Metin mojibake içeriyor görünümünde: %s", path))
    }
  }

  n_expected <- mergen_speech_expected_script_count()
  if (nrow(expected) != n_expected) {
    problems <- c(problems, sprintf(
      "Beklenen metin sayısı tutarsız: %d != %d", nrow(expected), n_expected
    ))
  }

  list(ok = length(problems) == 0, problems = problems, scripts = expected)
}

# --- Üretim durumu (resume/skip için persona başına sidecar) ---

speech_gen_state_read <- function(persona, root = mergen_speech_root()) {
  path <- mergen_speech_generation_state_path(persona, root)
  if (!file.exists(path)) return(list())
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
}

speech_gen_state_write <- function(persona, state, root = mergen_speech_root()) {
  path <- mergen_speech_generation_state_path(persona, root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, pretty = TRUE, null = "null")
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  con <- file(tmp, "wb"); writeBin(charToRaw(enc2utf8(as.character(json))), con); close(con)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(TRUE)
}

# --- Yeniden deneme sınıflandırması ---

speech_gen_should_retry <- function(http_status, error_text = "") {
  if (!is.na(http_status)) {
    if (http_status == 429L) return(TRUE)
    if (http_status %in% c(500L, 502L, 503L, 504L)) return(TRUE)
    if (http_status >= 400L && http_status < 500L) return(FALSE)
  }
  err <- tolower(as.character(error_text %||% ""))
  grepl("timeout|timed out|zaman aşımı|connection|could not resolve|reset", err)
}

speech_gen_backoff_secs <- function(attempt, base = 2, max_secs = 30) {
  min(base * (2 ^ (attempt - 1L)), max_secs)
}

# --- Atomik WAV yazımı: geçici dosya -> doğrulama -> hedefe taşıma ---

speech_gen_write_wav_atomic <- function(audio_raw, final_path,
                                        expected = mergen_speech_expected_wav_profile()) {
  dir.create(dirname(final_path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(final_path, ".tmp_", Sys.getpid())

  con <- file(tmp, "wb")
  writeBin(audio_raw, con)
  close(con)

  check <- mergen_wav_validate(tmp, expected = expected)
  if (!isTRUE(check$ok)) {
    unlink(tmp)

    return(list(
      ok = FALSE,
      reason = check$reason,
      info = check$info,
      expected = expected
    ))
  }

  if (!file.rename(tmp, final_path)) {
    ok <- file.copy(tmp, final_path, overwrite = TRUE)
    unlink(tmp)
    if (!isTRUE(ok)) return(list(ok = FALSE, reason = "hedefe_tasinamadi"))
  }

  list(ok = TRUE, reason = NULL, info = check$info)
}

# --- Tek varlık sentezi (sınırlı yeniden denemeyle) ---

speech_gen_synthesize_wav <- function(text, reference, profile,
                                      max_attempts = 3,
                                      synth_fn = NULL,
                                      sleep_fn = Sys.sleep) {
  if (is.null(synth_fn)) {
    endpoint <- mergen_voxcpm2_endpoint_url()
    api_key <- speech_gen_resolve_tts_api_key()
    timeout_val <- suppressWarnings(as.numeric(Sys.getenv("LOCAL_TTS_TIMEOUT", "120")))
    if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 120
    verify_ssl <- !tolower(Sys.getenv("LOCAL_TTS_VERIFY_SSL", "TRUE")) %in%
      c("false", "f", "0", "no")

    synth_fn <- function(body) {
      mergen_voxcpm2_synthesize_blocking(
        body = body, endpoint_url = endpoint, api_key = api_key,
        timeout_seconds = timeout_val, verify_ssl = verify_ssl
      )
    }
  }

  body <- mergen_voxcpm2_request_body(
    profile = profile, text = text, reference = reference,
    response_format = "wav"
  )

  for (attempt in seq_len(max_attempts)) {
    res <- synth_fn(body)
    if (isTRUE(res$success)) return(res)

    if (!speech_gen_should_retry(res$http_status %||% NA_integer_, res$error)) {
      return(res)
    }
    if (attempt < max_attempts) {
      wait <- speech_gen_backoff_secs(attempt)
      message(sprintf("    Geçici hata, %d sn sonra yeniden denenecek (%d/%d): %s",
                      wait, attempt, max_attempts, res$error %||% ""))
      sleep_fn(wait)
    }
  }
  res
}

# --- Üretim planı: hangi varlıklar atlanır, hangileri üretilir ---

speech_gen_plan <- function(persona, root = mergen_speech_root(),
                            overwrite = FALSE, max_files = NULL) {
  expected <- mergen_speech_expected_assets(root)
  state <- speech_gen_state_read(persona, root)
  wav_profile <- mergen_speech_expected_wav_profile()

  lock <- mergen_speech_voice_lock_read(persona, root)
  lock_sha <- mergen_speech_sha256_file(mergen_speech_voice_lock_path(persona, root))
  profile <- mergen_speech_voice_profile(persona, root)
  profile_fp <- mergen_speech_profile_identity_fingerprint(profile)

  actions <- character(nrow(expected))
  reasons <- character(nrow(expected))
  audio_paths <- character(nrow(expected))

  for (i in seq_len(nrow(expected))) {
    row <- expected[i, ]
    page <- if (is.na(row$page)) NULL else row$page
    audio_path <- mergen_speech_audio_path(persona, row$scenario, page, row$variant, root)
    audio_paths[i] <- audio_path

    if (isTRUE(overwrite)) {
      actions[i] <- "generate"; reasons[i] <- "overwrite_istendi"; next
    }
    if (!file.exists(audio_path)) {
      actions[i] <- "generate"; reasons[i] <- "dosya_yok"; next
    }

    # Var olan dosyayı atlamak için TÜM koşullar sağlanmalı:
    # WAV geçerli + metin özeti + ses özeti + kilit özeti + profil parmak izi
    entry <- state[[row$id]]
    if (is.null(entry)) {
      actions[i] <- "generate"; reasons[i] <- "durum_kaydi_yok"; next
    }

    script_text <- .speech_read_utf8_text(row$script_path)
    if (is.null(script_text) ||
        !identical(mergen_speech_sha256_text(script_text),
                   as.character(entry$script_sha256))) {
      actions[i] <- "generate"; reasons[i] <- "metin_degisti"; next
    }

    if (!identical(as.character(entry$voice_lock_sha256), lock_sha)) {
      actions[i] <- "generate"; reasons[i] <- "voice_lock_degisti"; next
    }
    if (!identical(as.character(entry$profile_fingerprint), profile_fp)) {
      actions[i] <- "generate"; reasons[i] <- "profil_degisti"; next
    }

    wav_check <- mergen_wav_validate(audio_path, expected = wav_profile)
    if (!isTRUE(wav_check$ok)) {
      actions[i] <- "generate"; reasons[i] <- sprintf("wav_gecersiz:%s", wav_check$reason); next
    }
    if (!identical(mergen_speech_sha256_file(audio_path),
                   as.character(entry$audio_sha256))) {
      actions[i] <- "generate"; reasons[i] <- "ses_ozeti_uyusmuyor"; next
    }

    actions[i] <- "skip"; reasons[i] <- "gecerli_mevcut"
  }

  plan <- cbind(expected, data.frame(
    audio_path = audio_paths, action = actions, reason = reasons,
    stringsAsFactors = FALSE
  ))

  if (!is.null(max_files)) {
    gen_idx <- which(plan$action == "generate")
    if (length(gen_idx) > max_files) {
      plan$action[gen_idx[-seq_len(max_files)]] <- "deferred"
      plan$reason[gen_idx[-seq_len(max_files)]] <- "max_files_siniri"
    }
  }

  plan
}

# --- Persona koşusu: plan -> sentez -> atomik yazım -> durum -> rapor ---

speech_gen_run <- function(persona, root = mergen_speech_root(),
                           overwrite = FALSE, max_files = NULL,
                           preview = FALSE, synth_fn = NULL) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) stop("Geçersiz persona kimliği.", call. = FALSE)

  lock_validation <- mergen_speech_voice_lock_validate(persona, root)
  if (!isTRUE(lock_validation$ok)) {
    stop(sprintf(
      paste0("Persona '%s' için onaylı referans yok veya geçersiz (%s). Önce ",
             "generate_reference_candidate('%s') + approve_reference_voice('%s') çalıştırın."),
      persona, lock_validation$reason, persona, persona
    ), call. = FALSE)
  }

  plan <- speech_gen_plan(persona, root, overwrite = overwrite, max_files = max_files)
  gen_rows <- which(plan$action == "generate")

  message(sprintf(
    "Persona '%s': %d üretilecek, %d atlanacak, %d ertelendi.",
    persona, length(gen_rows), sum(plan$action == "skip"), sum(plan$action == "deferred")
  ))

  if (isTRUE(preview)) {
    message("Önizleme modu: hiçbir dosya yazılmadı.")
    return(invisible(list(persona = persona, plan = plan, generated = 0L,
                          skipped = sum(plan$action == "skip"), failed = 0L,
                          preview = TRUE)))
  }

  if (length(gen_rows) == 0) {
    return(invisible(list(persona = persona, plan = plan, generated = 0L,
                          skipped = sum(plan$action == "skip"), failed = 0L,
                          preview = FALSE)))
  }

  speech_gen_acquire_lock(root)
  on.exit(speech_gen_release_lock(root), add = TRUE)

  reference <- mergen_speech_reference_payload(persona, root)
  if (!isTRUE(reference$ok)) {
    stop(sprintf("Referans yükü çözülemedi: %s", reference$reason), call. = FALSE)
  }

  profile <- reference$profile
  lock_sha <- mergen_speech_sha256_file(mergen_speech_voice_lock_path(persona, root))
  profile_fp <- mergen_speech_profile_identity_fingerprint(profile)
  state <- speech_gen_state_read(persona, root)

  started_at <- Sys.time()
  generated <- 0L
  failed <- character(0)

  for (i in gen_rows) {
    row <- plan[i, ]
    script_text <- .speech_read_utf8_text(row$script_path)
    if (is.null(script_text) || !nzchar(script_text)) {
      failed <- c(failed, sprintf("%s (metin okunamadı)", row$id))
      next
    }

    message(sprintf("  [%d/%d] %s sentezleniyor...",
                    match(i, gen_rows), length(gen_rows), row$id))

    res <- speech_gen_synthesize_wav(script_text, reference, profile,
                                     synth_fn = synth_fn)
    if (!isTRUE(res$success)) {
      failed <- c(failed, sprintf("%s (%s)", row$id,
                                  mergen_voxcpm2_redact(res$error %||% "hata")))
      next
    }

    write_res <- speech_gen_write_wav_atomic(res$audio_raw, row$audio_path)
    if (!isTRUE(write_res$ok)) {
      failed <- c(failed, sprintf("%s (yazım: %s)", row$id, write_res$reason))
      next
    }

    state[[row$id]] <- list(
      script_sha256 = mergen_speech_sha256_text(script_text),
      audio_sha256 = mergen_speech_sha256_file(row$audio_path),
      voice_lock_sha256 = lock_sha,
      profile_fingerprint = profile_fp,
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    )
    # Durum her dosyadan sonra atomik yazılır: kesinti sonrası kaldığı yerden sürer
    speech_gen_state_write(persona, state, root)
    generated <- generated + 1L
    # Kilit sahip dosyasını tazele: 750 dosyalık uzun bir koşu stale_minutes'i
    # aşarsa bile hâlâ aktif olduğu için başka bir oturum tarafından devralınmasın.
    speech_gen_lock_heartbeat(root)
  }

  elapsed <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
  message(sprintf(
    "Persona '%s' tamamlandı: %d üretildi, %d atlandı, %d başarısız, %.1f sn.",
    persona, generated, sum(plan$action == "skip"), length(failed), elapsed
  ))
  if (length(failed) > 0) {
    message("Başarısız varlıklar:")
    for (f in utils::head(failed, 20)) message("  - ", f)
  }

  invisible(list(persona = persona, plan = plan, generated = generated,
                 skipped = sum(plan$action == "skip"),
                 failed = length(failed), failed_ids = failed,
                 elapsed_secs = elapsed, preview = FALSE))
}

# --- VoxCPM2 Voice Design sözleşmesi (aday referans üretimi) ---
# VM'de DOĞRULANMIŞ sözleşme: tests/scripts/test_voxcpm2_persona_voices.R beş
# FARKLI persona sesini aynı servise karşı bu istek biçimiyle başarıyla üretir:
#   - `voice` alanı HER ZAMAN "default"tur. Bu VoxCPM2 kurulumunda KAYITLI
#     ses adları yoktur; kayıtlı olmayan bir ad
#     gönderilirse servis yönlendiricisi HTTP 503 "No Healthy Address Found"
#     döndürür. LOCAL_TTS_VOICE bu isteğe asla sızmamalıdır.
#   - Doğal dil ses tasarımı tanımı `input` metninin BAŞINA parantez içinde
#     eklenir: "(<tasarım>)<metin>".
#   - Referans klonlama alanları (ref_audio/ref_text) bu aşamada gönderilmez.

#' Beş personanın amaçlanan Voice Design tanımları (üretici tek kaynağı).
#' Metinler VM'de doğrulanan tests/scripts/test_voxcpm2_persona_voices.R
#' betiğiyle birebir aynıdır; üç erkek (emre, deniz, can) + iki kadın
#' (selin, ipek) AYRI konuşmacıdır. Kayıtlı ses adı DEĞİL, VoxCPM2 Voice
#' Design özelliğine gönderilen doğal dil tanımlarıdır.
speech_gen_voice_design_descriptions <- function() {
  list(
    emre = paste(
      "An adult Turkish male voice with a calm, balanced and trustworthy presence.",
      "Warm but restrained, medium-low pitch, natural professional tone.",
      "He sounds pragmatic, reassuring and clear, never theatrical or overly dramatic.",
      "Native-level fluent Standard Turkish pronunciation, precise articulation, normal pace and short natural pauses."
    ),
    selin = paste(
      "An adult Turkish female voice that sounds constructive, confident and solution-oriented.",
      "Clear medium pitch, professional warmth and a positive forward-moving energy.",
      "She sounds capable and encouraging without becoming overly cheerful or promotional.",
      "Native-level fluent Standard Turkish pronunciation, crisp articulation, normal pace and natural pauses."
    ),
    deniz = paste(
      "An adult Turkish male strategist with a composed, thoughtful and analytical voice.",
      "Low to medium-low pitch, measured delivery and quiet confidence.",
      "He sounds long-term oriented and structured, with deliberate emphasis on important points.",
      "Native-level fluent Standard Turkish pronunciation, clear articulation, moderately measured pace and natural pauses."
    ),
    can = paste(
      "An adult Turkish male voice that is precise, disciplined and respectfully critical.",
      "Medium pitch, firm but calm delivery, with crisp and direct articulation.",
      "He sounds attentive to risks and evidence, never harsh, aggressive or sarcastic.",
      "Native-level fluent Standard Turkish pronunciation, controlled pace and short natural pauses."
    ),
    ipek = paste(
      "An adult Turkish female teacher and guide with a warm, patient and empathetic voice.",
      "Clear medium pitch, gentle confidence and an approachable professional tone.",
      "She explains calmly and reassuringly, without sounding childish, artificial or exaggerated.",
      "Native-level fluent Standard Turkish pronunciation, very clear articulation, comfortable pace and natural pauses."
    )
  )
}

#' VOXCPM2_DESIGN_VOICE_<PERSONA> ortam değişkeni adı. ASCII chartr kullanılır;
#' Türkçe yerel ayarda toupper("ipek") "İPEK" ürettiği için toupper güvensizdir.
.speech_gen_design_env_name <- function(persona) {
  paste0(
    "VOXCPM2_DESIGN_VOICE_",
    chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", persona)
  )
}

#' Override değeri doğal dil ses tasarımı tanımı DEĞİL gibi görünüyorsa TRUE.
#' VOXCPM2_DESIGN_VOICE_* değişkenleri kayıtlı ses kimliği, eski takma ad
#' (eski takma ad/default) veya sayısal tohum olarak KULLANILAMAZ;
#' böyle değerler yok sayılır ve yerleşik tanıma düşülür.
.speech_gen_design_override_gecersiz <- function(value) {
  v <- trimws(as.character(value)[1])
  v <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", v)
  if (!nzchar(v)) return(TRUE)
  if (identical(v, "default")) return(TRUE)
  if (grepl("^tr-(male|female)-[0-9]+$", v)) return(TRUE)
  if (grepl("^[-+.]?[0-9][0-9.]*$", v)) return(TRUE)
  FALSE
}

#' Persona için etkin Voice Design tanımını çöz: geçerli bir doğal dil
#' override'ı varsa o, yoksa yerleşik tanım döner. Tanım `voice` alanına
#' DEĞİL, input metninin başına gider.
speech_gen_voice_design_description <- function(persona) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) return(NA_character_)

  env_name <- .speech_gen_design_env_name(persona)
  override <- Sys.getenv(env_name, "")
  if (nzchar(trimws(override))) {
    if (!.speech_gen_design_override_gecersiz(override)) return(trimws(override))
    message(sprintf(
      paste0("%s değeri doğal dil ses tasarımı tanımı değil (kayıtlı ses adı ",
             "veya sayısal tohum görünümünde); yok sayıldı, yerleşik tanım kullanılacak."),
      env_name
    ))
  }

  as.character(speech_gen_voice_design_descriptions()[[persona]])
}

# --- Referans adayı üretimi ve onay/kilitleme ---

speech_gen_reference_candidate <- function(persona, root = mergen_speech_root(),
                                           synth_fn = NULL) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) stop("Geçersiz persona kimliği.", call. = FALSE)

  profile <- mergen_speech_voice_profile(persona, root)
  ref_text <- .speech_read_utf8_text(profile$reference_text_path)
  if (is.null(ref_text) || !nzchar(ref_text)) {
    stop(sprintf("Referans metni okunamadı: %s", profile$reference_text_path), call. = FALSE)
  }

  # Aday üretimi referanssız ses TASARIMI isteğidir ve yukarıdaki doğrulanmış
  # VoxCPM2 Voice Design sözleşmesini kullanmak ZORUNDADIR: voice = "default",
  # doğal dil tasarım tanımı input'un başında, referans alanları gönderilmez.
  design <- speech_gen_voice_design_description(persona)
  if (is.na(design) || !nzchar(design)) {
    stop(sprintf("Persona '%s' için ses tasarımı tanımı çözülemedi.", persona),
         call. = FALSE)
  }

  body <- list(
    model = profile$model,
    input = paste0("(", design, ")", ref_text),
    voice = "default",
    response_format = "wav"
  )
  for (nm in names(profile$identity_params)) {
    param <- profile$identity_params[[nm]]
    if (!is.null(param) && !is.na(param)) body[[nm]] <- param
  }

  if (is.null(synth_fn)) {
    endpoint <- mergen_voxcpm2_endpoint_url()
    api_key <- speech_gen_resolve_tts_api_key()
    verify_ssl <- !tolower(Sys.getenv("LOCAL_TTS_VERIFY_SSL", "TRUE")) %in%
      c("false", "f", "0", "no")
    synth_fn <- function(b) {
      mergen_voxcpm2_synthesize_blocking(
        body = b, endpoint_url = endpoint, api_key = api_key,
        timeout_seconds = 120, verify_ssl = verify_ssl
      )
    }
  }

  res <- synth_fn(body)
  if (!isTRUE(res$success)) {
    stop(sprintf("Aday referans sentezi başarısız: %s",
                 mergen_voxcpm2_redact(res$error %||% "hata")), call. = FALSE)
  }

  candidate_path <- mergen_speech_candidate_reference_path(persona, root)
  write_res <- speech_gen_write_wav_atomic(res$audio_raw, candidate_path)

  if (!isTRUE(write_res$ok)) {
    rate_details <- ""

    if (identical(write_res$reason, "ornekleme_hizi_uyusmuyor") &&
        !is.null(write_res$info) &&
        !is.null(write_res$expected)) {
      rate_details <- sprintf(
        " (beklenen=%s Hz, gerçek=%s Hz)",
        write_res$expected$sample_rate %||% "bilinmiyor",
        write_res$info$sample_rate %||% "bilinmiyor"
      )
    }

    stop(
      sprintf(
        "Aday WAV doğrulanamadı/yazılamadı: %s%s",
        write_res$reason,
        rate_details
      ),
      call. = FALSE
    )
  }

  message(sprintf(
    paste0("Aday referans üretildi: %s\nLütfen dosyayı DİNLEYİN. Ses uygunsa ",
           "approve_reference_voice(\"%s\") ile onaylayın; değilse yeniden üretin."),
    candidate_path, persona
  ))
  invisible(candidate_path)
}

speech_gen_reference_approve <- function(persona, root = mergen_speech_root(),
                                         reset_reference = FALSE) {
  persona <- mergen_speech_canonical_persona(persona)
  if (is.na(persona)) stop("Geçersiz persona kimliği.", call. = FALSE)

  profile <- mergen_speech_voice_profile(persona, root)
  lock_path <- profile$voice_lock_path

  if (file.exists(lock_path) && !isTRUE(reset_reference)) {
    stop(sprintf(
      paste0("Persona '%s' için onaylı referans ZATEN var. Sessizce değiştirilmez. ",
             "Bilinçli değişim için approve_reference_voice(\"%s\", reset_reference = TRUE) ",
             "kullanın; bu, personanın üretilmiş TÜM WAV'larını geçersiz kılar ve ",
             "yeniden üretim gerektirir."),
      persona, persona
    ), call. = FALSE)
  }

  candidate_path <- mergen_speech_candidate_reference_path(persona, root)
  if (!file.exists(candidate_path)) {
    stop(sprintf(
      "Aday referans yok: %s. Önce generate_reference_candidate(\"%s\") çalıştırın.",
      candidate_path, persona
    ), call. = FALSE)
  }

  check <- mergen_wav_validate(candidate_path,
                               expected = mergen_speech_expected_wav_profile(),
                               min_ms = 500)
  if (!isTRUE(check$ok)) {
    stop(sprintf("Aday WAV doğrulanamadı (%s); onay iptal edildi.", check$reason),
         call. = FALSE)
  }

  ref_text <- .speech_read_utf8_text(profile$reference_text_path)
  if (is.null(ref_text) || !nzchar(ref_text)) {
    stop("Referans metni okunamadı; onay iptal edildi.", call. = FALSE)
  }

  if (isTRUE(reset_reference) && file.exists(lock_path)) {
    # generator.lock'u BURADA al ve fonksiyon çıkana kadar tut (aşağıdaki
    # yeni referans/kilit yazımını da kapsar). Başka bir oturumun
    # speech_gen_run()'ı bu kilidi ZATEN tutuyorsa (aktif üretim sürüyorsa)
    # bu çağrı güvenle hata verir; aksi halde o koşu ESKİ referans yükünü
    # zaten yakalamış olabileceğinden, resetimiz sonrasında da eski sesle
    # WAV üretmeye devam edip YENİ kilidin üzerine yazabilirdi.
    speech_gen_acquire_lock(root)
    on.exit(speech_gen_release_lock(root), add = TRUE)

    old_state <- speech_gen_state_read(persona, root)
    message(sprintf(
      paste0("UYARI: Persona '%s' referansı SIFIRLANIYOR. Bu personaya ait üretilmiş ",
             "%d varlık kaydı geçersiz kılınacak ve sonraki koşuda yeniden üretilecek."),
      persona, length(old_state)
    ))
    speech_gen_state_write(persona, list(), root)

    # Durum kaydını temizlemek TEK BAŞINA yeterli değildir: mergen_speech_
    # manifest_build() üretici sidecar durumuna değil yalnızca WAV başlığına
    # (format) bakar, bu yüzden eski sesle üretilmiş bir WAV, YENİ voice-lock
    # kimliği altında geçerli görünüp yayınlanabilir (üretici yarıda kesilse/
    # atlansa bile). Eski WAV'ları hemen silmek bu pencereyi kapatır: eksik
    # dosyalar generate_speech_manifest()'i fail-closed biçimde engeller,
    # yeniden üretim tamamlanana kadar eski ses hiçbir zaman yeni kimlik
    # altında sunulmaz.
    audio_root <- mergen_speech_persona_audio_root(persona, root)
    if (dir.exists(audio_root)) {
      removed_n <- length(list.files(audio_root, pattern = "\\.wav$",
                                     recursive = TRUE, ignore.case = TRUE))
      unlink(audio_root, recursive = TRUE, force = TRUE)
      message(sprintf(
        "Persona '%s' için %d eski ses dosyası silindi (eski sesle karışma önlendi).",
        persona, removed_n
      ))
    }
  }

  # Adayı atomik kur, sonra kilidi yaz
  final_wav <- profile$reference_wav_path
  dir.create(dirname(final_wav), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(final_wav, ".tmp_", Sys.getpid())
  file.copy(candidate_path, tmp, overwrite = TRUE)
  if (!file.rename(tmp, final_wav)) {
    file.copy(tmp, final_wav, overwrite = TRUE); unlink(tmp)
  }

  lock_payload <- mergen_speech_voice_lock_payload(profile, final_wav, ref_text)
  json <- jsonlite::toJSON(lock_payload, auto_unbox = TRUE, pretty = TRUE, null = "null")
  lock_tmp <- paste0(lock_path, ".tmp_", Sys.getpid())
  con <- file(lock_tmp, "wb"); writeBin(charToRaw(enc2utf8(as.character(json))), con); close(con)
  if (!file.rename(lock_tmp, lock_path)) {
    file.copy(lock_tmp, lock_path, overwrite = TRUE); unlink(lock_tmp)
  }

  mergen_speech_reference_cache_clear()

  validation <- mergen_speech_voice_lock_validate(persona, root)
  if (!isTRUE(validation$ok)) {
    stop(sprintf("Kilit yazıldı ama doğrulanamadı (%s); durumu inceleyin.",
                 validation$reason), call. = FALSE)
  }

  message(sprintf(
    "Persona '%s' referansı ONAYLANDI ve kilitlendi:\n  %s\n  %s",
    persona, final_wav, lock_path
  ))
  invisible(TRUE)
}
