# ==============================================================================
# Dosya Yolu: R/helpers_streaming_io.R
# Açıklama: Gerçek SSE akışı için olay-döngüsü (event-loop) basıncını azaltan saf
#           akış G/Ç yardımcıları:
#             - artımlı (incremental) akış dosyası okuma (her yoklamada tüm
#               dosyayı yeniden okumak yerine yalnızca eklenen baytları okur),
#             - uyarlanır (adaptive) yoklama aralığı / geri çekilme (backoff),
#             - delta taşımacılığını daha geniş tercih etme kararı,
#             - savunmacı akış/akıl yürütme metin üst sınırları.
#           Shiny/DB/LLM/ağ erişimi yoktur; saf ve izole test edilebilir.
#
# Tasarım sözleşmesi (DAVRANIŞI VARSAYILAN OLARAK DEĞİŞTİRMEZ):
#   - Uyarlanır geri çekilme VARSAYILAN KAPALIDIR (MERGEN_STREAM_POLL_IDLE_BACKOFF);
#     kapalıyken yoklama aralığı sabittir (mevcut davranış korunur).
#   - Delta taşımacılığı varsayılanı, profil zaten delta istiyorsa TRUE; aksi halde
#     yalnızca MERGEN_STREAM_DELTA_DEFAULT açıkken geniş delta devreye girer.
#   - Metin üst sınırları yüksek ve savunmacıdır (120000/80000); normal yanıtlar
#     etkilenmez. <=0 değer "sınırsız" anlamına gelir.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Ortam bayrağı okuyucu (ASCII-güvenli truthy çözümleme). Boşsa varsayılan döner.
.mergen_stream_env_flag <- function(name, default = FALSE) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(isTRUE(default))
  tolower(raw) %in% c("1", "true", "t", "yes", "y", "on", "evet", "aktif")
}

# Ortam sayısal okuyucu. Boş/geçersiz değer varsayılana döner.
.mergen_stream_env_num <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.numeric(default))
  val <- suppressWarnings(as.numeric(raw))
  if (!is.finite(val)) as.numeric(default) else val
}

# Sır-güvenli çalışma-zamanı sayacı artışı (yardımcı yoksa güvenli no-op).
.mergen_stream_metric_inc <- function(name, by = 1L) {
  if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
    try(mergen_runtime_metric_inc(name, by), silent = TRUE)
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Artımlı akış dosyası okuma
# ------------------------------------------------------------------------------

# Artımlı okuma durumunu sıfırdan oluşturur.
#   offset               : son okunan bayt konumu
#   partial              : yarım kalmış son satırın ham baytları (sonraki okumaya taşınır)
#   last_size            : son görülen dosya boyutu
#   processed_line_count : yayımlanan tam satır sayısı (fallback dedup için)
mergen_stream_read_state_new <- function() {
  list(offset = 0, partial = raw(0), last_size = 0, processed_line_count = 0L)
}

# Ham baytları UTF-8'e güvenle çözer: gömülü NUL temizlenir, geçersiz UTF-8
# baytları düşürülür (Windows VM dayanıklılığı). Çökmeden boş metne döner.
.mergen_stream_decode_raw_utf8 <- function(raw_bytes) {
  if (length(raw_bytes) == 0L) return("")
  raw_bytes <- raw_bytes[raw_bytes != as.raw(0L)]
  if (length(raw_bytes) == 0L) return("")
  txt <- rawToChar(raw_bytes)
  Encoding(txt) <- "UTF-8"
  cleaned <- iconv(txt, from = "UTF-8", to = "UTF-8", sub = "")
  if (is.na(cleaned)) txt else cleaned
}

# Güvenli tam-okuma geri dönüşü (dosya kesilmesi/rotasyonu veya okuma hatası).
# Çift satır yayımını önlemek için processed_line_count ile dilimler.
.mergen_stream_read_full_fallback <- function(path, state) {
  processed <- suppressWarnings(as.integer(state$processed_line_count %||% 0L))
  if (length(processed) == 0L || is.na(processed) || processed < 0L) processed <- 0L

  # Offset GERÇEKTEN okunan bayt sayısından türetilir. file.size() eşzamanlı
  # yazan worker'da bayat-düşük kalabildiği için okuma öncesi boyutu offset
  # yapmak, sonraki turda aynı baytları İKİNCİ kez yayımlıyordu; okuma sonrası
  # boyut ise hiç yayımlanmamış baytları atlatıyordu.
  ham <- raw(0)
  con <- tryCatch(file(path, open = "rb"), error = function(e) NULL)
  if (!is.null(con)) {
    on.exit(try(close(con), silent = TRUE), add = TRUE)
    # Parçalar listede toplanır; `c()` ile büyütmek O(n^2) kopyalama üretirdi.
    parcalar <- list()
    # OKUMA HATASI EOF DEĞİLDİR: `raw(0)` döndürüp döngüyü kırmak, dosyanın
    # ORTASINDA oluşan geçici bir okuma hatasında (Windows/UNC'de eşzamanlı
    # yazılan dosya) kısmi içeriği tam sanıyordu. `offset` ve
    # `processed_line_count` daha önce tüketilen değerin ALTINA geri sarılıyor,
    # sonraki yoklama aynı satırları ikinci kez yayımlıyordu.
    okuma_hatasi <- FALSE
    repeat {
      parca <- tryCatch(
        readBin(con, what = "raw", n = 1048576L),
        error = function(e) {
          okuma_hatasi <<- TRUE
          raw(0)
        }
      )
      if (!length(parca)) break
      parcalar[[length(parcalar) + 1L]] <- parca
    }
    if (!okuma_hatasi && length(parcalar)) ham <- unlist(parcalar, use.names = FALSE)
  }

  if (!length(ham)) {
    # Ham okuma yapılamadı (bağlantı açılamadı / readBin hata verdi) ya da dosya
    # boş. Önceki durum OLDUĞU GİBİ korunur: `processed_line_count` sıfırlanırsa
    # bir sonraki başarılı fallback okuması zaten yayımlanmış satırları İKİNCİ
    # kez gönderiyor ve `accumulated_text` tekrarlanıyordu.
    korunan_offset <- suppressWarnings(as.numeric(state$offset %||% 0))
    if (length(korunan_offset) != 1L || !is.finite(korunan_offset) || korunan_offset < 0) {
      korunan_offset <- 0
    }
    korunan_boyut <- suppressWarnings(as.numeric(state$last_size %||% 0))
    if (length(korunan_boyut) != 1L || !is.finite(korunan_boyut) || korunan_boyut < 0) {
      korunan_boyut <- 0
    }
    return(list(
      lines = character(0),
      state = list(
        offset = korunan_offset,
        partial = if (is.raw(state$partial)) state$partial else raw(0),
        last_size = korunan_boyut,
        processed_line_count = processed
      ),
      used_fallback = TRUE,
      read_bytes = 0
    ))
  }

  size <- length(ham)
  # YALNIZCA LF ile sonlanan satırlar yayımlanır. Yarım kalan son satır ham
  # bayt olarak `partial` içinde tutulur; aksi hâlde tamamlanmamış bir SSE
  # olayı satır sanılıp yayımlanıyor, tamamlandığında `processed` onu zaten
  # işlenmiş saydığı için kalan yarısı hiç görünmüyordu.
  son_lf <- 0L
  lf_konumlari <- which(ham == as.raw(0x0A))
  if (length(lf_konumlari)) son_lf <- lf_konumlari[length(lf_konumlari)]

  if (son_lf > 0L) {
    metin <- .mergen_stream_decode_raw_utf8(ham[seq_len(son_lf)])
    metin <- gsub("\r\n", "\n", metin, fixed = TRUE)
    metin <- sub("\n$", "", metin)
    all_lines <- if (nzchar(metin)) strsplit(metin, "\n", fixed = TRUE)[[1]] else character(0)
  } else {
    all_lines <- character(0)
  }
  kalan <- if (son_lf < length(ham)) ham[(son_lf + 1L):length(ham)] else raw(0)

  total <- length(all_lines)
  # `processed > total` (dosya kısaldı) durumunda imleç BİLİNÇLİ olarak
  # sıfırlanmaz. Akış dosyası istek başına benzersizdir
  # (`tempfile("llm_sse_<req_id>_")`) ve her istek TAZE bir okuma durumuyla
  # başlar; aynı durumla farklı bir akışa geçiş (rotasyon) OLUŞAMAZ. Bu yüzden
  # kısalma yalnızca KESİLME anlamına gelir ve baştan okumak, zaten yayımlanmış
  # deltaları kullanıcıya ikinci kez göndermek olurdu.
  new_lines <- if (total > processed) all_lines[seq.int(processed + 1L, total)] else character(0)

  list(
    lines = new_lines,
    state = list(offset = size, partial = kalan, last_size = size, processed_line_count = total),
    used_fallback = TRUE,
    read_bytes = as.numeric(size)
  )
}

# Akış dosyasından YALNIZCA son okumadan bu yana eklenen satırları okur.
# Ekleme-temelli (append-only) yazımda her fiziksel satırı tam olarak BİR kez
# döndürür; sonraki çağrıda çift satır üretmez. Yarım kalan son satır ham bayt
# olarak tamponlanıp tamamlandığında bir sonraki okumada yayımlanır.
#
# Dönüş: list(lines, state, used_fallback, read_bytes).
#   - dosya yoksa/erişilemezse: boş satır, durum korunur, used_fallback = FALSE.
#   - dosya offset'in altına küçüldüyse (kesme/rotasyon) veya okuma hata verirse:
#     güvenli tam-okuma geri dönüşü (used_fallback = TRUE).
mergen_stream_read_new_lines <- function(path, state = NULL) {
  if (is.null(state) || !is.list(state)) state <- mergen_stream_read_state_new()

  partial <- if (is.raw(state$partial)) state$partial else raw(0)
  offset <- suppressWarnings(as.numeric(state$offset %||% 0))
  if (!is.finite(offset) || offset < 0) offset <- 0
  processed <- suppressWarnings(as.integer(state$processed_line_count %||% 0L))
  if (length(processed) == 0L || is.na(processed) || processed < 0L) processed <- 0L

  last_size <- suppressWarnings(as.numeric(state$last_size %||% 0))
  if (!is.finite(last_size) || last_size < 0) last_size <- 0

  unchanged_state <- list(offset = offset, partial = partial, last_size = last_size,
                          processed_line_count = processed)
  empty_result <- list(lines = character(0), state = unchanged_state,
                       used_fallback = FALSE, read_bytes = 0)

  if (is.null(path) || length(path) == 0L) return(empty_result)
  p <- as.character(path)[1]
  if (is.na(p) || !nzchar(p)) return(empty_result)
  if (!isTRUE(file.exists(p))) return(empty_result)

  # Kesme/rotasyon savunması: dosyanın GÖZLEMLENEN stat boyutu daha önce
  # gördüğümüz stat boyutunun altına inerse güvenli tam-okuma yapılır.
  # Windows VM'de file.size()/stat bayat-düşük kalabilir; offset gerçek EOF'a
  # kadar okunduğu için offset stat boyutunun önüne geçebilir. Bu durum tek
  # başına kesilme sayılmaz, yoksa bir sonraki yoklama fallback ile offset'i
  # bayat file.size() değerine geri alıp satırları tekrar yayımlayabilir.
  size <- suppressWarnings(file.size(p))
  observed_size <- if (!is.na(size) && is.finite(size) && size >= 0) as.numeric(size) else last_size
  if (!is.na(size) && is.finite(size) && size < offset && size < last_size) {
    .mergen_stream_metric_inc("stream_poll_file_read_fallback")
    return(.mergen_stream_read_full_fallback(p, state))
  }

  # ÖNEMLİ (Windows VM): file.size() / stat, BAŞKA bir süreç (SSE worker)
  # tarafından eşzamanlı yazılan dosya için BAYAT olabilir; flush edilmiş baytlar
  # ayrı bir okuyucu tutamacıyla okunabildiği halde boyut metaverisi geç
  # güncellenir. Bu yüzden okunacak bayt miktarını file.size() ile SINIRLAMAYIZ;
  # bağlantıyı offset'ten GERÇEK EOF'a kadar okuruz. Aksi halde canlı reasoning
  # ilk-token'ı görünmez (panel boş kalır) ve boyut metaverisi geç güncellendiğinde
  # birikmiş satırlar tek yoklamada "büyük blok" olarak düşer.
  new_bytes <- tryCatch({
    con <- file(p, open = "rb")
    on.exit(try(close(con), silent = TRUE), add = TRUE)
    if (offset > 0) {
      suppressWarnings(seek(con, where = offset, origin = "start"))
    }
    collected <- raw(0)
    repeat {
      chunk <- readBin(con, what = "raw", n = 262144L)
      if (length(chunk) == 0L) break
      collected <- if (length(collected) > 0L) c(collected, chunk) else chunk
    }
    collected
  }, error = function(e) NULL)

  if (is.null(new_bytes)) {
    .mergen_stream_metric_inc("stream_poll_file_read_fallback")
    return(.mergen_stream_read_full_fallback(p, state))
  }

  if (length(new_bytes) == 0L) {
    # Gerçek EOF offset'te: yeni veri yok (bayat boyuta takılmadan kesin sonuç).
    return(list(
      lines = character(0),
      state = list(offset = offset, partial = partial, last_size = max(last_size, observed_size),
                   processed_line_count = processed),
      used_fallback = FALSE, read_bytes = 0
    ))
  }

  .mergen_stream_metric_inc("stream_poll_file_read_calls")
  .mergen_stream_metric_inc("stream_poll_file_read_bytes", length(new_bytes))

  # Yeni offset gerçekten okunan bayt miktarına göre ilerletilir (file.size'a değil).
  new_offset <- offset + length(new_bytes)
  combined <- c(partial, new_bytes)
  nl_pos <- which(combined == as.raw(0x0A))

  if (length(nl_pos) == 0L) {
    # Henüz tam satır yok; her şeyi tamponla.
    return(list(
      lines = character(0),
      state = list(offset = new_offset, partial = combined,
                   last_size = max(last_size, observed_size),
                   processed_line_count = processed),
      used_fallback = FALSE, read_bytes = length(new_bytes)
    ))
  }

  last_nl <- nl_pos[length(nl_pos)]
  complete_raw <- combined[seq_len(last_nl)]
  remainder <- if (last_nl < length(combined)) {
    combined[(last_nl + 1L):length(combined)]
  } else {
    raw(0)
  }

  text <- .mergen_stream_decode_raw_utf8(complete_raw)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  if (length(lines) == 0L) lines <- character(0)

  list(
    lines = lines,
    state = list(offset = new_offset, partial = remainder,
                 last_size = max(last_size, observed_size),
                 processed_line_count = processed + length(lines)),
    used_fallback = FALSE,
    read_bytes = length(new_bytes)
  )
}

# ------------------------------------------------------------------------------
# Uyarlanır yoklama (adaptive polling / backoff)
# ------------------------------------------------------------------------------

# Yoklama geri çekilme yapılandırmasını ortamdan çözer. VARSAYILAN KAPALI.
mergen_stream_poll_backoff_config <- function() {
  min_ms <- as.integer(.mergen_stream_env_num("MERGEN_STREAM_POLL_MIN_MS", 25))
  max_ms <- as.integer(.mergen_stream_env_num("MERGEN_STREAM_POLL_MAX_MS", 250))
  factor <- .mergen_stream_env_num("MERGEN_STREAM_POLL_BACKOFF_FACTOR", 1.5)

  if (is.na(min_ms) || min_ms < 1L) min_ms <- 1L
  if (is.na(max_ms) || max_ms < min_ms) max_ms <- min_ms
  if (!is.finite(factor) || factor < 1) factor <- 1.5

  list(
    enabled = .mergen_stream_env_flag("MERGEN_STREAM_POLL_IDLE_BACKOFF", default = FALSE),
    min_ms = min_ms,
    max_ms = max_ms,
    factor = factor,
    reset_on_delta = .mergen_stream_env_flag("MERGEN_STREAM_POLL_RESET_ON_DELTA", default = TRUE)
  )
}

# Bir sonraki yoklama aralığını hesaplar (saf karar).
#   - geri çekilme kapalıysa mevcut aralık olduğu gibi döner (sabit yoklama),
#   - yeni satır geldiyse ve reset_on_delta açıksa min_ms'e döner,
#   - boş yoklamalarda factor ile çarpılarak max_ms'e kadar büyür.
# config verilmezse ortamdan okunur (testlerde enjekte edilebilir).
mergen_stream_next_poll_interval_ms <- function(current_interval_ms,
                                                had_new_lines,
                                                config = NULL) {
  if (is.null(config)) config <- mergen_stream_poll_backoff_config()

  current <- suppressWarnings(as.integer(current_interval_ms)[1])
  if (length(current) == 0L || is.na(current) || current < 1L) current <- config$min_ms

  if (!isTRUE(config$enabled)) return(current)

  if (isTRUE(had_new_lines)) {
    if (isTRUE(config$reset_on_delta)) {
      .mergen_stream_metric_inc("stream_poll_delta_reset_count")
      return(config$min_ms)
    }
    return(current)
  }

  nxt <- as.integer(ceiling(current * config$factor))
  if (is.na(nxt) || nxt < config$min_ms) nxt <- config$min_ms
  if (nxt > config$max_ms) nxt <- config$max_ms
  if (nxt > current) .mergen_stream_metric_inc("stream_poll_idle_backoff_count")
  nxt
}

# ------------------------------------------------------------------------------
# Delta taşımacılığı tercihi
# ------------------------------------------------------------------------------

# Bu akış için delta taşımacılığı kullanılmalı mı? Karar sırası:
#   1) MERGEN_STREAM_FULL_UPDATE_LEGACY açıksa -> FALSE (eski tam-güncelleme zorlanır),
#   2) profil zaten delta istiyorsa -> TRUE (mevcut hızlı profiller),
#   3) MERGEN_STREAM_DELTA_DEFAULT açıksa -> TRUE (geniş delta),
#   4) aksi halde FALSE (mevcut varsayılan).
mergen_stream_use_delta_transport <- function(stream_profile = list()) {
  if (.mergen_stream_env_flag("MERGEN_STREAM_FULL_UPDATE_LEGACY", default = FALSE)) {
    return(FALSE)
  }
  if (isTRUE(stream_profile$use_delta_transport)) return(TRUE)
  .mergen_stream_env_flag("MERGEN_STREAM_DELTA_DEFAULT", default = FALSE)
}

# ------------------------------------------------------------------------------
# Savunmacı metin üst sınırları
# ------------------------------------------------------------------------------

# Akış/akıl yürütme metni için karakter üst sınırını ortamdan çözer.
# <=0 değer "sınırsız" anlamındadır.
mergen_stream_text_char_limit <- function(kind = "text") {
  if (identical(kind, "reasoning")) {
    .mergen_stream_env_num("MERGEN_MAX_REASONING_CHARS", 80000)
  } else {
    .mergen_stream_env_num("MERGEN_MAX_STREAM_CHARS", 120000)
  }
}

# Metni güvenle (UTF-8 karakter sınırında) üst sınıra kırpar. substr karakter
# temelli çalıştığı için Türkçe karakter/emoji ortadan bölünmez. Kırpma olduğunda
# isteğe bağlı Türkçe not eklenir ve sayaç artırılır. Sınır <=0 ise kırpma yok.
mergen_stream_apply_text_cap <- function(text, max_chars, note = NULL, metric_name = NULL) {
  txt <- if (is.null(text)) "" else as.character(text)[1]
  if (length(txt) == 0L || is.na(txt)) txt <- ""

  limit <- suppressWarnings(as.numeric(max_chars)[1])
  if (!is.finite(limit) || limit <= 0) {
    return(list(text = txt, truncated = FALSE))
  }

  if (nchar(txt) <= limit) {
    return(list(text = txt, truncated = FALSE))
  }

  truncated_text <- substr(txt, 1L, as.integer(limit))
  if (!is.null(note) && nzchar(note)) {
    truncated_text <- paste0(truncated_text, note)
  }
  if (!is.null(metric_name)) .mergen_stream_metric_inc(metric_name)

  list(text = enc2utf8(truncated_text), truncated = TRUE)
}