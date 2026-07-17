# tools/speech/generate_voxcpm2_assets.R
# MERGEN Bilge hibrit konuşma varlığı üreticisi - OPERATÖR GİRİŞ BETİĞİ.
#
# Windows VM üzerinde RStudio'dan çalıştırılır; Shiny uygulamasının koşuyor
# olması GEREKMEZ. Tipik akış (depo kökünden):
#
#   source("tools/speech/generate_voxcpm2_assets.R", encoding = "UTF-8")
#   speech_asset_env_check()
#   generate_reference_candidate("emre")   # adayı üret, DİNLE
#   approve_reference_voice("emre")        # onayla ve kilitle
#   generate_persona_speech_assets("emre") # 150 WAV üret
#   ... diğer personalar ...
#   validate_speech_assets()
#   generate_speech_manifest()
#
# Üretilen dosyalar (referans WAV'lar, kilitler, 750 WAV, manifest) GitHub'a
# COMMIT EDİLMEZ; VM-yereldir. Ayrıntılar: docs/speech-operator-runbook.md

local({
  # Depo kökünü güvenle bul: bu dosyadan veya getwd()'den yukarı doğru ara
  find_repo_root <- function() {
    candidates <- character(0)

    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", args, value = TRUE)
    if (length(file_arg) == 1) {
      candidates <- c(candidates, dirname(dirname(dirname(
        normalizePath(sub("^--file=", "", file_arg), winslash = "/", mustWork = FALSE)
      ))))
    }

    probe <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    for (i in 1:6) {
      candidates <- c(candidates, probe)
      parent <- dirname(probe)
      if (identical(parent, probe)) break
      probe <- parent
    }

    for (cand in candidates) {
      if (file.exists(file.path(cand, "app.R")) &&
          dir.exists(file.path(cand, "R")) &&
          dir.exists(file.path(cand, "www", "speech"))) {
        return(cand)
      }
    }
    stop(paste0(
      "MERGEN-Bilge depo kökü bulunamadı. RStudio'da önce setwd() ile depo ",
      "köküne geçin, örn. setwd(\"C:/path/to/MERGEN-Bilge\")."
    ), call. = FALSE)
  }

  repo_root <- find_repo_root()
  message(sprintf("Depo kökü: %s", repo_root))

  # .Renviron'u depo kökünden yükle (RStudio farklı profil yüklemiş olabilir)
  renviron_path <- file.path(repo_root, ".Renviron")
  if (file.exists(renviron_path)) {
    readRenviron(renviron_path)
    message(".Renviron yüklendi (değerler gizli tutulur).")
  } else {
    message("UYARI: depo kökünde .Renviron yok; ortam değişkenleri mevcut oturumdan okunacak.")
  }

  # Çalışma zamanı konuşma yardımcılarını TEK kaynak olarak yükle. Operatör
  # üreticisi Shiny oturumuna sahip değildir; buna karşın üretim VM'sindeki
  # mevcut şifreli api_keys/<kullanıcı>_api_key kaydını güvenle çözebilmek için
  # uygulamanın aynı helpers_api_key_crypto.R katmanı da yüklenir.
  runtime_files <- c(
    "R/utils_common.R",
    "R/helpers_api_key_crypto.R",
    "R/config_speech_assets.R",
    "R/config_speech_asset_paths.R",
    "R/helpers_speech_wav.R",
    "R/helpers_speech_voice_profiles.R",
    "R/helpers_speech_voxcpm2_adapter.R",
    "R/helpers_speech_manifest.R",
    "R/helpers_ai_expert_chunking.R"
  )
  for (f in runtime_files) {
    path <- file.path(repo_root, f)
    if (!file.exists(path)) stop(sprintf("Gerekli dosya eksik: %s", f), call. = FALSE)
    source(path, encoding = "UTF-8")
  }

  # helpers_api_key_crypto.R normal uygulamada getwd() üzerinden api_keys yolunu
  # kurar. Operatör betiği farklı bir çalışma dizininden source edilebildiği için
  # yolu açıkça bulunan depo köküne sabitle; hiçbir anahtar değeri yazdırılmaz.
  operator_api_keys_dir <- normalizePath(
    file.path(repo_root, "api_keys"),
    winslash = "/",
    mustWork = FALSE
  )
  dir.create(operator_api_keys_dir, showWarnings = FALSE, recursive = TRUE)
  assign("API_KEYS_DIR", operator_api_keys_dir, envir = globalenv())

  source(file.path(repo_root, "tools", "speech", "helpers_speech_generator.R"),
         encoding = "UTF-8")
  source(file.path(repo_root, "tools", "speech", "helpers_speech_chunked_assets.R"),
         encoding = "UTF-8")

  # Operatör anahtarı çözüm sırası:
  # 1) TTS'e özel ortam anahtarı
  # 2) genel yerel LLM ortam anahtarı
  # 3) MERGEN_SPEECH_API_KEY_USER ile açıkça seçilen mevcut şifreli kullanıcı kaydı
  # Kullanıcı seçimi zorunludur; api_keys klasöründe birden fazla dosya varsa
  # sessizce ilkini seçmek kimlik/güvenlik hatası olur. Ham anahtar loglanmaz.
  operator_key_resolver <- function() {
    tts_key <- Sys.getenv("LOCAL_TTS_API_KEY", "")
    if (nzchar(tts_key)) return(tts_key)

    llm_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
    if (nzchar(llm_key)) return(llm_key)

    operator_user <- trimws(Sys.getenv("MERGEN_SPEECH_API_KEY_USER", ""))
    if (!nzchar(operator_user)) return("")

    stored_key <- tryCatch(
      load_user_api_key(operator_user),
      error = function(e) NULL
    )
    stored_key <- as.character(stored_key %||% "")[1]
    if (is.na(stored_key) || !nzchar(stored_key)) return("")

    stored_key
  }

  assign(
    "speech_gen_resolve_tts_api_key",
    operator_key_resolver,
    envir = globalenv()
  )

  assign(".speech_generator_repo_root", repo_root, envir = globalenv())
})

.speech_gen_root <- function() {
  root_env <- Sys.getenv("MERGEN_SPEECH_ROOT", "")
  if (nzchar(root_env)) return(root_env)
  file.path(get(".speech_generator_repo_root", envir = globalenv()), "www", "speech")
}

#' Ortam/paket/uç nokta/metin ağacı ön kontrolü (hiçbir şey üretmez).
speech_asset_env_check <- function() {
  speech_gen_env_check(root = .speech_gen_root(), verbose = TRUE)
}

#' 1. AŞAMA: Persona için ADAY referans sesi üret (üretim varlıkları ÜRETİLMEZ).
#' Çıktı dosyasını dinleyin; uygun değilse yeniden çalıştırın.
generate_reference_candidate <- function(persona) {
  speech_gen_reference_candidate(persona, root = .speech_gen_root())
}

#' 2. AŞAMA: Dinlenip beğenilen adayı ONAYLA ve voice-lock.json ile kilitle.
#' Var olan onaylı referans sessizce değiştirilmez; bilinçli değişim için
#' reset_reference = TRUE gerekir (personanın tüm çıktıları geçersiz kılınır).
approve_reference_voice <- function(persona, reset_reference = FALSE) {
  speech_gen_reference_approve(persona, root = .speech_gen_root(),
                               reset_reference = reset_reference)
}

#' Tek persona için 150 üretim WAV'ını üret (onaylı referans zorunlu).
#' Kesinti sonrası aynı komut kaldığı yerden sürer; geçerli mevcut dosyalar
#' varsayılan olarak atlanır (overwrite = TRUE zorlar).
#'
#' @param preview TRUE ise plan gösterilir, dosya yazılmaz.
#' @param max_files Küçük deneme koşusu için üst sınır (örn. 3).
generate_persona_speech_assets <- function(persona, overwrite = FALSE,
                                           max_files = NULL, preview = FALSE) {
  speech_gen_run(persona, root = .speech_gen_root(), overwrite = overwrite,
                 max_files = max_files, preview = preview)
}

#' Tüm personalar için üretim koşusu. Referans onayını ATLAMAZ: onaysız
#' personalar hata listesine düşer, onaylılar üretilir.
generate_all_persona_speech_assets <- function(overwrite = FALSE, preview = FALSE) {
  results <- list()
  for (persona in mergen_speech_personas()) {
    results[[persona]] <- tryCatch(
      generate_persona_speech_assets(persona, overwrite = overwrite, preview = preview),
      error = function(e) {
        message(sprintf("Persona '%s' ATLANDI: %s", persona, conditionMessage(e)))
        list(persona = persona, generated = 0L, skipped = 0L, failed = NA_integer_,
             error = conditionMessage(e))
      }
    )
  }
  invisible(results)
}

#' Yalnızca doğrulama: metin ağacı + kilitler + WAV'lar + sayılar denetlenir.
validate_speech_assets <- function(deep_hashes = FALSE) {
  root <- .speech_gen_root()
  build <- mergen_speech_manifest_build(root)
  validation <- mergen_speech_manifest_validate(build$manifest, root,
                                                deep_hashes = deep_hashes)
  problems <- unique(c(build$problems, validation$problems))

  if (length(problems) == 0) {
    message(sprintf(
      "Doğrulama BAŞARILI: %d metin, %d persona, %d WAV.",
      build$manifest$script_count, build$manifest$persona_count,
      build$manifest$audio_count
    ))
  } else {
    message(sprintf("Doğrulama %d sorun buldu:", length(problems)))
    for (p in utils::head(problems, 40)) message("  - ", p)
    if (length(problems) > 40) message(sprintf("  ... ve %d sorun daha", length(problems) - 40))
  }

  invisible(list(ok = length(problems) == 0, problems = problems))
}

#' Manifesti mevcut varlıklardan yeniden üret ve atomik yaz. Tüm üst veriler
#' (yollar, süreler, özetler) gerçek dosyalardan türetilir; elle alan girilmez.
generate_speech_manifest <- function() {
  root <- .speech_gen_root()
  build <- mergen_speech_manifest_build(root)

  if (!isTRUE(build$ok)) {
    message(sprintf("Manifest üretimi %d sorunla karşılaştı:", length(build$problems)))
    for (p in utils::head(build$problems, 25)) message("  - ", p)
    stop("Manifest yazılmadı; önce sorunları giderin (validate_speech_assets()).",
         call. = FALSE)
  }

  validation <- mergen_speech_manifest_validate(build$manifest, root)
  if (!isTRUE(validation$ok)) {
    for (p in utils::head(validation$problems, 25)) message("  - ", p)
    stop("Manifest doğrulaması başarısız; yazılmadı.", call. = FALSE)
  }

  path <- mergen_speech_manifest_path(root)
  mergen_speech_manifest_write(build$manifest, path)
  message(sprintf(
    "Manifest yazıldı: %s (%d persona, %d WAV). Uygulama yeniden başlatıldığında yüklenir.",
    path, build$manifest$persona_count, build$manifest$audio_count
  ))
  invisible(path)
}

message(paste0(
  "Konuşma varlığı üreticisi hazır. Komutlar: speech_asset_env_check(), ",
  "generate_reference_candidate(persona), approve_reference_voice(persona), ",
  "generate_persona_speech_assets(persona), generate_all_persona_speech_assets(), ",
  "validate_speech_assets(), generate_speech_manifest()"
))
