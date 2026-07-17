# R/helpers_speech_manifest.R
# speech_manifest.json üretimi, doğrulaması ve çalışma zamanı yüklemesi.
# Manifest her zaman gerçek varlıklardan (ortak metinler, WAV başlıkları,
# dosya özetleri, onaylı voice-lock) OTOMATİK türetilir; elle alan girilmez.
# Çalışma zamanı manifesti süreç başına bir kez yükleyip önbelleğe alır;
# 750 WAV her Shiny oturumunda taranmaz.

MERGEN_SPEECH_MANIFEST_SCHEMA_VERSION <- 1L

#' Göreli, ileri-eğik-çizgili ve kök-dışına kaçmayan yol üret.
.speech_manifest_relative_path <- function(path, root) {
  norm <- gsub("\\\\", "/", as.character(path))
  root_norm <- sub("/+$", "", gsub("\\\\", "/", as.character(root)))
  prefix <- paste0(root_norm, "/")
  rel <- if (startsWith(norm, prefix)) substring(norm, nchar(prefix) + 1L) else norm
  paste0("www/speech/", rel)
}

#' Manifesti gerçek varlık ağacından üret.
#'
#' @param root Konuşma varlık kökü.
#' @param generator_version Üretici sürüm etiketi.
#' @return list(ok, manifest, problems)
mergen_speech_manifest_build <- function(root = mergen_speech_root(),
                                         generator_version = "1.0.0") {
  problems <- character(0)
  expected <- mergen_speech_expected_assets(root)
  personas <- mergen_speech_personas()
  wav_profile <- mergen_speech_expected_wav_profile()

  persona_entries <- list()

  for (persona in personas) {
    lock_path <- mergen_speech_voice_lock_path(persona, root)
    lock_validation <- mergen_speech_voice_lock_validate(persona, root)
    if (!isTRUE(lock_validation$ok)) {
      problems <- c(problems, sprintf(
        "persona '%s': voice-lock doğrulanamadı (%s)", persona, lock_validation$reason
      ))
      next
    }

    assets <- vector("list", nrow(expected))

    for (i in seq_len(nrow(expected))) {
      row <- expected[i, ]
      page <- if (is.na(row$page)) NULL else row$page
      script_path <- row$script_path
      audio_path <- mergen_speech_audio_path(persona, row$scenario, page, row$variant, root)

      script_text <- .speech_read_utf8_text(script_path)
      if (is.null(script_text) || !nzchar(script_text)) {
        problems <- c(problems, sprintf("metin eksik/boş: %s", script_path))
        next
      }

      wav_check <- mergen_wav_validate(audio_path, expected = wav_profile)
      if (!isTRUE(wav_check$ok)) {
        problems <- c(problems, sprintf(
          "persona '%s' ses dosyası geçersiz (%s): %s",
          persona, wav_check$reason, audio_path
        ))
        next
      }

      assets[[i]] <- list(
        id = row$id,
        scenario = row$scenario,
        page = page,
        variant = as.integer(row$variant),
        script_path = .speech_manifest_relative_path(script_path, root),
        audio_path = .speech_manifest_relative_path(audio_path, root),
        duration_ms = round(wav_check$info$duration_ms),
        sample_rate = wav_check$info$sample_rate,
        channels = wav_check$info$channels,
        bits_per_sample = wav_check$info$bits_per_sample,
        script_sha256 = mergen_speech_sha256_text(script_text),
        audio_sha256 = mergen_speech_sha256_file(audio_path)
      )
    }

    assets <- Filter(Negate(is.null), assets)

    persona_entries[[persona]] <- list(
      voice_lock_sha256 = mergen_speech_sha256_file(lock_path),
      reference_wav_sha256 = as.character(lock_validation$lock$reference_wav_sha256),
      reference_text_sha256 = as.character(lock_validation$lock$reference_text_sha256),
      assets = assets
    )
  }

  manifest <- list(
    schema_version = MERGEN_SPEECH_MANIFEST_SCHEMA_VERSION,
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    generator_version = as.character(generator_version),
    script_count = mergen_speech_expected_script_count(),
    persona_count = length(personas),
    audio_count = sum(vapply(persona_entries, function(p) length(p$assets), integer(1))),
    personas = persona_entries
  )

  list(ok = length(problems) == 0, manifest = manifest, problems = problems)
}

#' Manifesti tam kurallarla doğrula.
#'
#' @param manifest Manifest listesi.
#' @param root Varlık kökü (dosya varlığı/özet kontrolü için).
#' @param deep_hashes TRUE ise ses dosyası özetleri yeniden hesaplanır.
#' @return list(ok, problems)
mergen_speech_manifest_validate <- function(manifest,
                                            root = mergen_speech_root(),
                                            deep_hashes = FALSE) {
  problems <- character(0)
  add <- function(msg) problems <<- c(problems, msg)

  if (!is.list(manifest)) {
    return(list(ok = FALSE, problems = "manifest listesi değil"))
  }

  if (!identical(as.integer(manifest$schema_version), MERGEN_SPEECH_MANIFEST_SCHEMA_VERSION)) {
    add(sprintf("şema sürümü beklenen %d değil", MERGEN_SPEECH_MANIFEST_SCHEMA_VERSION))
  }

  personas <- mergen_speech_personas()
  guided_pages <- names(mergen_speech_guided_pages())
  silent_pages <- mergen_speech_silent_pages()
  variant_n <- mergen_speech_variant_count()
  expected_script_count <- mergen_speech_expected_script_count()
  expected_per_persona <- mergen_speech_expected_audio_per_persona()

  manifest_personas <- names(manifest$personas %||% list())

  if (!setequal(manifest_personas, personas)) {
    add(sprintf(
      "persona kümesi beklenenle uyuşmuyor (beklenen: %s; bulunan: %s)",
      paste(personas, collapse = ","), paste(manifest_personas, collapse = ",")
    ))
  }

  if (!identical(as.integer(manifest$script_count), as.integer(expected_script_count))) {
    add(sprintf("script_count %s beklenen %d değil", manifest$script_count, expected_script_count))
  }
  if (!identical(as.integer(manifest$persona_count), length(personas))) {
    add("persona_count beklenen persona sayısı değil")
  }

  total_assets <- 0L
  seen_audio_paths <- character(0)

  for (persona in manifest_personas) {
    entry <- manifest$personas[[persona]]
    assets <- entry$assets %||% list()
    total_assets <- total_assets + length(assets)

    if (!(persona %in% personas)) {
      add(sprintf("bilinmeyen persona: %s", persona))
      next
    }

    if (length(assets) != expected_per_persona) {
      add(sprintf("persona '%s' varlık sayısı %d != %d", persona, length(assets), expected_per_persona))
    }

    lock_path <- mergen_speech_voice_lock_path(persona, root)
    lock_sha_now <- mergen_speech_sha256_file(lock_path)
    if (is.na(lock_sha_now) ||
        !identical(lock_sha_now, as.character(entry$voice_lock_sha256))) {
      add(sprintf("persona '%s': voice-lock özeti manifest ile uyuşmuyor (bayat manifest?)", persona))
    }

    seen_ids <- character(0)
    combo_keys <- character(0)

    for (asset in assets) {
      id <- as.character(asset$id %||% "")
      scenario <- as.character(asset$scenario %||% "")
      page <- asset$page
      variant <- suppressWarnings(as.integer(asset$variant))

      if (id %in% seen_ids) add(sprintf("persona '%s': yinelenen varlık kimliği %s", persona, id))
      seen_ids <- c(seen_ids, id)

      combo <- sprintf("%s|%s|%s", scenario, page %||% "", variant)
      if (combo %in% combo_keys) {
        add(sprintf("persona '%s': yinelenen senaryo/sayfa/çeşit: %s", persona, combo))
      }
      combo_keys <- c(combo_keys, combo)

      if (!scenario %in% mergen_speech_scenarios()) {
        add(sprintf("persona '%s': bilinmeyen senaryo %s", persona, scenario))
      }

      if (identical(scenario, "page_guidance")) {
        if (is.null(page) || !(page %in% guided_pages)) {
          add(sprintf("persona '%s': bilinmeyen/rehbersiz sayfa %s", persona, page %||% "<boş>"))
        }
        if (!is.null(page) && page %in% silent_pages) {
          add(sprintf("persona '%s': sessiz sayfa için ses var: %s", persona, page))
        }
      }

      if (is.na(variant) || variant < 1L || variant > variant_n) {
        add(sprintf("persona '%s': geçersiz çeşit %s (%s)", persona, asset$variant, id))
      }

      for (path_field in c("script_path", "audio_path")) {
        p <- as.character(asset[[path_field]] %||% "")
        if (grepl("\\.\\.", p, fixed = FALSE) || grepl("^([A-Za-z]:|/|\\\\)", p) ||
            !startsWith(p, "www/speech/")) {
          add(sprintf("persona '%s': yol www/speech dışına çıkıyor: %s", persona, p))
        }
      }

      audio_rel <- as.character(asset$audio_path %||% "")
      seen_audio_paths <- c(seen_audio_paths, audio_rel)

      script_abs <- file.path(root, sub("^www/speech/", "", as.character(asset$script_path %||% "")))
      audio_abs <- file.path(root, sub("^www/speech/", "", audio_rel))

      if (!file.exists(script_abs)) {
        add(sprintf("persona '%s': metin dosyası yok: %s", persona, asset$script_path))
      } else {
        script_text <- .speech_read_utf8_text(script_abs)
        if (is.null(script_text) || !nzchar(script_text)) {
          add(sprintf("persona '%s': metin boş/geçersiz: %s", persona, asset$script_path))
        } else if (!identical(mergen_speech_sha256_text(script_text),
                              as.character(asset$script_sha256))) {
          add(sprintf("persona '%s': metin özeti bayat: %s", persona, asset$script_path))
        }
      }

      if (!file.exists(audio_abs)) {
        add(sprintf("persona '%s': ses dosyası yok: %s", persona, audio_rel))
      } else if (isTRUE(deep_hashes)) {
        if (!identical(mergen_speech_sha256_file(audio_abs),
                       as.character(asset$audio_sha256))) {
          add(sprintf("persona '%s': ses özeti bayat: %s", persona, audio_rel))
        }
      }
    }
  }

  if (!identical(as.integer(manifest$audio_count), total_assets)) {
    add(sprintf("audio_count %s, varlık toplamı %d ile uyuşmuyor", manifest$audio_count, total_assets))
  }

  expected_total <- mergen_speech_expected_audio_total()
  if (total_assets != expected_total) {
    add(sprintf("toplam ses sayısı %d != beklenen %d", total_assets, expected_total))
  }

  # Sahipsiz (manifestte olmayan) WAV taraması
  audio_root <- file.path(root, "audio")
  if (dir.exists(audio_root)) {
    on_disk <- list.files(audio_root, pattern = "\\.wav$", recursive = TRUE,
                          full.names = FALSE, ignore.case = TRUE)
    on_disk_rel <- file.path("www/speech/audio", on_disk, fsep = "/")
    orphans <- setdiff(gsub("\\\\", "/", on_disk_rel), seen_audio_paths)
    for (orphan in orphans) add(sprintf("sahipsiz ses dosyası: %s", orphan))
  }

  list(ok = length(problems) == 0, problems = problems)
}

#' Manifesti atomik olarak yaz (önce geçici dosya, doğrulama, sonra taşıma).
mergen_speech_manifest_write <- function(manifest, path = mergen_speech_manifest_path()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  json <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null")
  tmp <- paste0(path, ".tmp_", Sys.getpid())

  writer <- get0("atomic_write_text", mode = "function")
  if (!is.null(writer)) {
    ok <- tryCatch(writer(as.character(json), path), error = function(e) FALSE)
    if (isTRUE(ok)) return(invisible(TRUE))
  }

  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8(as.character(json))), con)
  close(con)

  reread <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(reread)) {
    unlink(tmp)
    stop("Manifest geçici dosyası doğrulanamadı; hedef dosyaya dokunulmadı.")
  }

  if (!file.rename(tmp, path)) {
    ok <- file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
    if (!isTRUE(ok)) stop("Manifest hedef konuma taşınamadı.")
  }

  invisible(TRUE)
}

#' Manifesti diskten oku (sığ doğrulamayla).
#'
#' @return list(ok, manifest, reason)
mergen_speech_manifest_load <- function(root = mergen_speech_root()) {
  path <- mergen_speech_manifest_path(root)
  if (!file.exists(path)) {
    return(list(ok = FALSE, manifest = NULL, reason = "manifest_yok"))
  }

  manifest <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(manifest)) {
    return(list(ok = FALSE, manifest = NULL, reason = "manifest_okunamadi"))
  }

  if (!identical(as.integer(manifest$schema_version), MERGEN_SPEECH_MANIFEST_SCHEMA_VERSION)) {
    return(list(ok = FALSE, manifest = NULL, reason = "sema_surumu_uyusmuyor"))
  }

  list(ok = TRUE, manifest = manifest, reason = NULL)
}

# Süreç kapsamlı manifest önbelleği (Shiny oturumu başına yeniden taranmaz).
if (!exists(".mergen_speech_manifest_cache", inherits = FALSE)) {
  .mergen_speech_manifest_cache <- new.env(parent = emptyenv())
}

#' Çalışma zamanı manifesti: bir kez yükle, önbellekten sun. Manifest yoksa
#' uygulama açılışını KIRMAZ; statik konuşma varlıkları kullanılamaz sayılır.
#'
#' @param refresh TRUE ise önbellek yenilenir (yeniden üretim/dağıtım sonrası).
#' @return list(ok, manifest, reason)
mergen_speech_manifest_runtime <- function(root = mergen_speech_root(), refresh = FALSE) {
  cache_key <- "runtime"

  if (!isTRUE(refresh)) {
    cached <- get0(cache_key, envir = .mergen_speech_manifest_cache, ifnotfound = NULL)
    if (!is.null(cached) && identical(cached$root, root)) return(cached$value)
  }

  loaded <- mergen_speech_manifest_load(root)
  if (isTRUE(loaded$ok)) {
    validation <- mergen_speech_manifest_validate(loaded$manifest, root, deep_hashes = FALSE)
    if (!isTRUE(validation$ok)) {
      loaded <- list(ok = FALSE, manifest = NULL, reason = "manifest_dogrulanamadi")
      preview <- paste(utils::head(validation$problems, 5), collapse = " | ")
      cat(sprintf("[SPEECH] Manifest doğrulanamadı: %s\n", preview))
    }
  } else {
    cat(sprintf("[SPEECH] Statik konuşma varlıkları kullanılamıyor (%s).\n", loaded$reason))
  }

  assign(cache_key, list(root = root, value = loaded), envir = .mergen_speech_manifest_cache)
  loaded
}

#' Manifest önbelleğini kontrollü yenile (operatör/deploy sonrası).
mergen_speech_manifest_refresh <- function(root = mergen_speech_root()) {
  mergen_speech_manifest_runtime(root, refresh = TRUE)
}

#' Manifest önbelleğini tamamen temizle (test yalıtımı).
mergen_speech_manifest_cache_clear <- function() {
  rm(list = ls(envir = .mergen_speech_manifest_cache),
     envir = .mergen_speech_manifest_cache)
  invisible(NULL)
}

#' Manifest içinden varlık kaydı bul.
mergen_speech_asset_lookup <- function(manifest, persona, scenario, page = NULL, variant = 1L) {
  if (is.null(manifest)) return(NULL)
  entry <- manifest$personas[[persona]]
  if (is.null(entry)) return(NULL)

  target_id <- mergen_speech_asset_id(scenario, page, variant)
  for (asset in entry$assets %||% list()) {
    if (identical(as.character(asset$id), target_id) &&
        identical(as.character(asset$scenario), scenario)) {
      return(asset)
    }
  }
  NULL
}

#' Persona statik varlıkları çalışır durumda mı? Manifest + canlı voice-lock
#' özeti eşleşmesi (ucuz kontrol; 750 dosya taranmaz).
mergen_speech_persona_static_ready <- function(persona, root = mergen_speech_root()) {
  loaded <- mergen_speech_manifest_runtime(root)
  if (!isTRUE(loaded$ok)) return(FALSE)

  entry <- loaded$manifest$personas[[persona]]
  if (is.null(entry)) return(FALSE)
  if (length(entry$assets %||% list()) != mergen_speech_expected_audio_per_persona()) {
    return(FALSE)
  }

  lock_sha <- mergen_speech_sha256_file(mergen_speech_voice_lock_path(persona, root))
  if (is.na(lock_sha)) return(FALSE)
  identical(lock_sha, as.character(entry$voice_lock_sha256))
}
