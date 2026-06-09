# ==============================================================================
# Dosya Yolu: R/helpers_deep_thinking_model_capabilities.R
# Açıklama: api_config üzerinde Derin Düşünme (Excel Analizi / Kodlama Desteği)
#           modellerinin yetenek ve endpoint kayıtlarını tamamlayan saf yardımcı.
#           config_api.R tarafından, model yetenek tablosu kurulduktan sonra
#           guard'lı biçimde çağrılır (bkz. apply_vision_model_capabilities ile
#           aynı desen).
#
#           Bu dosya, config_api.R içinde daha önce İKİ ayrı source-time blok
#           olarak yaşayan kayıt mekanizmasını tek sahipte birleştirir:
#             1) tabloda olmayan Derin Düşünme modeline güvenli varsayılan
#                yetenek kaydı açma + endpoint haritasına "primary" ekleme,
#             2) tabloda olan Derin Düşünme modeline eksik varsayılan yetenek
#                alanlarını (örn. request_overrides) tamamlama.
#           Birleşik davranış, eski blokların sıralı bileşimiyle birebir aynıdır.
#
#           Model kimlikleri .Renviron yer-tutuculardır; fonksiyonlara sabit
#           model adı gömülmez. Bu dosya Shiny/reactive/ağ/DB'ye dokunmaz.
# ==============================================================================

# api_config$deep_thinking_models ağacından geçerli (NA olmayan, boş olmayan)
# benzersiz Derin Düşünme model kimliklerini toplar.
collect_deep_thinking_model_ids <- function(api_config) {
  if (!is.list(api_config)) {
    return(character(0))
  }

  ids <- unique(unname(unlist(
    api_config$deep_thinking_models,
    recursive = TRUE,
    use.names = FALSE
  )))

  ids <- as.character(ids)
  ids[!is.na(ids) & nzchar(ids)]
}

# Derin Düşünme modellerini yetenek tablosuna ve endpoint haritasına kaydeder.
# - Yetenekler: eksik alanlar güvenli thinking varsayılanlarıyla tamamlanır;
#   var olan açık tanımların değerleri korunur (modifyList(defaults, existing)).
# - Endpoint haritası: kimlik haritada yoksa veya boş/NA ise "primary" eklenir;
#   mevcut girdiler korunur. Harita adlandırılmış karakter vektörü kalır.
#
# ÖNEMLİ: local_model_endpoint_map adlandırılmış karakter vektörüdür; eksik ada
# [[...]] ile erişmek "altindis sınırlar dışında" hatası verir. Bu nedenle
# eksik-ad kontrolü %in% names(...) ile, okuma tekli [ ] ile yapılır.
apply_deep_thinking_model_capabilities <- function(api_config,
                                                   deep_model_ids = NULL) {
  if (!is.list(api_config)) {
    return(api_config)
  }

  if (is.null(deep_model_ids)) {
    deep_model_ids <- collect_deep_thinking_model_ids(api_config)
  }

  deep_model_ids <- as.character(deep_model_ids)
  deep_model_ids <- unique(deep_model_ids[!is.na(deep_model_ids) & nzchar(deep_model_ids)])

  if (length(deep_model_ids) == 0L) {
    return(api_config)
  }

  # Güvenli varsayılan: bilinmeyen deep model için ekstra body alanı ekleme.
  # Model özel override gerekiyorsa local_model_capabilities içinde açıkça
  # tanımlanmalı.
  capability_defaults <- list(
    thinking = TRUE,
    omit_temperature = TRUE,
    stream_reasoning = TRUE,
    allow_reasoning_fallback = TRUE,
    request_overrides = list()
  )

  caps <- api_config$local_model_capabilities
  if (!is.list(caps)) {
    caps <- list()
  }

  endpoint_map <- api_config$local_model_endpoint_map
  if (is.null(endpoint_map)) {
    endpoint_map <- character()
  }

  for (model_id in deep_model_ids) {
    existing_caps <- caps[[model_id]]
    if (!is.list(existing_caps)) {
      existing_caps <- list()
    }

    # Var olan açık tanım kazanır; yalnızca eksik alanlar varsayılanla dolar.
    caps[[model_id]] <- utils::modifyList(
      capability_defaults,
      existing_caps,
      keep.null = TRUE
    )

    endpoint_map_names <- names(endpoint_map)

    endpoint_mapped <- !is.null(endpoint_map_names) &&
      model_id %in% endpoint_map_names &&
      !is.na(endpoint_map[model_id]) &&
      nzchar(as.character(endpoint_map[model_id])[1])

    if (!isTRUE(endpoint_mapped)) {
      endpoint_map[model_id] <- "primary"
    }
  }

  api_config$local_model_capabilities <- caps
  api_config$local_model_endpoint_map <- endpoint_map
  api_config
}
