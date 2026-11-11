# ==============================================================================
# Dosya Yolu: R/helpers_worker_future_dispatch.R
# Açıklama: tracked_future_promise() future (kalıcı PSOCK) şeridinin gönderim
#           katmanı. İşçiye giden yükün yalnızca görev ve açık globals'tan
#           oluşmasını garanti eder; Shiny oturum grafiği soketlere taşınmaz.
#           helpers_worker_monitor.R ile aynı manifest satırında yüklenir.
# ==============================================================================

# İşi promises iş kuyruğuyla (boş işçi gelince) future olarak başlatır.
# Future nesnesi promises'a VERİLMEZ: as.promise() dönüşüm sonucunu future
# ortamına "converted_promise" özniteliği olarak yazar ve future'ın iç
# clusterCall kapanışları (işçi temizleme/gc) bu ortamı yakaladığı için then
# geri çağrılarına bağlı oturum grafiği (yüzlerce MB) her tamamlanmada işçi
# soketine serileştirilip ana olay döngüsünü saniyelerce blokluyordu. Sonuç
# burada aynı 0,1 sn aralıkla yoklanır ve yalnızca düz bir promise döner.
# future çağrıları, çerçevesi yalnızca future'ı tutan üst düzey yardımcılardan
# yapılır; tembel argümanlar üzerinden de geri çağrı grafiğine erişilemez.
.worker_monitor_future_baslat <- function(globals, packages) {
  f <- future::future({ if (is.raw(task_fn)) task_fn <- unserialize(task_fn); task_fn() },
                      envir = baseenv(), globals = globals, packages = packages, lazy = TRUE)
  # Oluşturma anındaki çağrı yığını (sys.calls) yalnızca hata bağlamı içindir;
  # later/oturum geri çağrılarından gönderimde gömülü oturum nesnelerini taşıyıp
  # işçiye giden yükü yüzlerce MB'a çıkarıyordu. Başlatmadan önce boşaltılır.
  f[["calls"]] <- NULL
  future::run(f)
}
.worker_monitor_future_bitti <- function(f) future::resolved(f, timeout = 0)
.worker_monitor_future_deger <- function(f) future::value(f, signal = TRUE)

worker_monitor_future_promise <- function(promise_globals, future_packages) {
  kuyruk <- promises::future_promise_queue()
  promises::promise(function(resolve, reject) {
    kuyruk$schedule_work(function() {
      is_promise <- promises::promise(function(cozul, reddet) {
        is_future <- .worker_monitor_future_baslat(promise_globals, future_packages)
        yokla <- function() {
          bitti <- tryCatch(.worker_monitor_future_bitti(is_future),
                            FutureError = function(e) { reddet(e); NA })
          if (is.na(bitti)) return(invisible(NULL))
          if (!isTRUE(bitti)) return(invisible(later::later(yokla, 0.1)))
          tryCatch(cozul(.worker_monitor_future_deger(is_future)),
                   error = function(e) reddet(e))
        }
        yokla()
      })
      resolve(is_promise)
      is_promise
    })
  })
}
