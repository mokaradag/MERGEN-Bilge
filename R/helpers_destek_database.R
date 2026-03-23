# Dosya Yolu: R/helpers_destek_database.R
# Açıklama: Destek sayfası veritabanı yardımcı fonksiyonları.
#            MB_Destek_Geri_Bildirim ve MB_Destek_Hata_Bildir tablolarına
#            kayıt ekleme, listeleme ve silme işlemlerini yönetir.

# ==============================================================================
# GERİ BİLDİRİM KAYDETME
# ==============================================================================

#' Geri bildirim formunu veritabanına kaydet
#' @param user_id Kullanıcı kimliği (MB_Users.UserID)
#' @param memnuniyet Memnuniyet puanı (1-5)
#' @param nps_puan NPS puanı (0-10, opsiyonel)
#' @param etiketler Seçilen etiketler (virgülle ayrılmış metin)
#' @param en_cok_sevilen "En çok neyi sevdiniz?" yanıtı
#' @param gelistirme "Neyi geliştirebiliriz?" yanıtı
#' @param iletisim_izni İletişim izni (TRUE/FALSE)
#' @return Eklenen kaydın ID'si
destek_geri_bildirim_kaydet <- function(user_id, memnuniyet, nps_puan = NULL,
                                         etiketler = NULL, en_cok_sevilen = NULL,
                                         gelistirme = NULL, iletisim_izni = FALSE) {
  stopifnot(!is.null(user_id), !is.null(memnuniyet))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # NULL değerleri SQL NULL olarak işle
  # Türkçe karakterlerin doğru kaydedilmesi için UTF-8 normalleştirmesi
  safe_nps <- if (is.null(nps_puan) || is.na(nps_puan)) NA_integer_ else as.integer(nps_puan)
  safe_etiketler <- if (is.null(etiketler) || !nzchar(etiketler)) NA_character_ else ensure_utf8(as.character(etiketler))
  safe_sevilen <- if (is.null(en_cok_sevilen) || !nzchar(en_cok_sevilen)) NA_character_ else ensure_utf8(as.character(en_cok_sevilen))
  safe_gelistirme <- if (is.null(gelistirme) || !nzchar(gelistirme)) NA_character_ else ensure_utf8(as.character(gelistirme))
  safe_iletisim <- if (isTRUE(iletisim_izni)) 1L else 0L

  query <- "
    INSERT INTO MB_Destek_Geri_Bildirim
      (UserID, Memnuniyet, NPS_Puan, Etiketler, EnCokSevilen, Gelistirme, IletisimIzni, OlusturmaTarihi)
    OUTPUT INSERTED.GeriBildirimID AS GeriBildirimID
    VALUES (?, ?, ?, ?, ?, ?, ?, GETDATE())
  "

  res <- DBI::dbGetQuery(conn, query, params = list(
    as.integer(user_id),
    as.integer(memnuniyet),
    safe_nps,
    safe_etiketler,
    safe_sevilen,
    safe_gelistirme,
    safe_iletisim
  ))

  if (nrow(res) == 0) stop("Geri bildirim kaydedilemedi.")
  return(as.integer(res$GeriBildirimID[1]))
}

# ==============================================================================
# HATA BİLDİRİMİ KAYDETME
# ==============================================================================

#' Hata bildirim formunu veritabanına kaydet
#' @param user_id Kullanıcı kimliği (MB_Users.UserID)
#' @param konular Hata konuları (virgülle ayrılmış metin)
#' @param kategoriler Seçilen kategoriler (virgülle ayrılmış metin)
#' @param oncelik Öncelik seviyesi (dusuk/orta/yuksek/kritik)
#' @param aciklama Detaylı açıklama
#' @param ek_dosya_yollari Eklenen dosyaların yolları (virgülle ayrılmış metin, opsiyonel)
#' @return Eklenen kaydın ID'si
destek_hata_bildir_kaydet <- function(user_id, konular, kategoriler, oncelik = "orta",
                                       aciklama, ek_dosya_yollari = NULL) {
  stopifnot(!is.null(user_id), !is.null(konular), !is.null(kategoriler), !is.null(aciklama))

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  # Türkçe karakterlerin doğru kaydedilmesi için UTF-8 normalleştirmesi
  safe_ek_dosyalar <- if (is.null(ek_dosya_yollari) || !nzchar(ek_dosya_yollari)) NA_character_ else ensure_utf8(as.character(ek_dosya_yollari))
  safe_oncelik <- if (is.null(oncelik) || !nzchar(oncelik)) "orta" else ensure_utf8(as.character(oncelik))
  konular <- ensure_utf8(as.character(konular))
  kategoriler <- ensure_utf8(as.character(kategoriler))
  aciklama <- ensure_utf8(as.character(aciklama))

  query <- "
    INSERT INTO MB_Destek_Hata_Bildir
      (UserID, Konular, Kategoriler, Oncelik, Aciklama, EkDosyaYollari, Durum, OlusturmaTarihi)
    OUTPUT INSERTED.HataBildirimID AS HataBildirimID
    VALUES (?, ?, ?, ?, ?, ?, 'acik', GETDATE())
  "

  res <- DBI::dbGetQuery(conn, query, params = list(
    as.integer(user_id),
    as.character(konular),
    as.character(kategoriler),
    safe_oncelik,
    as.character(aciklama),
    safe_ek_dosyalar
  ))

  if (nrow(res) == 0) stop("Hata bildirimi kaydedilemedi.")
  return(as.integer(res$HataBildirimID[1]))
}

# ==============================================================================
# GERİ BİLDİRİM LİSTELEME (Yönetici paneli için)
# ==============================================================================

#' Tüm geri bildirimleri listele
#' @param limit Döndürülecek kayıt sayısı
#' @return data.frame
destek_geri_bildirim_listele <- function(limit = 100) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- sprintf("
    SELECT TOP %d
      gb.GeriBildirimID, gb.UserID, u.KaynakAdi AS KullaniciAdi,
      gb.Memnuniyet, gb.NPS_Puan, gb.Etiketler,
      gb.EnCokSevilen, gb.Gelistirme, gb.IletisimIzni,
      gb.OlusturmaTarihi
    FROM MB_Destek_Geri_Bildirim gb
    LEFT JOIN MB_Users u ON gb.UserID = u.UserID
    ORDER BY gb.OlusturmaTarihi DESC
  ", as.integer(limit))

  DBI::dbGetQuery(conn, query)
}

# ==============================================================================
# HATA BİLDİRİMLERİ LİSTELEME (Yönetici paneli için)
# ==============================================================================

#' Tüm hata bildirimlerini listele
#' @param limit Döndürülecek kayıt sayısı
#' @return data.frame
destek_hata_bildirim_listele <- function(limit = 100) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- sprintf("
    SELECT TOP %d
      hb.HataBildirimID, hb.UserID, u.KaynakAdi AS KullaniciAdi,
      hb.Konular, hb.Kategoriler, hb.Oncelik, hb.Aciklama,
      hb.EkDosyaYollari, hb.Durum, hb.OlusturmaTarihi
    FROM MB_Destek_Hata_Bildir hb
    LEFT JOIN MB_Users u ON hb.UserID = u.UserID
    ORDER BY hb.OlusturmaTarihi DESC
  ", as.integer(limit))

  DBI::dbGetQuery(conn, query)
}

# ==============================================================================
# KULLANICI BAZLI GERİ BİLDİRİM GEÇMİŞİ
# ==============================================================================

#' Belirli bir kullanıcının geri bildirim geçmişini getir
#' @param user_id Kullanıcı kimliği
#' @return data.frame
destek_kullanici_geri_bildirim <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    SELECT GeriBildirimID, Memnuniyet, NPS_Puan, Etiketler,
           EnCokSevilen, Gelistirme, IletisimIzni, OlusturmaTarihi
    FROM MB_Destek_Geri_Bildirim
    WHERE UserID = ?
    ORDER BY OlusturmaTarihi DESC
  "

  DBI::dbGetQuery(conn, query, params = list(as.integer(user_id)))
}

# ==============================================================================
# HATA BİLDİRİMİ DURUM GÜNCELLEME (Yönetici paneli için)
# ==============================================================================

#' Hata bildiriminin durumunu güncelle
#' @param bildirim_id Hata bildirim ID
#' @param yeni_durum Yeni durum değeri (acik, inceleme, cozuldu, kapandi, reddedildi)
#' @return Güncellenen satır sayısı
destek_hata_durum_guncelle <- function(bildirim_id, yeni_durum) {
  stopifnot(!is.null(bildirim_id), !is.null(yeni_durum))

  gecerli_durumlar <- c("acik", "inceleme", "cozuldu", "kapandi", "reddedildi")
  if (!yeni_durum %in% gecerli_durumlar) {
    stop(paste0("Geçersiz durum değeri: ", yeni_durum))
  }

  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "UPDATE MB_Destek_Hata_Bildir SET Durum = ? WHERE HataBildirimID = ?"

  DBI::dbExecute(conn, query, params = list(
    as.character(yeni_durum),
    as.integer(bildirim_id)
  ))
}

#' Belirli bir kullanıcının hata bildirim geçmişini getir
#' @param user_id Kullanıcı kimliği
#' @return data.frame
destek_kullanici_hata_bildirim <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "
    SELECT HataBildirimID, Konular, Kategoriler, Oncelik,
           Aciklama, EkDosyaYollari, Durum, OlusturmaTarihi
    FROM MB_Destek_Hata_Bildir
    WHERE UserID = ?
    ORDER BY OlusturmaTarihi DESC
  "

  DBI::dbGetQuery(conn, query, params = list(as.integer(user_id)))
}