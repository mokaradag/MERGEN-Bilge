# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_bootstrap_fs.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ BOOTSTRAP'ının SINIRLI dosya-varlık denetimi.
#
# NEDEN AYRI DOSYA: `R/helpers_pk_async_bootstrap.R` bakım ratchet'inin
# 24-fonksiyon KÜRESEL tavanındadır; oraya yeni bir yardımcı (ya da
# `pk_async_bounded_fs()`e verilecek anonim kapanışlar) eklemek tavanı aşardı.
# `R/helpers_pk_async_worker_env.R` de aynı tavandadır. Ayrım aynı zamanda
# doğru sınırdır: "hangi dosyalar yüklenir" ile "bir yol denetimi bütçeye
# uyar mı" farklı sorumluluklardır.
#
# SAF: Shiny, reaktif değer, DB, ağ veya oturum bağımlılığı YOKTUR.
# ==============================================================================

#' Dosya/dizin varlığını KALAN BÜTÇE altında denetle
#'
#' `dir.exists()` / `file.exists()` ASKIDA bir UNC/NFS bağlama noktasında
#' bloklayabilir. Bootstrap içindeki çıplak çağrılar iptal/son tarih kapısına
#' HİÇ ulaşmadan işçiyi sabitliyordu: ana süreçteki bekçi kullanıcıya yanıt
#' verse de PSOCK işçisi tutulu kalıyor ve asenkron şerit istek servis etmeyi
#' bırakıyordu. Bu sarmalayıcı denetimi `pk_async_bounded_fs()` üzerinden
#' geçirir; bütçe tükendiğinde ya da çağrı kesildiğinde `FALSE` döner
#' (KAPALI BAŞARISIZ: eksik dosya gibi davranılır).
#'
#' `pk_async_bounded_fs()` yoksa (izole test/eski yükleme sırası) davranış
#' çıplak denetimle AYNIDIR; yani bu dosya hiçbir yolu yeni bir bağımlılığa
#' bağlamaz.
#'
#' @param path Denetlenecek yol (tek öge).
#' @param dir `TRUE` ise `dir.exists()`, aksi hâlde `file.exists()`.
#' @param deadline_at Mutlak son tarih (`POSIXct`) ya da `NULL`.
#' @return `TRUE` / `FALSE`.
pk_async_bounded_path_exists <- function(path, dir = FALSE, deadline_at = NULL) {
  yol <- tryCatch(as.character(path)[1], error = function(e) NA_character_)
  if (length(yol) != 1L || is.na(yol) || !nzchar(yol)) return(FALSE)

  if (!exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
    denetim <- if (isTRUE(dir)) {
      tryCatch(dir.exists(yol), error = function(e) FALSE)
    } else {
      tryCatch(file.exists(yol), error = function(e) FALSE)
    }
    return(isTRUE(denetim[1]))
  }

  sonuc <- pk_async_bounded_fs(function() {
    if (isTRUE(dir)) dir.exists(yol) else file.exists(yol)
  }, deadline_at)

  isTRUE(sonuc$ok) && isTRUE(sonuc$value[1])
}
