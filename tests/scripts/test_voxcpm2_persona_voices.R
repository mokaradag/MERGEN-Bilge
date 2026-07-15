#!/usr/bin/env Rscript

# VoxCPM2: MERGEN Bilge persona sesleri testi
# Personalar: Emre, Selin, Deniz, Can ve İpek
#
# Bu betik:
# - 3 erkek ve 2 kadın sesi üretir,
# - VoxCPM2 Voice Design özelliğini kullanır,
# - ses klonlama, referans WAV veya ref_text kullanmaz,
# - mevcut tests/scripts/test_voxcpm2_tts.R betiğini çağırır.
#
# MERGEN-Bilge depo kökünden çalıştırın:
# Rscript --vanilla --encoding=UTF-8 tests/scripts/test_voxcpm2_persona_voices.R

options(warn = 1, encoding = "UTF-8")

base_script <- file.path("tests", "scripts", "test_voxcpm2_tts.R")

if (!file.exists(base_script)) {
  stop(
    paste0(
      "tests/scripts/test_voxcpm2_tts.R bulunamadı. ",
      "Betiği MERGEN-Bilge depo kökünden çalıştırın."
    ),
    call. = FALSE
  )
}

output_dir <- file.path(
  "tests",
  "output",
  "voxcpm2_persona_voices"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# Persona sırası ve cinsiyet dağılımı:
# Emre  : erkek
# Selin : kadın
# Deniz : erkek
# Can   : erkek
# İpek  : kadın
#
# voice_design metinleri R/config_characters.R içindeki persona rollerine göre
# hazırlanmıştır. Bunlar kayıtlı ses adları değil, VoxCPM2'nin yerleşik
# Voice Design özelliğine gönderilen doğal dil ses tanımlarıdır.
personas <- list(
  emre = list(
    full_name = "Emre Onat",
    role = "Ana Asistan",
    gender = "erkek",
    voice_design = paste(
      "An adult Turkish male voice with a calm, balanced and trustworthy presence.",
      "Warm but restrained, medium-low pitch, natural professional tone.",
      "He sounds pragmatic, reassuring and clear, never theatrical or overly dramatic.",
      "Native-level fluent Standard Turkish pronunciation, precise articulation, normal pace and short natural pauses."
    )
  ),

  selin = list(
    full_name = "Selin Sezgin",
    role = "Yapıcı Uzman",
    gender = "kadın",
    voice_design = paste(
      "An adult Turkish female voice that sounds constructive, confident and solution-oriented.",
      "Clear medium pitch, professional warmth and a positive forward-moving energy.",
      "She sounds capable and encouraging without becoming overly cheerful or promotional.",
      "Native-level fluent Standard Turkish pronunciation, crisp articulation, normal pace and natural pauses."
    )
  ),

  deniz = list(
    full_name = "Deniz Özgün",
    role = "Stratejist",
    gender = "erkek",
    voice_design = paste(
      "An adult Turkish male strategist with a composed, thoughtful and analytical voice.",
      "Low to medium-low pitch, measured delivery and quiet confidence.",
      "He sounds long-term oriented and structured, with deliberate emphasis on important points.",
      "Native-level fluent Standard Turkish pronunciation, clear articulation, moderately measured pace and natural pauses."
    )
  ),

  can = list(
    full_name = "Can Yalın",
    role = "Eleştirel Eş",
    gender = "erkek",
    voice_design = paste(
      "An adult Turkish male voice that is precise, disciplined and respectfully critical.",
      "Medium pitch, firm but calm delivery, with crisp and direct articulation.",
      "He sounds attentive to risks and evidence, never harsh, aggressive or sarcastic.",
      "Native-level fluent Standard Turkish pronunciation, controlled pace and short natural pauses."
    )
  ),

  ipek = list(
    full_name = "İpek Duru",
    role = "Rehber",
    gender = "kadın",
    voice_design = paste(
      "An adult Turkish female teacher and guide with a warm, patient and empathetic voice.",
      "Clear medium pitch, gentle confidence and an approachable professional tone.",
      "She explains calmly and reassuringly, without sounding childish, artificial or exaggerated.",
      "Native-level fluent Standard Turkish pronunciation, very clear articulation, comfortable pace and natural pauses."
    )
  )
)

expected_ids <- c("emre", "selin", "deniz", "can", "ipek")

if (!identical(names(personas), expected_ids)) {
  stop(
    "Persona sırası emre, selin, deniz, can, ipek olmalıdır.",
    call. = FALSE
  )
}

male_count <- sum(vapply(
  personas,
  function(x) identical(x$gender, "erkek"),
  logical(1)
))

female_count <- sum(vapply(
  personas,
  function(x) identical(x$gender, "kadın"),
  logical(1)
))

if (male_count != 3L || female_count != 2L) {
  stop(
    sprintf(
      "Beklenen dağılım 3 erkek ve 2 kadın sestir; bulunan: %d erkek, %d kadın.",
      male_count,
      female_count
    ),
    call. = FALSE
  )
}

# Her persona kendi adını ve rolünü söyler; ardından bütün personlarda aynı
# Türkçe değerlendirme pasajı kullanılır. Böylece dosyalar kolayca ayırt edilir
# ve Türkçe akıcılık ortak bir metin üzerinde karşılaştırılabilir.
common_test_text <- paste0(
  "Bu, MERGEN Bilge için doğal Türkçe konuşma testidir. ",
  "Çalışma, özgürlük, yağmur, ışık, ölçü, düşünce ve Türkiye ",
  "sözcüklerini açıkça söylüyorum. Karmaşık bir konuyu sakin, akıcı, ",
  "anlaşılır ve güven veren bir biçimde açıklayabilirim."
)

# Türkçe metinler geçici UTF-8 dosyalarına yazılır. Bu yaklaşım Windows komut
# satırında Türkçe karakterlerin bozulma riskini azaltır.
temp_files <- character(0)

on.exit({
  if (length(temp_files) > 0L) {
    unlink(temp_files, force = TRUE)
  }
}, add = TRUE)

rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)

cat("============================================================\n")
cat("VoxCPM2 - MERGEN Bilge Persona Sesleri Testi\n")
cat("============================================================\n")
cat(sprintf("Persona sayısı    : %d\n", length(personas)))
cat(sprintf("Erkek ses sayısı  : %d\n", male_count))
cat(sprintf("Kadın ses sayısı  : %d\n", female_count))
cat("Klonlama          : YOK\n")
cat("Referans WAV      : YOK\n")
cat("ref_text          : YOK\n")
cat("API voice alanı   : default\n")
cat(sprintf(
  "Çıktı klasörü    : %s\n\n",
  normalizePath(output_dir, winslash = "/", mustWork = TRUE)
))

failed <- character(0)
results <- vector("list", length(personas))
names(results) <- names(personas)

for (i in seq_along(personas)) {
  persona_id <- names(personas)[[i]]
  persona <- personas[[i]]

  spoken_text <- paste0(
    "Merhaba, ben ", persona$full_name, ". ",
    "MERGEN Bilge'de ", persona$role, " rolündeyim. ",
    common_test_text
  )

  text_file <- tempfile(
    pattern = paste0("voxcpm2_", persona_id, "_"),
    fileext = ".txt"
  )

  temp_files <- c(temp_files, text_file)

  writeLines(
    enc2utf8(spoken_text),
    text_file,
    useBytes = TRUE
  )

  output_file <- file.path(
    output_dir,
    sprintf(
      "%02d_%s.wav",
      i,
      persona_id
    )
  )

  cat(sprintf(
    "[%d/%d] %s - %s (%s) üretiliyor...\n",
    i,
    length(personas),
    persona$full_name,
    persona$role,
    persona$gender
  ))

  started_at <- Sys.time()

  status <- system2(
    command = rscript,
    args = c(
      "--vanilla",
      "--encoding=UTF-8",
      shQuote(base_script),
      "--text-file",
      shQuote(text_file),
      "--control",
      shQuote(persona$voice_design),
      "--voice",
      "default",
      "--model",
      "VoxCPM2",
      "--response-format",
      "wav",
      "--speed",
      "1.0",
      "--output",
      shQuote(output_file)
    )
  )

  elapsed <- as.numeric(difftime(
    Sys.time(),
    started_at,
    units = "secs"
  ))

  file_size <- if (file.exists(output_file)) {
    suppressWarnings(file.info(output_file)$size)
  } else {
    NA_real_
  }

  ok <- identical(as.integer(status), 0L) &&
    file.exists(output_file) &&
    !is.na(file_size) &&
    file_size > 0

  results[[persona_id]] <- list(
    ok = ok,
    path = output_file,
    bytes = file_size,
    elapsed = elapsed
  )

  if (ok) {
    cat(sprintf(
      "  BAŞARILI: %s\n",
      normalizePath(output_file, winslash = "/", mustWork = TRUE)
    ))
    cat(sprintf("  Süre     : %.2f saniye\n", elapsed))
    cat(sprintf("  Boyut    : %.0f bayt\n\n", file_size))
  } else {
    cat(sprintf("  BAŞARISIZ: çıkış kodu %s\n\n", status))
    failed <- c(failed, persona_id)
  }
}

cat("============================================================\n")
cat("SONUÇ\n")
cat("============================================================\n")

for (persona_id in names(results)) {
  persona <- personas[[persona_id]]
  result <- results[[persona_id]]

  cat(sprintf(
    "%-6s | %-13s | %-5s | %s\n",
    toupper(persona_id),
    persona$role,
    if (isTRUE(result$ok)) "OK" else "HATA",
    result$path
  ))
}

if (length(failed) > 0L) {
  stop(
    sprintf(
      "Üretilemeyen persona sesleri: %s",
      paste(failed, collapse = ", ")
    ),
    call. = FALSE
  )
}

cat("\nTÜM PERSONA SESLERİ BAŞARIYLA ÜRETİLDİ\n")
cat("\nDinlerken şu noktaları değerlendirin:\n")
cat("1. Emre sakin, dengeli ve güven veren bir ana asistan mı?\n")
cat("2. Selin profesyonel, yapıcı ve çözüm odaklı mı?\n")
cat("3. Deniz düşünceli, ölçülü ve stratejik mi?\n")
cat("4. Can net, disiplinli ve eleştirel fakat saygılı mı?\n")
cat("5. İpek sıcak, sabırlı ve öğretici bir rehber mi?\n")
cat("6. Beş ses de Türkçeyi doğal, doğru ve akıcı söylüyor mu?\n")