# ==============================================================================
# Dosya Yolu: tests/scripts/mock_llm_server.R
# Aciklama:
#   Yerel, OpenAI-uyumlu SAHTE (fake) LLM endpoint'i. SIFIR gercek anahtar
#   kullanir. Soak testinin ana yuksek-eszamanlilik seridi (Lane A) icin
#   tasarlandi: uygulamanin Shiny oturumlarini, akis (streaming) UI'sini, DB
#   yazimlarini ve istek sonlandirmasini gercek bir LLM saglayicisina ihtiyac
#   duymadan zorlamak.
#
#   Protokol uyumu (R/helpers_llm_api.R + R/helpers_llm_sse.R'den dogrulandi):
#     - POST <endpoint>/v1/chat/completions  (ayrica /chat/completions ve / kabul)
#     - Authorization: Bearer <key>  (opsiyonel)
#     - Govde: {model, messages:[{role,content}], stream, temperature, ...}
#     - Non-streaming yanit: {choices:[{message:{content}}]}
#     - Streaming SSE: "data: {choices:[{delta:{content}}]}" ... "data: [DONE]"
#
#   Hata enjeksiyonu: normal, slow, timeout, http500, http429, malformed, empty,
#   interrupted-stream, long, markdown, code, table, turkish.
#
#   Tasarim: SAF "yanit plani" mantigi (mock_llm_response_plan) httpuv'dan
#   ayridir, boylece sozlesme testi soket olmadan dogrudan cagirabilir. Gecikme
#   httpuv altinda promises + later ile BLOKLAMADAN uygulanir (tek thread'li
#   event loop'ta gercek eszamanlilik).
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok). Calisma
#   zamani Turkce metin yukleri \u kacis dizileriyle uretilir (parser-guvenli).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Tum hata/icerik durumlari (sozlesme testi bunlari zorlamali olarak surer).
mock_llm_cases <- function() {
  c("normal", "slow", "timeout", "http500", "http429", "malformed", "empty",
    "interrupted", "long", "markdown", "code", "table", "turkish")
}

# Calisma zamani Turkce metin (parser-guvenli \u kacislari; kaynak ASCII kalir,
# calisma zamani dogru UTF-8 Turkce uretir). Tum Turkce ozel karakterler
# kasitli olarak yer alir: c g i I o s u + buyukleri.
.mock_turkish_sentence <- function() {
  paste0(
    "Bu otomatik soak test yan\u0131t\u0131d\u0131r. ",
    "T\u00fcrk\u00e7e karakterler: \u00e7 \u011f \u0131 \u0130 \u00f6 \u015f \u00fc ",
    "\u00c7 \u011e \u0130 \u00d6 \u015e \u00dc. ",
    "T\u00fcrkiye'nin ba\u015fkenti Ankara'd\u0131r."
  )
}

# Duruma gore icerik metni uretir (Turkce, markdown, kod, tablo, uzun).
mock_llm_content <- function(case) {
  base <- .mock_turkish_sentence()
  switch(
    case,
    markdown = paste0(
      "## \u00d6zet\n\n",
      "**Kal\u0131n** ve *italik* metin. `satir ici kod`.\n\n",
      "- Birinci madde\n- \u0130kinci madde\n- \u00dc\u00e7\u00fcnc\u00fc madde\n\n",
      base
    ),
    code = paste0(
      "A\u015fa\u011f\u0131daki R kodu \u00f6rne\u011fidir:\n\n",
      "```r\n",
      "topla <- function(a, b) {\n  a + b\n}\n",
      "print(topla(2, 3))\n",
      "```\n\n", base
    ),
    table = paste0(
      "| S\u00fctun A | S\u00fctun B | De\u011fer |\n",
      "|---------|---------|-------|\n",
      "| Ankara  | T\u00fcrkiye | 100   |\n",
      "| \u0130stanbul| T\u00fcrkiye | 250   |\n\n",
      base
    ),
    turkish = paste(rep(base, 2L), collapse = " "),
    long = paste(rep(base, 40L), collapse = " "),
    base
  )
}

# Yanit plani: SAF, deterministik. status/headers/body/delay_ms/case doner.
# force_case verilirse (test/zorlamali) o kullanilir; yoksa config oranlarina
# gore agirlikli secim yapilir.
mock_llm_response_plan <- function(req_info, config = list(), force_case = NULL) {
  fake <- config$fake %||% list()
  lat_min <- as.numeric(fake$latency_ms_min %||% 80)
  lat_max <- as.numeric(fake$latency_ms_max %||% 600)
  error_rate <- as.numeric(fake$error_rate %||% 0.02)
  timeout_rate <- as.numeric(fake$timeout_rate %||% 0.01)
  long_rate <- as.numeric(fake$long_response_rate %||% 0.05)
  stream_enabled <- isTRUE(fake$stream %||% TRUE)
  stream_chunks <- as.integer(fake$stream_chunks %||% 12L)
  client_timeout_ms <- as.numeric(config$client_timeout_sec %||% 20) * 1000

  model <- req_info$model %||% "soak-fake-model"
  wants_stream <- isTRUE(req_info$stream) && stream_enabled

  # Durum secimi.
  case <- force_case %||% req_info$force_case
  if (is.null(case) || !nzchar(case)) {
    roll <- stats::runif(1)
    case <- if (roll < timeout_rate) {
      "timeout"
    } else if (roll < timeout_rate + error_rate) {
      sample(c("http500", "http429", "malformed", "empty", "interrupted"), 1)
    } else if (roll < timeout_rate + error_rate + long_rate) {
      "long"
    } else {
      sample(c("normal", "markdown", "code", "table", "turkish"),
             1, prob = c(0.5, 0.15, 0.15, 0.1, 0.1))
    }
  }

  # Gecikme.
  delay_ms <- stats::runif(1, lat_min, lat_max)
  if (identical(case, "slow")) {
    delay_ms <- lat_max
  }
  if (identical(case, "timeout")) {
    # Client timeout'unu asacak gecikme (gercek timeout uretir).
    delay_ms <- client_timeout_ms + 2000
  }

  # Hata durumlari.
  if (identical(case, "http500")) {
    return(list(
      case = case, status = 500L, delay_ms = min(delay_ms, lat_max),
      headers = list("Content-Type" = "application/json"),
      body = '{"error":{"message":"soak injected server error","type":"server_error","code":500}}'
    ))
  }
  if (identical(case, "http429")) {
    return(list(
      case = case, status = 429L, delay_ms = min(delay_ms, lat_max),
      headers = list("Content-Type" = "application/json", "Retry-After" = "1"),
      body = '{"error":{"message":"soak injected rate limit","type":"rate_limit","code":429}}'
    ))
  }
  if (identical(case, "malformed")) {
    return(list(
      case = case, status = 200L, delay_ms = min(delay_ms, lat_max),
      headers = list("Content-Type" = "application/json"),
      body = '{"choices":[{"message":{"content":"yarim'  # bilerek bozuk/kapanmamis JSON
    ))
  }
  if (identical(case, "empty")) {
    return(list(
      case = case, status = 200L, delay_ms = min(delay_ms, lat_max),
      headers = list("Content-Type" = "application/json"),
      body = ""
    ))
  }

  content <- mock_llm_content(case)

  if (wants_stream || identical(case, "interrupted")) {
    sse <- mock_llm_build_sse_body(
      content = content,
      n_chunks = max(1L, stream_chunks),
      interrupted = identical(case, "interrupted")
    )
    return(list(
      case = case, status = 200L, delay_ms = delay_ms,
      headers = list("Content-Type" = "text/event-stream", "Cache-Control" = "no-cache"),
      body = sse
    ))
  }

  list(
    case = case, status = 200L, delay_ms = delay_ms,
    headers = list("Content-Type" = "application/json"),
    body = mock_llm_build_json_body(model = model, content = content)
  )
}

# Non-streaming OpenAI-uyumlu JSON govdesi.
mock_llm_build_json_body <- function(model, content) {
  obj <- list(
    id = paste0("soak-", as.integer(stats::runif(1, 1e6, 9e6))),
    object = "chat.completion",
    model = model,
    choices = list(list(
      index = 0L,
      message = list(role = "assistant", content = content),
      finish_reason = "stop"
    )),
    usage = list(prompt_tokens = 16L, completion_tokens = nchar(content) %/% 4L,
                 total_tokens = 16L + nchar(content) %/% 4L)
  )
  as.character(jsonlite::toJSON(obj, auto_unbox = TRUE, null = "null"))
}

# SSE govdesi: icerigi n parcaya boler, her parca "data: {delta}\n\n", sonunda
# "data: [DONE]\n\n". interrupted=TRUE ise [DONE] ve son parca atlanir.
mock_llm_build_sse_body <- function(content, n_chunks = 12L, interrupted = FALSE) {
  chars <- strsplit(content, "", fixed = TRUE)[[1]]
  if (length(chars) == 0L) chars <- " "
  n_chunks <- max(1L, min(n_chunks, length(chars)))
  groups <- split(chars, cut(seq_along(chars), breaks = n_chunks, labels = FALSE))
  pieces <- vapply(groups, function(g) paste(g, collapse = ""), character(1))

  if (isTRUE(interrupted) && length(pieces) > 2L) {
    # Akis ortasinda kesilir: son birkac parca ve [DONE] yok.
    pieces <- pieces[seq_len(length(pieces) - 2L)]
  }

  lines <- vapply(pieces, function(p) {
    delta <- list(choices = list(list(index = 0L, delta = list(content = p))))
    sprintf("data: %s\n\n",
            as.character(jsonlite::toJSON(delta, auto_unbox = TRUE, null = "null")))
  }, character(1))

  body <- paste(lines, collapse = "")
  if (!isTRUE(interrupted)) {
    body <- paste0(body, "data: [DONE]\n\n")
  }
  enc2utf8(body)
}

# httpuv req ortamindan istek bilgisini cikarir (method, path, auth, body alanlari).
mock_llm_parse_request <- function(req) {
  method <- toupper(req[["REQUEST_METHOD"]] %||% "GET")
  path <- req[["PATH_INFO"]] %||% "/"
  auth <- req[["HTTP_AUTHORIZATION"]] %||% ""
  force_case <- req[["HTTP_X_SOAK_FORCE"]] %||% ""

  body_text <- ""
  input <- req[["rook.input"]]
  if (!is.null(input)) {
    body_text <- tryCatch({
      raw <- input$read()
      if (length(raw) > 0L) rawToChar(raw) else ""
    }, error = function(e) "")
  }

  parsed <- tryCatch(
    if (nzchar(body_text)) jsonlite::fromJSON(body_text, simplifyVector = FALSE) else list(),
    error = function(e) list()
  )

  list(
    method = method,
    path = path,
    authorization = auth,
    force_case = if (nzchar(force_case)) force_case else NULL,
    model = parsed$model %||% NULL,
    stream = isTRUE(parsed$stream),
    messages = parsed$messages %||% list()
  )
}

# httpuv app nesnesi olusturur. state, istek sayaclarini tutar.
mock_llm_app <- function(config = list(), state = NULL) {
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$requests <- 0L
    state$case_counts <- list()
  }

  handle_sync <- function(req) {
    info <- mock_llm_parse_request(req)

    # Saglik ve ozet uclari.
    if (identical(info$method, "GET")) {
      if (grepl("healthz", info$path, fixed = TRUE)) {
        return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                    body = '{"status":"ok","server":"mock-llm"}'))
      }
      if (grepl("mock-summary", info$path, fixed = TRUE)) {
        summ <- list(server = "mock-llm", requests = state$requests,
                     case_counts = state$case_counts)
        return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                    body = as.character(jsonlite::toJSON(summ, auto_unbox = TRUE, null = "null"))))
      }
      return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                  body = '{"status":"ok","hint":"POST /v1/chat/completions"}'))
    }

    plan <- mock_llm_response_plan(info, config = config, force_case = info$force_case)

    state$requests <- state$requests + 1L
    state$case_counts[[plan$case]] <- (state$case_counts[[plan$case]] %||% 0L) + 1L

    plan
  }

  list(
    call = function(req) {
      plan <- handle_sync(req)
      response <- list(status = plan$status, headers = plan$headers, body = plan$body)
      delay_ms <- as.numeric(plan$delay_ms %||% 0)

      # Bloklamayan gecikme: promise + later. httpuv promise donusunu bekler.
      if (delay_ms > 0 && requireNamespace("promises", quietly = TRUE) &&
          requireNamespace("later", quietly = TRUE)) {
        promises::promise(function(resolve, reject) {
          later::later(function() resolve(response), delay_ms / 1000)
        })
      } else {
        response
      }
    },
    onHeaders = function(req) NULL
  )
}

# Adanmis bir surecte httpuv sunucusunu calistirir (callr ile cagrilir).
mock_llm_run <- function(host, port, config = list(), log_path = NULL,
                         ready_path = NULL) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
    ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (isTRUE(ok)) break
  }

  log_con <- NULL
  if (!is.null(log_path)) {
    log_con <- file(log_path, open = "wt", encoding = "UTF-8")
    on.exit(try(close(log_con), silent = TRUE), add = TRUE)
  }
  emit <- function(...) {
    line <- paste0("[mock-llm] ", sprintf(...))
    if (!is.null(log_con)) writeLines(line, log_con) else cat(line, "\n")
    if (!is.null(log_con)) flush(log_con)
  }

  app <- mock_llm_app(config = config)

  # Once baglan (startServer), SONRA ready isaretle: ready dosyasi sunucu
  # gercekten dinlemeye basladiktan sonra yazilmali (race onlenir).
  server <- tryCatch(
    httpuv::startServer(host, port, app),
    error = function(e) {
      emit("bind hatasi %s:%d -> %s", host, port, conditionMessage(e))
      NULL
    }
  )

  if (is.null(server)) {
    if (!is.null(ready_path)) writeLines("BIND_FAILED", ready_path)
    return(invisible(FALSE))
  }

  on.exit(try(httpuv::stopServer(server), silent = TRUE), add = TRUE)
  emit("listening on http://%s:%d (fake OpenAI-compatible)", host, port)
  if (!is.null(ready_path)) {
    writeLines(sprintf("%s:%d", host, port), ready_path)
  }

  # Servis dongusu: httpuv olaylarini ve gecikmeli yanitlar icin later
  # callback'lerini bloklamadan isler. Bu, tek thread'li event loop'ta gercek
  # eszamanli istek islemeyi saglar.
  repeat {
    httpuv::service(100)
    later::run_now(timeoutSecs = 0)
  }

  invisible(TRUE)
}
