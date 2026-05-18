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

test_that("cc_synthesize_tool_uses_from_downloads aynı dosya yolu için tekrar sentetik üretmez", {
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
      "Gerçek tool_use aynı dosya yolu için zaten varsa sentetik üretilmemelidir;",
      "aksi halde kullanıcı aynı dosya işlemi için iki kart görür."
    )
  )

  expect_equal(
    length(session$mesajlar),
    0L,
    info = "Aynı dosya yolu kapsandığında cc-stream-chunk mesajı yayınlanmamalıdır."
  )
})

test_that("cc_synthesize_tool_uses_from_downloads gerçek tool_use kapsamadığı dosyalar için sentetik üretir", {
  # Parser bir tool_use yakaladıysa (örn. Read), ama snapshot diff başka
  # dosyalar (örn. Write çıktıları) tespit ettiyse, kapsanmamış dosyalar
  # için sentetik Write üretilmelidir. Aksi halde model gerçek anlamda
  # dosyaları üretmiş olsa bile ARAÇ KULLANIMLARI sayacı yetersiz görünür.
  test_env <- .source_cc_synthetic_tools_for_test()

  session <- .cc_fake_session_for_synth()

  env <- new.env(parent = emptyenv())
  env$karakter_renk <- "#81C784"
  env$karakter_adi <- "Mergen"
  env$zaman_damgasi <- "10:00:00"

  ayristirma <- list(
    text_output = "Okudum ve özetledim.",
    tool_uses = list(
      list(
        id = "toolu_read",
        name = "Read",
        input = list(file_path = "/tmp/test/girdi.pdf")
      )
    ),
    session_id = "sess_read"
  )

  olusan_dosyalar <- list(
    list(
      original_path = "/tmp/test/ozet_1.txt",
      display_name = "ozet_1.txt",
      size = 100
    ),
    list(
      original_path = "/tmp/test/ozet_2.txt",
      display_name = "ozet_2.txt",
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

  expect_equal(
    length(sonuc),
    2L,
    info = paste(
      "Read tool_use mevcut olsa bile, snapshot diff'in tespit ettiği iki",
      "yeni dosya için sentetik Write üretilmelidir."
    )
  )

  arac_mesajlari <- Filter(
    function(m) identical(m$type, "cc-stream-chunk") &&
                 identical(m$message$chunkType, "tool_use"),
    session$mesajlar
  )

  expect_equal(length(arac_mesajlari), 2L)
})

test_that("cc_collect_covered_tool_paths tool_use girdilerinden dosya yollarını çıkarır", {
  test_env <- .source_cc_synthetic_tools_for_test()

  tool_uses <- list(
    list(
      id = "toolu_a",
      name = "Write",
      input = list(file_path = "/tmp/a.txt")
    ),
    list(
      id = "toolu_b",
      name = "Edit",
      input = list(path = "/tmp/b.md")
    ),
    list(
      id = "toolu_c",
      name = "Bash",
      input = list(command = "ls")
    )
  )

  yollar <- test_env$cc_collect_covered_tool_paths(tool_uses)

  expect_true("/tmp/a.txt" %in% yollar)
  expect_true("/tmp/b.md" %in% yollar)
  expect_equal(length(yollar), 2L,
               info = "Bash gibi dosya yolu olmayan tool_use'lar yol setine eklenmemelidir.")
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

# ==============================================================================
# FINAL TOOL USE HTML SÖZLEŞMESİ
# Canlı akış chunk'ları araç bloklarını eksik veya hiç yayınlamadığında ya da
# on-prem LLM proxy varyantı tool_use'ları farklı biçimde emit ettiğinde,
# cc-stream-end mesajıyla birlikte gönderilen finalToolUsesHtml alanı son
# durumu garanti eder. Böylece ARAÇ KULLANIMLARI sayacı gerçek tool_use
# sayısını yansıtır.
# ==============================================================================

.read_repo_text_cc_final_tool_uses_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
}

test_that("module_claude_code_stream_poll.R cc-stream-end mesajına finalToolUsesHtml ekler", {
  txt <- .read_repo_text_cc_final_tool_uses_contract(
    "R/module_claude_code_stream_poll.R"
  )

  expect_true(
    grepl("finalToolUsesHtml\\s*=\\s*son_arac_kullanim_html", txt, perl = TRUE),
    info = paste(
      "cc-stream-end mesajı finalToolUsesHtml alanını içermelidir; aksi halde",
      "canlı akış araç bloklarını eksik yayınladığında ARAÇ KULLANIMLARI",
      "sayacı 0 kalır."
    )
  )

  expect_true(
    grepl(
      "format_tool_uses_html_enhanced\\(ayristirma\\$tool_uses\\)",
      txt,
      perl = TRUE
    ),
    info = paste(
      "Final tool_use HTML formatters helper ile üretilmelidir;",
      "tool_uses bulunamadığında boş string gönderilmelidir."
    )
  )
})

test_that("claude_code_streaming.js cc-stream-end içinde finalToolUsesHtml'i işler", {
  txt <- .read_repo_text_cc_final_tool_uses_contract(
    "www/js/claude_code_streaming.js"
  )

  expect_true(
    grepl("data.finalToolUsesHtml", txt, fixed = TRUE),
    info = paste(
      "Sunucudan gelen finalToolUsesHtml alanı JS tarafında okunmalı ve",
      "mevcut/eksik .cc-tool-section yerine yeni HTML yerleştirilmelidir."
    )
  )

  expect_true(
    grepl("cc-tool-section", txt, fixed = TRUE),
    info = "JS handler tool section seçicisini kullanmalıdır."
  )
})

test_that("format_tool_uses_html_enhanced bilgilendirici sayaç ve blok HTML üretir", {
  test_env <- .source_cc_synthetic_tools_for_test()

  tool_uses <- list(
    list(
      id = "toolu_bash_1",
      name = "Bash",
      input = list(command = "ls -la"),
      result = "dosya1.txt\ndosya2.txt"
    ),
    list(
      id = "toolu_write_1",
      name = "Write",
      input = list(file_path = "/tmp/test/rapor.txt", content = "Selam"),
      result = "Dosya yazıldı."
    )
  )

  html <- test_env$format_tool_uses_html_enhanced(tool_uses)

  expect_true(nzchar(html))
  expect_true(grepl("cc-tool-section", html, fixed = TRUE))
  expect_true(grepl("cc-tool-count", html, fixed = TRUE))
  expect_true(
    grepl("(2)", html, fixed = TRUE),
    info = "Sayaç tool_uses uzunluğunu yansıtmalıdır."
  )
  expect_true(
    grepl("Kabuk Komutu", html, fixed = TRUE),
    info = "Bash aracı için Türkçe başlık üretilmelidir."
  )
  expect_true(
    grepl("ls -la", html, fixed = TRUE),
    info = "Bash komutu kabuk içeriği olarak render edilmelidir."
  )
  expect_true(
    grepl("Dosya Yazma", html, fixed = TRUE),
    info = "Write aracı için Türkçe başlık üretilmelidir."
  )
})

test_that("config_claude_code.R varsayılan allowed_tools listesi Bash içerir", {
  txt <- .read_repo_text_cc_final_tool_uses_contract("R/config_claude_code.R")

  expect_true(
    grepl(
      "Read;Write;Edit;MultiEdit;Glob;Grep;LS;Bash",
      txt,
      fixed = TRUE
    ),
    info = paste(
      "MERGEN Bilge kurumsal/on-prem ortamda çalıştığı için Bash varsayılan",
      "olarak izinli olmalıdır; aksi halde model canlı kabuk komutu",
      "çalıştıramaz ve kullanıcı tool_use sayacında 0 görür."
    )
  )
})

test_that("claude_code_streaming.js shellVisible değişkenini açıkça bildirir (ReferenceError regresyon koruması)", {
  # Kritik bug: 'use strict' altındaki IIFE içinde shellVisible bildirilmemişti.
  # handleToolUseChunk içinde 'if (!shellVisible)' satırı çalıştığında strict
  # mode ReferenceError fırlatıyor, append işlemi yarıda kesiliyordu. Sonuç:
  # .cc-tool-section oluşturuluyor ama içine cc-tool-block eklenmiyor; sayaç
  # canlı akışta "(0)" ve içerik boş kalıyordu. Bloklar yalnızca cc-stream-end
  # finalToolUsesHtml ile toplu olarak görünüyordu.
  txt <- .read_repo_text_cc_final_tool_uses_contract("www/js/claude_code_streaming.js")

  expect_true(
    grepl("var\\s+shellVisible\\s*=", txt, perl = TRUE),
    info = paste(
      "shellVisible IIFE kapsamında 'var shellVisible = ...' ile bildirilmelidir;",
      "aksi halde strict mode ReferenceError fırlatır ve canlı araç bloğu",
      "akışı kesilir."
    )
  )

  # shellVisible'a okuma ve yazma erişimi olduğunu doğrula; ileride
  # değişkenin bildiriliyor ama hiç kullanılmıyor olarak silinmediğinden
  # emin olmak için.
  expect_true(
    grepl("if\\s*\\(\\s*!\\s*shellVisible\\s*\\)", txt, perl = TRUE),
    info = "handleToolUseChunk shellVisible flag'ini kontrol etmelidir."
  )

  expect_true(
    grepl("shellVisible\\s*=\\s*!shellVisible", txt, perl = TRUE),
    info = "ccToggleShellVisibility shellVisible flag'ini tersine çevirmelidir."
  )
})
