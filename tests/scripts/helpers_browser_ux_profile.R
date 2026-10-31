# Kalici SSO profili repo/kanit agacina cookie yazamaz. Iki runner ayni kapiyi kullanir.
ux_smoke_path_within <- function(path, root, windows = .Platform$OS.type == "windows") {
  if (windows) {
    path <- tolower(chartr("\\", "/", path))
    root <- tolower(chartr("\\", "/", root))
  }
  root <- sub("/+$", "", root)
  identical(sub("/+$", "", path), root) || startsWith(path, paste0(root, "/"))
}

ux_smoke_profile_path <- function(path, roots) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  # Profil zaten vardir; var olmayan bir kok onun atasi olamaz.
  roots <- roots[nzchar(roots) & dir.exists(roots)]
  for (root in roots) {
    root <- normalizePath(root, winslash = "/", mustWork = TRUE)
    if (ux_smoke_path_within(path, root)) {
      stop("The dedicated profile must be outside the repository and artifacts.", call. = FALSE)
    }
  }
  path
}

ux_smoke_redact_profile <- function(text, profile = Sys.getenv("MERGEN_BROWSER_UX_PROFILE_DIR", "")) {
  values <- c(profile, Sys.getenv(c("USERPROFILE", "LOCALAPPDATA"), ""))
  values <- values[nzchar(trimws(values))]
  values <- unique(c(values, chartr("\\", "/", values), chartr("/", "\\", values),
                     vapply(values, function(v) encodeString(v, quote = ""), character(1)),
                     vapply(values, utils::URLencode, character(1), reserved = TRUE)))
  for (value in values[order(nchar(values), decreasing = TRUE)]) {
    text <- gsub(value, "<BROWSER_PROFILE>", text, fixed = TRUE)
  }
  text
}

ux_smoke_check_edge_policy <- function(windows = .Platform$OS.type == "windows") {
  if (!windows) return(invisible(TRUE))
  # Zorunlu ilke komut satırı profilini ezer; değerini okumadan kapalı kal.
  script <- paste(
    "$ErrorActionPreference='Stop'; try {",
    "foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {",
    "foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {",
    "$root=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view);",
    "try { $key=$root.OpenSubKey('SOFTWARE\\Policies\\Microsoft\\Edge');",
    "if ($null -ne $key) { try { if ($key.GetValueNames() -contains 'UserDataDir') { exit 2 } } finally { $key.Dispose() } }",
    "} finally { $root.Dispose() } } };",
    "Write-Output 'UX_SMOKE_EDGE_POLICY_OK'; exit 0 } catch { exit 3 }"
  )
  result <- tryCatch(processx::run("powershell.exe", c("-NoProfile", "-NonInteractive", "-Command", script),
                                 echo = FALSE, error_on_status = FALSE, timeout = 20),
                     error = function(e) NULL)
  if (is.null(result) || !identical(result$status, 0L) ||
      !identical(trimws(result$stdout), "UX_SMOKE_EDGE_POLICY_OK")) {
    stop("Dedicated Edge profile cannot be verified: UserDataDir policy is set or policy inspection failed. No browser was launched.", call. = FALSE)
  }
  invisible(TRUE)
}
