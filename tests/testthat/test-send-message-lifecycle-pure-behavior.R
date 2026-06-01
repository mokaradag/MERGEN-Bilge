# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-lifecycle-pure-behavior.R
# Açıklama: Mesaj gönderimi yaşam döngüsünün saf yardımcılarını davranışsal
#           kapsar. Mevcut sözleşme testini tamamlar; özellikle:
#           - mergen_build_thinking_panel_plan() için reasoning_will_stream'in
#             araç ailesine göre dışlama matrisi (mcp_excel/sql_analysis/image/
#             summarization akış DIŞI), düşünmeyen model + klasik gösterge
#             matrisi ve override önceliği,
#           - mergen_build_send_message_prompt_snapshot() metin/dosya çıkarımı,
#           - mergen_should_run_deferred_stream_persist() yarış (stale/finalize)
#             koruması.
#           Saf mantık; Shiny/DB/HTTP gerektirmez. Global stub'lar kaydedilip
#           geri yüklenir, böylece tam suite kirlenmez.
# ==============================================================================

.find_lifecycle_pure_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Lifecycle pure davranış testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_lifecycle_pure <- .find_lifecycle_pure_repo_root()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

source(
  file.path(repo_root_lifecycle_pure, "R", "helpers_send_message_request_lifecycle.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Global fonksiyonları geçici olarak değiştirip güvenle geri yükleyen yardımcı.
.lc_stub <- function(name, fn) {
  existed <- exists(name, envir = globalenv(), inherits = FALSE)
  old <- if (existed) get(name, envir = globalenv()) else NULL
  assign(name, fn, envir = globalenv())
  list(name = name, existed = existed, old = old)
}

.lc_unstub <- function(saved) {
  for (s in saved) {
    if (isTRUE(s$existed)) {
      assign(s$name, s$old, envir = globalenv())
    } else if (exists(s$name, envir = globalenv(), inherits = FALSE)) {
      rm(list = s$name, envir = globalenv())
    }
  }
}

.lc_settings <- function(streaming = TRUE, tts = FALSE, typing = FALSE,
                         model_selection = "settings-model") {
  list(
    enable_streaming = streaming,
    enable_tts_audio = tts,
    enable_typing_indicator = typing,
    model_selection = model_selection
  )
}

# --- mergen_build_thinking_panel_plan(): reasoning_will_stream aile matrisi ----

test_that("düşünen model akıştayken akışa izin verilen aileler simüle değildir", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) identical(m, "thinker")),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  for (fam in c("none", "coding")) {
    plan <- mergen_build_thinking_panel_plan(
      tool_family = fam,
      settings_data = .lc_settings(),
      resolved_model_id = "thinker"
    )
    expect_true(plan$thinking_model_active, info = fam)
    expect_true(plan$reasoning_will_stream, info = fam)
    expect_false(plan$panel_simulated, info = fam)
    expect_true(plan$show_thinking_wrapper, info = fam)
  }
})

test_that("akış DIŞI bırakılan aileler reasoning akışı yapmaz (tek stream excel sınırı)", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) identical(m, "thinker")),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  for (fam in c("mcp_excel", "sql_analysis", "image", "summarization")) {
    plan <- mergen_build_thinking_panel_plan(
      tool_family = fam,
      settings_data = .lc_settings(),
      resolved_model_id = "thinker"
    )
    expect_false(plan$reasoning_will_stream, info = fam)
    # Düşünen model olsa bile akış olmadığı için panel simüledir.
    expect_true(plan$panel_simulated, info = fam)
    # Düşünen model aktif olduğundan sarmalayıcı yine gösterilir.
    expect_true(plan$show_thinking_wrapper, info = fam)
  }
})

test_that("streaming kapalı veya TTS açık iken reasoning akışı kapanır", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) identical(m, "thinker")),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  no_stream <- mergen_build_thinking_panel_plan(
    "none", .lc_settings(streaming = FALSE), resolved_model_id = "thinker"
  )
  expect_false(no_stream$reasoning_will_stream)
  expect_true(no_stream$panel_simulated)

  tts_on <- mergen_build_thinking_panel_plan(
    "none", .lc_settings(tts = TRUE), resolved_model_id = "thinker"
  )
  expect_false(tts_on$reasoning_will_stream)
  expect_true(tts_on$panel_simulated)
})

test_that("override reasoning_will_stream aile mantığını ezer", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) identical(m, "thinker")),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  # mcp_excel normalde akış DIŞI; override TRUE bunu ezer.
  forced_on <- mergen_build_thinking_panel_plan(
    "mcp_excel", .lc_settings(), resolved_model_id = "thinker",
    reasoning_will_stream_override = TRUE
  )
  expect_true(forced_on$reasoning_will_stream)
  expect_false(forced_on$panel_simulated)

  # none normalde akışta; override FALSE bunu kapatır.
  forced_off <- mergen_build_thinking_panel_plan(
    "none", .lc_settings(), resolved_model_id = "thinker",
    reasoning_will_stream_override = FALSE
  )
  expect_false(forced_off$reasoning_will_stream)
  expect_true(forced_off$panel_simulated)
})

test_that("düşünmeyen modelde panel simüledir; sarmalayıcı klasik göstergeye bağlıdır", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) FALSE),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  no_classic <- mergen_build_thinking_panel_plan(
    "none", .lc_settings(typing = FALSE), resolved_model_id = "plain"
  )
  expect_false(no_classic$thinking_model_active)
  expect_true(no_classic$panel_simulated)
  expect_false(no_classic$show_thinking_wrapper)

  with_classic <- mergen_build_thinking_panel_plan(
    "none", .lc_settings(typing = TRUE), resolved_model_id = "plain"
  )
  expect_false(with_classic$thinking_model_active)
  expect_true(with_classic$show_thinking_wrapper)
})

test_that("resolved_model_id boşsa panel modeli aile çözümleyiciden gelir", {
  saved <- list(
    .lc_stub("is_thinking_model", function(m) identical(m, "family-model")),
    .lc_stub("resolve_tool_model_for_family", function(tool_family, fallback_model = NULL, ...) "family-model")
  )
  on.exit(.lc_unstub(saved), add = TRUE)

  plan <- mergen_build_thinking_panel_plan(
    "coding", .lc_settings(), resolved_model_id = ""
  )
  expect_identical(plan$panel_model_id, "family-model")
  expect_true(plan$thinking_model_active)

  # Açıkça verilen resolved_model_id korunur.
  plan2 <- mergen_build_thinking_panel_plan(
    "coding", .lc_settings(), resolved_model_id = "explicit-model"
  )
  expect_identical(plan2$panel_model_id, "explicit-model")
})

# --- mergen_build_send_message_prompt_snapshot() ------------------------------

test_that("prompt snapshot metni ve dosyaları doğru çıkarır", {
  snap <- mergen_build_send_message_prompt_snapshot(
    "  merhaba dünya  ",
    function() list()
  )
  expect_identical(snap$user_message_text, "merhaba dünya")
  expect_identical(snap$uploaded_count, 0L)
  expect_identical(snap$uploaded_names, character(0))
})

test_that("prompt snapshot list(text=) biçimini açar ve NULL'u boş yapar", {
  snap_list <- mergen_build_send_message_prompt_snapshot(
    list(text = "liste metni"),
    function() list()
  )
  expect_identical(snap_list$user_message_text, "liste metni")

  snap_null <- mergen_build_send_message_prompt_snapshot(NULL, function() list())
  expect_identical(snap_null$user_message_text, "")
})

test_that("prompt snapshot yüklenen dosya adlarını ve sayısını verir", {
  files <- list(`a.xlsx` = list(path = "/x/a.xlsx"), `b.pdf` = list(path = "/x/b.pdf"))
  snap <- mergen_build_send_message_prompt_snapshot("soru", function() files)
  expect_identical(snap$uploaded_count, 2L)
  expect_setequal(snap$uploaded_names, c("a.xlsx", "b.pdf"))
  expect_identical(snap$current_session_files, files)
})

# --- mergen_should_run_deferred_stream_persist(): yarış koruması ---------------

test_that("ertelenmiş akış kalıcılığı yalnızca güncel ve sonlanmamış istekte çalışır", {
  current_id <- function() "r1"

  # Güncel istek + sonlanmamış akış -> TRUE
  expect_true(mergen_should_run_deferred_stream_persist(current_id, "r1", list(finalized = FALSE)))
  # finalized alanı yoksa (NULL) TRUE olmalı (yalnızca isTRUE(finalized) bloklar)
  expect_true(mergen_should_run_deferred_stream_persist(current_id, "r1", list()))

  # Sonlanmış akış -> FALSE
  expect_false(mergen_should_run_deferred_stream_persist(current_id, "r1", list(finalized = TRUE)))
  # NULL stream_env -> FALSE
  expect_false(mergen_should_run_deferred_stream_persist(current_id, "r1", NULL))
  # Stale istek (id eşleşmiyor) -> FALSE
  expect_false(mergen_should_run_deferred_stream_persist(current_id, "r2", list(finalized = FALSE)))
  # active_request_id fonksiyon değilse -> FALSE
  expect_false(mergen_should_run_deferred_stream_persist("not-a-fn", "r1", list(finalized = FALSE)))
  # Boş/NULL req_id -> FALSE
  expect_false(mergen_should_run_deferred_stream_persist(current_id, "", list(finalized = FALSE)))
  expect_false(mergen_should_run_deferred_stream_persist(current_id, NULL, list(finalized = FALSE)))
})
