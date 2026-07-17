# tools/speech/helpers_speech_chunked_assets.R
# VoxCPM2 servisinin yaklaşık 10 saniyelik sabit çıktı tavanına karşı statik
# konuşma varlıklarını kısa metin parçalarıyla üretir. Her parça aynı kilitli
# persona referansıyla sentezlenir; sınır sessizlikleri güvenli pay bırakılarak
# kırpılır, noktalama işaretine göre kısa bir boşluk eklenir ve PCM verileri tek
# bir geçerli WAV içinde birleştirilir. Bu dosya yalnızca operatör üreticisinde
# source edilir; canlı TTS çalışma zamanını değiştirmez.

SPEECH_GEN_CHUNK_PIPELINE_VERSION <- "chunked_pcm_v1"

.speech_gen_chunk_env_int <- function(name, default, minimum = 0L) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, as.character(default))))
  if (is.na(value) || value < minimum) as.integer(default) else value
}

#' Statik varlık üretiminde kullanılan parça/kırpma/geçiş ayarları.
speech_gen_chunking_config <- function() {
  max_chars <- .speech_gen_chunk_env_int(
    "VOXCPM2_ASSET_MAX_CHUNK_CHARS", 110L, minimum = 20L
  )
  min_chars <- .speech_gen_chunk_env_int(
    "VOXCPM2_ASSET_MIN_CHUNK_CHARS", 35L, minimum = 0L
  )
  if (min_chars > max_chars) min_chars <- max_chars

  list(
    max_chunk_chars = max_chars,
    min_chunk_chars = min_chars,
    trim_threshold = .speech_gen_chunk_env_int(
      "VOXCPM2_ASSET_TRIM_THRESHOLD", 250L, minimum = 0L
    ),
    trim_keep_ms = .speech_gen_chunk_env_int(
      "VOXCPM2_ASSET_TRIM_KEEP_MS", 25L, minimum = 0L
    ),
    sentence_gap_ms = .speech_gen_chunk_env_int(
      "VOXCPM2_ASSET_GAP_SENTENCE_MS", 45L, minimum = 0L
    ),
    clause_gap_ms = .speech_gen_chunk_env_int(
      "VOXCPM2_ASSET_GAP_CLAUSE_MS", 25L, minimum = 0L
    ),
    other_gap_ms = .speech_gen_chunk_env_int(
      "VOXCPM2_ASSET_GAP_OTHER_MS", 30L, minimum = 0L
    )
  )
}

#' Üretim sidecar'ında saklanan, ayar değişince eski WAV'ı geçersiz kılan imza.
speech_gen_generation_pipeline_signature <- function(
    config = speech_gen_chunking_config()) {
  values <- vapply(config, function(x) as.character(x)[1], character(1))
  paste(
    c(
      sprintf("version=%s", SPEECH_GEN_CHUNK_PIPELINE_VERSION),
      sprintf("%s=%s", names(values), values)
    ),
    collapse = "|"
  )
}

.speech_gen_normalize_space <- function(text) {
  gsub("\\s+", " ", trimws(as.character(text)[1]), perl = TRUE)
}

.speech_gen_split_piece_strict <- function(piece, max_chars) {
  piece <- trimws(as.character(piece)[1])
  if (!nzchar(piece)) return(character(0))
  if (nchar(piece) <= max_chars) return(piece)

  parts <- .ai_expert_split_long_piece(piece, max_chunk_chars = max_chars)
  parts <- trimws(as.character(parts))
  parts <- parts[nzchar(parts)]
  if (length(parts) > 0L && all(nchar(parts) <= max_chars)) return(parts)

  words <- unlist(strsplit(piece, "\\s+", perl = TRUE), use.names = FALSE)
  if (any(nchar(words) > max_chars)) {
    stop("Tek bir sözcük statik konuşma parçası sınırını aşıyor.", call. = FALSE)
  }

  out <- character(0)
  current <- ""
  for (word in words) {
    candidate <- trimws(paste(current, word))
    if (!nzchar(current) || nchar(candidate) <= max_chars) {
      current <- candidate
    } else {
      out <- c(out, current)
      current <- word
    }
  }
  if (nzchar(current)) out <- c(out, current)
  out
}

#' Metni noktalama sınırlarını koruyarak, kesin karakter tavanıyla parçalara ayır.
speech_gen_split_asset_text <- function(
    text,
    config = speech_gen_chunking_config()) {
  text <- trimws(as.character(text %||% "")[1])
  if (!nzchar(text)) return(character(0))
  if (nchar(text) <= config$max_chunk_chars) return(text)

  chunks <- unlist(
    split_text_for_ai_expert_tts(
      text,
      max_chunk_chars = config$max_chunk_chars,
      min_chunk_chars = config$min_chunk_chars
    ),
    use.names = FALSE
  )
  chunks <- trimws(as.character(chunks))
  chunks <- chunks[nzchar(chunks)]

  strict <- unlist(
    lapply(
      chunks,
      .speech_gen_split_piece_strict,
      max_chars = config$max_chunk_chars
    ),
    use.names = FALSE
  )
  strict <- trimws(strict)
  strict <- strict[nzchar(strict)]

  if (length(strict) == 0L || any(nchar(strict) > config$max_chunk_chars)) {
    stop("Konuşma metni güvenli parça boyutuna ayrılamadı.", call. = FALSE)
  }
  if (!identical(
    .speech_gen_normalize_space(paste(strict, collapse = " ")),
    .speech_gen_normalize_space(text)
  )) {
    stop("Konuşma metni parçalanırken içerik bütünlüğü bozuldu.", call. = FALSE)
  }

  strict
}

#' WAV raw yanıtını doğrula ve mono 16-bit PCM örneklerini çıkar.
.speech_gen_decode_pcm16_wav <- function(
    audio_raw,
    expected = mergen_speech_expected_wav_profile()) {
  fail <- function(reason, info = NULL) {
    list(ok = FALSE, reason = reason, info = info, samples = NULL)
  }

  if (!is.raw(audio_raw) || length(audio_raw) < 44L) {
    return(fail("kesik_dosya"))
  }
  if (!identical(as.integer(expected$channels), 1L) ||
      !identical(as.integer(expected$bits_per_sample), 16L)) {
    return(fail("parca_birlestirme_yalnizca_mono_pcm16"))
  }

  tmp <- tempfile(pattern = "speech_chunk_", fileext = ".wav")
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  con <- file(tmp, "wb")
  writeBin(audio_raw, con)
  close(con)

  check <- mergen_wav_validate(tmp, expected = expected)
  if (!isTRUE(check$ok)) return(fail(check$reason, check$info))

  position <- 13L
  payload <- NULL
  while (position + 7L <= length(audio_raw)) {
    chunk_id <- rawToChar(audio_raw[position:(position + 3L)])
    chunk_size <- sum(
      as.numeric(audio_raw[(position + 4L):(position + 7L)]) * 256^(0:3)
    )
    payload_start <- position + 8L
    payload_end <- payload_start + as.integer(chunk_size) - 1L

    if (is.na(chunk_size) || chunk_size < 0L || payload_end > length(audio_raw)) {
      return(fail("kesik_dosya", check$info))
    }
    if (identical(chunk_id, "data")) {
      payload <- audio_raw[payload_start:payload_end]
      break
    }
    position <- payload_end + 1L + as.integer(chunk_size %% 2L)
  }

  if (is.null(payload) || length(payload) == 0L) {
    return(fail("data_chunk_yok", check$info))
  }
  if (length(payload) %% 2L != 0L) {
    return(fail("pcm_ornek_hizasi_gecersiz", check$info))
  }

  pcm_con <- rawConnection(payload, open = "rb")
  on.exit(close(pcm_con), add = TRUE)
  samples <- readBin(
    pcm_con,
    what = integer(),
    n = length(payload) %/% 2L,
    size = 2L,
    signed = TRUE,
    endian = "little"
  )

  list(ok = TRUE, reason = NULL, info = check$info, samples = samples)
}

#' Parça başı/sonundaki uzun sessizliği, sessiz ünsüzleri koruyan payla kırp.
speech_gen_trim_pcm_boundary <- function(
    samples,
    sample_rate,
    amplitude_threshold = 250L,
    keep_ms = 25L) {
  samples <- as.integer(samples)
  if (length(samples) == 0L) return(samples)

  active <- which(abs(samples) >= as.integer(amplitude_threshold))
  if (length(active) == 0L) return(samples)

  keep_samples <- as.integer(round(sample_rate * keep_ms / 1000))
  first <- max(1L, min(active) - keep_samples)
  last <- min(length(samples), max(active) + keep_samples)
  samples[first:last]
}

#' Önceki parçanın son noktalamasına göre doğal geçiş boşluğu.
speech_gen_gap_ms_for_chunk <- function(
    text,
    config = speech_gen_chunking_config()) {
  text <- trimws(as.character(text)[1])
  if (!nzchar(text)) return(as.integer(config$other_gap_ms))
  if (grepl("[.!?…]$", text, perl = TRUE)) {
    return(as.integer(config$sentence_gap_ms))
  }
  if (grepl("[,;:]$", text, perl = TRUE)) {
    return(as.integer(config$clause_gap_ms))
  }
  as.integer(config$other_gap_ms)
}

# Kurulum tekrar source edilirse mevcut wrapper'ı wrapper içine sarmalama.
if (!isTRUE(attr(speech_gen_synthesize_wav, "speech_gen_chunk_wrapper"))) {
  .speech_gen_chunk_base_synthesize_wav <- speech_gen_synthesize_wav

  speech_gen_synthesize_wav <- function(text, reference, profile,
                                        max_attempts = 3,
                                        synth_fn = NULL,
                                        sleep_fn = Sys.sleep) {
    config <- speech_gen_chunking_config()
    chunks <- speech_gen_split_asset_text(text, config = config)
    if (length(chunks) == 0L) {
      return(list(
        success = FALSE, audio_raw = NULL, content_type = NA_character_,
        http_status = NA_integer_, error = "Seslendirilecek metin boş."
      ))
    }

    if (length(chunks) == 1L) {
      result <- .speech_gen_chunk_base_synthesize_wav(
        chunks[[1]], reference, profile,
        max_attempts = max_attempts,
        synth_fn = synth_fn,
        sleep_fn = sleep_fn
      )
      result$chunk_count <- 1L
      return(result)
    }

    expected <- mergen_speech_expected_wav_profile()
    trimmed_chunks <- vector("list", length(chunks))
    chunk_durations_ms <- numeric(length(chunks))

    for (i in seq_along(chunks)) {
      result <- .speech_gen_chunk_base_synthesize_wav(
        chunks[[i]], reference, profile,
        max_attempts = max_attempts,
        synth_fn = synth_fn,
        sleep_fn = sleep_fn
      )
      if (!isTRUE(result$success)) {
        result$error <- sprintf(
          "Parça %d/%d sentezlenemedi: %s",
          i, length(chunks), result$error %||% "bilinmeyen hata"
        )
        return(result)
      }

      decoded <- .speech_gen_decode_pcm16_wav(result$audio_raw, expected)
      if (!isTRUE(decoded$ok)) {
        return(list(
          success = FALSE,
          audio_raw = NULL,
          content_type = NA_character_,
          http_status = result$http_status %||% NA_integer_,
          error = sprintf(
            "Parça %d/%d WAV doğrulamasından geçemedi: %s",
            i, length(chunks), decoded$reason
          )
        ))
      }

      trimmed_chunks[[i]] <- speech_gen_trim_pcm_boundary(
        decoded$samples,
        sample_rate = expected$sample_rate,
        amplitude_threshold = config$trim_threshold,
        keep_ms = config$trim_keep_ms
      )
      chunk_durations_ms[[i]] <- decoded$info$duration_ms
    }

    combined_parts <- vector("list", length(chunks) * 2L - 1L)
    output_index <- 1L
    for (i in seq_along(trimmed_chunks)) {
      combined_parts[[output_index]] <- trimmed_chunks[[i]]
      output_index <- output_index + 1L

      if (i < length(trimmed_chunks)) {
        gap_ms <- speech_gen_gap_ms_for_chunk(chunks[[i]], config = config)
        gap_samples <- as.integer(round(expected$sample_rate * gap_ms / 1000))
        combined_parts[[output_index]] <- integer(gap_samples)
        output_index <- output_index + 1L
      }
    }

    combined_samples <- as.integer(do.call(c, combined_parts))
    combined_wav <- mergen_wav_build_pcm(
      n_samples = length(combined_samples),
      sample_rate = expected$sample_rate,
      channels = expected$channels,
      bits_per_sample = expected$bits_per_sample,
      samples = combined_samples
    )

    list(
      success = TRUE,
      audio_raw = combined_wav,
      content_type = "audio/wav",
      http_status = 200L,
      error = NULL,
      chunk_count = length(chunks),
      chunk_durations_ms = chunk_durations_ms
    )
  }
  attr(speech_gen_synthesize_wav, "speech_gen_chunk_wrapper") <- TRUE
}

# Eski (tek istekli) üretimle yazılmış WAV'ları sessizce atlama: sidecar imzası
# yoksa veya etkin parça ayarlarıyla uyuşmuyorsa yeniden üret.
if (!isTRUE(attr(speech_gen_plan, "speech_gen_chunk_wrapper"))) {
  .speech_gen_chunk_base_plan <- speech_gen_plan

  speech_gen_plan <- function(persona, root = mergen_speech_root(),
                              overwrite = FALSE, max_files = NULL) {
    plan <- .speech_gen_chunk_base_plan(
      persona,
      root = root,
      overwrite = overwrite,
      max_files = NULL
    )

    if (!isTRUE(overwrite)) {
      state <- speech_gen_state_read(persona, root)
      signature <- speech_gen_generation_pipeline_signature()
      skip_rows <- which(plan$action == "skip")
      for (i in skip_rows) {
        entry <- state[[plan$id[[i]]]]
        entry_signature <- as.character(
          entry$generation_pipeline_signature %||% ""
        )[1]
        if (!identical(entry_signature, signature)) {
          plan$action[[i]] <- "generate"
          plan$reason[[i]] <- "uretim_hatti_degisti"
        }
      }
    }

    if (!is.null(max_files)) {
      max_files <- suppressWarnings(as.integer(max_files))
      if (is.na(max_files) || max_files < 0L) max_files <- 0L
      gen_idx <- which(plan$action == "generate")
      if (length(gen_idx) > max_files) {
        deferred <- gen_idx[-seq_len(max_files)]
        plan$action[deferred] <- "deferred"
        plan$reason[deferred] <- "max_files_siniri"
      }
    }

    plan
  }
  attr(speech_gen_plan, "speech_gen_chunk_wrapper") <- TRUE
}

# Base koşu her başarılı WAV'dan sonra sidecar'ı yazar. Aşağıdaki izleyici,
# yalnızca o anda değişen girdiye üretim hattı imzasını ekler; böylece uzun bir
# koşu yarıda kesilirse tamamlanan dosyalar güvenle atlanarak devam edilebilir.
if (!exists(".speech_gen_chunk_state_tracker", inherits = FALSE) ||
    !is.environment(.speech_gen_chunk_state_tracker)) {
  .speech_gen_chunk_state_tracker <- new.env(parent = emptyenv())
}

.speech_gen_chunk_state_key <- function(persona, root) {
  paste(
    normalizePath(root, winslash = "/", mustWork = FALSE),
    as.character(persona)[1],
    sep = "::"
  )
}

if (!isTRUE(attr(speech_gen_state_write, "speech_gen_chunk_wrapper"))) {
  .speech_gen_chunk_base_state_write <- speech_gen_state_write

  speech_gen_state_write <- function(persona, state,
                                     root = mergen_speech_root()) {
    key <- .speech_gen_chunk_state_key(persona, root)
    previous <- get0(
      key,
      envir = .speech_gen_chunk_state_tracker,
      inherits = FALSE,
      ifnotfound = NULL
    )

    if (!is.null(previous)) {
      signature <- speech_gen_generation_pipeline_signature()
      for (id in names(state)) {
        current_entry <- state[[id]]
        previous_entry <- previous[[id]]
        changed <- is.null(previous_entry) ||
          !identical(
            as.character(current_entry$audio_sha256 %||% ""),
            as.character(previous_entry$audio_sha256 %||% "")
          ) ||
          !identical(
            as.character(current_entry$generated_at %||% ""),
            as.character(previous_entry$generated_at %||% "")
          )

        if (isTRUE(changed) &&
            nzchar(as.character(current_entry$audio_sha256 %||% ""))) {
          current_entry$generation_pipeline_signature <- signature
          state[[id]] <- current_entry
        }
      }
    }

    result <- .speech_gen_chunk_base_state_write(persona, state, root)
    if (!is.null(previous)) {
      assign(key, state, envir = .speech_gen_chunk_state_tracker)
    }
    result
  }
  attr(speech_gen_state_write, "speech_gen_chunk_wrapper") <- TRUE
}

if (!isTRUE(attr(speech_gen_run, "speech_gen_chunk_wrapper"))) {
  .speech_gen_chunk_base_run <- speech_gen_run

  speech_gen_run <- function(persona, root = mergen_speech_root(),
                             overwrite = FALSE, max_files = NULL,
                             preview = FALSE, synth_fn = NULL) {
    canonical <- mergen_speech_canonical_persona(persona)
    if (is.na(canonical)) {
      return(.speech_gen_chunk_base_run(
        persona,
        root = root,
        overwrite = overwrite,
        max_files = max_files,
        preview = preview,
        synth_fn = synth_fn
      ))
    }
    key <- .speech_gen_chunk_state_key(canonical, root)
    assign(
      key,
      speech_gen_state_read(canonical, root),
      envir = .speech_gen_chunk_state_tracker
    )
    on.exit(
      rm(list = key, envir = .speech_gen_chunk_state_tracker),
      add = TRUE
    )

    .speech_gen_chunk_base_run(
      canonical,
      root = root,
      overwrite = overwrite,
      max_files = max_files,
      preview = preview,
      synth_fn = synth_fn
    )
  }
  attr(speech_gen_run, "speech_gen_chunk_wrapper") <- TRUE
}

# Manifest üretimi, yarım kalmış bir geçişte eski tek-istek WAV'larını yeni
# parça hattıyla karıştırmamalıdır. Sidecar imzası uyuşmayan varlıklar manifest
# dışında bırakılır ve üretim fail-closed biçimde başarısız sayılır.
if (!isTRUE(attr(mergen_speech_manifest_build, "speech_gen_chunk_wrapper"))) {
  .speech_gen_chunk_base_manifest_build <- mergen_speech_manifest_build

  mergen_speech_manifest_build <- function(
      root = mergen_speech_root(),
      generator_version = "1.0.0") {
    result <- .speech_gen_chunk_base_manifest_build(
      root = root,
      generator_version = generator_version
    )
    signature <- speech_gen_generation_pipeline_signature()

    for (persona in names(result$manifest$personas %||% list())) {
      state_path <- mergen_speech_generation_state_path(persona, root)
      if (!file.exists(state_path)) next

      state <- mergen_speech_generation_state_read(persona, root)
      persona_entry <- result$manifest$personas[[persona]]
      assets <- persona_entry$assets %||% list()
      if (length(assets) == 0L) next

      keep <- rep(TRUE, length(assets))
      for (i in seq_along(assets)) {
        asset_id <- as.character(assets[[i]]$id %||% "")[1]
        state_entry <- state[[asset_id]]
        state_signature <- as.character(
          state_entry$generation_pipeline_signature %||% ""
        )[1]
        if (!identical(state_signature, signature)) {
          keep[[i]] <- FALSE
          result$problems <- c(
            result$problems,
            sprintf(
              paste0(
                "persona '%s': üretim hattı imzası bayat/eksik; ",
                "WAV yeniden üretilmeli: %s"
              ),
              persona, asset_id
            )
          )
        }
      }

      persona_entry$assets <- assets[keep]
      result$manifest$personas[[persona]] <- persona_entry
    }

    result$manifest$audio_count <- sum(vapply(
      result$manifest$personas %||% list(),
      function(entry) length(entry$assets %||% list()),
      integer(1)
    ))
    result$problems <- unique(result$problems)
    result$ok <- length(result$problems) == 0L
    result
  }
  attr(mergen_speech_manifest_build, "speech_gen_chunk_wrapper") <- TRUE
}
