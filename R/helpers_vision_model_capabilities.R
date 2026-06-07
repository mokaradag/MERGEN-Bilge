# ==============================================================================
# Dosya Yolu: R/helpers_vision_model_capabilities.R
# Açıklama: api_config$local_model_capabilities tablosuna görsel anlama (vision /
#           Image Input) yeteneğini işaretleyen saf yardımcı. config_api.R
#           tarafından, model yetenek tablosu kurulduktan sonra çağrılır.
#
#           Yetenek-öncelikli tasarım: gating'i model yeteneği belirler; bu dosya
#           yalnızca HANGİ modellerin vision = TRUE olacağını işaretler. Model
#           kimlikleri .Renviron yer-tutuculardır; fonksiyonlara sabit model adı
#           gömülmez.
#
#           Vision destekli model kimlikleri iki kaynaktan toplanır:
#             1) MERGEN_VISION_MODELS  -> ";" veya "," ile ayrılmış model listesi
#             2) extra_vision_models   -> çağıranın eklediği kimlikler (Kodlama
#                Uzmanı derin düşünme modelleri katalogda Image Input destekli).
#
#           Bu dosya Shiny/reactive/ağ/DB'ye dokunmaz.
# ==============================================================================

# MERGEN_VISION_MODELS ortam değişkenini güvenli biçimde model kimliği vektörüne
# çevirir. Model kimlikleri boşluk içerebildiği için yalnızca ";" ve "," ile
# ayrılır; her parça trimlenir.
parse_vision_models_env <- function(env_value = Sys.getenv("MERGEN_VISION_MODELS", "")) {
  if (!is.character(env_value) || length(env_value) < 1L ||
      is.na(env_value[1]) || !nzchar(env_value[1])) {
    return(character(0))
  }
  ids <- trimws(unlist(strsplit(env_value[1], "[;,]+")))
  ids[!is.na(ids) & nzchar(ids)]
}

# api_config$local_model_capabilities tablosuna vision alanını işaretler.
# - Her girdide vision varsayılanı FALSE'a çekilir.
# - MERGEN_VISION_MODELS + extra_vision_models kimlikleri vision = TRUE yapılır;
#   tabloda olmayan kimlik için güvenli temel kayıt açılır.
apply_vision_model_capabilities <- function(api_config,
                                            extra_vision_models = character(0),
                                            env_value = Sys.getenv("MERGEN_VISION_MODELS", "")) {
  if (!is.list(api_config)) {
    return(api_config)
  }

  caps <- api_config$local_model_capabilities
  if (!is.list(caps)) {
    caps <- list()
  }

  # 1) Her girdide vision varsayılanını FALSE yap.
  for (cap_id in names(caps)) {
    if (is.list(caps[[cap_id]]) && is.null(caps[[cap_id]]$vision)) {
      caps[[cap_id]]$vision <- FALSE
    }
  }

  # 2) Vision destekli kimlikleri topla (env + çağıran ek listesi).
  vision_ids <- unique(c(
    parse_vision_models_env(env_value),
    as.character(extra_vision_models)
  ))
  vision_ids <- vision_ids[!is.na(vision_ids) & nzchar(vision_ids)]

  # 3) Vision destekli modelleri TRUE yap; tabloda yoksa güvenli temel kayıt aç.
  for (vid in vision_ids) {
    cap <- caps[[vid]]
    if (!is.list(cap)) {
      cap <- list(
        thinking = FALSE,
        omit_temperature = FALSE,
        stream_reasoning = FALSE,
        allow_reasoning_fallback = FALSE
      )
    }
    cap$vision <- TRUE
    caps[[vid]] <- cap
  }

  api_config$local_model_capabilities <- caps
  api_config
}
