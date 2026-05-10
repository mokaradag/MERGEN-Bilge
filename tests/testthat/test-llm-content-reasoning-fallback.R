# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-content-reasoning-fallback.R
# Açıklama: Thinking/reasoning model yanıtlarında boş content alanının reasoning
#           fallback metnini ezmemesini doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.find_repo_root_llm_fallback <- function() {
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

repo_root_llm_fallback <- .find_repo_root_llm_fallback()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

source(
  file.path(repo_root_llm_fallback, "R", "helpers_llm_response_postprocess.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.with_reasoning_fallback_stub <- function(value, expr) {
  old_exists <- exists(
    "should_allow_reasoning_fallback",
    envir = globalenv(),
    inherits = FALSE
  )

  old_value <- NULL
  if (old_exists) {
    old_value <- get(
      "should_allow_reasoning_fallback",
      envir = globalenv(),
      inherits = FALSE
    )
  }

  assign(
    "should_allow_reasoning_fallback",
    function(model_id = NULL, config = NULL) isTRUE(value),
    envir = globalenv()
  )

  on.exit({
    if (old_exists) {
      assign("should_allow_reasoning_fallback", old_value, envir = globalenv())
    } else {
      rm("should_allow_reasoning_fallback", envir = globalenv())
    }
  }, add = TRUE)

  eval.parent(substitute(expr))
}

test_that("reasoning fallback boş message$content tarafından ezilmez", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "",
          reasoning_content = "Bu reasoning metni fallback olarak kullanılmalı."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(TRUE, {
    out <- extract_llm_content_and_sources(response, model_id = "thinking-model")

    expect_identical(
      out$content,
      "Bu reasoning metni fallback olarak kullanılmalı."
    )

    expect_identical(
      out$reasoning,
      "Bu reasoning metni fallback olarak kullanılmalı."
    )
  })
})

test_that("reasoning fallback kapalıysa boş content boş kalır ama reasoning korunur", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "",
          reasoning_content = "Bu metin sadece reasoning kanalında kalmalı."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(FALSE, {
    out <- extract_llm_content_and_sources(response, model_id = "non-thinking-model")

    expect_identical(out$content, "")
    expect_identical(out$reasoning, "Bu metin sadece reasoning kanalında kalmalı.")
  })
})

test_that("normal content varsa reasoning fallback normal cevabı değiştirmez", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "Nihai cevap budur.",
          reasoning_content = "Bu iç reasoning metnidir."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(TRUE, {
    out <- extract_llm_content_and_sources(response, model_id = "thinking-model")

    expect_identical(out$content, "Nihai cevap budur.")
    expect_identical(out$reasoning, "Bu iç reasoning metnidir.")
  })
})

test_that("delta$content boş olsa bile delta$reasoning_content fallback olabilir", {
  response <- list(
    choices = list(
      list(
        delta = list(
          content = "",
          reasoning_content = "Delta reasoning fallback metni."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(TRUE, {
    out <- extract_llm_content_and_sources(response, model_id = "thinking-model")

    expect_identical(out$content, "Delta reasoning fallback metni.")
    expect_identical(out$reasoning, "Delta reasoning fallback metni.")
  })
})

test_that("OpenAI uyumlu message$content normal cevap olarak ayrıştırılır", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = "Normal OpenAI uyumlu yanıt.",
          reasoning_content = "Bu iç reasoning metnidir."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(TRUE, {
    out <- extract_llm_content_and_sources(response, model_id = "thinking-model")

    expect_identical(out$content, "Normal OpenAI uyumlu yanıt.")
    expect_identical(out$reasoning, "Bu iç reasoning metnidir.")
  })
})

test_that("streaming delta$content görünür cevap olarak ayrıştırılır", {
  response <- list(
    choices = list(
      list(
        delta = list(
          content = "Canlı delta yanıtı."
        )
      )
    )
  )

  .with_reasoning_fallback_stub(TRUE, {
    out <- extract_llm_content_and_sources(response, model_id = "thinking-model")

    expect_identical(out$content, "Canlı delta yanıtı.")
    expect_identical(out$reasoning, "")
  })
})

test_that("choice text alanı görünür cevap olarak ayrıştırılır", {
  response <- list(
    choices = list(
      list(
        text = "Text alanından gelen yanıt."
      )
    )
  )

  .with_reasoning_fallback_stub(FALSE, {
    out <- extract_llm_content_and_sources(response, model_id = "plain-model")

    expect_identical(out$content, "Text alanından gelen yanıt.")
    expect_identical(out$reasoning, "")
  })
})

test_that("liste tabanlı metin düğümleri tek UTF-8 cevaba indirilir", {
  response <- list(
    choices = list(
      list(
        message = list(
          content = list(
            list(text = "İlk "),
            list(content = "parça")
          )
        )
      )
    )
  )

  .with_reasoning_fallback_stub(FALSE, {
    out <- extract_llm_content_and_sources(response, model_id = "plain-model")

    expect_identical(out$content, "İlk parça")
    expect_identical(out$reasoning, "")
  })
})