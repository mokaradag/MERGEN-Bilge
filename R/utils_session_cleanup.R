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

.session_user_data_normalize_key <- function(key, owner) {
  if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
    stop(sprintf("%s: Geçerli bir session$userData anahtarı bekleniyor.", owner), call. = FALSE)
  }

  as.character(key)
}

session_user_data_env <- function(session, owner = "session_user_data_env") {
  if (is.null(session) || !(is.list(session) || is.environment(session))) {
    stop(sprintf("%s: Geçerli bir Shiny session nesnesi bekleniyor.", owner), call. = FALSE)
  }

  if (is.null(session$userData) || !is.environment(session$userData)) {
    stop(sprintf("%s: session$userData environment olmalıdır.", owner), call. = FALSE)
  }

  session$userData
}

session_user_data_get_list <- function(session, key, default = list(), create = TRUE) {
  key <- .session_user_data_normalize_key(key, "session_user_data_get_list")
  user_data <- session_user_data_env(session, "session_user_data_get_list")

  value <- user_data[[key]]

  if (is.null(value)) {
    if (is.null(default)) {
      default <- list()
    }

    if (!is.list(default)) {
      stop("session_user_data_get_list: default liste olmalıdır.", call. = FALSE)
    }

    if (isTRUE(create)) {
      user_data[[key]] <- default
    }

    return(default)
  }

  if (!is.list(value)) {
    stop(sprintf("session_user_data_get_list: '%s' alanı liste olmalıdır.", key), call. = FALSE)
  }

  value
}

session_user_data_set_list <- function(session, key, value = list()) {
  key <- .session_user_data_normalize_key(key, "session_user_data_set_list")
  user_data <- session_user_data_env(session, "session_user_data_set_list")

  if (is.null(value)) {
    value <- list()
  }

  if (!is.list(value)) {
    stop(sprintf("session_user_data_set_list: '%s' için liste bekleniyor.", key), call. = FALSE)
  }

  user_data[[key]] <- value
  user_data[[key]]
}

session_user_data_put_list_item <- function(session, key, item_name, value) {
  key <- .session_user_data_normalize_key(key, "session_user_data_put_list_item")

  if (is.null(item_name) || length(item_name) != 1L || !nzchar(as.character(item_name))) {
    stop("session_user_data_put_list_item: Geçerli bir öğe adı bekleniyor.", call. = FALSE)
  }

  items <- session_user_data_get_list(session, key)
  items[[as.character(item_name)]] <- value
  session_user_data_set_list(session, key, items)
}

session_user_data_remove_list_item <- function(session, key, item_name) {
  key <- .session_user_data_normalize_key(key, "session_user_data_remove_list_item")

  if (is.null(item_name) || length(item_name) != 1L || !nzchar(as.character(item_name))) {
    return(invisible(session_user_data_get_list(session, key)))
  }

  items <- session_user_data_get_list(session, key)
  items[[as.character(item_name)]] <- NULL
  session_user_data_set_list(session, key, items)
}

session_user_data_reset_lists <- function(session, keys) {
  if (is.null(keys) || length(keys) == 0L) {
    return(invisible(FALSE))
  }

  for (key in as.character(keys)) {
    session_user_data_set_list(session, key, list())
  }

  invisible(TRUE)
}

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