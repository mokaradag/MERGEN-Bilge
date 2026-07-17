# R/helpers_speech_voxcpm2_adapter.R
# VoxCPM2 servis adaptörü: uygulamanın kararlı iç sözleşmesini (profil +
# kilitli referans + metin) gerçek servis isteğine çevirir. Uç noktaya özgü
# alan adlarını YALNIZCA bu dosya bilir; referans klonlama alan adları uç
# nokta sözleşmesi VM'de doğrulanana kadar ortam değişkenleriyle eşlenebilir.
# Worker-güvenlidir: Shiny/reactive erişimi yoktur.

#' Ses kimlik modu: "locked_reference" (varsayılan, fail-closed persona
#' referansı zorunlu) veya "legacy_alias" (yalnızca bilinçli operatör geçişi).
mergen_speech_voice_mode <- function() {
  mode <- tolower(trimws(Sys.getenv("MERGEN_SPEECH_VOICE_MODE", "locked_reference")))
  if (identical(mode, "legacy_alias")) return("legacy_alias")
  "locked_reference"
}

#' Akış modu: "buffered" (varsayılan; tam yanıt) veya "chunked_pcm" (uç nokta
#' ham PCM'i parça parça akıtabildiğinde gerçek akış). Bilinmeyen değerler
#' güvenli biçimde "buffered" olur.
mergen_voxcpm2_streaming_mode <- function() {
  mode <- tolower(trimws(Sys.getenv("VOXCPM2_STREAMING_MODE", "buffered")))
  if (identical(mode, "chunked_pcm")) return("chunked_pcm")
  "buffered"
}

#' Referans klonlama alan adları (uç nokta sözleşmesine göre ayarlanabilir).
mergen_voxcpm2_ref_field_names <- function() {
  audio_field <- trimws(Sys.getenv("VOXCPM2_REF_AUDIO_FIELD", "ref_audio"))
  text_field <- trimws(Sys.getenv("VOXCPM2_REF_TEXT_FIELD", "ref_text"))
  if (!nzchar(audio_field)) audio_field <- "ref_audio"
  if (!nzchar(text_field)) text_field <- "ref_text"
  list(audio = audio_field, text = text_field)
}

#' TTS uç noktası URL'si (.../audio/speech biçimine tamamlanır).
mergen_voxcpm2_endpoint_url <- function(base_url = NULL) {
  base <- base_url %||% Sys.getenv("LOCAL_TTS_ENDPOINT", "")
  base <- trimws(base)
  if (!nzchar(base)) return("")
  base <- sub("/+$", "", base)
  if (grepl("/audio/speech$", base, ignore.case = TRUE)) return(base)
  paste0(base, "/audio/speech")
}

#' OpenAI uyumlu istek gövdesi kur. Kilitli referans modunda referans sesi ve
#' birebir referans metni gövdeye eklenir; kimliği etkileyen parametreler
#' profilden gelir. `reference = NULL` yalnızca legacy_alias modunda geçerlidir.
#'
#' @param profile mergen_speech_voice_profile() çıktısı (legacy modda NULL olabilir).
#' @param text Seslendirilecek metin.
#' @param reference mergen_speech_reference_payload() çıktısı veya NULL.
#' @param response_format "wav" | "mp3" | "pcm".
#' @param stream TRUE ise akış bayrağı eklenir (chunked_pcm taşıması).
#' @param legacy_voice legacy_alias modunda kullanılacak eski ses etiketi.
mergen_voxcpm2_request_body <- function(profile, text, reference = NULL,
                                        response_format = "wav",
                                        stream = FALSE,
                                        legacy_voice = NULL) {
  body <- list(
    model = if (!is.null(profile)) profile$model else Sys.getenv("LOCAL_TTS_MODEL", "voxcpm2"),
    input = as.character(text)[1],
    response_format = response_format
  )

  if (!is.null(reference) && isTRUE(reference$ok)) {
    fields <- mergen_voxcpm2_ref_field_names()

    # Bu VoxCPM2 uç noktası yalnızca voice="default" kabul eder.
    # Persona kimliği ref_audio + ref_text referans çiftiyle belirlenir.
    body$voice <- "default"

    # Uç nokta bare base64 değil, URL biçimi bekler.
    body[[fields$audio]] <- paste0(
      "data:audio/wav;base64,",
      reference$ref_b64
    )

    body[[fields$text]] <- reference$ref_text
  } else if (identical(mergen_speech_voice_mode(), "legacy_alias")) {
    body$voice <- as.character(legacy_voice %||% Sys.getenv("LOCAL_TTS_VOICE", "tr-male-1"))
  } else {
    stop("Kilitli referans modunda referans yükü olmadan istek kurulamaz (fail-closed).")
  }

  if (!is.null(profile)) {
    params <- profile$identity_params %||% list()
    for (nm in names(params)) {
      if (!is.null(params[[nm]]) && !is.na(params[[nm]])) body[[nm]] <- params[[nm]]
    }
  }

  if (isTRUE(stream)) body$stream <- TRUE
  body
}

#' Log/hata metinlerinden gizli değerleri ve büyük base64 yüklerini ayıkla.
mergen_voxcpm2_redact <- function(x) {
  txt <- paste(as.character(x), collapse = " ")
  txt <- gsub("Bearer\\s+[A-Za-z0-9._~+/=-]+", "Bearer [GIZLI]", txt)
  fields <- mergen_voxcpm2_ref_field_names()
  for (field in c(fields$audio, "api_key", "authorization")) {
    pattern <- sprintf("(\"%s\"\\s*:\\s*\")[^\"]*(\")", field)
    txt <- gsub(pattern, "\\1[GIZLI]\\2", txt, ignore.case = TRUE)
  }
  # Uzun base64 blokları kırp (referans sesi asla loglanmasın)
  txt <- gsub("[A-Za-z0-9+/]{160,}={0,2}", "[BASE64-KIRPILDI]", txt)
  txt
}

#' Bloklayıcı (senkron) sentez çağrısı. RStudio üretici akışında ve worker
#' task_fn içinde kullanılır. Ham ses baytları döner; hata metinleri gizli
#' değer içermez.
#'
#' @return list(success, audio_raw, content_type, http_status, error)
mergen_voxcpm2_synthesize_blocking <- function(body,
                                               endpoint_url = mergen_voxcpm2_endpoint_url(),
                                               api_key = "",
                                               timeout_seconds = 90,
                                               verify_ssl = TRUE) {
  fail <- function(error, status = NA_integer_) {
    list(success = FALSE, audio_raw = NULL, content_type = NA_character_,
         http_status = status, error = mergen_voxcpm2_redact(error))
  }

  if (!nzchar(endpoint_url)) return(fail("TTS uç noktası yapılandırılmamış."))
  if (!requireNamespace("httr", quietly = TRUE)) return(fail("httr paketi yok."))

  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds))
  if (is.na(timeout_seconds) || timeout_seconds <= 0) timeout_seconds <- 90

  req_config <- if (isTRUE(verify_ssl)) {
    httr::config()
  } else {
    httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
  }

  resp <- tryCatch({
    httr::POST(
      url = endpoint_url,
      httr::add_headers(
        `Content-Type` = "application/json",
        `Authorization` = paste("Bearer", api_key)
      ),
      body = body,
      encode = "json",
      httr::timeout(timeout_seconds),
      req_config
    )
  }, error = function(e) e)

  if (inherits(resp, "error")) {
    return(fail(sprintf("İstek hatası: %s", conditionMessage(resp))))
  }

  status <- httr::status_code(resp)
  if (status < 200 || status >= 300) {
    err_body <- tryCatch(
      httr::content(resp, as = "text", encoding = "UTF-8"),
      error = function(e) ""
    )
    return(fail(sprintf("HTTP %d: %s", status, substr(err_body, 1, 300)), status))
  }

  audio_raw <- tryCatch(httr::content(resp, as = "raw"), error = function(e) raw(0))
  if (length(audio_raw) == 0) return(fail("Ses yanıtı boş döndü.", status))

  content_type <- httr::headers(resp)[["content-type"]] %||% ""
  if (nzchar(content_type)) {
    content_type <- strsplit(content_type, ";", fixed = TRUE)[[1]][1]
  }

  list(success = TRUE, audio_raw = audio_raw, content_type = content_type,
       http_status = status, error = NULL)
}

#' Gerçek akış taşıması: yanıt baytlarını geldikçe dosyaya yaz (worker
#' tarafı). Ana süreç dosyayı büyüdükçe okuyup istemciye parça gönderir.
#' Uç nokta gerçekten akıtamıyorsa dosya tek seferde dolar; bu durumda taşıma
#' pratikte tamponlu davranır ve bu dürüstçe belgelenir.
#'
#' @return list(success, bytes_written, http_status, error)
mergen_voxcpm2_stream_to_file <- function(body,
                                          out_path,
                                          endpoint_url = mergen_voxcpm2_endpoint_url(),
                                          api_key = "",
                                          timeout_seconds = 120,
                                          verify_ssl = TRUE) {
  fail <- function(error, status = NA_integer_, bytes = 0) {
    list(success = FALSE, bytes_written = bytes, http_status = status,
         error = mergen_voxcpm2_redact(error))
  }

  if (!nzchar(endpoint_url)) return(fail("TTS uç noktası yapılandırılmamış."))
  if (!requireNamespace("curl", quietly = TRUE)) return(fail("curl paketi yok."))
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(fail("jsonlite paketi yok."))

  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds))
  if (is.na(timeout_seconds) || timeout_seconds <= 0) timeout_seconds <- 120

  handle <- curl::new_handle()
  curl::handle_setopt(
    handle,
    post = TRUE,
    postfields = jsonlite::toJSON(body, auto_unbox = TRUE),
    timeout = timeout_seconds,
    ssl_verifypeer = if (isTRUE(verify_ssl)) 1L else 0L,
    ssl_verifyhost = if (isTRUE(verify_ssl)) 2L else 0L
  )
  curl::handle_setheaders(
    handle,
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )

  out_con <- file(out_path, "wb")
  on.exit(try(close(out_con), silent = TRUE), add = TRUE)

  # Yanıt gövdesini yalnızca HTTP durumu 2xx doğrulandıktan SONRA ses dosyasına
  # yaz. Bağlantı elle açılır: libcurl gövde baytlarından ÖNCE üstbilgileri
  # aldığı için durum kodu ilk okumadan önce handle_data() ile alınabilir.
  # Böylece 401/500 gibi hata gövdeleri (JSON/metin) ana sürecin akış pompası
  # tarafından tarayıcıya ham PCM olarak gönderilip gürültü üretmez.
  result <- tryCatch({
    http_con <- curl::curl(endpoint_url, handle = handle)
    open(http_con, "rbf")
    on.exit(try(close(http_con), silent = TRUE), add = TRUE)

    status <- tryCatch(as.integer(curl::handle_data(handle)$status_code),
                       error = function(e) NA_integer_)
    ok_status <- !is.na(status) && status >= 200 && status < 300

    written <- 0
    err_body <- raw(0)
    while (isIncomplete(http_con)) {
      buf <- readBin(http_con, raw(), 32768L)
      if (length(buf) == 0L) next
      if (ok_status) {
        writeBin(buf, out_con)
        flush(out_con)
        written <- written + length(buf)
      } else if (length(err_body) < 512L) {
        take <- min(length(buf), 512L - length(err_body))
        err_body <- c(err_body, buf[seq_len(take)])
      }
    }
    list(status = status, ok = ok_status, written = written, err_body = err_body)
  }, error = function(e) e)

  if (inherits(result, "error")) {
    return(fail(sprintf("Akış hatası: %s", conditionMessage(result))))
  }

  if (!isTRUE(result$ok)) {
    snippet <- tryCatch(rawToChar(result$err_body), error = function(e) "")
    return(fail(
      sprintf("HTTP %s akış hatası: %s",
              if (is.na(result$status)) "?" else as.character(result$status),
              substr(snippet, 1, 300)),
      result$status, result$written
    ))
  }
  if (isTRUE(result$written == 0)) return(fail("Akış boş döndü.", result$status))

  list(success = TRUE, bytes_written = result$written,
       http_status = result$status, error = NULL)
}
