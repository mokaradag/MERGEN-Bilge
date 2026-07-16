# ==============================================================================
# Dosya Yolu: R/server_handler_langflow.R
# Açıklama: "Süreç Yönetimi Sistemi" ve "Uygulama Uzmanı" araçlarının kurumsal
#           Langflow akışına (Chat Input / Chat Output) yönlendirilen işleyicisi.
#           Bu araçlar artık normal yerel LLM uç noktasını ve MCP araçlarını
#           kullanmaz; bunun yerine yapılandırılmış Langflow akışını çağırır.
#           Asenkron çağrı, görsel oluşturma işleyicisiyle aynı tracked future +
#           bayat-istek koruması desenini izler.
# ==============================================================================

.MERGEN_LANGFLOW_SOURCE_RESOLVER_VERSION <- "v4"

.MERGEN_LANGFLOW_DOCUMENT_EXTENSIONS <- c(
  "pdf", "doc", "docx", "docm", "txt", "csv", "xls", "xlsx",
  "ppt", "pptx", "json", "md", "r", "py", "log"
)

.mergen_langflow_safe_relative_document <- function(value) {
  candidate <- trimws(as.character(value %||% "")[1])
  if (is.na(candidate) || !nzchar(candidate)) return(FALSE)
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", candidate)) return(FALSE)

  normalized <- gsub("\\\\", "/", candidate)
  if (grepl("^/", normalized) || grepl("^[A-Za-z]:", normalized)) return(FALSE)

  parts <- strsplit(normalized, "/", fixed = TRUE)[[1]]
  if (any(parts %in% c(".", ".."))) return(FALSE)

  tolower(tools::file_ext(normalized)) %in% .MERGEN_LANGFLOW_DOCUMENT_EXTENSIONS
}

.mergen_langflow_normalize_key <- function(value) {
  key <- enc2utf8(tolower(as.character(value %||% "")))
  key <- chartr("çğıöşü", "cgiosu", key)
  gsub("[^a-z0-9]", "", key)
}

# Araç ailesine karşılık gelen model tabanlarını seçer. Üretim yapılandırmasında
# teknik kimlikler genellikle "...surecyonetimi" / "...uygulamauzmani" biçiminde
# adlandırılır. Önce açık source_path_keys benzeri alanlar, sonra güvenli teknik-ad
# eşleşmesi kullanılır; eşleşme yoksa geriye dönük uyumluluk için tüm tabanlar
# döner. Yol değerleri günlüklenmez.
mergen_langflow_model_bases_for_tool <- function(local_model_paths,
                                                  tool_family = "",
                                                  tool_mode_config = list()) {
  if (is.null(local_model_paths)) return(character(0))

  paths <- if (is.list(local_model_paths)) {
    unlist(local_model_paths, use.names = TRUE)
  } else {
    as.character(local_model_paths)
  }
  paths <- as.character(paths)
  keep <- !is.na(paths) & nzchar(trimws(paths))
  paths <- paths[keep]
  if (!length(paths)) return(character(0))

  mode_cfg <- tryCatch(tool_mode_config[[tool_family]], error = function(e) NULL)
  explicit_keys <- character(0)
  if (is.list(mode_cfg)) {
    for (field in c("source_path_keys", "local_model_path_keys", "source_model_keys")) {
      raw <- mode_cfg[[field]]
      if (!is.null(raw)) explicit_keys <- c(explicit_keys, as.character(unlist(raw, use.names = FALSE)))
    }
  }
  explicit_keys <- unique(explicit_keys[!is.na(explicit_keys) & nzchar(trimws(explicit_keys))])
  if (length(explicit_keys) && !is.null(names(paths))) {
    matched <- paths[names(paths) %in% explicit_keys]
    if (length(matched)) return(unique(unname(matched)))
  }

  path_names <- names(paths)
  if (is.null(path_names) || !length(path_names)) return(unique(unname(paths)))

  family <- .mergen_langflow_normalize_key(tool_family)
  fixed_tokens <- switch(
    family,
    process = c("process", "surec", "surecyonetimi"),
    appexpert = c("appexpert", "uygulama", "uygulamauzmani"),
    character(0)
  )
  title_token <- if (is.list(mode_cfg)) .mergen_langflow_normalize_key(mode_cfg$title) else ""
  tokens <- unique(c(family, fixed_tokens, title_token))
  tokens <- tokens[nzchar(tokens)]

  normalized_names <- vapply(path_names, .mergen_langflow_normalize_key, character(1))
  matched_idx <- vapply(
    normalized_names,
    function(key) any(vapply(tokens, function(token) grepl(token, key, fixed = TRUE), logical(1))),
    logical(1)
  )

  if (any(matched_idx)) unique(unname(paths[matched_idx])) else unique(unname(paths))
}

# Mesaj render katmanı literal "\\n" dizilerini gerçek satır sonuna çevirir.
# Kaynak ayrıştırma render'dan ÖNCE çalıştığından aynı normalizasyon burada da
# yapılır; aksi halde ekranda ayrı satırlar görünen kaynak bölümü sunucuda tek
# satır kalır ve hiçbir aday çıkarılamaz.
.mergen_langflow_normalize_source_text <- function(value) {
  txt <- as.character(value %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(if (is.na(txt)) "" else txt)

  txt <- gsub("\r\n?", "\n", txt, perl = TRUE)
  txt <- gsub("\\\\r\\\\n", "\n", txt, fixed = TRUE)
  txt <- gsub("\\\\n", "\n", txt, fixed = TRUE)
  txt <- gsub("\\\\r", "\n", txt, fixed = TRUE)
  txt <- gsub("(?i)<br[[:space:]]*/?>", "\n", txt, perl = TRUE)
  txt <- gsub("(?i)</p[[:space:]]*>", "\n", txt, perl = TRUE)
  txt
}

# Kaynak başlığı/maddesi ayrıştırılırken yalnızca sunum işaretlerini kaldırır.
# Orijinal mesaj satırı değiştirilmez; bu değer yalnızca kaynak tespiti içindir.
# Dosya adlarındaki alt çizgi ve literal && korunur.
.mergen_langflow_source_parse_line <- function(value) {
  line <- trimws(as.character(value %||% "")[1])
  if (is.na(line) || !nzchar(line)) return("")

  line <- gsub("(?i)<br[[:space:]]*/?>", " ", line, perl = TRUE)
  line <- gsub("<[^>]+>", "", line, perl = TRUE)
  line <- gsub("(?i)&nbsp;|&#160;", " ", line, perl = TRUE)
  line <- gsub("(?i)&amp;", "&", line, perl = TRUE)
  line <- gsub("(?i)&lbrack;|&#91;", "[", line, perl = TRUE)
  line <- gsub("(?i)&rbrack;|&#93;", "]", line, perl = TRUE)
  line <- sub("^[[:space:]]*#{1,6}[[:space:]]*", "", line, perl = TRUE)
  line <- gsub("\\*\\*|__", "", line, perl = TRUE)
  trimws(line)
}

.mergen_langflow_strip_source_wrappers <- function(value) {
  candidate <- .mergen_langflow_source_parse_line(value)
  if (!nzchar(candidate)) return("")

  repeat {
    before <- candidate
    candidate <- sub("^`(.*)`$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^['\"](.*)['\"]$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^\\[(.*)\\]$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^\\((.*)\\)$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^\\*{1,3}(.*)\\*{1,3}$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^_{2,3}(.*)_{2,3}$", "\\1", candidate, perl = TRUE)
    candidate <- sub("^~~(.*)~~$", "\\1", candidate, perl = TRUE)
    candidate <- trimws(candidate)
    if (identical(candidate, before)) break
  }
  candidate
}

# "Kaynak: [dosya.pdf]", markdown bağlantısı ve kaynak-listesi madde işaretleri
# gibi üretimde görülen biçimlerden güvenli göreli belge adaylarını çıkarır.
.mergen_langflow_fragment_candidates <- function(fragment) {
  raw <- .mergen_langflow_source_parse_line(fragment)
  if (!nzchar(raw)) return(character(0))

  raw <- sub("^[[:space:]]*(?:[-*+]|[0-9]+[.)]|\u2022)[[:space:]]*", "", raw, perl = TRUE)
  candidates <- character(0)

  markdown_links <- regmatches(raw, gregexpr("\\[[^]\\r\\n]+\\]\\([^)\\r\\n]+\\)", raw, perl = TRUE))[[1]]
  if (length(markdown_links)) {
    for (link in markdown_links) {
      target <- sub("^.*\\]\\(([^)]+)\\)$", "\\1", link, perl = TRUE)
      label <- sub("^\\[([^]]+)\\].*$", "\\1", link, perl = TRUE)
      chosen <- if (.mergen_langflow_safe_relative_document(target)) target else label
      chosen <- .mergen_langflow_strip_source_wrappers(chosen)
      if (.mergen_langflow_safe_relative_document(chosen)) candidates <- c(candidates, chosen)
    }
  }

  bracketed <- regmatches(raw, gregexpr("\\[[^]\\r\\n]+\\]", raw, perl = TRUE))[[1]]
  if (length(bracketed)) {
    for (entry in bracketed) {
      chosen <- .mergen_langflow_strip_source_wrappers(entry)
      if (.mergen_langflow_safe_relative_document(chosen)) candidates <- c(candidates, chosen)
    }
  }

  if (length(candidates)) return(unique(candidates))

  candidate <- .mergen_langflow_strip_source_wrappers(raw)
  ext_pattern <- paste(.MERGEN_LANGFLOW_DOCUMENT_EXTENSIONS, collapse = "|")
  match <- regmatches(
    candidate,
    regexec(
      paste0("^(.+?\\.(?:", ext_pattern, "))(?:[[:space:]]*(?:[,;|].*)?)$"),
      candidate,
      ignore.case = TRUE,
      perl = TRUE
    )
  )[[1]]
  if (length(match) >= 2L) candidate <- trimws(match[[2]])
  candidate <- sub("[[:space:]]*[,;]+$", "", candidate, perl = TRUE)
  candidate <- .mergen_langflow_strip_source_wrappers(candidate)

  if (.mergen_langflow_safe_relative_document(candidate)) candidate else character(0)
}

# Kaynak başlıklarını ve bunların altındaki belge maddelerini bulur. Yalnızca
# açıkça kaynak olarak etiketlenmiş satırlar incelenir; normal yanıt düzyazısında
# geçen dosya adları kendiliğinden kaynak sayılmaz.
.mergen_langflow_text_source_items <- function(text, max_sources = 20L) {
  txt <- .mergen_langflow_normalize_source_text(text)
  if (!nzchar(txt)) {
    return(list(lines = txt, items = list(), headers = list()))
  }

  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  items <- list()
  headers <- list()
  active_header <- NA_integer_
  header_pattern <- paste0(
    "^(Kaynak|Kaynaklar|Kaynakça|Source|Sources|References|",
    "Genel[[:space:]]+Kaynak[[:space:]]+Listesi|General[[:space:]]+Source[[:space:]]+List)",
    "[[:space:]]*:[[:space:]]*(.*)$"
  )

  add_item <- function(candidate, line_index, header_index) {
    if (length(items) >= max_sources) return(invisible(FALSE))
    item_id <- length(items) + 1L
    items[[item_id]] <<- list(
      candidate = candidate,
      line_index = as.integer(line_index),
      header_index = as.integer(header_index)
    )
    key <- as.character(header_index)
    headers[[key]] <<- c(headers[[key]] %||% integer(0), item_id)
    invisible(TRUE)
  }

  for (i in seq_along(lines)) {
    line_parsed <- .mergen_langflow_source_parse_line(lines[[i]])
    header_match <- regmatches(
      line_parsed,
      regexec(header_pattern, line_parsed, ignore.case = TRUE, perl = TRUE)
    )[[1]]

    if (length(header_match) == 3L) {
      active_header <- i
      headers[[as.character(i)]] <- headers[[as.character(i)]] %||% integer(0)
      remainder <- trimws(header_match[[3]])
      for (candidate in .mergen_langflow_fragment_candidates(remainder)) {
        add_item(candidate, i, i)
      }
      next
    }

    if (is.na(active_header)) next
    if (!nzchar(line_parsed)) next

    is_bullet <- grepl(
      "^[[:space:]]*(?:[-*+]|[0-9]+[.)]|\u2022)[[:space:]]+",
      line_parsed,
      perl = TRUE
    )
    candidates <- .mergen_langflow_fragment_candidates(line_parsed)
    if (length(candidates) && (is_bullet || length(candidates) == 1L)) {
      for (candidate in candidates) add_item(candidate, i, active_header)
      next
    }

    active_header <- NA_integer_
  }

  list(lines = lines, items = items, headers = headers)
}

.mergen_langflow_normalized_path <- function(path) {
  raw <- as.character(path %||% "")[1]
  if (is.na(raw) || !nzchar(raw)) return("")
  normalized <- tryCatch(
    normalizePath(raw, winslash = "/", mustWork = FALSE),
    error = function(e) raw
  )
  gsub("\\\\", "/", normalized)
}

# Kaynak tıklama hattının eski "&&" sözleşmesi hem alt klasör ayracı hem de
# üretimdeki gerçek dosya adlarının literal parçası olarak kullanılıyor. Bu iki
# anlam çakıştığında göreli alt-klasör yolunu işaretleyiciye taşımak dosya adını
# böler. Dosya indeksi zaten model kökü altında rekürsif olduğundan güvenli ve
# kararlı tıklama ipucu olarak gerçek basename kullanılır.
.mergen_langflow_click_path <- function(found_path) {
  basename(gsub("\\\\", "/", as.character(found_path %||% "")[1]))
}

# Yapılandırılmış Langflow kaynaklarını ve model metnindeki gerçek kaynak
# bölümlerini aynı güvenli çözümleme hattında birleştirir. Her aday, seçili aracın
# model tabanlarında search_file_in_folder() ile rekürsif aranır. Bulunan tam UNC
# yolu istemciye yazılmaz; doğrulanmış gerçek basename Kaynakça işaretleyicisinin
# tıklama ipucu olur.
mergen_langflow_promote_validated_sources <- function(
  text,
  structured_sources = list(),
  local_model_paths,
  tool_family = "",
  tool_mode_config = list(),
  resolver = NULL,
  path_exists_fn = NULL,
  max_sources = 20L
) {
  txt <- .mergen_langflow_normalize_source_text(text)

  max_sources <- suppressWarnings(as.integer(max_sources[1]))
  if (is.na(max_sources) || max_sources < 1L) {
    return(list(text = txt, sources = list(), candidate_count = 0L, base_count = 0L))
  }

  bases <- mergen_langflow_model_bases_for_tool(
    local_model_paths,
    tool_family = tool_family,
    tool_mode_config = tool_mode_config
  )
  resolver <- resolver %||% get0("search_file_in_folder", mode = "function", inherits = TRUE)
  if (!is.function(path_exists_fn)) {
    path_exists_fn <- get0("path_exists_relaxed", mode = "function", inherits = TRUE)
  }
  if (!is.function(path_exists_fn)) path_exists_fn <- file.exists

  parsed_text <- .mergen_langflow_text_source_items(txt, max_sources = max_sources)
  if (!length(bases) || !is.function(resolver)) {
    return(list(
      text = txt,
      sources = list(),
      candidate_count = length(parsed_text$items),
      base_count = length(bases)
    ))
  }

  sources <- list()
  seen_paths <- character(0)
  resolved_items <- rep(FALSE, length(parsed_text$items))

  resolve_candidate <- function(candidate, page = "") {
    candidate <- .mergen_langflow_strip_source_wrappers(candidate)
    if (!.mergen_langflow_safe_relative_document(candidate)) return(FALSE)

    hit_path <- NULL
    for (base_dir in bases) {
      hit <- tryCatch(resolver(base_dir, candidate), error = function(e) NULL)
      hit <- as.character(hit %||% "")[1]
      if (!is.na(hit) && nzchar(hit) && isTRUE(path_exists_fn(hit))) {
        hit_path <- hit
        break
      }
    }
    if (is.null(hit_path)) return(FALSE)

    found_key <- tolower(.mergen_langflow_normalized_path(hit_path))
    if (!(found_key %in% seen_paths) && length(sources) < max_sources) {
      title <- basename(gsub("\\\\", "/", hit_path))
      sources[[length(sources) + 1L]] <<- list(
        title = title,
        path = .mergen_langflow_click_path(hit_path),
        page = if (grepl("^[0-9]+$", page)) page else "",
        type = tolower(tools::file_ext(title))
      )
      seen_paths <<- c(seen_paths, found_key)
    }
    TRUE
  }

  source_keys <- c("title", "name", "file_name", "filename", "display_name", "file_path", "filepath", "path", "source", "file")
  structured <- structured_sources
  if (is.list(structured) && length(structured) && !is.null(names(structured)) && any(names(structured) %in% source_keys)) {
    structured <- list(structured)
  }
  if (is.list(structured)) {
    for (record in structured) {
      if (!is.list(record)) next
      candidate <- as.character(record$path %||% record$file_path %||% record$filename %||% record$file_name %||% record$title %||% "")[1]
      page <- as.character(record$page %||% record$page_number %||% "")[1]
      candidates <- .mergen_langflow_fragment_candidates(candidate)
      if (!length(candidates) && .mergen_langflow_safe_relative_document(candidate)) candidates <- candidate
      for (entry in candidates) resolve_candidate(entry, page)
    }
  }

  if (length(parsed_text$items)) {
    for (i in seq_along(parsed_text$items)) {
      resolved_items[[i]] <- resolve_candidate(parsed_text$items[[i]]$candidate)
    }
  }

  remove_lines <- integer(0)
  if (length(resolved_items) && any(resolved_items)) {
    remove_lines <- vapply(
      parsed_text$items[resolved_items],
      function(item) item$line_index,
      integer(1)
    )
  }
  if (length(parsed_text$headers)) {
    for (header_key in names(parsed_text$headers)) {
      item_ids <- parsed_text$headers[[header_key]]
      if (length(item_ids) && all(resolved_items[item_ids])) {
        remove_lines <- c(remove_lines, as.integer(header_key))
      }
    }
  }

  final_text <- txt
  if (length(remove_lines) && length(parsed_text$lines)) {
    kept <- parsed_text$lines[-unique(remove_lines)]
    final_text <- paste(kept, collapse = "\n")
    final_text <- gsub("\n{3,}", "\n\n", final_text, perl = TRUE)
    final_text <- trimws(final_text)
  }

  list(
    text = final_text,
    sources = sources,
    candidate_count = length(parsed_text$items) + if (is.list(structured)) length(structured) else 0L,
    base_count = length(bases)
  )
}

# Geriye dönük dar sarmalayıcı: yalnızca metindeki kaynakları yükseltir.
mergen_langflow_promote_validated_text_sources <- function(
  text,
  local_model_paths,
  resolver = NULL,
  path_exists_fn = NULL,
  max_sources = 20L
) {
  mergen_langflow_promote_validated_sources(
    text = text,
    structured_sources = list(),
    local_model_paths = local_model_paths,
    resolver = resolver,
    path_exists_fn = path_exists_fn,
    max_sources = max_sources
  )
}

# Langflow sohbet modunu işle.
# ctx: mesaj gönderme bağlamından gerekli değişkenleri içeren liste.
# Döndürür: TRUE (işlendi ve send_message erken dönüş yapmalı).
handle_langflow_chat_mode <- function(ctx) {
  config <- ctx$api_config %||% api_config
  tool_family <- ctx$tool_family

  lf_cfg <- mergen_langflow_config(config)
  base_url <- normalize_langflow_base_url(lf_cfg$base_url)
  # Süreç Yönetimi çoklu akış: seçilen akış (key/id) çözülür; diğer aileler tekil.
  selected_process_flow <- ctx$selected_process_flow
  flow_id <- mergen_langflow_flow_id_for_family(tool_family, config, selected_flow = selected_process_flow)
  # Yalnızca loglama/metadata için akış adı (API anahtarı/URL asla loglanmaz).
  flow_label <- tryCatch(
    if (identical(tool_family, "process")) {
      mergen_langflow_process_flow_label(config, selected_process_flow)
    } else {
      ""
    },
    error = function(e) ""
  )
  api_key <- tryCatch(as.character(lf_cfg$api_key %||% "")[1], error = function(e) "")
  timeout_seconds <- suppressWarnings(as.numeric(lf_cfg$timeout_seconds %||% 300))
  if (length(timeout_seconds) == 0 || is.na(timeout_seconds) || timeout_seconds <= 0) {
    timeout_seconds <- 300
  }

  log_debug("[LANGFLOW] Araç={tool_family} akış={flow_label} için Langflow akışı çağrılıyor")

  # Yarış koruması: bu isteğin kimliğini en başta yakala. Kullanıcı durdurup yeni
  # bir istek başlatırsa bayat sonuç yeni isteğin yazma alanını/sohbetini ezmemeli.
  active_request_id_local <- ctx$active_request_id
  stop_generation_local <- ctx$stop_generation
  req_id_local <- tryCatch(
    if (is.function(active_request_id_local)) active_request_id_local() else NULL,
    error = function(e) NULL
  )

  # Backpressure slotu yaşam döngüsü: send_message slotu values$backpressure_token
  # içine devretti. Bu asenkron yol normal cleanup callback'ini çağırmadığından,
  # slot bu istek bitince (başarı/hata/iptal) açıkça serbest bırakılır. req_id
  # koruması yeni bir isteğin slotunu yanlışlıkla serbest bırakmayı engeller.
  # Backpressure kapalıyken (varsayılan) token NULL'dur ve bu çağrı no-op'tur.
  release_langflow_backpressure_slot <- function() {
    mergen_send_message_release_values_token(ctx$values, req_id = req_id_local)
  }

  is_stale_langflow_request <- function() {
    if (!is.function(active_request_id_local) || is.null(req_id_local)) {
      return(FALSE)
    }
    !mergen_is_current_request(active_request_id_local, req_id_local, stop_generation_local)
  }

  # Yapılandırma eksikse net, kullanıcı dostu hata ver ve normal LLM yoluna geçme.
  if (!nzchar(base_url) || !nzchar(flow_id)) {
    log_warn("[LANGFLOW] Yapılandırma eksik (araç={tool_family}); taban URL veya akış kimliği çözülemedi")
    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn(
      paste0(
        "\U000026A0\U0000FE0F Bu araç için kurumsal Langflow yapılandırması eksik ",
        "veya seçili süreç akışı bulunamadı. Lütfen sistem yöneticisiyle iletişime ",
        "geçin (LANGFLOW_BASE_URL ve süreç akışı kimlikleri)."
      ),
      "ai"
    )
    ctx$reset_chat_state_fn()
    return(TRUE)
  }

  # Oturum kimliği çözülen akış kimliğiyle daraltılır; böylece aynı Mergen
  # sohbetinde farklı süreç akışları arasında geçildiğinde Langflow'un session_id
  # ile anahtarlanan sohbet belleği akışlar arasında karışmaz (akış başına
  # süreklilik korunur).
  session_id <- mergen_build_langflow_session_id(ctx$current_user_id, ctx$chat_id_val, flow_id = flow_id)

  # Standart düşünme paneli (simüle fazlı) send_message tarafından zaten
  # gösterildi ve Langflow non-streaming yanıtı gelene kadar canlı kalır.
  # Görsel oluşturma spinner'ı KULLANILMAZ; böylece bu araçlar diğer düşünen
  # model akışlarıyla aynı deneyimi verir.

  # Asenkron çağrı için yalnızca skalar yereller yakalanır (ağır api_config
  # nesnesi worker tarafına taşınmaz).
  input_value_local <- ctx$user_message_text
  base_url_local <- base_url
  flow_id_local <- flow_id
  api_key_local <- api_key
  session_id_local <- session_id
  timeout_local <- timeout_seconds

  tracked_future_promise(
    task_fn = function() {
      call_langflow_chat(
        input_value = input_value_local,
        base_url = base_url_local,
        flow_id = flow_id_local,
        api_key = api_key_local,
        session_id = session_id_local,
        timeout_seconds = timeout_local
      )
    },
    task_type = "langflow_chat",
    session_token = ctx$session$token,
    meta = list(tool_family = tool_family)
  ) %...>% (function(result) {
    # Bayat sonuç: kullanıcı durdurup yeni istek başlattıysa UI mutasyonu yapma.
    # Durdurma/iptal yolunda (Durdur) henüz yeni istek başlamamış olabilir; bu
    # durumda slot hâlâ bu isteğe aittir ve req_id korumalı serbest bırakma onu
    # açar. Yeni bir istek slotun sahibiyse koruma no-op yapar.
    if (isTRUE(is_stale_langflow_request())) {
      release_langflow_backpressure_slot()
      return(invisible(NULL))
    }

    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE

    if (isTRUE(result$success)) {
      original_text <- as.character(result$text %||% "")[1]
      prepared <- tryCatch(
        mergen_langflow_promote_validated_sources(
          text = original_text,
          structured_sources = result$sources %||% list(),
          local_model_paths = config$local_model_paths %||% list(),
          tool_family = tool_family,
          tool_mode_config = config$tool_mode_config %||% list()
        ),
        error = function(e) list(
          text = original_text,
          sources = list(),
          candidate_count = 0L,
          base_count = 0L
        )
      )
      final_text <- prepared$text
      final_sources <- prepared$sources
      kaynak_blok <- ""

      # Belge kaynakları (başlık/yol/sayfa/tür) düz metin Kaynakça işaretleyici
      # bloğu olarak içeriğe eklenir; render sırasında process_message_content
      # bloğu güvenli tıklanabilir .source-link HTML'ine yükseltir. İçerik DB'ye
      # işaretleyiciyle kaydedildiği için kayıtlı sohbet yeniden yüklemesinde de
      # aynı tıklanabilir Kaynakça üretilir.
      if (exists("mergen_langflow_kaynakca_marker_block", mode = "function", inherits = TRUE)) {
        kaynak_blok <- tryCatch(
          mergen_langflow_kaynakca_marker_block(final_sources),
          error = function(e) ""
        )
      }

      marker_ready <- nzchar(kaynak_blok)
      log_info(paste0(
        "[LANGFLOW SOURCE] resolver=", .MERGEN_LANGFLOW_SOURCE_RESOLVER_VERSION,
        " tool=", tool_family,
        " bases=", prepared$base_count %||% 0L,
        " candidates=", prepared$candidate_count %||% 0L,
        " resolved=", length(final_sources),
        " marker=", marker_ready
      ))

      if (marker_ready) {
        final_text <- paste0(final_text, kaynak_blok)
      } else if (length(final_sources)) {
        # İmzalı marker üretilemediyse kaynak metnini sessizce kaybetme. Bu durum
        # çoğunlukla openssl paketinin üretim ortamında bulunmadığını gösterir.
        final_text <- original_text
        log_warn(paste0(
          "[LANGFLOW SOURCE] resolver=", .MERGEN_LANGFLOW_SOURCE_RESOLVER_VERSION,
          " kaynak çözüldü ancak güvenli marker üretilemedi; düz metin korundu"
        ))
      }

      ctx$add_message_fn(final_text, "ai")
    } else {
      err_msg <- result$error %||% "Langflow yanıtı alınamadı."
      # Hata önizlemesi worker tarafında üretildiğinden, ana süreçte (sır
      # redaksiyon yardımcısı garanti yüklüyken) yeniden redakte edilir; böylece
      # bir üst-akış/proxy hatası API anahtarını prose içinde yansıtsa bile
      # sohbete/toast'a sızmaz. Redaksiyon idempotenttir.
      if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
        err_msg <- redact_sensitive_text(err_msg)
      }
      ctx$add_message_fn(paste0("\U000026A0\U0000FE0F ", err_msg), "ai")
      showToast(ctx$session, err_msg, "error")
    }

    ctx$reset_chat_state_fn()
  }) %...!% (function(err) {
    # Bayat hata sonucu da yeni isteğin durumunu etkilememeli. Durdurma/iptal
    # yolunda slot hâlâ bu isteğe ait olabilir; req_id korumalı serbest bırakma
    # onu açar, yeni istek sahibiyse no-op olur.
    if (isTRUE(is_stale_langflow_request())) {
      release_langflow_backpressure_slot()
      return(invisible(NULL))
    }

    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn(paste0("\U0000274C Langflow hatası: ", err$message), "ai")
    showToast(ctx$session, paste("Hata:", err$message), "error")
    ctx$reset_chat_state_fn()
  })

  TRUE
}
