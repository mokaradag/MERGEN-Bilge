# ==============================================================================
# Dosya Yolu: R/utils_safe_worker_run.R
# Açıklama: Arka plan (future) görevleri içinde çalışan saf iş fonksiyonlarını
# tek tip bir "başarı/hata" yapısıyla sarmalayan yardımcı. Üretim ortamında
# tracked_future_promise zinciri içinden atılan ham stop() çağrıları:
#   - log'da ham mesaj olarak görünür (bazen hassas içerik barındırır),
#   - promise reject yoluna düştüğünde UI katmanında yakalanmamışsa oturumu
#     iki katmanlı hata mesajına sokar,
#   - süre (duration) bilgisi kaybolur.
# safe_worker_run bu üçünü ortadan kaldırır: sonucu daima
# list(ok, value, error_code, error_message, duration_sec) olarak döndürür.
# Çağıran taraf artık tek bir başarı/hata şeklinde UI'ye yansıtabilir.
# ==============================================================================

# task_fn:         Argümansız bir fonksiyon (veya lazy eval edilecek işi taşıyan).
# error_code_fn:   Opsiyonel, cerrahi durumlarda error_code'u özelleştirir.
#                  Varsayılan "worker_error". İki kademeli sınıflandırma yaparken
#                  çağıran taraf kendi kuralını uygulayabilir.
# timeout_sec:     İleri sürüm için rezerve; şu anda yan etkisi yok (future
#                  paketinde zamanaşımı desteği kurulum bağımlıdır). Ham tutulur
#                  ki çağrı imzası bozulmadan zamanaşımı eklenebilsin.
safe_worker_run <- function(task_fn,
                            error_code_fn = NULL,
                            timeout_sec = NULL) {
  if (!is.function(task_fn)) {
    return(list(
      ok = FALSE,
      value = NULL,
      error_code = "invalid_task_fn",
      error_message = "safe_worker_run: 'task_fn' fonksiyon değil.",
      duration_sec = 0
    ))
  }

  baslangic <- Sys.time()

  sonuc <- tryCatch(
    {
      deger <- task_fn()
      list(
        ok = TRUE,
        value = deger,
        error_code = NULL,
        error_message = NULL
      )
    },
    error = function(e) {
      ham_mesaj <- tryCatch(
        conditionMessage(e),
        error = function(err) "<bilinmeyen hata>"
      )

      mesaj <- ham_mesaj
      if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
        mesaj <- tryCatch(
          redact_sensitive_text(ham_mesaj),
          error = function(err) ham_mesaj
        )

        if (is.character(mesaj) && length(mesaj) > 0L) {
          mesaj <- mesaj[1]
        } else {
          mesaj <- ham_mesaj
        }
      }

      kod <- if (is.function(error_code_fn)) {
        tryCatch({
          ham <- error_code_fn(e)
          if (is.null(ham) || length(ham) == 0L) "worker_error" else as.character(ham)[1]
        }, error = function(err) "worker_error")
      } else {
        "worker_error"
      }

      list(
        ok = FALSE,
        value = NULL,
        error_code = kod,
        error_message = mesaj
      )
    }
  )

  bitis <- Sys.time()
  sonuc$duration_sec <- as.numeric(difftime(bitis, baslangic, units = "secs"))
  sonuc
}