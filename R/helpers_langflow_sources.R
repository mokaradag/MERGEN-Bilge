# ==============================================================================
# Dosya Yolu: R/helpers_langflow_sources.R
# Açıklama: Langflow yanıtlarından belge kaynak üstverisi (başlık/yol/sayfa/tür)
#           çıkarımı ve tıklanabilir Kaynakça işaretleyici (marker) katmanı.
#           Kaynaklar mesaj içeriğinde düz metin "[KAYNAK n] ..." satırları
#           olarak kalıcılaştırılır; render sırasında process_message_content
#           bu bloğu güvenli (tüm değerler kaçışlı) .source-link/.kaynakca-entry
#           HTML'ine yükseltir. Böylece mevcut kaynak tıklama -> güvenli dosya
#           önizleme mekanizması (source_file_clicked -> handle_source_file_click)
#           canlı mesajda VE kayıtlı sohbet yeniden yüklemesinde aynı biçimde
#           çalışır. Bu dosya Shiny/oturum/reaktif erişim içermez; saf ve izole
#           test edilebilirdir. Ham HTML asla işaretleyiciden geçirilmez;
#           HTML yalnızca bu dosyadaki kaçışlı kurucudan üretilir (XSS sınırı).
# ==============================================================================

# Bir kaynak sözlüğünden verilen anahtarların ilk boş olmayan skalar string
# değerini döndürür. Liste-sarmalı tekil değerler açılır; bulunamazsa "".
.langflow_source_field <- function(doc, keys) {
  if (!is.list(doc)) return("")
  nms <- names(doc)
  if (is.null(nms)) return("")

  for (key in keys) {
    if (!(key %in% nms)) next
    val <- doc[[key]]
    if (is.list(val) && length(val) == 1) {
      val <- val[[1]]
    }
    if (is.character(val) || is.numeric(val)) {
      out <- trimws(suppressWarnings(as.character(val))[1])
      if (!is.na(out) && nzchar(out)) {
        return(out)
      }
    }
  }
  ""
}

# Tek bir kaynak sözlüğünü kanonik kayda çevirir:
#   list(title, path, page, type)
# Başlık ve yol tamamen boşsa NULL döner (kaynak UYDURULMAZ). Sayfa yalnızca
# saf rakamsa korunur; tür küçük harf alfasayısala indirgenir.
.langflow_source_record <- function(doc) {
  if (!is.list(doc)) return(NULL)

  title <- .langflow_source_field(doc, c("title", "name", "file_name", "filename", "display_name"))
  path <- .langflow_source_field(doc, c("file_path", "filepath", "path", "source", "file"))
  path_like <- function(x) {
    nzchar(x) && (grepl("[\\/]", x) || nzchar(tools::file_ext(gsub("\\\\", "/", x))))
  }
  page <- .langflow_source_field(doc, c("page", "page_number", "page_label", "sayfa"))
  type <- .langflow_source_field(doc, c("type", "file_type", "filetype", "tur"))

  # "source" alanı bazen dosya değil model/bileşen adı taşır; yol ayracı veya
  # bilinen belge uzantısı yoksa kayıt üretme. Başlık tek başına yalnızca dosya
  # adı gibi görünüyorsa kabul edilir; aksi halde tıklanabilir kaynak uydurmayız.
  if (nzchar(path) && !path_like(path)) {
    if (!nzchar(title)) return(NULL)
    path <- ""
  }
  if (!nzchar(title) && nzchar(path)) {
    title <- basename(gsub("\\\\", "/", path))
  }
  if (!nzchar(path) && path_like(title)) {
    path <- title
  }
  if (!nzchar(title) || !path_like(if (nzchar(path)) path else title)) {
    return(NULL)
  }

  page <- if (grepl("^[0-9]+$", page)) page else ""

  type <- tolower(gsub("[^A-Za-z0-9]", "", type))
  if (!nzchar(type)) {
    ext_src <- if (nzchar(path)) path else title
    type <- tolower(tools::file_ext(gsub("\\\\", "/", ext_src)))
  }
  if (grepl("pdf", type)) type <- "pdf"
  if (grepl("word|docx|docm", type)) type <- "docx"

  list(title = title, path = path, page = page, type = type)
}

# Ayrıştırılmış Langflow yanıtında bilinen kaynak dizisi konumlarını toplar.
# Desteklenen şekiller (fromJSON(..., simplifyVector = FALSE) listesi; "sources"
# yerine "source_documents" anahtarı da kabul edilir):
#   - outputs[[i]]$outputs[[j]]$results$message$sources
#   - outputs[[i]]$outputs[[j]]$results$message$data$sources
#   - outputs[[i]]$outputs[[j]]$artifacts$sources
#   - üst düzey parsed$sources
# properties$source (model/bileşen bilgisi) BİLEREK okunmaz; belge kaynağı değildir.
.langflow_source_candidate_arrays <- function(parsed) {
  if (!is.list(parsed)) return(list())

  arrays <- list()
  add_candidate <- function(val) {
    if (is.list(val) && length(val) > 0) {
      arrays[[length(arrays) + 1L]] <<- val
    }
  }
  add_candidates_at <- function(container_path) {
    for (key in c("sources", "source_documents")) {
      add_candidate(.langflow_pluck(parsed, c(container_path, list(key))))
    }
  }

  add_candidates_at(list())

  outer <- parsed$outputs
  if (is.list(outer)) {
    for (i in seq_along(outer)) {
      inner <- .langflow_pluck(outer, list(i, "outputs"))
      if (!is.list(inner)) next
      for (j in seq_along(inner)) {
        add_candidates_at(list("outputs", i, "outputs", j, "results", "message"))
        add_candidates_at(list("outputs", i, "outputs", j, "results", "message", "data"))
        add_candidates_at(list("outputs", i, "outputs", j, "artifacts"))
      }
    }
  }

  arrays
}

# Langflow yanıtından belge kaynak kayıtlarını çıkarır. Her aday dizi öğesi ya
# doğrudan bir belge sözlüğüdür ya da (eski RAG proxy biçimi) "metadata" altında
# belge sözlükleri taşır. Kayıtlar (yol|başlık, sayfa) anahtarıyla teklenir ve
# max_sources ile sınırlanır. Kaynak bulunamazsa boş liste döner.
extract_langflow_chat_sources <- function(parsed, max_sources = 20L) {
  arrays <- .langflow_source_candidate_arrays(parsed)
  if (!length(arrays)) return(list())

  records <- list()
  seen <- character(0)

  add_record <- function(doc) {
    rec <- .langflow_source_record(doc)
    if (is.null(rec)) return(invisible(NULL))
    key <- paste0(tolower(if (nzchar(rec$path)) rec$path else rec$title), "|", rec$page)
    if (key %in% seen) return(invisible(NULL))
    seen <<- c(seen, key)
    records[[length(records) + 1L]] <<- rec
    invisible(NULL)
  }

  for (arr in arrays) {
    if (is.list(arr) && !is.null(names(arr)) && !any(vapply(arr, is.list, logical(1)))) {
      arr <- list(arr)
    }
    for (item in arr) {
      if (length(records) >= max_sources) break
      if (!is.list(item)) next
      meta <- item$metadata
      if (is.list(meta) && length(meta) > 0 && is.null(names(meta))) {
        for (doc in meta) {
          if (length(records) >= max_sources) break
          add_record(doc)
        }
      } else if (is.list(meta) && length(meta) > 0) {
        add_record(meta)
      } else {
        add_record(item)
      }
    }
  }

  records
}

# call_langflow_chat'in worker tarafında kullandığı güvenli kaynak çıkarım
# sarmalayıcısı: beklenmeyen bir hata yanıt metnini asla düşürmemeli, kaynaklar
# sessizce boş listeye inmelidir.
mergen_langflow_safe_sources <- function(parsed) {
  tryCatch(extract_langflow_chat_sources(parsed), error = function(e) list())
}

# İşaretleyici satırlarına girecek değerlerden ayraç/parantez/yeni satır gibi
# gramer bozucu karakterleri temizler (değer verisi olarak kalır, kaçış render
# sırasında yapılır). Ardışık boşluklar teke indirilir.
.kaynakca_marker_sanitize <- function(x) {
  val <- gsub("[\r\n|\\[\\]]+", " ", as.character(x %||% "")[1], perl = TRUE)
  val <- trimws(gsub("[ \t]+", " ", val))
  if (is.na(val)) "" else val
}

# Kaynak kayıtlarından mesaj sonuna eklenecek düz metin Kaynakça işaretleyici
# bloğunu üretir. Kayıt yoksa "" döner. Biçim (satır başına bir kaynak):
#   [KAYNAK 1] Başlık | yol=göreli/yol.pdf | sayfa=3 | tur=pdf
mergen_langflow_kaynakca_marker_block <- function(sources) {
  if (!is.list(sources) || !length(sources)) return("")

  lines <- character(0)
  for (rec in sources) {
    if (!is.list(rec)) next
    title <- .kaynakca_marker_sanitize(rec$title)
    if (!nzchar(title)) next

    line <- paste0("[KAYNAK ", length(lines) + 1L, "] ", title)
    path <- .kaynakca_marker_sanitize(rec$path)
    if (!nzchar(path) && grepl("\\.[A-Za-z0-9]{1,8}$", title)) path <- title
    if (!nzchar(path)) next
    line <- paste0(line, " | yol=", path, " | imza=mergen")
    page <- .kaynakca_marker_sanitize(rec$page)
    if (grepl("^[0-9]+$", page)) line <- paste0(line, " | sayfa=", page)
    type <- tolower(gsub("[^a-z0-9]", "", .kaynakca_marker_sanitize(rec$type)))
    if (nzchar(type)) line <- paste0(line, " | tur=", type)

    lines <- c(lines, line)
  }

  if (!length(lines)) return("")
  paste0("\n\nKaynakça:\n", paste(lines, collapse = "\n"), "\n")
}

# Mesaj içeriğinin SONUNDAKİ Kaynakça işaretleyici bloğunu ayırır.
# Dönüş: list(prose = <bloktan önceki metin>, entries = list(...)) veya blok
# yoksa/geçersizse NULL. Blok içindeki TEK bir satır bile gramerden saparsa tüm
# blok reddedilir (kısmi yükseltme yapılmaz).
mergen_kaynakca_marker_split <- function(content) {
  txt <- as.character(content %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  block_pattern <- "(^|\n)[ \t]*Kaynakça:[ \t]*\n\\[KAYNAK [0-9]+\\][^\n]*(\n\\[KAYNAK [0-9]+\\][^\n]*)*[ \t\n]*$"
  m <- regexpr(block_pattern, txt, perl = TRUE)
  if (m[1] < 0) return(NULL)

  block <- substr(txt, m[1], m[1] + attr(m, "match.length") - 1L)
  prose <- trimws(substr(txt, 1L, m[1] - 1L))

  line_matches <- regmatches(block, gregexpr("\\[KAYNAK [0-9]+\\][^\n]*", block, perl = TRUE))[[1]]
  if (!length(line_matches)) return(NULL)

  entries <- list()
  for (line in line_matches) {
    parts <- strsplit(sub("^\\[KAYNAK [0-9]+\\][ \t]*", "", line), "|", fixed = TRUE)[[1]]
    parts <- trimws(parts)
    title <- if (length(parts)) parts[1] else ""
    if (!nzchar(title)) return(NULL)

    rec <- list(title = title, path = "", page = "", type = "")
    if (length(parts) > 1) {
      for (fld in parts[-1]) {
        fm <- regmatches(fld, regexec("^(yol|sayfa|tur|imza)=(.*)$", fld, perl = TRUE))[[1]]
        if (length(fm) != 3) return(NULL)
        if (identical(fm[2], "sayfa") && !grepl("^[0-9]+$", trimws(fm[3]))) return(NULL)
        if (identical(fm[2], "imza")) {
          if (!identical(trimws(fm[3]), "mergen")) return(NULL)
          rec$signature <- "mergen"
        } else {
          rec[[c(yol = "path", sayfa = "page", tur = "type")[[fm[2]]]]] <- trimws(fm[3])
        }
      }
    }
    if (!identical(rec$signature, "mergen") || !nzchar(rec$path)) return(NULL)
    rec$signature <- NULL
    entries[[length(entries) + 1L]] <- rec
  }

  list(prose = prose, entries = entries)
}

# Kaynak yolundan tıklama çözümleme ipucunu üretir. Mevcut mekanizmanın
# "A&&B&&dosya.pdf" sözleşmesi kullanılır: soldaki parçalar alt klasör ipucu,
# son parça dosya adıdır. Güvenlik: "..", ".", sürücü/kök ve boş parçalar
# atılır; böylece işaretleyiciden gelen bir yol, izinli kökler dışına gezinme
# ipucu üretemez. Yol yoksa başlık kullanılır.
.kaynakca_click_hint <- function(path, title) {
  raw <- as.character(path %||% "")[1]
  if (is.na(raw) || !nzchar(raw)) {
    return(trimws(as.character(title %||% "")[1]))
  }

  segments <- strsplit(gsub("\\\\", "/", raw), "/", fixed = TRUE)[[1]]
  segments <- trimws(segments)
  segments <- segments[nzchar(segments)]
  segments <- segments[!(segments %in% c(".", "..")) & !grepl(":", segments, fixed = TRUE)]

  if (!length(segments)) {
    return(trimws(as.character(title %||% "")[1]))
  }
  paste(segments, collapse = "&&")
}

# Ayrıştırılmış Kaynakça girişlerini güvenli HTML'e çevirir. Tüm değerler
# htmltools::htmlEscape'ten geçer; işaretleyiciden gelen hiçbir metin ham HTML
# olarak yorumlanmaz. Üretilen işaretleme mevcut mekanizmayla aynıdır:
# .kaynakca-entry + .source-link (data-filename tıklama ipucu) + belge ikonu.
mergen_kaynakca_marker_html <- function(entries) {
  if (!is.list(entries) || !length(entries)) return("")

  entry_html <- character(0)
  for (i in seq_along(entries)) {
    rec <- entries[[i]]
    if (!is.list(rec)) next
    title <- trimws(as.character(rec$title %||% "")[1])
    if (!nzchar(title)) next

    type <- tolower(as.character(rec$type %||% "")[1])
    ext <- tolower(tools::file_ext(gsub("\\\\", "/", paste0(rec$path %||% "", ""))))
    icon_html <- if (type %in% c("doc", "docx", "docm") || ext %in% c("doc", "docx", "docm")) {
      "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
    } else if (identical(type, "pdf") || identical(ext, "pdf")) {
      "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
    } else {
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    }

    source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(title)))
    hint <- .kaynakca_click_hint(rec$path, title)

    page <- as.character(rec$page %||% "")[1]
    page_html <- if (grepl("^[0-9]+$", page)) {
      paste0(" <span class='kaynakca-page'>(Sayfa ", page, ")</span>")
    } else {
      ""
    }

    entry_html <- c(entry_html, paste0(
      "<span class='kaynakca-entry' data-entry='", i, "'>",
      i, ") ", icon_html,
      "<span class='source-link' data-source-id='",
      htmltools::htmlEscape(source_id, attribute = TRUE),
      "' data-filename='", htmltools::htmlEscape(hint, attribute = TRUE),
      "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
      htmltools::htmlEscape(title),
      "</span>", page_html,
      "</span>"
    ))
  }

  if (!length(entry_html)) return("")
  paste0(
    "<div class='kaynakca-block'><p>Kaynakça:</p>",
    paste(entry_html, collapse = ""),
    "</div>"
  )
}
