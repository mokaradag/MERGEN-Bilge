# ==============================================================================
# Dosya Yolu: R/helpers_mcp_context.R
# Açıklama: MCP araç ortamı, debug kapısı ve kullanıcı kimliği çözümleme
#           yardımcılarını küçük ve bağımsız bir bootstrap dosyasında toplar.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  helpers_mcp_tools <- new.env(parent = globalenv())
}

helpers_mcp_tools$mcp_debug_enabled <- function() {
  env_value <- tolower(trimws(Sys.getenv("MERGEN_MCP_DEBUG", "false")))
  isTRUE(getOption("mergen.mcp.debug", FALSE)) ||
    env_value %in% c("1", "true", "t", "yes", "y", "on")
}

helpers_mcp_tools$mcp_debug_log <- function(...) {
  if (!isTRUE(helpers_mcp_tools$mcp_debug_enabled())) {
    return(invisible(NULL))
  }

  msg <- paste(..., collapse = "")
  msg <- enc2utf8(msg)

  if (exists("log_debug", mode = "function", inherits = TRUE)) {
    log_debug(msg)
  } else {
    message(msg)
  }

  invisible(NULL)
}

# Ortam bayrağı okuması MCP ortamına BAĞLANIR. `call_llm_worker()` MCP
# araçlarını future işçisinde çalıştırabiliyor; işçiye `R/utils_common.R`
# yüklenmediği ve otomatik bağımlılık taraması ortam içindeki fonksiyonları
# incelemediği için `mergen_env_flag()` "could not find function" hatası
# veriyor ve güvenli ret yerine genel araç hatası dönüyordu.
helpers_mcp_tools$mcp_env_flag <- function(name, default = FALSE,
                                           invalid = default) {
  if (exists("mergen_env_flag", mode = "function", inherits = TRUE)) {
    return(mergen_env_flag(name, default = default, invalid = invalid))
  }

  ham <- trimws(as.character(Sys.getenv(name, unset = ""))[1])
  if (is.na(ham) || !nzchar(ham)) return(isTRUE(default))
  anahtar <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", ham)
  anahtar <- chartr("ÇĞİÖŞÜçğıöşü", "cgiosucgiosu", anahtar)
  if (anahtar %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik")) return(TRUE)
  if (anahtar %in% c("false", "f", "0", "no", "n", "off", "hayir", "kapali")) return(FALSE)
  isTRUE(invalid)
}

helpers_mcp_tools$get_session_user_id <- function(session = NULL) {
  if (is.null(session) || is.null(session$userData)) {
    return(NULL)
  }

  user_data <- session$userData
  candidate <- NULL

  for (field in c("user_id", "userId", "id", "userID")) {
    value <- NULL

    if (is.environment(user_data)) {
      if (exists(field, envir = user_data, inherits = FALSE)) {
        value <- get(field, envir = user_data, inherits = FALSE)
      }
    } else if (is.list(user_data)) {
      value <- user_data[[field]]
    }

    if (!is.null(value) && length(value) > 0L) {
      candidate <- value
      break
    }
  }

  if (is.null(candidate) || length(candidate) == 0L) {
    return(NULL)
  }

  candidate <- trimws(as.character(candidate[1]))

  if (!nzchar(candidate) ||
      tolower(candidate) %in% c("0", "unknown", "null", "na", "nan")) {
    return(NULL)
  }

  candidate
}