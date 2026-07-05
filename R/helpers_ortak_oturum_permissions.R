# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_permissions.R
# Açıklama: Ortak Oturumlar (işbirlikçi çalışma odaları) için SAF karar
#           yardımcıları: Türkçe iş kuralı sabitleri, rol/yetki matrisi,
#           içerik erişimi, canlı durum sınıflandırması, mesaj yönlendirme
#           planı ve liste görünürlük kuralları.
#
# Sözleşmeler:
#   * Bu dosya SAF kalır: Shiny, reactive, DB, ağ, dosya sistemi yok.
#   * DB'de saklanan iş kuralı değerleri TÜRKÇE'dir; İngilizce durum değeri
#     (owner/pending/completed vb.) üretilmez ve kabul edilmez.
#   * Yetki kararları UI gizlemesine ek olarak sunucu tarafında da bu
#     yardımcılarla doğrulanır (fail-closed: bilinmeyen rol = yetki yok).
# ==============================================================================

# --- Türkçe iş kuralı sabitleri ------------------------------------------------

ortak_oturum_kaynak_turleri <- function() {
  c("NormalSohbet", "BilgeYolaç")
}

ortak_oturum_durumlari <- function() {
  c("Aktif", "Arşivlendi", "Kapandı")
}

ortak_oturum_rolleri <- function() {
  c("Sahip", "OturumYöneticisi", "Katılımcı", "İzleyici")
}

ortak_katilim_durumlari <- function() {
  c("DavetEdildi", "Katıldı", "Reddetti", "Çıkarıldı", "Ayrıldı")
}

ortak_gorunum_durumlari <- function() {
  c("Görünüyor", "KullanıcıArşivledi", "Ayrıldı")
}

ortak_mesaj_turleri <- function() {
  c("OdaMesajı", "YapayZekaSorusu", "YapayZekaYanıtı",
    "SistemMesajı", "BelgeBildirimi")
}

ortak_mesaj_hedefleri <- function() {
  c("Katılımcılar", "YapayZeka")
}

ortak_davet_durumlari <- function() {
  c("Bekliyor", "Katıldı", "Reddetti", "SüresiDoldu", "İptalEdildi")
}

ortak_davet_yontemleri <- function() {
  c("Mergenİçi", "Eposta", "MergenİçiVeEposta")
}

ortak_canli_durumlar <- function() {
  c("Çevrimİçi", "Boşta", "ÇevrimDışı")
}

ortak_dosya_kopya_durumlari <- function() {
  c("Bekliyor", "Kopyalandı", "Reddetti", "Hata")
}

# Ortak oturum oluşturulurken kullanıcıya sunulan paylaşım başlangıç tipleri.
# Varsayılan her zaman en güvenli seçenektir: mevcut kişisel geçmiş gizli kalır.
ortak_paylasim_baslangic_tipleri <- function(kaynak_turu = "NormalSohbet") {
  if (identical(kaynak_turu, "BilgeYolaç")) {
    return(c(
      "SadeceYeniÇalıştırmalar",
      "Salt-OkunurÖzetAktarımı",
      "TümGeçmişVeBelgeKopyası"
    ))
  }

  c(
    "SadeceBundanSonrası",
    "GeçmişKopyasıAktarıldı",
    "BoşOrtakOturum"
  )
}

# --- Rol / yetki matrisi ---------------------------------------------------------

# Rol başına yetki listesi. Bilinmeyen rol her yetkide FALSE döner (fail-closed).
ortak_rol_yetkileri <- function(rol) {
  roller <- ortak_oturum_rolleri()
  sahip <- roller[1]
  yonetici <- roller[2]
  katilimci <- roller[3]
  izleyici <- roller[4]

  temel <- list(
    oku = FALSE,
    oda_yaz = FALSE,
    yapay_zeka_sor = FALSE,
    davet_et = FALSE,
    katilimci_yonet = FALSE,
    rol_degistir = FALSE,
    oturum_kapat = FALSE,
    belge_kopyala = FALSE
  )

  if (!is.character(rol) || length(rol) != 1L || is.na(rol)) {
    return(temel)
  }

  if (identical(rol, sahip)) {
    return(list(
      oku = TRUE, oda_yaz = TRUE, yapay_zeka_sor = TRUE, davet_et = TRUE,
      katilimci_yonet = TRUE, rol_degistir = TRUE, oturum_kapat = TRUE,
      belge_kopyala = TRUE
    ))
  }

  if (identical(rol, yonetici)) {
    return(list(
      oku = TRUE, oda_yaz = TRUE, yapay_zeka_sor = TRUE, davet_et = TRUE,
      katilimci_yonet = TRUE, rol_degistir = FALSE, oturum_kapat = FALSE,
      belge_kopyala = TRUE
    ))
  }

  if (identical(rol, katilimci)) {
    return(list(
      oku = TRUE, oda_yaz = TRUE, yapay_zeka_sor = TRUE, davet_et = FALSE,
      katilimci_yonet = FALSE, rol_degistir = FALSE, oturum_kapat = FALSE,
      belge_kopyala = TRUE
    ))
  }

  if (identical(rol, izleyici)) {
    return(list(
      oku = TRUE, oda_yaz = FALSE, yapay_zeka_sor = FALSE, davet_et = FALSE,
      katilimci_yonet = FALSE, rol_degistir = FALSE, oturum_kapat = FALSE,
      belge_kopyala = TRUE
    ))
  }

  temel
}

ortak_yetki_var_mi <- function(rol, eylem) {
  yetkiler <- ortak_rol_yetkileri(rol)
  isTRUE(yetkiler[[eylem]])
}

# İçerik erişimi yalnızca daveti kabul etmiş (Katıldı) katılımcılar içindir.
# Davet edilmiş ama henüz kabul etmemiş kullanıcı yalnızca davet metadata'sını
# görebilir; oda içeriğini GÖREMEZ.
ortak_icerik_erisimi_var_mi <- function(katilim_durumu) {
  identical(as.character(katilim_durumu)[1], "Katıldı")
}

# Sahip, başka bir katılımcı tarafından yönetilemez (rol değişikliği/çıkarma).
ortak_katilimci_yonetilebilir_mi <- function(yoneten_rol, hedef_rol) {
  if (!ortak_yetki_var_mi(yoneten_rol, "katilimci_yonet")) {
    return(FALSE)
  }
  !identical(hedef_rol, ortak_oturum_rolleri()[1])
}

# --- Mesaj yönlendirme planı ------------------------------------------------------

# Mesaj türüne göre hedef + LLM tetikleme kararı. TEK LLM tetikleyici yol
# YapayZekaSorusu'dur; OdaMesajı asla LLM'e gitmez.
ortak_mesaj_yonlendirme_plani <- function(mesaj_turu) {
  turler <- ortak_mesaj_turleri()
  hedefler <- ortak_mesaj_hedefleri()

  if (!is.character(mesaj_turu) || length(mesaj_turu) != 1L ||
      is.na(mesaj_turu) || !(mesaj_turu %in% turler)) {
    return(list(gecerli = FALSE, hedef = NA_character_, llm_tetikler = FALSE))
  }

  if (identical(mesaj_turu, "YapayZekaSorusu")) {
    return(list(gecerli = TRUE, hedef = hedefler[2], llm_tetikler = TRUE))
  }

  list(gecerli = TRUE, hedef = hedefler[1], llm_tetikler = FALSE)
}

# --- Canlı durum sınıflandırması ----------------------------------------------------

# Son kalp atışı zamanına göre Türkçe canlı durum değeri üretir.
#   <= cevrimici_saniye  -> Çevrimİçi
#   <= bosta_saniye      -> Boşta
#   aksi halde           -> ÇevrimDışı (NA/geçersiz zaman dahil)
ortak_sunum_durumu <- function(son_kalp_atisi,
                               simdi = Sys.time(),
                               cevrimici_saniye = 120,
                               bosta_saniye = 300) {
  durumlar <- ortak_canli_durumlar()

  zaman <- tryCatch(as.POSIXct(son_kalp_atisi, tz = "UTC"), error = function(e) NA)
  if (length(zaman) != 1L || is.na(zaman)) {
    return(durumlar[3])
  }

  fark <- as.numeric(difftime(simdi, zaman, units = "secs"))
  if (is.na(fark) || fark < 0) {
    fark <- 0
  }

  if (fark <= cevrimici_saniye) {
    return(durumlar[1])
  }
  if (fark <= bosta_saniye) {
    return(durumlar[2])
  }
  durumlar[3]
}

# --- Liste görünürlük kuralları ------------------------------------------------------

# Kullanıcının "Ortak Çalışmalarım" listesinde bir oturumu görüp görmeyeceği.
# Kullanıcı bazlı arşiv (KullanıcıArşivledi) yalnızca o kullanıcının görünümünü
# etkiler; oda herkese arşivlenmez.
ortak_liste_gorunur_mu <- function(katilim_durumu,
                                   gorunum_durumu,
                                   oturum_durumu,
                                   arsiv_gorunumu = FALSE) {
  katilim <- as.character(katilim_durumu)[1]
  gorunum <- as.character(gorunum_durumu)[1]
  oturum <- as.character(oturum_durumu)[1]

  if (!(katilim %in% c("Katıldı", "DavetEdildi"))) {
    return(FALSE)
  }

  kullanici_arsivledi <- identical(gorunum, "KullanıcıArşivledi")
  oda_arsivli <- oturum %in% c("Arşivlendi", "Kapandı")

  if (isTRUE(arsiv_gorunumu)) {
    return(kullanici_arsivledi || oda_arsivli)
  }

  !kullanici_arsivledi && !oda_arsivli
}
