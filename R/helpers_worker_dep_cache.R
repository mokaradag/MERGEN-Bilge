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

# Önbellekteki her adın varlık/tür imzası. Kaybolan, işleve dönüşen ya da
# sınıfı/paketi değişen bağımlılık yeniden tarama gerektirir: paket kümesi
# değerin sınıfına bağlı olabilir ve yeni işlevin yardımcıları genişletilmelidir.
.worker_monitor_dep_cache_signature <- function(adlar, ortam, miras) {
  vapply(as.character(adlar), function(nm) {
    if (!nzchar(nm) || !exists(nm, envir = ortam, inherits = miras)) return("<yok>")
    deger <- get(nm, envir = ortam, inherits = miras)
    if (is.function(deger)) return("<fn>")
    paste(c(class(deger), attr(class(deger), "package")), collapse = "/")
  }, character(1), USE.NAMES = FALSE)
}

# Paket/base üzerinden çözüldüğü için taranmayan doğrudan ad, sonradan görev
# ortamında ya da .GlobalEnv'de aynı adla tanımlanırsa (ör. global `filter`)
# R'nin sözcüksel araması değişir; kayıt kullanılmaz ve yeniden taranır.
.worker_monitor_dep_cache_shadowed <- function(nm, ortam) {
  arama <- parent.env(globalenv())
  e <- ortam
  while (!identical(e, arama) && !identical(e, emptyenv())) {
    if (exists(nm, envir = e, inherits = FALSE)) return(TRUE)
    e <- parent.env(e)
  }
  FALSE
}

# Çağıranın verdiği globals da anahtara girer: adları genişletmeyi (seen kümesi),
# işlevleri ise hangi yardımcıların taşınacağını belirler.
.worker_monitor_dep_cache_given <- function(promise_globals) {
  promise_globals <- promise_globals %||% list()
  adlar <- sort(as.character(names(promise_globals)))
  list(names = adlar,
       fns = Filter(is.function, promise_globals[adlar]))
}

worker_monitor_dep_cache_get <- function(task_type, task_fn, promise_globals = list()) {
  govde <- .worker_monitor_dep_cache_body(task_fn)
  fn_env <- environment(task_fn)
  if (!is.environment(fn_env)) fn_env <- globalenv()
  verilen <- .worker_monitor_dep_cache_given(promise_globals)
  for (kayit in .WORKER_MONITOR_DEP_CACHE[[as.character(task_type)[1]]]) {
    if (identical(kayit$body, govde) &&
        identical(kayit$given, verilen) &&
        .worker_monitor_dep_cache_refs_same(kayit$fn_detected, fn_env, TRUE) &&
        .worker_monitor_dep_cache_refs_same(kayit$fn_expanded, .GlobalEnv, FALSE) &&
        identical(kayit$sig_detected, .worker_monitor_dep_cache_signature(kayit$detected, fn_env, TRUE)) &&
        identical(kayit$sig_expanded, .worker_monitor_dep_cache_signature(kayit$expanded, .GlobalEnv, FALSE)) &&
        !any(vapply(kayit$shadow, .worker_monitor_dep_cache_shadowed, logical(1), ortam = fn_env))) {
      return(kayit)
    }
  }
  NULL
}

worker_monitor_dep_cache_put <- function(task_type, task_fn, detected_globals,
                                         expanded_names, packages, promise_globals = list()) {
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
  aramada <- vapply(dogrudan, exists, logical(1), envir = arama, inherits = TRUE)
  golge <- setdiff(dogrudan[aramada], detected_names)
  golge <- golge[!vapply(golge, .worker_monitor_dep_cache_shadowed, logical(1), ortam = fn_env)]
  dogrudan <- dogrudan[!aramada]
  tespit <- unique(c(as.character(detected_names), dogrudan))
  kayit <- list(body = .worker_monitor_dep_cache_body(task_fn),
                given = .worker_monitor_dep_cache_given(promise_globals),
                detected = tespit,
                sabit = detected_globals[sabit_adlar],
                expanded = as.character(expanded_names),
                packages = as.character(packages),
                fn_detected = .worker_monitor_dep_cache_fn_refs(detected_names, fn_env, TRUE),
                fn_expanded = .worker_monitor_dep_cache_fn_refs(expanded_names, .GlobalEnv, FALSE),
                sig_detected = .worker_monitor_dep_cache_signature(tespit, fn_env, TRUE),
                sig_expanded = .worker_monitor_dep_cache_signature(expanded_names, .GlobalEnv, FALSE),
                shadow = as.character(golge))
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
