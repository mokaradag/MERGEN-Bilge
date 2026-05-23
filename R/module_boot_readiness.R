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

  mark <- function(key, label = key, pct = NULL, detail = NULL) {
    if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
      return(invisible(FALSE))
    }
    key <- as.character(key)

    if (!key %in% done) {
      done <<- c(done, key)
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
