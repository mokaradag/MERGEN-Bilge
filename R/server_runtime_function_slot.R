# ==============================================================================
# Dosya Yolu: R/server_runtime_function_slot.R
# Açıklama: Geç bağlanan çalışma zamanı fonksiyon slotları için küçük yardımcı.
#           Amaç, server.R içinde yer tutucu fonksiyon + sonradan atama
#           desenini açık ve test edilebilir bir sözleşmeye taşımaktır.
# ==============================================================================

serverRuntimeCreateFunctionSlot <- function(name,
                                            fallback_fn = NULL) {
  if (is.null(name) || length(name) != 1L || !nzchar(as.character(name))) {
    .server_runtime_stop(
      "serverRuntimeCreateFunctionSlot: Geçerli bir slot adı bekleniyor."
    )
  }

  if (is.null(fallback_fn)) {
    fallback_fn <- function(...) invisible(NULL)
  }

  if (!is.function(fallback_fn)) {
    .server_runtime_stop(
      "serverRuntimeCreateFunctionSlot: fallback_fn fonksiyon olmalıdır."
    )
  }

  slot <- new.env(parent = emptyenv())
  class(slot) <- c("mergen_runtime_function_slot", "environment")

  slot$name <- as.character(name)
  slot$.fn <- fallback_fn
  slot$.bound <- FALSE

  slot$set <- function(fn) {
    if (!is.function(fn)) {
      .server_runtime_stop(sprintf(
        "serverRuntimeCreateFunctionSlot[%s]: Bağlanacak değer fonksiyon olmalıdır.",
        slot$name
      ))
    }

    slot$.fn <- fn
    slot$.bound <- TRUE

    invisible(slot)
  }

  slot$get <- function() {
    slot$.fn
  }

  slot$call <- function(...) {
    slot$.fn(...)
  }

  slot$is_bound <- function() {
    isTRUE(slot$.bound)
  }

  slot
}