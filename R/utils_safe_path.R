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
#   - Son birleşik yol denetimi base_dir'in altında değilse NULL döner.
#   - Güvenli durumda base_dir altında kurulmuş mutlak yol döner.
safe_join_path <- function(base_dir, user_segment) {
  if (is.null(base_dir) || !is.character(base_dir) || length(base_dir) != 1L || !nzchar(base_dir)) {
    return(NULL)
  }
  if (is.null(user_segment) || length(user_segment) != 1L) {
    return(NULL)
  }
  # Tür normalizasyonu boşluk/NA denetiminden ÖNCE gelir; karakter olmayan
  # girdi hata yerine NULL üretir.
  if (!is.character(user_segment)) {
    user_segment <- tryCatch(as.character(user_segment), error = function(e) NA_character_)
  }
  # `nzchar("   ")` TRUE döner ve nokta-parça denetimi de bunu kabul ediyordu;
  # sonuç, dosya sistemi işlemlerinde geçersiz bir yol bileşeniydi (Windows).
  if (length(user_segment) != 1L || is.na(user_segment) ||
      !nzchar(trimws(user_segment))) {
    return(NULL)
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

  # Windows ad bileşeninin SONUNDAKİ boşluk ve noktaları YOK SAYAR: `"rapor "`
  # ile `"rapor"` aynı dosyaya çözülür ve çağıranın istediğinden FARKLI bir
  # dosya hedeflenebilir/üzerine yazılabilir. Bu bileşenler reddedilir.
  if (any(grepl("[ .]$", parcalar))) return(NULL)

  # Güvenli göreli yolu tek tip ayraçla yeniden kur.
  goreli_yol <- paste(parcalar, collapse = "/")

  # Sadece mevcut taban dizini normalize et. Windows'ta henüz var olmayan alt
  # yol üzerinde normalizePath() çağrısı güvenli girdileri gereksiz yere NULL'a
  # düşürebilir.
  base_norm <- tryCatch(
    normalizePath(base_dir, winslash = "/", mustWork = FALSE),
    error = function(e) NULL
  )
  if (is.null(base_norm) || !nzchar(base_norm)) return(NULL)

  # Sonda fazla slash kalırsa temizle ve hedef yolu string düzeyinde kur.
  base_bitis <- sub("/+$", "", base_norm)
  hedef_norm <- paste0(base_bitis, "/", goreli_yol)

  # Son savunma hattı: hedef mutlaka normalize edilmiş tabanın altında kalmalı.
  if (!startsWith(paste0(hedef_norm, "/"), paste0(base_bitis, "/"))) {
    return(NULL)
  }

  hedef_norm
}