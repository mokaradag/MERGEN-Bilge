# ==============================================================================
# Dosya Yolu: tests/scripts/maintainability_report.R
# Açıklama: Büyük R dosyalarını, fonksiyon sayısını ve yaklaşık satır sayılarını
# raporlar. Bu script test değildir; üretim refactor planı için güvenli rapordur.
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "R"))) {
  stop("Bu script repo kökünden çalıştırılmalıdır.", call. = FALSE)
}

read_text <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

# Repo kökü önekini ayırır ve repoya GÖRE yolu döndürür.
#
# Eski sürüm öneki PCRE ile ayırıyordu:
#   sub(paste0("^", <kaçışlı repo_root>), "", normalizePath(path), perl = TRUE)
# Windows VM'de repo kökü bir UNC paylaşımıdır ve Türkçe karakter içerir
# ("//sunucu/.../04 - Geliştirme/MERGEN Bilge"). Desen ile hedef dizenin
# kodlama işaretleri ayrışabildiği için PCRE eşleşmesi SESSİZCE boşa düşüyor,
# önek ayrılmıyor ve `file` sütununda MUTLAK yol kalıyordu. Bu da
# `report$file == "R/x.R"` biçimindeki TAM eşitlik aramalarını bozuyordu
# (sonek eşleşmesi kullanan testler etkilenmediği için sorun uzun süre
# görünmez kaldı). Aşağıdaki yaklaşım regex kullanmaz; her iki tarafı da
# `enc2utf8()` ile aynı kodlamaya getirir ve `startsWith()` ile karşılaştırır.
# Aynı yöntem `tests/scripts/frontend_maintainability_report.R` içinde
# zaten VM'de doğrulanmış durumdadır.
# DEPO KÖKÜ BİR KEZ NORMALLEŞTİRİLİR. `relative_path()` keşfedilen HER dosya
# için çağrılıyor; kökü her çağrıda yeniden `normalizePath()` etmek Windows UNC
# çalışma kopyasında dosya başına bir AĞ GİDİŞ-DÖNÜŞÜ demektir.
repo_root_norm <- enc2utf8(normalizePath(repo_root, winslash = "/", mustWork = TRUE))
# SONDAKİ AYIRICI KIRPILIR: kök `C:/` ya da `//sunucu/pay/` biçiminde gelirse
# `paste0(kok, "/")` ÇİFT ayırıcı üretir, hiçbir yol öneki eşleşmez ve `file`
# sütununda MUTLAK yol kalır. Bu, `report$file == "R/x.R"` biçimindeki tam
# eşitlik aramalarının tamamını sessizce bozar.
repo_root_norm <- sub("/+$", "", repo_root_norm)
if (!nzchar(repo_root_norm)) repo_root_norm <- "/"

relative_path <- function(path) {
  path_norm <- enc2utf8(normalizePath(path, winslash = "/", mustWork = TRUE))

  # DOSYA SİSTEMİ KÖKÜ AYRI ELE ALINIR: kök `/` ise `paste0(kok, "/")` `//`
  # üretir, `/app.R` hiçbir önek dalına uymaz ve `relative_path()` MUTLAK yol
  # döndürür -- raporun göreli-dosya sözleşmesi bozulur.
  root_prefix <- if (identical(repo_root_norm, "/")) "/" else paste0(repo_root_norm, "/")

  if (startsWith(path_norm, root_prefix)) {
    return(substring(path_norm, nchar(root_prefix) + 1L))
  }

  # Windows/ağ yolu güvenliği: büyük/küçük harf farkı olsa da aynı öneki ayır.
  if (startsWith(tolower(path_norm), tolower(root_prefix))) {
    return(substring(path_norm, nchar(root_prefix) + 1L))
  }

  path_norm
}

runtime_files <- c(
  file.path(repo_root, "app.R"),
  file.path(repo_root, "global.R"),
  file.path(repo_root, "ui.R"),
  file.path(repo_root, "server.R"),
  file.path(repo_root, "welcome_screen.R"),
  list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
)

runtime_files <- unique(runtime_files[file.exists(runtime_files)])

report <- lapply(runtime_files, function(path) {
  txt <- read_text(path)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

  function_count <- length(gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]])

  if (identical(function_count, 1L) &&
      identical(gregexpr("(<-|=)\\s*function\\s*\\(", txt, perl = TRUE)[[1]][1], -1L)) {
    function_count <- 0L
  }

  data.frame(
    file = relative_path(path),
    lines = length(lines),
    functions = function_count,
    stringsAsFactors = FALSE
  )
})

report <- do.call(rbind, report)
report <- report[order(report$lines, decreasing = TRUE), ]

print(utils::head(report, 30), row.names = FALSE)

cat("\nRefactor adayları:\n")

# library_queries.R bilgi tabanı; library_query_meta*.R dosyaları ise sorgu
# kütüphanesinin metadata katmanıdır (curated meta, tracked auto iskelet ve
# yerelde üretilen gitignore'lu local artefakt). Üretim VM'indeki gerçek
# kütüphane on binlerce satıra ulaşabildiği için bu dosyalar bilinçli olarak
# büyük kalabilir ve ratchet skoruna dahil edilmez.
score_report <- subset(
  report,
  !grepl("(^|/)(library_queries|library_query_meta(_auto|_local)?)\\.R$", file, perl = TRUE)
)

candidates <- subset(score_report, lines >= 800 | functions >= 25)
print(candidates, row.names = FALSE)

total_files <- nrow(score_report)
large_files <- sum(score_report$lines >= 800)
large_function_files <- sum(score_report$functions >= 25)
very_large_files <- sum(score_report$lines >= 1500)
max_lines <- max(score_report$lines, na.rm = TRUE)
max_functions <- max(score_report$functions, na.rm = TRUE)

# 100 üzerinden basit, izlenebilir ve tartışılabilir bir bakım skoru.
# Amaç mutlak kaliteyi ölçmek değil; refactor yönünün iyileşip iyileşmediğini
# her koşumda görünür hale getirmektir.
maintainability_score <- 100 -
  (large_files * 3) -
  (large_function_files * 2) -
  (very_large_files * 5)

maintainability_score <- max(0, min(100, maintainability_score))

cat("\nMaintainability özeti:\n")
cat(sprintf("- Skor: %d/100\n", maintainability_score))
cat(sprintf("- Değerlendirilen dosya sayısı: %d\n", total_files))
cat(sprintf("- 800+ satır dosya sayısı: %d\n", large_files))
cat(sprintf("- 25+ fonksiyon dosya sayısı: %d\n", large_function_files))
cat(sprintf("- 1500+ satır dosya sayısı: %d\n", very_large_files))
cat(sprintf("- En büyük dosya satırı: %d\n", max_lines))
cat(sprintf("- En yüksek fonksiyon sayısı: %d\n", max_functions))

attr(report, "maintainability_score") <- maintainability_score
attr(report, "score_report") <- score_report

invisible(report)