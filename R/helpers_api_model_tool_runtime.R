# ==============================================================================
# Dosya Yolu: R/helpers_api_model_tool_runtime.R
# Açıklama:   Araç ailesi, Derin Düşünme seviyesi ve ana aksiyon model
#             seçimlerini çözen saf API model yardımcıları.
# ==============================================================================

# ------------------------------------------------------------------------------
# ARAÇ MODU ÇÖZÜMLEME YARDIMCILARI
# ------------------------------------------------------------------------------

get_tool_mode_config <- function(value,
                                 by = c("family", "setting_flag", "quick_action_id"),
                                 config = api_config) {
  by <- match.arg(by)
  all_cfg <- config$tool_mode_config %||% list()

  for (cfg in all_cfg) {
    candidate <- cfg[[by]] %||% NULL
    if (!is.null(candidate) && identical(as.character(candidate), as.character(value))) {
      return(cfg)
    }
  }

  NULL
}

resolve_tool_model_for_family <- function(tool_family,
                                          fallback_model = NULL,
                                          config = api_config) {
  cfg <- get_tool_mode_config(tool_family, by = "family", config = config)
  model_id <- cfg$model_id %||% fallback_model %||%
    as.character(config$local_models[1]) %||% ""

  as.character(model_id)[1]
}

resolve_deep_thinking_model <- function(tool_family,
                                        deep_level = "low",
                                        config = api_config) {
  if (is.null(tool_family) || !nzchar(as.character(tool_family))) {
    return(NULL)
  }

  dt_cfg <- config$deep_thinking_models %||% list()
  family_cfg <- dt_cfg[[as.character(tool_family)]]

  if (is.null(family_cfg)) {
    return(NULL)
  }

  level_key <- if (identical(tolower(as.character(deep_level)), "high")) {
    "high"
  } else {
    "low"
  }

  model_id <- family_cfg[[level_key]]

  if (is.null(model_id) || !nzchar(as.character(model_id))) {
    return(NULL)
  }

  as.character(model_id)[1]
}

resolve_runtime_model_for_request <- function(tool_family,
                                              fallback_model = NULL,
                                              excel_deep_on = FALSE,
                                              excel_deep_level = "low",
                                              coding_deep_on = FALSE,
                                              coding_deep_level = "low",
                                              config = api_config) {
  model_id <- resolve_tool_model_for_family(
    tool_family = tool_family,
    fallback_model = fallback_model,
    config = config
  )

  if (identical(tool_family, "mcp_excel") && isTRUE(excel_deep_on)) {
    deep_model <- resolve_deep_thinking_model(
      tool_family = "mcp_excel",
      deep_level = excel_deep_level,
      config = config
    )

    if (!is.null(deep_model) && nzchar(deep_model)) {
      model_id <- deep_model
    }

  } else if (identical(tool_family, "coding") && isTRUE(coding_deep_on)) {
    deep_model <- resolve_deep_thinking_model(
      tool_family = "coding",
      deep_level = coding_deep_level,
      config = config
    )

    if (!is.null(deep_model) && nzchar(deep_model)) {
      model_id <- deep_model
    }
  }

  model_id <- as.character(model_id %||% "")[1]

  if (is.na(model_id) || !nzchar(model_id)) {
    model_id <- as.character(config$local_models[1] %||% "")[1]
  }

  model_id
}

resolve_tool_model_for_flag <- function(setting_flag,
                                        fallback_model = NULL,
                                        config = api_config) {
  cfg <- get_tool_mode_config(setting_flag, by = "setting_flag", config = config)
  model_id <- cfg$model_id %||% fallback_model %||%
    as.character(config$local_models[1]) %||% ""

  as.character(model_id)[1]
}

build_main_actions_data_from_config <- function(config = api_config) {
  all_cfg <- config$tool_mode_config %||% list()

  actions <- lapply(all_cfg, function(cfg) {
    if (is.null(cfg$quick_action_id) || !nzchar(cfg$quick_action_id %||% "")) {
      return(NULL)
    }

    # Langflow araçları yerel model taşımaz (model akışın içine gömülüdür).
    # Bu tür hızlı eylemlerde model_value boş bırakılır ki hızlı eylem tıklaması
    # yanıltıcı bir model değişimini tetiklemesin.
    is_langflow_tool <- identical(as.character(cfg$runtime %||% "")[1], "langflow")
    model_value <- if (is_langflow_tool) {
      ""
    } else {
      cfg$model_id %||% as.character(config$local_models[1]) %||% ""
    }

    list(
      id = cfg$quick_action_id,
      title = cfg$title %||% cfg$quick_action_id,
      message = cfg$message %||% "",
      description = cfg$description %||% "",
      icon_name = cfg$icon_name %||% "bolt",
      themeColor = cfg$themeColor %||% "#6366f1",
      model_value = model_value
    )
  })

  Filter(Negate(is.null), actions)
}