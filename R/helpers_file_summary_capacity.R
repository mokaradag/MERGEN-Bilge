# ==============================================================================
# Dosya Yolu: R/helpers_file_summary_capacity.R
# Açıklama: Dosya özeti kuyruğunun kapasite ve sınır kararları (işçi havuzu,
#           eşzamanlılık, kuyruk bütçeleri, çok-süreçli dağıtım payı).
#           R/helpers_file_summary_queue.R kullanır.
# ==============================================================================

file_summary_int_setting <- function(env_name, default_value) {
  deger <- suppressWarnings(as.integer(Sys.getenv(env_name, as.character(default_value))))
  if (length(deger) != 1L || is.na(deger) || deger < 1L) default_value else deger
}

# Çok-süreçli dağıtımda (tools/run_mergen_workers.R) sınırlar DAĞITIM
# geneli içindir: her uygulama süreci kendi dilimini alır, dilimlerin toplamı
# yapılandırılan değeri aşmaz (N süreç x sınır kadar eşzamanlı LLM çağrısı olmaz).
file_summary_process_share <- function(toplam) {
  n <- suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_COUNT", "1")))
  i <- suppressWarnings(as.integer(Sys.getenv("MERGEN_APP_WORKER_INDEX", "1")))
  if (length(n) != 1L || is.na(n) || n <= 1L) return(as.integer(toplam))
  if (length(i) != 1L || is.na(i) || i < 1L || i > n) i <- 1L
  as.integer(toplam %/% n + (i <= toplam %% n))
}

file_summary_max_concurrent <- function() {
  file_summary_process_share(file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_CONCURRENT", 2L))
}

# Eşzamansız olmayan planda (sequential: küme kurulamadı ya da futures kapalı)
# özet ana olay döngüsünde çalışıp tüm oturumları dondurur; kapasite 0 sayılır.
file_summary_pool_size <- function() {
  plan_sinifi <- tryCatch(class(future::plan("list")[[1]]), error = function(e) character(0))
  if (!length(plan_sinifi) || any(c("sequential", "uniprocess", "transparent") %in% plan_sinifi)) return(0L)
  n <- tryCatch(suppressWarnings(as.integer(future::nbrOfWorkers())), error = function(e) NA_integer_)
  if (length(n) != 1L || is.na(n) || n < 1L) 1L else n
}

file_summary_free_workers <- function() {
  n <- tryCatch(suppressWarnings(as.integer(future::nbrOfFreeWorkers())), error = function(e) NA_integer_)
  if (length(n) != 1L) NA_integer_ else n
}

# Özetler paylaşılan havuzun tamamını tutamaz: sınır havuzdan bir eksiktir ve
# özet yalnız bir işçi etkileşimli işe (sohbet, LLM) boş kalacaksa başlar.
# İkiden az işçili havuz bölünemez; orada özet çalışmaz (tek işçiyi tutan özet
# sonradan gelen sohbet isteğini bekletirdi).
file_summary_effective_limit <- function() {
  havuz <- file_summary_pool_size()
  if (havuz < 2L) return(0L)
  min(file_summary_max_concurrent(), havuz - 1L)
}

# Boş işçi sayısı ölçülemezse özet başlamaz (kapalı-başarısız); kuyruk saniyede
# bir yeniden dener.
file_summary_has_capacity <- function() {
  sinir <- file_summary_effective_limit()
  if (sinir < 1L || .FILE_SUMMARY_QUEUE$active >= sinir) return(FALSE)
  bos <- file_summary_free_workers()
  if (is.na(bos)) return(FALSE)
  bos > 1L
}

# Bekleyen kuyruk da sınırlıdır (MERGEN_FILE_SUMMARY_MAX_QUEUE, varsayılan 64):
# her kayıt oturum ve dosya durumunu tuttuğundan sınırsız büyüyemez.
file_summary_max_queue <- function() {
  max(1L, file_summary_process_share(file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_QUEUE", 64L)))
}

# Tek kullanıcı (tüm sekmeleri birlikte) ortak bekleme bütçesini tüketemez
# (MERGEN_FILE_SUMMARY_MAX_QUEUE_PER_SESSION, varsayılan 16).
file_summary_max_queue_per_session <- function() {
  min(file_summary_int_setting("MERGEN_FILE_SUMMARY_MAX_QUEUE_PER_SESSION", 16L),
      file_summary_max_queue())
}
