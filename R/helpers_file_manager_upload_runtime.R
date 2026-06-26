# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_upload_runtime.R
# Açıklama: Dosya Yönetimi toplu yükleme doğrulama ve kalıcılaştırma runtime'ı.
# ==============================================================================

fm_process_bulk_upload_batch <- function(
  files_df,
  existing_names,
  session,
  uid,
  is_auth_ready,
  is_under_mcp_base,
  ensure_persisted_upload_index,
  process_uploaded_file,
  fm_debug
) {
  if (is.null(files_df) || nrow(files_df) == 0) return(list(saved_infos = list(), duplicate_names = character()))

  new_df <- files_df[!files_df$name %in% existing_names, , drop = FALSE]
  dup_df <- files_df[files_df$name %in% existing_names, , drop = FALSE]
  duplicate_names <- as.character(dup_df$name %||% character())

  if (nrow(new_df) == 0) {
    return(list(saved_infos = list(), duplicate_names = duplicate_names))
  }

  if (isTRUE(SSO_ENABLED) && !is_auth_ready()) {
    fm_debug("upload_skip", "auth henüz tamamlanmadığı için toplu yükleme ertelendi")
    showToast(session, "Kimlik doğrulama tamamlanmadan dosya yüklenemez.", "warning")
    return(list(saved_infos = list(), duplicate_names = duplicate_names, auth_blocked = TRUE))
  }

  saved_infos <- list()

  withProgress(message = 'Dosyalar yükleniyor...', value = 0, {
    for (i in seq_len(nrow(new_df))) {
      incProgress(1 / nrow(new_df), detail = new_df$name[i])

      upload_row <- new_df[i, , drop = FALSE]
      upload_name <- as.character(upload_row$name[1] %||% "")
      upload_path <- as.character(upload_row$datapath[1] %||% "")

      if (!nzchar(uid) || identical(uid, "unknown") || identical(uid, "0")) {
        fm_debug("persist_abort", sprintf("geçersiz user_id nedeniyle kaydedilemedi: %s", upload_name))
        showToast(session, paste("Dosya kalıcı klasöre kaydedilemedi:", upload_name), "error")
        next
      }

      if (exists("validate_uploaded_file", envir = globalenv(), inherits = FALSE)) {
        max_mb <- fm_upload_limit_mb()
        allowed_upload_exts <- if (exists("fm_normal_allowed_extensions", mode = "function", inherits = TRUE)) {
          fm_normal_allowed_extensions()
        } else {
          NULL
        }

        dogrulama <- validate_uploaded_file(
          path = upload_path,
          filename = upload_name,
          max_size_mb = max_mb,
          allowed_ext = allowed_upload_exts
        )

        if (!isTRUE(dogrulama$ok)) {
          fm_debug(
            "upload_validation_reject",
            sprintf("%s -> %s (%s)", upload_name, dogrulama$code %||% "unknown", dogrulama$error %||% "")
          )
          showToast(
            session,
            sprintf("Dosya reddedildi: %s - %s", upload_name, dogrulama$error %||% "bilinmeyen doğrulama hatası"),
            "error"
          )
          next
        }
      }

      if (!is_under_mcp_base(upload_path)) {
        persisted_path <- tryCatch({
          copy_to_mcp_base(
            list(
              name = upload_name,
              datapath = upload_path,
              size = suppressWarnings(as.numeric(upload_row$size[1] %||% NA_real_)),
              type = as.character(upload_row$type[1] %||% "")
            ),
            uid
          )
        }, error = function(e) {
          fm_debug("persist_error", sprintf("%s -> %s", upload_name, conditionMessage(e)))
          ""
        })

        if (!nzchar(persisted_path) || !path_exists_relaxed(persisted_path)) {
          showToast(session, paste("Dosya kalıcı klasöre kaydedilemedi:", upload_name), "error")
          next
        }

        upload_row$datapath[1] <- persisted_path

        persisted_size <- suppressWarnings(file.info(persisted_path)$size[1])
        if (!is.na(persisted_size)) {
          upload_row$size[1] <- persisted_size
        }
      }

      final_persisted_path <- as.character(upload_row$datapath[1] %||% "")
      ensure_persisted_upload_index(abs_path = final_persisted_path, display_name = upload_name, uid = uid)

      result <- process_uploaded_file(upload_row, generate_message = FALSE)
      if (!is.null(result)) {
        saved_infos[[length(saved_infos) + 1]] <- result
      }
    }
  })

  list(saved_infos = saved_infos, duplicate_names = duplicate_names)
}
