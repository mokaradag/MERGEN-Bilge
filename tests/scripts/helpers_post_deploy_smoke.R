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

# Değerlendirici sonucundan (mergen_post_deploy_smoke_evaluate çıktısı) makinece
# okunabilir, SECRET-SAFE bir kanıt kaydı üretir. SAF fonksiyondur: Shiny/DB/HTTP/
# dosya/sistem çağrısı yapmaz, böylece izole test edilebilir. Yazma işini (artifact
# dosyası) çağıran kapı betiği üstlenir; bu fonksiyon yalnızca kaydın içeriğini
# kurar. Dürüstlük alanları (does_prove/does_not_prove) ve kanıt sınırı notu zorunlu.
#
# Argümanlar:
#   result           : mergen_post_deploy_smoke_evaluate() çıktısı (liste).
#   critical_ids     : kapıda kullanılan kritik kontrol kimlikleri (kayda işlenir).
#   fail_on_unknown  : kritik unknown'ın bloklayıp bloklamadığı (kayda işlenir).
#   generated_at_utc : NULL ise UTC ISO zaman damgası üretilir (test için enjekte
#                      edilebilir → deterministik).
#   git_info         : list(branch=, sha=, dirty=); NULL ise boş. Git çağrısı SAF
#                      fonksiyonun dışındadır; çağıran toplar (en iyi çaba).
#   r_version        : NULL ise R.version'dan türetilir.
#
# Döner: gate/zaman/durum/sayaç + does_prove/does_not_prove + proof_boundary_notes
#        içeren isimli liste. Yalnızca kontrol kimlikleri ve sayaçlar tutulur;
#        ham log/ortam/secret değeri ASLA taşınmaz.
mergen_post_deploy_smoke_artifact_record <- function(result,
                                                     critical_ids = c("app.boot", "db.primary", "storage.disk_free"),
                                                     fail_on_unknown = FALSE,
                                                     generated_at_utc = NULL,
                                                     git_info = NULL,
                                                     r_version = NULL) {

  if (!is.list(result)) {
    result <- list()
  }

  # Standalone source edilebilirlik için (%||% kullanılmaz): küçük yerel yardımcılar.
  .first_or <- function(x, default) {
    if (is.null(x) || length(x) < 1L) return(default)
    v <- x[[1]]
    if (is.null(v) || (length(v) == 1L && is.na(v))) return(default)
    v
  }

  .as_char_vec <- function(x) {
    if (is.null(x) || !length(x)) return(character(0))
    out <- as.character(unlist(x, use.names = FALSE))
    out <- out[!is.na(out) & nzchar(out)]
    unique(out)
  }

  # counts (table veya isimli vektör) → deterministik, isimli tam-sayı listesi.
  ham_counts <- result$counts
  counts_list <- list()
  if (!is.null(ham_counts) && length(ham_counts) > 0L) {
    nm <- names(ham_counts)
    for (i in seq_along(ham_counts)) {
      ad <- if (is.null(nm)) as.character(i) else nm[i]
      if (is.null(ad) || is.na(ad) || !nzchar(ad)) next
      deger <- suppressWarnings(as.integer(ham_counts[[i]]))
      counts_list[[ad]] <- if (length(deger) == 1L && !is.na(deger)) deger else 0L
    }
  }

  generated_at_utc <- as.character(.first_or(generated_at_utc, ""))
  if (!nzchar(generated_at_utc)) {
    generated_at_utc <- tryCatch(
      format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      error = function(e) ""
    )
  }

  if (is.null(git_info) || !is.list(git_info)) {
    git_info <- list(branch = "", sha = "", dirty = FALSE)
  }

  r_version <- as.character(.first_or(r_version, ""))
  if (!nzchar(r_version)) {
    r_version <- tryCatch(
      paste(R.version$major, R.version$minor, sep = "."),
      error = function(e) ""
    )
  }

  list(
    gate = "run_post_deploy_smoke",
    generated_at_utc = generated_at_utc,
    validation_execution_status = "ran_by_post_deploy_smoke",
    overall = as.character(.first_or(result$overall, "unknown")),
    should_fail = isTRUE(result$should_fail),
    reason = as.character(.first_or(result$reason, "")),
    total = as.integer(.first_or(result$total, 0L)),
    counts = counts_list,
    failing = .as_char_vec(result$failing),
    critical_failures = .as_char_vec(result$critical_failures),
    critical_ids = .as_char_vec(critical_ids),
    fail_on_unknown = isTRUE(fail_on_unknown),
    evaluated_at = as.character(.first_or(result$evaluated_at, "")),
    git = list(
      branch = as.character(.first_or(git_info$branch, "")),
      sha = as.character(.first_or(git_info$sha, "")),
      dirty = isTRUE(git_info$dirty)
    ),
    r_version = r_version,
    secret_policy = paste(
      "Ham ortam/secret değeri yazılmaz; yalnızca sağlık kontrol kimlikleri,",
      "durum sayaçları ve genel sonuç metadata'sı tutulur."
    ),
    does_prove = paste(
      "Uygulama ortamı güvenli boot modunda (MERGEN_RUN_APP=false; Shiny servisi",
      "BAŞLATILMADAN, app.R source edilerek) yüklendikten sonra toplanan in-process",
      "sağlık kontrollerinin (boot, DB, depolama, yapılandırma, servis erişilebilirlik",
      "probe'ları) dağıtım anındaki anlık (snapshot) sonucunu kanıtlar."
    ),
    does_not_prove = paste(
      "Dağıtılan Shiny servisinin gerçekten ayakta olduğunu/istek karşıladığını",
      "KANITLAMAZ (app URL probe EDİLMEZ); ayrıca yük/eşzamanlılık dayanıklılığını,",
      "uzun süreli stabiliteyi, gerçek tarayıcı UX'ini veya VM/SSO/SQL Server Türkçe",
      "kodlama kanıtını kapsamaz; tek bir in-process anlık sağlık fotoğrafıdır."
    ),
    proof_boundary_notes = paste(
      "Bu artifact yalnızca 'pass' olduğunda anlık sağlık kanıtıdır;",
      "'degraded'/'fail' operatör incelemesi gerektirir ve yapılandırılmamış/",
      "SKIP edilen kontroller kanıt DEĞİLDİR."
    )
  )
}

# Kaydın yalnızca KARAKTER (string) DEĞERLERİNİ verilen redaktörden geçirir;
# liste ANAHTARLARI (örn. counts.ok), sayılar ve mantıksal değerler DOKUNULMAZ.
#
# Gerekçe: kayıt zaten secret-safe kurulur (yalnızca kontrol kimlikleri, durum
# sayaçları ve genel metadata; ham log/ortam/secret yok). Redaktör savunma
# derinliğidir. Önceki yaklaşım serileştirilmiş JSON metnini kör redakte ediyordu;
# bu, "ok" gibi bir secret değerinin `counts.ok` ANAHTARINI `<hidden>` ile ezip
# JSON yine de geçerli kalırken okuyucunun (release_evidence_post_deploy_smoke_summary)
# YANLIŞ "sıfır geçen kontrol" raporlamasına yol açabilirdi (yalnızca JSON
# söz dizimi doğrulamak yetmez). Bunun yerine redaksiyon SERİLEŞTİRMEDEN ÖNCE
# yalnızca yapısal string DEĞERLERE uygulanır; anahtarlar ve sayaçlar korunduğu
# için şema asla bozulmaz ve toJSON her zaman geçerli JSON üretir.
#
# Argümanlar:
#   record    : artifact kaydı (isimli / iç içe liste).
#   redact_fn : karakter vektörü alıp aynı uzunlukta karakter döndüren redaktör;
#               NULL ise kayıt değişmeden döner.
mergen_post_deploy_smoke_redact_record <- function(record, redact_fn = NULL) {
  if (is.null(redact_fn) || !is.function(redact_fn)) {
    return(record)
  }

  walk <- function(x) {
    if (is.character(x)) {
      out <- tryCatch(as.character(redact_fn(x)), error = function(e) x)
      # Redaktör beklenmedik uzunluk/şekil döndürürse orijinali koru.
      if (length(out) == length(x)) out else x
    } else if (is.list(x)) {
      # lapply liste anahtarlarını (isimleri) korur; yalnızca DEĞERLER ziyaret edilir.
      lapply(x, walk)
    } else {
      # Sayılar, mantıksal değerler, NULL vb. dokunulmaz.
      x
    }
  }

  redacted <- walk(record)

  # Şema-anlamlı enum/kimlik alanlarını redaksiyon SONRASI orijinalden geri yükle.
  # Bu alanlar tasarımca asla secret içermez (sabit/enum/git-metadata); ancak bir
  # secret DEĞERİ "pass"/"degraded" gibi kısa bir enum'a denk gelseydi yukarıdaki
  # walk `overall`/`reason`'ı ezip okuyucunun/sağlık panelinin GEÇEN veya DEGRADED
  # bir kapıyı nötr/unknown göstermesine yol açardı. Anahtar/sayaçlar zaten
  # korunur; bu adım durum enum'larını ve sabit kimlik alanlarını da korur.
  if (is.list(redacted)) {
    for (key in c("overall", "reason", "gate", "validation_execution_status")) {
      if (key %in% names(record)) {
        redacted[[key]] <- record[[key]]
      }
    }
  }

  redacted
}

# Erken-çıkış (boot/env) başarısızlıkları için minimum "fail" değerlendirici
# sonucu üretir. Kapı betiği; zorunlu env eksik olduğunda, app.R source
# edilemediğinde veya health_collect_checks bulunamadığında bunu kullanarak
# stop'tan ÖNCE bir BAŞARISIZLIK artifact'ı yazar. Böylece sağlık paneli koşumu
# "not_found" (hiç koşmamış gibi) değil, başarısız kapı olarak görür ve operatör
# dağıtımın gerçekten durdurulduğunu kaçırmaz.
mergen_post_deploy_smoke_failure_result <- function(reason) {
  if (is.null(reason) || length(reason) < 1L || is.na(reason[1])) {
    reason <- "unknown_failure"
  } else {
    reason <- as.character(reason)[1]
  }
  if (!nzchar(reason)) {
    reason <- "unknown_failure"
  }

  list(
    overall = "fail",
    should_fail = TRUE,
    reason = reason,
    total = 0L,
    counts = integer(0),
    failing = character(0),
    critical_failures = character(0),
    evaluated_at = tryCatch(
      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      error = function(e) ""
    )
  )
}
