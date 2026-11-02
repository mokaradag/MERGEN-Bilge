# Commit atfi icin baslangic/bitis checkout kimligi; ham dosya adlari yazilmaz.
evidence_checkout_snapshot <- function() {
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
       dirty = if (is.null(status)) NA else any(nzchar(status)), verified = isTRUE(valid))
}

evidence_checkout_matches <- function(before, after) {
  isTRUE(before$verified) && isTRUE(after$verified) &&
    identical(before$dirty, FALSE) && identical(after$dirty, FALSE) &&
    identical(before$sha, after$sha)
}
