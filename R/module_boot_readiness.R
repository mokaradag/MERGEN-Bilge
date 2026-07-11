# R/module_boot_readiness.R
# Açıklama: Açılış ekranının yalnızca gerçek hazır olma kontrol noktalarından
# ilerlemesini sağlayan küçük koordinatör. Kontrol noktaları işaretlendikçe
# istemciye "bootReadinessCheckpoint" mesajı gönderilir; tüm zorunlu noktalar
# tamamlandığında ready=TRUE bilgisi iletilir.
#
# Not: Tamamlanan anahtarlar düz bir karakter vektöründe tutulur. Daha önce
# burada bir reactiveVal kullanılıyordu; ancak mark() hem senkron başlangıç
# kodundan (yerel mod) hem de observer'lardan hem de promise geri
# çağrılarından çağrılabildiği için reaktif bağlam hatası riskini tamamen
# ortadan kaldırmak adına basit vektör tercih edilir.

bootReadinessInit <- function(session, required = NULL) {
  # Zorunlu kontrol noktaları: her biri uygulama tarafında gerçekten
  # işaretlenir. İlerleme çubuğu yalnızca bu noktalarla 100'e ulaşır.
  required <- required %||% c(
    "auth_ready",
    "saved_chats_preview_ready",
    "file_index_ready",
    "character_media_ready",
    "welcome_client_ready"
  )

  done <- character()

  # Soğuk açılış faz zamanlaması: her kontrol noktası, oturum başlangıcından
  # itibaren geçen süreyle loglanır. Böylece açılış süresinin hangi fazda
  # harcandığı (kimlik, son konuşmalar, dosya envanteri, medya, karşılama
  # istemcisi) log dosyasından doğrudan okunabilir. Tek satır/kontrol noktası
  # olduğu için üretimde gürültü oluşturmaz.
  boot_started_at <- Sys.time()

  # Soğuk açılış faz ayrımı: ilk reaktif flush'a kadar geçen süre, sunucu
  # kablolama maliyetini dosya/kimlik kontrol noktalarından ayırır. Sahte
  # session kullanan testlerde onFlushed olmayabilir; sessizce atlanır.
  tryCatch({
    if (is.function(session$onFlushed)) {
      session$onFlushed(function() {
        cat(sprintf(
          "[STARTUP PERF] first_flush elapsed_ms=%.0f\n",
          as.numeric(difftime(Sys.time(), boot_started_at, units = "secs")) * 1000
        ))
      }, once = TRUE)
    }
  }, error = function(e) NULL)

  mark <- function(key, label = key, pct = NULL, detail = NULL) {
    if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
      return(invisible(FALSE))
    }
    key <- as.character(key)

    if (!key %in% done) {
      done <<- c(done, key)

      elapsed_ms <- as.numeric(difftime(Sys.time(), boot_started_at, units = "secs")) * 1000
      deferred_flag <- isTRUE(is.list(detail) && isTRUE(detail$deferred))
      cat(sprintf(
        "[STARTUP PERF] checkpoint=%s elapsed_ms=%.0f deferred=%s\n",
        key, elapsed_ms, if (deferred_flag) "TRUE" else "FALSE"
      ))
    }

    payload <- list(
      key = key,
      label = label,
      pct = pct,
      detail = detail,
      required_done = intersect(done, required),
      required_total = length(required),
      ready = all(required %in% done)
    )

    # Oturum kapanmış olabilir (geç gelen promise geri çağrısı vb.);
    # bu durumda sessizce yut.
    tryCatch(
      session$sendCustomMessage("bootReadinessCheckpoint", payload),
      error = function(e) NULL
    )

    invisible(TRUE)
  }

  list(
    mark = mark,
    is_ready = function() all(required %in% done),
    done = function() done,
    required = required
  )
}