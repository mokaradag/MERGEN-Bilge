# ==============================================================================
# Dosya Yolu: R/helpers_tts_voice_cache.R
# Açıklama:   VoxCPM2 ses profili bellek önbelleği (süreç kapsamlı).
#             Bir profili yalnızca gerektiğinde yükler; doğrulanmış üst veriyi,
#             birebir transcript'i, sağlama toplamlarını ve base64 referans-ses
#             veri URL'sini süreç ömrü boyunca tutar. Aynı WAV her TTS parçası
#             için yeniden base64'lenmez.
#
#             Önbellek kaynak değişikliğinde kendini geçersiz kılar (manifest
#             mtime veya WAV mtime/boyut değişimi; profil sürümü manifest
#             düzenlemesiyle değiştiği için manifest mtime bunu da yakalar).
#             base64 değeri ASLA loglanmaz.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# Süreç-kapsamlı önbellek ortamı (yeniden source edilse de options üzerinden
# korunur; kilit/zamanlayıcı içermez, salt-veri saklama).
.mergen_tts_cache_env <- function() {
  store <- getOption("mergen.tts_profile_cache_env", NULL)
  if (is.null(store) || !is.environment(store)) {
    store <- new.env(parent = emptyenv())
    store$entries <- list()
    store$load_count <- 0L
    options(mergen.tts_profile_cache_env = store)
  }
  store
}

# İki sayısal değeri NA-güvenli karşılaştırır (her ikisi NA -> eşit).
.mergen_tts_num_equal <- function(a, b) {
  if (is.na(a) && is.na(b)) return(TRUE)
  if (is.na(a) || is.na(b)) return(FALSE)
  isTRUE(a == b)
}

#' Önbellekteki Profili Getir (tazelik denetimi yapmadan)
#' @param profile_id Profil kimliği
#' @return Önbellek girdisi veya NULL
mergen_tts_get_cached_profile <- function(profile_id) {
  profile_id <- tolower(trimws(as.character(profile_id %||% "")[1]))
  .mergen_tts_cache_env()$entries[[profile_id]]
}

#' Profil Önbelleğini Temizle
mergen_tts_invalidate_profile <- function(profile_id) {
  profile_id <- tolower(trimws(as.character(profile_id %||% "")[1]))
  store <- .mergen_tts_cache_env()
  store$entries[[profile_id]] <- NULL
  invisible(TRUE)
}

#' Tüm Profil Önbelleğini Temizle
mergen_tts_invalidate_all_profiles <- function() {
  store <- .mergen_tts_cache_env()
  store$entries <- list()
  store$load_count <- 0L
  invisible(TRUE)
}

#' Gerçekleşen çözümleme (resolver) çağrısı sayısı (dedup testleri için).
mergen_tts_profile_load_count <- function() {
  .mergen_tts_cache_env()$load_count
}

# Bir önbellek girdisinin kaynağının hâlâ taze olup olmadığını denetler.
.mergen_tts_entry_fresh <- function(entry, config, fail_ttl_secs = 60) {
  if (is.null(entry)) return(FALSE)

  voice_dir <- as.character(config$voice_dir %||% "")[1]
  manifest_path <- file.path(voice_dir, "manifest.json")
  cur_manifest_mtime <- tryCatch(as.numeric(file.info(manifest_path)$mtime), error = function(e) NA_real_)

  if (!.mergen_tts_num_equal(cur_manifest_mtime, entry$src_manifest_mtime %||% NA_real_)) {
    return(FALSE)
  }

  if (isTRUE(entry$resolved$ok)) {
    audio_path <- entry$resolved$audio_path %||% ""
    info <- tryCatch(file.info(audio_path), error = function(e) NULL)
    cur_mtime <- if (!is.null(info)) as.numeric(info$mtime) else NA_real_
    cur_size  <- if (!is.null(info)) as.numeric(info$size) else NA_real_
    if (!.mergen_tts_num_equal(cur_mtime, entry$src_audio_mtime %||% NA_real_)) return(FALSE)
    if (!.mergen_tts_num_equal(cur_size, entry$src_audio_size %||% NA_real_)) return(FALSE)

    # Transcript değişikliği de profili geçersiz kılar (mtime + boyut).
    tinfo <- tryCatch(file.info(entry$resolved$transcript_path %||% ""), error = function(e) NULL)
    cur_tmtime <- if (!is.null(tinfo)) as.numeric(tinfo$mtime) else NA_real_
    cur_tsize  <- if (!is.null(tinfo)) as.numeric(tinfo$size) else NA_real_
    if (!.mergen_tts_num_equal(cur_tmtime, entry$src_transcript_mtime %||% NA_real_)) return(FALSE)
    if (!.mergen_tts_num_equal(cur_tsize, entry$src_transcript_size %||% NA_real_)) return(FALSE)
    return(TRUE)
  }

  # Başarısız girdiler: manifest değişmedi ama TTL dolduysa yeniden dene
  # (bozuk WAV düzeltilirse yeniden başlatmadan kurtulma imkânı).
  age <- tryCatch(as.numeric(difftime(Sys.time(), entry$created_at, units = "secs")), error = function(e) Inf)
  if (!is.finite(age) || age > fail_ttl_secs) return(FALSE)
  TRUE
}

#' Profili Bellek Önbelleğinden Yükle (yoksa çöz ve önbelleğe al)
#'
#' @description Dedup edilmiş, sürümlenmiş yükleme. Kaynak (manifest/WAV)
#'   değiştiğinde otomatik yeniden çözer. Başarısız çözümlemeyi de önbelleğe
#'   alarak her istekte aynı hatayı loglamayı önler.
#' @param profile_id Profil kimliği
#' @param config TTS yapılandırması
#' @param resolver Çözümleyici (test için enjekte edilebilir)
#' @param force TRUE ise önbelleği yok say
#' @return mergen_tts_resolve_profile() sonucu (ok/error + üst veri)
mergen_tts_load_profile_cached <- function(profile_id, config = NULL,
                                           resolver = NULL, force = FALSE) {
  if (is.null(config)) config <- if (exists("tts_config", inherits = TRUE)) get("tts_config", inherits = TRUE) else list()
  if (is.null(resolver)) resolver <- mergen_tts_resolve_profile

  profile_id <- tolower(trimws(as.character(profile_id %||% "")[1]))
  store <- .mergen_tts_cache_env()
  entry <- store$entries[[profile_id]]

  if (!isTRUE(force) && .mergen_tts_entry_fresh(entry, config)) {
    return(entry$resolved)
  }

  resolved <- tryCatch(
    resolver(profile_id, config),
    error = function(e) list(ok = FALSE, error = conditionMessage(e), profile_id = profile_id)
  )
  store$load_count <- store$load_count + 1L

  voice_dir <- as.character(config$voice_dir %||% "")[1]
  manifest_path <- file.path(voice_dir, "manifest.json")

  tinfo <- tryCatch(file.info(resolved$transcript_path %||% ""), error = function(e) NULL)
  store$entries[[profile_id]] <- list(
    resolved = resolved,
    created_at = Sys.time(),
    src_manifest_mtime = tryCatch(as.numeric(file.info(manifest_path)$mtime), error = function(e) NA_real_),
    src_audio_mtime = resolved$audio_mtime %||% NA_real_,
    src_audio_size = resolved$audio_size %||% NA_real_,
    src_transcript_mtime = if (!is.null(tinfo)) as.numeric(tinfo$mtime) else NA_real_,
    src_transcript_size = if (!is.null(tinfo)) as.numeric(tinfo$size) else NA_real_
  )

  resolved
}
