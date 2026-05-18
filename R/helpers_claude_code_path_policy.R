# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_path_policy.R
# Açıklama: Bilge Yolaç Claude Code güvenlik ilkesinin yol/kök katmanı.
#           Yol normalizasyonu, izin verilen çalışma kökleri/çıktı kökleri ve
#           çalışma dizini doğrulaması burada toplanır. Bu dosya
#           R/helpers_claude_code_security_policy.R'den ayrıştırıldı; çalıştırma
#           izin/CLI arg politikaları orada kalır.
#
#           Dosya bölünmesinin nedeni: güvenlik ilkesi dosyası UNC error
#           handler'ları sonrası 25 fonksiyona ulaşmıştı; bu dosya
#           taşıma ile her iki dosyayı da 25+ fonksiyon eşiğinin altına
#           indirir ve maintainability ratchet'i koruyacak şekilde
#           güncel taban çizgisini düşürür.
# ==============================================================================

cc_policy_split_roots <- function(value) {
  value <- as.character(value %||% character(0))
  value <- value[nzchar(value)]

  if (!length(value)) {
    return(character(0))
  }

  parcalar <- unlist(strsplit(value, "[;,\n\r]+", perl = TRUE), use.names = FALSE)
  unique(trimws(parcalar[nzchar(trimws(parcalar))]))
}

cc_policy_normalize_path <- function(path, must_exist = FALSE) {
  path <- as.character(path %||% "")[1]
  if (is.na(path) || !nzchar(path)) return("")

  # UNC yolları (\\server\share veya //server/share) Windows VM'de mapped
  # drive harfine çözülebiliyor (örn. //rehisds/... -> M:/rehisds/...). Çözülen
  # M:/ formu is_problematic_windows_workdir tarafından UNC olarak algılanmadığı
  # için runtime aynalama atlanır ve processx'in spawn ettiği cmd.exe oturumu
  # M:/ drive haritalamasına sahip değilse "directory is empty" veya
  # "The system cannot find the path specified" hatasıyla biter. Bu yüzden
  # güvenlik politikası katmanı UNC yollarını UNC olarak korur.
  #
  # NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
  # eşler; bu yüzden \\server\share\sub gibi tek aralık ters slash'lı UNC'ler
  # için yanlış pozitif/negatif üretebilir. is_windows_unc_path hem çift slash
  # hem de tek slash ağ yolu varyantlarını birlikte tanır; mevcutsa onu
  # kullanırız. Yoksa yedek olarak tüm ters slash'ları forward slash'a çevirip
  # yeniden test ederiz.
  is_unc <- FALSE
  if (exists("is_windows_unc_path", mode = "function", inherits = TRUE)) {
    is_unc <- tryCatch(
      isTRUE(is_windows_unc_path(path)),
      error = function(e) FALSE
    )
  }

  if (!isTRUE(is_unc)) {
    candidate_slash <- gsub("\\", "/", path, fixed = TRUE)
    is_unc <- grepl("^//[^/]+/[^/]+", candidate_slash, perl = TRUE)
  }

  if (isTRUE(is_unc)) {
    if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
      cozulen <- tryCatch(
        normalize_mcp_path(path, must_exist = must_exist),
        error = function(e) NA_character_
      )

      if (!is.na(cozulen) && nzchar(cozulen)) {
        cozulen_slash <- gsub("\\", "/", cozulen, fixed = TRUE)
        if (grepl("^//", cozulen_slash, perl = TRUE)) {
          return(sub("/+$", "", cozulen_slash, perl = TRUE))
        }
      }
    }

    cleaned <- gsub("\\", "/", path, fixed = TRUE)
    cleaned <- paste0("//", sub("^/+", "", cleaned))
    return(sub("/+$", "", cleaned, perl = TRUE))
  }

  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = isTRUE(must_exist)),
    error = function(e) {
      tryCatch(
        normalizePath(path, winslash = "/", mustWork = FALSE),
        error = function(e2) path
      )
    }
  )

  # NOT: normalizePath winslash="/" ile zaten forward slash üretir ama herhangi
  # bir karma slash kalırsa tek ters slash'a göre değiştirme yaparız (çiftli
  # gsub baştaki çift slash dışında diğer ters slash'ları kaçırırdı).
  sonuc <- gsub("\\", "/", sonuc, fixed = TRUE)
  sub("/+$", "", sonuc, perl = TRUE)
}

cc_policy_normalize_roots <- function(roots) {
  roots <- cc_policy_split_roots(roots)
  if (!length(roots)) return(character(0))

  roots <- vapply(
    roots,
    cc_policy_normalize_path,
    character(1),
    must_exist = FALSE,
    USE.NAMES = FALSE
  )

  unique(roots[nzchar(roots)])
}

cc_policy_default_user_workspace <- function(user_id = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% NA_integer_))

  if (is.na(user_id) || user_id <= 0L) {
    return("")
  }

  if (!exists("get_user_workspace", mode = "function", inherits = TRUE)) {
    return("")
  }

  tryCatch(
    get_user_workspace(user_id),
    error = function(e) ""
  )
}

cc_policy_allowed_workdir_roots <- function(user_id = NULL,
                                            extra_roots = character(0),
                                            allow_system_temp = FALSE) {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(
      configured,
      claude_code_config$allowed_workdir_roots %||% "",
      claude_code_config$default_workdir %||% ""
    )
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS", ""),
    cc_policy_default_user_workspace(user_id),
    extra_roots
  )

  if (isTRUE(allow_system_temp)) {
    configured <- c(configured, tempdir())
  }

  cc_policy_normalize_roots(configured)
}

cc_policy_allowed_output_roots <- function(user_id = NULL, workdir = "") {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(configured, claude_code_config$allowed_output_roots %||% "")
  }

  download_root <- if (exists("get_claude_code_download_root", mode = "function", inherits = TRUE)) {
    tryCatch(get_claude_code_download_root(), error = function(e) "")
  } else {
    ""
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_OUTPUT_ROOTS", ""),
    workdir %||% "",
    cc_policy_allowed_workdir_roots(user_id),
    download_root
  )

  cc_policy_normalize_roots(configured)
}

cc_policy_path_inside_roots <- function(path, roots, must_exist = FALSE) {
  hedef <- cc_policy_normalize_path(path, must_exist = must_exist)
  kokler <- cc_policy_normalize_roots(roots)

  if (!nzchar(hedef) || !length(kokler)) {
    return(FALSE)
  }

  hedef_key <- if (.Platform$OS.type == "windows") tolower(hedef) else hedef

  for (kok in kokler) {
    kok_key <- if (.Platform$OS.type == "windows") tolower(kok) else kok

    if (identical(hedef_key, kok_key) || startsWith(hedef_key, paste0(kok_key, "/"))) {
      return(TRUE)
    }
  }

  FALSE
}

cc_policy_validate_workdir <- function(workdir,
                                       user_id = NULL,
                                       extra_allowed_roots = character(0),
                                       allow_system_temp = FALSE,
                                       allow_selected_workdir = FALSE) {
  ham_yol <- as.character(workdir %||% "")[1]

  if (is.na(ham_yol) || !nzchar(ham_yol)) {
    return(list(
      ok = FALSE,
      path = "",
      error = "Çalışma dizini boş olamaz."
    ))
  }

  # UNC / Türkçe karakter / native encoding durumları için mevcut relaxed resolver'ı kullan.
  resolved_existing <- ""
  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    resolved_existing <- tryCatch(
      cc_resolve_existing_dir_relaxed(ham_yol),
      error = function(e) ""
    )
  }

  if (!nzchar(resolved_existing)) {
    aday_yol <- cc_policy_normalize_path(ham_yol, must_exist = FALSE)
    exists_base <- tryCatch(
      isTRUE(dir.exists(aday_yol)) || isTRUE(fs::dir_exists(aday_yol)),
      error = function(e) FALSE
    )

    if (isTRUE(exists_base)) {
      resolved_existing <- aday_yol
    }
  }

  if (!nzchar(resolved_existing)) {
    return(list(
      ok = FALSE,
      path = cc_policy_normalize_path(ham_yol, must_exist = FALSE),
      error = paste0("Çalışma dizini bulunamadı: ", ham_yol)
    ))
  }

  yol <- cc_policy_normalize_path(resolved_existing, must_exist = FALSE)

  selected_roots <- character(0)
  if (isTRUE(allow_selected_workdir)) {
    selected_roots <- yol
  }

  kokler <- cc_policy_allowed_workdir_roots(
    user_id = user_id,
    extra_roots = c(extra_allowed_roots, selected_roots),
    allow_system_temp = allow_system_temp
  )

  allowed_by_base_policy <- cc_policy_path_inside_roots(
    yol,
    cc_policy_allowed_workdir_roots(
      user_id = user_id,
      extra_roots = extra_allowed_roots,
      allow_system_temp = allow_system_temp
    ),
    must_exist = TRUE
  )

  if (!cc_policy_path_inside_roots(yol, kokler, must_exist = TRUE)) {
    return(list(
      ok = FALSE,
      path = yol,
      error = paste0(
        "Çalışma dizini güvenlik ilkesi tarafından engellendi: ",
        ham_yol,
        ". İzin verilen köklerden biri içinde bir klasör seçin veya ",
        "CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS ayarını açıkça yapılandırın."
      )
    ))
  }

  if (isTRUE(allow_selected_workdir) && !isTRUE(allowed_by_base_policy)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Çalışma dizini kullanıcı seçimiyle bu çalışma için onaylandı:",
      gsub("[{}]", "", yol)
    ))
  }

  list(ok = TRUE, path = yol, error = "")
}

cc_policy_filter_generated_file_paths <- function(file_paths,
                                                  allowed_roots,
                                                  context = "üretilen dosya") {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) {
    return(character(0))
  }

  izinli <- character(0)

  for (yol in file_paths) {
    yol_norm <- cc_policy_normalize_path(yol, must_exist = FALSE)

    if (!cc_policy_path_inside_roots(yol_norm, allowed_roots, must_exist = FALSE)) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        context,
        "izin verilen köklerin dışında olduğu için engellendi:",
        gsub("[{}]", "", yol_norm)
      ))
      next
    }

    izinli <- c(izinli, yol_norm)
  }

  unique(izinli)
}
