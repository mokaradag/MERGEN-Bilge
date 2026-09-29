# ==============================================================================
# Dosya Yolu: R/helpers_admin_documentation_sanitize.R
# Açıklama: Yönetici paneli "Dokümantasyon" sayfası için HTML güvenlik temizliği
#           (etiket beyaz-listesi) ve tırnak duyarlı etiket/öznitelik
#           ayrıştırıcısı. R/helpers_admin_documentation.R kullanır.
#           Saf fonksiyonlardır: Shiny/reaktif/DB/ağ erişimi yoktur.
# ==============================================================================

# commonmark çıktısı; kod blokları zaten escape edilmiştir. Yalnızca <...>
# token'ları işlenir: izinli etiketler korunur (tehlikeli attribute'lar
# temizlenir), izinsiz etiketler (script/iframe/style ...) escape edilerek
# etkisizleştirilir. Gövde metni (token dışı) hiç değiştirilmez.
admin_doc_allowed_tags <- function() {
  c("h1", "h2", "h3", "h4", "h5", "h6", "p", "br", "hr", "a", "ul", "ol",
    "li", "code", "pre", "blockquote", "strong", "em", "del", "ins", "sup",
    "sub", "table", "thead", "tbody", "tr", "th", "td", "img", "span", "div")
}

# Etiket tarayıcısı tırnak duyarlıdır: tırnaklı öznitelik değerindeki ">"
# etiketi bitirmez (`<img alt=">" onerror=...>` tek token olarak denetlenir).
# HTML yorumu ayrı yakalanır; yorumdaki kesme işareti metni yutmaz. Kapanmamış
# tırnaklı etiket de ilk ">"e kadar token sayılır ve temizlenir.
.ADMIN_DOC_TAG_PATTERN <- "<!--[\\s\\S]*?-->|<(?:[^>\"']|\"[^\"]*\"|'[^']*')*>|<[^>]*>"

# Şema adındaki gömülü TAB/satır sonu/denetim karakterleri (tarayıcı URL
# ayrıştırmasında atılır) risk taramasında da yok sayılır.
.admin_doc_scheme_pattern <- function() {
  ara <- "[\\s\\x00-\\x1f]*"
  paste0("(?:", paste(strsplit("javascript", "")[[1]], collapse = ara), "|",
         paste(strsplit("vbscript", "")[[1]], collapse = ara), ")", ara, ":")
}
.ADMIN_DOC_RISKY_ATTR <- paste0("[\\s/](?:on[a-zA-Z]+|style|ping)\\s*=|", .admin_doc_scheme_pattern())

# Öznitelik dizesini tırnak duyarlı ayrıştırır: list(ad, deger) listesi
# (değersiz öznitelikte deger NA). Tırnaklı değerin İÇİNDEKİ `href=` metni ayrı
# öznitelik sayılmaz.
admin_doc_parse_attrs <- function(attr_str) {
  if (!is.character(attr_str) || length(attr_str) != 1L || is.na(attr_str) || !nzchar(attr_str)) {
    return(list())
  }
  m <- gregexpr("([^\\s\"'>/=]+)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+)))?",
                attr_str, perl = TRUE)[[1]]
  if (m[1] == -1L) return(list())
  bas <- attr(m, "capture.start")
  uz <- attr(m, "capture.length")
  lapply(seq_along(m), function(i) {
    grup <- which(bas[i, 2:4] > 0)
    deger <- if (length(grup)) substr(attr_str, bas[i, grup[1] + 1L], bas[i, grup[1] + 1L] + uz[i, grup[1] + 1L] - 1L) else NA_character_
    list(ad = tolower(substr(attr_str, bas[i, 1], bas[i, 1] + uz[i, 1] - 1L)), deger = deger)
  })
}

# Ayrıştırılmış öznitelikleri çift tırnaklı, kaçışlı biçimde yeniden yazar.
admin_doc_attrs_html <- function(attrs) {
  if (!length(attrs)) return("")
  paste(vapply(attrs, function(a) {
    if (is.na(a$deger)) a$ad else sprintf("%s=\"%s\"", a$ad, gsub("\"", "&quot;", a$deger, fixed = TRUE))
  }, character(1)), collapse = " ")
}

# Adres değerindeki sayısal HTML varlıkları (`&#x61;`, `&#97;`) ve adlandırılmış
# ayırıcılar çözülür, boşluk/denetim karakterleri atılır: tarayıcının gördüğü
# şema denetlenir (`jav&#x61;script:` gizlemesi geçmez).
.admin_doc_url_scheme_text <- function(deger) {
  sayilar <- regmatches(deger, gregexpr("&#[xX]?[0-9a-fA-F]+;?", deger, perl = TRUE))[[1]]
  for (v in unique(sayilar)) {
    sayi <- sub("^&#[xX]?([0-9a-fA-F]+);?$", "\\1", v)
    n <- suppressWarnings(if (grepl("^&#[xX]", v)) strtoi(sayi, 16L) else as.integer(sayi))
    deger <- gsub(v, if (is.na(n) || n <= 0L || n > 0x10FFFFL) "" else intToUtf8(n), deger, fixed = TRUE)
  }
  deger <- gsub("&colon;", ":", deger, ignore.case = TRUE)
  tolower(gsub("[[:space:][:cntrl:]]|&tab;|&newline;", "", deger, perl = TRUE, ignore.case = TRUE))
}

# İzinli bir etiketin attribute dizesini güvenli hale getirir: olay
# yakalayıcı (on*), style ve ping (tıklamada ek istek) kaldırılır; javascript:/vbscript:/data:text/html
# adresleri "#" olur. Öznitelikler tırnak duyarlı ayrıştırılıp yeniden yazılır.
admin_doc_clean_attributes <- function(attr_str) {
  attrs <- Filter(function(a) {
    grepl("^[a-z][a-z0-9:_.-]*$", a$ad) && !grepl("^on", a$ad) && !a$ad %in% c("style", "ping")
  }, admin_doc_parse_attrs(attr_str))
  adres <- c("href", "src", "xlink:href", "action", "formaction", "poster")
  for (k in seq_along(attrs)) {
    a <- attrs[[k]]
    if (a$ad %in% adres && !is.na(a$deger) &&
        grepl("^(?:javascript|vbscript):|^data:text/html", .admin_doc_url_scheme_text(a$deger), perl = TRUE)) {
      attrs[[k]]$deger <- "#"
    }
  }
  admin_doc_attrs_html(attrs)
}

# Tek bir <...> token'ını güvenli hale getirir (yalnızca ilgi gerektirenler için).
admin_doc_clean_one_tag <- function(tok, allowed = admin_doc_allowed_tags()) {
  inner <- substring(tok, 2L, nchar(tok) - 1L)

  # HTML yorumlarını tamamen düşür
  if (startsWith(inner, "!--")) return("")

  is_close <- grepl("^\\s*/", inner, perl = TRUE)
  body <- sub("^\\s*/?\\s*", "", inner, perl = TRUE)
  name <- tolower(sub("(?s)(^[a-zA-Z][a-zA-Z0-9]*).*$", "\\1", body, perl = TRUE))

  # İzinli değilse etkisizleştir (escape)
  if (!grepl("^[a-z][a-z0-9]*$", name) || !(name %in% allowed)) {
    return(paste0("&lt;", gsub("<", "&lt;", gsub(">", "&gt;", inner, fixed = TRUE), fixed = TRUE), "&gt;"))
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
# Tehlikenin TEK yolu: (a) script-yetenekli etiket, (b) on*/style/ping
# özniteliği (`/` sınırıyla da), (c) javascript:/vbscript:/data:text/html URL
# (sayısal varlıkla ya da gömülü TAB/satır sonuyla gizlenmiş adres dahil). Hiçbiri yoksa HTML zaten zararsızdır ve pahalı token
# ayrıştırması atlanır (büyük belge performansı).
admin_doc_html_has_risk <- function(html) {
  pattern <- paste0(
    "<\\s*/?\\s*(?:script|style|iframe|object|embed|form|input|link|meta",
    "|base|svg|math|template|frame|frameset|applet|noscript|xml|image|button",
    "|select|textarea|marquee|audio|video|source|track|canvas|portal|html|body|head)\\b",
    "|", .ADMIN_DOC_RISKY_ATTR,
    "|data\\s*:\\s*text/html",
    "|(?:href|src|action)\\s*=\\s*[\"']?[^\"'>]*&(?:#|colon;|tab;|newline;)"
  )
  if (grepl(pattern, html, perl = TRUE, ignore.case = TRUE)) return(TRUE)
  # Beyaz liste dışındaki her etiket (ör. <details>, <dialog>) de tam geçişe girer.
  etiketler <- regmatches(html, gregexpr("<\\s*/?\\s*[a-zA-Z][a-zA-Z0-9]*", html, perl = TRUE))[[1]]
  any(!tolower(sub("^<\\s*/?\\s*", "", etiketler, perl = TRUE)) %in% admin_doc_allowed_tags())
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
  m <- gregexpr(.ADMIN_DOC_TAG_PATTERN, html, perl = TRUE)
  toks <- regmatches(html, m)[[1]]
  if (!length(toks)) return(html)

  # Performans: büyük belgelerde token sayısı binlerce olabilir. commonmark
  # çıktısının ezici çoğunluğu güvenli yapısal etiketlerdir (<p>, <li>, <a ...>).
  # Bu yüzden önce VEKTÖREL bir geçişle yalnızca "ilgi gerektiren" token'ları
  # işaretler, ardından sadece onları tekil temizlik fonksiyonundan geçiririz.
  inner <- substring(toks, 2L, nchar(toks) - 1L)
  body0 <- sub("^\\s*/?\\s*", "", inner, perl = TRUE)
  names_v <- tolower(sub("(?s)(^[a-zA-Z][a-zA-Z0-9]*).*$", "\\1", body0, perl = TRUE))
  valid_name <- grepl("^[a-z][a-z0-9]*$", names_v, perl = TRUE)
  is_comment <- startsWith(inner, "!--")
  disallowed <- !valid_name | !(names_v %in% allowed)
  dangerous_attr <- grepl(
    paste0(.ADMIN_DOC_RISKY_ATTR, "|(data\\s*:\\s*text/html)",
           "|((?:href|src|action)\\s*=\\s*[\"']?[^\"'>]*&(?:#|colon;|tab;|newline;))"),
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
