# ==============================================================================
# Proje/Kaynak Analizi çekirdeği yükleyicisi.
# ==============================================================================

# Bare göreli source("R/...") çağrıları YALNIZCA getwd() == repo kökü iken
# çalışır. testthat `source_file()` her test dosyasını `chdir = TRUE` ile
# kaynaklar ve bu, test gövdesi çalışırken cwd'yi `tests/testthat`'e taşır;
# bu yüzden kardeş dosyalar çalışma dizininden BAĞIMSIZ bulunur (bkz.
# helpers_pk_analysis_filters.R'deki aynı desen).
.pk_core_resolve_sibling <- function(filename) {
  # 1) Bu dosyayı source eden çerçevedeki ofile üzerinden kardeş dosyayı bul.
  #    testthat yığınında source çerçevesi sys.frame(1) DEĞİLDİR; bu yüzden
  #    tüm çerçeveler içten dışa taranır.
  sibling <- NULL
  for (i in rev(seq_len(sys.nframe()))) {
    of <- tryCatch(
      get("ofile", envir = sys.frame(i), inherits = FALSE),
      error = function(e) NULL
    )
    if (is.character(of) && length(of) == 1L && !is.na(of) && nzchar(of)) {
      cand <- file.path(
        dirname(normalizePath(of, winslash = "/", mustWork = FALSE)),
        filename
      )
      if (isTRUE(tryCatch(file.exists(cand), error = function(e) FALSE))) {
        sibling <- cand
        break
      }
    }
  }

  # 2) Çalışma dizininden bağımsız aday yollar: repo kökü, tests/testthat,
  #    MERGEN_REPO_ROOT.
  candidates <- c(
    sibling,
    file.path("R", filename),
    file.path("..", "..", "R", filename),
    file.path("..", "R", filename),
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", filename)
    } else {
      NULL
    }
  )

  for (cand in candidates) {
    if (!is.null(cand) && nzchar(cand) &&
        isTRUE(tryCatch(file.exists(cand), error = function(e) FALSE))) {
      return(cand)
    }
  }

  stop(sprintf("%s bulunamadı.", filename), call. = FALSE)
}

# ÜRETİMDE MANİFEST YÜKLER.
#
# `R/helpers_pk_analysis_core_impl.R` ve `R/helpers_pk_p1_runtime_guards.R`
# artık `R/config_source_manifest.R` içinde AÇIKÇA sıralanmıştır (impl bu
# dosyadan ÖNCE, guard'lar SONRA). Manifest dışı dinamik `source()` bağımlılık
# sırasını atlatıyor ve staged/asenkron dağıtımlarda yanlış ya da eksik yol
# çözebiliyordu. Aşağıdaki guard YALNIZCA izole test/hata ayıklama
# yüklemeleri içindir; manifest yolunda hiçbir zaman tetiklenmez.
if (!exists("summarize_columns_for_ai", mode = "function", inherits = TRUE)) {
  source(
    .pk_core_resolve_sibling("helpers_pk_analysis_core_impl.R"),
    encoding = "UTF-8", local = environment()
  )
}

rm(.pk_core_resolve_sibling)
