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

test_that("oturum sonu kaydı 24 saat ve kayıt tavanıyla budanır", {
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
                                             stale = 1800, max_history = 2L)
  for (i in 1:3) {
    env$mb_presence_record_end(paste0("k", i), list(user_id = i, last_seen = now),
                               ended_at = now + i, history_env = gecmis)
  }
  expect_identical(sort(ls(gecmis)), c("k2", "k3"))
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
  expect_true(grepl("oturum açan kullanıcı görünmüyor", bos, fixed = TRUE))
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
