# Commit atfi icin baslangic/bitis checkout kimligi; ham dosya adlari yazilmaz.
# Git kimligi yalniz atif metadatasidir; uygulama/tarayici kosumunun on kosulu degildir.
evidence_checkout_snapshot <- function() {
  # GitHub kaynak ZIP'inde .git yoktur: Git cagrilmaz, ust dizin deposu da okunmaz.
  if (!file.exists(".git")) {
    return(list(sha = "", dirty = NA, verified = FALSE, available = FALSE))
  }
  read_git <- function(args) {
    out <- tryCatch(suppressWarnings(system2("git", args, stdout = TRUE, stderr = FALSE)),
                    error = function(e) structure(character(), status = 127L))
    if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) return(NULL)
    out
  }
  sha <- read_git(c("rev-parse", "--verify", "HEAD"))
  status <- read_git(c("status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none"))
  end_sha <- read_git(c("rev-parse", "--verify", "HEAD"))
  valid <- length(sha) == 1L && grepl("^[0-9a-f]{40}$", sha) &&
    identical(sha, end_sha) && !is.null(status)
  list(sha = if (isTRUE(valid)) unname(sha) else "",
       dirty = if (is.null(status)) NA else any(nzchar(status)), verified = isTRUE(valid),
       available = TRUE)
}

evidence_checkout_matches <- function(before, after) {
  isTRUE(before$verified) && isTRUE(after$verified) &&
    identical(before$dirty, FALSE) && identical(after$dirty, FALSE) &&
    identical(before$sha, after$sha)
}

# Kosumun kullandigi dosya (or. renv.lock) commit'e ait mi? Izlenen dosya + temiz
# checkout, calisan kopyanin HEAD ile ayni oldugunu gosterir. Yerel exclude ile
# gizlenen/kopyalanan kilit izlenmedigi icin atif kapsamina girmez.
evidence_checkout_file_committed <- function(path) {
  if (!file.exists(".git")) return(FALSE)
  out <- tryCatch(suppressWarnings(system2("git", c("ls-files", "--error-unmatch", "--", path),
                                           stdout = TRUE, stderr = FALSE)),
                  error = function(e) structure(character(), status = 127L))
  is.null(attr(out, "status")) && identical(out, path)
}

# Git metadatasi hic yoksa kosum surer; yalniz commit atfi yapilamaz.
evidence_checkout_unavailable <- function(snapshot) {
  identical(snapshot$available, FALSE)
}
