# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_dir_listing_async.R
# Açıklama: Bilge Yolaç dizin gezgini numaralandırmasını ana Shiny olay
#           döngüsünden çıkarmak için gereken worker global paketi ve plan
#           uygunluk kontrolü. Yalnızca saf karar/veri hazırlığı içerir;
#           Shiny, reaktif değer, DB veya ağ bağımlılığı yoktur.
#
#           Ayrı dosyada tutulmasının nedeni, dizin listeleme yardımcısının
#           bakım ratchet bütçesini (satır/fonksiyon) korumaktır.
# ==============================================================================

# Dizin numaralandırması worker'a gönderilirken taşınacak global paketi.
# Süreç başına BİR KEZ kurulur: bağımlılık taraması her yenilemede ana Shiny
# olay döngüsünde tekrarlanmamalıdır.
.cc_dir_listing_worker_cache <- new.env(parent = emptyenv())

#' Dizin listeleme worker'ına aktarılacak global paketi (bir kez) oluştur
#'
#' @param refresh Önbelleği yenile
#' @param envir Aranacak ortam
#' @return Worker'a aktarılacak isimlendirilmiş global listesi
cc_dir_listing_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
  if (!isTRUE(refresh) && !is.null(.cc_dir_listing_worker_cache$globals)) {
    return(.cc_dir_listing_worker_cache$globals)
  }

  istenen <- c(
    "list_directory_contents",
    "cc_build_dir_variants",
    "cc_list_dir_relaxed",
    "cc_normalize_dir_entry",
    "cc_resolve_dir_display_name",
    "cc_scan_list_dir_bounded",
    "mergen_resolve_display_name",
    "normalize_mcp_path",
    "path_exists_relaxed",
    ".load_index"
  )

  paket <- list()
  for (ad in istenen) {
    nesne <- get0(ad, envir = envir, inherits = TRUE)
    if (!is.null(nesne)) paket[[ad]] <- nesne
  }

  if (exists("worker_monitor_expand_function_globals", mode = "function", inherits = TRUE)) {
    ic_ice <- tryCatch(
      worker_monitor_expand_function_globals(paket),
      error = function(e) list()
    )

    for (ad in names(ic_ice)) {
      if (!ad %in% names(paket)) paket[[ad]] <- ic_ice[[ad]]
    }
  }

  .cc_dir_listing_worker_cache$globals <- paket
  paket
}

#' Dizin listeleme arka planda çalıştırılabilir mi
#'
#' Gerçekten eşzamansız bir future planı yoksa gönderim gövdeyi ana olay
#' döngüsünde çalıştırır; bu durumda doğrudan senkron çağrı tercih edilir.
#'
#' @return Eşzamansız gönderim mümkünse TRUE
cc_dir_listing_async_available <- function() {
  if (!exists("tracked_future_promise", mode = "function", inherits = TRUE)) return(FALSE)
  if (!requireNamespace("promises", quietly = TRUE)) return(FALSE)
  if (!exists("cc_future_plan_is_async", mode = "function", inherits = TRUE)) return(FALSE)

  isTRUE(tryCatch(cc_future_plan_is_async(), error = function(e) FALSE))
}

#' Bloklayan `fs::dir_ls()` yedeği bu bağlamda serbest mi
#'
#' `.cc_scan_list_entries()` yedeği `setTimeLimit(transient = TRUE)` ile
#' sınırlar; ancak o mekanizma R/Rcpp düzeyinde kesme yapar ve ASKIDA kalmış
#' bir YERLİ çağrıyı (kopmuş ya da çok yavaş bir UNC paylaşımında
#' `fs::dir_ls()`) KESEMEZ. Ana Shiny olay döngüsünde çalışırsa çağrı dönene
#' kadar TÜM oturumlar birlikte donar.
#'
#' Kural: etkin bir reaktif alan VARSA (yani ana süreçteki bir gözlemcideyiz)
#' VE güvenli eşzamansız yol MEVCUTSA yedek kapatılır; `observe_dir_contents()`
#' zaten işçiye gönderir ve işçide reaktif alan YOKTUR, dolayısıyla yedek orada
#' normal çalışmaya devam eder. Eşzamansız yol yoksa (sıralı future planı,
#' izole test) davranış AYNEN korunur: UNC sahte-boş listesine karşı tek
#' koruma odur.
#'
#' @return Bloklayan dosya sistemi yedeği çalıştırılabilirse TRUE
cc_dir_listing_fs_fallback_allowed <- function() {
  reaktif_alanda <- isTRUE(tryCatch(
    !is.null(shiny::getDefaultReactiveDomain()),
    error = function(e) FALSE
  ))
  if (!reaktif_alanda) return(TRUE)

  !isTRUE(tryCatch(cc_dir_listing_async_available(), error = function(e) FALSE))
}

