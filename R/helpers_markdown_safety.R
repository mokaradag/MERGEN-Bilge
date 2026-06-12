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

  # Markdown linkleri üzerinden tehlikeli protokoller (javascript:, vbscript:,
  # data:text/html) üretilirse tıklanamaz hale getir. Bu protokoller tarayıcıda
  # betik yürütebilir; bu nedenle href "#" ile etkisizleştirilir. Güvenli
  # data:image/... (görsel) ve normal http/https/göreli linkler etkilenmez.
  tehlikeli_protokol <- "(?:(?:javascript|vbscript):|data:text/html)"

  safe_html <- gsub(
    sprintf("href\\s*=\\s*\"\\s*%s[^\"]*\"", tehlikeli_protokol),
    "href=\"#\" data-mergen-unsafe-href=\"removed\"",
    safe_html,
    ignore.case = TRUE,
    perl = TRUE
  )

  safe_html <- gsub(
    sprintf("href\\s*=\\s*'\\s*%s[^']*'", tehlikeli_protokol),
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

# ------------------------------------------------------------------------------
# Görseli oturum-kapsamlı (session-scoped) bir URL üzerinden sunar.
#
# Eski yol her görseli satır içi base64 data-URI olarak gömüyordu; bu, uzun
# görsel söyleşilerinde çok megabaytlık metni Shiny websocket'i üzerinden
# göndererek belirgin gecikme yaratıyordu. Bunun yerine dosya, session$registerDataObj
# ile yalnızca o oturuma ait (tahmin edilemez, kullanıcı izolasyonunu koruyan)
# bir URL üzerinden sunulur; tarayıcı görseli doğrudan/tembel ve paralel çeker.
#
# Aynı oturumda aynı dosya için tek bir kayıt yapılır (URL yeniden kullanılır),
# böylece tekrarlı render'larda handler birikmesi önlenir. Kayıtlı filtre dosyayı
# her istekte taze okuduğu için dosya içeriği değişse bile doğru bayt sunulur.
# ------------------------------------------------------------------------------
.mergen_register_image_data_obj <- function(session, local_path) {
  norm_path <- normalizePath(local_path, winslash = "/", mustWork = FALSE)

  cache <- session$userData$mergen_image_url_cache
  if (is.null(cache)) cache <- list()
  if (!is.null(cache[[norm_path]]) && nzchar(cache[[norm_path]])) {
    return(cache[[norm_path]])
  }

  ext <- tolower(tools::file_ext(local_path))
  content_type <- switch(
    ext,
    "jpg" = , "jpeg" = "image/jpeg",
    "png"  = "image/png",
    "gif"  = "image/gif",
    "webp" = "image/webp",
    "bmp"  = "image/bmp",
    "svg"  = "image/svg+xml",
    "image/png"
  )

  obj_name <- paste0("mergen_img_", gsub("[^a-zA-Z0-9]", "_", basename(local_path)))

  url <- session$registerDataObj(
    name = obj_name,
    data = list(path = norm_path, ctype = content_type),
    filterFunc = function(data, req) {
      fpath <- data$path
      if (!file.exists(fpath)) {
        return(shiny::httpResponse(
          status = 404L,
          content_type = "text/plain; charset=UTF-8",
          content = "Gorsel bulunamadi"
        ))
      }
      raw_bytes <- readBin(fpath, "raw", file.info(fpath)$size)
      shiny::httpResponse(
        status = 200L,
        content_type = data$ctype,
        content = raw_bytes
      )
    }
  )

  cache[[norm_path]] <- url
  session$userData$mergen_image_url_cache <- cache
  url
}

# Görsel için sunulabilir bir kaynak döndürür. Aktif bir Shiny oturumu varsa
# session-scoped URL üretir; oturum yoksa (test/oturumsuz bağlam) veya kayıt
# başarısız olursa eski base64 data-URI davranışına güvenli biçimde düşer.
mergen_serve_image_data_url <- function(local_path,
                                        session = shiny::getDefaultReactiveDomain()) {
  if (is.null(local_path) || length(local_path) != 1L || !nzchar(local_path) ||
      !file.exists(local_path)) {
    return(NULL)
  }

  if (!is.null(session) && !is.null(session$registerDataObj)) {
    served <- tryCatch(
      .mergen_register_image_data_obj(session, local_path),
      error = function(e) NULL
    )
    if (!is.null(served) && nzchar(served)) {
      return(served)
    }
  }

  # base64 yedeği (oturumsuz/hata durumu) — eski davranışı korur.
  tryCatch(
    paste0("data:image/png;base64,", base64enc::base64encode(local_path)),
    error = function(e) NULL
  )
}