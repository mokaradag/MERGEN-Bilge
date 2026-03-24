# Dosya Yolu: R/module_user_identity.R
# Açıklama: Kullanıcı kimlik bilgilerini yöneten modül.
#            SSO_ENABLED anahtarına göre iki modda çalışır:
#            - SSO aktif (TRUE): Keycloak token'ından kullanıcı bilgisi alır
#            - SSO kapalı (FALSE): Sistem kullanıcı adı + veritabanı sorgusu kullanır

#' Kullanıcı Kimlik Bilgilerini Al
#' @description SSO moduna göre kullanıcı kimlik bilgilerini çözümler.
#'   SSO aktif: sso_claims parametresinden Keycloak bilgilerini kullanır.
#'   SSO kapalı: Sistem kullanıcı adı + DB'den ad bilgisi alır.
#' @param sso_claims SSO kullanıcı bilgileri (SSO aktifken sso_state$user_claims)
#' @return Liste: username, first_name, full_name, sicil ve diğer SSO alanları
resolveUserIdentity <- function(sso_claims = NULL) {

  # ===========================================================================
  # MOD 1: SSO AKTİF (Keycloak)
  # ===========================================================================
  if (isTRUE(SSO_ENABLED) && !is.null(sso_claims)) {

    username   <- ensure_utf8(fixTurkishEncoding(sso_claims$username %||% ""))
    first_name <- ensure_utf8(fixTurkishEncoding(sso_claims$first_name %||% ""))
    full_name  <- ensure_utf8(fixTurkishEncoding(sso_claims$full_name %||% ""))
    sicil      <- ensure_utf8(sso_claims$sicil)

    # İlk isim boşsa tam isimden çıkar
    if (!nzchar(first_name) && nzchar(full_name)) {
      first_name <- extractFirstName(full_name)
    }

    # Tam isim boşsa kullanıcı adını kullan
    if (!nzchar(full_name)) {
      full_name <- capitalizeFirst(username)
    }

    # İlk ismi düzelt (baş harfi büyük)
    if (nzchar(first_name)) {
      first_name <- capitalizeFirst(first_name)
    }

    log_info("SSO kimlik çözümleme: kullanıcı={username}, ad={full_name}, sicil={sicil %||% 'YOK'}")

    return(list(
      username        = username,
      first_name      = first_name,
      full_name       = full_name,
      sicil           = sicil,
      email           = ensure_utf8(sso_claims$email),
      last_name       = ensure_utf8(fixTurkishEncoding(sso_claims$last_name %||% "")),
      sektor          = ensure_utf8(fixTurkishEncoding(sso_claims$sektor %||% "")),
      department      = ensure_utf8(fixTurkishEncoding(sso_claims$department %||% "")),
      mudurluk        = ensure_utf8(fixTurkishEncoding(sso_claims$mudurluk %||% "")),
      masraf_yeri_kodu = ensure_utf8(sso_claims$masraf_yeri_kodu),
      auth_level      = sso_claims$yetki %||% "USER",
      keycloak_sid    = sso_claims$keycloak_sid,
      keycloak_sub    = sso_claims$keycloak_sub,
      auth_source     = "keycloak"
    ))
  }

  # ===========================================================================
  # MOD 2: YEREL GELİŞTİRME (SSO kapalı)
  # ===========================================================================
  system_username <- Sys.info()["user"]

  # Veritabanından kullanıcı tam adını al
  db_result <- tryCatch({
    conn_info <- get_connection()
    conn <- conn_info$conn
    on.exit(release_connection(conn_info))

    # DC01_user_base'den tam adı al
    query <- "SELECT KaynakAdi FROM DC01_user_base WHERE KullaniciAdi = ?"
    result <- dbGetQuery(conn, query, params = list(system_username))

    if (nrow(result) > 0 && nzchar(result$KaynakAdi[1])) {
      result$KaynakAdi[1]
    } else {
      # DB'de kayıt yoksa MB_Users tablosundan dene
      query2 <- "SELECT KaynakAdi FROM MB_Users WHERE KullaniciAdi = ?"
      result2 <- dbGetQuery(conn, query2, params = list(system_username))
      if (nrow(result2) > 0 && nzchar(result2$KaynakAdi[1])) {
        result2$KaynakAdi[1]
      } else {
        NULL
      }
    }
  }, error = function(e) {
    log_warn("Kullanıcı adı DB'den alınamadı: {e$message}")
    NULL
  })

  # Tam ad ve ilk isim belirle (DB'den gelen bozuk Türkçe karakterleri düzelt)
  if (!is.null(db_result) && nzchar(db_result)) {
    full_name  <- fixTurkishEncoding(db_result)
    first_name <- extractFirstName(full_name)
  } else {
    full_name  <- capitalizeFirst(system_username)
    first_name <- full_name
  }

  list(
    username        = system_username,
    first_name      = first_name,
    full_name       = full_name,
    sicil           = NULL,
    email           = NULL,
    last_name       = NULL,
    sektor          = NULL,
    department      = NULL,
    mudurluk        = NULL,
    masraf_yeri_kodu = NULL,
    auth_level      = Sys.getenv("MERGEN_AUTH_LEVEL", "ADMIN"),
    keycloak_sid    = NULL,
    keycloak_sub    = NULL,
    auth_source     = "local"
  )
}


#' Türkçe Karakter Encoding Düzeltme
#' @description Keycloak'tan gelen bozuk UTF-8 Türkçe karakterleri düzeltir.
#'   Örnek: "KARADAĞ" bozuk gelirse düzeltir.
#' @param text Düzeltilecek metin
#' @return Düzeltilmiş metin
fixTurkishEncoding <- function(text) {
  if (is.null(text) || !nzchar(text)) return(text)

  raw_text <- as.character(text)
  result <- raw_text

  # Her durumda deterministik bir normalize uygula:
  # 1) UTF-8'e güvenli dönüşüm dene
  # 2) Başarısızsa karakter kaybı yerine transliterasyon + temizleme ile öngörülebilir çıktı üret
  normalize_fallback <- function(x) {
    x_utf8 <- tryCatch(enc2utf8(x), error = function(e) x)
    x_clean <- tryCatch(iconv(x_utf8, from = "", to = "UTF-8", sub = ""), error = function(e) NA_character_)
    if (!is.na(x_clean) && nzchar(x_clean)) {
      return(x_clean)
    }

    x_ascii <- tryCatch(iconv(x_utf8, from = "", to = "ASCII//TRANSLIT", sub = ""), error = function(e) NA_character_)
    if (is.na(x_ascii) || !nzchar(x_ascii)) {
      x_ascii <- gsub("[^[:print:]]+", "", x_utf8, perl = TRUE)
    }
    trimws(x_ascii)
  }

  result <- normalize_fallback(result)

  # Çift-encoding (mojibake) onarım adayları
  candidates <- unique(c(
    result,
    tryCatch(iconv(result, from = "UTF-8", to = "latin1", sub = "byte"), error = function(e) NA_character_),
    tryCatch(iconv(result, from = "UTF-8", to = "windows-1254", sub = "byte"), error = function(e) NA_character_),
    tryCatch(iconv(result, from = "latin1", to = "UTF-8", sub = ""), error = function(e) NA_character_),
    tryCatch(iconv(result, from = "windows-1254", to = "UTF-8", sub = ""), error = function(e) NA_character_)
  ))
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]

  # Bilinen mojibake + CP1254/Latin-1 tekil/truncated desen onarımı
  apply_replacements <- function(x) {
    replacements <- list(
      c("Ã‡", "Ç"), c("Ãœ", "Ü"), c("Ã–", "Ö"), c("Äž", "Ğ"), c("Ä°", "İ"), c("Åž", "Ş"),
      c("Ã§", "ç"), c("Ã¼", "ü"), c("Ã¶", "ö"), c("ÄŸ", "ğ"), c("Ä±", "ı"), c("ÅŸ", "ş"),
      c("Ä‡", "Ç"), c("ÄŸ", "ğ"), c("Äž", "Ğ"), c("Ä±", "ı"), c("Ä°", "İ"), c("ÅŸ", "ş"), c("Åž", "Ş"),
      # Tekil/truncated bayt kaynaklı tipik kalıntılar
      c("Ð", "Ğ"), c("ð", "ğ"), c("Þ", "Ş"), c("þ", "ş"),
      c("Ý", "İ"), c("ý", "ı"), c("¿", " "), c("�", "")
    )
    out <- x
    for (rep in replacements) {
      out <- gsub(rep[1], rep[2], out, fixed = TRUE)
    }
    out
  }

  candidates <- unique(vapply(candidates, apply_replacements, character(1), USE.NAMES = FALSE))
  candidates <- unique(vapply(candidates, normalize_fallback, character(1), USE.NAMES = FALSE))

  # En iyi adayı seç: Türkçe karakter içeren ve daha okunabilir adayı tercih et
  score_candidate <- function(x) {
    has_noise <- grepl("[ÃÄÅÐÞÝ�]", x, perl = TRUE)
    tr_hits <- gregexpr("[ÇĞİÖŞÜçğıöşü]", x, perl = TRUE)[[1]]
    tr_count <- ifelse(identical(tr_hits[1], -1L), 0L, length(tr_hits))
    printable_hits <- gregexpr("[[:print:]]", x, perl = TRUE)[[1]]
    printable <- ifelse(identical(printable_hits[1], -1L), 0L, length(printable_hits))
    penalty <- ifelse(has_noise, 10, 0)
    tr_count * 100 + printable - penalty
  }

  if (length(candidates) > 0) {
    scores <- vapply(candidates, score_candidate, numeric(1))
    result <- candidates[[which.max(scores)]]
  }

  # Son normalize: geçersiz UTF-8'i deterministik şekilde temizle
  result <- normalize_fallback(result)
  Encoding(result) <- "UTF-8"
  result
}


#' İlk İsmi Çıkar
#' @description Tam isimden ilk ismi çıkarır ve baş harfi büyütür.
#' @param full_name Tam isim
#' @return İlk isim (baş harfi büyük, geri kalanı küçük)
extractFirstName <- function(full_name) {
  if (is.null(full_name) || !nzchar(full_name)) return("")

  parts <- strsplit(trimws(full_name), "\\s+")[[1]]
  first <- parts[1]
  capitalizeFirst(first)
}


#' Baş Harfi Büyült
#' @description Metnin baş harfini büyük, geri kalanını küçük yapar.
#' @param text Metin
#' @return Baş harfi büyük metin
capitalizeFirst <- function(text) {
  if (is.null(text) || !nzchar(text)) return("")

  text <- trimws(text)
  first_char <- substring(text, 1, 1)
  rest <- substring(text, 2)

  paste0(
    toupper(first_char),
    tolower(rest)
  )
}
