# DNS beklerken yalnız ilgili HTTP kontrolleri yenilenir.
health_refresh_pending_endpoints <- function(checks) {
  bekleyen <- which(checks$value == "DNS bekleniyor" & !is.na(checks$value))
  for (i in bekleyen) {
    sonuc <- switch(checks$id[i],
      llm.endpoint = health_check_llm_endpoint(),
      tts.endpoint = health_check_http_endpoint("tts.endpoint", "TTS Endpoint",
        Sys.getenv("LOCAL_TTS_ENDPOINT", "")),
      stt.endpoint = health_check_http_endpoint("stt.endpoint", "STT Endpoint",
        Sys.getenv("LOCAL_STT_ENDPOINT", "")),
      image.endpoint = health_check_http_endpoint("image.endpoint", "Görsel Üretim Endpoint",
        Sys.getenv("IMAGE_GEN_ENDPOINT", Sys.getenv("LOCAL_IMAGE_ENDPOINT", ""))))
    if (is.data.frame(sonuc)) checks[i, ] <- sonuc[1L, names(checks), drop = FALSE]
  }
  checks
}
