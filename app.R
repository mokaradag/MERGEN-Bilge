# app.R
#
# Bu, Shiny uygulaması için ana giriş noktasıdır.
# Gerekli dosyaları doğru sırayla yükler ve uygulamayı döndürür.
#
# ÖNEMLİ: Bu dosya runApp() çağırmaz — sadece shinyApp() nesnesi döndürür.
# Shiny'nin runApp() / "Run App" butonu bu dosyayı source ederek uygulamayı alır
# ve kendisi başlatır. app.R içinde runApp() çağırmak çift yüklemeye neden olur.

# safe_source() fonksiyonunu burada İLK olarak tanımla, herhangi bir dosya yüklenmeden önce.
# Türkçe yerel ayara sahip bazı Windows sanal makinelerinde source(encoding = "UTF-8")
# çok baytlı karakterleri hâlâ yanlış okuyarak INCOMPLETE_STRING parse hatalarına
# neden olabilir. Bu yöntem dosyayı önce UTF-8 metni olarak okur, sonra metin
# tamponunu parse eder; böylece dosya düzeyindeki encoding hatasını tamamen atlar.
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  source(file, encoding = encoding, local = envir)
}

# 1. Global yapılandırmayı ve tüm yardımcı/modül dosyalarını yükle.
#    Böylece tüm kütüphaneler, fonksiyonlar ve modül tanımları kullanılabilir olur.
#    global.R ayrıca dokümantasyonun açık olması için safe_source() fonksiyonunu
#    (aynı kopya) tekrar tanımlar.
safe_source("global.R", encoding = "UTF-8")

# 2. Kullanıcı arayüzü tanımını yükle.
#    Bu işlem `ui` nesnesini yükler.
safe_source("ui.R", encoding = "UTF-8")

# 3. Sunucu (server) mantığını yükle.
#    Bu işlem `server` fonksiyonunu yükler.
safe_source("server.R", encoding = "UTF-8")

# 4. www/ alt klasörlerini kaynak yolu olarak kaydet.
#    "Run App" butonu runApp(appDir) kullanır ve www/ otomatik sunulur.
#    Ancak Ctrl+Enter ile çalıştırıldığında shinyApp(ui, server) uygulama
#    dizinini bilmez; bu yüzden www/ kaynakları bulunamaz.
#    runApp(".") kullanılamaz çünkü:
#      - app.R'ı tekrar source ederek özyineleme yaratır
#      - normalizePath ile uzun yolları (>260 karakter) çözemez (Windows VM sorunu)
#    Çözüm: Her www/ alt klasörünü kendi adıyla kaydet.
#    Örn: addResourcePath("css", "www/css") → /css/style.css URL'si çalışır.
#    NOT: Mutlak yol kullanılır, böylece Ctrl+Enter ile çalıştırıldığında da
#    kaynak yolları doğru çözümlenir.
www_abs_dir <- normalize_utf8_path("www", mustWork = FALSE)

resolve_resource_root <- function(www_dir) {
  path_has_encoding_issue <- is.na(tryCatch(
    iconv(www_dir, from = "", to = "UTF-8", sub = NA),
    error = function(e) NA_character_
  ))

  if (dir.exists(www_dir) && !isTRUE(path_has_encoding_issue)) {
    return(www_dir)
  }

  # Bazı locale/encoding kombinasyonlarında normalizePath() ile üretilen
  # mutlak yol addResourcePath() içinde "invalid multibyte string" hatasına
  # düşebilir. Bu durumda ASCII bir geçici yol üzerinden www/ dizinine
  # symlink (veya kopya) oluşturarak kaynakları güvenli bir yoldan sun.
  alias_root <- file.path(tempdir(), "mergen_www_alias")
  alias_www <- file.path(alias_root, "www")

  unlink(alias_www, recursive = TRUE, force = TRUE)
  dir.create(alias_root, recursive = TRUE, showWarnings = FALSE)

  linked <- tryCatch(
    file.symlink(from = "www", to = alias_www),
    warning = function(w) FALSE,
    error = function(e) FALSE
  )

  if (!isTRUE(linked)) {
    copied <- tryCatch(
      file.copy(from = "www", to = alias_www, recursive = TRUE),
      warning = function(w) FALSE,
      error = function(e) FALSE
    )
    if (!isTRUE(copied)) {
      return(www_dir)
    }
  }

  normalize_utf8_path(alias_www, mustWork = FALSE)
}

build_sanitized_path_variants <- function(path, mustWork = FALSE) {
  if (is.null(path) || !nzchar(path)) {
    return(character(0))
  }

  raw <- as.character(path)
  native <- tryCatch(enc2native(raw), error = function(e) raw)
  utf8 <- tryCatch(enc2utf8(raw), error = function(e) raw)
  iconv_utf8 <- tryCatch(iconv(raw, from = "", to = "UTF-8", sub = ""), error = function(e) raw)
  iconv_ascii <- tryCatch(iconv(raw, from = "", to = "ASCII//TRANSLIT", sub = ""), error = function(e) raw)

  candidates <- unique(Filter(nzchar, c(
    tryCatch(normalize_utf8_path(raw, mustWork = mustWork), error = function(e) raw),
    tryCatch(normalize_utf8_path(native, mustWork = mustWork), error = function(e) native),
    tryCatch(normalize_utf8_path(utf8, mustWork = mustWork), error = function(e) utf8),
    tryCatch(normalize_utf8_path(iconv_utf8, mustWork = mustWork), error = function(e) iconv_utf8),
    tryCatch(normalize_utf8_path(iconv_ascii, mustWork = mustWork), error = function(e) iconv_ascii),
    native,
    utf8,
    iconv_utf8,
    iconv_ascii
  )))

  candidates
}

register_resource_path <- function(prefix, path, mustWork = FALSE, strict = FALSE) {
  variants <- build_sanitized_path_variants(path, mustWork = mustWork)
  if (!length(variants)) {
    msg <- sprintf("Kaynak yolu üretilemedi (prefix: %s, path: %s)", prefix, path)
    if (isTRUE(strict)) {
      stop(msg)
    }
    warning(msg, call. = FALSE)
    return(invisible(FALSE))
  }

  last_error <- NULL
  for (candidate in variants) {
    candidate_variants <- unique(Filter(nzchar, c(
      candidate,
      tryCatch(enc2native(candidate), error = function(e) candidate),
      tryCatch(enc2utf8(candidate), error = function(e) candidate)
    )))

    ok <- FALSE
    for (candidate_local in candidate_variants) {
      ok <- tryCatch({
        addResourcePath(prefix, candidate_local)
        TRUE
      }, error = function(e) {
        last_error <<- e
        FALSE
      })

      if (isTRUE(ok)) {
        break
      }
    }

    if (isTRUE(ok)) {
      return(invisible(TRUE))
    }
  }

  msg <- sprintf(
    "addResourcePath başarısız (prefix: %s). Denenen sanitize edilmiş yollar: %s. Son hata: %s",
    prefix,
    paste(variants, collapse = " | "),
    if (!is.null(last_error)) conditionMessage(last_error) else "bilinmeyen hata"
  )
  if (isTRUE(strict)) {
    stop(msg)
  }
  warning(msg, call. = FALSE)
  invisible(FALSE)
}

if (!dir.exists(www_abs_dir) && !dir.exists("www")) {
  stop(sprintf("www dizini bulunamadı veya erişilemiyor: %s", www_abs_dir))
}

www_resource_root <- resolve_resource_root(www_abs_dir)

subdirs <- list.dirs(www_resource_root, recursive = FALSE, full.names = FALSE)
for (subdir in subdirs) {
  if (!nzchar(subdir) || is.na(subdir)) {
    warning(sprintf("Geçersiz alt klasör adı algılandı (www: %s).", www_abs_dir), call. = FALSE)
    next
  }

  if (is.na(iconv(subdir, from = "", to = "UTF-8", sub = NA))) {
    warning(sprintf(
      "Alt klasör adı encoding sorunu içeriyor ve atlanıyor: '%s' (www: %s)",
      subdir,
      www_resource_root
    ), call. = FALSE)
    next
  }

  subdir_path <- normalize_utf8_path(file.path(www_resource_root, subdir), mustWork = FALSE)
  register_resource_path(subdir, subdir_path, mustWork = FALSE)
}
# www/ kök dizinindeki dosyalar (mergen_avatar.png, company_logo.png vb.)
# boş prefix ile kaydedilemez. "img" prefix'i ile www/ kök dizinini kaydet.
# Kodda bu dosyalar "img/dosya.png" şeklinde referans edilir.
register_resource_path("img", www_resource_root, mustWork = FALSE)

# 5. Shiny sunucu seçeneklerini ayarla.
#    runApp() artık bu dosya tarafından çağrılmaz; Shiny altyapısı (veya
#    kullanıcının doğrudan runApp() çağrısı) bu seçenekleri kullanır.
options(shiny.host = "0.0.0.0", shiny.port = 8000L)

# 6. Uygulamayı döndür — Shiny bu nesneyi otomatik olarak başlatır.
shinyApp(ui = ui, server = server)
