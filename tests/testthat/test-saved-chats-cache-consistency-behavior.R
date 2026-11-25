# ==============================================================================
# Dosya Yolu: tests/testthat/test-saved-chats-cache-consistency-behavior.R
# Açıklama: Kayıtlı söyleşi önbelleği tutarlılık sözleşmeleri. Yardımcılar
#           güncel çalışma kopyasından taze bir ortama kaynaklanır (oturumda
#           önceden yüklenmiş eski tanımlar kullanılmaz). DB gerekmez.
#   - Kayıtsız mesaj taşınırken yeniden okuma işareti mesajlar eşit olsa da konur.
#   - SSE yeniden denemesi kaydedilen istemi önbellekte yerinde günceller.
#   - Özet (mesajsız) önbelleğe eklenen mesaj sayıyı uzunluğa indirgemez.
#   - Hidrasyon uzlaştırması DB sırasını ve kayıtsız konumunu korur.
#   - Vektörel etkinlik zamanı tekil dönüştürücüyle aynı sonucu verir.
# ==============================================================================

.onbellek_ortami <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  for (f in c("helpers_chat_message_formatting.R", "helpers_saved_chats_merge.R", "helpers_chat_runtime.R")) {
    sys.source(file.path(kok, "R", f), envir = env, keep.source = FALSE)
  }
  env
}

testthat::test_that("kayıtsız mesaj taşınırken mesajlar zaten eşitse de yeniden okuma işareti konur ve yerel etkinlik korunur", {
  env <- .onbellek_ortami()
  yerel_zaman <- as.POSIXct("2026-11-20 12:00:00", tz = "Europe/Istanbul")
  db_zaman <- as.POSIXct("2026-11-20 11:00:00", tz = "Europe/Istanbul")
  mesajlar <- list(list(id = "11", db_id = 11L, type = "user", content = "kayıtlı"),
                   list(id = "yerel_1", db_id = NULL, type = "user", content = "kayıtsız"))
  current <- list("5" = list(title = "Beş", messages = mesajlar, last_message_timestamp = yerel_zaman))
  sonuc <- list("5" = list(title = "Beş", messages = mesajlar, last_message_timestamp = db_zaman))
  cikti <- env$mergen_saved_chats_carry_unsaved(sonuc, current)
  testthat::expect_true(isTRUE(cikti[["5"]]$transkript_yenile))
  testthat::expect_identical(cikti[["5"]]$last_message_timestamp, yerel_zaman)

  # DB etkinliği daha yeniyse DB zamanı korunur; tamamen kayıtlı transkript işaretlenmez.
  sonuc2 <- list("5" = list(title = "Beş", last_message_timestamp = yerel_zaman + 3600))
  testthat::expect_identical(env$mergen_saved_chats_carry_unsaved(sonuc2, current)[["5"]]$last_message_timestamp,
                             yerel_zaman + 3600)
  kayitli <- list("5" = list(messages = mesajlar[1]))
  testthat::expect_null(env$mergen_saved_chats_carry_unsaved(list("5" = list(title = "Beş")), kayitli)[["5"]]$transkript_yenile)
})

testthat::test_that("SSE yeniden denemesi kaydedilen istemi önbellekte yerinde günceller; hidrasyon istemi iki kez göstermez", {
  env <- .onbellek_ortami()
  values <- new.env()
  values$current_chat_id <- 5L
  istem <- list(id = "yerel_9", db_id = NULL, type = "user", content = "aynı istem")
  values$saved_chats <- list("5" = list(title = "Beş", messages = list(), message_count = 0L,
                                        timestamp = Sys.time()))
  env$chat_store_message_in_saved_chats(values, istem)
  kaydedilen <- istem; kaydedilen$db_id <- 91L
  env$chat_store_message_in_saved_chats(values, kaydedilen)
  onbellek <- values$saved_chats[["5"]]
  testthat::expect_length(onbellek$messages, 1L)
  testthat::expect_identical(onbellek$messages[[1]]$db_id, 91L)
  testthat::expect_identical(onbellek$messages[[1]]$id, "yerel_9")
  testthat::expect_identical(onbellek$message_count, 1L)

  detay <- list(title = "Beş", messages = list(list(id = "91", type = "user", content = "aynı istem")),
                message_count = 1L)
  uzlasan <- env$mergen_chat_reconcile_hydrated_detail(detay, onbellek)
  testthat::expect_length(uzlasan$messages, 1L)
})

testthat::test_that("özet (mesajsız) önbelleğe eklenen mesaj sayıyı uzunluğa indirgemez; yeniden açılış hidrasyon ister", {
  env <- .onbellek_ortami()
  values <- new.env()
  values$current_chat_id <- 5L
  values$saved_chats <- list("5" = list(title = "Beş", message_count = 6L, timestamp = Sys.time()))
  env$chat_store_message_in_saved_chats(values, list(id = "41", db_id = 41L, type = "user", content = "yeni"))
  env$chat_store_message_in_saved_chats(values, list(id = "42", db_id = 42L, type = "ai", content = "yanıt"))
  onbellek <- values$saved_chats[["5"]]
  testthat::expect_length(onbellek$messages, 2L)
  testthat::expect_identical(onbellek$message_count, 8L)
  testthat::expect_true(onbellek$message_count > length(onbellek$messages))

  # Tam önbellekte sayı uzunluğu izler (önceki davranış korunur).
  values$saved_chats <- list("6" = list(title = "Altı", messages = list(), message_count = 0L))
  values$current_chat_id <- 6L
  env$chat_store_message_in_saved_chats(values, list(id = "51", db_id = 51L, type = "user", content = "ilk"))
  testthat::expect_identical(values$saved_chats[["6"]]$message_count, 1L)
})

testthat::test_that("hidrasyon uzlaştırması uzun transkriptte DB sırasını ve kayıtsız mesajın konumunu korur", {
  env <- .onbellek_ortami()
  n <- 3000L
  db <- lapply(seq_len(n), function(i) list(id = as.character(i), type = if (i %% 2) "user" else "ai", content = paste("m", i)))
  kayitsiz <- list(id = "yerel_x", db_id = NULL, type = "user", content = "kayıtsız")
  yerel <- c(db[1:10], list(kayitsiz), db[11:12])
  # Yapısal karmaşıklık denetimi (duvar saatine bağlı değil): uzlaştırma mesaj
  # başına DB kimliklerini yeniden tarayan tekil yardımcıyı hiç çağırmaz.
  tekil_cagri <- 0L
  ozgun <- env$mergen_chat_message_unsaved
  env$mergen_chat_message_unsaved <- function(...) { tekil_cagri <<- tekil_cagri + 1L; ozgun(...) }
  sonuc <- env$mergen_chat_reconcile_hydrated_detail(
    list(title = "Uzun", messages = db, message_count = n, okuma_baslangici = 1000),
    list(messages = yerel))
  testthat::expect_identical(tekil_cagri, 0L)
  kimlikler <- vapply(sonuc$messages, function(m) m$id, character(1))
  testthat::expect_identical(length(kimlikler), n + 1L)
  testthat::expect_identical(kimlikler[11], "yerel_x")
  testthat::expect_identical(kimlikler[-11], as.character(seq_len(n)))
  # Hidrasyon zamanı okumanın başlangıcıdır; geçici alan önbelleğe taşınmaz.
  testthat::expect_identical(sonuc$hidrate_zamani, 1000)
  testthat::expect_null(sonuc$okuma_baslangici)
})

testthat::test_that("uzlaştırma aynı çapadaki kayıtsız mesajların sırasını, yinelenen DB kimliğini ve kuyruğu korur", {
  env <- .onbellek_ortami()
  m <- function(id, ...) list(id = id, type = "user", content = id, ...)
  db <- list(m("1"), m("2"), m("2"), m("3"))
  yerel <- list(m("a", db_id = NULL), m("1"), m("b", db_id = NULL), m("c", db_id = NULL), m("2"), m("3"),
                m("z", db_id = NULL), m("y"))
  sonuc <- env$mergen_chat_reconcile_hydrated_detail(list(messages = db), list(messages = yerel))
  kimlikler <- vapply(sonuc$messages, function(x) x$id, character(1))
  # "y" kimliği ne DB'de ne kayıtsız (sayısal değil ama db_id alanı yok) -> ad tabanlı kural:
  # sayısal olmayan kimlik kayıtsız sayılır ve kuyruğa eklenir.
  testthat::expect_identical(kimlikler, c("a", "1", "b", "c", "2", "2", "3", "z", "y"))
  testthat::expect_identical(sonuc$message_count, 9L)
  # Tekil yardımcıyla aynı kayıtsızlık kararı.
  karar <- vapply(yerel, env$mergen_chat_message_unsaved, logical(1),
                  db_ids = vapply(db, function(x) x$id, character(1)))
  testthat::expect_identical(karar, c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE))
})

testthat::test_that("etkinlik zamanı yalnızca desteklenen biçimin tamamı eşleşirse çözülür", {
  env <- .onbellek_ortami()
  for (tz in c("UTC", "Europe/Istanbul")) withr::with_envvar(c(TZ = tz), {
    gecersiz <- list("2026-11-20 25:00", "2026-11-20 10:00 fazlalık", "2026-11-20xyz", "20.11.2026 - 10:30 ek",
                     "2026-11-20 10:61")
    for (g in gecersiz) {
      testthat::expect_true(is.na(env$mergen_chat_activity_seconds(g)), info = g)
    }
    testthat::expect_true(all(is.na(env$mergen_chat_activity_seconds_vec(gecersiz))))
    gecerli <- list("2026-11-20 10:00:05.250", "2026-11-20T10:00:05", "2026-11-20 10:00", "20.11.2026 - 10:30",
                    "2026-11-20")
    beklenen <- as.numeric(as.POSIXct(c("2026-11-20 10:00:05.25", "2026-11-20 10:00:05", "2026-11-20 10:00:00",
                                        "2026-11-20 10:30:00", "2026-11-20 00:00:00"), tz = "Europe/Istanbul"))
    testthat::expect_equal(env$mergen_chat_activity_seconds_vec(gecerli), beklenen, info = tz)
    testthat::expect_equal(vapply(gecerli, env$mergen_chat_activity_seconds, numeric(1)), beklenen, info = tz)
  })
})

testthat::test_that("vektörel etkinlik zamanı tekil dönüştürücüyle aynı sonucu verir", {
  env <- .onbellek_ortami()
  degerler <- list(
    as.POSIXct("2026-11-20 09:15:00", tz = "UTC"),
    as.POSIXct("2026-11-20 09:15:00", tz = "Europe/Istanbul"),
    "2026-11-20 10:00:05", "2026-11-20 10:00", "20.11.2026 - 10:30", "2026-11-19",
    as.Date("2026-11-18"), 1763630000, NULL, NA, "", "geçersiz", character(0),
    as.POSIXct(NA)
  )
  tekil <- vapply(degerler, env$mergen_chat_activity_seconds, numeric(1))
  testthat::expect_identical(env$mergen_chat_activity_seconds_vec(degerler), unname(tekil))
  testthat::expect_identical(env$mergen_chat_activity_seconds_vec(list()), numeric(0))
})
