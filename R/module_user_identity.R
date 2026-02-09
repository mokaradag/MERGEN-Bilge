# Dosya Yolu: R/module_user_identity.R
# Açıklama: Kullanıcı kimlik bilgilerini yöneten modül.
# Keycloak entegrasyonuna hazır yapı. Şu an sistem kullanıcı adı ve
# veritabanından alınan bilgilerle çalışır. Keycloak aktif olduğunda
# sadece bu dosya güncellenecek.

#' Kullanıcı Kimlik Bilgilerini Al
#' @description Keycloak entegrasyonuna hazır kullanıcı kimlik çözümleyici.
#'   Şu an: sistem kullanıcı adı + DB'den ad bilgisi.
#'   Keycloak sonrası: preferred_username, given_name, name, sicil alanları kullanılacak.
#' @return Liste: username, first_name, full_name, sicil
resolveUserIdentity <- function() {
  
  # ---------------------------------------------------------------
  # KEYCLOAK ENTEGRASYONU İÇİN HAZIRLIK
  #
  # Keycloak aktif olduğunda aşağıdaki blok açılacak:
  #
  # keycloak_claims <- getKeycloakClaims(session)
  # raw_given_name  <- keycloak_claims$given_name
  # raw_full_name   <- keycloak_claims$name
  # username        <- keycloak_claims$preferred_username
  # sicil           <- keycloak_claims$sicil
  #
  # first_name <- fixTurkishEncoding(raw_given_name)
  # first_name <- extractFirstName(first_name)
  # full_name  <- fixTurkishEncoding(raw_full_name)
  # ---------------------------------------------------------------
  
  # --- Mevcut yöntem: Sistem kullanıcı adından bilgi al ---
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
    log_warn("Kullanici adi DB'den alinamadi: {e$message}")
    NULL
  })
  
  # Tam ad ve ilk isim belirle
  if (!is.null(db_result) && nzchar(db_result)) {
    full_name  <- db_result
    first_name <- extractFirstName(full_name)
  } else {
    full_name  <- capitalizeFirst(system_username)
    first_name <- full_name
  }
  
  list(
    username   = system_username,
    first_name = first_name,
    full_name  = full_name,
    sicil      = NULL  # Keycloak sonrası doldurulacak
  )
}


#' Türkçe Karakter Encoding Düzeltme
#' @description Keycloak'tan gelen bozuk UTF-8 Türkçe karakterleri düzeltir.
#'   Örnek: "KARADAÃ\u0087" -> "KARADAĞ"
#' @param text Düzeltilecek metin
#' @return Düzeltilmiş metin
fixTurkishEncoding <- function(text) {
  if (is.null(text) || !nzchar(text)) return(text)
  
  # Yaygın bozuk UTF-8 -> doğru Türkçe karakter eşlemeleri
  replacements <- list(
    c("\u00c3\u0087",       "\u00c7"),   # Ç
    c("\u00c3\u009c",       "\u00dc"),   # Ü
    c("\u00c3\u0096",       "\u00d6"),   # Ö
    c("\u00c4\u009e",       "\u011e"),   # Ğ
    c("\u00c4\u00b0",       "\u0130"),   # İ
    c("\u00c5\u009e",       "\u015e"),   # Ş
    c("\u00c3\u00a7",       "\u00e7"),   # ç
    c("\u00c3\u00bc",       "\u00fc"),   # ü
    c("\u00c3\u00b6",       "\u00f6"),   # ö
    c("\u00c4\u009f",       "\u011f"),   # ğ
    c("\u00c4\u00b1",       "\u0131"),   # ı
    c("\u00c5\u009f",       "\u015f")    # ş
  )
  
  result <- text
  for (rep in replacements) {
    result <- gsub(rep[1], rep[2], result, fixed = TRUE)
  }
  
  # Hâlâ bozuk karakterler varsa latin1 -> UTF-8 dönüşümü dene
  if (grepl("[\u00c3\u00c4\u00c5]", result)) {
    tryCatch({
      raw_bytes <- charToRaw(result)
      result <- rawToChar(raw_bytes)
      Encoding(result) <- "UTF-8"
      if (!validUTF8(result)) {
        result <- iconv(text, from = "latin1", to = "UTF-8")
      }
    }, error = function(e) {
      log_warn("Encoding duzeltme basarisiz: {e$message}")
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