# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_prompt_security_policy.R
# Açıklama: Bilge Yolaç prompt içindeki dosya yolu niyetlerini denetler.
#           Çalışma dizini dışına açık yazma/düzenleme/silme isteklerini
#           CLI başlamadan önce engellemek için güvenlik ilkesini genişletir.
# ==============================================================================

cc_policy_prompt_has_write_intent <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  yazma_deseni <- paste(
    c(
      "oluştur",
      "olustur",
      "yarat",
      "üret",
      "uret",
      "hazırla",
      "hazirla",
      "kaydet",
      "yaz",
      "düzenle",
      "duzenle",
      "değiştir",
      "degistir",
      "sil",
      "kopyala",
      "taşı",
      "tasi",
      "yeniden adlandır",
      "yeniden adlandir",
      "\\bwrite\\b",
      "\\bcreate\\b",
      "\\bsave\\b",
      "\\bedit\\b",
      "\\bpatch\\b",
      "\\bdelete\\b",
      "\\bremove\\b",
      "\\bcopy\\b",
      "\\bmove\\b",
      "\\brename\\b",
      "\\btouch\\b",
      "\\bmkdir\\b",
      "\\brm\\b"
    ),
    collapse = "|"
  )

  grepl(yazma_deseni, metin, perl = TRUE)
}

cc_policy_extract_path_like_tokens <- function(prompt) {
  metin <- enc2utf8(paste(as.character(prompt %||% ""), collapse = " "))
  if (!nzchar(metin)) return(character(0))

  desenler <- c(
    "[A-Za-z]:[\\\\/][^\\s\"'<>|]+(?:[\\\\/][^\\s\"'<>|]+)*",
    "(?<!:)(?:\\\\\\\\|//)[^\\s\"'<>|]+",
    "(?:^|\\s)(/[^\\s\"'<>|]+(?:/[^\\s\"'<>|]+)*)",
    "(?:^|\\s)(\\.\\.[\\\\/][^\\s\"'<>|]+)"
  )

  eslesmeler <- character(0)

  for (desen in desenler) {
    bulunan <- gregexpr(desen, metin, perl = TRUE)
    parcalar <- regmatches(metin, bulunan)[[1]]
    if (length(parcalar) && !identical(parcalar, character(0))) {
      eslesmeler <- c(eslesmeler, parcalar)
    }
  }

  eslesmeler <- trimws(eslesmeler)
  eslesmeler <- sub("[,.;:!?]+$", "", eslesmeler, perl = TRUE)
  eslesmeler <- eslesmeler[nzchar(eslesmeler)]

  unique(eslesmeler)
}

cc_policy_path_is_absolute <- function(path) {
  yol <- as.character(path %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return(FALSE)

  yol <- gsub("\\", "/", yol, fixed = TRUE)

  isTRUE(
    grepl("^[A-Za-z]:/", yol, perl = TRUE) ||
      startsWith(yol, "/") ||
      startsWith(yol, "//")
  )
}

cc_policy_validate_prompt_file_intent <- function(prompt,
                                                  workdir = "",
                                                  user_id = NULL,
                                                  allowed_roots = character(0)) {
  if (!cc_policy_prompt_has_write_intent(prompt)) {
    return(list(ok = TRUE, error = "", blocked_paths = character(0)))
  }

  path_tokens <- cc_policy_extract_path_like_tokens(prompt)

  if (!length(path_tokens)) {
    return(list(ok = TRUE, error = "", blocked_paths = character(0)))
  }

  workdir_norm <- cc_policy_normalize_path(workdir, must_exist = FALSE)

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = workdir_norm
    )
  }

  blocked <- character(0)

  for (token in path_tokens) {
    token_norm <- token

    if (!cc_policy_path_is_absolute(token_norm)) {
      if (!nzchar(workdir_norm)) {
        blocked <- c(blocked, token)
        next
      }

      token_norm <- file.path(workdir_norm, token_norm)
    }

    hedef <- cc_policy_normalize_path(token_norm, must_exist = FALSE)

    if (!cc_policy_path_inside_roots(
      hedef,
      allowed_roots,
      must_exist = FALSE
    )) {
      blocked <- c(blocked, token)
    }
  }

  blocked <- unique(blocked[nzchar(blocked)])

  if (!length(blocked)) {
    return(list(ok = TRUE, error = "", blocked_paths = character(0)))
  }

  list(
    ok = FALSE,
    error = paste0(
      "Bu istek güvenlik ilkesi tarafından engellendi. ",
      "Bilge Yolaç yalnızca seçili çalışma dizini veya açıkça izin verilen ",
      "çıktı kökleri içinde dosya oluşturabilir/düzenleyebilir. Engellenen yol: ",
      paste(blocked, collapse = ", ")
    ),
    blocked_paths = blocked
  )
}