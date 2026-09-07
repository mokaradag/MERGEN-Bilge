# ==============================================================================
# Dosya Yolu: R/helpers_llm_true_streaming_worker.R
# Açıklama: Gerçek SSE streaming işçisine (call_local_llm_sse_worker)
#           tracked_future_promise üzerinden aktarılacak global bağımlılık
#           listesini kuran SAF fabrika. handle_true_streaming_mode() bu listeyi
#           tek satırda alır.
#
#           Neden ayrı dosya: bu liste worker-export SÖZLEŞMESİDİR. Reasoning
#           delta yazımı, stop-file kontrolü ve modele özel request override
#           yardımcılarının işçi tarafında görünür kalması gerekir (CLAUDE.md).
#           Listeyi tek yerde toplamak, sözleşmeyi bir testle (worker-export
#           adlarının varlığı) kilitler ve gerçek SSE handler dosyasını
#           küçük/odaklı tutar.
#
#           Saflık: fonksiyon yan etkisizdir. Sembolleri ÇAĞIRMAZ, yalnızca
#           isimli bir listede toplar. İsteğe-özel 4 nesne (chat geçmişi,
#           ayarlar, akış/stop dosya yolları) argüman olarak alınır; geri kalanı
#           çalışma zamanında global ortamda çözülen kararlı yardımcı fonksiyonlar
#           ve api_config'tir. Bu yüzden yalnızca handle_true_streaming_mode'un
#           çağrıldığı çalışma zamanı bağlamında (global yardımcılar yüklüyken)
#           çağrılmalıdır.
# ==============================================================================

mergen_true_streaming_worker_globals <- function(chat_history_for_sse,
                                                 settings_for_sse,
                                                 stream_file_for_sse,
                                                 stop_file_for_sse) {
  list(
    chat_history_for_sse = chat_history_for_sse,
    settings_for_sse = settings_for_sse,
    stream_file_for_sse = stream_file_for_sse,
    stop_file_for_sse = stop_file_for_sse,
    call_local_llm_sse_worker = call_local_llm_sse_worker,
    get_local_model_capabilities = get_local_model_capabilities,
    should_omit_temperature = should_omit_temperature,
    should_allow_reasoning_fallback = should_allow_reasoning_fallback,
    apply_model_request_overrides = apply_model_request_overrides,
    normalize_llm_text_node = normalize_llm_text_node,
    extract_first_nonempty_llm_text = extract_first_nonempty_llm_text,
    extract_llm_text_bundle = extract_llm_text_bundle,
    extract_llm_delta_bundle = extract_llm_delta_bundle,
    `%||%` = `%||%`,
    resolve_local_llm_endpoint = resolve_local_llm_endpoint,
    resolve_local_llm_credentials = resolve_local_llm_credentials,
    extract_llm_content_and_sources = extract_llm_content_and_sources,
    normalize_llm_scalar_content = normalize_llm_scalar_content,
    strip_planner_text = strip_planner_text,
    decode_utf8_raw_chunk = decode_utf8_raw_chunk,
    create_utf8_stream_decoder = create_utf8_stream_decoder,
    find_last_utf8_boundary = find_last_utf8_boundary,
    parse_llm_sse_event = parse_llm_sse_event,
    extract_llm_delta_text = extract_llm_delta_text,
    extract_llm_event_sources = extract_llm_event_sources,
    append_stream_delta_line = append_stream_delta_line,
    append_stream_reasoning_line = append_stream_reasoning_line,
    # Durdurma dosyası denetimi worker içinde yapılır; sembol açıkça taşınmazsa
    # explicit bağımlılık kipinde "fonksiyon bulunamadı" ile düşerdi.
    streaming_should_stop = streaming_should_stop,
    log_info = log_info,
    log_warn = log_warn,
    # SQL/Proje analizi non-streaming güvenlik ağı: işçi, akış yalnızca
    # akıl yürütme benzeri/boş içerik döndürdüğünde bu yardımcıyla tespit yapar.
    llm_worker_stream_content_looks_like_reasoning = llm_worker_stream_content_looks_like_reasoning,
    api_config = api_config
  )
}
