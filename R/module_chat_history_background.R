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
# isitma verilmişse her çağrı (söyleşi önbellekte olmasa da) ilgili sürümü
# artırır (kimliksizse tüm söyleşilerinkini): süren eşzamansız hazırlığın eski
# sonucu düşürülen söyleşiye yazılamaz; ısıtma nesline dokunulmaz.
history_cache_dropper <- function(messages_cache, yayin_sayaci = NULL, isitma = NULL) {
  function(chat_ids = NULL) {
    if (is.environment(isitma)) {
      if (is.null(chat_ids)) isitma$tum_dusurme <- (isitma$tum_dusurme %||% 0L) + 1L
      else history_touch(isitma, chat_ids)
    }
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

# Söyleşi başına önbellek yazım sürümü: eşzamanlı okuma her yazımda/silmede
# ve önbellek düşürme her çağrıda ilgili kimliğin sürümünü artırır. Süren
# eşzamansız hazırlık yalnızca gönderimden beri sürümü değişmeyen kimlikleri
# yazar (daha yeni önbellek kaydı ya da düşürme eski sonuçla ezilmez). Isıtma
# nesline dokunmaz: ilgisiz arka plan ısıtması iptal edilmez.
history_touch <- function(isitma, chat_ids) {
  ids <- unique(as.character(chat_ids %||% character()))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  if (length(ids)) isitma$surum[ids] <- history_versions(isitma, ids, tum = FALSE) + 1L
  invisible(NULL)
}

# tum = TRUE: kimliksiz (tümü) düşürme sayacı da eklenir; o artınca tüm
# söyleşilerin sürümü değişmiş sayılır.
history_versions <- function(isitma, chat_ids, tum = TRUE) {
  surum <- unname(isitma$surum[as.character(chat_ids)])
  surum[is.na(surum)] <- 0L
  if (isTRUE(tum)) surum + (isitma$tum_dusurme %||% 0L) else surum
}

# Kimlik -> damga eşlemesi (verilen sırayla, adlı karakter vektörü).
history_stamps <- function(chat_ids, chats, stamp_fn) {
  vapply(chat_ids, function(id) stamp_fn(chats[[id]]), character(1))
}

# Verilen kimliklerin tümü güncel damgalarıyla önbellekte mi?
history_all_cached <- function(chat_ids, chats, cache, stamp_fn) {
  !length(history_ids_needing_fetch(chat_ids, chats, cache, stamp_fn))
}

# Hazırlık sonucunu bildiren işlev: sonuç gönderilen kimliklerden değil,
# GÜNCEL ilk sayfanın (en yeni 60 söyleşi) önbellek durumundan türetilir.
# Arada eklenen söyleşi eksikse "kısmen", silinen söyleşi eksik sayılmaz.
history_first_page_notifier <- function(bildir, kimlikler_fn, guncel_sohbetler, messages_cache,
                                        stamp_fn, sayfa = 60L) {
  function(...) {
    bildir(history_all_cached(utils::head(kimlikler_fn(), sayfa), shiny::isolate(guncel_sohbetler()),
                              shiny::isolate(messages_cache()), stamp_fn))
  }
}

# Açılış hazırlığı için geçmiş satırlarını mevcut açık (explicit) işçi
# sınırında okur: DB beklemesi ana olay döngüsünde olmaz ve sorgu süre
# bütçesiyle sınırlıdır (mergen_bounded_db_fetch_raw). İşçiye yalnızca SQL
# metni, tam sayı parametreler ve skaler yapılandırma gider; normalizasyon ve
# biçimlendirme ana süreçte tek biçimlendiriciyle yapılır. Kimlik yetkisi SQL
# içindedir (c.UserID = ? ve IsDeleted = 0).
history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, gecerli = NULL) {
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
      veri <- mergen_bounded_db_fetch_raw(gecmis_sql, gecmis_parametreler, gecmis_dsn, gecmis_kodlama,
                                          gecmis_ad_kodlama, gecmis_login, gecmis_sure)
      attr(veri, "mergen_okuma_zamani") <- Sys.time()
      veri
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
  promises::then(ham, onFulfilled = function(cerceve) history_rows_format_staged(ids, uid, cerceve, gecerli = gecerli))
}

# Yeniden doğrulama: verilen kimliklerin okuma zamanı `ttl_sn`'den eski (ya da
# saat geri alındığı için gelecekte/eksik) kayıtlarının damgası düşürülür;
# satırlar korunur, senkronizasyon onları yeniden okur. Taze kayıtlar dokunulmaz.
history_mark_stale_for_revalidation <- function(cache, ids, ttl_sn = 60, simdi = Sys.time()) {
  ttl <- suppressWarnings(as.numeric(ttl_sn)[1])
  if (!length(cache) || !length(ids) || length(ttl) != 1L || is.na(ttl)) return(cache)
  for (id in intersect(as.character(ids), names(cache))) {
    kayit <- cache[[id]]
    if (identical(id, "current_chat") || is.null(kayit) || is.null(kayit$stamp)) next
    yas <- if (inherits(kayit$okuma, "POSIXt")) as.numeric(difftime(simdi, kayit$okuma, units = "secs")) else NA_real_
    if (is.na(yas) || yas < 0 || yas > ttl) {
      kayit["stamp"] <- list(NULL)
      cache[[id]] <- kayit
    }
  }
  cache
}

# Elle yenilemenin bitiş bildirimi: hazır-olmayı yayımlar ve kullanıcıya
# sonucu (tam/kısmen) yeni satırlar yayımlandıktan sonra gösterir.
history_refresh_notifier <- function(session, hazir_bildir, bildir_toast,
                                     tam_mesaj = "Geçmiş tablosu yenilendi.",
                                     kismen_mesaj = "Geçmiş tablosu kısmen yenilendi; okunamayan söyleşiler yeniden denenecek.") {
  function(basarili = TRUE) {
    hazir_bildir(basarili)
    if (isTRUE(basarili)) bildir_toast(session, tam_mesaj, "info")
    else bildir_toast(session, kismen_mesaj, "warning")
  }
}

# Geçmiş hazırlığı günlüğü: paylaşılan logger (dosya + redaksiyon hattı)
# kullanılır; logger yüklenmemiş izole bağlamda konsola düşer.
.history_log_warn <- function(msg) {
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    # logger glue çözümlemesine takılmaması için süslü parantezler temizlenir.
    log_warn(gsub("[{}]", "", msg))
  } else {
    cat(msg, "\n", sep = "")
  }
  invisible(NULL)
}

# Büyük geçmiş sonucu (söyleşi sayısı satır sayısını sınırlamaz) ana olay
# döngüsünü tek geri çağrıda tutmaz: satırlar dilim satırlık parçalarla ayrı
# döngü turlarında aynı biçimlendiriciden geçer, arada diğer oturumlar ilerler.
# Biçimlendirme satır başınadır ve SQL sırası (ChatID, sıra) korunur; parçalara
# bölünen söyleşinin satırları sırayla birleştirilir. Sonuç tek seferlikle aynıdır.
# gecerli(): istek hâlâ güncel mi (sahip/nesil). Her dilimden önce sorulur;
# bayatlayan istemin kalan dilimleri olay döngüsünde biçimlendirilmez, söz
# NULL ile kapanır ve hazır-olma yayımlanmaz (çağıran geçerliliği yeniden denetler).
history_rows_format_staged <- function(ids, uid, cerceve, dilim = 500L, gecerli = NULL) {
  okuma_zamani <- attr(cerceve, "mergen_okuma_zamani")
  n <- if (is.data.frame(cerceve)) nrow(cerceve) else 0L
  if (n <= dilim) {
    sonuc <- load_history_rows_batch(ids, user_id = uid, result = cerceve)
    if (inherits(okuma_zamani, "POSIXt") && is.list(sonuc)) attr(sonuc, "mergen_okuma_zamani") <- okuma_zamani
    return(sonuc)
  }
  promises::promise(function(resolve, reject) {
    parcalar <- stats::setNames(rep(list(list()), length(ids)), ids)
    bas <- 1L
    adim <- function() {
      if (is.function(gecerli) && !isTRUE(gecerli())) {
        resolve(NULL)
        return(invisible(NULL))
      }
      tryCatch({
        son <- min(n, bas + dilim - 1L)
        parca <- cerceve[bas:son, , drop = FALSE]
        bicimli <- load_history_rows_batch(intersect(ids, as.character(parca$ChatID)),
                                           user_id = uid, result = parca)
        for (k in names(bicimli)) parcalar[[k]][[length(parcalar[[k]]) + 1L]] <<- bicimli[[k]]
        bas <<- son + 1L
        if (bas > n) {
          tam <- lapply(parcalar, function(p) if (length(p)) do.call(c, p) else list())
          if (inherits(okuma_zamani, "POSIXt")) attr(tam, "mergen_okuma_zamani") <- okuma_zamani
          resolve(tam)
        } else later::later(adim, 0)
      }, error = function(e) reject(e))
    }
    adim()
  })
}

# Açılış hazırlığı: eksik kimlikler işçide okunur, sonuç yalnızca gönderimdeki
# önbellek nesli ve sahip hâlâ geçerliyse gönderim anındaki damgalarla yazılır
# (eski sonuç yeni sahibe/nesle yazılamaz). Gönderimden beri eşzamanlı okuma
# ya da düşürmeyle sürümü değişen söyleşi YAZILMAZ: daha yeni kayıt korunur,
# düşürülen (ör. silinmiş görsel alıntılı) satırlar geri gelmez. Sonuç
# bildir(TRUE/FALSE) ile tam bir kez bildirilir: her kimlik ya bu sonuçla ya da
# daha yeni bir okumayla önbellekteyse "hazır"dır. Okuma hatası günlüğe
# maskelenmiş yazılır.
# guncel_sohbetler() + damga_fn: sonuç geldiğinde söyleşilerin GÜNCEL damgaları.
# Hazırlık sürerken damgası değişen (yeni mesaj alan) söyleşi eski damgayla
# yazılmaz ve "hazır" sayılmaz; güncel damgalı kaydı yoksa durum "kısmen"dir.
history_prepare_rows_async <- function(session, ids, damgalar, uid, isitma, resolve_uid,
                                       messages_cache, yayin_sayaci, bildir,
                                       guncel_sohbetler = NULL, damga_fn = NULL,
                                       liste_basliklar = NULL) {
  nesil <- isitma$nesil
  surumler <- history_versions(isitma, ids)
  gecerli <- function() !isTRUE(session$isClosed()) && identical(isitma$nesil, nesil) &&
    identical(shiny::isolate(resolve_uid()), uid)
  okuma <- tryCatch(history_rows_worker_promise(ids, uid, session$token, gecerli = gecerli),
                    error = function(e) promises::promise_reject(e))
  promises::then(okuma, onFulfilled = function(sonuc) {
    if (!gecerli()) return(NULL)
    shiny::isolate({
      cache <- messages_cache()
      simdiki <- if (is.function(guncel_sohbetler) && is.function(damga_fn)) {
        history_stamps(ids, guncel_sohbetler(), damga_fn)
      } else damgalar[ids]
      damga_ayni <- vapply(ids, function(id) identical(simdiki[[id]], damgalar[[id]]), logical(1))
      degismeyen <- ids[history_versions(isitma, ids) == surumler & damga_ayni]
      okunan <- intersect(degismeyen, names(sonuc))
      # TTL işçi DB okuma anından başlar; uzun kuyruk/yayın gecikmesi eski
      # alıntıyı taze göstermez.
      okuma_zamani <- attr(sonuc, "mergen_okuma_zamani")
      if (!inherits(okuma_zamani, "POSIXt")) okuma_zamani <- Sys.time()
      for (id in okunan) {
        cache[[id]] <- list(rows = if (is.list(sonuc[[id]])) sonuc[[id]] else list(),
                            stamp = damgalar[[id]], okuma = okuma_zamani,
                            liste_baslik = if (is.list(liste_basliklar)) liste_basliklar[[id]] else NULL)
      }
      history_touch(isitma, okunan)
      messages_cache(cache)
      # Arka plan hazırlığı sayfa etkinleştirmesi DEĞİLDİR (isitma$etkin'e
      # dokunulmaz): geçmiş açılmadıkça liste değişimleri olay döngüsünde
      # eşzamanlı okuma tetiklemez; bayat kayıtlar ilk ziyarette yenilenir.
      yayin_sayaci(yayin_sayaci() + 1)
      yenisi_var <- setdiff(ids, degismeyen)
      bildir(all(ids %in% okunan |
                   (ids %in% yenisi_var & vapply(ids, function(id) {
                     !is.null(cache[[id]]) && identical(cache[[id]]$stamp, simdiki[[id]])
                   }, logical(1)))))
    })
    NULL
  }, onRejected = function(e) {
    if (!gecerli()) return(NULL)
    .history_log_warn(sprintf("[HISTORY] açılış hazırlığı okunamadı: %s", mergen_db_error_log_summary(e)))
    shiny::isolate(bildir(FALSE))
    NULL
  })
}

# Partiler later ile zincirlenerek ertelenir: her parti TAMAMLANDIKTAN sonra
# sonraki parti delay_sec ile planlanır; böylece uzun süren bir parti kalan
# partilerin tümünü aynı olay döngüsü turunda art arda koşturmaz.
# is_current() FALSE dönerse (önbellek geçersiz kılındı, tarih aralığı/sahip
# değişti) kalan partiler İŞLENMEZ ve planlanmaz. Bir partinin hatası zinciri
# kırmaz; on_complete her durumda tam bir kez çağrılır.
historyBackgroundWarm <- function(session, chat_ids, chats, ensure_history_cache,
                                  batch_size = 120L, delay_sec = 0.35,
                                  on_complete = NULL, is_current = NULL) {
  if (!length(chat_ids)) return(invisible(NULL))

  batches <- split(chat_ids, ceiling(seq_along(chat_ids) / batch_size))
  toplam <- length(batches)
  basarili <- TRUE

  planla <- function(idx) {
    later::later(function() {
      if (isTRUE(session$isClosed())) return(invisible(NULL))
      shiny::withReactiveDomain(session, {
        shiny::isolate({
          guncel <- !is.function(is_current) || isTRUE(is_current())
          if (!guncel) {
            basarili <<- FALSE
            if (is.function(on_complete)) {
              if (length(formals(on_complete))) on_complete(basarili) else on_complete()
            }
            return(invisible(NULL))
          }
          sonuc <- tryCatch(ensure_history_cache(batches[[idx]], chats), error = function(e) {
            .history_log_warn(sprintf("[HISTORY] arka plan partisi okunamadı: %s", mergen_db_error_log_summary(e)))
            FALSE
          })
          if (isFALSE(sonuc)) basarili <<- FALSE

          if (idx < toplam) {
            planla(idx + 1L)
          } else if (is.function(on_complete)) {
            if (length(formals(on_complete))) on_complete(basarili) else on_complete()
          }
        })
      })
    }, delay = delay_sec)
  }

  planla(1L)
  invisible(TRUE)
}