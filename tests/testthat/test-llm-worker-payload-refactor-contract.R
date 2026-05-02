# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-payload-refactor-contract.R
# Açıklama: helpers_llm_worker.R içinden ayrılan saf mesaj/grafik yardımcılarının
#           davranış sözleşmesini korur. Uygulamayı başlatmaz.
# ==============================================================================

.find_repo_root_llm_worker_payload <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

repo_root_llm_worker_payload <- .find_repo_root_llm_worker_payload()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

source(
  file.path(repo_root_llm_worker_payload, "R", "helpers_llm_worker_payload.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("chat history API mesajlarına davranış korunarak dönüştürülür", {
  history <- list(
    list(type = "system", content = "Sistem yönergesi"),
    list(type = "user", content = "Merhaba"),
    list(role = "assistant", message = "Yanıt"),
    list(content = "Rol yoksa user kabul edilir")
  )

  out <- llm_worker_chat_history_to_messages(history)

  expect_equal(
    vapply(out, `[[`, character(1), "role"),
    c("system", "user", "assistant", "user")
  )

  expect_equal(out[[1]]$content, "Sistem yönergesi")
  expect_equal(out[[2]]$content, "Merhaba")
  expect_equal(out[[3]]$content, "Yanıt")
  expect_equal(out[[4]]$content, "Rol yoksa user kabul edilir")
})

test_that("system mesajları sırayı koruyarak tek system mesajında öne alınır", {
  messages <- list(
    list(role = "user", content = "Soru"),
    list(role = "system", content = "Kural 1"),
    list(role = "assistant", content = "Ara yanıt"),
    list(role = "system", content = "Kural 2")
  )

  out <- llm_worker_merge_system_messages_to_front(messages)
  compat_out <- merge_system_messages_to_front(messages)

  expect_equal(out[[1]]$role, "system")
  expect_equal(out[[1]]$content, "Kural 1\n\nKural 2")
  expect_equal(vapply(out[-1], `[[`, character(1), "role"), c("user", "assistant"))
  expect_identical(compat_out, out)
})

test_that("grafik niyeti Türkçe ve İngilizce anahtarlarla algılanır", {
  expect_true(llm_worker_has_chart_intent(list(
    list(role = "user", content = "Bu Excel verisinden çizgi grafik oluştur.")
  )))

  expect_true(llm_worker_has_chart_intent(list(
    list(role = "user", content = "Please visualize this as a scatter plot.")
  )))

  expect_false(llm_worker_has_chart_intent(list(
    list(role = "user", content = "Bu dosyayı sadece kısaca açıkla.")
  )))

  expect_equal(llm_worker_detect_chart_type_from_text("pasta grafik çiz"), "pie")
  expect_equal(llm_worker_detect_chart_type_from_text("zaman serisi trend"), "line")
  expect_equal(llm_worker_detect_chart_type_from_text("belirsiz metin"), "auto")
})

test_that("grafik özeti data frame olmadan hata üretmez", {
  out <- llm_worker_build_auto_insight(list(
    list(
      chart = list(
        type = "bar",
        mapping = list(x = "Kategori", y = "Tutar"),
        n = 10
      )
    )
  ))

  expect_true(grepl("Grafik hazırlandı:", out, fixed = TRUE))
  expect_true(grepl("Tür: bar", out, fixed = TRUE))
  expect_true(grepl("X=Kategori", out, fixed = TRUE))
  expect_true(grepl("Y=Tutar", out, fixed = TRUE))
  expect_true(grepl("Örnek satır sayısı: 10", out, fixed = TRUE))
})

test_that("tablo önizleme içgörüsü sayısal kolonları davranış korunarak özetler", {
  out <- llm_worker_build_auto_insight(list(
    list(
      preview = data.frame(
        deger = c(1, 2, 3),
        kategori = c("a", "b", "c"),
        stringsAsFactors = FALSE
      )
    )
  ))

  expect_true(grepl(
    "İçgörü: 3 satırın deger sütunu min 1.00, medyan 2.00, ortalama 2.00, max 3.00.",
    out,
    fixed = TRUE
  ))

  expect_true(grepl("Standart sapma 1.00", out, fixed = TRUE))
})