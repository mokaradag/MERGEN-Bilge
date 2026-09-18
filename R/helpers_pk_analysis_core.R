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

  # 2) Çalışma dizininden bağımsız aday yollar.
  #
  # SIRALAMA ÖNEMLİDİR: `MERGEN_REPO_ROOT` ÇALIŞMA DİZİNİNE GÖRELİ adaylardan
  # ÖNCE denenir. `R/`, `../R/` ve `../../R/` adayları süreç çalışma dizinine
  # görelidir; süreç repo kökünde DEĞİLKEN ve hiçbir çerçeve `ofile` taşımazken
  # `file.path("R", filename)` BAŞKA bir ağaçtaki aynı adlı dosyayı eşleyebilir
  # ve bu yükleyici o dosyanın tanımlarını kurardı. Açıkça beyan edilmiş repo
  # kökü, tahmine dayalı göreli adaylardan her zaman daha güvenilirdir; göreli
  # adaylar yalnızca izole test/hata ayıklama yedeği olarak KORUNUR (üretim
  # yüklemesi manifeste aittir).
  candidates <- c(
    sibling,
    if (nzchar(Sys.getenv("MERGEN_REPO_ROOT"))) {
      file.path(Sys.getenv("MERGEN_REPO_ROOT"), "R", filename)
    } else {
      NULL
    },
    file.path("R", filename),
    file.path("..", "..", "R", filename),
    file.path("..", "R", filename)
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
# `R/helpers_pk_analysis_core_impl.R` ve `R/helpers_pk_runtime_guards.R`
# artık `R/config_source_manifest.R` içinde AÇIKÇA sıralanmıştır (impl bu
# dosyadan ÖNCE, guard'lar SONRA). Manifest dışı dinamik `source()` bağımlılık
# sırasını atlatıyor ve staged/asenkron dağıtımlarda yanlış ya da eksik yol
# çözebiliyordu. Aşağıdaki guard YALNIZCA izole test/hata ayıklama
# yüklemeleri içindir; manifest yolunda hiçbir zaman tetiklenmez.
#
# KONTROL BU ORTAMA BAKAR (`inherits = FALSE`), ARAMA YOLUNA DEĞİL.
# `inherits = TRUE` ölçülmüş bir kusurdur: testler bu dosyayı `parent =
# globalenv()` olan TAZE bir ortama kaynaklar; aynı oturumda daha önce çalışan
# bir test yardımcıyı `globalenv()`e bırakmışsa arama yolu onu bulur, gövde
# ATLANIR ve yardımcılar hedef ortamda HİÇ tanımlanmaz. Üretimde bu dosya
# `globalenv()` içine kaynaklandığı için `environment()` zaten `globalenv()`tir
# ve manifest yolunda gövde yine atlanır.
if (!exists("summarize_columns_for_ai", mode = "function",
            envir = environment(), inherits = FALSE)) {
  # YÜKLEME `safe_source()` ÜZERİNDEN YAPILIR (repo sözleşmesi): UTF-8/BOM ve
  # Windows yerel geri düşmeleri düz `source()` içinde YOKTUR. Yardımcı
  # bulunamayan gerçekten izole bağlamlarda düz `source()` son çare olarak kalır.
  .pk_core_impl_path <- .pk_core_resolve_sibling("helpers_pk_analysis_core_impl.R")
  if (exists("safe_source", mode = "function", inherits = TRUE)) {
    safe_source(.pk_core_impl_path, encoding = "UTF-8", envir = environment())
  } else {
    source(.pk_core_impl_path, encoding = "UTF-8", local = environment())
  }
  rm(.pk_core_impl_path)
}

rm(.pk_core_resolve_sibling)
