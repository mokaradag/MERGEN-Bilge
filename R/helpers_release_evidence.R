# ==============================================================================
# Dosya Yolu: R/helpers_release_evidence.R
# Açıklama: Release/doğrulama kanıt artifact'larını (vm-evidence evidence.json,
#           ai-validation summary.json) ve günlük log sağlık sayaçlarını
#           SECRET-SAFE biçimde okuyan saf yardımcılar. Operatör görünürlüğü
#           içindir: hangi kanıt kapısı en son ne zaman, hangi sonuçla koştu?
#
#           Sınırlar:
#           - Saf okuma katmanıdır: Shiny/reactive/DB/LLM/ağ çağrısı YOKTUR.
#           - Artifact'lar sözleşme gereği zaten secret-safe yazılır; bu okuyucu
#             yine de YALNIZCA beyaz-listeli alanları seçer, ham içerik veya
#             ortam değeri asla döndürmez (savunma derinliği).
#           - Kanıt sınırı dürüstlüğü korunur: bulunamayan artifact "not_found"
#             olarak raporlanır, asla başarı gibi gösterilmez. SKIP edilen
#             adımlar kanıt DEĞİLDİR.
# ==============================================================================

# Artifact kökünü çözer (repo kökü altındaki artifacts/ dizini)
release_evidence_artifact_root <- function(repo_root = getwd()) {
  file.path(repo_root, "artifacts")
}

# Bir artifact ailesinin en yeni zaman damgalı alt dizinindeki hedef dosyayı
# bulur. Dizin adları (örn. 20260612-211836) ada göre azalan sıralanır;
# hedef dosyayı içeren ilk dizin kazanır. Bulunamazsa "".
release_evidence_latest_artifact <- function(base_dir, file_name) {
  if (is.null(base_dir) || length(base_dir) != 1L || is.na(base_dir) ||
      !nzchar(base_dir) || !dir.exists(base_dir)) {
    return("")
  }

  alt_dizinler <- list.dirs(base_dir, full.names = TRUE, recursive = FALSE)
  if (!length(alt_dizinler)) {
    return("")
  }

  # Zaman damgalı adlar sözlüksel sırada kronolojiktir; en yenisi başa gelir
  alt_dizinler <- alt_dizinler[order(basename(alt_dizinler), decreasing = TRUE)]

  for (dizin in alt_dizinler) {
    aday <- file.path(dizin, file_name)
    if (file.exists(aday)) {
      return(aday)
    }
  }

  ""
}

# JSON artifact'ını güvenle okur; bozuk/eksik dosyada NULL döner, asla durmaz.
release_evidence_read_json <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }

  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

# Tek skaler alanı güvenle çeker (yoksa varsayılan); ham yapılar dönmez.
.release_evidence_scalar <- function(x, name, default = "") {
  deger <- tryCatch(x[[name]], error = function(e) NULL)
  if (is.null(deger) || length(deger) < 1L) {
    return(default)
  }
  deger <- deger[[1]]
  if (is.null(deger) || is.na(deger)) {
    return(default)
  }
  as.character(deger)
}

# VM kanıt kapısının (run_vm_evidence_gate.R) en son evidence.json özetini
# beyaz-listeli alanlarla döndürür. Adım listesi yalnızca id/status/required
# üçlüsüne indirgenir; log yolları, detaylar ve notlar dışarı taşınmaz.
release_evidence_vm_summary <- function(repo_root = getwd()) {
  yol <- release_evidence_latest_artifact(
    file.path(release_evidence_artifact_root(repo_root), "vm-evidence"),
    "evidence.json"
  )

  bulunamadi <- list(
    found = FALSE,
    status = "not_found",
    artifact_path = "",
    generated_at_utc = "",
    profile_effective = "",
    passed = 0L,
    failed = 0L,
    skipped = 0L,
    steps = list()
  )

  veri <- release_evidence_read_json(yol)
  if (is.null(veri)) {
    return(bulunamadi)
  }

  sayilar <- veri$counts
  adimlar <- lapply(veri$steps, function(s) {
    list(
      id = .release_evidence_scalar(s, "id"),
      status = .release_evidence_scalar(s, "status", default = "unknown"),
      required = isTRUE(tryCatch(s$required, error = function(e) FALSE))
    )
  })

  list(
    found = TRUE,
    status = .release_evidence_scalar(veri, "overall_status", default = "unknown"),
    artifact_path = yol,
    generated_at_utc = .release_evidence_scalar(veri, "generated_at_utc"),
    profile_effective = .release_evidence_scalar(veri, "profile_effective"),
    passed = as.integer(.release_evidence_scalar(sayilar, "passed", default = "0")),
    failed = as.integer(.release_evidence_scalar(sayilar, "failed", default = "0")),
    skipped = as.integer(.release_evidence_scalar(sayilar, "skipped", default = "0")),
    steps = adimlar
  )
}

# ai_validate (ai_repo_check.R) en son summary.json özetini döndürür.
# Yalnızca dokümante kanıt alanları seçilir; ham adım çıktıları taşınmaz.
release_evidence_ai_validation_summary <- function(repo_root = getwd()) {
  yol <- release_evidence_latest_artifact(
    file.path(release_evidence_artifact_root(repo_root), "ai-validation"),
    "summary.json"
  )

  bulunamadi <- list(
    found = FALSE,
    artifact_path = "",
    validation_execution_status = "not_found",
    profile_requested = "",
    profile_effective = "",
    failed_steps = NA_integer_,
    skipped_steps = NA_integer_,
    app_source_smoke_status = "",
    shiny_boot_smoke_status = "",
    browser_smoke_status = ""
  )

  veri <- release_evidence_read_json(yol)
  if (is.null(veri)) {
    return(bulunamadi)
  }

  .sayi <- function(name) {
    ham <- .release_evidence_scalar(veri, name, default = NA_character_)
    out <- suppressWarnings(as.integer(ham))
    if (length(out) != 1L) NA_integer_ else out
  }

  list(
    found = TRUE,
    artifact_path = yol,
    validation_execution_status = .release_evidence_scalar(
      veri, "validation_execution_status", default = "unknown"
    ),
    profile_requested = .release_evidence_scalar(veri, "profile_requested"),
    profile_effective = .release_evidence_scalar(veri, "profile_effective"),
    failed_steps = .sayi("failed_steps"),
    skipped_steps = .sayi("skipped_steps"),
    app_source_smoke_status = .release_evidence_scalar(veri, "app_source_smoke_status"),
    shiny_boot_smoke_status = .release_evidence_scalar(veri, "shiny_boot_smoke_status"),
    browser_smoke_status = .release_evidence_scalar(veri, "browser_smoke_status")
  )
}

# Bugünün uygulama logundaki ERROR/WARN satırlarını sınırlı pencerede sayar.
# Log satır İÇERİĞİ döndürülmez (redakte edilmiş olsa bile); yalnızca sayaç
# ve son hata zaman öneki raporlanır. Dosya yoksa güvenli sıfır özeti döner.
release_evidence_log_health <- function(log_dir = NULL, max_lines = 2000L) {
  if (is.null(log_dir) || !nzchar(log_dir %||% "")) {
    log_dir <- trimws(Sys.getenv("MERGEN_LOG_DIR", "logs"))
  }

  log_yolu <- file.path(
    log_dir,
    sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
  )

  bos <- list(
    found = FALSE,
    log_path = log_yolu,
    window_lines = 0L,
    error_count = 0L,
    warn_count = 0L,
    last_error_at = ""
  )

  if (!file.exists(log_yolu)) {
    return(bos)
  }

  satirlar <- tryCatch(
    readLines(log_yolu, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character(0)
  )
  if (!length(satirlar)) {
    bos$found <- TRUE
    return(bos)
  }

  # Sınırlı pencere: yalnızca son max_lines satır incelenir
  if (length(satirlar) > max_lines) {
    satirlar <- satirlar[(length(satirlar) - max_lines + 1L):length(satirlar)]
  }

  hata_satirlari <- satirlar[startsWith(satirlar, "ERROR")]
  uyari_satirlari <- satirlar[startsWith(satirlar, "WARN")]

  son_hata_zamani <- ""
  if (length(hata_satirlari)) {
    # Yalnızca köşeli parantezli zaman öneki çıkarılır; mesaj içeriği taşınmaz
    eslesme <- regmatches(
      hata_satirlari[length(hata_satirlari)],
      regexpr("\\[[0-9 :-]+\\]", hata_satirlari[length(hata_satirlari)])
    )
    if (length(eslesme)) {
      son_hata_zamani <- gsub("[][]", "", eslesme[1])
    }
  }

  list(
    found = TRUE,
    log_path = log_yolu,
    window_lines = length(satirlar),
    error_count = length(hata_satirlari),
    warn_count = length(uyari_satirlari),
    last_error_at = son_hata_zamani
  )
}

# Operatör görünümü için birleşik release kanıt özeti. Tüm alt özetler
# secret-safe alan seçiminden geçer; bulunamayan kanıtlar dürüstçe
# not_found olarak işaretlenir ve asla kanıt yerine geçmez.
release_evidence_overview <- function(repo_root = getwd(), log_dir = NULL) {
  list(
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    vm_evidence = release_evidence_vm_summary(repo_root),
    ai_validation = release_evidence_ai_validation_summary(repo_root),
    log_health = release_evidence_log_health(log_dir),
    proof_note = paste(
      "SKIP edilen adımlar kanıt değildir; cloud profili VM/SSO/DB/SQL Server",
      "Türkçe kodlama/gerçek tarayıcı kanıtı üretmez. Yalnızca 'passed' adımlar",
      "ilgili kapsam için kanıttır."
    )
  )
}
