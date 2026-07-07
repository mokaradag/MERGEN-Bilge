# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_sunum.R
# Açıklama: Ortak Oturumlar SAF sunum-karar yardımcıları: rol görünen ad,
#           atanabilir rol seçenekleri ve canlı durum sunum rozeti (renk sınıfı
#           + erişilebilir Türkçe etiket). Yetki matrisi ve iş kuralı sabitleri
#           R/helpers_ortak_oturum_permissions.R içindedir ve bu dosyadan ÖNCE
#           yüklenir (ortak_oturum_rolleri bağımlılığı).
#
# Sözleşmeler:
#   * Bu dosya SAF kalır: Shiny, reactive, DB, ağ, dosya sistemi yok.
#   * Teknik rol anahtarları (OturumYöneticisi) DEĞİŞMEZ; yalnızca görünen ad
#     boşluklu üretilir. Görünüm ayrımı güvenlik değildir.
#   * Durum göstergesi yalnızca renge dayanmaz: rozet daima title/aria-label
#     için Türkçe etiket taşır.
# ==============================================================================

# DB'de saklanan teknik rol adının kullanıcıya görünen Türkçe etiketi.
# Teknik anahtarlar değişmez; yalnızca görünüm ayrışır.
ortak_rol_gorunen_ad <- function(rol) {
  etiketler <- c(
    "Sahip" = "Sahip",
    "OturumYöneticisi" = "Oturum Yöneticisi",
    "Katılımcı" = "Katılımcı",
    "İzleyici" = "İzleyici"
  )

  rol <- as.character(rol %||% "")[1]
  if (!is.na(rol) && nzchar(rol) && rol %in% names(etiketler)) {
    return(unname(etiketler[[rol]]))
  }
  if (is.na(rol)) "" else rol
}

# Davet/rol atama seçenekleri: Sahip atanamaz; görünen etiket + teknik değer.
ortak_rol_secenekleri <- function() {
  roller <- setdiff(ortak_oturum_rolleri(), ortak_oturum_rolleri()[1])
  stats::setNames(roller, vapply(roller, ortak_rol_gorunen_ad, character(1)))
}

# Katılımcı/davet listelerindeki durum göstergesi: renk sınıfı + erişilebilir
# Türkçe etiket (yalnızca renge dayanılmaz).
#   davet bekliyor            -> sarı (oo-canli-davetli)
#   çevrim içi + bu odada     -> yeşil (oo-canli-odada)
#   çevrim içi (başka sayfa)  -> mavi (oo-canli-cevrimici)
#   boşta                     -> turuncu (oo-canli-bosta)
#   aksi                      -> gri (oo-canli-cevrimdisi)
ortak_sunum_rozeti <- function(canli_durum,
                               ayni_odada = FALSE,
                               davet_bekliyor = FALSE) {
  if (isTRUE(davet_bekliyor)) {
    return(list(sinif = "oo-canli-davetli", etiket = "Davet bekliyor"))
  }

  durum <- as.character(canli_durum %||% "")[1]

  if (identical(durum, "Çevrimİçi")) {
    if (isTRUE(ayni_odada)) {
      return(list(sinif = "oo-canli-odada", etiket = "Bu odada çevrim içi"))
    }
    return(list(sinif = "oo-canli-cevrimici", etiket = "Uygulamada çevrim içi"))
  }

  if (identical(durum, "Boşta")) {
    return(list(sinif = "oo-canli-bosta", etiket = "Boşta"))
  }

  list(sinif = "oo-canli-cevrimdisi", etiket = "Çevrim dışı")
}
