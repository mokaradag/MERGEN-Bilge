# ==============================================================================
# Dosya Yolu: R/helpers_worker_dep_cache.R
# Açıklama: tracked_future_promise() otomatik kipinin bağımlılık önbelleği
#           (R/helpers_worker_monitor.R ile aynı temel katmanda yüklenir).
# ==============================================================================

# Otomatik modun bağımlılık ADLARI görev gövdesi başına bir kez taranır;
# DEĞERLER her çağrıda taze okunur. Tarama büyük .GlobalEnv'de saniyeler
# sürüyor ve her sohbet/dosya özeti gönderiminde TÜM kullanıcılar için olay
# döngüsünü blokluyordu.
.WORKER_MONITOR_DEP_CACHE <- new.env(parent = emptyenv())

.worker_monitor_dep_cache_body <- function(task_fn) {
  paste(c(deparse(formals(task_fn), width.cutoff = 500L),
          deparse(body(task_fn), width.cutoff = 500L)), collapse = "\n")
}

# Gövde aynı olsa da bağlı yardımcı fonksiyonlar değişmiş olabilir (farklı
# kapanış ya da yeniden yüklenen global); o durumda kayıt kullanılmaz ve yeniden
# taranır. Aynı nesne için identical() işaretçi karşılaştırmasıdır, ucuzdur.
.worker_monitor_dep_cache_fn_refs <- function(adlar, ortam, miras) {
  refs <- list()
  for (nm in adlar) {
    if (!nzchar(nm)) next
    deger <- get0(nm, envir = ortam, inherits = miras, ifnotfound = NULL)
    if (is.function(deger)) refs[nm] <- list(deger)
  }
  refs
}

.worker_monitor_dep_cache_refs_same <- function(refs, ortam, miras) {
  for (nm in names(refs)) {
    if (!identical(get0(nm, envir = ortam, inherits = miras, ifnotfound = NULL), refs[[nm]])) {
      return(FALSE)
    }
  }
  TRUE
}

worker_monitor_dep_cache_get <- function(task_type, task_fn) {
  govde <- .worker_monitor_dep_cache_body(task_fn)
  fn_env <- environment(task_fn)
  if (!is.environment(fn_env)) fn_env <- globalenv()
  for (kayit in .WORKER_MONITOR_DEP_CACHE[[as.character(task_type)[1]]]) {
    if (identical(kayit$body, govde) &&
        .worker_monitor_dep_cache_refs_same(kayit$fn_detected, fn_env, TRUE) &&
        .worker_monitor_dep_cache_refs_same(kayit$fn_expanded, .GlobalEnv, FALSE)) {
      return(kayit)
    }
  }
  NULL
}

worker_monitor_dep_cache_put <- function(task_type, task_fn, detected_globals,
                                         expanded_names, packages) {
  anahtar <- as.character(task_type)[1]
  detected_names <- names(detected_globals)
  fn_env <- environment(task_fn)
  if (!is.environment(fn_env)) fn_env <- globalenv()
  # Yalnızca bir kapanışın iç ortamında bulunan adlar (ör. fabrika sabitleri)
  # görev ortamından çözülemez; ilk taramadaki değerleri korunur.
  sabit_adlar <- detected_names[!vapply(detected_names, exists, logical(1),
                                        envir = fn_env, inherits = TRUE)]
  # İlk taramada o an TANIMSIZ olan doğrudan serbest değişkenler de eklenir;
  # sonraki çağrıda tanımlıysa değeri yine taşınır (paket/base adları hariç).
  dogrudan <- tryCatch(codetools::findGlobals(task_fn, merge = TRUE),
                       error = function(e) character(0))
  arama <- parent.env(globalenv())
  dogrudan <- dogrudan[!vapply(dogrudan, exists, logical(1), envir = arama, inherits = TRUE)]
  kayit <- list(body = .worker_monitor_dep_cache_body(task_fn),
                detected = unique(c(as.character(detected_names), dogrudan)),
                sabit = detected_globals[sabit_adlar],
                expanded = as.character(expanded_names),
                packages = as.character(packages),
                fn_detected = .worker_monitor_dep_cache_fn_refs(detected_names, fn_env, TRUE),
                fn_expanded = .worker_monitor_dep_cache_fn_refs(expanded_names, .GlobalEnv, FALSE))
  mevcut <- .WORKER_MONITOR_DEP_CACHE[[anahtar]] %||% list()
  .WORKER_MONITOR_DEP_CACHE[[anahtar]] <- utils::tail(c(mevcut, list(kayit)), 8L)
  invisible(kayit)
}

worker_monitor_dep_cache_clear <- function() {
  rm(list = ls(envir = .WORKER_MONITOR_DEP_CACHE, all.names = TRUE), envir = .WORKER_MONITOR_DEP_CACHE)
  invisible(TRUE)
}

# Önbellekteki adların GÜNCEL değerleri: tespit edilenler görev ortamından
# (kapanış değişkenleri dahil), genişletilenler .GlobalEnv'den okunur.
worker_monitor_dep_cache_values <- function(entry, task_fn) {
  fn_env <- environment(task_fn)
  if (!is.environment(fn_env)) fn_env <- globalenv()
  topla <- function(adlar, ortam, miras) {
    sonuc <- list()
    for (nm in adlar) {
      if (nzchar(nm) && exists(nm, envir = ortam, inherits = miras)) {
        sonuc[nm] <- list(get(nm, envir = ortam, inherits = miras))
      }
    }
    sonuc
  }
  tespit <- topla(entry$detected, fn_env, TRUE)
  for (nm in setdiff(names(entry$sabit), names(tespit))) tespit[nm] <- list(entry$sabit[[nm]])
  list(detected = tespit,
       expanded = topla(entry$expanded, .GlobalEnv, FALSE))
}
