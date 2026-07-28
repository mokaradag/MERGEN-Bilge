#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/seam_doctor.R
# Açıklama:
#   Üretim-kritik dikiş (seam) kayıt defterini ve frontend bölge sahiplik
#   haritasını manifest gerçekliğine karşı doğrular; insan-okur özet ve
#   secret-güvenli JSON artifact üretir.
#
#   Bu script ağır kontrol ÇALIŞTIRMAZ: uygulamayı, tarayıcıyı, DB'yi, LLM'i
#   veya ağı başlatmaz. Validation doctor gibi rehberlik aracıdır; ancak
#   yapısal seam/bölge sözleşmesi bozulmuşsa sıfır-dışı çıkış koduyla biter,
#   böylece CI/VM akışlarında erken uyarı verir. Kanıt kapısı olarak testthat
#   sözleşme testleri (test-seam-registry-contract.R,
#   test-ui-asset-zones-contract.R) esastır.
#
# Kullanım:
#   Rscript tests/scripts/seam_doctor.R
#   Rscript tests/scripts/seam_doctor.R --artifact-dir artifacts/seam-doctor
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]

  if (length(direct) > 0L) {
    return(sub(prefix, "", direct[[1]], fixed = TRUE))
  }

  pos <- match(name, args)

  if (!is.na(pos) && pos < length(args)) {
    return(args[[pos + 1L]])
  }

  default
}

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R")) &&
        dir.exists(file.path(cand, "tests", "scripts"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Repo root bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

artifact_dir <- arg_value("--artifact-dir", file.path("artifacts", "seam-doctor"))
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

json_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\\\\\", x, perl = TRUE)
  x <- gsub("\"", "\\\\\"", x, perl = TRUE)
  x <- gsub("\n", "\\\\n", x, perl = TRUE)
  x <- gsub("\r", "\\\\r", x, perl = TRUE)
  x <- gsub("\t", "\\\\t", x, perl = TRUE)
  x
}

json_string_array <- function(values) {
  if (length(values) == 0L) {
    return("[]")
  }

  paste0("[", paste(sprintf("\"%s\"", json_escape(values)), collapse = ","), "]")
}

# Governance katmanını izole ortamda yükle; global ortamı kirletme.
gov_env <- new.env(parent = globalenv())

source("R/config_source_manifest.R", encoding = "UTF-8", local = gov_env)
source("R/config_ui_assets.R", encoding = "UTF-8", local = gov_env)
source("R/config_ui_asset_validators.R", encoding = "UTF-8", local = gov_env)
source("R/config_ui_asset_tags.R", encoding = "UTF-8", local = gov_env)
source("R/config_ui_asset_zones.R", encoding = "UTF-8", local = gov_env)
source("R/config_ui_asset_zone_validators.R", encoding = "UTF-8", local = gov_env)
source("R/config_seam_registry.R", encoding = "UTF-8", local = gov_env)

registry <- gov_env$mergen_seam_registry()
sections <- gov_env$source_manifest_sections
zones <- gov_env$ui_asset_ownership_zones
unmanifested <- gov_env$ui_asset_unmanifested_ownership

zone_owners <- gov_env$ui_asset_zone_owner_seams(zones)

seam_problems <- gov_env$mergen_seam_registry_validate(
  registry = registry,
  manifest_section_names = names(sections),
  zone_owner_seam_ids = zone_owners,
  repo_root = repo_root
)

zone_problems <- gov_env$ui_asset_zones_validate(
  zones = zones,
  css_paths = gov_env$ui_asset_all_css(),
  js_paths = gov_env$ui_asset_all_js(),
  css_groups = gov_env$ui_asset_css_groups,
  js_groups = gov_env$ui_asset_js_groups,
  unmanifested = unmanifested,
  repo_root = repo_root
)

ownership_gaps <- gov_env$ui_asset_frontend_ownership_gaps(
  repo_root = repo_root,
  zones = zones,
  css_paths = gov_env$ui_asset_all_css(),
  js_paths = gov_env$ui_asset_all_js(),
  unmanifested = unmanifested
)

orphan_r_files <- setdiff(
  file.path("R", list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = FALSE)),
  c(gov_env$source_manifest_runtime_paths, gov_env$mergen_seam_runtime_allowlist(registry))
)

all_problems <- c(seam_problems, zone_problems)

if (length(ownership_gaps) > 0L) {
  all_problems <- c(all_problems, sprintf(
    "Sahipsiz frontend dosyası: %s",
    paste(ownership_gaps, collapse = ", ")
  ))
}

if (length(orphan_r_files) > 0L) {
  # Her sahipsiz dosya AYRI bir sorun kaydı olur: tek satırda birleştirilen
  # uzun bir liste Windows konsolunda kırpılabilir ve dosya adının sonu
  # kaybolarak yanlış teşhise yol açar.
  for (orphan in orphan_r_files) {
    benzer <- tryCatch(
      setdiff(
        agrep(basename(orphan), basename(gov_env$source_manifest_runtime_paths),
              max.distance = 0.1, ignore.case = TRUE, value = TRUE),
        basename(orphan)
      ),
      error = function(e) character(0)
    )

    all_problems <- c(all_problems, sprintf(
      "Sahipsiz R/ runtime dosyası: %s%s",
      orphan,
      if (length(benzer)) {
        sprintf(
          " (manifestte benzer adlı kayıt: %s -> çalışma kopyası git ile senkron değil olabilir)",
          paste(benzer, collapse = ", ")
        )
      } else {
        ""
      }
    ))
  }
}

cat("== MERGEN seam doctor ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Seam sayısı: %d\n", length(registry)))
cat(sprintf("Manifest bölüm sayısı: %d\n", length(sections)))
cat(sprintf("Frontend bölge sayısı: %d\n", length(zones)))
cat(sprintf("Manifest dışı sahipli frontend dosyası: %d\n", length(unmanifested)))
cat("\n")

seam_lines <- character(0)

for (seam_id in names(registry)) {
  seam <- registry[[seam_id]]

  section_count <- length(seam$manifest_sections)
  file_count <- 0L

  for (section in seam$manifest_sections) {
    file_count <- file_count + length(sections[[section]])
  }

  file_count <- file_count + length(seam$extra_runtime_files)
  seam_zones <- gov_env$ui_asset_zones_for_seam(seam_id, zones)

  cat(sprintf(
    "  %-24s bölüm=%-2d runtime-dosya=%-3d frontend-bölge=%-2d guard-test=%d\n",
    seam_id,
    section_count,
    file_count,
    length(seam_zones),
    length(seam$guard_tests)
  ))

  seam_lines <- c(seam_lines, paste0(
    "    {",
    sprintf("\"id\":\"%s\",", json_escape(seam_id)),
    sprintf("\"title\":\"%s\",", json_escape(seam$title)),
    sprintf("\"manifest_sections\":%s,", json_string_array(seam$manifest_sections)),
    sprintf("\"runtime_file_count\":%d,", file_count),
    sprintf("\"frontend_zones\":%s,", json_string_array(seam_zones)),
    sprintf("\"guard_tests\":%s", json_string_array(seam$guard_tests)),
    "}"
  ))
}

cat("\n")

if (length(all_problems) == 0L) {
  cat("SEAM_DOCTOR_RESULT: OK (yapısal sorun yok)\n")
} else {
  cat(sprintf("SEAM_DOCTOR_RESULT: PROBLEM (%d sorun)\n", length(all_problems)))
  cat(paste0("  - ", all_problems, collapse = "\n"))
  cat("\n")
}

timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
artifact_path <- file.path(artifact_dir, sprintf("seam-doctor-%s.json", timestamp))

json_lines <- c(
  "{",
  sprintf("  \"generated_at_utc\": \"%s\",", json_escape(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))),
  "  \"doctor_script\": \"tests/scripts/seam_doctor.R\",",
  "  \"doctor_runs_heavy_checks\": false,",
  "  \"doctor_runs_runtime\": false,",
  "  \"doctor_runs_browser\": false,",
  "  \"doctor_runs_database\": false,",
  "  \"validation_execution_status\": \"not_run_by_seam_doctor\",",
  "  \"secret_policy\": \"value=<not-collected>; ham ortam değeri yazılmaz\",",
  sprintf("  \"seam_count\": %d,", length(registry)),
  sprintf("  \"manifest_section_count\": %d,", length(sections)),
  sprintf("  \"frontend_zone_count\": %d,", length(zones)),
  sprintf("  \"unmanifested_owned_count\": %d,", length(unmanifested)),
  sprintf("  \"problem_count\": %d,", length(all_problems)),
  sprintf("  \"problems\": %s,", json_string_array(all_problems)),
  sprintf("  \"frontend_ownership_gaps\": %s,", json_string_array(ownership_gaps)),
  sprintf("  \"orphan_r_files\": %s,", json_string_array(orphan_r_files)),
  "  \"seams\": [",
  paste(seam_lines, collapse = ",\n"),
  "  ],",
  "  \"doctor_execution_notes\": \"Bu artifact yapısal seam/bölge doğrulamasıdır; testthat, app boot, tarayıcı smoke, VM/SSO/DB veya encoding preflight kanıtı DEĞİLDİR.\"",
  "}"
)

writeLines(enc2utf8(json_lines), artifact_path, useBytes = TRUE)

cat(sprintf("\nArtifact: %s\n", artifact_path))

# quit() kullanılmaz: betik source(...) ile de güvenle çalıştırılabilmelidir.
# stop() Rscript altında sıfır-dışı çıkış kodu üretir, oturumu öldürmez.
if (length(all_problems) > 0L) {
  stop(
    sprintf("Seam doctor %d yapısal sorun buldu; ayrıntılar: %s", length(all_problems), artifact_path),
    call. = FALSE
  )
}

invisible(TRUE)
