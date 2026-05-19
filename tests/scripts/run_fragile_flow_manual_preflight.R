# ==============================================================================
# Dosya Yolu: tests/scripts/run_fragile_flow_manual_preflight.R
# Açıklama: Yerel ve Windows VM/SSO kırılgan kullanıcı akışları için
#           etkileşimli manuel preflight kayıt betiği.
#           Tarayıcı otomasyon bağımlılığı eklemez.
# ==============================================================================

normalize_manual_answer <- function(value) {
  value <- toupper(trimws(as.character(value %||% "")))
  if (value %in% c("P", "PASS", "OK", "GEÇTİ", "GECTI")) return("PASS")
  if (value %in% c("F", "FAIL", "FAILED", "KALDI")) return("FAIL")
  if (value %in% c("S", "SKIP", "ATLA")) return("SKIP")
  "UNKNOWN"
}

ask_manual_step <- function(mode, step_id, instruction) {
  cat("\n", strrep("-", 78), "\n", sep = "")
  cat(sprintf("[%s] %s\n%s\n", mode, step_id, instruction))
  cat("Sonuç girin: PASS / FAIL / SKIP: ")

  answer <- if (interactive()) readline() else "SKIP"
  status <- normalize_manual_answer(answer)

  note <- ""
  if (interactive()) {
    cat("Kısa not/kanıt girin (opsiyonel): ")
    note <- readline()
  }

  data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"),
    mode = mode,
    step_id = step_id,
    status = status,
    note = enc2utf8(note),
    instruction = enc2utf8(instruction),
    stringsAsFactors = FALSE
  )
}

local_steps <- list(
  L01 = "Start app with SSO_ENABLED=FALSE.",
  L02 = "Open Ana Söyleşi.",
  L03 = "Send a normal streaming message.",
  L04 = paste(
    "Press stop during streaming and confirm:",
    "send button returns to normal;",
    "typing/thinking wrapper disappears or resolves cleanly;",
    "no duplicate assistant message appears."
  ),
  L05 = "Upload PDF, DOCX, TXT, CSV, XLSX.",
  L06 = "Refresh browser and verify files remain visible once.",
  L07 = "Fully restart app and verify files remain visible once.",
  L08 = "Load a saved chat and confirm TTS does not auto-play old AI messages.",
  L09 = "Open /smoke/ux-smoke.html against the running app and confirm UX_SMOKE_DONE:PASS."
)

vm_sso_steps <- list(
  V01 = "Start app with SSO_ENABLED=TRUE.",
  V02 = "Confirm authenticated user identity is correct.",
  V03 = "Confirm Ana Söyleşi recent chats show user-specific rows.",
  V04 = paste(
    "Confirm Söyleşi Geçmişi, Kayıtlı Söyleşiler,",
    "Görsel Galerisi show user-specific rows."
  ),
  V05 = "Upload Turkish filename: Türkçe_çalışma_özeti_İstanbul.pdf",
  V06 = "Refresh browser and verify Turkish display name remains readable.",
  V07 = "Restart app and verify Turkish display name remains readable once.",
  V08 = paste(
    "Toggle background music, open STT modal, cancel STT, then play TTS.",
    "Confirm only one music track plays and ducking recovers after TTS/STT."
  ),
  V09 = paste(
    "Run tests/scripts/run_vm_preflight_real.R with",
    "MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE and confirm it completes."
  ),
  V10 = "Open /smoke/ux-smoke.html on the VM app URL and confirm UX_SMOKE_DONE:PASS."
)

cat("\nMERGEN fragile-flow manual preflight\n")
cat("Bu betik uygulamayı başlatmaz; gözlemlerinizi UTF-8 CSV olarak kaydeder.\n")
cat("Ağır browser automation bağımlılığı eklenmez.\n")

results <- list()

for (id in names(local_steps)) {
  results[[length(results) + 1L]] <- ask_manual_step(
    "LOCAL",
    id,
    local_steps[[id]]
  )
}

for (id in names(vm_sso_steps)) {
  results[[length(results) + 1L]] <- ask_manual_step(
    "WINDOWS_VM_SSO",
    id,
    vm_sso_steps[[id]]
  )
}

result_df <- do.call(rbind, results)

log_dir <- Sys.getenv("MERGEN_LOG_DIR", "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

out_file <- file.path(
  log_dir,
  sprintf(
    "fragile_flow_manual_preflight_%s.csv",
    format(Sys.time(), "%Y%m%d_%H%M%S")
  )
)

utils::write.csv(
  result_df,
  out_file,
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

cat(sprintf("\nManual preflight sonucu yazıldı: %s\n", out_file))

failed <- result_df[result_df$status == "FAIL", , drop = FALSE]
unknown <- result_df[result_df$status == "UNKNOWN", , drop = FALSE]

if (nrow(failed) > 0L || nrow(unknown) > 0L) {
  stop(sprintf(
    "Manual preflight başarısız veya belirsiz: FAIL=%d UNKNOWN=%d. CSV: %s",
    nrow(failed),
    nrow(unknown),
    out_file
  ), call. = FALSE)
}

cat("OK: Manual fragile-flow preflight PASS/SKIP dışında sorun bildirmedi.\n")