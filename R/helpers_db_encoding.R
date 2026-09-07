# ==============================================================================
# Dosya Yolu: R/helpers_db_encoding.R
# Açıklama: DB istemci kodlaması, kullanıcıya görünen DB metni normalizasyonu
#           ve MB_Messages yazım sonrası kodlama koruma yardımcıları.
# ==============================================================================

resolve_db_client_encoding <- function() {
  # DB istemci kodlaması üretim VM üzerinde .Renviron ile yönetilir.
  # Ortam değişkeni yoksa test/local varsayılanı korunur.
  env_encoding <- Sys.getenv("DB_CLIENT_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.client_encoding", "UTF-8")
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return("UTF-8")
  }

  trimws(option_encoding)
}

resolve_db_name_encoding <- function(client_encoding = resolve_db_client_encoding()) {
  # Sütun/tablo adı kodlaması ayrı verilmemişse istemci kodlamasıyla aynı tutulur.
  env_encoding <- Sys.getenv("DB_NAME_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.name_encoding", client_encoding)
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return(client_encoding)
  }

  trimws(option_encoding)
}

db_client_encoding_is_utf8 <- function(encoding_name) {
  encoding_name <- toupper(gsub("[_-]", "", as.character(encoding_name %||% "")[1]))
  identical(encoding_name, "UTF8")
}

.DEFAULT_DB_CLIENT_ENCODING <- resolve_db_client_encoding()
.DEFAULT_DB_NAME_ENCODING <- resolve_db_name_encoding(.DEFAULT_DB_CLIENT_ENCODING)

normalize_db_value <- function(x, repair_mojibake = FALSE) {
  # DBI parametreleri çoğunlukla skaler gelir; yine de bu yardımcı vektör,
  # NA ve boş karakter girdilerinde uyarı üretmemelidir. Strict test runner
  # stop_on_warning = TRUE kullandığı için burada warning-free davranış kritiktir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (length(x) == 0L) {
    return(x)
  }

  repair_mojibake <- isTRUE(repair_mojibake)

  out_utf8 <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    normalize_text_utf8(x, repair_mojibake = repair_mojibake)
  } else {
    tryCatch(
      enc2utf8(x),
      error = function(e) x
    )
  }

  out_utf8[is.na(x)] <- NA_character_

  client_encoding <- resolve_db_client_encoding()
  client_is_utf8 <- db_client_encoding_is_utf8(client_encoding)

  if (isTRUE(client_is_utf8) && isTRUE(l10n_info()[["UTF-8"]])) {
    return(out_utf8)
  }

  if (!isTRUE(client_is_utf8)) {
    out_client <- tryCatch(
      iconv(out_utf8, from = "UTF-8", to = client_encoding, sub = NA_character_),
      error = function(e) rep(NA_character_, length(out_utf8))
    )

    failed <- is.na(out_client) & !is.na(out_utf8)

    # WINDOWS-1254 Türkçe karakterleri temsil eder; ancak bazı Unicode sembolleri
    # temsil edemez. Böyle bir karakter tüm string için iconv sonucunu NA yaparsa,
    # ham UTF-8'e düşmek yerine temsil edilemeyen karakterleri ASCII kaçış
    # belirteçlerine dönüştürürüz. UI okuma sınırında bu belirteçler geri açılır.
    if (any(failed)) {
      escaped_values <- if (exists("db_unicode_escape_for_client_encoding", mode = "function", inherits = TRUE)) {
        db_unicode_escape_for_client_encoding(out_utf8[failed], client_encoding)
      } else {
        iconv(out_utf8[failed], from = "UTF-8", to = client_encoding, sub = "")
      }

      escaped_client <- tryCatch(
        iconv(escaped_values, from = "UTF-8", to = client_encoding, sub = NA_character_),
        error = function(e) rep(NA_character_, length(escaped_values))
      )

      still_failed <- is.na(escaped_client) & !is.na(escaped_values)

      if (any(still_failed)) {
        escaped_client[still_failed] <- iconv(
          escaped_values[still_failed],
          from = "UTF-8",
          to = client_encoding,
          sub = ""
        )
      }

      escaped_client[is.na(escaped_client)] <- ""
      out_client[failed] <- escaped_client
    }

    if (any(!is.na(out_client))) {
      Encoding(out_client[!is.na(out_client)]) <- "unknown"
    }

    out_client[is.na(x)] <- NA_character_
    return(out_client)
  }

  out_native <- tryCatch(
    enc2native(out_utf8),
    error = function(e) out_utf8
  )

  out_native[is.na(x)] <- NA_character_

  roundtrip_utf8 <- tryCatch(
    enc2utf8(out_native),
    error = function(e) out_utf8
  )
  roundtrip_utf8[is.na(x)] <- NA_character_

  if (!identical(unname(roundtrip_utf8), unname(out_utf8))) {
    return(out_utf8)
  }

  out_native
}

normalize_db_visible_value <- function(x) {
  # Kullanıcıya görünen metinler DB parametre sınırına gelmeden onarılır.
  # Teknik kimlik, enum, bayrak ve yol alanları bu yardımcıdan geçirilmemelidir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = TRUE))
  }

  enc2utf8(x)
}

normalize_db_technical_value <- function(x) {
  # Teknik karakter alanları UTF-8 olarak işaretlenir; mojibake onarımı yapılmaz.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = FALSE))
  }

  enc2utf8(x)
}

db_visible_text_has_mojibake <- function(value) {
  if (is.null(value) || length(value) == 0L) {
    return(FALSE)
  }

  text <- paste(enc2utf8(as.character(value)), collapse = "\n")

  if (!nzchar(text)) {
    return(FALSE)
  }

  mojibake_tokens <- c(
    "\u00C3\u00A7",
    "\u00C3\u00B6",
    "\u00C3\u00BC",
    "\u00C4\u00B1",
    "\u00C4\u00B0",
    "\u00C4\u0178",
    "\u00C5\u0178",
    "\u00C3\u2021",
    "\u00C3\u2013",
    "\u00C3\u0153",
    "\u00C4\u017E",
    "\u00C5\u017E",
    "T\u00C3\u00BCrkiye",
    "Nas\u00C4\u00B1l",
    "yard\u00C4\u00B1mc\u00C4\u00B1",
    "ba\u00C5\u0178kent",
    "te\u00C5\u0178ekk\u00C3\u00BCr"
  )

  any(vapply(
    mojibake_tokens,
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

# ReasoningContent sütun varlığı süreç başına bir kez belirlenir; her mesaj
# yazımında açık transaction içinde INFORMATION_SCHEMA sorgusu çalıştırılmaz.
.mb_messages_reasoning_column_cache <- new.env(parent = emptyenv())

# Önbellek anahtarı HEDEF ŞEMAYI de içerir. Yalnızca class(conn) ile anahtarlamak
# aynı ODBC sınıfını paylaşan farklı veritabanlarını birbirine karıştırıyordu:
# sütunu olmayan bir DB için önbelleğe alınan FALSE, sütunu olan ikinci DB'de
# reasoning denetimini atlıyor; ters sırada ise post-insert sorgusu var olmayan
# sütunu isteyip hata veriyordu.
# Etkin şema adı (okunamazsa boş dize).
# TABLOYU SAHİPLENEN şema çözülür. `SCHEMA_NAME()` yalnızca ÇAĞIRANIN varsayılan
# şemasıdır: varsayılan şema `dbo` değilken niteliksiz `MB_Messages` sorgusu yine
# `dbo.MB_Messages` tablosunu çözüyor, metaveri filtresi ise `SCHEMA_NAME()` ile
# hiçbir satır bulamıyordu. Guard o durumda `CAST(NULL ...)` seçip
# ReasoningContent mojibake denetimini atlıyor ve bozuk içerik commit ediliyordu.
.mb_messages_current_schema <- function(conn) {
  sahip <- tryCatch({
    df <- DBI::dbGetQuery(
      conn,
      "SELECT OBJECT_SCHEMA_NAME(OBJECT_ID(N'MB_Messages')) AS s"
    )
    deger <- as.character(df[[1]][1])
    if (length(deger) != 1L || is.na(deger)) "" else deger
  }, error = function(e) "")

  if (nzchar(sahip)) return(sahip)

  tryCatch({
    df <- DBI::dbGetQuery(conn, "SELECT SCHEMA_NAME() AS s")
    deger <- as.character(df[[1]][1])
    if (length(deger) != 1L || is.na(deger)) "" else deger
  }, error = function(e) "")
}

# Şema adı da süreç başına ÖNBELLEKLENİR. Önceki biçim, önbellek anahtarını
# kurarken her seferinde `SELECT OBJECT_SCHEMA_NAME(...)` çalıştırıyordu;
# `save_message_to_db()` bu denetimi `UPDLOCK, HOLDLOCK` alındıktan SONRA ve
# `dbCommit()` ÖNCESİNDE yaptığı için her mesaj yazımı kilidi fazladan bir
# gidiş-dönüş kadar uzatıyordu (havuz kapalıyken her yazım yeni bağlantıdır,
# bağlantı başına önbellek bu sorguyu kaldırmaz). Anahtar sunucu|veritabanı|
# kullanıcı üçlüsüdür; şema bu üçlü için kararlıdır ve sonuç ANAHTARIN
# parçası olmaya devam eder.
.mb_messages_schema_cache <- new.env(parent = emptyenv())

.mb_messages_cached_schema <- function(conn, taban) {
  if (!nzchar(taban)) return(.mb_messages_current_schema(conn))

  onbellek <- get0(taban, envir = .mb_messages_schema_cache, inherits = FALSE)
  if (is.character(onbellek) && length(onbellek) == 1L && !is.na(onbellek)) {
    return(onbellek)
  }

  sema <- .mb_messages_current_schema(conn)
  # Boş sonuç (okunamadı) ÖNBELLEKLENMEZ; geçici bir hata kalıcı olmamalıdır.
  if (nzchar(sema)) assign(taban, sema, envir = .mb_messages_schema_cache)
  sema
}

.mb_messages_reasoning_cache_key <- function(conn) {
  kimlik <- tryCatch({
    bilgi <- DBI::dbGetInfo(conn)
    kimlik_parcalari <- c(
      as.character(bilgi$servername %||% bilgi$sourcename %||% "")[1],
      as.character(bilgi$dbname %||% bilgi$dbms.name %||% "")[1],
      as.character(bilgi$username %||% "")[1]
    )
    # NA ayıklama KORUNUR: kimlik hiç okunamadığında anahtar boş kalmalı ve
    # sonuç önbelleğe ALINMAMALIDIR (aksi hâlde farklı veritabanları "NA|NA"
    # altında birleşirdi).
    taban <- paste(kimlik_parcalari[!is.na(kimlik_parcalari)], collapse = "|")
    parcalar <- c(
      taban,
      # ETKİN ŞEMA da anahtara girer: aynı veritabanında farklı şemalardaki
      # MB_Messages tabloları birbirinin sonucunu önbelleğe alabiliyordu.
      .mb_messages_cached_schema(conn, taban)
    )
    paste(parcalar[!is.na(parcalar)], collapse = "|")
  }, error = function(e) "")

  # Kimlik okunamıyorsa ÖNBELLEKLENMEZ (boş anahtar). Sınıf adına geri dönmek
  # farklı veritabanlarını yeniden aynı girişte birleştirirdi.
  if (!nzchar(kimlik)) return("")

  paste(paste(class(conn), collapse = "/"), kimlik, sep = "@")
}

.mb_messages_has_reasoning_column <- function(conn) {
  anahtar <- .mb_messages_reasoning_cache_key(conn)
  if (nzchar(anahtar)) {
    cached <- get0(anahtar, envir = .mb_messages_reasoning_column_cache, inherits = FALSE)
    if (is.logical(cached) && length(cached) == 1L && !is.na(cached)) {
      return(cached)
    }
  }

  sonuc <- tryCatch({
    cols <- DBI::dbGetQuery(
      conn,
      "
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'MB_Messages'
          AND COLUMN_NAME = 'ReasoningContent'
          AND TABLE_SCHEMA = OBJECT_SCHEMA_NAME(OBJECT_ID(N'MB_Messages'))
      "
    )
    nrow(cols) > 0L
  }, error = function(e) {
    NA
  })

  if (!is.na(sonuc) && nzchar(anahtar)) {
    assign(anahtar, isTRUE(sonuc), envir = .mb_messages_reasoning_column_cache)
  }

  # BİLİNMEYEN durum (NA) korunur: şema sondası başarısızken `FALSE` dönmek
  # `CAST(NULL ...)` seçtiriyor, ReasoningContent'teki mojibake saptanmıyor ve
  # bozuk görünür içerik commit edilebiliyordu.
  sonuc
}

# Geri okunan görünür metinde mojibake bulunursa işlem KOŞULSUZ geri alınır:
# yeni hiçbir MB_Messages satırı bozuk metinle kalıcılaşmaz (depo sözleşmesi).
# expected_content / expected_reasoning yalnızca geriye dönük imza uyumluluğu
# için korunur; muafiyet ölçütü olarak KULLANILMAZ.
assert_mb_message_visible_encoding_clean <- function(conn, message_id,
                                                     expected_content = NULL,
                                                     expected_reasoning = NULL) {
  if (is.null(conn) || is.null(message_id) || is.na(message_id)) {
    return(invisible(TRUE))
  }

  has_reasoning_content <- .mb_messages_has_reasoning_column(conn)

  # BİLİNMEYEN sonda sonucu (NA) "sütun yok" sayılmaz: sütun gerçekte varken
  # ReasoningContent denetimi atlanıyor ve mojibake saptanmadan commit
  # edilebiliyordu. Bilinmeyen durumda sütun VARMIŞ gibi denenir; sütun
  # gerçekten yoksa sorgu hata verir ve guard KAPALI-BAŞARISIZ davranır.
  if (is.na(has_reasoning_content)) has_reasoning_content <- TRUE

  query <- if (isTRUE(has_reasoning_content)) {
    "
      SELECT MessageContent, ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  } else {
    "
      SELECT
        MessageContent,
        CAST(NULL AS NVARCHAR(MAX)) AS ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  }

  row <- DBI::dbGetQuery(
    conn,
    query,
    params = normalize_db_params(list(as.integer(message_id)))
  )

  if (nrow(row) == 0L) {
    return(invisible(TRUE))
  }

  # KOŞULSUZ: geri okunan değerde mojibake varsa işlem geri alınır. Girdinin
  # kendisi bozuksa muafiyet tanımak, ZATEN bozuk bir kullanıcı/asistan metnini
  # (ya da ODBC yazımının eklediği bozulmayı) yeni bir MB_Messages satırı olarak
  # kalıcılaştırıyor ve guard'ı o sütun için tamamen devre dışı bırakıyordu.
  # Görünür metin bağlamadan ÖNCE normalize_db_visible_value() ile onarılır.
  if (db_visible_text_has_mojibake(row$MessageContent) ||
      db_visible_text_has_mojibake(row$ReasoningContent)) {
    stop(
      sprintf(
        "MB_Messages encoding guard failed after insert. MessageID=%s. Transaction will be rolled back.",
        as.character(message_id)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

normalize_db_params <- function(params, repair_mojibake = FALSE) {
  lapply(params, normalize_db_value, repair_mojibake = repair_mojibake)
}