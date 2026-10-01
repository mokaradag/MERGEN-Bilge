# Destek ekleri yalnız canlı yönetici oturumuna bağlı uç noktadan sunulur.

admin_ha_attachment_urls <- function(session, dosyalar) {
  admin_require_session(session)
  kok <- get0("destek_uploads_dir", inherits = TRUE,
              ifnotfound = file.path(getwd(), "destek_uploads"))
  yollar <- vapply(dosyalar, function(yol) {
    yol <- gsub("\\\\", "/", yol)
    alt <- sub("^/?destek_uploads/", "", yol)
    if (grepl("^(?:/|[A-Za-z]:)", alt)) return("")
    aday <- file.path(kok, alt)
    if (!file.exists(aday) || dir.exists(aday) || !mergen_path_inside_root(aday, kok)) return("")
    normalizePath(aday, winslash = "/", mustWork = TRUE)
  }, character(1))
  jeton <- paste(format(openssl::rand_bytes(32)), collapse = "")
  nesli <- session$userData$kimlik_nesli %||% 0L
  url <- session$registerDataObj("support_attachments",
    list(yollar = yollar, jeton = jeton, nesli = nesli), function(data, req) {
      yetkili <- tryCatch(shiny::isolate({
        admin_require_session(session)
        identical(data$nesli, session$userData$kimlik_nesli %||% 0L) && !session$isClosed()
      }), error = function(e) FALSE)
      sorgu <- shiny::parseQueryString(req$QUERY_STRING %||% "")
      sira <- suppressWarnings(as.integer(sorgu$attachment))
      if (!isTRUE(yetkili) || !identical(sorgu$token, data$jeton) || length(sira) != 1L ||
          is.na(sira) || sira < 1L || sira > length(data$yollar)) {
        return(shiny::httpResponse(403L, "text/plain; charset=UTF-8", "Erişim reddedildi"))
      }
      yol <- data$yollar[sira]
      if (!nzchar(yol) || !file.exists(yol) || !mergen_path_inside_root(yol, kok)) {
        return(shiny::httpResponse(404L, "text/plain; charset=UTF-8", "Dosya bulunamadı"))
      }
      uzanti <- tolower(tools::file_ext(yol))
      tur <- switch(uzanti, png = "image/png", jpg = , jpeg = "image/jpeg",
                    gif = "image/gif", mp4 = "video/mp4", "application/octet-stream")
      shiny::httpResponse(200L, tur, list(file = yol, owned = FALSE),
        headers = list("Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff"))
    })
  setNames(ifelse(nzchar(yollar), paste0(url, "&token=", jeton,
                                       "&attachment=", seq_along(yollar)), ""), dosyalar)
}
