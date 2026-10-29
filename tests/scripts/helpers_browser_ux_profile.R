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
