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

# Ham metni (";" veya "," ayraçlı) temiz, boş olmayan parça vektörüne çevirir.
# Ayraç YALNIZCA ";"/"," olduğundan boşluk içeren adlar korunur.
.langflow_split_list <- function(raw) {
  val <- .langflow_chr1(raw)
  if (!nzchar(val)) {
    return(character(0))
  }
  parts <- trimws(unlist(strsplit(val, "[;,]")))
  parts[nzchar(parts)]
}

# Ham metni (";"/"," ayraçlı) parça vektörüne çevirir; boş KONUMLAR KORUNUR
# (yalnızca kırpma yapılır, boşlar atılmaz). Kimlik listesiyle pozisyonel
# hizalanması gereken ad listesi için kullanılır: boş bir konum "o slotta değer
# yok, yedek ada düş" demektir. Böylece `id1;id2` + `;Flow 2` girdisinde flow_1
# yanlışlıkla "Flow 2" etiketlenmez.
.langflow_split_list_positional <- function(raw) {
  val <- .langflow_chr1(raw)
  if (!nzchar(val)) {
    return(character(0))
  }
  trimws(unlist(strsplit(val, "[;,]")))
}

# Süreç Yönetimi çoklu Langflow akışlarını ham env değerlerinden ayrıştırır.
# ids_raw   : LANGFLOW_PROCESS_FLOW_IDS (";"/"," ayraçlı akış kimlikleri)
# names_raw : LANGFLOW_PROCESS_FLOW_NAMES (";"/"," ayraçlı görünen adlar)
# legacy_id : eski tekil LANGFLOW_PROCESS_FLOW_ID (geçici geriye dönük uyumluluk)
# Dönüş: list( list(key, id, name), ... ). Kimlik yoksa boş liste.
# Kimlik değerinde satır içi "#" yorumu ayıklanır. Ayıklama sonrası hâlâ bozuk
# (boşluk/URL-dışı karakter içeren) bir belirteç kalırsa TÜM liste reddedilir:
# tek belirteci atmak sonraki akışları sola kaydırır ve kullanıcının seçtiği
# akış sessizce başka bir akışa yönlenirdi. Reddetme, işleyicideki net
# "yapılandırma eksik" hatası olarak yüzeye çıkar.
mergen_parse_langflow_process_flows <- function(ids_raw = "",
                                                names_raw = "",
                                                legacy_id = "") {
  # readRenviron() satır içi "#" yorumunu değerin parçası olarak bırakır; "#"
  # geçerli bir akış kimliği karakteri olmadığından ilk "#" ve sonrası atılır.
  # Yorum ";" içerse bile ayrıştırmayı kirletemez (önce yorum, sonra bölme).
  ids <- .langflow_split_list(sub("#.*$", "", .langflow_chr1(ids_raw)))
  # Adlar kimliklerle pozisyonel hizalanmalıdır: boş bir ad konumu atılmamalı,
  # yoksa sonraki adlar sola kayar ve yanlış akış etiketlenir. Boş konumlar
  # korunur ve slot bazında yedek ada ("Akış i") düşülür. Türkçe adlar UTF-8'e
  # normalleştirilir (Windows VM .Renviron mojibake onarımı).
  names_vec <- .langflow_split_list_positional(names_raw)
  if (length(names_vec) > 0) {
    names_vec <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      normalize_text_utf8(names_vec, repair_mojibake = TRUE)
    } else {
      enc2utf8(names_vec)
    }
  }

  # Liste formatı boşsa eski tekil kimliğe düş (geçici uyumluluk). Satır içi
  # "#" yorumu burada da ayıklanır.
  if (length(ids) == 0) {
    legacy <- trimws(sub("#.*$", "", .langflow_chr1(legacy_id)))
    if (nzchar(legacy)) {
      ids <- legacy
    }
  }

  if (length(ids) == 0) {
    return(list())
  }

  gecersiz <- ids[!grepl("^[A-Za-z0-9._~-]+$", ids)]
  if (length(gecersiz) > 0) {
    if (exists("log_warn", mode = "function", inherits = TRUE)) {
      log_warn(paste0(
        "[LANGFLOW] Geçersiz süreç akış kimliği belirteci: ",
        paste(sprintf("'%s'", gecersiz), collapse = ", "),
        " - LANGFLOW_PROCESS_FLOW_IDS düzeltilene kadar süreç akışları devre dışı.",
        " Yorumlar .Renviron içinde ayrı satıra yazılmalıdır."
      ))
    }
    return(list())
  }

  flows <- vector("list", length(ids))
  for (i in seq_along(ids)) {
    display_name <- if (i <= length(names_vec) && nzchar(names_vec[i])) {
      names_vec[i]
    } else {
      paste0("Akış ", i)
    }
    flows[[i]] <- list(
      key = paste0("flow_", i),
      id = ids[i],
      name = display_name
    )
  }
  flows
}

# api_config$langflow altındaki süreç akışlarını döndürür. Önce önceden
# ayrıştırılmış `process_flows` alanını, yoksa ham env alanlarını kullanır.
mergen_langflow_process_flows <- function(config = api_config) {
  cfg <- mergen_langflow_config(config)

  parsed <- cfg$process_flows
  if (is.list(parsed) && length(parsed) > 0) {
    return(parsed)
  }

  mergen_parse_langflow_process_flows(
    ids_raw   = cfg$process_flow_ids_raw,
    names_raw = cfg$process_flow_names_raw,
    legacy_id = cfg$process_flow_legacy_id
  )
}

# Seçilen süreç akışının (key veya id) gerçek Langflow akış kimliğini çözer.
# Seçim boşsa varsayılan ilk akış kullanılır. Seçim DOLU ama hiçbir akışla
# eşleşmiyorsa "" döner: kullanıcının açıkça seçtiği akış sessizce 1. akışa
# yönlendirilmez; işleyici net "seçili süreç akışı bulunamadı" hatası gösterir.
# Hiç akış yoksa "".
mergen_langflow_process_flow_id <- function(config = api_config, selected_flow = NULL) {
  flows <- mergen_langflow_process_flows(config)

  if (length(flows) == 0) {
    # Son çare: eski merkezi flow_ids$process haritası.
    ids <- mergen_langflow_config(config)$flow_ids %||% list()
    return(trimws(.langflow_chr1(ids$process)))
  }

  sel <- .langflow_chr1(selected_flow)
  if (nzchar(sel)) {
    for (fl in flows) {
      if (identical(.langflow_chr1(fl$key), sel) ||
          identical(.langflow_chr1(fl$id), sel)) {
        return(trimws(.langflow_chr1(fl$id)))
      }
    }
    return("")
  }

  trimws(.langflow_chr1(flows[[1]]$id))
}

# Belirli bir araç ailesi için akış kimliğini çözer.
# - "process" ailesi çoklu akış destekler: seçilen akış (key/id) veya varsayılan
#   ilk akış çözülür (selected_flow argümanı ile).
# - Diğer aileler önce araç moduna özel `langflow_flow_id` alanına, ardından
#   merkezi `langflow$flow_ids[[family]]` haritasına bakar.
mergen_langflow_flow_id_for_family <- function(tool_family, config = api_config, selected_flow = NULL) {
  tf <- .langflow_chr1(tool_family)
  if (!nzchar(tf)) {
    return("")
  }

  # Süreç Yönetimi: çoklu akış çözümlemesi.
  if (identical(tf, "process")) {
    return(mergen_langflow_process_flow_id(config, selected_flow))
  }

  tool_cfg <- get_tool_mode_config(tf, by = "family", config = config)
  fid <- trimws(.langflow_chr1(tool_cfg$langflow_flow_id))
  if (nzchar(fid)) {
    return(fid)
  }

  ids <- mergen_langflow_config(config)$flow_ids %||% list()
  trimws(.langflow_chr1(ids[[tf]]))
}

# Bir araç ailesinin Langflow ile mi çalışacağını belirler.
# require_config = TRUE (varsayılan): TRUE dönmesi için (1) araç modu
#   yapılandırmasında runtime == "langflow", (2) Langflow taban URL'i ayarlı,
#   (3) bu aile için bir akış kimliği çözülebiliyor olmalı.
# require_config = FALSE: yalnızca runtime == "langflow" yeterlidir. Yönlendirme
#   kararı için kullanılır: yapılandırma eksik olsa bile araç Langflow işleyicisine
#   gider ve orada net bir "yapılandırma eksik" hatası gösterilir (normal LLM'ye
#   sessizce DÜŞMEZ).
is_langflow_tool_family <- function(tool_family, config = api_config, require_config = TRUE) {
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

  if (!isTRUE(require_config)) {
    return(TRUE)
  }

  base_url <- normalize_langflow_base_url(mergen_langflow_config(config)$base_url)
  flow_id <- mergen_langflow_flow_id_for_family(tf, config)

  nzchar(base_url) && nzchar(flow_id)
}

# Seçilen (veya varsayılan) süreç akışının görünen adını döndürür. Yalnızca
# loglama/metadata amaçlıdır; API anahtarı veya taban URL içermez. Dolu ama
# eşleşmeyen seçim, kimlik çözümlemesiyle tutarlı biçimde "" döndürür.
mergen_langflow_process_flow_label <- function(config = api_config, selected_flow = NULL) {
  flows <- mergen_langflow_process_flows(config)
  if (length(flows) == 0) {
    return("")
  }

  sel <- .langflow_chr1(selected_flow)
  if (nzchar(sel)) {
    for (fl in flows) {
      if (identical(.langflow_chr1(fl$key), sel) ||
          identical(.langflow_chr1(fl$id), sel)) {
        return(.langflow_chr1(fl$name))
      }
    }
    return("")
  }

  .langflow_chr1(flows[[1]]$name)
}

# runtime == "langflow" olan araçların setting_flag adlarını döndürür. Sohbet
# başlığındaki yerel model rozetini, aktif araç Langflow ise gizlemek için
# kullanılır (model, akışın içine gömülüdür; yerel model kavramı yoktur).
mergen_langflow_setting_flags <- function(config = api_config) {
  cfgs <- if (is.list(config)) config$tool_mode_config else NULL
  if (is.null(cfgs) || !is.list(cfgs)) {
    return(character(0))
  }

  flags <- character(0)
  for (cfg in cfgs) {
    if (identical(.langflow_chr1(cfg$runtime), "langflow")) {
      flag <- .langflow_chr1(cfg$setting_flag)
      if (nzchar(flag)) {
        flags <- c(flags, flag)
      }
    }
  }
  unique(flags)
}

# Aynı Mergen sohbeti için kararlı bir Langflow session_id üretir. Böylece aynı
# sohbette art arda gelen mesajlar aynı Langflow oturumunu (konuşma geçmişini)
# sürdürür. flow_id verildiğinde oturum ayrıca akışa göre daraltılır: aynı Mergen
# sohbetinde bir süreç akışından diğerine geçilince ikinci akış, session_id ile
# anahtarlanan Langflow sohbet belleğinde birinci akışın konuşma bağlamını
# paylaşmaz (akış başına süreklilik korunur). flow_id boş/NULL ise eski
# üç parçalı biçim korunur. user_id/chat_id eksikse güvenli yer tutuculara düşer.
mergen_build_langflow_session_id <- function(user_id, chat_id, flow_id = NULL) {
  uid <- .langflow_chr1(user_id, default = "0")
  cid <- .langflow_chr1(chat_id, default = "new")
  fid <- .langflow_chr1(flow_id)
  parts <- c("mergen", uid, cid)
  if (nzchar(fid)) {
    parts <- c(parts, fid)
  }
  paste(parts, collapse = "_")
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

  # Belge kaynak üstverisi (başlık/yol/sayfa/tür) yanıtla birlikte taşınır.
  # Çıkarıcı yüklü değilse (izole test/worker) kaynaklar boş listeye düşer;
  # kaynak uydurulmaz. Güvenli sarmalayıcı hata durumunda da boş liste verir.
  sources <- if (exists("mergen_langflow_safe_sources", mode = "function", inherits = TRUE)) {
    mergen_langflow_safe_sources(parsed)
  } else {
    list()
  }

  list(success = TRUE, text = answer, error = NULL, status = status, sources = sources)
}
