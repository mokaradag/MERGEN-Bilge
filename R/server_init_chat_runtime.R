# ==============================================================================
# Dosya Yolu: R/server_init_chat_runtime.R
# Açıklama: server.R içinde kullanılan sohbet çalışma zamanı yardımcılarını
#           kurar. Mesaj ekleme, durum sıfırlama, başlık üretme ve simüle
#           streaming sarmalayıcılarını tek yerde toplar.
# ==============================================================================

serverInitChatRuntime <- function(session, values, settings_data, output,
                                  resolve_current_user_id, stop_generation) {

  # ---------------------------------------------------------------------------
  # Sohbet durumunu sıfırlayan yardımcı
  # ---------------------------------------------------------------------------
  reset_chat_state <- function() {
    chat_reset_state(session, values)
  }

  # ---------------------------------------------------------------------------
  # Oturumun etkin kullanıcı kimliği ile mesaj ekleyen yardımcı
  # ---------------------------------------------------------------------------
  add_message <- function(content, type = "user", html = NULL, followups = NULL,
                          audio_src = NULL, audio_voice = NULL,
                          reasoning_content = NULL) {

    effective_user_id <- resolve_current_user_id()

    chat_add_message(
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      content = content,
      type = type,
      html = html,
      current_user_id = effective_user_id,
      followups = followups,
      audio_src = audio_src,
      audio_voice = audio_voice,
      reasoning_content = reasoning_content
    )
  }

  # ---------------------------------------------------------------------------
  # Sohbet başlığı üreten yardımcı
  # ---------------------------------------------------------------------------
  generate_title_from_prompt <- function(prompt, max_len = 60) {
    chat_generate_title_from_prompt(prompt, max_len)
  }

  # ---------------------------------------------------------------------------
  # Simüle streaming sarmalayıcısı
  # ---------------------------------------------------------------------------
  simulate_streaming_stoppable <- function(full_response, followups = NULL,
                                           on_complete = NULL, on_start = NULL,
                                           tts_engine = NULL, tts_voice = NULL) {
    chat_simulate_streaming(
      full_response = full_response,
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      stop_generation = stop_generation,
      followups = followups,
      on_complete = on_complete,
      on_start = on_start,
      tts_engine = tts_engine,
      tts_voice = tts_voice
    )
  }

  list(
    reset_chat_state = reset_chat_state,
    add_message = add_message,
    generate_title_from_prompt = generate_title_from_prompt,
    simulate_streaming_stoppable = simulate_streaming_stoppable
  )
}