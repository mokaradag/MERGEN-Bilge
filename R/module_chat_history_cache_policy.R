# ==============================================================================
# Dosya Yolu: R/module_chat_history_cache_policy.R
# Açıklama: Söyleşi Geçmişi önbellek politikası yardımcıları: etkinliğe göre
#           sıralama, açık geçersizleştirmede yeniden okuma izni, yerel başlık
#           işareti ve TTL yeniden doğrulaması. Saf yardımcılardır; reaktif
#           durum module_chat_history.R'de kalır.
# ==============================================================================

# Kimlikleri etkinlik zamanına (son mesaj, yoksa oluşturma) göre yeni önce
# sıralar; eşitlikte ve zamanı olmayanlarda girdi sırası korunur (kararlı).
history_ids_by_activity <- function(chat_ids, chats) {
  ids <- as.character(chat_ids %||% character())
  if (length(ids) < 2L) return(ids)
  zaman <- vapply(ids, function(id) {
    s <- chats[[id]]
    v <- mergen_chat_activity_seconds(s$last_message_timestamp %||% s$timestamp)
    if (is.finite(v)) v else -Inf
  }, numeric(1))
  ids[order(-zaman, seq_along(ids))]
}

# Açık geçersizleştirme (önbellekten düşürme ya da TTL yeniden doğrulaması)
# aynı ısıtma zincirinde yeniden okumaya izin verir: deneme kimliği (zincir
# damgası) ve plan üyeliği düşer. Damgası değişmeyen BAŞARISIZ okuma bu yoldan
# geçmez; aynı damgada döngüye girmez.
history_allow_reread <- function(isitma, chat_ids) {
  ids <- as.character(chat_ids %||% character())
  if (!is.environment(isitma) || !length(ids)) return(invisible(NULL))
  isitma$zincir <- isitma$zincir[setdiff(names(isitma$zincir), ids)]
  isitma$planli <- setdiff(isitma$planli, ids)
  invisible(NULL)
}

# Önbellekteki satırların liste başlığı okumadan sonra yerelde değiştiyse
# kalıcı "baslik_yerel" işareti konur (başlık özgün değerine dönse de tablo
# güncel liste başlığını gösterir). Değişiklik yoksa önbellek aynen döner.
history_mark_local_titles <- function(cache, chats) {
  for (id in intersect(names(cache), names(chats %||% list()))) {
    kayit <- cache[[id]]
    if (is.null(kayit$liste_baslik) || isTRUE(kayit$baslik_yerel)) next
    if (!identical(chats[[id]]$title, kayit$liste_baslik)) {
      kayit$baslik_yerel <- TRUE
      cache[[id]] <- kayit
    }
  }
  cache
}

# Yeniden doğrulama: verilen kimliklerin okuma zamanı `ttl_sn`'den eski (ya da
# saat geri alındığı için gelecekte/eksik) kayıtlarının damgası düşürülür;
# satırlar korunur, senkronizasyon onları yeniden okur. Taze kayıtlar dokunulmaz.
history_mark_stale_for_revalidation <- function(cache, ids, ttl_sn = 60, simdi = Sys.time()) {
  ttl <- suppressWarnings(as.numeric(ttl_sn)[1])
  if (!length(cache) || !length(ids) || length(ttl) != 1L || is.na(ttl)) return(cache)
  temizlenen <- character()
  for (id in intersect(as.character(ids), names(cache))) {
    kayit <- cache[[id]]
    if (identical(id, "current_chat") || is.null(kayit) || is.null(kayit$stamp)) next
    yas <- if (inherits(kayit$okuma, "POSIXt")) as.numeric(difftime(simdi, kayit$okuma, units = "secs")) else NA_real_
    if (is.na(yas) || yas < 0 || yas > ttl) {
      kayit["stamp"] <- list(NULL)
      cache[[id]] <- kayit
      temizlenen <- c(temizlenen, id)
    }
  }
  # Damgası gerçekten düşürülen kimlikler çağırana bildirilir.
  attr(cache, "temizlenen") <- temizlenen
  cache
}
