# ==============================================================================
# Dosya Yolu: R/helpers_feature_api_key.R
# Açıklama:   Sohbet dışındaki özellikler için etkin API anahtarını çözen
#             küçük yardımcılar.
#             Kişisel anahtar, izinli kurum anahtarı ve özellik-özel servis
#             anahtarı öncelikleri burada merkezileştirilir.
# ==============================================================================

.mb_feature_api_key_scalar <- function(value) {
  if (is.null(value)) {
    return("")
  }

  value <- tryCatch(as.character(value)[1], error = function(e) "")
  if (is.na(value)) {
    return("")
  }

  trimws(value)
}

mb_api_key_get_feature_key_value <- function(session = NULL,
                                             service_key = "",
                                             fallback_key = "",
                                             require_auth = TRUE,
                                             clear_on_mismatch = TRUE,
                                             prefer_service_key_after_personal = FALSE) {
  service_key <- .mb_feature_api_key_scalar(service_key)
  fallback_key <- .mb_feature_api_key_scalar(fallback_key)

  personal_key <- ""
  default_key <- ""

  plan <- tryCatch(
    mb_api_key_get_effective_key(
      session = session,
      require_auth = require_auth,
      allow_default = NULL,
      clear_on_mismatch = clear_on_mismatch
    ),
    error = function(e) NULL
  )

  if (is.list(plan)) {
    plan_key <- .mb_feature_api_key_scalar(plan$key)
    plan_source <- .mb_feature_api_key_scalar(plan$source)

    if (identical(plan_source, "personal") && nzchar(plan_key)) {
      personal_key <- plan_key
    } else if (identical(plan_source, "default") && nzchar(plan_key)) {
      default_key <- plan_key
    }
  }

  if (nzchar(personal_key)) {
    return(personal_key)
  }

  # TTS gibi özelliklerde, açıkça tanımlanmış özellik-özel servis anahtarı
  # varsa kişisel anahtardan sonra onu koru; yoksa kurum anahtarına düş.
  if (isTRUE(prefer_service_key_after_personal) && nzchar(service_key)) {
    return(service_key)
  }

  if (nzchar(default_key)) {
    return(default_key)
  }

  if (nzchar(service_key)) {
    return(service_key)
  }

  if (nzchar(fallback_key)) {
    return(fallback_key)
  }

  ""
}