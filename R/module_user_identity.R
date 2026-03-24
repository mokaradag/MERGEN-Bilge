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

  result <- text

  # Encoding etiketini açıkça UTF-8 olarak ayarla
  Encoding(result) <- "UTF-8"

  # ÖNCELİKLİ YÖNTEMİ: iconv ile çift-encoding onarımı.
  # Keycloak veya DB'den gelen bozuk Türkçe genellikle şu şekilde oluşur:
  # Orijinal UTF-8 baytları Latin-1/Windows-1252 olarak yorumlanır ve tekrar UTF-8'e kodlanır.
  # Örnek: "Ğ" (C4 9E) → Latin-1 okuma → "Ä" + kontrol karakteri → tekrar UTF-8 → bozuk metin.
  # Çözüm: UTF-8 → Latin-1 (baytları geri al) → UTF-8 olarak işaretle.
  if (grepl("[\u00c3\u00c4\u00c5][\u0080-\u00bf]", result, perl = TRUE)) {
    tryCatch({
      repaired <- iconv(result, from = "UTF-8", to = "latin1", sub = "byte")
      if (!is.na(repaired)) {
        Encoding(repaired) <- "UTF-8"
        if (validUTF8(repaired)) {
          result <- repaired
        }
      }
    }, error = function(e) {
      # Dönüşüm başarısızsa, karakter bazlı değiştirme yöntemine geç
    })
  }

  # YEDEK YÖNTEM: Hâlâ bozuk karakterler varsa bilinen eşlemelerle düzelt.
  # (iconv yöntemi bazı özel durumlarda başarısız olabilir)
  # Not: Üretim ortamında "ORÄ‡UN" gibi CP1252/CP1254 türevi bozulmalar görülebilir.
  if (grepl("[ÃÄÅ]", result, perl = TRUE)) {
    replacements <- list(
      # Yaygın UTF-8 mojibake eşleşmeleri
      c("Ã‡", "Ç"), c("Ãœ", "Ü"), c("Ã–", "Ö"), c("Äž", "Ğ"), c("Ä°", "İ"), c("Åž", "Ş"),
      c("Ã§", "ç"), c("Ã¼", "ü"), c("Ã¶", "ö"), c("ÄŸ", "ğ"), c("Ä±", "ı"), c("ÅŸ", "ş"),
      # CP1252/CP1254 kaynaklı tipik bozulmalar
      c("Ä‡", "Ç"), c("ÄŸ", "ğ"), c("Äž", "Ğ"), c("Ä±", "ı"), c("Ä°", "İ"), c("ÅŸ", "ş"), c("Åž", "Ş")
    )
    for (rep in replacements) {
      result <- gsub(rep[1], rep[2], result, fixed = TRUE)
    }
  }

  # Son kontrol: hâlâ geçersiz UTF-8 baytları varsa temizle
  if (!validUTF8(result)) {
    tryCatch({
      clean <- iconv(text, from = "latin1", to = "UTF-8")
      if (!is.na(clean) && nzchar(clean)) result <- clean
    }, error = function(e) {
      log_warn("Encoding düzeltme başarısız: {e$message}")
    })
  }

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
