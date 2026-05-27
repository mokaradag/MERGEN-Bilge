# ==============================================================================
# Dosya Yolu: R/helpers_markdown_safety.R
# Açıklama: Markdown -> HTML dönüşümünde ham HTML/script geçişini engelleyen
#           küçük güvenlik yardımcıları.
# ==============================================================================

mergen_escape_raw_html_for_markdown <- function(text) {
  if (is.null(text) || length(text) == 0L || is.na(text[1])) {
    return("")
  }

  safe_text <- enc2utf8(as.character(text[1]))
  safe_text <- gsub("<", "&lt;", safe_text, fixed = TRUE)
  safe_text <- gsub(">", "&gt;", safe_text, fixed = TRUE)
  safe_text
}

mergen_sanitize_markdown_links <- function(html) {
  if (is.null(html) || length(html) == 0L || is.na(html[1])) {
    return("")
  }

  safe_html <- enc2utf8(as.character(html[1]))

  # Markdown linkleri üzerinden javascript: protokolü üretilirse tıklanamaz hale getir.
  safe_html <- gsub(
    "href\\s*=\\s*\"\\s*javascript:[^\"]*\"",
    "href=\"#\" data-mergen-unsafe-href=\"removed\"",
    safe_html,
    ignore.case = TRUE,
    perl = TRUE
  )

  safe_html <- gsub(
    "href\\s*=\\s*'\\s*javascript:[^']*'",
    "href=\"#\" data-mergen-unsafe-href=\"removed\"",
    safe_html,
    ignore.case = TRUE,
    perl = TRUE
  )

  safe_html
}

render_safe_markdown_html <- function(content,
                                      hardbreaks = TRUE,
                                      extensions = c("strikethrough", "table")) {
  safe_input <- mergen_escape_raw_html_for_markdown(content)

  html <- commonmark::markdown_html(
    safe_input,
    hardbreaks = hardbreaks,
    extensions = extensions
  )

  mergen_sanitize_markdown_links(html)
}