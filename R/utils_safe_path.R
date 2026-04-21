# ==============================================================================
# Dosya Yolu: R/utils_safe_path.R
# Açıklama: Kullanıcı girdisiyle gelen parça yollarını mutlak taban dizinin
# ALTINDA birleştirmek için güvenli yardımcı. Amaç: path traversal (..),
# mutlak yol kaçışı (C:\ veya /etc/...) ve NUL bayt girişleriyle tabanın
# dışına çıkılmasını engellemek. Windows VM üzerinde hem ters hem düz slash
# normalize edilir. Aynı kodun her dosya modülünde ayrı ayrı yazılması yerine
# tek bir noktadan kullanılması, regresyonları azaltır.
# ==============================================================================

# base_dir altında user_segment birleşimini döndürür.
#   - user_segment NULL, boş, NA, NUL içeren, ".." içeren veya mutlak yol ise NULL
#     döner. Böylece çağıran taraf basit bir is.null() kontrolüyle güvenliği
#     denetleyebilir.
#   - Normalize sonrası yol gerçekten base_dir'in altında değilse de NULL döner.
#   - Güvenli durumda normalize edilmiş mutlak yol döner.
safe_join_path <- function(base_dir, user_segment) {
  if (is.null(base_dir) || !is.character(base_dir) || length(base_dir) != 1L || !nzchar(base_dir)) {
    return(NULL)
  }
  if (is.null(user_segment) || length(user_segment) != 1L) {
    return(NULL)
  }
  if (is.na(user_segment) || !nzchar(user_segment)) {
    return(NULL)
  }
  if (!is.character(user_segment)) {
    user_segment <- tryCatch(as.character(user_segment), error = function(e) "")
    if (!nzchar(user_segment)) return(NULL)
  }

  # NUL bayt tespiti (binary-safe).
  if (grepl("\\x00", user_segment, useBytes = TRUE)) return(NULL)

  # Slash normalize: Windows'tan gelen ters slashları önce düz slasha çevir.
  seg_norm <- gsub("\\\\", "/", user_segment, fixed = FALSE)

  # Mutlak yol reddedilir: POSIX mutlak (/...) veya Windows sürücü harfi (C:/, C:\).
  if (substr(seg_norm, 1, 1) == "/") return(NULL)
  if (grepl("^[A-Za-z]:", seg_norm)) return(NULL)

  # ".." segmenti (parça sınırları içinde) reddedilir.
  parcalar <- strsplit(seg_norm, "/", fixed = TRUE)[[1]]
  parcalar <- parcalar[nzchar(parcalar)]
  if (any(parcalar == "..")) return(NULL)

  # Herhangi bir parça yalnızca nokta veya whitespace ise reddet (Windows
  # ".", "..", " " gibi özel isimler rezerve olabilir).
  if (any(grepl("^\\s*\\.+\\s*$", parcalar))) return(NULL)

  birlesim <- file.path(base_dir, paste(parcalar, collapse = "/"))

  # Normalize. mustWork = FALSE: hedef henüz oluşturulmamış da olabilir.
  base_norm <- tryCatch(
    normalizePath(base_dir, winslash = "/", mustWork = FALSE),
    error = function(e) NULL
  )
  hedef_norm <- tryCatch(
    normalizePath(birlesim, winslash = "/", mustWork = FALSE),
    error = function(e) NULL
  )
  if (is.null(base_norm) || is.null(hedef_norm)) return(NULL)

  # base_norm'un sonunda '/' yoksa ekle ki startsWith doğru eşleşsin.
  base_bitis <- if (endsWith(base_norm, "/")) base_norm else paste0(base_norm, "/")

  if (!startsWith(paste0(hedef_norm, "/"), base_bitis)) {
    return(NULL)
  }

  hedef_norm
}
