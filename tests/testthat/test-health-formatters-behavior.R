# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-formatters-behavior.R
# Açıklama: R/helpers_health_formatters.R Sistem Durumu saf biçimlendirme ve
#           güvenli (sır redaksiyonu dahil) yardımcılarının DAVRANIŞSAL testleri:
#           health_status_label/icon, health_safe_value, health_redact_secret,
#           health_is_secret_name, health_format_bytes, health_ms,
#           health_overall_status, health_score, health_is_copyable_path.
#           Shiny/htmltools üreten (tags/div/icon) yardımcılar KAPSAM DIŞIDIR.
#           Saf base R; ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.healthfmt_source_once <- function() {
  if (exists("health_format_bytes", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_health_formatters.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# health_format_bytes
# ------------------------------------------------------------------------------
testthat::test_that("health_format_bytes uygun birime ölçekler ve geçersizi N/A yapar", {
  .healthfmt_source_once()
  testthat::expect_identical(health_format_bytes(0), "0.0 B")
  testthat::expect_identical(health_format_bytes(512), "512.0 B")
  testthat::expect_identical(health_format_bytes(1024), "1.0 KB")
  testthat::expect_identical(health_format_bytes(1536), "1.5 KB")
  testthat::expect_identical(health_format_bytes(1048576), "1.0 MB")
  testthat::expect_identical(health_format_bytes(1073741824), "1.0 GB")
  testthat::expect_identical(health_format_bytes(1099511627776), "1.0 TB")
  # Negatif / NA / sayısal olmayan => "N/A".
  testthat::expect_identical(health_format_bytes(-5), "N/A")
  testthat::expect_identical(health_format_bytes(NA), "N/A")
  testthat::expect_identical(health_format_bytes("abc"), "N/A")
})

# ------------------------------------------------------------------------------
# health_redact_secret / health_is_secret_name (güvenlik)
# ------------------------------------------------------------------------------
testthat::test_that("health_redact_secret değeri sızdırmadan varlık/uzunluk bildirir", {
  .healthfmt_source_once()
  # Boş => "missing"; ham sır metni asla döndürülmez.
  testthat::expect_identical(health_redact_secret(""), "missing")
  testthat::expect_identical(health_redact_secret(NULL), "missing")
  # Dolu => yalnızca uzunluk bilgisi.
  testthat::expect_identical(health_redact_secret("abcde"), "configured (5 karakter)")
  testthat::expect_identical(health_redact_secret("abcde", show_length = FALSE), "configured")
  # Çıktı ham sır değerini içermemeli.
  testthat::expect_false(grepl("abcde", health_redact_secret("abcde"), fixed = TRUE))
})

testthat::test_that("health_is_secret_name sır benzeri adları büyük/küçük harf duyarsız yakalar", {
  .healthfmt_source_once()
  testthat::expect_true(health_is_secret_name("API_KEY"))
  testthat::expect_true(health_is_secret_name("DB_TOKEN"))
  testthat::expect_true(health_is_secret_name("MY_SECRET"))
  testthat::expect_true(health_is_secret_name("USER_PASSWORD"))
  testthat::expect_true(health_is_secret_name("user_pass"))
  testthat::expect_true(health_is_secret_name("PWD"))
  testthat::expect_true(health_is_secret_name("db_credential"))
  testthat::expect_true(health_is_secret_name("api_key"))  # küçük harf
  # Sır olmayan adlar.
  testthat::expect_false(health_is_secret_name("username"))
  testthat::expect_false(health_is_secret_name("endpoint"))
  testthat::expect_false(health_is_secret_name("host"))
})

# ------------------------------------------------------------------------------
# health_safe_value
# ------------------------------------------------------------------------------
testthat::test_that("health_safe_value NULL/NA/boş için varsayılan, aksi halde ilk değeri verir", {
  .healthfmt_source_once()
  testthat::expect_identical(health_safe_value(NULL), "—")
  testthat::expect_identical(health_safe_value(NA), "—")
  testthat::expect_identical(health_safe_value(character(0)), "—")
  testthat::expect_identical(health_safe_value(""), "—")
  testthat::expect_identical(health_safe_value(c(NA, NA)), "—")
  testthat::expect_identical(health_safe_value("x"), "x")
  # Vektörde ilk eleman.
  testthat::expect_identical(health_safe_value(c("a", "b")), "a")
  # Özel boş değer.
  testthat::expect_identical(health_safe_value(NULL, empty = "yok"), "yok")
})

# ------------------------------------------------------------------------------
# health_status_label / health_status_icon (alias normalizasyonu dahil)
# ------------------------------------------------------------------------------
testthat::test_that("health_status_label durumu (alias dahil) Türkçe etikete çevirir", {
  .healthfmt_source_once()
  testthat::expect_identical(health_status_label("ok"), "Sağlıklı")
  testthat::expect_identical(health_status_label("healthy"), "Sağlıklı")    # alias
  testthat::expect_identical(health_status_label("warn"), "Uyarı")          # alias
  testthat::expect_identical(health_status_label("error"), "Kritik")        # alias
  testthat::expect_identical(health_status_label("disabled"), "Tanımlı Değil") # alias
  # Bilinmeyen / boş / NULL => "Bilinmiyor".
  testthat::expect_identical(health_status_label("xyz"), "Bilinmiyor")
  testthat::expect_identical(health_status_label(""), "Bilinmiyor")
  testthat::expect_identical(health_status_label(NULL), "Bilinmiyor")
})

testthat::test_that("health_status_icon her durum için beklenen ikonu döner", {
  .healthfmt_source_once()
  testthat::expect_identical(health_status_icon("ok"), "check-circle")
  testthat::expect_identical(health_status_icon("warning"), "exclamation-triangle")
  testthat::expect_identical(health_status_icon("critical"), "times-circle")
  testthat::expect_identical(health_status_icon("not_configured"), "minus-circle")
  testthat::expect_identical(health_status_icon("unknown"), "question-circle")
})

# ------------------------------------------------------------------------------
# health_overall_status / health_score
# ------------------------------------------------------------------------------
testthat::test_that("health_overall_status en kötü severity'yi yansıtır", {
  .healthfmt_source_once()
  testthat::expect_identical(health_overall_status(NULL), "unknown")
  testthat::expect_identical(
    health_overall_status(data.frame(severity = c(0L, 3L))), "warning"
  )
  testthat::expect_identical(
    health_overall_status(data.frame(severity = c(0L, 4L))), "critical"
  )
})

testthat::test_that("health_score penaltıyı 0-100 arası tamsayıya çevirir; not_configured hariç tutulur", {
  .healthfmt_source_once()
  # Hepsi ok => tam puan.
  testthat::expect_identical(
    health_score(data.frame(status = c("ok", "ok"), severity = c(0L, 0L))), 100L
  )
  # Tek kritik => 0.
  testthat::expect_identical(
    health_score(data.frame(status = "critical", severity = 4L)), 0L
  )
  # ok + warning => 100 - (3/8*100) = 62.5 -> 62 (çift yuvarlama).
  testthat::expect_identical(
    health_score(data.frame(status = c("ok", "warning"), severity = c(0L, 3L))), 62L
  )
  # not_configured satırı puana dahil edilmez.
  testthat::expect_identical(
    health_score(data.frame(status = c("ok", "not_configured"), severity = c(0L, 1L))), 100L
  )
  # Yalnızca not_configured => 0; NULL/boş => 0.
  testthat::expect_identical(
    health_score(data.frame(status = "not_configured", severity = 1L)), 0L
  )
  testthat::expect_identical(health_score(NULL), 0L)
})

# ------------------------------------------------------------------------------
# health_ms (zaman tabanlı; gevşek sınırlarla)
# ------------------------------------------------------------------------------
testthat::test_that("health_ms negatif olmayan milisaniye verir ve geçmiş zamanda büyür", {
  .healthfmt_source_once()
  t0 <- Sys.time()
  ms_now <- health_ms(t0)
  testthat::expect_true(is.numeric(ms_now))
  testthat::expect_length(ms_now, 1L)
  testthat::expect_true(ms_now >= 0)
  testthat::expect_true(ms_now < 2000)  # çağrı neredeyse anlık
  # 3 saniye öncesi en az ~3 saniye olarak ölçülür.
  testthat::expect_true(health_ms(t0 - 3) >= 2900)
})

# ------------------------------------------------------------------------------
# health_is_copyable_path (id izin listesi + gerçek yol kontrolü)
# ------------------------------------------------------------------------------
testthat::test_that("health_is_copyable_path yalnızca izinli id + var olan yol için TRUE döner", {
  .healthfmt_source_once()
  d <- tempfile("healthpath"); dir.create(d)

  # Var olan dizin + izinli id.
  testthat::expect_true(health_is_copyable_path(d, "storage.files_root"))
  # Var olan dizin + 'storage.path.' önekli id.
  testthat::expect_true(health_is_copyable_path(d, "storage.path.custom"))
  # İzinli id ama yol yok => FALSE.
  testthat::expect_false(
    health_is_copyable_path(file.path(d, "yok-boyle"), "storage.files_root")
  )
  # Var olan yol ama izinsiz id => FALSE.
  testthat::expect_false(health_is_copyable_path(d, "diagnostics.other"))
})

testthat::test_that("health_is_copyable_path durum/placeholder/boş değerleri reddeder", {
  .healthfmt_source_once()
  testthat::expect_false(health_is_copyable_path("n/a", "storage.files_root"))
  testthat::expect_false(health_is_copyable_path("configured", "storage.files_root"))
  testthat::expect_false(health_is_copyable_path("missing", "storage.files_root"))
  testthat::expect_false(health_is_copyable_path("ok", "storage.files_root"))      # durum seviyesi
  testthat::expect_false(health_is_copyable_path("", "storage.files_root"))
  testthat::expect_false(health_is_copyable_path(NULL, "storage.files_root"))
})
