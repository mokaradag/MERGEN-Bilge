# ==============================================================================
# Dosya Yolu: R/helpers_langflow_runtime.R
# Açıklama: Kurumsal Langflow akış API'sini (Chat Input / Chat Output) çağıran
#           SAF yardımcılar. "Süreç Yönetimi Sistemi" ve "Uygulama Uzmanı"
#           araçları normal yerel LLM uç noktası yerine bu akışları kullanır.
#           Bu dosya Shiny/oturum/reaktif erişim içermez; izole test edilebilir
#           ve future worker tarafına güvenle taşınabilir.
# ==============================================================================

# Tek bir değeri güvenli biçimde ilk skalar string'e indirger. Anonim handler
# sayısını düşük tutmak için ortak coercion noktası olarak kullanılır.
.langflow_chr1 <- function(x, default = "") {
  if (is.null(x) || length(x) == 0) return(default)
  val <- suppressWarnings(as.character(x))[1]
  if (is.na(val) || !nzchar(val)) default else val
}

# Langflow taban URL'ini normalleştirir: boşlukları ve sondaki '/' karakterlerini
# temizler. Boş/NA değerler boş string'e indirgenir.
normalize_langflow_base_url <- function(base_url) {
  url <- trimws(.langflow_chr1(base_url))
  sub("/+$", "", url)
}

# Akış çalıştırma uç noktasını üretir:
#   {base_url}/{flow_id}
# Taban URL veya akış kimliği eksikse boş string döner (çağıran taraf bunu
# yapılandırma eksikliği olarak ele alır).
build_langflow_run_url <- function(base_url, flow_id) {
  base <- normalize_langflow_base_url(base_url)
  fid <- trimws(.langflow_chr1(flow_id))

  if (!nzchar(base) || !nzchar(fid)) {
    return("")
  }

  paste0(base, "/", fid)
}

# api_config içindeki Langflow yapılandırma bloğunu döndürür (yoksa boş liste).
mergen_langflow_config <- function(config = api_config) {
  if (!is.list(config)) return(list())
  cfg <- config$langflow
  if (is.null(cfg) || !is.list(cfg)) list() else cfg
}

# Belirli bir araç ailesi için akış kimliğini çözer. Önce araç moduna özel
# `langflow_flow_id` alanına, ardından merkezi `langflow$flow_ids[[family]]`
# haritasına bakar.
mergen_langflow_flow_id_for_family <- function(tool_family, config = api_config) {
  tf <- .langflow_chr1(tool_family)
  if (!nzchar(tf)) {
    return("")
  }

  tool_cfg <- get_tool_mode_config(tf, by = "family", config = config)
  fid <- trimws(.langflow_chr1(tool_cfg$langflow_flow_id))
  if (nzchar(fid)) {
    return(fid)
  }

  ids <- mergen_langflow_config(config)$flow_ids %||% list()
  trimws(.langflow_chr1(ids[[tf]]))
}

# Bir araç ailesinin Langflow ile mi çalışacağını belirler. TRUE dönmesi için:
#   1) araç modu yapılandırmasında runtime == "langflow",
#   2) Langflow taban URL'i ayarlı,
#   3) bu aile için bir akış kimliği çözülebiliyor.
# Aksi halde FALSE döner ve çağıran taraf normal LLM yoluna devam eder.
is_langflow_tool_family <- function(tool_family, config = api_config) {
  tf <- .langflow_chr1(tool_family)
  if (!nzchar(tf)) {
    return(FALSE)
  }

  tool_cfg <- get_tool_mode_config(tf, by = "family", config = config)
  if (is.null(tool_cfg)) {
    return(FALSE)
  }

  if (!identical(.langflow_chr1(tool_cfg$runtime), "langflow")) {
    return(FALSE)
  }

  base_url <- normalize_langflow_base_url(mergen_langflow_config(config)$base_url)
  flow_id <- mergen_langflow_flow_id_for_family(tf, config)

  nzchar(base_url) && nzchar(flow_id)
}

# Aynı Mergen sohbeti için kararlı bir Langflow session_id üretir. Böylece aynı
# sohbette art arda gelen mesajlar aynı Langflow oturumunu (konuşma geçmişini)
# sürdürür. user_id/chat_id eksikse güvenli yer tutuculara düşer.
mergen_build_langflow_session_id <- function(user_id, chat_id) {
  uid <- .langflow_chr1(user_id, default = "0")
  cid <- .langflow_chr1(chat_id, default = "new")
  paste("mergen", uid, cid, sep = "_")
}

# Bir değeri tek satırlık güvenli metne indirger (liste/skalar/karakter).
.langflow_clean_text <- function(x) {
  if (is.null(x)) return("")

  if (is.list(x)) {
    if (length(x) == 1 && (is.character(x[[1]]) || is.numeric(x[[1]]))) {
      x <- x[[1]]
    } else {
      return("")
    }
  }

  if (!is.character(x)) {
    x <- suppressWarnings(as.character(x))
  }
  if (length(x) == 0) return("")

  val <- trimws(paste(x, collapse = "\n"))
  if (is.na(val)) "" else val
}

# İç içe listede güvenli yol takibi. Yol elemanları string (anahtar) veya
# sayısal (indeks) olabilir. Herhangi bir adım başarısızsa NULL döner.
.langflow_pluck <- function(x, path) {
  cur <- x
  for (key in path) {
    if (is.null(cur)) return(NULL)
    if (is.numeric(key)) {
      idx <- as.integer(key)
      if (!is.list(cur) || length(cur) < idx) return(NULL)
      cur <- cur[[idx]]
    } else {
      if (!is.list(cur) || is.null(names(cur)) || !(key %in% names(cur))) return(NULL)
      cur <- cur[[key]]
    }
  }
  cur
}

# Güvenli özyinelemeli geri dönüş: yapı içinde "text" veya "message" adlı,
# boş olmayan skalar string değerini derinlik öncelikli arar. Yalnızca açık
# yollar başarısız olduğunda kullanılır.
.langflow_deep_find_text <- function(x, depth = 0L) {
  if (depth > 12L || is.null(x) || !is.list(x)) {
    return("")
  }

  nms <- names(x)
  for (key in c("text", "message")) {
    if (!is.null(nms) && key %in% nms) {
      val <- .langflow_clean_text(x[[key]])
      if (nzchar(val)) return(val)
    }
  }

  for (i in seq_along(x)) {
    val <- .langflow_deep_find_text(x[[i]], depth + 1L)
    if (nzchar(val)) return(val)
  }

  ""
}

# Langflow API yanıtından (jsonlite::fromJSON(..., simplifyVector = FALSE) ile
# elde edilen iç içe liste) nihai sohbet metnini savunmacı biçimde çıkarır.
# Belgede gösterilen Chat Output yerleşik yolları öncelik sırasıyla denenir;
# hiçbiri tutmazsa yalnızca `outputs` altında güvenli özyinelemeli arama yapılır.
extract_langflow_chat_text <- function(parsed) {
  if (is.null(parsed)) return("")

  # Bazı uçlar düz metin döndürebilir.
  if (is.character(parsed)) {
    val <- .langflow_clean_text(parsed)
    if (nzchar(val)) return(val)
  }

  if (!is.list(parsed)) return("")

  candidate_paths <- list(
    list("outputs", 1, "outputs", 1, "results", "message", "text"),
    list("outputs", 1, "outputs", 1, "results", "message", "data", "text"),
    list("outputs", 1, "outputs", 1, "results", "message", "message"),
    list("outputs", 1, "outputs", 1, "artifacts", "message"),
    list("outputs", 1, "outputs", 1, "outputs", "message", "message"),
    list("outputs", 1, "outputs", 1, "outputs", "message", "text"),
    list("outputs", 1, "outputs", 1, "outputs", "text", "message"),
    list("outputs", 1, "outputs", 1, "messages", 1, "message"),
    list("outputs", 1, "outputs", 1, "messages", 1, "text"),
    list("result", "message", "text"),
    list("result", "text"),
    list("message"),
    list("text"),
    list("result"),
    list("detail")
  )

  for (path in candidate_paths) {
    val <- .langflow_clean_text(.langflow_pluck(parsed, path))
    if (nzchar(val)) return(val)
  }

  search_root <- parsed$outputs %||% parsed
  val <- .langflow_deep_find_text(search_root)
  if (nzchar(val)) return(val)

  ""
}

# HTTP yanıt gövdesinin kısa, kontrol-karakterlerinden arındırılmış ve (varsa)
# sır-redakte edilmiş bir önizlemesini üretir. Loglarda/hata mesajlarında kullanılır.
.langflow_sanitize_preview <- function(raw_text, max_chars = 200L) {
  txt <- .langflow_chr1(raw_text)
  if (!nzchar(txt)) return("")

  txt <- gsub("[[:cntrl:]]+", " ", txt)
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    txt <- redact_sensitive_text(txt)
  }
  substr(trimws(txt), 1L, max_chars)
}

# HTTP durum koduna göre kullanıcı dostu, Türkçe hata mesajı üretir.
langflow_http_error_message <- function(status, raw_text = "") {
  preview <- .langflow_sanitize_preview(raw_text)
  status_int <- suppressWarnings(as.integer(status))

  base_msg <- if (!is.na(status_int) && status_int %in% c(401L, 403L)) {
    "Langflow kimlik doğrulama hatası (API anahtarı geçersiz veya eksik)."
  } else if (!is.na(status_int) && identical(status_int, 404L)) {
    "Langflow akışı bulunamadı (akış kimliği veya uç nokta yanlış olabilir)."
  } else {
    sprintf("Langflow beklenmeyen yanıt verdi (HTTP %s).", as.character(status))
  }

  if (nzchar(preview)) paste0(base_msg, " Detay: ", preview) else base_msg
}

# Langflow bağlantı/zaman aşımı hatasını sınıflandırıp kullanıcı dostu mesaja çevirir.
.langflow_connection_error <- function(condition) {
  msg <- conditionMessage(condition)
  is_timeout <- grepl("time(d)? *out|too slow|operation timed", msg, ignore.case = TRUE)

  text <- if (is_timeout) {
    "Langflow zaman aşımına uğradı (akış belirtilen sürede yanıt vermedi)."
  } else {
    paste0("Langflow bağlantı hatası: ", msg)
  }

  list(success = FALSE, text = "", error = text, status = NA_integer_)
}

# Langflow akışını Chat Input / Chat Output anlamıyla çağırır.
# Gövde: {input_value, output_type:"chat", input_type:"chat", session_id?}
# Başlık: Content-Type ve (varsa) x-api-key.
# Dönüş: list(success, text, error, status). Bu fonksiyon bilinçli olarak
# yalnızca skalar argümanlar alır; böylece future worker tarafına ağır
# api_config nesnesi taşınmadan güvenle çalıştırılabilir.
call_langflow_chat <- function(input_value,
                               base_url,
                               flow_id,
                               api_key = "",
                               session_id = NULL,
                               timeout_seconds = 300) {
  run_url <- build_langflow_run_url(base_url, flow_id)
  if (!nzchar(run_url)) {
    return(list(
      success = FALSE,
      text = "",
      error = "Langflow yapılandırması eksik (taban URL veya akış kimliği tanımlı değil).",
      status = NA_integer_
    ))
  }

  timeout_sec <- suppressWarnings(as.numeric(timeout_seconds))
  if (length(timeout_sec) == 0 || is.na(timeout_sec) || timeout_sec <= 0) {
    timeout_sec <- 300
  }

  body <- list(
    input_value = .langflow_chr1(input_value),
    output_type = "chat",
    input_type = "chat"
  )

  sid <- .langflow_chr1(session_id)
  if (nzchar(sid)) {
    body$session_id <- sid
  }

  hds <- list(`Content-Type` = "application/json")
  key <- .langflow_chr1(api_key)
  if (nzchar(key)) {
    hds[["x-api-key"]] <- key
  }

  response <- tryCatch(
    httr::POST(
      url = run_url,
      body = body,
      encode = "json",
      do.call(httr::add_headers, hds),
      httr::timeout(timeout_sec)
    ),
    error = identity
  )

  if (inherits(response, "condition")) {
    return(.langflow_connection_error(response))
  }

  status <- httr::status_code(response)
  raw_text <- tryCatch(
    httr::content(response, as = "text", encoding = "UTF-8"),
    error = function(e) ""
  )

  if (status >= 400) {
    return(list(
      success = FALSE,
      text = "",
      error = langflow_http_error_message(status, raw_text),
      status = status
    ))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
    error = function(e) NULL
  )

  answer <- extract_langflow_chat_text(parsed)

  if (!nzchar(answer)) {
    return(list(
      success = FALSE,
      text = "",
      error = "Langflow yanıtından kullanılabilir bir metin çıkarılamadı.",
      status = status
    ))
  }

  list(success = TRUE, text = answer, error = NULL, status = status)
}