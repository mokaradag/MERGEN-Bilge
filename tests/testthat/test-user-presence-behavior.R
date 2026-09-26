# ==============================================================================
# Dosya Yolu: tests/testthat/test-user-presence-behavior.R
# Açıklama: Sistem Durumu "Çevrimiçi" sekmesinin varlık defteri
#           (R/helpers_user_presence.R), sekme UI'ı (R/module_health_presence.R)
#           ve performans modülünün nabız/oturum sonu kaydı davranış testleri.
#           Çevrimdışı ve deterministiktir; DB/SSO/ağ gerekmez.
# ==============================================================================

.presence_env <- function(with_ui = FALSE) {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_user_presence.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_user_presence_shared.R"), encoding = "UTF-8", local = env)
  if (with_ui) {
    testthat::skip_if_not_installed("shiny")
    suppressMessages(library(shiny))
    source(file.path(kok, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
    source(file.path(kok, "R", "helpers_sidebar_user_display.R"), encoding = "UTF-8", local = env)
    source(file.path(kok, "R", "module_health_presence.R"), encoding = "UTF-8", local = env)
  }
  env
}

.presence_fixture <- function(now) {
  aktif <- new.env(parent = emptyenv())
  gecmis <- new.env(parent = emptyenv())
  ad <- intToUtf8(c(0x41, 0x79, 0x15F, 0x65, 0x20, 0x59, 0x131, 0x6C, 0x6D, 0x61, 0x7A))
  aktif$t1 <- list(user_id = 5L, last_seen = now - 20, started_at = now - 3600,
                   profile = list(full_name = ad, username = "ayilmaz", sicil = "1234",
                                  department = "Bilgi", mudurluk = "Yazilim"))
  aktif$t2 <- list(user_id = 5L, last_seen = now - 50, started_at = now - 600, profile = list())
  aktif$t3 <- list(user_id = 0L, last_seen = now - 5, started_at = now - 5)
  aktif$t4 <- list(user_id = 7L, last_seen = now - 400, started_at = now - 900,
                   profile = list(full_name = "Sessiz Kullanici"))
  aktif$t5 <- list(user_id = 8L, last_seen = now - 4000, started_at = now - 5000,
                   profile = list(full_name = "Kopan Kullanici"))
  gecmis$t6 <- list(user_id = 9L, last_seen = now - 700, started_at = now - 4000,
                    ended_at = now - 700, profile = list(full_name = "Ayrilan", department = "Bilgi"))
  gecmis$t7 <- list(user_id = 11L, last_seen = now - 90000, started_at = now - 90000,
                    ended_at = now - 90000)
  list(aktif = aktif, gecmis = gecmis, ad = ad)
}

test_that("anlık görüntü çevrimiçi, sessiz ve ayrılan kullanıcıları doğru sınıflar", {
  env <- .presence_env()
  now <- as.POSIXct("2026-09-25 10:00:00", tz = "UTC")
  f <- .presence_fixture(now)
  s <- env$mb_presence_snapshot(f$aktif, f$gecmis, now)

  expect_identical(s$metrics$online, 1L)
  expect_identical(s$metrics$recent, 3L)            # 5 (çevrimiçi), 7 (sessiz), 9 (ayrıldı)
  expect_identical(s$metrics$day, 4L)               # 11 numaralı kayıt 24 saatten eski
  expect_identical(s$metrics$open_sessions, 4L)     # kimliksiz oturum dahil, kopan hariç
  expect_identical(s$metrics$departments, 1L)

  u <- s$users
  expect_identical(u$user_id, c(5L, 7L, 9L, 8L))   # ayrılanlar son görülmeye göre
  expect_identical(u$status, c("cevrimici", "sessiz", "ayrildi", "ayrildi"))
  expect_identical(u$sessions[1], 2L)
  expect_identical(u$full_name[1], f$ad)
  expect_identical(u$duration_secs[1], 3600)
  expect_false(0L %in% u$user_id)
})

test_that("boş defter sıfır sayaç ve boş liste döndürür", {
  env <- .presence_env()
  s <- env$mb_presence_snapshot(new.env(), new.env(), Sys.time())
  expect_identical(unlist(s$metrics), c(online = 0L, recent = 0L, day = 0L,
                                        open_sessions = 0L, departments = 0L))
  expect_null(s$users)
})

test_that("nabız kaydı ilk bağlantı anını ve dolu profil alanlarını korur", {
  env <- .presence_env()
  t0 <- as.POSIXct("2026-09-25 09:00:00", tz = "UTC")
  ilk <- env$mb_presence_session_entry(NULL, 5L, list(full_name = "Ad", sicil = ""), now = t0)
  sonra <- env$mb_presence_session_entry(ilk, 5L, list(full_name = "", sicil = "77"), now = t0 + 60)
  expect_identical(sonra$started_at, t0)
  expect_identical(sonra$last_seen, t0 + 60)
  expect_identical(sonra$profile$full_name, "Ad")
  expect_identical(sonra$profile$sicil, "77")
})

test_that("oturum başka kullanıcıya geçince profil ve başlangıç devralınmaz", {
  env <- .presence_env()
  t0 <- as.POSIXct("2026-09-25 09:00:00", tz = "UTC")
  a <- env$mb_presence_session_entry(NULL, 5L, list(full_name = "A Kisi", sicil = "11"), now = t0)
  # Kimlik geçici olarak 0'a düşerse son bilinen kullanıcı korunur.
  bos <- env$mb_presence_session_entry(a, 0L, list(full_name = "", sicil = ""), now = t0 + 30)
  expect_identical(bos$user_id, 5L)
  expect_identical(bos$profile$sicil, "11")

  b <- env$mb_presence_session_entry(bos, 6L, list(full_name = "B Kisi", sicil = ""), now = t0 + 60)
  expect_identical(b$user_id, 6L)
  expect_identical(b$started_at, t0 + 60)
  expect_identical(b$profile$full_name, "B Kisi")
  expect_null(b$profile$sicil)

  aktif <- new.env(parent = emptyenv())
  gecmis <- new.env(parent = emptyenv())
  env$mb_presence_touch(aktif, "tok", 5L, list(full_name = "A Kisi", sicil = "11"), now = t0, history_env = gecmis)
  env$mb_presence_touch(aktif, "tok", 6L, list(full_name = "B Kisi", sicil = ""), now = t0 + 60, history_env = gecmis)
  expect_identical(aktif$tok$user_id, 6L)
  expect_null(aktif$tok$profile$sicil)
  expect_identical(ls(gecmis), "tok#5")
  expect_identical(gecmis[["tok#5"]]$profile$sicil, "11")
  expect_identical(gecmis[["tok#5"]]$ended_at, t0 + 60)
})

test_that("geçmiş defter güncel zamana göre budanır", {
  env <- .presence_env()
  now <- as.POSIXct("2026-09-25 10:00:00", tz = "UTC")
  gecmis <- new.env(parent = emptyenv())
  gecmis$eski <- list(user_id = 1L, last_seen = now - 87000, ended_at = now - 87000)
  # Bayat oturum temizliği geçmiş bir bitiş anı verir; pencere geriye kaymaz.
  env$mb_presence_record_end("bayat", list(user_id = 2L, last_seen = now - 2000),
                             ended_at = now - 2000, history_env = gecmis, now = now)
  expect_identical(ls(gecmis), "bayat")

  # Hiç oturum kapanmasa da anlık görüntü eski kayıtları bellekten atar.
  gecmis$eski <- list(user_id = 1L, last_seen = now - 87000, ended_at = now - 87000)
  env$mb_presence_snapshot(new.env(), gecmis, now)
  expect_identical(ls(gecmis), "bayat")
})

test_that("oturum sonu kaydı 24 saat ile budanır, tavan pencere içindeki kullanıcıyı silmez", {
  env <- .presence_env()
  gecmis <- new.env(parent = emptyenv())
  now <- Sys.time()
  env$mb_presence_record_end("eski", list(user_id = 1L, last_seen = now - 90000),
                             ended_at = now - 90000, history_env = gecmis)
  env$mb_presence_record_end("yeni", list(user_id = 2L, last_seen = now - 10),
                             ended_at = now, history_env = gecmis)
  expect_identical(ls(gecmis), "yeni")
  expect_false(env$mb_presence_record_end("bos", NULL, history_env = gecmis))

  env$mb_presence_windows <- function() list(online = 180, recent = 900, history = 86400,
                                             stale = 1800, max_history = 2L, skew = 120)
  rm(list = ls(gecmis), envir = gecmis)
  # Farklı kullanıcılar 24 saat içindeyse tavan aşılsa da hiçbiri silinmez.
  for (i in 1:3) {
    env$mb_presence_record_end(paste0("k", i), list(user_id = i, last_seen = now),
                               ended_at = now - 10 + i, history_env = gecmis)
  }
  expect_identical(sort(ls(gecmis)), c("k1", "k2", "k3"))
  expect_identical(env$mb_presence_snapshot(new.env(), gecmis, now)$metrics$day, 3L)

  # Aynı kullanıcının eski kayıtları en son kayda sıkıştırılır; profil korunur.
  rm(list = ls(gecmis), envir = gecmis)
  env$mb_presence_record_end("a1", list(user_id = 4L, last_seen = now - 30, profile = list(sicil = "44")),
                             ended_at = now - 30, history_env = gecmis, now = now)
  env$mb_presence_record_end("a2", list(user_id = 4L, last_seen = now - 20, profile = list(sicil = "")),
                             ended_at = now - 20, history_env = gecmis, now = now)
  env$mb_presence_record_end("z", list(user_id = 0L, last_seen = now - 15),
                             ended_at = now - 15, history_env = gecmis, now = now)
  expect_identical(ls(gecmis), "a2")
  expect_identical(gecmis$a2$profile$sicil, "44")

  # Uzak gelecekteki (geçersiz) kayıt sıkıştırmada geçerli kaydın yerini almaz.
  rm(list = ls(gecmis), envir = gecmis)
  gecmis$gelecek <- list(user_id = 4L, last_seen = now, ended_at = now + 7200)
  gecmis$b1 <- list(user_id = 4L, last_seen = now - 40, ended_at = now - 40)
  gecmis$b2 <- list(user_id = 5L, last_seen = now - 30, ended_at = now - 30)
  env$mb_presence_prune(gecmis, now)
  expect_identical(sort(ls(gecmis)), c("b1", "b2"))
})

test_that("A->B->A->B geçişinde önceki oturumlar geçmişte ezilmez", {
  env <- .presence_env()
  t0 <- as.POSIXct("2026-09-25 09:00:00", tz = "UTC")
  aktif <- new.env(parent = emptyenv())
  gecmis <- new.env(parent = emptyenv())
  for (i in 0:3) {
    env$mb_presence_touch(aktif, "tok", if (i %% 2L) 6L else 5L, list(), now = t0 + i * 60,
                          history_env = gecmis)
  }
  expect_length(ls(gecmis), 3L)
  bitisler <- vapply(ls(gecmis), function(k) as.numeric(gecmis[[k]]$ended_at), numeric(1))
  expect_identical(sort(unname(bitisler)), as.numeric(t0) + c(60, 120, 180))
})

test_that("kimlik açıkça düşünce önceki kullanıcı nabızla çevrimiçi kalmaz", {
  env <- .presence_env()
  t0 <- as.POSIXct("2026-09-25 09:00:00", tz = "UTC")
  aktif <- new.env(parent = emptyenv())
  gecmis <- new.env(parent = emptyenv())
  env$mb_presence_touch(aktif, "tok", 5L, list(full_name = "A"), now = t0, history_env = gecmis)
  # Geçici 0 son bilinen kullanıcıyı korur.
  env$mb_presence_touch(aktif, "tok", 0L, list(), now = t0 + 30, history_env = gecmis)
  expect_identical(aktif$tok$user_id, 5L)
  # SSO süresi doldu: önceki oturum biter, sonraki nabızlar kullanıcıyı canlı tutmaz.
  env$mb_presence_touch(aktif, "tok", 0L, list(), now = t0 + 90, history_env = gecmis, auth_lost = TRUE)
  env$mb_presence_touch(aktif, "tok", 0L, list(), now = t0 + 150, history_env = gecmis, auth_lost = TRUE)
  expect_identical(aktif$tok$user_id, 0L)
  expect_identical(ls(gecmis), "tok#5")
  # Kimliksiz aralıktan sonra giriş yapan kullanıcının süresi o aralığı içermez.
  env$mb_presence_touch(aktif, "tok", 0L, list(), now = t0 + 200, history_env = gecmis)
  env$mb_presence_touch(aktif, "tok", 7L, list(full_name = "B"), now = t0 + 600, history_env = gecmis)
  expect_identical(aktif$tok$started_at, t0 + 600)
  expect_false(isTRUE(aktif$tok$auth_lost))
  # İlk bağlantıdaki kimlik öncesi 0 ise bağlantı anı korunur.
  on <- env$mb_presence_session_entry(NULL, 0L, list(), now = t0)
  expect_identical(env$mb_presence_session_entry(on, 9L, list(), now = t0 + 5)$started_at, t0)
  s <- env$mb_presence_snapshot(aktif, gecmis, t0 + 160)
  expect_identical(s$metrics$online, 0L)
  expect_identical(s$users$status, "ayrildi")
})

test_that("geçersiz ya da gelecekteki zaman damgaları çevrimiçi sayılmaz ve budamayı bozmaz", {
  env <- .presence_env()
  now <- as.POSIXct("2026-09-25 10:00:00", tz = "UTC")
  gecmis <- new.env(parent = emptyenv())
  expect_false(env$mb_presence_record_end("na", list(user_id = 3L, last_seen = as.POSIXct(NA)),
                                          history_env = gecmis, now = now))
  gecmis$bozuk <- list(user_id = 3L, last_seen = now - 5, ended_at = NA)
  expect_silent(env$mb_presence_prune(gecmis, now))
  expect_false("bozuk" %in% ls(gecmis))

  aktif <- new.env(parent = emptyenv())
  aktif$gelecek <- list(user_id = 5L, last_seen = now + 3600, started_at = now - 60)
  aktif$kayma <- list(user_id = 6L, last_seen = now + 30, started_at = now - 60)
  s <- env$mb_presence_snapshot(aktif, gecmis, now)
  expect_identical(s$users$user_id, 6L)
  expect_identical(s$metrics$online, 1L)
})

test_that("profil yalnızca görünen kimlik alanlarını okur", {
  env <- .presence_env()
  oturum <- list(userData = new.env())
  oturum$userData$user_identity <- list(full_name = " Ad Soyad ", username = "adsoyad",
                                        Sicil = "42", Departman = "Birim", token = "gizli")
  p <- env$mb_presence_profile(oturum)
  expect_identical(p, list(full_name = "Ad Soyad", username = "adsoyad", sicil = "42",
                           department = "Birim", mudurluk = ""))
  expect_identical(env$mb_presence_profile(list(userData = new.env()))$full_name, "")
})

test_that("süre ve göreli zaman etiketleri Türkçe üretilir", {
  env <- .presence_env()
  expect_identical(env$mb_presence_duration_label(45), "45 sn")
  expect_identical(env$mb_presence_duration_label(600), "10 dk")
  expect_identical(env$mb_presence_duration_label(3900), "1 sa 5 dk")
  expect_identical(env$mb_presence_duration_label(NA), "—")
  expect_identical(env$mb_presence_ago_label(10), "şimdi")
  expect_identical(env$mb_presence_ago_label(120), "2 dk önce")
})

test_that("Çevrimiçi sekmesi sayaçları, tabloyu ve kaçışlı adları üretir", {
  env <- .presence_env(with_ui = TRUE)
  now <- as.POSIXct("2026-09-25 10:00:00", tz = "UTC")
  f <- .presence_fixture(now)
  f$aktif$t4$profile$full_name <- "<script>alert(1)</script>"
  html <- as.character(env$health_presence_ui(env$mb_presence_snapshot(f$aktif, f$gecmis, now)))

  expect_true(grepl("Şu Anda Çevrimiçi", html, fixed = TRUE))
  expect_true(grepl("Kullanıcı Oturum Takibi", html, fixed = TRUE))
  expect_true(grepl(f$ad, html, fixed = TRUE))
  expect_true(grepl("2 sekme", html, fixed = TRUE))
  expect_true(grepl("health-presence-online", html, fixed = TRUE))
  expect_true(grepl("health-presence-left", html, fixed = TRUE))
  expect_true(grepl("Ayrıldı", html, fixed = TRUE))
  expect_false(grepl("<script>alert", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))

  bos <- as.character(env$health_presence_ui(env$mb_presence_snapshot(new.env(), new.env(), now)))
  expect_true(grepl("uygulamayı kullanan kullanıcı görünmüyor", bos, fixed = TRUE))
  expect_true(grepl("bilgisi alınamadı", as.character(env$health_presence_ui(NULL)), fixed = TRUE))
})

test_that("performans modülü profili kaydeder ve kapanan oturumu geçmişe taşır", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .presence_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "module_performance.R"),
         encoding = "UTF-8", local = env)
  gecmis <- env$mb_presence_env(".mergen_presence_history")
  sonuc <- new.env()
  tmp <- withr::local_tempdir()
  invisible(utils::capture.output(withr::with_dir(tmp, {
    shiny::testServer(env$performanceStatsServer,
                      args = list(current_user_id_provider = function() 5L), {
      session$userData$user_identity <- list(full_name = "Test Kisi", username = "tkisi")
      session$returned$touch_session(5L)
      aktif <- get(".mergen_active_sessions", envir = globalenv())
      sonuc$token <- session$token
      sonuc$kayit <- aktif[[session$token]]
    })
  })))
  withr::defer(suppressWarnings(rm(list = sonuc$token, envir = gecmis)))

  expect_identical(sonuc$kayit$user_id, 5L)
  expect_identical(sonuc$kayit$profile$full_name, "Test Kisi")
  expect_s3_class(sonuc$kayit$started_at, "POSIXct")
  aktif <- get(".mergen_active_sessions", envir = globalenv())
  expect_false(sonuc$token %in% ls(aktif))
  expect_true(sonuc$token %in% ls(gecmis))
  expect_identical(gecmis[[sonuc$token]]$profile$username, "tkisi")
})

test_that("performans modülü geçersiz last_seen kaydını geçmişe yazmadan atar ve düşen kimliği bitirir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .presence_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "module_performance.R"),
         encoding = "UTF-8", local = env)
  gecmis <- env$mb_presence_env(".mergen_presence_history")
  sonuc <- new.env()
  tmp <- withr::local_tempdir()
  invisible(utils::capture.output(withr::with_dir(tmp, {
    shiny::testServer(env$performanceStatsServer,
                      args = list(current_user_id_provider = function() 5L), {
      aktif <- get(".mergen_active_sessions", envir = globalenv())
      aktif[["bozuk-tok"]] <- list(user_id = 3L, last_seen = as.POSIXct(NA))
      # Saat kayması payından fazla gelecekteki nabız da sayaçta tutulmaz.
      aktif[["gelecek-tok"]] <- list(user_id = 4L, last_seen = Sys.time() + 3600)
      session$userData$user_id <- 5L
      session$userData$auth_initialized <- TRUE
      session$returned$touch_session()
      sonuc$bozuk_aktif <- "bozuk-tok" %in% ls(aktif)
      sonuc$gelecek_aktif <- "gelecek-tok" %in% ls(aktif)
      # SSO süresi doldu: sağlayıcı hâlâ 5 döndürse de nabız 0 yazar.
      session$userData$user_id <- 0L
      session$userData$auth_initialized <- FALSE
      session$returned$touch_session()
      sonuc$token <- session$token
      sonuc$kayit <- aktif[[session$token]]
    })
  })))
  withr::defer(suppressWarnings(rm(list = c(sonuc$token, paste0(sonuc$token, "#5")), envir = gecmis)))

  expect_false(sonuc$bozuk_aktif)
  expect_false("bozuk-tok" %in% ls(gecmis))
  expect_false(sonuc$gelecek_aktif)
  expect_false("gelecek-tok" %in% ls(gecmis))
  expect_identical(sonuc$kayit$user_id, 0L)
  expect_true(paste0(sonuc$token, "#5") %in% ls(gecmis))
})

test_that("çok-süreçli dağıtımda diğer süreçlerin oturumları birleştirilir; kapanan süreç ayrıldı sayılır", {
  env <- .presence_env()
  dizin <- withr::local_tempdir()
  withr::local_envvar(c(MERGEN_PRESENCE_SHARED_DIR = dizin))
  now <- Sys.time()
  # Tek süreçte (paylaşılan dizin yok) dosya yazılmaz.
  withr::with_envvar(c(MERGEN_PRESENCE_SHARED_DIR = "", MERGEN_APP_WORKER_COUNT = "1"),
                     expect_false(env$mb_presence_publish(new.env(), new.env(), now)))

  uzak_aktif <- new.env()
  uzak_aktif$u1 <- list(user_id = 21L, last_seen = now - 30, started_at = now - 600,
                        profile = list(full_name = "Uzak Kisi"))
  satirlar <- env$mb_presence_session_rows(uzak_aktif, new.env(), now)
  saveRDS(list(generated_at = as.numeric(now) - 20, rows = satirlar),
          file.path(dizin, "presence_baska-surec_1.rds"))
  saveRDS(list(generated_at = as.numeric(now) - 600, rows = transform(satirlar, user_id = 22L)),
          file.path(dizin, "presence_olu-surec_2.rds"))

  yerel <- new.env()
  yerel$t1 <- list(user_id = 5L, last_seen = now - 10, started_at = now - 100, profile = list())
  anlik <- env$mb_presence_snapshot(yerel, new.env(), now)
  expect_identical(anlik$metrics$online, 2L)
  expect_identical(anlik$metrics$day, 3L)
  expect_identical(anlik$users$status[anlik$users$user_id == 22L], "ayrildi")

  # Bu sürecin yayını kendisi tarafından yeniden okunmaz; yayın aralığı sınırlıdır.
  expect_true(env$mb_presence_publish(yerel, new.env(), now))
  expect_false(env$mb_presence_publish(yerel, new.env(), now + 5))
  expect_true(file.exists(file.path(dizin, paste0("presence_", env$mb_presence_process_id(), ".rds"))))
  expect_identical(env$mb_presence_snapshot(yerel, new.env(), now)$metrics$day, 3L)
})

test_that("Çevrimiçi tablosu satır sayısı sınırlıdır, sayaçlar tam kalır", {
  env <- .presence_env(with_ui = TRUE)
  now <- Sys.time()
  kullanicilar <- data.frame(user_id = 1:5, status = "cevrimici", sessions = 1L,
                             started_at = as.numeric(now) - 60, last_seen = as.numeric(now),
                             duration_secs = 60, full_name = paste("Kisi", 1:5), username = "",
                             sicil = "", department = "", mudurluk = "", stringsAsFactors = FALSE)
  html <- as.character(env$health_presence_table(kullanicilar, now, max_rows = 2L))
  expect_identical(lengths(regmatches(html, gregexpr("health-presence-row", html, fixed = TRUE))), 2L)
  expect_true(grepl("İlk 2 kullanıcı gösteriliyor (toplam 5).", html, fixed = TRUE))
})

test_that("kimlik sinyali nabız beklemeden varlık kaydını günceller", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .presence_env()
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_performance.R"), encoding = "UTF-8", local = env)
  gecmis <- env$mb_presence_env(".mergen_presence_history")
  sonuc <- new.env()
  tmp <- withr::local_tempdir()
  invisible(utils::capture.output(withr::with_dir(tmp, {
    shiny::testServer(env$performanceStatsServer,
                      args = list(current_user_id_provider = function() 5L), {
      session$userData$user_id <- 5L
      session$userData$auth_initialized <- TRUE
      session$flushReact()
      aktif <- get(".mergen_active_sessions", envir = globalenv())
      sonuc$once <- aktif[[session$token]]$user_id
      # SSO süresi doldu: kimlik geçişi sinyali artırır, kayıt hemen biter.
      session$userData$user_id <- 0L
      session$userData$auth_initialized <- FALSE
      sinyal <- session$userData$kimlik_sinyali
      sinyal(shiny::isolate(sinyal()) + 1L)
      session$flushReact()
      sonuc$sonra <- aktif[[session$token]]$user_id
      sonuc$token <- session$token
    })
  })))
  withr::defer(suppressWarnings(rm(list = c(sonuc$token, paste0(sonuc$token, "#5")), envir = gecmis)))
  expect_identical(sonuc$once, 5L)
  expect_identical(sonuc$sonra, 0L)
  expect_true(paste0(sonuc$token, "#5") %in% ls(gecmis))
})
