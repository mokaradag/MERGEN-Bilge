# R/config_version_history.R
# Dosya Yolu: R/config_version_history.R
# Açıklama: Sürüm geçmişi ve güncelleme bilgilerini tanımlayan yapılandırma dosyası.
# Her yeni sürüm için buraya yeni bir giriş eklenir.

#' Sürüm Geçmişi Verilerini Getir
#'
#' @description Tüm sürüm bilgilerini kronolojik sıralamayla döndürür.
#' En güncel sürüm listenin başında yer alır.
#'
#' @return Sürüm listesi: her eleman id, version, date, title, highlights ve details içerir.
get_version_history <- function() {
  list(
    # Mevcut sürüm
    current_version = "1.0",

    versions = list(

      # ------------------------------------------------------------------
      # SÜRÜM 1.0 — Üretim Sürümü
      # ------------------------------------------------------------------
      list(
        id = "v1_0",
        version = "1.0",
        date = "2026-03-07",
        title = "MERGEN Bilge Resmi Lansman",
        badge = "Yeni",
        highlights = list(
          "Bütünleşik mod ile tam özellikli deneyim",
          "5 benzersiz AI karakter ve sinematik seçim ekranı",
          "Proje ve Kaynak Analizi aracı ile akıllı veri sorgulama",
          "Görsel oluşturma ve galeri yönetimi",
          "Destek merkezi, geri bildirim ve hata bildirimi",
          "Sürüm bilgilendirme sistemi"
        ),
        details = list(
          list(
            category = "Yeni Özellikler",
            icon = "sparkles",
            items = list(
              "Sinematik giriş ekranı ile 3 farklı deneyim modu (Odak, Dinamik, Bütünleşik)",
              "Bütünleşik modda karakter seçim adımı eklendi",
              "Sürüm bilgilendirme sistemi: giriş ekranında bildirim ikonu ve özel sayfa",
              "Karakter bazlı neural network animasyonu (daha canlı renkler)",
              "Proje sorgulamaları için önceden toplulaştırılmış sütun desteği"
            )
          ),
          list(
            category = "İyileştirmeler",
            icon = "arrow-up-right-dots",
            items = list(
              "Kayıtlı söyleşi yüklendiğinde araç aktivasyonu düzeltildi",
              "NPS puanlama daireleri daha kompakt ve doğru konumlandırıldı",
              "Neural network animasyon renkleri daha belirgin hale getirildi",
              "Sorgu sonuçlarında önceden hesaplanmış sütunlar istatistik özetinden çıkarıldı"
            )
          ),
          list(
            category = "Teknik",
            icon = "code",
            items = list(
              "Modüler dosya yapısı ile ayrılmış CSS, JS ve R betikleri",
              "Karakter verileri istemciye dinamik olarak aktarılıyor",
              "Yarış koşullarına karşı önlemler alınmıştır"
            )
          )
        )
      ),

      # ------------------------------------------------------------------
      # SÜRÜM 0.9 — Beta Sürümü
      # ------------------------------------------------------------------
      list(
        id = "v0_9",
        version = "0.9",
        date = "2026-03-04",
        title = "Beta Sürümü",
        badge = NULL,
        highlights = list(
          "Temel sohbet altyapısı ve LLM entegrasyonu",
          "Dosya yükleme ve analiz özellikleri",
          "Karakter sistemi ve kişiselleştirme sayfası",
          "Destek sayfaları (Yardım Merkezi, Geri Bildirim, Hakkında)"
        ),
        details = list(
          list(
            category = "Temel Özellikler",
            icon = "layer-group",
            items = list(
              "Gerçek zamanlı akış (streaming) ile LLM yanıt sistemi",
              "MCP araç entegrasyonu ve tekrarlı araç çağırma desteği",
              "Dosya yükleme, önizleme ve sohbete ekleme",
              "Söyleşi kaydetme, yükleme ve arama",
              "5 AI karakter profili ve video tanıtım sistemi",
              "TTS ve STT entegrasyonu",
              "Görsel oluşturma (DALL-E entegrasyonu)",
              "Sinematik giriş ekranı ve deneyim modu seçimi",
              "Destek: Yardım Merkezi, Geri Bildirim, Hata Bildirimi, Hakkında"
            )
          )
        )
      )
    )
  )
}

#' Mevcut Sürüm Numarasını Getir
#' @return Karakter türünde sürüm numarası
get_current_version <- function() {
  get_version_history()$current_version
}