# ==============================================================================
# Dosya Yolu: R/helpers_admin_documentation.R
# Açıklama: Yönetici paneli "Dokümantasyon" sayfası için saf yardımcılar.
#            - İzin listeli (allowlist) belge kayıt defteri (tek doğruluk kaynağı)
#            - Yol güvenliği (path traversal / mutlak yol reddi)
#            - UTF-8 güvenli Markdown okuma
#            - commonmark ile Markdown -> HTML + etiket beyaz-liste temizliği
#            - Başlıklardan ASCII-güvenli çapa (anchor) ve İçindekiler üretimi
#
#            Bu dosya yalnızca saf fonksiyon içerir: Shiny/reaktif/DB/ağ erişimi
#            YOKTUR. Böylece çevrimdışı ve deterministik biçimde test edilebilir.
#            CLAUDE.md Markdown/HTML güvenlik sınırı korunur: belgeler güvenilir
#            depo dosyalarıdır; yine de ham script/olay yakalayıcı HTML
#            etkisizleştirilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# BELGE KAYIT DEFTERİ (TEK DOĞRULUK KAYNAĞI / ALLOWLIST)
# ------------------------------------------------------------------------------
# Yalnızca buradaki belgeler uygulama içinde gösterilir. CLAUDE.md ve AGENTS.md
# (AI ajan sözleşmeleri) bilinçli olarak DIŞARIDA bırakılmıştır.
admin_doc_registry <- function() {
  list(
    list(
      id = "baslangic", title = "Başlangıç", icon = "rocket",
      docs = list(
        list(id = "readme", title = "Genel Bakış (README)",
             file = "README.md",
             desc = "Ürünün genel tanıtımı ve ilk giriş belgesi."),
        list(id = "docs_readme", title = "Dokümantasyon Haritası",
             file = "docs/README.md",
             desc = "Tüm belgelerin haritası ve önerilen okuma sırası.")
      )
    ),
    list(
      id = "mimari", title = "Mimari ve Teknik", icon = "sitemap",
      docs = list(
        list(id = "architecture", title = "Mimari Haritası",
             file = "docs/architecture-map.md",
             desc = "Uygulama mimarisi, katmanlar ve korunan sınırlar."),
        list(id = "database", title = "Veritabanı Şeması",
             file = "docs/database-schema.md",
             desc = "MB_* tabloları ve veri modeli."),
        list(id = "technical", title = "Teknik Referans",
             file = "docs/technical-reference.md",
             desc = "Derin teknik referans ve modül ayrıntıları.")
      )
    ),
    list(
      id = "operasyon", title = "Operasyon", icon = "server",
      docs = list(
        list(id = "runbook", title = "Operasyon Kılavuzu (RUNBOOK)",
             file = "RUNBOOK.md",
             desc = "Windows VM, SSO ve üretim çalıştırma kılavuzu."),
        list(id = "dependency", title = "Bağımlılık Kilitleme",
             file = "docs/dependency-locking.md",
             desc = "renv ile sürüm kilitleme akışı ve kurallar."),
        list(id = "renv_status", title = "renv Kilit Durumu",
             file = "RENV_LOCK_STATUS.md",
             desc = "Üretim renv.lock kaynağı ve sağlama notu.")
      )
    ),
    list(
      id = "urun", title = "Ürün ve Davranış", icon = "compass",
      docs = list(
        list(id = "ai_rehber", title = "Asistan Davranış Rehberi",
             file = "ai_rehber.md",
             desc = "Destek sohbet botu ve AI Uzman için bilgi tabanı."),
        list(id = "release_notes", title = "Sürüm Notları",
             file = "docs/release-notes.md",
             desc = "Sürüm geçmişi ve değişiklik notları.")
      )
    )
  )
}

# Tüm belgeleri tek düz listeye indirger
admin_doc_all_docs <- function() {
  out <- list()
  for (g in admin_doc_registry()) {
    for (d in g$docs) {
      out[[length(out) + 1L]] <- d
    }
  }
  out
}

# Belge kimliğine göre kayıt defteri girdisini döndürür (yoksa NULL)
admin_doc_lookup <- function(doc_id) {
  if (is.null(doc_id) || !is.character(doc_id) ||
      length(doc_id) != 1L || is.na(doc_id) || !nzchar(doc_id)) {
    return(NULL)
  }
  for (d in admin_doc_all_docs()) {
    if (identical(d$id, doc_id)) return(d)
  }
  NULL
}

admin_doc_is_known <- function(doc_id) {
  !is.null(admin_doc_lookup(doc_id))
}

admin_doc_docs_in_group <- function(group_id) {
  for (g in admin_doc_registry()) {
    if (identical(g$id, group_id)) return(g$docs)
  }
  list()
}

admin_doc_default_group_id <- function() {
  admin_doc_registry()[[1]]$id
}

admin_doc_default_doc_id <- function() {
  admin_doc_registry()[[1]]$docs[[1]]$id
}

# ------------------------------------------------------------------------------
# REPO KÖKÜ VE YOL GÜVENLİĞİ
# ------------------------------------------------------------------------------
# Çalışma zamanında repo kökünü bulur: app.R + R/ klasörü olan dizin.
admin_doc_repo_root <- function() {
  candidates <- c(
    getwd(),
    Sys.getenv("MERGEN_REPO_ROOT", ""),
    normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
  )
  candidates <- candidates[nzchar(candidates)]

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

# İzin listeli belge kimliğini güvenli mutlak yola çözer.
# Bilinmeyen kimlik, yol kaçışı (..) veya mutlak yol => "" (reddedilir).
admin_doc_resolve_path <- function(doc_id, root = admin_doc_repo_root()) {
  entry <- admin_doc_lookup(doc_id)
  if (is.null(entry)) return("")

  rel <- entry$file
  if (is.null(rel) || !is.character(rel) || length(rel) != 1L || !nzchar(rel)) {
    return("")
  }

  # Güvenlik: yol kaçışı ve mutlak/sürücü-kökü yollar reddedilir
  if (grepl("..", rel, fixed = TRUE)) return("")
  if (grepl("^([A-Za-z]:|/|\\\\)", rel, perl = TRUE)) return("")

  if (is.null(root) || !nzchar(root)) return("")

  candidate <- normalizePath(file.path(root, rel), winslash = "/", mustWork = FALSE)
  root_norm <- normalizePath(root, winslash = "/", mustWork = FALSE)

  # İçerme kontrolü: aday kesinlikle kök altında olmalı
  if (!startsWith(paste0(candidate, "/"), paste0(root_norm, "/"))) {
    return("")
  }

  candidate
}

# UTF-8/BOM/CRLF güvenli okuma; satırları tek metne birleştirir.
admin_doc_read_markdown <- function(path) {
  if (is.null(path) || !is.character(path) || length(path) != 1L ||
      !nzchar(path) || !file.exists(path)) {
    return("")
  }

  lines <- if (exists("read_text_lines_utf8", mode = "function", inherits = TRUE)) {
    read_text_lines_utf8(path)
  } else {
    tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"),
             error = function(e) character(0))
  }

  if (!length(lines)) return("")
  enc2utf8(paste(lines, collapse = "\n"))
}

# ------------------------------------------------------------------------------
# ÇAPA (ANCHOR) / SLUG ÜRETİMİ
# ------------------------------------------------------------------------------
# Türkçe karakterleri ASCII'ye çevirir; ASCII-güvenli slug üretir. tolower yerine
# chartr ile küçültür çünkü Türkçe locale'de tolower("I") -> "ı" (locale-bağımlı).
admin_doc_slugify <- function(text) {
  if (is.null(text) || !is.character(text) || length(text) != 1L || is.na(text)) {
    return("bolum")
  }

  s <- enc2utf8(text)
  tr_from <- c("ç", "Ç", "ğ", "Ğ", "ı", "İ", "ö", "Ö", "ş", "Ş", "ü", "Ü")
  tr_to   <- c("c", "c", "g", "g", "i", "i", "o", "o", "s", "s", "u", "u")
  for (i in seq_along(tr_from)) {
    s <- gsub(tr_from[i], tr_to[i], s, fixed = TRUE)
  }

  # ASCII'ye özel olmayan kalan karakterleri de güvenli biçimde ayıkla
  s <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", s)
  s <- gsub("[^a-z0-9]+", "-", s, perl = TRUE)
  s <- gsub("^-+|-+$", "", s, perl = TRUE)

  if (!nzchar(s)) s <- "bolum"
  s
}

# İç metinden HTML etiketlerini ve temel entity'leri ayıklar (İçindekiler metni).
admin_doc_strip_tags <- function(x) {
  if (is.null(x) || !is.character(x) || length(x) != 1L || is.na(x)) return("")
  out <- gsub("<[^>]*>", "", x, perl = TRUE)
  out <- gsub("&lt;", "<", out, fixed = TRUE)
  out <- gsub("&gt;", ">", out, fixed = TRUE)
  out <- gsub("&quot;", "\"", out, fixed = TRUE)
  out <- gsub("&#39;", "'", out, fixed = TRUE)
  out <- gsub("&amp;", "&", out, fixed = TRUE)
  trimws(out)
}

# ------------------------------------------------------------------------------
# HTML GÜVENLİK TEMİZLİĞİ (ETİKET BEYAZ-LİSTESİ)
# ------------------------------------------------------------------------------
# commonmark çıktısı; kod blokları zaten escape edilmiştir. Yalnızca <...>
# token'ları işlenir: izinli etiketler korunur (tehlikeli attribute'lar
# temizlenir), izinsiz etiketler (script/iframe/style ...) escape edilerek
# etkisizleştirilir. Gövde metni (token dışı) hiç değiştirilmez.
admin_doc_allowed_tags <- function() {
  c("h1", "h2", "h3", "h4", "h5", "h6", "p", "br", "hr", "a", "ul", "ol",
    "li", "code", "pre", "blockquote", "strong", "em", "del", "ins", "sup",
    "sub", "table", "thead", "tbody", "tr", "th", "td", "img", "span", "div")
}

# İzinli bir etiketin attribute dizesini güvenli hale getirir.
admin_doc_clean_attributes <- function(attr_str) {
  if (is.null(attr_str) || is.na(attr_str) || !nzchar(attr_str)) return("")
  out <- attr_str

  # Olay yakalayıcı (on*) attribute'larını kaldır
  out <- gsub("\\s+on[a-zA-Z]+\\s*=\\s*\"[^\"]*\"", "", out, perl = TRUE)
  out <- gsub("\\s+on[a-zA-Z]+\\s*=\\s*'[^']*'", "", out, perl = TRUE)
  out <- gsub("\\s+on[a-zA-Z]+\\s*=\\s*[^\\s>]+", "", out, perl = TRUE)

  # Inline style kaldır (gerekmez, expression() benzeri riskleri eler)
  out <- gsub("\\s+style\\s*=\\s*\"[^\"]*\"", "", out, perl = TRUE)
  out <- gsub("\\s+style\\s*=\\s*'[^']*'", "", out, perl = TRUE)

  # Tehlikeli protokolleri (# ile) etkisizleştir
  out <- gsub(
    "(href|src|xlink:href)\\s*=\\s*\"\\s*(?:javascript|vbscript)\\s*:[^\"]*\"",
    "\\1=\"#\"", out, perl = TRUE, ignore.case = TRUE)
  out <- gsub(
    "(href|src|xlink:href)\\s*=\\s*'\\s*(?:javascript|vbscript)\\s*:[^']*'",
    "\\1='#'", out, perl = TRUE, ignore.case = TRUE)
  out <- gsub(
    "(href|src|xlink:href)\\s*=\\s*(?:javascript|vbscript)\\s*:[^\\s>]*",
    "\\1=\"#\"", out, perl = TRUE, ignore.case = TRUE)
  out <- gsub(
    "(href|src)\\s*=\\s*\"\\s*data\\s*:\\s*text/html[^\"]*\"",
    "\\1=\"#\"", out, perl = TRUE, ignore.case = TRUE)

  out
}

# Tek bir <...> token'ını güvenli hale getirir (yalnızca ilgi gerektirenler için).
admin_doc_clean_one_tag <- function(tok, allowed = admin_doc_allowed_tags()) {
  inner <- substring(tok, 2L, nchar(tok) - 1L)

  # HTML yorumlarını tamamen düşür
  if (startsWith(inner, "!--")) return("")

  is_close <- grepl("^\\s*/", inner, perl = TRUE)
  body <- sub("^\\s*/?\\s*", "", inner, perl = TRUE)
  name <- tolower(sub("(^[a-zA-Z][a-zA-Z0-9]*).*$", "\\1", body, perl = TRUE))

  # İzinli değilse etkisizleştir (escape)
  if (!grepl("^[a-z][a-z0-9]*$", name) || !(name %in% allowed)) {
    return(paste0("&lt;", inner, "&gt;"))
  }

  if (is_close) return(paste0("</", name, ">"))

  self_close <- grepl("/\\s*$", inner)
  attr_str <- sub("^[a-zA-Z][a-zA-Z0-9]*", "", body)
  attr_str <- sub("/\\s*$", "", attr_str)
  attr_str <- trimws(admin_doc_clean_attributes(attr_str))
  closing <- if (self_close) " />" else ">"

  if (nzchar(attr_str)) {
    paste0("<", name, " ", attr_str, closing)
  } else {
    paste0("<", name, closing)
  }
}

# Ham HTML'de script çalıştırabilecek bir kalıp var mı? (hızlı tek-geçiş tarama)
# Tehlikenin TEK yolu: (a) script-yetenekli etiket, (b) on* olay yakalayıcı,
# (c) javascript:/vbscript:/data:text/html URL. Hiçbiri yoksa HTML zaten
# zararsızdır ve pahalı token ayrıştırması atlanır (büyük belge performansı).
admin_doc_html_has_risk <- function(html) {
  pattern <- paste0(
    "<\\s*/?\\s*(?:script|style|iframe|object|embed|form|input|link|meta",
    "|base|svg|math|template|frame|frameset|applet|noscript|xml|image|button",
    "|select|textarea|marquee|audio|video|source|track|canvas|portal|html|body|head)\\b",
    "|\\son[a-zA-Z]+\\s*=",
    "|(?:javascript|vbscript)\\s*:",
    "|data\\s*:\\s*text/html"
  )
  grepl(pattern, html, perl = TRUE, ignore.case = TRUE)
}

admin_doc_sanitize_html <- function(html) {
  if (is.null(html) || length(html) != 1L || is.na(html) || !nzchar(html)) {
    return("")
  }

  # Hızlı yol: hiçbir riskli kalıp yoksa, çıktıyı olduğu gibi döndür.
  if (!admin_doc_html_has_risk(html)) {
    return(html)
  }

  allowed <- admin_doc_allowed_tags()
  m <- gregexpr("<[^>]*>", html, perl = TRUE)
  toks <- regmatches(html, m)[[1]]
  if (!length(toks)) return(html)

  # Performans: büyük belgelerde token sayısı binlerce olabilir. commonmark
  # çıktısının ezici çoğunluğu güvenli yapısal etiketlerdir (<p>, <li>, <a ...>).
  # Bu yüzden önce VEKTÖREL bir geçişle yalnızca "ilgi gerektiren" token'ları
  # işaretler, ardından sadece onları tekil temizlik fonksiyonundan geçiririz.
  inner <- substring(toks, 2L, nchar(toks) - 1L)
  body0 <- sub("^\\s*/?\\s*", "", inner, perl = TRUE)
  names_v <- tolower(sub("(^[a-zA-Z][a-zA-Z0-9]*).*$", "\\1", body0, perl = TRUE))
  valid_name <- grepl("^[a-z][a-z0-9]*$", names_v, perl = TRUE)
  is_comment <- startsWith(inner, "!--")
  disallowed <- !valid_name | !(names_v %in% allowed)
  dangerous_attr <- grepl(
    "(\\son[a-zA-Z]+\\s*=)|(\\sstyle\\s*=)|((?:javascript|vbscript)\\s*:)|(data\\s*:\\s*text/html)",
    toks, perl = TRUE, ignore.case = TRUE
  )

  needs <- is_comment | disallowed | dangerous_attr
  if (any(needs)) {
    idx <- which(needs)
    toks[idx] <- vapply(
      toks[idx], admin_doc_clean_one_tag, character(1),
      allowed = allowed, USE.NAMES = FALSE
    )
    regmatches(html, m) <- list(toks)
  }

  html
}

# ------------------------------------------------------------------------------
# İÇİNDEKİLER (TOC) + BAŞLIK ÇAPALARI
# ------------------------------------------------------------------------------
# Temizlenmiş HTML üzerinden başlıklara ASCII-güvenli id ekler ve İçindekiler
# listesini üretir. Çakışan başlıklar için benzersizlik eki uygulanır.
admin_doc_extract_toc <- function(html) {
  if (is.null(html) || length(html) != 1L || is.na(html) || !nzchar(html)) {
    return(list(html = if (is.null(html)) "" else html, toc = list()))
  }

  m <- gregexpr("<h([1-6])>(.*?)</h\\1>", html, perl = TRUE)
  matches <- regmatches(html, m)[[1]]
  if (!length(matches)) return(list(html = html, toc = list()))

  used <- new.env(parent = emptyenv())
  toc <- vector("list", length(matches))
  new_heads <- character(length(matches))

  for (i in seq_along(matches)) {
    h <- matches[i]
    level <- as.integer(sub("^<h([1-6])>.*$", "\\1", h, perl = TRUE))
    inner <- sub("^<h[1-6]>(.*)</h[1-6]>$", "\\1", h, perl = TRUE)
    text <- admin_doc_strip_tags(inner)
    if (!nzchar(text)) text <- "Bölüm"

    anchor <- paste0("mbdoc-", admin_doc_slugify(text))
    key <- anchor
    n <- 1L
    while (!is.null(used[[key]])) {
      n <- n + 1L
      key <- paste0(anchor, "-", n)
    }
    used[[key]] <- TRUE
    anchor <- key

    new_heads[i] <- paste0(
      "<h", level, " id=\"", anchor,
      "\" class=\"mb-doc-h mb-doc-h", level, "\">", inner, "</h", level, ">"
    )
    toc[[i]] <- list(level = level, text = text, id = anchor)
  }

  regmatches(html, m) <- list(new_heads)
  list(html = html, toc = toc)
}

# ------------------------------------------------------------------------------
# YÜKSEK SEVİYE RENDER
# ------------------------------------------------------------------------------
admin_doc_render_markdown <- function(content) {
  if (is.null(content) || !is.character(content) || length(content) != 1L ||
      is.na(content) || !nzchar(content)) {
    return(list(html = "", toc = list()))
  }

  raw_html <- commonmark::markdown_html(
    content,
    hardbreaks = FALSE,
    extensions = c("strikethrough", "table")
  )

  safe_html <- admin_doc_sanitize_html(raw_html)
  admin_doc_extract_toc(safe_html)
}

# İzin listeli belge kimliğini güvenli biçimde render eder.
admin_doc_render_document <- function(doc_id, root = admin_doc_repo_root()) {
  entry <- admin_doc_lookup(doc_id)
  if (is.null(entry)) {
    return(list(ok = FALSE, doc_id = doc_id, title = "", source = "",
                html = "", toc = list(),
                message = "Bu belge görüntülenemiyor."))
  }

  path <- admin_doc_resolve_path(doc_id, root)
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(list(ok = FALSE, doc_id = doc_id, title = entry$title,
                source = entry$file, html = "", toc = list(),
                message = "Belge dosyası bulunamadı."))
  }

  content <- admin_doc_read_markdown(path)
  rendered <- admin_doc_render_markdown(content)

  list(ok = TRUE, doc_id = doc_id, title = entry$title, source = entry$file,
       html = rendered$html, toc = rendered$toc, message = "")
}
