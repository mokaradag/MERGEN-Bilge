# R/config_version_history.R
# Dosya Yolu: R/config_version_history.R
# Aciklama: Surum gecmisi ve guncelleme bilgilerini tanimlayan yapilandirma dosyasi.
# Her yeni surum icin buraya yeni bir giris eklenir.

#' Surum Gecmisi Verilerini Getir
#'
#' @description Tum surum bilgilerini kronolojik siralamayla dondurur.
#' En guncel surum listenin basinda yer alir.
#'
#' @return Surum listesi: her eleman id, version, date, title, highlights ve details iceri.
get_version_history <- function() {
  list(
    # Mevcut surum
    current_version = "1.0",

    versions = list(

      # ------------------------------------------------------------------
      # SURUM 1.0 — Uretim Surumu
      # ------------------------------------------------------------------
      list(
        id = "v1_0",
        version = "1.0",
        date = "2026-03-07",
        title = "MERGEN Bilge Resmi Lansman",
        badge = "Yeni",
        highlights = list(
          "Butunlesik mod ile tam ozellikli deneyim",
          "5 benzersiz AI karakter ve sinematik secim ekrani",
          "Proje ve Kaynak Analizi araci ile akilli veri sorgulama",
          "Gorsel olusturma ve galeri yonetimi",
          "Destek merkezi, geri bildirim ve hata bildirimi",
          "Surum bilgilendirme sistemi"
        ),
        details = list(
          list(
            category = "Yeni Ozellikler",
            icon = "sparkles",
            items = list(
              "Sinematik giris ekrani ile 3 farkli deneyim modu (Odak, Dinamik, Butunlesik)",
              "Butunlesik modda karakter secim adimi eklendi",
              "Surum bilgilendirme sistemi: giris ekraninda bildirim ikonu ve ozel sayfa",
              "Karakter bazli neural network animasyonu (daha canli renkler)",
              "Proje sorgulamalari icin onceden toplulaştirilmiş sutun destegi"
            )
          ),
          list(
            category = "Iyilestirmeler",
            icon = "arrow-up-right-dots",
            items = list(
              "Kayitli soylesi yuklendiginde arac aktivasyonu duzeltildi",
              "NPS puanlama daireleri daha kompakt ve dogru konumlandirildi",
              "Neural network animasyon renkleri daha belirgin hale getirildi",
              "Sorgu sonuclarinda onceden hesaplanmis sutunlar istatistik ozetinden cikarildi"
            )
          ),
          list(
            category = "Teknik",
            icon = "code",
            items = list(
              "Moduler dosya yapisi ile ayrilmis CSS, JS ve R betikleri",
              "Karakter verileri istemciye dinamik olarak aktariliyor",
              "Yaris kosullarina karsi onlemler alinmistir"
            )
          )
        )
      ),

      # ------------------------------------------------------------------
      # SURUM 0.9 — Beta Surumu
      # ------------------------------------------------------------------
      list(
        id = "v0_9",
        version = "0.9",
        date = "2026-03-04",
        title = "Beta Surumu",
        badge = NULL,
        highlights = list(
          "Temel sohbet altyapisi ve LLM entegrasyonu",
          "Dosya yukleme ve analiz ozellikleri",
          "Karakter sistemi ve kisisellesirme sayfasi",
          "Destek sayfalari (Yardim Merkezi, Geri Bildirim, Hakkinda)"
        ),
        details = list(
          list(
            category = "Temel Ozellikler",
            icon = "layer-group",
            items = list(
              "Gercek zamanli akis (streaming) ile LLM yanit sistemi",
              "MCP arac entegrasyonu ve tekrarli arac cagirma destegi",
              "Dosya yukleme, onizleme ve sohbete ekleme",
              "Soylesi kaydetme, yukleme ve arama",
              "5 AI karakter profili ve video tanitim sistemi",
              "TTS ve STT entegrasyonu",
              "Gorsel olusturma (DALL-E entegrasyonu)",
              "Sinematik giris ekrani ve deneyim modu secimi",
              "Destek: Yardim Merkezi, Geri Bildirim, Hata Bildirimi, Hakkinda"
            )
          )
        )
      )
    )
  )
}

#' Mevcut Surum Numarasini Getir
#' @return Karakter turunde surum numarasi
get_current_version <- function() {
  get_version_history()$current_version
}
