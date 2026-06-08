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

# ------------------------------------------------------------------------------
# Oluşturulan görsel kartı için kanonik güvenli HTML üretir.
# Aynı kart işaretlemesi (filigran + indir/kopyala/yazdır butonları + isteğe
# bağlı açıklama) görsel oluşturma ve sohbet mesajı biçimlendirme yollarında
# tekrarlanıyordu. Tek kaynak burada toplanır; böylece XSS kaçış sınırı tek bir
# yerde korunur.
#
# Güvenlik sözleşmesi:
#   - message_id ve description HTML kaçışına tabi tutulur (XSS koruması).
#   - img_src çağıran tarafça güvenli kabul edilen URL/data-URI'dir ve src
#     içine olduğu gibi yerleştirilir (mevcut davranışla aynıdır).
# ------------------------------------------------------------------------------
mergen_generated_image_card_html <- function(message_id, img_src, description = NULL) {
  description_html <- if (!is.null(description) && nzchar(description)) {
    sprintf(
      '<div class="image-description"><p>%s</p></div>',
      htmltools::htmlEscape(description)
    )
  } else {
    ""
  }

  sprintf(
    '<div class="generated-image-container" data-message-id="%s">
       <div class="image-wrapper">
         <img src="%s" alt="Oluşturulan görsel" class="generated-image" loading="lazy" />
         <div class="image-watermark">MERGEN Bilge</div>
       </div>
       <div class="image-actions">
         <button class="image-action-btn-modern" onclick="window.downloadGeneratedImage(this)" title="İndir">
           <i class="fas fa-download"></i>
         </button>
         <button class="image-action-btn-modern" onclick="window.copyGeneratedImage(this)" title="Kopyala">
           <i class="fas fa-copy"></i>
         </button>
         <button class="image-action-btn-modern" onclick="window.printGeneratedImage(this)" title="Yazdır">
           <i class="fas fa-print"></i>
         </button>
       </div>
       %s
     </div>',
    htmltools::htmlEscape(as.character(message_id)),
    img_src,
    description_html
  )
}