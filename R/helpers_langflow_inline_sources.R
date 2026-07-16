# ==============================================================================
# Dosya Yolu: R/helpers_langflow_inline_sources.R
# Açıklama: Bazı Langflow akışları belge kaynaklarını YAPISAL JSON alanında değil,
#           yanıt METNİNİN sonuna düz "Kaynak:" bölümü ve gövdeye satır içi
#           <sup>(n)</sup> üstsimge atıfları olarak yazar. Bu katman o düzyazı
#           biçimini yakalar: (1) <sup>(n)</sup> atıflarını citation_handler.js
#           üstsimge rozetine dönüşen [n] biçimine çevirir, (2) sondaki "Kaynak:"
#           listesini ayrıştırıp mevcut imzalı Kaynakça işaretleyici bloğuna
#           (mergen_langflow_kaynakca_marker_block) yükseltir; böylece render'da
#           process_message_content aynı güvenli, tıklanabilir .source-link
#           HTML'ini üretir ve kayıtlı sohbet yeniden yüklemesinde de çalışır.
#           Dosya adları "A&&B&&dosya.pdf" gibi düz (dizin olmayan) '&&' ayraçlı
#           gerçek adlardır; disk basename'i '&&' içerir. Bu dosya Shiny/oturum/
#           reaktif erişim içermez; saf ve izole test edilebilirdir. Ham HTML asla
#           üretilmez; işaretleyici düz metindir, HTML kaçışı render'da yapılır.
# ==============================================================================

# Desteklenen belge uzantıları (tıklanabilir kaynak yalnızca bunlar için üretilir).
.langflow_inline_doc_exts <- function() {
  c("pdf", "doc", "docx", "docm", "txt", "csv", "xls", "xlsx", "ppt", "pptx", "md")
}

# Etiket içeriği "citation-şekilli" mi? Yalnızca bir veya daha fazla parantezli
# rakam grubu, örn. "(1)", "(1)(2)", "(1, 2)" kabul edilir (boşluklar önce
# ayıklanır). Bare (parantezsiz) rakam -- m<sup>2</sup> gibi sıradan üs/dipnot
# gösterimi -- citation SAYILMAZ; bu, gerçek Langflow biçimiyle (<sup>(n)</sup>)
# örtüşür ve sıradan üs/dipnot içeriğinin yanlışlıkla atfa dönüştürülmesini
# veya kaybolmasını önler.
.langflow_sup_is_citation_shaped <- function(inner) {
  trimmed <- gsub("[ \t]+", "", inner)
  grepl("^(\\([0-9]+([,;][0-9]+)*\\))+$", trimmed, perl = TRUE)
}

# Gövdedeki <sup>...</sup> üstsimge atıflarını [n] biçimine çevirir. Markdown
# kaçışı (<,> -> &lt;,&gt;) üstsimgeyi metne çevirdiğinden, atıflar burada erken
# [n]'e indirgenir; citation_handler.js bunları tıklanabilir üstsimge rozetine
# dönüştürür. Bir üstsimge birden çok sayı taşıyabilir (<sup>(1)(2)</sup>) ve
# öznitelik içerebilir (<sup class="citation">(1)</sup>). Yalnızca CITATION-
# ŞEKİLLİ (tamamen parantezli rakam grupları) içerik dönüştürülür; sıradan
# (parantezsiz) üs/dipnot gösterimleri (m<sup>2</sup> gibi) DOKUNULMADAN kalır.
# num_map verilirse orijinal numara -> pozisyon yeniden eşlenir (Kaynak listesi
# 1..n sırasıyla numaralanmadıysa atıf/kaynak hizası korunur). Eşleşmeyen numara
# DÜŞÜRÜLÜR (etkisiz): yoğun yeniden numaralanan Kaynakça'da yanlış belgeye atıf
# yapmasını önler. Tüm numaraları düşen citation-şekilli üstsimge kaldırılır.
.langflow_inline_sup_to_citation <- function(text, num_map = NULL) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(text)
  if (!grepl("<sup", txt, ignore.case = TRUE)) return(txt)

  # Öznitelikli açılış etiketini de yakala; <supper> gibi farklı etiketi yakalama
  # (\\b sözcük sınırı).
  m <- gregexpr("<sup\\b[^>]*>.*?</sup>", txt, perl = TRUE, ignore.case = TRUE)
  chunks <- regmatches(txt, m)[[1]]
  if (!length(chunks)) return(txt)

  map_names <- if (!is.null(num_map)) names(num_map) else character(0)
  replacements <- vapply(chunks, function(chunk) {
    # Sayılar YALNIZCA etiket İÇERİĞİNDEN alınır; açılış etiketindeki öznitelik
    # değerlerindeki rakamlar (class="cite-3", data-x='1' ...) atıf sayılmamalı.
    inner <- sub("^<sup\\b[^>]*>", "", chunk, perl = TRUE, ignore.case = TRUE)
    inner <- sub("</sup>$", "", inner, perl = TRUE, ignore.case = TRUE)

    if (!.langflow_sup_is_citation_shaped(inner)) return(chunk)

    nums <- regmatches(inner, gregexpr("[0-9]+", inner, perl = TRUE))[[1]]
    if (!length(nums)) return(chunk)
    if (!is.null(num_map)) {
      mapped <- character(0)
      for (n in nums) {
        if (n %in% map_names) {
          v <- as.character(num_map[[n]])
          if (!is.na(v) && nzchar(v)) mapped <- c(mapped, v)
        }
        # Eşleşmeyen numara atlanır (etkisiz).
      }
      nums <- mapped
    }
    if (!length(nums)) return("")
    paste0("[", nums, "]", collapse = "")
  }, character(1))

  regmatches(txt, m) <- list(replacements)
  txt
}

# Tek bir düz "Kaynak" satırı adayını (numaralı girişin metni) kanonik kayda
# çevirir: list(title, path, page, type). Güvenlik: URL/mutlak/sürücü/gezinme
# (../.) girişleri ve belge uzantısı taşımayanlar reddedilir (NULL). '&&' düz
# dosya adı ayracıdır ve KORUNUR; path disk basename'iyle eşleşebilsin diye
# orijinal '&&' adı olarak tutulur, title son parçadır (görünen dosya adı).
.langflow_prose_source_record <- function(raw_name, num = "") {
  name <- trimws(as.character(raw_name %||% "")[1])
  if (is.na(name) || !nzchar(name)) return(NULL)

  # Markdown süsleri ve sondaki noktalama temizlenir (**, `, sonda ., ,, ;).
  name <- gsub("[*`]", "", name)
  name <- trimws(name)
  name <- sub("[.,;]+$", "", name)
  if (!nzchar(name)) return(NULL)

  # URL / mutlak yol / sürücü harfi reddi.
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", name)) return(NULL)
  norm <- gsub("\\\\", "/", name)
  if (grepl("^/", norm) || grepl("^[A-Za-z]:", norm)) return(NULL)

  # '&&' (düz ad ayracı) veya '/' (gerçek dizin) parçalarına ayır; gezinme kontrolü.
  segs <- strsplit(norm, "(&&|/)", perl = TRUE)[[1]]
  segs <- trimws(segs)
  segs <- segs[nzchar(segs)]
  if (!length(segs)) return(NULL)
  if (any(segs %in% c(".", ".."))) return(NULL)

  last_seg <- segs[length(segs)]
  ext <- tolower(tools::file_ext(last_seg))
  if (!(ext %in% .langflow_inline_doc_exts())) return(NULL)

  type <- if (identical(ext, "pdf")) {
    "pdf"
  } else if (ext %in% c("doc", "docx", "docm")) {
    "docx"
  } else {
    ext
  }

  list(title = last_seg, path = name, page = "", type = type, num = trimws(as.character(num %||% "")[1]))
}

# Yanıt metninin SONUNDAKİ düz "Kaynak(lar/ça):" bölümünü ayrıştırır.
# Dönüş: list(prose = <bölümden önceki metin>, records = list(...)) veya bölüm
# yoksa/geçerli giriş yoksa NULL. Başlık kendi satırında tek başına olmalıdır
# (isteğe bağlı markdown süsleriyle). Girişler "(1) ad", "1) ad", "1. ad",
# "1- ad" biçimlerini kabul eder; ad geçerli bir belge dosyası olmalıdır.
mergen_langflow_parse_prose_sources <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  # CRLF/CR satır sonlarını normalleştir (başlık satırı tespiti için).
  txt <- gsub("\r\n", "\n", txt, fixed = TRUE)
  txt <- gsub("\r", "\n", txt, fixed = TRUE)

  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  if (!length(lines)) return(NULL)

  # "Kaynak" / "Kaynaklar" / "Kaynakça" / "Kaynakca" / "Kaynakları" başlığı;
  # başlık kendi satırında tek başına olmalı (isteğe bağlı markdown/blockquote
  # süsleriyle). "Kaynak" kısmı BÜYÜK/küçük harf duyarsızdır (KAYNAK:, KAYNAKÇA:
  # dahil); ek (lar/ça/ları...) herhangi harften oluşabilir (`ignore.case`
  # Türkçe Ç için güvenilmez olduğundan açık harf sınıfı kullanılır).
  heading_re <- "^[ \t>*_#-]*[Kk][Aa][Yy][Nn][Aa][Kk][A-Za-zçÇğĞıİöÖşŞüÜ]*[ \t]*:?[ \t*_]*$"
  heading_idx <- NA_integer_
  for (i in rev(seq_along(lines))) {
    if (grepl(heading_re, lines[i], perl = TRUE)) {
      heading_idx <- i
      break
    }
  }
  if (is.na(heading_idx)) return(NULL)

  entry_re <- "^[ \t>*_-]*\\(?\\s*([0-9]+)\\s*\\)?[.):\\-]?[ \t]+(.+?)[ \t]*$"
  records <- list()
  saw_entry <- FALSE
  after <- if (heading_idx < length(lines)) {
    lines[(heading_idx + 1L):length(lines)]
  } else {
    character(0)
  }

  n_after <- length(after)
  idx <- 1L
  while (idx <= n_after) {
    ln <- after[idx]
    if (!nzchar(trimws(ln))) {
      # Boş satırlar HER ZAMAN atlanır (listeyi bitirmez); bazı Langflow
      # akışları numaralı girişler arasına boşluk bırakır. Liste yalnızca
      # gerçek (boş olmayan) numarasız bir satırla sonlanır.
      idx <- idx + 1L
      next
    }
    m <- regmatches(ln, regexec(entry_re, ln, perl = TRUE))[[1]]
    if (length(m) != 3) {
      # Numaralı giriş değil: girişler başladıysa dur, başlamadıysa atla.
      if (saw_entry) break
      idx <- idx + 1L
      next
    }
    saw_entry <- TRUE
    rec <- .langflow_prose_source_record(m[3], m[2])
    if (!is.null(rec)) {
      records[[length(records) + 1L]] <- rec
    }
    idx <- idx + 1L
  }

  if (!length(records)) return(NULL)

  # Girişlerden SONRA kalan metin (örn. sarmalanmış bir açıklama veya "Not:"
  # ibaresi) sessizce düşürülmez; düzyazıya eklenmek üzere korunur.
  tail <- if (saw_entry && idx <= n_after) {
    trimws(paste(after[idx:n_after], collapse = "\n"))
  } else {
    ""
  }

  prose <- if (heading_idx > 1L) {
    trimws(paste(lines[seq_len(heading_idx - 1L)], collapse = "\n"))
  } else {
    ""
  }

  list(prose = prose, records = records, tail = tail)
}

# Üretilen imzalı işaretleyici bloğundaki [KAYNAK n] giriş sayısını sayar.
.langflow_count_marker_entries <- function(marker_block) {
  m <- gregexpr("\\[KAYNAK [0-9]+\\]", marker_block, perl = TRUE)[[1]]
  if (length(m) == 1L && m[1] == -1L) return(0L)
  length(m)
}

# Langflow yanıt metnini son biçimine getirir (işleyicinin tek giriş noktası):
#   1) Kaynakça işaretleyici bloğu ekler: önce YAPISAL kaynaklar (mevcut davranış),
#      yoksa düzyazı "Kaynak:" bölümü ayrıştırılıp bölüm SÖKÜLÜR ve imzalı
#      işaretleyici bloğu eklenir. Girişlerden sonraki metin (varsa) düzyazıya
#      taşınarak korunur.
#   2) YALNIZCA tıklanabilir bir Kaynakça bloğu üretildiğinde <sup>(n)</sup>
#      atıflarını [n]'e çevirir; aksi halde "m<sup>2</sup>" gibi sıradan çıktı
#      yanlış atıf gibi görünmez ve ham metin korunur. Atıflar render edilen
#      giriş sayısına hizalanır; aralık dışı/eşleşmeyen atıflar etkisiz kılınır.
# İşaretleyici üretici yüklü değilse (izole test/worker) metin değişmeden döner.
# Sonuç DB'ye kaydedilir; render'da process_message_content tıklanabilir
# Kaynakça'ya yükseltir.
mergen_langflow_finalize_answer <- function(text, structured_sources = list()) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt)) txt <- ""

  marker_block <- ""
  sup_map <- NULL

  has_block_fn <- exists("mergen_langflow_kaynakca_marker_block", mode = "function", inherits = TRUE)

  if (has_block_fn && is.list(structured_sources) && length(structured_sources) > 0) {
    marker_block <- tryCatch(
      mergen_langflow_kaynakca_marker_block(structured_sources),
      error = function(e) ""
    )
    if (nzchar(marker_block)) {
      # Yapısal kaynaklarda atıflar 1..n (render edilen giriş sayısı) ile hizalı
      # varsayılır; aralık dışı atıflar etkisiz kılınır.
      n_entries <- .langflow_count_marker_entries(marker_block)
      if (n_entries > 0L) {
        sup_map <- stats::setNames(as.character(seq_len(n_entries)), as.character(seq_len(n_entries)))
      }
    }
  }

  if (!nzchar(marker_block) && has_block_fn) {
    parsed <- tryCatch(mergen_langflow_parse_prose_sources(txt), error = function(e) NULL)
    if (!is.null(parsed) && length(parsed$records) > 0) {
      block <- tryCatch(
        mergen_langflow_kaynakca_marker_block(parsed$records),
        error = function(e) ""
      )
      if (nzchar(block)) {
        tail_txt <- as.character(parsed$tail %||% "")[1]
        txt <- if (nzchar(tail_txt)) paste0(parsed$prose, "\n\n", tail_txt) else parsed$prose
        marker_block <- block
        # Orijinal Kaynak numarası -> yoğun pozisyon eşlemesi (üstsimge hizalaması).
        orig_nums <- vapply(parsed$records, function(r) as.character(r$num %||% ""), character(1))
        sup_map <- stats::setNames(as.character(seq_along(orig_nums)), orig_nums)
      }
    }
  }

  # Üstsimge dönüşümü yalnızca gerçek bir Kaynakça bloğu varken uygulanır.
  if (nzchar(marker_block)) {
    txt <- .langflow_inline_sup_to_citation(txt, sup_map)
    txt <- paste0(txt, marker_block)
  }
  txt
}
