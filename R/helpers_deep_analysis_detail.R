# ==============================================================================
# Dosya Yolu: R/helpers_deep_analysis_detail.R
# Açıklama:   Derin Analiz detay seviyesi kataloğu ve seviye çözümleyicileri.
#
#             Bu dosya BİLİNÇLİ olarak saftır: Shiny/reactive/DB/LLM/ağ
#             bağımlılığı yoktur, worker güvenlidir. R/helpers_deep_analysis.R
#             bakım borcu ratchet bütçesini aştığı için buradan ayrılmıştır;
#             seviye kataloğunu tekrar orkestratör dosyasına taşımayın.
#
#             Yükleme sırası: R/config_source_manifest.R içindeki
#             `analysis_helpers` bölümünde R/helpers_deep_analysis.R ÖNCESİNDE
#             yer alır. Bu dosyayı yalıtılmış olarak source eden testler,
#             R/helpers_deep_analysis.R yanında bunu da source etmelidir.
# ==============================================================================

# ------------------------------------------------------------------------------
# SABİTLER
# ------------------------------------------------------------------------------

# Detay seviyesi tanımları
ANALYSIS_DETAIL_LEVELS <- list(
  ozet   = list(
    id    = "ozet",
    label = "Özet",
    description = "Kısa ve öz bulgular, temel istatistikler",
    max_tokens  = 1500,
    preview_rows = 10,
    instruction = paste0(
      "KISA VE ÖZ yanıt ver. Sadece EN ÖNEMLİ 2-3 bulguyu belirt. ",
      "Uzun açıklamalardan kaçın, madde işaretleri kullan. ",
      "Toplamda 5-8 cümleyi geçme."
    )
  ),
  standart = list(
    id    = "standart",
    label = "Standart",
    description = "Dengeli detay seviyesi, temel analiz ve öneriler",
    max_tokens  = 3000,
    preview_rows = 20,
    instruction = paste0(
      "DENGELİ bir analiz sun. Önemli bulguları, temel istatistikleri ve ",
      "kısa öneriler içer. Her sorgu için 1-2 paragraf yeterli. ",
      "Gereksiz detaylardan kaçın ama önemli noktaları atla."
    )
  ),
  detayli = list(
    id    = "detayli",
    label = "Detaylı",
    description = "Kapsamlı analiz, kök sebepler ve detaylı öneriler",
    max_tokens  = 4096,
    preview_rows = 50,
    instruction = paste0(
      "DERİNLEMESİNE analiz yap. Her sütunun hikayesini anlat, ",
      "dağılımları, anormallikleri ve eğilimleri detaylı incele. ",
      "Kök sebep analizi yap ve spesifik, uygulanabilir öneriler sun. ",
      "Tablolar ve karşılaştırmalar kullan."
    )
  )
)

#' Detay seviyesi yapılandırmasını döndür
#' @param level_id Seviye kimliği ("ozet", "standart", "detayli")
#' @return Detay seviyesi yapılandırma listesi
get_analysis_detail_config <- function(level_id) {
  # KİMLİK ÖNCE SKALER METNE İNDİRGENİR.
  #
  # `ANALYSIS_DETAIL_LEVELS[[NULL]]` / `[[NA]]` / `[[character(0)]]` HATA verir;
  # detay seviyesi ayarlanmamış bir işçi anlık görüntüsü ya da UI değeri derin
  # çalıştırmayı `standart`a düşmek yerine DÜŞÜRÜYORDU. Belgelenen yedek yalnızca
  # BİLİNMEYEN ama boş olmayan dizeleri kapsıyordu.
  kimlik <- suppressWarnings(as.character(level_id)[1])
  if (length(kimlik) != 1L || is.na(kimlik) || !nzchar(kimlik)) kimlik <- "standart"
  config <- ANALYSIS_DETAIL_LEVELS[[kimlik]]
  if (is.null(config)) {
    config <- ANALYSIS_DETAIL_LEVELS[["standart"]]
  }
  return(config)
}

#' Detay seviyesi talimatını döndür
#' @param level_id Seviye kimliği
#' @return Karakter dizisi olarak talimat metni
get_analysis_detail_instruction <- function(level_id) {
  config <- get_analysis_detail_config(level_id)
  return(config$instruction)
}

