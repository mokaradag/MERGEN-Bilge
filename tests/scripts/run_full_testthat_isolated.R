# ==============================================================================
# Dosya Yolu: tests/scripts/run_full_testthat_isolated.R
# Aciklama:
#   Tam testthat suitini dosya dosya temiz Rscript cocuk sureclerinde kosar.
#   Native Rscript.exe crash durumunda hangi test dosyasinin crash urettigini
#   kanit loglarinda gorunur hale getirir.
#
#   NOT: Bu operasyonel betik ASCII-guvenli tutulur.
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "tests", "testthat"))) {
  stop("run_full_testthat_isolated.R repo kokunden calistirilmalidir.", call. = FALSE)
}

artifact_dir <- Sys.getenv(
  "MERGEN_EVIDENCE_ARTIFACT_DIR",
  unset = file.path("artifacts", "vm-evidence", "manual-full-testthat-isolated")
)

# Bilerek normalizePath() kullanma: VM repo yolu UNC + non-ASCII karakterler
# tasiyabilir. Cocuk Rscript runner'lari repo kokunden calistigi icin goreli
# artifact yolu yeterlidir ve daha guvenlidir.
artifact_dir <- gsub("\\", "/", artifact_dir, fixed = TRUE)
file_log_dir <- file.path(artifact_dir, "step_full_testthat_files")
dir.create(file_log_dir, recursive = TRUE, showWarnings = FALSE)

rscript_bin <- file.path(R.home("bin"), "Rscript")
if (.Platform$OS.type == "windows") {
  rscript_bin <- paste0(rscript_bin, ".exe")
}

if (!file.exists(rscript_bin)) {
  stop(sprintf("Rscript bulunamadi: %s", rscript_bin), call. = FALSE)
}

path_for_r <- function(path) {
  gsub("\\", "/", path, fixed = TRUE)
}

r_string <- function(path) {
  encodeString(path_for_r(path), quote = "'")
}

test_files <- list.files(
  file.path("tests", "testthat"),
  pattern = "^test-.*\\.R$",
  full.names = TRUE
)

test_files <- sort(test_files)
all_test_files <- test_files

if (length(all_test_files) == 0) {
  stop("tests/testthat altinda test-*.R dosyasi bulunamadi.", call. = FALSE)
}

parse_testthat_index <- function(env_name, default, upper_bound) {
  raw <- trimws(Sys.getenv(env_name, unset = ""))

  if (!nzchar(raw)) {
    return(default)
  }

  value <- suppressWarnings(as.integer(raw))

  if (is.na(value) || value < 1L || value > upper_bound) {
    stop(sprintf(
      "%s gecersiz: %s. 1-%d arasi tamsayi kullanin.",
      env_name,
      raw,
      upper_bound
    ), call. = FALSE)
  }

  value
}

range_start <- parse_testthat_index(
  "MERGEN_TESTTHAT_START_INDEX",
  1L,
  length(all_test_files)
)

range_end <- parse_testthat_index(
  "MERGEN_TESTTHAT_END_INDEX",
  length(all_test_files),
  length(all_test_files)
)

if (range_start > range_end) {
  stop(sprintf(
    "MERGEN_TESTTHAT_START_INDEX (%d) MERGEN_TESTTHAT_END_INDEX (%d) degerinden buyuk olamaz.",
    range_start,
    range_end
  ), call. = FALSE)
}

selected_indices <- seq.int(range_start, range_end)
test_files <- all_test_files[selected_indices]

running_marker <- file.path(file_log_dir, "RUNNING_TEST_FILE.txt")
summary_file <- file.path(file_log_dir, "SUMMARY.tsv")

writeLines(
  "index\ttotal\tstatus\ttest_file\texit_status\tduration_sec\tlog_file",
  summary_file,
  useBytes = TRUE
)

cat(sprintf("FULL_TESTTHAT_ISOLATED_TOTAL:%d\n", length(all_test_files)))
cat(sprintf("FULL_TESTTHAT_ISOLATED_RANGE:%d:%d\n", range_start, range_end))
cat(sprintf("FULL_TESTTHAT_ISOLATED_SELECTED:%d\n", length(test_files)))

failed <- list()

for (i in seq_along(test_files)) {
  original_index <- selected_indices[[i]]
  test_file <- test_files[[i]]
  test_name <- basename(test_file)
  safe_name <- gsub("[^A-Za-z0-9_.-]+", "_", test_name)
  log_file <- file.path(file_log_dir, sprintf("%03d_%s.log", original_index, safe_name))
  runner_file <- file.path(file_log_dir, sprintf("%03d_%s_runner.R", original_index, safe_name))

writeLines(
  c(
    sprintf("index=%d", original_index),
    sprintf("total=%d", length(all_test_files)),
    sprintf("selected_index=%d", i),
    sprintf("selected_total=%d", length(test_files)),
    sprintf("test_file=%s", path_for_r(test_file)),
    sprintf("started_at=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  ),
  running_marker,
  useBytes = TRUE
)

  runner_lines <- c(
    "for (.loc in c('C.UTF-8', 'en_US.UTF-8', 'tr_TR.UTF-8')) {",
    "  ok <- tryCatch(nzchar(Sys.setlocale('LC_CTYPE', .loc)), error = function(e) FALSE, warning = function(w) FALSE)",
    "  if (isTRUE(ok)) break",
    "}",
    "Sys.setenv(",
    "  MERGEN_RUN_APP = 'false',",
    "  MERGEN_DISABLE_FUTURES = 'true',",
    "  TZ = 'UTC'",
    ")",
    "options(warn = 1)",
    "library(testthat)",
    "testthat::local_edition(3)",
	sprintf(
	  "res <- testthat::test_file(%s, reporter = 'summary', stop_on_failure = TRUE, stop_on_warning = TRUE)",
	  r_string(test_file)
	),
    "invisible(res)"
  )

  writeLines(runner_lines, runner_file, useBytes = TRUE)

  cat(sprintf(
    "[FULL_TESTTHAT_FILE %03d/%03d selected %03d/%03d] %s ...",
    original_index,
    length(all_test_files),
    i,
    length(test_files),
    test_name
  ))
  started <- Sys.time()

	child_env <- c(
	  MERGEN_RUN_APP = "false",
	  MERGEN_DISABLE_FUTURES = "true",
	  TZ = "UTC",
	  MERGEN_EVIDENCE_ARTIFACT_DIR = artifact_dir,
	  MERGEN_REQUIRE_BROWSER_UX_SMOKE = "false",
	  MERGEN_BROWSER_UX_BASE_URL = ""
	)

old_env <- Sys.getenv(names(child_env), unset = NA_character_)

do.call(
  Sys.setenv,
  stats::setNames(as.list(unname(child_env)), names(child_env))
)

status <- tryCatch(
  suppressWarnings(system2(
    rscript_bin,
    args = c("--vanilla", runner_file),
    stdout = log_file,
    stderr = log_file
  )),
  finally = {
    for (nm in names(child_env)) {
      old_value <- old_env[[nm]]
      if (is.na(old_value)) {
        Sys.unsetenv(nm)
      } else {
        do.call(Sys.setenv, stats::setNames(list(old_value), nm))
      }
    }
  }
)

  duration <- round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  exit_status <- as.integer(status %||% 1L)

  status_label <- if (identical(exit_status, 0L)) "passed" else "failed"

  write(
    sprintf(
      "%d\t%d\t%s\t%s\t%d\t%.1f\t%s",
	  original_index,
	  length(all_test_files),
	  status_label,
	  path_for_r(test_file),
	  exit_status,
	  duration,
	  path_for_r(log_file)
    ),
    file = summary_file,
    append = TRUE
  )

  cat(sprintf(" %s (exit=%d, %.1f sn)\n", toupper(status_label), exit_status, duration))

  unlink(runner_file, force = TRUE)

  if (!identical(exit_status, 0L)) {
    failed[[length(failed) + 1L]] <- list(
      file = path_for_r(test_file),
      log_file = path_for_r(log_file),
      exit_status = exit_status
    )

    stop(sprintf(
      paste(
        "full_testthat dosya izolasyonunda basarisiz oldu.",
        "Fail/crash dosyasi: %s",
        "Exit: %d",
        "Log: %s",
        sep = "\n"
      ),
      path_for_r(test_file),
      exit_status,
      path_for_r(log_file)
    ), call. = FALSE)
  }
}

unlink(running_marker, force = TRUE)

cat("FULL_TESTTHAT_ISOLATED_DONE:PASS\n")
invisible(TRUE)