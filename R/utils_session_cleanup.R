# ==============================================================================
# Dosya Yolu: R/utils_session_cleanup.R
# Açıklama: Shiny oturumu sonlandığında arka plan kaynaklarının temizlenmesi
# için merkezi yardımcılar. Uzun süreli çalışan VM kurulumunda oturumların
# düzensiz kapanması (tarayıcı sekmesi kapandı, ağ koptu, timeout) async
# görevlerin defterde ölü kayıt bırakmasına sebep olur. Sağlık metrikleri ve
# kapasite planlama bu nedenle yanlış okunur. Bu modül, modüllerin tek tip
# biçimde `register_session_cleanup_on_end()` çağrısıyla kendilerini bu
# defterden düşürmesini sağlar.
#
# Bağımlılık: helpers_worker_monitor.R içindeki cleanup_worker_tasks_for_session
# fonksiyonu (global.R Grup 1'de önce yüklenir).
# ==============================================================================

# Bir Shiny oturumu sonlandığında tetiklenecek temizlik setini tek çağrı ile
# kaydeder. Çağrı idempotent değildir: aynı oturum için iki kez çağrılırsa
# iki callback birikir. Modüller bu yüzden oturum başına bir kez çağırmalı.
# Ek callback'ler extra_cleanup = list(function() {...}, function() {...})
# olarak geçilebilir.
register_session_cleanup_on_end <- function(session, extra_cleanup = list()) {
  # Shiny session nesnesi list veya environment biçiminde gelebilir.
  if (is.null(session) || !(is.list(session) || is.environment(session))) {
    return(invisible(FALSE))
  }

  # Bazı Shiny oturumları onSessionEnded metodunu taşımayabilir (örn. testServer
  # bağlamı); bu durumda sessizce atlanır.
  if (!is.function(session$onSessionEnded)) {
    return(invisible(FALSE))
  }

  # Aynı oturum için temizlik callback'i birden fazla kez kaydedilmesin.
  # Büyük Shiny uygulamalarında modül yeniden bağlama / Ctrl+Enter / testServer
  # senaryoları çift kayıt oluşturabilir. Bu da aynı temizlik işinin gereksiz
  # tekrarına ve yanıltıcı sayaçlara yol açar.
  if (is.null(session$userData) || !is.environment(session$userData)) {
    session$userData <- new.env(parent = emptyenv())
  }

  if (isTRUE(session$userData$mergen_session_cleanup_registered)) {
    return(invisible(TRUE))
  }

  session$userData$mergen_session_cleanup_registered <- TRUE

  session_token <- session$token %||% NA_character_

  session$onSessionEnded(function() {
    # 1) Async görev defterini bu oturuma ait kayıtlardan temizle.
    if (exists("cleanup_worker_tasks_for_session",
               envir = globalenv(), inherits = FALSE)) {
      try(cleanup_worker_tasks_for_session(session_token), silent = TRUE)
    }

    # 2) Çağıranın özel temizlik fonksiyonlarını çalıştır. Herhangi biri
    #    hata verirse diğerleri yine de çalışır; üretimde sessiz log'la.
    if (length(extra_cleanup) > 0L) {
      for (fn in extra_cleanup) {
        if (is.function(fn)) {
          try(fn(), silent = TRUE)
        }
      }
    }
  })

  invisible(TRUE)
}

# Tek bir geçici dosyayı güvenle (hata fırlatmadan) siler. Cleanup callback'i
# içinde bir dosya yolunun temizlenmesi için doğrudan callback'e sarmalanabilir.
# session ended aşamasında dosya zaten silinmiş veya kilitli olabileceği için
# başarısızlık sessizce atlanır.
safe_unlink_if_exists <- function(path) {
  if (is.null(path) || !is.character(path) || length(path) != 1L) return(invisible(FALSE))
  if (!nzchar(path) || is.na(path)) return(invisible(FALSE))
  if (!file.exists(path)) return(invisible(FALSE))
  try(unlink(path, force = TRUE), silent = TRUE)
  invisible(TRUE)
}