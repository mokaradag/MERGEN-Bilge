# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_evidence_gate.R
# Aciklama:
#   MERGEN Bilge icin TEK tekrarlanabilir preflight dogrulama yolu. Var olan
#   dogrulama betiklerini sirali adimlar halinde TEMIZ COCUK R OTURUMLARINDA
#   calistirir ve secret-guvenli, makinece okunabilir tek bir kanit artifact'i
#   uretir: artifacts/vm-evidence/<timestamp>/evidence.json (+ adim loglari).
#
#   Kapsanan kanit alanlari:
#     - on-prem yapilandirma varsayimlari (env metadata; ham deger YAZILMAZ)
#     - parse sanity ve uygulama boot smoke
#     - tam strict testthat suiti
#     - maintainability raporu (skor)
#     - frontend maintainability ratchet
#     - seam doctor (governance/manifest tutarliligi)
#     - source manifest ve UI asset manifest sozlesme testleri
#     - tarayici UX smoke (varsa; MERGEN_BROWSER_BIN acikca verilmisse zorunlu)
#     - gercek VM preflight (SSO hazirligi + DB saglik + LLM erisilebilirlik)
#     - DB kodlama yazma/okuma preflight (transactional probe)
#     - renv kilit durumu
#
#   Profiller (MERGEN_EVIDENCE_PROFILE):
#     - "vm"    : VM-yalniz kapilar (vm_preflight, db_encoding, renv kilidi)
#                 ZORUNLUDUR; basarisizlik kapiyi dusurur.
#     - "cloud" : VM-yalniz kapilar gerekceli SKIP olur; yapisal + suit
#                 kaniti uretir. Varsayilan: SSO_ENABLED=TRUE ise "vm",
#                 degilse "cloud".
#
#   Durustluk sozlesmesi:
#     - Her adim icin proves / does_not_prove alanlari yazilir.
#     - SKIP edilen adim, kanit olarak RAPOR EDILEMEZ; evidence.json bunu
#       acikca "skipped" olarak tasir.
#     - Bu betik quit() CAGIRMAZ; source(...) ile guvenle calistirilabilir.
#       Zorunlu adim basarisizliginda stop() ile biter (Rscript altinda
#       sifir-disi cikis kodu uretir).
#
#   NOT: Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok).
#   Operasyonel giris noktasi betikleri (.Rprofile, tools/renv_snapshot.R gibi)
#   POSIX/C veya Windows/Turkce locale altinda source(...) edilirken sessiz
#   kirpilmaya ugramamalidir; kirpilan bir kapi HIC CALISMADAN exit 0
#   verebilir. Turkce ozel karakter EKLEMEYIN (diakritiksiz Turkce yorum
#   kullanin). Bu kisit test ile zorlanir:
#   tests/testthat/test-vm-evidence-gate-contract.R ("ascii-guvenli" testi).
#
# Kullanim:
#   Rscript tests/scripts/run_vm_evidence_gate.R
#   MERGEN_EVIDENCE_PROFILE=vm Rscript tests/scripts/run_vm_evidence_gate.R
#   MERGEN_EVIDENCE_STEPS=seam_doctor,renv_status Rscript tests/scripts/run_vm_evidence_gate.R
#   bash tools/vm_evidence_gate.sh
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

evidence_gate_repo_root <- function() {
  candidates <- c(".", "..", "../..")

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R")) &&
        dir.exists(file.path(cand, "tests", "scripts"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("run_vm_evidence_gate.R repo kokunden (veya yakinindan) calistirilmalidir.", call. = FALSE)
}

repo_root <- evidence_gate_repo_root()
old_wd <- getwd()
setwd(repo_root)
on.exit(setwd(old_wd), add = TRUE)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Kanit kapisi icin jsonlite paketi gereklidir (uygulamanin zorunlu paketi).", call. = FALSE)
}

# ------------------------------------------------------------------------------
# Secret-guvenli yardimcilar: ham ortam degeri ASLA yazilmaz.
# ------------------------------------------------------------------------------

evidence_value_metadata <- function(name) {
  value <- Sys.getenv(name, unset = "")
  list(
    name = name,
    present = nzchar(value),
    nchar = nchar(value, type = "bytes"),
    value = "<hidden>"
  )
}

evidence_env_flag_true <- function(name, default = FALSE) {
  raw <- tolower(trimws(Sys.getenv(name, unset = "")))
  if (!nzchar(raw)) return(isTRUE(default))
  raw %in% c("true", "t", "1", "yes", "y")
}

evidence_redact_text <- function(text) {
  sensitive_names <- c(
    "LOCAL_LLM_ENDPOINT", "LOCAL_LLM_API_KEY", "DB_DSN", "DB_PASSWORD",
    "AI_KEYS_MASTER", "SSO_KEYCLOAK_URL", "SSO_CLIENT_SECRET",
    "MERGEN_DEFAULT_API_KEY", "MERGEN_BROWSER_BIN"
  )

  values <- Sys.getenv(sensitive_names, unset = "")
  values <- unique(values[nzchar(values)])
  values <- values[order(nchar(values), decreasing = TRUE)]

  out <- paste(as.character(text %||% ""), collapse = "\n")
  for (v in values) {
    out <- gsub(v, "<hidden>", out, fixed = TRUE)
  }
  enc2utf8(out)
}

# ------------------------------------------------------------------------------
# Profil ve adim secimi
# ------------------------------------------------------------------------------

profile_requested <- tolower(trimws(Sys.getenv("MERGEN_EVIDENCE_PROFILE", unset = "")))

if (!profile_requested %in% c("", "vm", "cloud")) {
  stop(sprintf(
    "MERGEN_EVIDENCE_PROFILE gecersiz: %s. 'vm' veya 'cloud' kullanin.",
    profile_requested
  ), call. = FALSE)
}

profile_effective <- if (nzchar(profile_requested)) {
  profile_requested
} else if (evidence_env_flag_true("SSO_ENABLED")) {
  "vm"
} else {
  "cloud"
}

steps_filter_raw <- trimws(Sys.getenv("MERGEN_EVIDENCE_STEPS", unset = ""))
steps_filter <- if (nzchar(steps_filter_raw)) {
  trimws(strsplit(steps_filter_raw, ",", fixed = TRUE)[[1]])
} else {
  character(0)
}

# Cloud profilinde placeholder test env degerleri yalnizca EKSIKSE doldurulur;
# VM profilinde gercek ortam degerlerine dokunulmaz.
evidence_set_env_if_blank <- function(name, value) {
  if (!nzchar(Sys.getenv(name, unset = ""))) {
    do.call(Sys.setenv, stats::setNames(list(value), name))
  }
}

if (identical(profile_effective, "cloud")) {
  evidence_set_env_if_blank("LOCAL_LLM_ENDPOINT", "http://test.local/v1")
  evidence_set_env_if_blank("DB_DSN", "test-dsn")
  evidence_set_env_if_blank("AI_KEYS_MASTER", "test-master-key-evidence-gate")
  evidence_set_env_if_blank("TZ", "UTC")
}

# ------------------------------------------------------------------------------
# Artifact dizini ve cocuk oturum koscusu
# ------------------------------------------------------------------------------

gate_timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
artifact_dir <- file.path("artifacts", "vm-evidence", gate_timestamp)
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

rscript_bin <- file.path(R.home("bin"), "Rscript")
if (.Platform$OS.type == "windows") {
  rscript_bin <- paste0(rscript_bin, ".exe")
}

if (!file.exists(rscript_bin)) {
  stop(sprintf("Rscript bulunamadi: %s", rscript_bin), call. = FALSE)
}

# Cocuk runner basligi: once UTF-8 locale dene (POSIX/C ana surec altinda
# Turkce icerikli betiklerin source(encoding='UTF-8') ile sessiz kirpilmasini
# onler; Windows'ta sessizce basarisiz olur ve zarar vermez), sonra test modu.
child_runner_header <- c(
  "for (.loc in c('C.UTF-8', 'en_US.UTF-8', 'tr_TR.UTF-8')) {",
  "  ok <- tryCatch(nzchar(Sys.setlocale('LC_CTYPE', .loc)), error = function(e) FALSE, warning = function(w) FALSE)",
  "  if (isTRUE(ok)) break",
  "}",
  "Sys.setenv(MERGEN_RUN_APP = 'false', MERGEN_DISABLE_FUTURES = 'true')",
  "options(warn = 1)"
)

# Bir adimi temiz cocuk R oturumunda calistirir; stdout/stderr'i secret-guvenli
# bicimde adim log dosyasina yazar. extra_env yalnizca o cocuga uygulanir.
evidence_run_child_step <- function(step_id, code_lines, extra_env = character(0)) {
  runner_file <- file.path(artifact_dir, sprintf("step_%s_runner.R", step_id))
  log_file <- file.path(artifact_dir, sprintf("step_%s.log", step_id))

  writeLines(enc2utf8(c(child_runner_header, code_lines)), runner_file, useBytes = TRUE)

  env_args <- character(0)
  if (length(extra_env) > 0L) {
    env_args <- paste0(names(extra_env), "=", unname(extra_env))
  }

  started <- Sys.time()
  status <- suppressWarnings(system2(
    rscript_bin,
    args = c("--vanilla", runner_file),
    stdout = log_file,
    stderr = log_file,
    env = env_args
  ))
  duration <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  raw_log <- tryCatch(
    paste(readLines(log_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  writeLines(evidence_redact_text(raw_log), log_file, useBytes = TRUE)

  unlink(runner_file, force = TRUE)

  list(
    exit_status = as.integer(status %||% 1L),
    duration_sec = round(duration, 1),
    log_file = log_file
  )
}

# ------------------------------------------------------------------------------
# Adim tanimlari: id, etiket, profil-gereksinimi ve kanit sinirlari tek yerde.
# ------------------------------------------------------------------------------

evidence_step_specs <- list(
  list(
    id = "env_config",
    label = "On-prem yapilandirma varsayimlari (secret-safe metadata)",
    required_in = c("vm", "cloud"),
    proves = "Zorunlu ortam degiskenlerinin varligi ve kritik on-prem beklentileri (yalnizca metadata).",
    does_not_prove = "Degerlerin dogrulugu; gercek baglanti kurulabilirligi."
  ),
  list(
    id = "parse_sanity",
    label = "Parse sanity (tum runtime R dosyalari)",
    required_in = c("vm", "cloud"),
    proves = "Tum runtime R dosyalari UTF-8 ile parse edilebilir.",
    does_not_prove = "Calisma zamani davranisi."
  ),
  list(
    id = "app_boot_smoke",
    label = "Uygulama boot smoke (shiny.appobj)",
    required_in = c("vm", "cloud"),
    proves = "app.R kaynaklanir, validate_boot_state() gecer, shiny.appobj olusur.",
    does_not_prove = "Gercek sunucu/oturum davranisi, tarayici, DB."
  ),
  list(
    id = "full_testthat",
    label = "Tam strict testthat suiti (temiz cocuk oturum)",
    required_in = c("vm", "cloud"),
    proves = "Tum testthat sozlesme/regresyon testleri stop_on_failure/stop_on_warning ile gecti.",
    does_not_prove = "Gercek DB/SSO/tarayici/LLM davranisi (testler deterministik/offline)."
  ),
  list(
    id = "maintainability_report",
    label = "Maintainability raporu ve skor",
    required_in = c("vm", "cloud"),
    proves = "Runtime dosya butce/skor taban cizgisi korunuyor.",
    does_not_prove = "Islevsel dogruluk."
  ),
  list(
    id = "frontend_ratchet",
    label = "Frontend maintainability ratchet",
    required_in = c("vm", "cloud"),
    proves = "Frontend varlik butceleri ve yasak selektor taramalari gecti.",
    does_not_prove = "Gercek tarayici render davranisi."
  ),
  list(
    id = "seam_doctor",
    label = "Seam doctor (governance tutarliligi)",
    required_in = c("vm", "cloud"),
    proves = "Seam kayit defteri, bolge haritasi ve manifest yapisal olarak tutarli.",
    does_not_prove = "Calisma zamani/runtime kaniti."
  ),
  list(
    id = "source_manifest_contracts",
    label = "Source manifest sozlesme testleri",
    required_in = c("vm", "cloud"),
    proves = "Runtime kaynak sirasi ve manifest butunlugu korunuyor.",
    does_not_prove = "Yuklenen dosyalarin davranissal dogrulugu."
  ),
  list(
    id = "ui_asset_manifest_contracts",
    label = "UI asset manifest + bolge sozlesme testleri",
    required_in = c("vm", "cloud"),
    proves = "Frontend varlik yukleme sirasi ve sahiplik bolumlemesi korunuyor.",
    does_not_prove = "Gercek tarayicida varlik yuklenmesi."
  ),
  list(
    id = "browser_ux_smoke",
    label = "Tarayici UX smoke (varsa zorunlu, yoksa gerekceli SKIP)",
    required_in = character(0),
    proves = "UX_SMOKE_DONE:PASS ile akis/ses/dosya-adi kritik akislari gercek tarayicida calisti.",
    does_not_prove = "SSO/Keycloak yonlendirmeli uretim akisi."
  ),
  list(
    id = "vm_preflight_real",
    label = "Gercek VM preflight (SSO hazirlik + DB saglik + LLM erisilebilirlik)",
    required_in = c("vm"),
    proves = "Gercek ortamda boot, SSO config, DB saglik, LLM erisilebilirlik, yazilabilir yollar.",
    does_not_prove = "Tarayici UX; SQL Server Turkce kodlama yazma davranisi (ayri adim)."
  ),
  list(
    id = "db_encoding_preflight",
    label = "DB kodlama yazma/okuma preflight (transactional probe)",
    required_in = c("vm"),
    proves = "Turkce metin + kacis token yazma/okuma sinirlari gercek DB'de dogru; probe rollback edildi.",
    does_not_prove = "Eski (legacy) satirlarin temizligi."
  ),
  list(
    id = "renv_status",
    label = "renv kilit durumu",
    required_in = c("vm"),
    proves = "Bagimlilik kilidi beklenen yerde ve R surumu raporlandi.",
    does_not_prove = "Kilit iceriginin calisan kutuphane ile birebir eslesmesi."
  )
)

# ------------------------------------------------------------------------------
# Adim uygulayicilari
# ------------------------------------------------------------------------------

run_step_env_config <- function() {
  required_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
  sso_enabled <- evidence_env_flag_true("SSO_ENABLED")

  if (isTRUE(sso_enabled)) {
    required_vars <- c(required_vars, "SSO_KEYCLOAK_URL")
  }

  observed <- lapply(required_vars, evidence_value_metadata)
  missing_vars <- vapply(observed, function(m) !isTRUE(m$present), logical(1))

  notes <- character(0)
  ok <- TRUE

  if (any(missing_vars)) {
    ok <- FALSE
    notes <- c(notes, sprintf(
      "Eksik zorunlu ortam degiskenleri: %s",
      paste(required_vars[missing_vars], collapse = ", ")
    ))
  }

  db_client_enc <- toupper(trimws(Sys.getenv("DB_CLIENT_ENCODING", unset = "")))
  db_name_enc <- toupper(trimws(Sys.getenv("DB_NAME_ENCODING", unset = "")))

  if (identical(profile_effective, "vm")) {
    if (!identical(db_client_enc, "WINDOWS-1254")) {
      ok <- FALSE
      notes <- c(notes, sprintf(
        "VM profili DB_CLIENT_ENCODING=WINDOWS-1254 bekler; gozlenen: %s",
        if (nzchar(db_client_enc)) db_client_enc else "<bos>"
      ))
    }
    if (!identical(db_name_enc, "WINDOWS-1254")) {
      ok <- FALSE
      notes <- c(notes, sprintf(
        "VM profili DB_NAME_ENCODING=WINDOWS-1254 bekler; gozlenen: %s",
        if (nzchar(db_name_enc)) db_name_enc else "<bos>"
      ))
    }

    port_raw <- trimws(Sys.getenv("MERGEN_PORT", unset = ""))
    if (nzchar(port_raw) && !identical(port_raw, "8009")) {
      ok <- FALSE
      notes <- c(notes, sprintf("VM profili MERGEN_PORT=8009 bekler; gozlenen: %s", port_raw))
    }

    if (!isTRUE(sso_enabled)) {
      ok <- FALSE
      notes <- c(notes, "VM profili SSO_ENABLED=TRUE bekler.")
    }
  }

  optional_path_vars <- c(
    "MERGEN_FILES_ROOT", "MERGEN_UPLOADS_DIR", "MERGEN_INDEX_PATH",
    "MCP_FILES_BASE", "MERGEN_MCP_BASE_DIR", "MERGEN_LOG_DIR"
  )

  detail <- list(
    sso_enabled = sso_enabled,
    db_client_encoding = if (nzchar(db_client_enc)) db_client_enc else "<bos>",
    db_name_encoding = if (nzchar(db_name_enc)) db_name_enc else "<bos>",
    required_env = observed,
    optional_path_env = lapply(optional_path_vars, evidence_value_metadata)
  )

  log_file <- file.path(artifact_dir, "step_env_config.log")
  writeLines(enc2utf8(c(
    sprintf("profile_effective=%s", profile_effective),
    sprintf("sso_enabled=%s", sso_enabled),
    sprintf("db_client_encoding=%s", detail$db_client_encoding),
    sprintf("db_name_encoding=%s", detail$db_name_encoding),
    vapply(observed, function(m) {
      sprintf("env %s: present=%s nchar=%d value=<hidden>", m$name, m$present, m$nchar)
    }, character(1)),
    notes
  )), log_file, useBytes = TRUE)

  list(ok = ok, notes = notes, detail = detail, log_file = log_file, duration_sec = 0)
}

run_step_simple_child <- function(step_id, body_lines, extra_env = character(0)) {
  res <- evidence_run_child_step(step_id, body_lines, extra_env)
  list(
    ok = identical(res$exit_status, 0L),
    notes = if (identical(res$exit_status, 0L)) character(0) else sprintf(
      "Cocuk oturum sifir-disi cikti (exit=%d). Log: %s", res$exit_status, res$log_file
    ),
    detail = list(exit_status = res$exit_status),
    log_file = res$log_file,
    duration_sec = res$duration_sec
  )
}

run_step_browser_ux_smoke <- function() {
  browser_bin_set <- nzchar(Sys.getenv("MERGEN_BROWSER_BIN", unset = ""))
  require_browser <- browser_bin_set ||
    evidence_env_flag_true("MERGEN_REQUIRE_BROWSER_UX_SMOKE")

  res <- run_step_simple_child(
    "browser_ux_smoke",
    "source('tests/scripts/ai_browser_ux_smoke.R', encoding = 'UTF-8')"
  )

  log_text <- tryCatch(
    paste(readLines(res$log_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )

  # Durustluk kurali: bu adim yalnizca gercek UX_SMOKE_DONE:PASS kanitiyla
  # "passed" sayilir. Alt betik tarayici yokken exit 0 ile SKIP yazabilir;
  # bu durum kanit DEGILDIR ve "skipped" olarak siniflandirilir. Tarayici
  # zorunluysa SKIP de basarisizliktir.
  smoke_pass_seen <- grepl("UX_SMOKE_DONE:PASS", log_text, fixed = TRUE)
  smoke_skip_seen <- grepl("SKIP", log_text, fixed = TRUE)

  if (isTRUE(res$ok) && !smoke_pass_seen) {
    if (smoke_skip_seen && !require_browser) {
      res$ok <- FALSE
      res$skipped <- TRUE
      res$notes <- "Yerel tarayici binari yok; smoke SKIP (zorunlu degil; kanit uretilmedi)."
    } else {
      res$ok <- FALSE
      res$notes <- "Cocuk oturum exit 0 ama UX_SMOKE_DONE:PASS kaniti yok; adim passed sayilamaz."
    }
  }

  if (!isTRUE(res$ok) && !isTRUE(res$skipped) && !require_browser && smoke_skip_seen) {
    res$skipped <- TRUE
    res$notes <- "Yerel tarayici binari yok; smoke SKIP (zorunlu degil)."
  }

  res$detail$require_browser <- require_browser
  res$detail$browser_bin_set <- browser_bin_set
  res$detail$ux_smoke_pass_marker <- smoke_pass_seen
  res
}

run_step_renv_status <- function() {
  lock_exists <- file.exists("renv.lock")
  marker_exists <- file.exists("RENV_LOCK_STATUS.md")
  library_populated <- length(Sys.glob(file.path("renv", "library", "*", "*", "*", "*", "DESCRIPTION"))) > 0L

  detail <- list(
    renv_lock_present = lock_exists,
    renv_status_marker_present = marker_exists,
    renv_library_populated = library_populated,
    r_version = paste(R.version$major, R.version$minor, sep = ".")
  )

  ok <- TRUE
  notes <- character(0)

  if (identical(profile_effective, "vm") && !lock_exists) {
    ok <- FALSE
    notes <- c(notes, "VM profili calisan kopyada commit edilmis renv.lock bekler.")
  }

  if (identical(profile_effective, "cloud") && !lock_exists && !marker_exists) {
    notes <- c(notes, "Cloud checkout'unda ne renv.lock ne RENV_LOCK_STATUS.md var; provenance isaretcisi eksik.")
  }

  log_file <- file.path(artifact_dir, "step_renv_status.log")
  writeLines(enc2utf8(c(
    sprintf("renv.lock present=%s", lock_exists),
    sprintf("RENV_LOCK_STATUS.md present=%s", marker_exists),
    sprintf("renv/library populated=%s", library_populated),
    sprintf("R version=%s", detail$r_version),
    notes
  )), log_file, useBytes = TRUE)

  list(ok = ok, notes = notes, detail = detail, log_file = log_file, duration_sec = 0)
}

evidence_step_runners <- list(
  env_config = run_step_env_config,
  parse_sanity = function() run_step_simple_child(
    "parse_sanity",
    "source('tests/scripts/parse_sanity_check.R', encoding = 'UTF-8')"
  ),
  app_boot_smoke = function() run_step_simple_child(
    "app_boot_smoke",
    "source('tests/scripts/smoke_app_boot.R', encoding = 'UTF-8')"
  ),
  full_testthat = function() run_step_simple_child(
    "full_testthat",
    "source('tests/testthat.R', encoding = 'UTF-8')",
    extra_env = c(TZ = "UTC")
  ),
  maintainability_report = function() run_step_simple_child(
    "maintainability_report",
    c(
      "maint_env <- new.env(parent = globalenv())",
      "res <- source('tests/scripts/maintainability_report.R', encoding = 'UTF-8', local = maint_env)$value",
      "score <- attr(res, 'maintainability_score', exact = TRUE)",
      "if (is.null(score) || is.na(score)) stop('Maintainability skoru okunamadi.')",
      "cat(sprintf('EVIDENCE_MAINTAINABILITY_SCORE:%d\\n', as.integer(score)))"
    )
  ),
  frontend_ratchet = function() run_step_simple_child(
    "frontend_ratchet",
    c(
      "library(testthat)",
      "res <- test_file('tests/testthat/test-frontend-maintainability-ratchet.R', reporter = 'summary')",
      "df <- as.data.frame(res)",
      "if (sum(df$failed) > 0 || any(df$error)) stop('Frontend ratchet basarisiz.')"
    )
  ),
  seam_doctor = function() run_step_simple_child(
    "seam_doctor",
    "source('tests/scripts/seam_doctor.R', encoding = 'UTF-8')"
  ),
  source_manifest_contracts = function() run_step_simple_child(
    "source_manifest_contracts",
    c(
      "library(testthat)",
      "files <- c(",
      "  'tests/testthat/test-source-manifest-contract.R',",
      "  'tests/testthat/test-global-source-manifest-contract.R',",
      "  'tests/testthat/test-source-manifest-sections-contract.R'",
      ")",
      "for (f in files) {",
      "  res <- test_file(f, reporter = 'summary')",
      "  df <- as.data.frame(res)",
      "  if (sum(df$failed) > 0 || any(df$error)) stop(sprintf('Sozlesme basarisiz: %s', f))",
      "}"
    )
  ),
  ui_asset_manifest_contracts = function() run_step_simple_child(
    "ui_asset_manifest_contracts",
    c(
      "library(testthat)",
      "files <- c(",
      "  'tests/testthat/test-ui-asset-manifest-contract.R',",
      "  'tests/testthat/test-ui-asset-zones-contract.R'",
      ")",
      "for (f in files) {",
      "  res <- test_file(f, reporter = 'summary')",
      "  df <- as.data.frame(res)",
      "  if (sum(df$failed) > 0 || any(df$error)) stop(sprintf('Sozlesme basarisiz: %s', f))",
      "}"
    )
  ),
  browser_ux_smoke = run_step_browser_ux_smoke,
  vm_preflight_real = function() run_step_simple_child(
    "vm_preflight_real",
    "source('tests/scripts/run_vm_preflight_real.R', encoding = 'UTF-8')"
  ),
  db_encoding_preflight = function() run_step_simple_child(
    "db_encoding_preflight",
    "source('tests/scripts/run_vm_encoding_preflight_real.R', encoding = 'UTF-8')",
    extra_env = c(
      MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE",
      MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE = Sys.getenv(
        "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE", unset = "FALSE"
      )
    )
  ),
  renv_status = run_step_renv_status
)

# ------------------------------------------------------------------------------
# Adimlari calistir
# ------------------------------------------------------------------------------

cat("== MERGEN VM kanit kapisi ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Profil (istenen/etkin): %s/%s\n",
            if (nzchar(profile_requested)) profile_requested else "<auto>",
            profile_effective))
cat(sprintf("Artifact dizini: %s\n\n", artifact_dir))

step_results <- list()

for (spec in evidence_step_specs) {
  step_id <- spec$id
  required <- profile_effective %in% spec$required_in

  if (length(steps_filter) > 0L && !(step_id %in% steps_filter)) {
    step_results[[step_id]] <- list(
      spec = spec, status = "skipped", required = FALSE,
      notes = "MERGEN_EVIDENCE_STEPS filtresi disinda.",
      detail = list(), log_file = NULL, duration_sec = 0
    )
    cat(sprintf("[ATLANDI] %-28s (adim filtresi)\n", step_id))
    next
  }

  vm_only <- identical(spec$required_in, "vm")
  if (vm_only && identical(profile_effective, "cloud")) {
    step_results[[step_id]] <- list(
      spec = spec, status = "skipped", required = FALSE,
      notes = "VM-yalniz kapi; cloud profilinde gerekceli SKIP.",
      detail = list(), log_file = NULL, duration_sec = 0
    )
    cat(sprintf("[ATLANDI] %-28s (VM-yalniz; profil=cloud)\n", step_id))
    next
  }

  cat(sprintf("[KOSULUYOR] %-26s ...", step_id))
  res <- tryCatch(
    evidence_step_runners[[step_id]](),
    error = function(e) list(
      ok = FALSE,
      notes = sprintf("Adim calistiricisi hata verdi: %s", evidence_redact_text(conditionMessage(e))),
      detail = list(), log_file = NULL, duration_sec = 0
    )
  )

  status <- if (isTRUE(res$skipped)) {
    "skipped"
  } else if (isTRUE(res$ok)) {
    "passed"
  } else {
    "failed"
  }

  step_results[[step_id]] <- list(
    spec = spec,
    status = status,
    required = required,
    notes = as.character(res$notes %||% character(0)),
    detail = res$detail %||% list(),
    log_file = res$log_file,
    duration_sec = res$duration_sec %||% 0
  )

  cat(sprintf(" %s (%.1f sn)\n", toupper(status), res$duration_sec %||% 0))
}

# ------------------------------------------------------------------------------
# Kanit artifact'i
# ------------------------------------------------------------------------------

git_field <- function(args) {
  out <- tryCatch(
    suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE)),
    error = function(e) character(0)
  )
  if (length(out) == 0L) "" else trimws(out[1])
}

failed_required <- vapply(step_results, function(r) {
  identical(r$status, "failed") && isTRUE(r$required)
}, logical(1))

failed_optional <- vapply(step_results, function(r) {
  identical(r$status, "failed") && !isTRUE(r$required)
}, logical(1))

overall_status <- if (any(failed_required)) "failed" else "passed"

evidence <- list(
  gate = "run_vm_evidence_gate",
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  validation_execution_status = "ran_by_vm_evidence_gate",
  profile_requested = if (nzchar(profile_requested)) profile_requested else "<auto>",
  profile_effective = profile_effective,
  overall_status = overall_status,
  secret_policy = "Ham ortam degeri yazilmaz; yalnizca present/nchar/value=<hidden> metadata.",
  git = list(
    branch = git_field(c("rev-parse", "--abbrev-ref", "HEAD")),
    sha = git_field(c("rev-parse", "--short", "HEAD")),
    dirty = nzchar(git_field(c("status", "--porcelain")))
  ),
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  steps = lapply(names(step_results), function(step_id) {
    r <- step_results[[step_id]]
    list(
      id = step_id,
      label = r$spec$label,
      status = r$status,
      required = r$required,
      duration_sec = r$duration_sec,
      log_file = r$log_file %||% "",
      notes = r$notes,
      proves = r$spec$proves,
      does_not_prove = r$spec$does_not_prove,
      detail = r$detail
    )
  }),
  counts = list(
    passed = sum(vapply(step_results, function(r) identical(r$status, "passed"), logical(1))),
    failed = sum(vapply(step_results, function(r) identical(r$status, "failed"), logical(1))),
    skipped = sum(vapply(step_results, function(r) identical(r$status, "skipped"), logical(1)))
  ),
  proof_boundary_notes = paste(
    "SKIP edilen adimlar kanit DEGILDIR. Cloud profili VM/SSO/DB/SQL Server",
    "Turkce kodlama/gercek tarayici kaniti uretmez; bu kapilar yalnizca",
    "profile_effective=vm kosumunda ve ilgili adimlar passed oldugunda kanittir."
  )
)

evidence_json_path <- file.path(artifact_dir, "evidence.json")
evidence_json <- jsonlite::toJSON(evidence, auto_unbox = TRUE, pretty = TRUE, null = "null")
writeLines(evidence_redact_text(as.character(evidence_json)), evidence_json_path, useBytes = TRUE)

cat("\n=== Kanit kapisi ozeti ===\n")
for (step_id in names(step_results)) {
  r <- step_results[[step_id]]
  cat(sprintf(
    "  %-28s %-8s %s\n",
    step_id,
    toupper(r$status),
    if (length(r$notes) > 0L) paste0("- ", paste(r$notes, collapse = " | ")) else ""
  ))
}

cat(sprintf(
  "\nToplam: %d passed, %d failed, %d skipped\n",
  evidence$counts$passed, evidence$counts$failed, evidence$counts$skipped
))
cat(sprintf("Kanit artifact'i: %s\n", evidence_json_path))

if (any(failed_optional)) {
  cat("WARN: Zorunlu olmayan adim(lar) basarisiz oldu; loglari inceleyin.\n")
}

# quit() kullanilmaz: source(...) ile guvenli; stop() Rscript altinda
# sifir-disi cikis kodu uretir.
if (identical(overall_status, "failed")) {
  stop(sprintf(
    "VM kanit kapisi basarisiz: %s. Ayrintilar: %s",
    paste(names(step_results)[failed_required], collapse = ", "),
    evidence_json_path
  ), call. = FALSE)
}

cat("OK: VM kanit kapisi basariyla tamamlandi.\n")
invisible(TRUE)
