# ==============================================================================
# Dosya Yolu: tests/scripts/run_post_deploy_smoke.R
# Açıklama: Dağıtım sonrası duman testi kapısı. Uygulama ortamını güvenli boot
#           modunda yükler, sağlık kontrollerini toplar ve dağıtım sonrası genel
#           durumu hesaplar. Kritik bir kontrol bozuksa sıfırdan farklı çıkışla
#           (stop) başarısız olur. Sırları redakte ederek özet basar.
#
#           Her çıkış yolunda (başarı, degraded, fail VE erken boot/env
#           başarısızlıkları) stop'tan ÖNCE secret-safe bir kanıt artifact'ı
#           yazar: artifacts/post-deploy-smoke/<timestamp>/post-deploy-smoke.json.
#           Böylece sağlık paneli koşumu "not_found" sanmaz; başarısız kapı
#           sonucu korunur.
#
# Kullanım (uygulama VM'de ayaktayken, repo kökünden):
#   Rscript tests/scripts/run_post_deploy_smoke.R
#
# Yapılandırma:
#   MERGEN_SMOKE_CRITICAL_IDS=app.boot,db.primary,storage.disk_free
#   MERGEN_SMOKE_FAIL_ON_UNKNOWN=FALSE
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "tests", "scripts"))) {
  stop("run_post_deploy_smoke.R repo kökünden çalıştırılmalıdır.", call. = FALSE)
}

# --- Yardımcılar -------------------------------------------------------------

.smoke_normalize_bool <- function(value, default = FALSE) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }
  norm <- tolower(trimws(as.character(value[1])))
  if (!nzchar(norm)) return(default)
  if (norm %in% c("true", "t", "1", "yes")) return(TRUE)
  if (norm %in% c("false", "f", "0", "no")) return(FALSE)
  default
}

# Saf değerlendirici + kanıt-kaydı + başarısızlık-sonucu yardımcıları. app.R'den
# BAĞIMSIZDIR; bu yüzden erken boot/env başarısızlıklarında bile artifact yazmak
# için ÖNCE (app.R'den önce) yüklenir.
source("tests/scripts/helpers_post_deploy_smoke.R", encoding = "UTF-8")

# --- Sırları redakte eden çıktı yardımcısı (erken yüklenir) ------------------

.smoke_redact <- function(text) {
  out <- as.character(text)
  if (length(out) == 0L) return("")
  if (is.na(out[1])) out[1] <- ""

  # Bilinen hassas env değerlerini maskele (uzundan kısaya).
  sensitive_names <- c(
    "LOCAL_LLM_ENDPOINT", "LOCAL_LLM_API_KEY", "DB_DSN", "DB_PASSWORD",
    "AI_KEYS_MASTER", "SSO_KEYCLOAK_URL", "SSO_CLIENT_SECRET"
  )
  values <- Sys.getenv(sensitive_names, unset = "")
  values <- unique(values[nzchar(values)])
  values <- values[order(nchar(values), decreasing = TRUE)]
  for (value in values) {
    out <- gsub(value, "<hidden>", out, fixed = TRUE)
  }

  # Genel redaktör mevcutsa (app.R yüklendikten sonra) ek olarak token/JWT/anahtar
  # desenlerini de maskele. app.R'den önce çağrılırsa bu adım atlanır (env masking
  # yine uygulanır ve kayıt zaten secret-safe kurulur).
  if (exists("redact_sensitive_text", mode = "function")) {
    out <- tryCatch(redact_sensitive_text(out), error = function(e) out)
  }

  enc2utf8(out)
}

.smoke_git_field <- function(args) {
  out <- tryCatch(
    suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE)),
    error = function(e) character(0)
  )
  if (length(out) == 0L) "" else trimws(out[1])
}

# Kritik kontrol kimlikleri ve fail_on_unknown yalnızca env'e bağlıdır; hem erken
# hem normal artifact yazımı için hemen hesaplanır.
critical_ids_raw <- Sys.getenv("MERGEN_SMOKE_CRITICAL_IDS", "")
critical_ids <- if (nzchar(critical_ids_raw)) {
  trimws(strsplit(critical_ids_raw, ",", fixed = TRUE)[[1]])
} else {
  c("app.boot", "db.primary", "storage.disk_free")
}

fail_on_unknown <- .smoke_normalize_bool(
  Sys.getenv("MERGEN_SMOKE_FAIL_ON_UNKNOWN", "FALSE"),
  default = FALSE
)

# Değerlendirici sonucundan secret-safe artifact'ı yazar; yol döndürür (hata →
# WARN + ""). Redaksiyon yalnızca yapısal string DEĞERLERE uygulanır (anahtarlar/
# sayaçlar/enum'lar korunur), sonra serileştirilir → şema asla bozulmaz.
.smoke_write_artifact <- function(result) {
  tryCatch({
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      stop("jsonlite paketi yok", call. = FALSE)
    }

    record <- mergen_post_deploy_smoke_artifact_record(
      result,
      critical_ids = critical_ids,
      fail_on_unknown = fail_on_unknown,
      git_info = list(
        branch = .smoke_git_field(c("rev-parse", "--abbrev-ref", "HEAD")),
        sha = .smoke_git_field(c("rev-parse", "--short", "HEAD")),
        dirty = nzchar(.smoke_git_field(c("status", "--porcelain")))
      )
    )

    artifact_ts <- format(Sys.time(), "%Y%m%d-%H%M%S")
    artifact_dir <- file.path("artifacts", "post-deploy-smoke", artifact_ts)
    dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

    out_path <- file.path(artifact_dir, "post-deploy-smoke.json")
    safe_record <- mergen_post_deploy_smoke_redact_record(record, redact_fn = .smoke_redact)
    json_txt <- as.character(jsonlite::toJSON(safe_record, auto_unbox = TRUE, pretty = TRUE, null = "null"))
    writeLines(json_txt, out_path, useBytes = TRUE)
    out_path
  }, error = function(e) {
    cat(sprintf("WARN: Kanıt artifact'ı yazılamadı: %s\n", .smoke_redact(conditionMessage(e))))
    ""
  })
}

# Erken boot/env başarısızlığında: stop'tan ÖNCE bir BAŞARISIZLIK artifact'ı yaz,
# yolu bas, sonra sıfırdan farklı çıkışla dur. Böylece sağlık paneli koşumu
# "not_found" değil, başarısız kapı olarak görür.
.smoke_fail_and_stop <- function(reason, message) {
  artifact_path <- .smoke_write_artifact(mergen_post_deploy_smoke_failure_result(reason))
  if (nzchar(artifact_path)) {
    cat(sprintf("- Kanıt artifact'ı (başarısızlık): %s\n", artifact_path))
  }
  stop(message, call. = FALSE)
}

# --- Zorunlu env kontrolü (erken çıkışta bile artifact yazılır) --------------

# Üretim profilinde uygulamanın boot için ihtiyaç duyduğu zorunlu değişkenler.
.smoke_required_env <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
.smoke_missing_env <- .smoke_required_env[
  !nzchar(trimws(Sys.getenv(.smoke_required_env, unset = "")))
]
if (length(.smoke_missing_env) > 0) {
  .smoke_fail_and_stop(
    "missing_required_env",
    sprintf(
      "Dağıtım sonrası duman testi durduruldu. Eksik zorunlu ortam değişkenleri: %s",
      paste(.smoke_missing_env, collapse = ", ")
    )
  )
}

# Boot için process-genel env değişkenlerini geçici ayarla ve çıkışta geri yükle.
.smoke_env_to_restore <- c("MERGEN_DISABLE_FUTURES", "MERGEN_RUN_APP")
.smoke_env_snapshot <- Sys.getenv(.smoke_env_to_restore, unset = NA_character_)

on.exit({
  for (nm in names(.smoke_env_snapshot)) {
    old_value <- .smoke_env_snapshot[[nm]]
    if (is.na(old_value)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(old_value), nm))
    }
  }
}, add = TRUE)

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false"
)

# --- Ortamı yükle (app.R başarısız olsa bile artifact yazılır) ---------------

boot_ok <- tryCatch({
  source("app.R", encoding = "UTF-8")
  TRUE
}, error = function(e) {
  cat(sprintf("WARN: app.R yüklenemedi: %s\n", .smoke_redact(conditionMessage(e))))
  FALSE
})

if (!isTRUE(boot_ok)) {
  .smoke_fail_and_stop(
    "app_boot_failed",
    "Dağıtım sonrası duman testi başarısız: app.R yüklenemedi."
  )
}

if (!exists("health_collect_checks", envir = globalenv(), mode = "function")) {
  .smoke_fail_and_stop(
    "health_collect_checks_missing",
    "Dağıtım sonrası duman testi başarısız: health_collect_checks() bulunamadı."
  )
}

# --- Sağlık kontrollerini topla ve değerlendir -------------------------------

checks <- tryCatch(
  health_collect_checks(include_slow = TRUE),
  error = function(e) {
    cat(sprintf("WARN: health_collect_checks hata verdi: %s\n", .smoke_redact(conditionMessage(e))))
    NULL
  }
)

result <- mergen_post_deploy_smoke_evaluate(
  checks,
  critical_ids = critical_ids,
  fail_on_unknown = fail_on_unknown
)

# --- Özet -------------------------------------------------------------------

cat("\n== Dağıtım Sonrası Duman Testi ==\n")
cat(sprintf("- Genel durum   : %s\n", result$overall))
cat(sprintf("- Kontrol sayısı: %d\n", result$total))

if (length(result$counts) > 0L) {
  for (nm in names(result$counts)) {
    cat(sprintf("  - %-15s: %d\n", nm, as.integer(result$counts[[nm]])))
  }
}

if (length(result$failing) > 0L) {
  cat(sprintf("- Başarısız kontroller: %s\n", .smoke_redact(paste(result$failing, collapse = ", "))))
}
if (length(result$critical_failures) > 0L) {
  cat(sprintf("- Kritik bozulmalar  : %s\n", .smoke_redact(paste(result$critical_failures, collapse = ", "))))
}

# --- Makinece okunabilir kanıt artifact'ı (secret-safe) ----------------------
# Kapı, başarısız olsa bile önce kanıt artifact'ını yazar (stop'tan ÖNCE), böylece
# "fail"/"degraded" koşumlar da operatör ve release kanıt okuyucusu için iz bırakır.

artifact_path <- .smoke_write_artifact(result)

if (nzchar(artifact_path)) {
  cat(sprintf("- Kanıt artifact'ı   : %s\n", artifact_path))
}

if (isTRUE(result$should_fail)) {
  stop(sprintf(
    "Dağıtım sonrası duman testi REDDEDİLDİ (durum=%s, neden=%s). Sağlık panelini ve logları inceleyin.",
    result$overall,
    result$reason
  ), call. = FALSE)
}

cat("OK: Dağıtım sonrası duman testi geçti.\n")
