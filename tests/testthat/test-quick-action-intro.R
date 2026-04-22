# ==============================================================================
# Dosya Yolu: tests/testthat/test-quick-action-intro.R
# Açıklama: build_quick_action_intro_message() hazır yönlendirme metinlerinin
# ilk isim kişiselleştirmesi, bilinmeyen action_id fallback'i ve bilinen
# action_id için başlık/selamlama içerik kurallarını doğrulayan testleri
# içerir. Quick-action metinleri LLM çağrısı yapmadan üretilir (CLAUDE.md §5A).
# ==============================================================================

# Testlerin config_api.R'nin tamamını source etmemesi için, yalnızca bu test
# dosyasının ihtiyaç duyduğu minimal get_tool_mode_config() ikamesi ve
# helpers_quick_action_intro_messages.R ilk çağrıda yüklenir.
local({
  if (!exists("get_tool_mode_config", envir = globalenv(), inherits = FALSE)) {
    assign("get_tool_mode_config", function(value, by = c("family", "setting_flag", "quick_action_id"),
                                            config = NULL) {
      by <- match.arg(by)
      all_cfg <- config$tool_mode_config %||% list()
      for (cfg in all_cfg) {
        candidate <- cfg[[by]] %||% NULL
        if (!is.null(candidate) && identical(as.character(candidate), as.character(value))) {
          return(cfg)
        }
      }
      NULL
    }, envir = globalenv())
  }

  if (!exists("api_config", envir = globalenv(), inherits = FALSE)) {
    # helpers_quick_action_intro_messages.R fonksiyonunun varsayılan config
    # argümanında api_config referansı vardır. Testler kendi config'ini ilettiği
    # için bu referansın var olması yeterli.
    assign("api_config", list(tool_mode_config = list()), envir = globalenv())
  }

  if (!exists("build_quick_action_intro_message", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_quick_action_intro_messages.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Test için minimal config: iki bilinen quick_action_id tanımlanır.
.make_test_quick_action_config <- function() {
  list(
    tool_mode_config = list(
      list(quick_action_id = "summarization", title = "Özetleme Desteği"),
      list(quick_action_id = "excel-analysis", title = "Excel Analizi")
    )
  )
}

# Bilinen action_id için selamlama ve başlık metni beklenir.
test_that("build_quick_action_intro_message bilinen action_id için başlık içerir", {
  test_cfg <- .make_test_quick_action_config()

  metin <- build_quick_action_intro_message(
    action_id = "summarization",
    user_name = "Mehmet",
    config    = test_cfg
  )
  expect_true(nzchar(metin))
  expect_true(grepl("Özetleme Desteği", metin, fixed = TRUE))
  expect_true(grepl("Mehmet", metin, fixed = TRUE))
})

# user_name verilmediğinde bold ad eklenmeden jenerik selamlama üretilmeli.
test_that("build_quick_action_intro_message user_name boş ise bold ad eklemez", {
  test_cfg <- .make_test_quick_action_config()

  metin <- build_quick_action_intro_message(
    action_id = "excel-analysis",
    user_name = "",
    config    = test_cfg
  )
  expect_true(nzchar(metin))
  # Boş bir kişi adı ile **Ad** kalıbı üretilmemelidir.
  expect_false(grepl("\\*\\*\\*\\*", metin))
  expect_true(grepl("Excel Analizi", metin, fixed = TRUE))
})

# Bilinmeyen action_id için generic fallback metni üretilir.
test_that("build_quick_action_intro_message bilinmeyen action_id için generic fallback döner", {
  test_cfg <- .make_test_quick_action_config()

  metin <- build_quick_action_intro_message(
    action_id = "olmayan_action",
    user_name = "Ayşe",
    config    = test_cfg
  )
  expect_true(nzchar(metin))
  # Generic fallback "Hızlı İşlem" başlığıyla döner veya action_title alır.
  expect_true(grepl("Hızlı İşlem|Sorunuzu yazabilirsiniz", metin))
})

# NULL veya eksik action_id girişinde güvenli fallback davranışı sergilenmeli.
test_that("build_quick_action_intro_message NULL action_id'de çökmeden metin üretir", {
  test_cfg <- .make_test_quick_action_config()

  metin <- build_quick_action_intro_message(
    action_id = NULL,
    user_name = NULL,
    config    = test_cfg
  )
  expect_true(is.character(metin))
  expect_true(nzchar(metin))
})