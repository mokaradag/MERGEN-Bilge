# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-second-pass-pure-behavior.R
# Açıklama: helpers_llm_worker_second_pass.R içindeki SAF yardımcıların mevcut
#           sözleşme testinde kapsanmayan davranışlarını doldurur:
#           - llm_worker_second_pass_headers() (mevcut testte 0 referans),
#           - llm_worker_second_pass_fallback_response() (0 referans),
#           - llm_worker_stream_content_looks_like_reasoning() için mevcut testte
#             denenmeyen regex ön-ek dalları ve boş/NA içerik kapısı.
#           Ağ (httr/SSE) gerektiren yollar bilinçli olarak kapsanmaz.
#           format_answer_from_tool_results stub'u kaydedilip geri yüklenir.
# ==============================================================================

.find_second_pass_pure_repo_root <- function() {
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

  stop("Second-pass pure davranış testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_second_pass_pure <- .find_second_pass_pure_repo_root()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

source(
  file.path(repo_root_second_pass_pure, "R", "helpers_llm_worker_second_pass.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# --- llm_worker_second_pass_headers() ----------------------------------------

test_that("ikinci geçiş header'ları yalnızca anahtar varsa Authorization ekler", {
  no_key <- llm_worker_second_pass_headers(NULL)
  expect_identical(no_key$`Content-Type`, "application/json")
  expect_null(no_key$Authorization)

  empty_key <- llm_worker_second_pass_headers("")
  expect_null(empty_key$Authorization)

  with_key <- llm_worker_second_pass_headers("anahtar-degeri")
  expect_identical(with_key$Authorization, "Bearer anahtar-degeri")
  expect_identical(with_key$`Content-Type`, "application/json")
})

# --- llm_worker_second_pass_fallback_response() ------------------------------

# format_answer_from_tool_results global stub'u güvenle değiştir/geri yükle.
.with_format_stub <- function(fn, code) {
  name <- "format_answer_from_tool_results"
  existed <- exists(name, envir = globalenv(), inherits = FALSE)
  old <- if (existed) get(name, envir = globalenv()) else NULL
  assign(name, fn, envir = globalenv())
  on.exit({
    if (isTRUE(existed)) {
      assign(name, old, envir = globalenv())
    } else if (exists(name, envir = globalenv(), inherits = FALSE)) {
      rm(list = name, envir = globalenv())
    }
  }, add = TRUE)
  force(code)
}

test_that("fallback yanıtı araç çıktısı metnini kullanır ve chart_store taşır", {
  .with_format_stub(function(x) "Araç cevabı", {
    out <- llm_worker_second_pass_fallback_response(
      tool_results_raw = list(),
      chart_blocks_text = "",
      charts_to_store = list(grafik = 1),
      add_fallback_chart = function(x) x,
      worker_start_time = Sys.time() - 2
    )
    expect_identical(out$content, "Araç cevabı")
    expect_identical(out$chart_store, list(grafik = 1))
    expect_true(is.numeric(out$duration))
    expect_null(out$reasoning_content)
  })
})

test_that("fallback yanıtı boş araç çıktısında varsayılan mesaja düşer", {
  .with_format_stub(function(x) "   ", {
    out <- llm_worker_second_pass_fallback_response(
      tool_results_raw = list(),
      chart_blocks_text = "",
      charts_to_store = list(),
      add_fallback_chart = function(x) x,
      worker_start_time = Sys.time(),
      message = "VARSAYILAN-MESAJ"
    )
    expect_identical(out$content, "VARSAYILAN-MESAJ")
  })
})

test_that("fallback yanıtı chart_blocks_text ekler ve add_fallback_chart uygular", {
  .with_format_stub(function(x) "Ana cevap", {
    out <- llm_worker_second_pass_fallback_response(
      tool_results_raw = list(),
      chart_blocks_text = "CHART-BLOK",
      charts_to_store = list(),
      add_fallback_chart = function(x) paste0(x, " [son-grafik]"),
      worker_start_time = Sys.time()
    )
    expect_identical(out$content, "Ana cevap\n\nCHART-BLOK [son-grafik]")
  })
})

test_that("fallback yanıtı reasoning_content'i yalnızca doluysa ekler", {
  .with_format_stub(function(x) "Cevap", {
    with_reasoning <- llm_worker_second_pass_fallback_response(
      tool_results_raw = list(), chart_blocks_text = "", charts_to_store = list(),
      add_fallback_chart = function(x) x, worker_start_time = Sys.time(),
      reasoning_content = "akil yurutme"
    )
    expect_identical(with_reasoning$reasoning_content, "akil yurutme")

    empty_reasoning <- llm_worker_second_pass_fallback_response(
      tool_results_raw = list(), chart_blocks_text = "", charts_to_store = list(),
      add_fallback_chart = function(x) x, worker_start_time = Sys.time(),
      reasoning_content = ""
    )
    expect_null(empty_reasoning$reasoning_content)
  })
})

# --- llm_worker_stream_content_looks_like_reasoning(): denenmeyen dallar -------

test_that("akış içeriği reasoning ön-ek desenlerini tanır (denenmeyen dallar)", {
  # Mevcut test yalnızca eşitlik + 'Okay, I will' dalını kapsıyor.
  expect_true(llm_worker_stream_content_looks_like_reasoning("**Analyze the Request: ...", ""))
  expect_true(llm_worker_stream_content_looks_like_reasoning("1. **Analyze the Request now", ""))
  expect_true(llm_worker_stream_content_looks_like_reasoning("Let's assemble the final answer", ""))
  expect_true(llm_worker_stream_content_looks_like_reasoning("I will structure it logically", ""))
  expect_true(llm_worker_stream_content_looks_like_reasoning("Thinking Process: adimlar", ""))
})

test_that("akış içeriği trim sonrası reasoning'e eşitse reasoning sayılır", {
  expect_true(llm_worker_stream_content_looks_like_reasoning("  ayni metin  ", "ayni metin"))
})

test_that("boş/NA içerik veya normal cevap reasoning sayılmaz", {
  # Boş içerik kapısı: nzchar(stream_content) FALSE -> reasoning boş olsa bile FALSE.
  expect_false(llm_worker_stream_content_looks_like_reasoning("", ""))
  expect_false(llm_worker_stream_content_looks_like_reasoning(NA, "herhangi"))
  # Normal cevap, reasoning'den farklı ve ön-ek yok -> FALSE.
  expect_false(llm_worker_stream_content_looks_like_reasoning(
    "İşte sonuç: toplam 42.",
    "Thinking Process: ..."
  ))
})
