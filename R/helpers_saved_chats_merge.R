# ==============================================================================
# Dosya Yolu: R/helpers_saved_chats_merge.R
# Açıklama: Kayıtlı söyleşi listesinin arka plan tam liste birleştirmesi ve
#           silinenler (tombstone) kümesi yardımcıları. Ana süreçte çalışır;
#           işçi sözleşmesine (helpers_startup_chat_preview.R) dahil değildir.
#           Etkinlik zamanları helpers_chat_message_formatting.R içindeki
#           mergen_chat_activity_seconds ile aynı saat düzleminde karşılaştırılır.
# ==============================================================================

# Arka plan tam listesi gönderimden SONRA yerelde yapılan değişiklikleri ezmez:
# yerelde eklenen söyleşiler başa eklenir, yerelde silinenler geri gelmez.
# DB'de de bulunan söyleşide yalnızca yerelde DEĞİŞEN alanlar uygulanır (ör. ad
# değişimi DB'nin daha yeni sayı/zamanını ezmez); etkinliği yerelde ilerleyen
# söyleşi başa taşınır. Yerel durum değişmediyse DB sonucu aynen uygulanır.
# Gönderim anında var olup DB sonucunda olmayan söyleşi (başka oturumda
# silindi) yerel değişikliği olsa da geri getirilmez; yalnızca gönderimden
# SONRA yerelde açılan söyleşiler korunur. Etkinlik (mesaj sayısı, sayılar
# eşitse zaman) DB'de ileride ise etkinlik alanları DB'den kalır; zamanlar
# mergen_chat_activity_seconds ile aynı saat düzlemine çevrilip karşılaştırılır.
# Hidrasyonla gelen başlık yalnızca DB okumasından (db_okuma_zamani) SONRA
# okunduysa korunur. DB'de de olan söyleşinin kayıtsız yerel mesajları her
# durumda (kısayol dahil) taşınır ve açılışta kapsamlı yeniden okuma istenir.
# (Silme/Tümünü Temizle sonrası sonuç çağıran tarafından hiç uygulanmaz.)
# silinenler: bu oturumda DB'de gerçekten silinen kimlikler (anlık görüntüde
# olmasalar da); DB sonucundan her durumda önce çıkarılır, kısayol dahil.
mergen_saved_chats_merge_newer <- function(db_chats, dispatch_snapshot, current, silinenler = character(),
                                           db_okuma_zamani = NULL) {
  db_chats <- db_chats %||% list()
  silinenler <- as.character(silinenler %||% character())
  if (length(silinenler) && length(names(db_chats))) db_chats <- db_chats[!(names(db_chats) %in% silinenler)]
  dispatch_snapshot <- dispatch_snapshot %||% list()
  current <- current %||% list()
  if (identical(current, dispatch_snapshot)) {
    return(mergen_saved_chats_carry_unsaved(db_chats, current))
  }
  silinen <- setdiff(names(dispatch_snapshot), names(current))
  birlesik <- db_chats[setdiff(names(db_chats), silinen)]
  degisen <- Filter(function(k) !identical(current[[k]], dispatch_snapshot[[k]]), names(current))
  etkinlik_alanlari <- c("last_message_timestamp", "message_count")
  sayi <- function(x) suppressWarnings(as.integer(x %||% NA_integer_)[1])
  etkin <- character()
  eksik <- function(x) is.null(x) || length(x) == 0L || is.na(x[1])
  okuma_sn <- suppressWarnings(as.numeric(db_okuma_zamani %||% NA_real_)[1])
  for (k in intersect(degisen, names(birlesik))) {
    once <- dispatch_snapshot[[k]]
    db_sayi <- sayi(birlesik[[k]]$message_count)
    yerel_sayi <- sayi(current[[k]]$message_count)
    # Hidrasyon başlığı DB okumasından önceyse DB'nin başlığı daha tazedir.
    hidrate_sn <- suppressWarnings(as.numeric(current[[k]]$hidrate_zamani %||% NA_real_)[1])
    yerel_hidrate <- isTRUE(current[[k]]$hidrate_edildi) && !isTRUE(current[[k]]$baslik_yerel_degisti) &&
      !isTRUE(hidrate_sn > okuma_sn)
    yerel_zaman <- current[[k]]$last_message_timestamp
    db_zaman <- birlesik[[k]]$last_message_timestamp
    yerel_sn <- mergen_chat_activity_seconds(yerel_zaman)
    db_sn <- mergen_chat_activity_seconds(db_zaman)
    esit_sayi <- isTRUE(yerel_sayi == db_sayi)
    # Başka oturum daha sonra mesaj eklediyse (sayı büyük ya da sayılar eşitken
    # zaman daha yeni) DB'nin sayı/zaman çifti daha yenidir.
    db_ileride <- isTRUE(db_sayi > yerel_sayi) || (esit_sayi && isTRUE(db_sn > yerel_sn))
    yerel_ileride <- isTRUE(yerel_sayi > db_sayi) || (esit_sayi && isTRUE(yerel_sn > db_sn))
    if (is.null(once)) {
      # Gönderimden sonra yerelde açılan/hidrate edilen söyleşi: DB girdisi
      # TABAN kalır (detay okuyucu etkinlik zamanı taşımayabilir; eksik alan
      # DB'nin zamanını silmez). Yerel etkinlik DB'yi geçtiyse başa taşınır.
      taban <- birlesik[[k]]
      for (alan in names(current[[k]])) {
        deger <- current[[k]][[alan]]
        if (eksik(deger) || (alan %in% etkinlik_alanlari && !yerel_ileride)) next
        if (identical(alan, "title") && yerel_hidrate) next
        taban[alan] <- list(deger)
      }
      if (yerel_ileride) etkin <- c(etkin, k)
      # Yerelde mesaj yazıldı ve DB de ayrıca okundu: eşit sayı içerik eşitliği
      # değildir (başka sekmenin mesajı eksik olabilir). Önbellek korunur, yeniden
      # açılışta kapsamlı bir yeniden okuma istenir.
      if (!eksik(yerel_zaman) && !identical(yerel_zaman, db_zaman)) {
        taban$transkript_yenile <- TRUE
      }
      birlesik[[k]] <- taban
      next
    }
    for (alan in names(current[[k]])) {
      if (alan %in% etkinlik_alanlari && db_ileride) next
      if (identical(alan, "title") && yerel_hidrate) next
      if (!identical(current[[k]][[alan]], once[[alan]])) birlesik[[k]][alan] <- list(current[[k]][[alan]])
    }
    # Gönderimden sonra hem DB hem yerel etkinlik ilerlediyse transkript iki
    # kaynağın birleşimidir; sayı eşitliği tam olduğunu kanıtlamaz.
    once_sayi <- sayi(once$message_count)
    if (isTRUE(db_sayi > once_sayi) && isTRUE(yerel_sayi > once_sayi)) {
      birlesik[[k]]$transkript_yenile <- TRUE
    }
    # DB bu oturumun güncellemesini zaten içeriyorsa DB sırası korunur; yalnızca
    # yerel etkinlik DB'nin önündeyse söyleşi başa taşınır.
    if (yerel_ileride) {
      etkin <- c(etkin, k)
    }
  }
  # Yalnızca gönderimden SONRA yerelde oluşturulan söyleşiler korunur; başka
  # oturumda silinmiş ama bu oturumda yalnızca hidrate edilmiş (açılmış) kayıt
  # geri gelmez. Oluşturma kaynak kanıtlıdır (yerel_olusturuldu = yerel oluşturma
  # anı): yerelde oluşturulup sonra açılan söyleşi de korunur; ancak DB okuması
  # oluşturmadan SONRA başladıysa listede olmaması silme kanıtıdır (geri gelmez).
  yerel_olusturma <- function(k) {
    an <- suppressWarnings(as.numeric(current[[k]]$yerel_olusturuldu %||% NA_real_)[1])
    is.finite(an) && !isTRUE(an < okuma_sn)
  }
  yerel_yeni <- Filter(
    function(k) yerel_olusturma(k) || (is.null(current[[k]]$yerel_olusturuldu) && !isTRUE(current[[k]]$hidrate_edildi)),
    setdiff(setdiff(degisen, names(birlesik)), names(dispatch_snapshot))
  )
  sonuc <- c(current[yerel_yeni], birlesik[etkin], birlesik[setdiff(names(birlesik), etkin)])
  if (length(sonuc) > 1L && (length(yerel_yeni) > 0L || length(etkin) > 0L)) {
    # SQL ile aynı sıra: etkinlik zamanı, sonra oluşturma zamanı (yeni önce);
    # ikisi de eşitse girdi sırası korunur.
    # Anahtarlar toplu dönüştürülür (öğe başına ayrıştırma yapılmaz).
    anahtar <- function(x) { v <- mergen_chat_activity_seconds_vec(x); v[!is.finite(v)] <- -Inf; v }
    ts_deger <- anahtar(lapply(sonuc, function(s) {
      if (!eksik(s$last_message_timestamp)) s$last_message_timestamp else s$timestamp
    }))
    olusturma <- anahtar(lapply(sonuc, function(s) s$timestamp))
    if (any(is.finite(ts_deger))) sonuc <- sonuc[order(-ts_deger, -olusturma, seq_along(sonuc))]
  }
  mergen_saved_chats_carry_unsaved(sonuc, current)
}

# Sonuçtaki söyleşinin yerel önbelleğinde kayıtsız (DB'ye yazılamamış) mesaj
# varsa yerel transkript korunur ve açılışta kapsamlı yeniden okuma istenir;
# hidrasyon uzlaştırması kayıtsız mesajı konumuyla geri ekler.
mergen_saved_chats_carry_unsaved <- function(sonuc, current) {
  for (k in intersect(names(sonuc), names(current))) {
    yerel <- current[[k]]$messages
    if (!is.list(yerel) || !length(yerel)) next
    if (!any(vapply(yerel, mergen_chat_message_unsaved, logical(1)))) next
    # Eşitlik yalnızca kopyayı atlar; yeniden okuma işareti her durumda konur.
    if (!identical(sonuc[[k]]$messages, yerel)) sonuc[[k]]$messages <- yerel
    sonuc[[k]]$transkript_yenile <- TRUE
    # Kayıtsız yerel mesaj DB'nin son etkinliğinden yeniyse etkinlik zamanı korunur.
    yerel_zaman <- current[[k]]$last_message_timestamp
    yerel_sn <- mergen_chat_activity_seconds(yerel_zaman)
    db_sn <- mergen_chat_activity_seconds(sonuc[[k]]$last_message_timestamp)
    if (is.finite(yerel_sn) && (!is.finite(db_sn) || yerel_sn > db_sn)) {
      sonuc[[k]]$last_message_timestamp <- yerel_zaman
    }
  }
  sonuc
}

# Söyleşinin DB'de olmadığı doğrulandı (onaylı silme ya da hidrasyonda kayıt
# yok): kanonik kimlik oturumun silinenler kümesine eklenir; süren tam liste
# birleştirmesi onu geri getiremez. Başarısız okuma bunu ÇAĞIRMAZ.
mergen_saved_chats_mark_deleted <- function(session, chat_id) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  kimlik <- mergen_canonical_user_id(chat_id)
  if (!is.environment(ud) || !isTRUE(kimlik > 0L)) return(invisible(FALSE))
  ud$saved_chats_silinenler <- union(ud$saved_chats_silinenler %||% character(), as.character(kimlik))
  invisible(TRUE)
}

# Oturumun silinenler kümesindeki söyleşiler listeden çıkarılır (ön izleme ve
# tam liste aynı kuralı kullanır: doğrulanmış silme geri getirilmez).
mergen_saved_chats_drop_deleted <- function(chats, session) {
  silinenler <- tryCatch(as.character(session$userData$saved_chats_silinenler %||% character()),
                         error = function(e) character())
  if (!length(silinenler) || !length(names(chats))) return(chats)
  chats[!(names(chats) %in% silinenler)]
}

# Önbellek anahtarı kanonik kimliktir ("007" -> "7"); kimlik olmayan değer aynen döner.
mergen_saved_chats_canonical_key <- function(chat_id) {
  kimlik <- mergen_canonical_user_id(chat_id)
  if (isTRUE(kimlik > 0L)) as.character(kimlik) else chat_id
}

# Okuma hatasında gösterilebilecek (boş olmayan) önbellek transkripti var mı?
mergen_saved_chats_has_transcript <- function(chat) {
  is.list(chat) && is.list(chat$messages) && length(chat$messages) > 0L
}

# Maskelenmiş, fırlatmayan DB uyarısı (log katmanı yüklenmemiş yalıtık testte
# yalnızca hata sınıfı yazılır).
mergen_saved_chats_warn <- function(etiket, e) {
  if (exists("mergen_db_error_warn", mode = "function", inherits = TRUE)) return(mergen_db_error_warn(etiket, e))
  try(warning(sprintf("%s: %s", etiket, class(e)[1]), call. = FALSE), silent = TRUE)
  invisible(NULL)
}

# Silme DB hatası oturumu kapatmaz: maskelenmiş uyarı yazılır ve NA döner
# (çağıran doğrulanamayan silme yoluna düşer).
mergen_saved_chats_delete_rows <- function(delete_fn, chat_id, user_id) {
  tryCatch(delete_fn(chat_id, user_id), error = function(e) {
    mergen_saved_chats_warn(sprintf("[SAVED_CHATS] Söyleşi silinemedi (ChatID: %s)", chat_id), e)
    NA_integer_
  })
}

# Beğeni durumu söyleşi açılışında okunur; okuma hatası açılışı kesmez (Kayıtlı
# Söyleşiler ve Görsel Galerisi ortak yolu): beğeni durumu boş kalır, uyarı yazılır.
# oku: çağıranın çözdüğü okuyucu (varsayılan load_feedback_from_db).
mergen_saved_chats_load_feedback <- function(user_id, oku = load_feedback_from_db) {
  tryCatch(oku(user_id), error = function(e) {
    mergen_saved_chats_warn("[SAVED_CHATS] Beğeni durumu okunamadı", e)
    list(liked = character(0), disliked = character(0))
  })
}

# Etkin söyleşi silinince/temizlenince süren istek (ör. görsel) durdurulur:
# sahibi kalmayan istek gönderimi kilitli tutmaz, geç sonucu uygulanmaz.
# Durdurma yolu sohbet girdisi gözlemcisinin Durdur düğmesiyle aynıdır.
mergen_saved_chats_stop_active_request <- function(session) {
  durdur <- tryCatch(session$userData$mergen_etkin_istegi_durdur, error = function(e) NULL)
  if (is.function(durdur)) durdur()
  invisible(NULL)
}

# Etkin söyleşi kimliği verilen söyleşiyle kanonik olarak aynı mı ("007" = "7")?
mergen_saved_chats_is_active <- function(etkin_id, chat_id) {
  etkin <- mergen_canonical_user_id(if (length(etkin_id) == 1L) as.character(etkin_id) else NULL)
  isTRUE(etkin > 0L) && identical(etkin, mergen_canonical_user_id(as.character(chat_id)))
}
