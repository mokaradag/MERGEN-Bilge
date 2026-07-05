# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_email.R
# Açıklama: Ortak Oturum davetleri için SAF e-posta taslağı yardımcıları.
#
# Sözleşmeler:
#   * E-posta OTOMATİK GÖNDERİLMEZ. Bu katman yalnızca güvenli, genel bir
#     taslak üretir; davet eden kullanıcı taslağı kendi e-posta istemcisinde
#     (mailto: üzerinden) gözden geçirip kendisi gönderir.
#   * Taslak İÇERİK SIZDIRMAZ: sohbet metni, yapay zekâ yanıtı, üretilen
#     belge adı/yolu/bağlantısı veya yetkilendirmeyi atlatan URL içermez.
#     Alıcı, daveti ancak MERGEN Bilge'ye giriş yapıp "Ortak Çalışmalarım >
#     Davetlerim" üzerinden kabul ederek içerik erişimi kazanır.
#   * mailto sınırı Türkçe güvenli kodlama için mergen_mailto_href()
#     üzerinden geçer (CLAUDE.md mailto sözleşmesi).
# ==============================================================================

# Davet e-postası konu + gövde metnini üretir. Yalnızca davet metadata'sı
# (davet eden ad, oturum başlığı) kullanılır; içerik asla eklenmez.
ortak_davet_eposta_metni <- function(davet_eden_ad, oturum_baslik) {
  davet_eden_ad <- trimws(as.character(davet_eden_ad %||% "")[1])
  oturum_baslik <- trimws(as.character(oturum_baslik %||% "")[1])

  if (!nzchar(davet_eden_ad)) {
    davet_eden_ad <- "Bir MERGEN Bilge kullanıcısı"
  }
  if (!nzchar(oturum_baslik)) {
    oturum_baslik <- "Ortak Çalışma"
  }

  konu <- sprintf("MERGEN Bilge ortak çalışma daveti: %s", oturum_baslik)

  govde <- paste0(
    "Merhaba,\n\n",
    davet_eden_ad,
    " sizi MERGEN Bilge üzerinde yürütülen “",
    oturum_baslik,
    "” adlı ortak çalışmaya davet ediyor.\n\n",
    "Ortak oturuma katılmak için MERGEN Bilge'ye giriş yaparak ",
    "“Ortak Çalışmalarım > Davetlerim” bölümünden daveti ",
    "kabul edebilirsiniz.\n\n",
    "Saygılarımla,\nMERGEN Bilge"
  )

  list(konu = konu, govde = govde)
}

# Davet taslağını mailto: bağlantısına çevirir. Merkezi mailto yardımcısı
# yoksa (izole test bağlamı) güvenli UTF-8 yüzde-kodlamalı yedek yol kullanılır.
ortak_davet_eposta_taslak_href <- function(alici_eposta, davet_eden_ad, oturum_baslik) {
  alici_eposta <- trimws(as.character(alici_eposta %||% "")[1])
  if (!nzchar(alici_eposta)) {
    return("")
  }

  metin <- ortak_davet_eposta_metni(davet_eden_ad, oturum_baslik)

  if (exists("mergen_mailto_href", mode = "function", inherits = TRUE)) {
    return(mergen_mailto_href(
      to = alici_eposta,
      subject = metin$konu,
      body = metin$govde
    ))
  }

  # Yedek yol: UTF-8 baytlarından yüzde kodlama (Windows native-byte riskine karşı).
  yuzde <- function(x) {
    baytlar <- charToRaw(enc2utf8(x))
    paste0(sprintf("%%%02X", as.integer(baytlar)), collapse = "")
  }

  paste0("mailto:", alici_eposta, "?subject=", yuzde(metin$konu), "&body=", yuzde(metin$govde))
}

# Taslağın güvenli (içerik sızdırmayan) olduğunu doğrular. Testler ve davet
# panosu bu kontrolü kullanır: yasak işaretleyicilerden biri geçerse FALSE.
ortak_davet_eposta_guvenli_mi <- function(govde_metni) {
  govde <- as.character(govde_metni %||% "")[1]
  if (!nzchar(govde)) {
    return(FALSE)
  }

  # İçerik sızıntısı işaretleyicileri: doğrudan URL, dosya yolu ve içerik blokları.
  yasakli_desenler <- c(
    "https?://", "\\\\\\\\", "/bilge_yolac_downloads/", "ortak_oturumlar/",
    "MesajMetni", "YapayZekaYanıtı", "token=", "api[_-]?key", "Bearer "
  )

  !any(vapply(
    yasakli_desenler,
    function(desen) grepl(desen, govde, ignore.case = TRUE, perl = TRUE),
    logical(1)
  ))
}
