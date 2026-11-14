# ==============================================================================
# Dosya Yolu: R/helpers_llm_true_streaming_task.R
# Açıklama: Gerçek SSE işçi görev kapanışı fabrikası ve açılış ısıtması.
#           Kapanışın gövdesi ve ortam şekli her istekte birebir aynıdır;
#           böylece otomatik bağımlılık taraması önbelleği açılışta ısıtılan
#           kayıtla eşleşir ve ilk istem ~3 sn'lik taramayı olay döngüsünde
#           ödemez. helpers_llm_true_streaming_worker.R (globals sözleşmesi)
#           bütçesini korumak için ayrı dosyadadır; ondan SONRA yüklenir.
# ==============================================================================

mergen_true_streaming_task_fn <- function(chat_history_for_sse, settings_for_sse,
                                          stream_file_for_sse, stop_file_for_sse) {
  # Argümanlar hemen değerlendirilir: kapanış çağıranın çerçevesine bağlı
  # tembel argüman (promise) taşımaz; serileştirilen yük yalnızca veridir.
  force(chat_history_for_sse)
  force(settings_for_sse)
  force(stream_file_for_sse)
  force(stop_file_for_sse)
  function() {
    call_local_llm_sse_worker(
      chat_history = chat_history_for_sse,
      current_settings = settings_for_sse,
      stream_file = stream_file_for_sse,
      stop_file = stop_file_for_sse
    )
  }
}

# Açılışta (oturumlar gelmeden) gerçek SSE görevinin bağımlılık taramasını ısıtır.
mergen_true_streaming_warm_dependencies <- function() {
  if (!exists("worker_monitor_auto_globals", mode = "function", inherits = TRUE)) {
    return(invisible(FALSE))
  }
  sonuc <- worker_monitor_auto_globals(
    "llm_true_streaming",
    mergen_true_streaming_task_fn(list(), list(), "", ""),
    mergen_true_streaming_worker_globals(list(), list(), "", "")
  )
  invisible(isTRUE(sonuc$ok))
}
