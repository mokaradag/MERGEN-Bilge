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
                  cat(sprintf("[HISTORY] arka plan partisi okunamadı: %s\n", conditionMessage(e)))
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