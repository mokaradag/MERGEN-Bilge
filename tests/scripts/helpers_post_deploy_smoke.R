# ==============================================================================
# Dosya Yolu: tests/scripts/helpers_post_deploy_smoke.R
# Açıklama: Dağıtım sonrası duman testi için SAF değerlendirme yardımcısı.
#           Çalışan uygulamadan toplanan sağlık kontrol sonuçlarından genel
#           dağıtım durumunu (pass/degraded/fail) hesaplar. Shiny, DB, HTTP veya
#           dosya erişimi içermez; bu sayede izole test edilebilir ve kendisi
#           hizmet çağrısı yapmaz.
# ==============================================================================

# Sağlık durum sözlüğü health_severity_rank ile hizalıdır:
# ok < not_configured < unknown < warning < critical
# Bu yerel fallback yalnızca health_normalize_status mevcut değilken kullanılır.
.post_deploy_smoke_status_fallback <- function(status) {
  if (is.null(status) || length(status) == 0L) {
    return("unknown")
  }

  status <- tolower(trimws(as.character(status[1])))
  if (is.na(status) || !nzchar(status)) {
    return("unknown")
  }

  aliases <- c(
    pass = "ok", healthy = "ok", up = "ok", success = "ok", green = "ok",
    warn = "warning", degraded = "warning", yellow = "warning",
    fail = "critical", error = "critical", down = "critical",
    fail_critical = "critical", red = "critical",
    skipped = "not_configured"
  )

  if (status %in% names(aliases)) {
    return(unname(aliases[status]))
  }

  known <- c("ok", "not_configured", "unknown", "warning", "critical")
  if (status %in% known) status else "unknown"
}

# Toplanan sağlık kontrol sonuçlarından dağıtım sonrası genel durumu hesaplar.
#
# Argümanlar:
#   checks          : sağlık kontrol kayıtları listesi (her biri en az id/status taşır).
#   critical_ids    : bozulduğunda dağıtımı bloklayan kritik kontrol kimlikleri.
#   fail_statuses   : tek başına başarısızlık sayılan durumlar.
#   degrade_statuses: pass yerine "degraded" sayılan durumlar.
#   fail_on_unknown : TRUE ise kritik kontrolün "unknown" durumu da bloklar.
#   normalize_fn    : durum normalleştirici; verilmezse health_normalize_status
#                     ya da yerel fallback kullanılır.
#
# Döner: overall, should_fail, reason, total, counts, failing, critical_failures.
mergen_post_deploy_smoke_evaluate <- function(checks,
                                              critical_ids = c("app.boot", "db.primary", "storage.disk_free"),
                                              fail_statuses = c("critical"),
                                              degrade_statuses = c("warning", "unknown"),
                                              fail_on_unknown = FALSE,
                                              normalize_fn = NULL) {

  if (is.null(normalize_fn)) {
    if (exists("health_normalize_status", mode = "function")) {
      normalize_fn <- get("health_normalize_status", mode = "function")
    } else {
      normalize_fn <- .post_deploy_smoke_status_fallback
    }
  }

  critical_ids <- as.character(critical_ids)
  fail_statuses <- as.character(fail_statuses)
  degrade_statuses <- as.character(degrade_statuses)

  evaluated_at <- tryCatch(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    error = function(e) ""
  )

  # Boş/eksik kontrol seti şüphelidir: sağlığı doğrulayamadık -> fail.
  if (is.null(checks) || length(checks) == 0L) {
    return(list(
      overall = "unknown",
      should_fail = TRUE,
      reason = "no_checks",
      total = 0L,
      counts = integer(0),
      failing = character(0),
      critical_failures = character(0),
      evaluated_at = evaluated_at
    ))
  }

  ids <- character(0)
  statuses <- character(0)

  for (chk in checks) {
    id_val <- ""
    status_val <- "unknown"

    if (is.list(chk)) {
      if (!is.null(chk$id)) id_val <- as.character(chk$id)[1]
      if (!is.null(chk$status)) status_val <- as.character(chk$status)[1]
    }

    if (is.na(id_val)) id_val <- ""

    norm <- tryCatch(
      as.character(normalize_fn(status_val))[1],
      error = function(e) "unknown"
    )
    if (is.na(norm) || !nzchar(norm)) norm <- "unknown"

    ids <- c(ids, id_val)
    statuses <- c(statuses, norm)
  }

  counts <- table(statuses)

  # 1) Herhangi bir kontrol fail_statuses içindeyse bloklar.
  failing_idx <- which(statuses %in% fail_statuses)
  failing <- unique(ids[failing_idx])
  failing <- failing[nzchar(failing)]

  # 2) Bir KRİTİK kontrol bozuksa bloklar (warning dahil; unknown opsiyonel).
  critical_block_statuses <- unique(c(fail_statuses, "warning"))
  if (isTRUE(fail_on_unknown)) {
    critical_block_statuses <- unique(c(critical_block_statuses, "unknown"))
  }
  crit_idx <- which(ids %in% critical_ids & statuses %in% critical_block_statuses)
  critical_failures <- unique(ids[crit_idx])
  critical_failures <- critical_failures[nzchar(critical_failures)]

  should_fail <- (length(failing_idx) > 0L) || (length(crit_idx) > 0L)

  overall <- "pass"
  if (isTRUE(should_fail)) {
    overall <- "fail"
  } else if (any(statuses %in% degrade_statuses)) {
    overall <- "degraded"
  }

  list(
    overall = overall,
    should_fail = isTRUE(should_fail),
    reason = if (isTRUE(should_fail)) "critical_or_failing_check" else "ok",
    total = length(statuses),
    counts = counts,
    failing = failing,
    critical_failures = critical_failures,
    evaluated_at = evaluated_at
  )
}
