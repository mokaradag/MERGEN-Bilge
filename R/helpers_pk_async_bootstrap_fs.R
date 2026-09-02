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
#' `pk_async_bounded_fs()` YOKSA (izole test/eski yükleme sırası) denetim
#' KAPALI BAŞARISIZ olur ve `FALSE` döner; çıplak `file.exists()`/`dir.exists()`
#' çağrısına DÜŞÜLMEZ. Askıda bir UNC/NFS bağlama noktasında çıplak çağrı
#' işçiyi süresiz bloklar ve iptal/son tarih kapısına hiç ulaşılamaz; bu
#' yardımcı tam da onu engellemek için vardır, dolayısıyla sınırlandırıcının
#' yokluğunda "dosya yok" demek "sınırsız beklemek"ten güvenlidir.
#'
#' @param path Denetlenecek yol (tek öge).
#' @param dir `TRUE` ise `dir.exists()`, aksi hâlde `file.exists()`.
#' @param deadline_at Mutlak son tarih (`POSIXct`) ya da `NULL`.
#' @return `TRUE` / `FALSE`.
pk_async_bounded_path_exists <- function(path, dir = FALSE, deadline_at = NULL) {
  yol <- tryCatch(as.character(path)[1], error = function(e) NA_character_)
  if (length(yol) != 1L || is.na(yol) || !nzchar(yol)) return(FALSE)

  # SINIRSIZ DOSYA DENETİMİ YAPILMAZ (KAPALI BAŞARISIZ): `pk_async_bounded_fs`
  # yüklü değilken doğrudan `dir.exists()`/`file.exists()` çağrılırsa, askıda
  # bir UNC/NFS bağlama noktasında işçi o çağrıda BLOKLANIR ve iptal/son tarih
  # kapısına HİÇ ulaşamaz. Sınırlandırıcı yoksa bootstrap `FALSE` ile kapanır.
  if (!exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) return(FALSE)

  sonuc <- pk_async_bounded_fs(function() {
    if (isTRUE(dir)) dir.exists(yol) else file.exists(yol)
  }, deadline_at)

  isTRUE(sonuc$ok) && isTRUE(sonuc$value[1])
}
