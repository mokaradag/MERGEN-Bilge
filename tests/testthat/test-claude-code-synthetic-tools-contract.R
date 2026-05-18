# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-synthetic-tools-contract.R
# Açıklama: Bilge Yolaç on-prem LLM proxy modeli Anthropic tool_use blokları
#           yaymadığı durumlarda snapshot diff ile algılanan dosyalar için
#           sentetik Write araç bloğu yayınlandığını doğrular. Bu, ARAÇ
#           KULLANIMLARI sayacının modelin gerçekleştirdiği dosya işlemini
#           kullanıcıya geri bildirim olarak yansıtmasını sağlar.
# ==============================================================================

.source_cc_synthetic_tools_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$log_error <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"

  test_env$claude_code_streaming_config <- list(
    poll_interval_ms = 200L,
    file_preview_lines = 10L,
    result_truncate_chars = 1000L,
    shell_visible_default = TRUE
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_formatters.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_streaming.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

# Sahte Shiny session: sendCustomMessage çağrılarını yakalar
.cc_fake_session_for_synth <- function() {
  s <- new.env(parent = emptyenv())
  s$mesajlar <- list()
  s$sendCustomMessage <- function(type, message) {
    s$mesajlar <- c(s$mesajlar, list(list(type = type, message = message)))
    invisible(NULL)
  }
  s$ns <- function(id) paste0("test-", id)
  s
}

test_that("cc_synthesize_tool_uses_from_downloads boş tool_uses + algılanan dosya için sentetik Write üretir", {
  test_env <- .source_cc_synthetic_tools_for_test()

  session <- .cc_fake_session_for_synth()

  env <- new.env(parent = emptyenv())
  env$karakter_renk <- "#81C784"
  env$karakter_adi <- "Mergen"
  env$zaman_damgasi <- "10:00:00"

  ayristirma <- list(
    text_output = "Dosyayı kaydettim.",
    tool_uses = list(),
    session_id = "sess_synth"
  )

  olusan_dosyalar <- list(
    list(
      original_path = "/tmp/test/kod_kalitesi_raporu.txt",
      display_name = "kod_kalitesi_raporu.txt",
      size = 6100,
      url = "bilge_yolac_downloads/user_1/session_x/kod_kalitesi_raporu.txt"
    )
  )

  sonuc <- test_env$cc_synthesize_tool_uses_from_downloads(
    session = session,
    ns = session$ns,
    env = env,
    ayristirma = ayristirma,
    olusan_dosyalar = olusan_dosyalar
  )

  expect_equal(
    length(sonuc),
    1L,
    info = paste(
      "Sentetik Write araç bloğu üretilmelidir; modelin gerçek tool_use",
      "yaymadığı ama dosyanın oluşturulduğu senaryoda kullanıcı geri bildirim alır."
    )
  )

  expect_equal(sonuc[[1]]$name, "Write")
  expect_equal(sonuc[[1]]$input$file_path, "/tmp/test/kod_kalitesi_raporu.txt")
  expect_true(grepl("^synth_write_", sonuc[[1]]$id))

  # cc-stream-chunk mesajının UI'a yayınlandığını doğrula (ARAÇ KULLANIMLARI sayacı)
  arac_mesajlari <- Filter(
    function(m) identical(m$type, "cc-stream-chunk") &&
                 identical(m$message$chunkType, "tool_use"),
    session$mesajlar
  )

  expect_equal(
    length(arac_mesajlari),
    1L,
    info = "Sentetik tool_use için cc-stream-chunk mesajı UI'a yayınlanmalıdır."
  )
})

test_that("cc_synthesize_tool_uses_from_downloads model tool_use yaydığında sentetik üretmez", {
  test_env <- .source_cc_synthetic_tools_for_test()

  session <- .cc_fake_session_for_synth()

  env <- new.env(parent = emptyenv())
  env$karakter_renk <- "#81C784"
  env$karakter_adi <- "Mergen"
  env$zaman_damgasi <- "10:00:00"

  ayristirma <- list(
    text_output = "Dosyayı kaydettim.",
    tool_uses = list(
      list(
        id = "toolu_real",
        name = "Write",
        input = list(file_path = "/tmp/test/raporu.txt")
      )
    ),
    session_id = "sess_real"
  )

  olusan_dosyalar <- list(
    list(
      original_path = "/tmp/test/raporu.txt",
      display_name = "raporu.txt",
      size = 1024,
      url = "bilge_yolac_downloads/user_1/session_x/raporu.txt"
    )
  )

  sonuc <- test_env$cc_synthesize_tool_uses_from_downloads(
    session = session,
    ns = session$ns,
    env = env,
    ayristirma = ayristirma,
    olusan_dosyalar = olusan_dosyalar
  )

  expect_equal(
    length(sonuc),
    0L,
    info = paste(
      "Model zaten tool_use yaydıysa sentetik üretilmemelidir; aksi halde",
      "kullanıcı aynı dosya işlemi için iki kart görür."
    )
  )

  expect_equal(
    length(session$mesajlar),
    0L,
    info = "Mevcut tool_use varken cc-stream-chunk mesajı yayınlanmamalıdır."
  )
})

test_that("cc_synthesize_tool_uses_from_downloads boş dosya listesi için boş döner", {
  test_env <- .source_cc_synthetic_tools_for_test()

  session <- .cc_fake_session_for_synth()

  env <- new.env(parent = emptyenv())
  env$karakter_renk <- "#81C784"
  env$karakter_adi <- "Mergen"
  env$zaman_damgasi <- "10:00:00"

  ayristirma <- list(
    text_output = "Sadece metin.",
    tool_uses = list(),
    session_id = "sess_empty"
  )

  sonuc <- test_env$cc_synthesize_tool_uses_from_downloads(
    session = session,
    ns = session$ns,
    env = env,
    ayristirma = ayristirma,
    olusan_dosyalar = list()
  )

  expect_equal(length(sonuc), 0L)
  expect_equal(length(session$mesajlar), 0L)
})

test_that("cc_synthesize_tool_uses_from_downloads birden fazla dosya için her birine ayrı sentetik üretir", {
  test_env <- .source_cc_synthetic_tools_for_test()

  session <- .cc_fake_session_for_synth()

  env <- new.env(parent = emptyenv())
  env$karakter_renk <- "#81C784"
  env$karakter_adi <- "Mergen"
  env$zaman_damgasi <- "10:00:00"

  ayristirma <- list(
    text_output = "İki dosya oluşturdum.",
    tool_uses = list(),
    session_id = "sess_multi"
  )

  olusan_dosyalar <- list(
    list(
      original_path = "/tmp/test/rapor_1.txt",
      display_name = "rapor_1.txt",
      size = 100
    ),
    list(
      original_path = "/tmp/test/rapor_2.txt",
      display_name = "rapor_2.txt",
      size = 200
    )
  )

  sonuc <- test_env$cc_synthesize_tool_uses_from_downloads(
    session = session,
    ns = session$ns,
    env = env,
    ayristirma = ayristirma,
    olusan_dosyalar = olusan_dosyalar
  )

  expect_equal(length(sonuc), 2L)
  expect_equal(sonuc[[1]]$input$file_path, "/tmp/test/rapor_1.txt")
  expect_equal(sonuc[[2]]$input$file_path, "/tmp/test/rapor_2.txt")
  expect_false(
    identical(sonuc[[1]]$id, sonuc[[2]]$id),
    info = "Her sentetik tool_use'un benzersiz id'si olmalıdır."
  )

  arac_mesajlari <- Filter(
    function(m) identical(m$type, "cc-stream-chunk") &&
                 identical(m$message$chunkType, "tool_use"),
    session$mesajlar
  )

  expect_equal(length(arac_mesajlari), 2L)
})
