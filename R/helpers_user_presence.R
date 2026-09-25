# ==============================================================================
# Dosya Yolu: R/helpers_user_presence.R
# Açıklama: Sistem Durumu "Çevrimiçi" sekmesi için kullanıcı varlığı (presence)
#           defteri. Canlı oturumlar R/module_performance.R'nin süreç-içi
#           defterinden (.mergen_active_sessions) okunur; kapanan oturumlar
#           24 saat boyunca ayrı bir defterde tutulur.
#
#           Çevrimiçi = uygulamaya bağlı oturumu olan ve son 3 dakikada nabız
#           görülen kullanıcı (nabız bağlı oturumda dakikada bir yazılır).
#           Veri süreç belleğindedir: yeniden başlatmada sıfırlanır ve birden
#           çok uygulama süreci varsa her süreç kendi oturumlarını görür.
#           Saf yardımcılardır; Shiny/DB/ağ erişimi yapmaz.
# ==============================================================================

mb_presence_windows <- function() {
  list(online = 180, recent = 900, history = 86400, stale = 1800, max_history = 1000L)
}

mb_presence_env <- function(name) {
  if (!exists(name, envir = globalenv(), inherits = FALSE)) {
    assign(name, new.env(parent = emptyenv()), envir = globalenv())
  }
  get(name, envir = globalenv(), inherits = FALSE)
}

# Oturumun kimlik bilgisinden tabloda gösterilecek alanlar (yalnız görünen ad,
# kullanıcı adı, sicil ve birim; token veya claim ham verisi saklanmaz).
mb_presence_profile <- function(session) {
  kimlik <- tryCatch(session$userData$user_identity, error = function(e) NULL)
  if (!is.list(kimlik)) kimlik <- list()
  al <- function(...) {
    for (anahtar in c(...)) {
      deger <- kimlik[[anahtar]]
      if (!is.null(deger) && length(deger) && !is.na(deger[1])) {
        deger <- trimws(enc2utf8(as.character(deger[1])))
        if (nzchar(deger)) return(deger)
      }
    }
    ""
  }
  list(full_name = al("full_name", "KaynakAdi"),
       username = al("username", "KullaniciAdi"),
       sicil = al("sicil", "Sicil"),
       department = al("department", "Departman"),
       mudurluk = al("mudurluk", "Mudurluk"))
}

mb_presence_uid <- function(x) {
  deger <- suppressWarnings(as.integer(x %||% 0L)[1])
  if (length(deger) != 1L || is.na(deger) || deger < 0L) 0L else deger
}

# Nabız kaydı: ilk bağlantı anı korunur, boş profil önceki dolu profili ezmez.
# Kimlik geçici olarak 0'a düşerse son bilinen kullanıcı korunur; oturum başka
# kullanıcıya geçtiyse önceki kullanıcının profili ve başlangıcı devralınmaz.
mb_presence_session_entry <- function(previous, user_id, profile, now = Sys.time()) {
  onceki <- mb_presence_uid(previous$user_id)
  yeni <- mb_presence_uid(user_id)
  if (yeni == 0L) yeni <- onceki
  if (onceki > 0L && yeni != onceki) previous <- NULL
  profil <- previous$profile %||% list()
  for (alan in names(profile)) {
    if (nzchar(profile[[alan]] %||% "")) profil[[alan]] <- profile[[alan]]
  }
  list(user_id = yeni, last_seen = now,
       started_at = previous$started_at %||% now, profile = profil)
}

# Oturumun nabzını yazar. Aynı Shiny oturumu başka kullanıcıya geçtiyse önceki
# kullanıcının oturumu bitmiş sayılır ve geçmişe ayrı anahtarla yazılır.
mb_presence_touch <- function(active_env, token, user_id, profile, now = Sys.time(),
                              history_env = mb_presence_env(".mergen_presence_history")) {
  anahtar <- as.character(token)[1]
  onceki <- if (exists(anahtar, envir = active_env, inherits = FALSE)) active_env[[anahtar]] else NULL
  eski_uid <- mb_presence_uid(onceki$user_id)
  yeni_uid <- mb_presence_uid(user_id)
  if (eski_uid > 0L && yeni_uid > 0L && yeni_uid != eski_uid) {
    mb_presence_record_end(paste0(anahtar, "#", eski_uid), onceki, ended_at = now,
                           history_env = history_env, now = now)
  }
  assign(anahtar, mb_presence_session_entry(onceki, user_id, profile, now), envir = active_env)
  invisible(active_env[[anahtar]])
}

# Budama bitiş anına değil GÜNCEL zamana göre yapılır; bayat oturum temizliği
# geçmiş bir bitiş anı verse de pencere geriye kaymaz.
mb_presence_record_end <- function(token, entry, ended_at = Sys.time(),
                                   history_env = mb_presence_env(".mergen_presence_history"),
                                   now = Sys.time()) {
  if (!is.list(entry) || is.null(entry$last_seen)) return(invisible(FALSE))
  entry$ended_at <- ended_at
  assign(as.character(token)[1], entry, envir = history_env)
  mb_presence_prune(history_env, now)
  invisible(TRUE)
}

mb_presence_prune <- function(history_env, now = Sys.time()) {
  pencere <- mb_presence_windows()
  anahtarlar <- ls(history_env, all.names = TRUE)
  if (!length(anahtarlar)) return(invisible(0L))
  bitis <- vapply(anahtarlar, function(k) {
    as.numeric(history_env[[k]]$ended_at %||% 0)
  }, numeric(1))
  eski <- anahtarlar[(as.numeric(now) - bitis) > pencere$history]
  fazla <- length(anahtarlar) - length(eski) - pencere$max_history
  if (fazla > 0L) {
    kalan <- setdiff(anahtarlar, eski)
    eski <- c(eski, kalan[order(bitis[kalan])][seq_len(fazla)])
  }
  if (length(eski)) rm(list = eski, envir = history_env)
  invisible(length(eski))
}

# Oturum başına satırlar: canlı defter + kapanmış oturum defteri.
mb_presence_session_rows <- function(active_env, history_env, now = Sys.time()) {
  pencere <- mb_presence_windows()
  satir <- function(e, bitti) {
    son <- as.numeric(e$last_seen %||% NA)
    bitis <- if (bitti) as.numeric(e$ended_at %||% son) else NA_real_
    yas <- as.numeric(now) - son
    if (!bitti && isTRUE(yas > pencere$stale)) {
      bitti <- TRUE
      bitis <- son
    }
    durum <- if (bitti) "ayrildi" else if (isTRUE(yas <= pencere$online)) "cevrimici" else "sessiz"
    p <- e$profile %||% list()
    data.frame(user_id = suppressWarnings(as.integer(e$user_id %||% 0L)),
               status = durum, started_at = as.numeric(e$started_at %||% son),
               last_seen = if (bitti) bitis else son,
               full_name = p$full_name %||% "", username = p$username %||% "",
               sicil = p$sicil %||% "", department = p$department %||% "",
               mudurluk = p$mudurluk %||% "", stringsAsFactors = FALSE)
  }
  topla <- function(env, bitti) {
    if (!is.environment(env)) return(list())
    lapply(ls(env, all.names = TRUE), function(k) {
      e <- tryCatch(env[[k]], error = function(err) NULL)
      if (is.list(e) && !is.null(e$last_seen)) satir(e, bitti) else NULL
    })
  }
  satirlar <- Filter(Negate(is.null), c(topla(active_env, FALSE), topla(history_env, TRUE)))
  if (!length(satirlar)) {
    return(data.frame(user_id = integer(0), status = character(0), started_at = numeric(0),
                      last_seen = numeric(0), full_name = character(0), username = character(0),
                      sicil = character(0), department = character(0), mudurluk = character(0),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, satirlar)
}

# Kullanıcı başına özet ve sayaçlar. Kimliği çözülmemiş (user_id = 0) oturumlar
# kullanıcı listesine girmez, yalnızca açık oturum sayısına katılır.
mb_presence_snapshot <- function(active_env = mb_presence_env(".mergen_active_sessions"),
                                 history_env = mb_presence_env(".mergen_presence_history"),
                                 now = Sys.time()) {
  pencere <- mb_presence_windows()
  # Oturum kapanmasa da 24 saatten eski geçmiş kayıtları bellekte kalmaz.
  if (is.environment(history_env)) mb_presence_prune(history_env, now)
  oturumlar <- mb_presence_session_rows(active_env, history_env, now)
  simdi <- as.numeric(now)
  oturumlar <- oturumlar[!is.na(oturumlar$last_seen) &
                           simdi - oturumlar$last_seen <= pencere$history, , drop = FALSE]
  acik <- sum(oturumlar$status != "ayrildi")
  kisiler <- oturumlar[!is.na(oturumlar$user_id) & oturumlar$user_id > 0L, , drop = FALSE]

  sira <- c(cevrimici = 1L, sessiz = 2L, ayrildi = 3L)
  kullanicilar <- lapply(split(kisiler, kisiler$user_id), function(u) {
    u <- u[order(-u$last_seen), , drop = FALSE]
    canli <- u[u$status != "ayrildi", , drop = FALSE]
    durum <- names(sira)[min(sira[u$status])]
    dolu <- function(alan) { v <- u[[alan]][nzchar(u[[alan]])]; if (length(v)) v[1] else "" }
    baslangic <- if (nrow(canli)) min(canli$started_at) else u$started_at[1]
    bitis <- if (nrow(canli)) simdi else u$last_seen[1]
    data.frame(user_id = u$user_id[1], status = durum, sessions = nrow(canli),
               started_at = baslangic, last_seen = max(u$last_seen),
               duration_secs = max(0, bitis - baslangic),
               full_name = dolu("full_name"), username = dolu("username"),
               sicil = dolu("sicil"), department = dolu("department"),
               mudurluk = dolu("mudurluk"), stringsAsFactors = FALSE)
  })
  kullanicilar <- if (length(kullanicilar)) do.call(rbind, kullanicilar) else NULL
  if (!is.null(kullanicilar)) {
    kullanicilar <- kullanicilar[order(sira[kullanicilar$status], -kullanicilar$last_seen), , drop = FALSE]
    rownames(kullanicilar) <- NULL
  }

  cevrimici <- if (is.null(kullanicilar)) 0L else sum(kullanicilar$status == "cevrimici")
  yakin <- if (is.null(kullanicilar)) 0L else sum(simdi - kullanicilar$last_seen <= pencere$recent)
  birimler <- if (is.null(kullanicilar)) character(0) else
    kullanicilar$department[kullanicilar$status == "cevrimici" & nzchar(kullanicilar$department)]
  list(
    generated_at = now,
    windows = pencere,
    metrics = list(online = as.integer(cevrimici), recent = as.integer(yakin),
                   day = if (is.null(kullanicilar)) 0L else nrow(kullanicilar),
                   open_sessions = as.integer(acik), departments = length(unique(birimler))),
    users = kullanicilar
  )
}

mb_presence_duration_label <- function(secs) {
  secs <- suppressWarnings(as.numeric(secs))
  if (!length(secs) || is.na(secs[1]) || secs[1] < 0) return("—")
  secs <- secs[1]
  if (secs < 60) return(sprintf("%d sn", as.integer(secs)))
  dk <- floor(secs / 60)
  if (dk < 60) return(sprintf("%d dk", as.integer(dk)))
  sprintf("%d sa %d dk", as.integer(dk %/% 60), as.integer(dk %% 60))
}

mb_presence_ago_label <- function(secs) {
  secs <- suppressWarnings(as.numeric(secs))
  if (!length(secs) || is.na(secs[1])) return("—")
  if (secs[1] < 60) return("şimdi")
  paste(mb_presence_duration_label(secs[1]), "önce")
}
