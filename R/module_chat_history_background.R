# R/module_chat_history_background.R
# Açıklama: Söyleşi geçmişini görünür ilk bölümden sonra küçük partilerle ısıtır.

# Önbellekte eksik ya da damgası değişmiş (bayat) söyleşi kimlikleri, verilen
# sırayla. Başarısız okumalar önbelleğe hiç yazılmadığı için burada "eksik"
# görünür ve yeniden denenir; başarıyla okunmuş BOŞ geçmiş damga eşleştikçe
# isabettir (her ziyarette yeniden sorgulanmaz).
history_ids_needing_fetch <- function(chat_ids, chats, cache, stamp_fn) {
  ids <- setdiff(as.character(chat_ids %||% character()), "current_chat")
  ids <- ids[!is.na(ids) & nzchar(ids)]
  ids[vapply(ids, function(id) {
    info <- chats[[id]]
    if (is.null(info)) return(FALSE)
    onbellek <- cache[[id]]
    is.null(onbellek) || !identical(onbellek$stamp, stamp_fn(info))
  }, logical(1), USE.NAMES = FALSE)]
}

# Önbellekten kayıt düşüren işlev üretir: yerinde içerik düzenlemesi (ör.
# galeriden görsel silme mesaj metnini değiştirir) zaman/sayı damgasını
# değiştirmediği için ilgili kayıtlar düşer. yayin_sayaci (reactiveVal)
# verilmişse artırılır: açık geçmiş tablosu yeniden yayınlanır ve silinmiş
# görselin alıntısı tabloda kalmaz. chat_ids NULL ise tüm önbellek düşer.
history_cache_dropper <- function(messages_cache, yayin_sayaci = NULL) {
  function(chat_ids = NULL) {
    cache <- shiny::isolate(messages_cache())
    dusur <- if (is.null(chat_ids)) names(cache) else intersect(names(cache), as.character(chat_ids))
    if (length(dusur)) {
      cache[dusur] <- NULL
      messages_cache(cache)
      if (is.function(yayin_sayaci)) yayin_sayaci(shiny::isolate(yayin_sayaci()) + 1)
    }
    invisible(length(dusur))
  }
}

# Kimlik -> damga eşlemesi (verilen sırayla, adlı karakter vektörü).
history_stamps <- function(chat_ids, chats, stamp_fn) {
  vapply(chat_ids, function(id) stamp_fn(chats[[id]]), character(1))
}

# Verilen kimliklerin tümü güncel damgalarıyla önbellekte mi?
history_all_cached <- function(chat_ids, chats, cache, stamp_fn) {
  !length(history_ids_needing_fetch(chat_ids, chats, cache, stamp_fn))
}

# Açılış hazırlığı için geçmiş satırlarını mevcut açık (explicit) işçi
# sınırında okur: DB beklemesi ana olay döngüsünde olmaz ve sorgu süre
# bütçesiyle sınırlıdır (mergen_bounded_db_fetch_raw). İşçiye yalnızca SQL
# metni, tam sayı parametreler ve skaler yapılandırma gider; normalizasyon ve
# biçimlendirme ana süreçte tek biçimlendiriciyle yapılır. Kimlik yetkisi SQL
# içindedir (c.UserID = ? ve IsDeleted = 0).
history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL) {
  ids <- unique(as.character(chat_ids %||% character()))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  sayisal <- suppressWarnings(as.integer(ids))
  uid <- suppressWarnings(as.integer(user_id[1]))
  if (!length(ids) || anyNA(sayisal) || length(uid) != 1L || is.na(uid) || uid <= 0L) {
    return(promises::promise_reject(simpleError("Geçmiş hazırlığı için geçerli kimlik yok.")))
  }
  yapilandirma <- mergen_startup_db_worker_config()
  gecmis_sql <- db_history_rows_query_sql(paste(rep("?", length(ids)), collapse = ", "), scoped = TRUE)
  gecmis_parametreler <- c(as.list(sayisal), list(uid))
  gecmis_dsn <- yapilandirma$dsn
  gecmis_kodlama <- yapilandirma$encoding
  gecmis_ad_kodlama <- yapilandirma$name_encoding
  gecmis_login <- yapilandirma$login_timeout
  gecmis_sure <- yapilandirma$query_timeout
  ham <- tracked_future_promise(
    task_fn = function() {
      mergen_bounded_db_fetch_raw(gecmis_sql, gecmis_parametreler, gecmis_dsn, gecmis_kodlama,
                                  gecmis_ad_kodlama, gecmis_login, gecmis_sure)
    },
    task_type = "history_rows_prepare",
    session_token = session_token,
    dependency_mode = "explicit",
    globals = list(
      gecmis_sql = gecmis_sql, gecmis_parametreler = gecmis_parametreler,
      gecmis_dsn = gecmis_dsn, gecmis_kodlama = gecmis_kodlama,
      gecmis_ad_kodlama = gecmis_ad_kodlama, gecmis_login = gecmis_login,
      gecmis_sure = gecmis_sure, mergen_bounded_db_fetch_raw = mergen_bounded_db_fetch_raw
    ),
    packages = c("DBI")
  )
  promises::then(ham, onFulfilled = function(cerceve) load_history_rows_batch(ids, user_id = uid, result = cerceve))
}

# Açılış hazırlığı: eksik kimlikler işçide okunur, sonuç yalnızca gönderimdeki
# önbellek nesli ve sahip hâlâ geçerliyse gönderim anındaki damgalarla yazılır
# (eski sonuç yeni sahibe/nesle yazılamaz). Sonuç bildir(TRUE/FALSE) ile tam
# bir kez bildirilir; okuma hatası günlüğe maskelenmiş yazılır.
history_prepare_rows_async <- function(session, ids, damgalar, uid, isitma, resolve_uid,
                                       messages_cache, yayin_sayaci, bildir) {
  nesil <- isitma$nesil
  gecerli <- function() !isTRUE(session$isClosed()) && identical(isitma$nesil, nesil) &&
    identical(shiny::isolate(resolve_uid()), uid)
  okuma <- tryCatch(history_rows_worker_promise(ids, uid, session$token),
                    error = function(e) promises::promise_reject(e))
  promises::then(okuma, onFulfilled = function(sonuc) {
    if (!gecerli()) return(NULL)
    shiny::isolate({
      cache <- messages_cache()
      okunan <- intersect(ids, names(sonuc))
      for (id in okunan) {
        cache[[id]] <- list(rows = if (is.list(sonuc[[id]])) sonuc[[id]] else list(),
                            stamp = damgalar[[id]])
      }
      messages_cache(cache)
      isitma$etkin <- TRUE
      yayin_sayaci(yayin_sayaci() + 1)
      bildir(length(okunan) == length(ids))
    })
    NULL
  }, onRejected = function(e) {
    if (!gecerli()) return(NULL)
    cat(sprintf("[HISTORY] açılış hazırlığı okunamadı: %s\n", redacted_condition_message(e)))
    shiny::isolate(bildir(FALSE))
    NULL
  })
}

# Partiler later ile ertelenir. is_current() FALSE dönerse (önbellek
# geçersiz kılındı, tarih aralığı/sahip değişti) parti İŞLENMEZ: eski bir
# planın sonucu yeni önbelleğe yazılamaz. Bir partinin hatası zinciri kırmaz;
# on_complete her durumda tam bir kez çağrılır ve (argüman alıyorsa) tüm
# güncel partilerin başarılı olup olmadığını alır.
historyBackgroundWarm <- function(session, chat_ids, chats, ensure_history_cache,
                                  batch_size = 120L, delay_sec = 0.35,
                                  on_complete = NULL, is_current = NULL) {
  if (!length(chat_ids)) return(invisible(NULL))

  batches <- split(chat_ids, ceiling(seq_along(chat_ids) / batch_size))
  remaining <- length(batches)
  basarili <- TRUE

  for (i in seq_along(batches)) {
    local({
      batch <- batches[[i]]
      wait <- i * delay_sec

      later::later(function() {
        if (!session$isClosed()) {
          shiny::withReactiveDomain(session, {
            shiny::isolate({
              guncel <- !is.function(is_current) || isTRUE(is_current())
              if (guncel) {
                sonuc <- tryCatch(ensure_history_cache(batch, chats), error = function(e) {
                  cat(sprintf("[HISTORY] arka plan partisi okunamadı: %s\n", redacted_condition_message(e)))
                  FALSE
                })
                if (isFALSE(sonuc)) basarili <<- FALSE
              } else {
                basarili <<- FALSE
              }
              remaining <<- remaining - 1L

              if (remaining <= 0L && is.function(on_complete)) {
                if (length(formals(on_complete))) on_complete(basarili) else on_complete()
              }
            })
          })
        }
      }, delay = wait)
    })
  }

  invisible(TRUE)
}