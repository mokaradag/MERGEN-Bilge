# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_probe.R
# Açıklama: Faz 6 (§5.10) — future planının GERÇEKTEN ayrı süreçte çalışıp
#           çalışmadığını ölçen işçi-PID sondası ve süreç-yerel önbelleği.
#
#           `R/helpers_pk_async_plan.R` İÇİNDEN AYRILDI (bakım ratchet'i):
#           sonda, bekleyen future'ı yeniden kullanan ve ölçülemeyen sonucu
#           soğuma penceresiyle hatırlayan kendi başına bir eşzamanlılık
#           sorunudur. Plan dosyası yalnızca yetenek/strateji çözümlemesini
#           taşır.
#
#           Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı YOKTUR. Kaynak
#           manifesti bu dosyayı `helpers_pk_async_plan.R` dosyasından ÖNCE
#           yükler; plan dosyası sondayı ÇAĞIRIR.
# ==============================================================================

# İşçi PID sondası (SÜREÇ BAŞINA MEMOIZE)
#
# @return `TRUE` işçi AYRI süreçte, `FALSE` işçi ANA süreçte, `NA` ölçülemedi.
.pk_async_plan_probe_cache <- new.env(parent = emptyenv())

.pk_async_worker_pid_probe <- function(force = FALSE, plan_key = NULL) {
  anahtar <- tryCatch(as.character(plan_key %||% .pk_async_plan_key())[1],
                      error = function(e) "plan")
  if (!isTRUE(force) && !is.null(.pk_async_plan_probe_cache$result) &&
      identical(.pk_async_plan_probe_cache$key, anahtar)) {
    return(.pk_async_plan_probe_cache$result)
  }
  # Plan DEĞİŞTİYSE bekleyen sonda ve soğuma penceresi de geçersizdir.
  if (!identical(.pk_async_plan_probe_cache$key, anahtar)) {
    .pk_async_plan_probe_cache$pending <- NULL
    .pk_async_plan_probe_cache$na_until <- NULL
  }
  .pk_async_plan_probe_cache$key <- anahtar

  # SONDA SINIRLIDIR: ANA OLAY DÖNGÜSÜ BLOKE EDİLMEZ. `future::value(f)` tek
  # işçili bir `AsIs` planında işçi boşalana kadar TÜM oturumları dondururdu;
  # bunun yerine `resolved()` sınırlı bütçe boyunca yoklanır ve çözülmezse
  # sonuç ÖLÇÜLEMEDİ (`NA`) olur.
  butce_sn <- suppressWarnings(as.numeric(
    Sys.getenv("MERGEN_PK_ASYNC_PROBE_TIMEOUT_SEC", unset = "1")
  )[1])
  if (is.na(butce_sn) || !is.finite(butce_sn) || butce_sn < 0) butce_sn <- 1

  # ÖLÇÜLEMEYEN SONUÇ KISA SÜRE HATIRLANIR; BEKLEYEN SONDA YENİDEN KULLANILIR.
  #
  # Eskiden her çağrı YENİ bir `Sys.getpid()` future'ı kuyruğa alıyor ve tam
  # bütçe boyunca ana süreçte uyuyordu; tek işçili planda sondalar gerçek
  # analiz işinin ÖNÜNE diziliyor, her istek yoklama gecikmesini yeniden
  # ödüyordu. `MERGEN_PK_ASYNC_PROBE_RETRY_SEC` (varsayılan 30 sn) soğuma
  # penceresidir; `force = TRUE` pencereyi atlar.
  soguma_sn <- suppressWarnings(as.numeric(
    Sys.getenv("MERGEN_PK_ASYNC_PROBE_RETRY_SEC", unset = "30")
  )[1])
  if (is.na(soguma_sn) || !is.finite(soguma_sn) || soguma_sn < 0) soguma_sn <- 30
  na_kadar <- .pk_async_plan_probe_cache$na_until
  if (!isTRUE(force) && inherits(na_kadar, "POSIXct") && length(na_kadar) == 1L &&
      !is.na(na_kadar) && Sys.time() < na_kadar) return(NA)

  sonuc <- tryCatch({
    f <- .pk_async_plan_probe_cache$pending
    if (is.null(f) || !inherits(f, "Future")) {
      f <- future::future(Sys.getpid(), lazy = FALSE, seed = TRUE)
      .pk_async_plan_probe_cache$pending <- f
    }
    bitis <- Sys.time() + butce_sn
    cozuldu <- FALSE
    repeat {
      cozuldu <- isTRUE(future::resolved(f))
      if (cozuldu || Sys.time() >= bitis) break
      Sys.sleep(0.025)
    }
    if (!cozuldu) NA else {
      .pk_async_plan_probe_cache$pending <- NULL
      isci_pid <- suppressWarnings(as.integer(future::value(f))[1])
      if (is.na(isci_pid)) NA else !identical(isci_pid, Sys.getpid())
    }
  }, error = function(e) {
    .pk_async_plan_probe_cache$pending <- NULL
    NA
  })

  # Kesin sonuç (TRUE/FALSE) plan başına bir kez ölçülür.
  if (!is.na(sonuc)) {
    .pk_async_plan_probe_cache$result <- sonuc
    .pk_async_plan_probe_cache$na_until <- NULL
  } else {
    .pk_async_plan_probe_cache$na_until <- Sys.time() + soguma_sn
  }
  sonuc
}

#' Sonda önbelleğini sıfırla (plan değiştiğinde / testlerde)
pk_async_plan_probe_reset <- function() {
  .pk_async_plan_probe_cache$result <- NULL
  .pk_async_plan_probe_cache$key <- NULL
  .pk_async_plan_probe_cache$pending <- NULL
  .pk_async_plan_probe_cache$na_until <- NULL
  invisible(TRUE)
}
