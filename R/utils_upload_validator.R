# ==============================================================================
# Dosya Yolu: R/utils_upload_validator.R
# Açıklama: Kullanıcı yüklemelerini kayıt altına almadan önce güvenlik ve
# boyut sınırlarını denetleyen yardımcılar. Üretim (Windows VM) ortamında
# libmagic gibi MIME kütüphaneleri bulunmadığı için içerik imzası (magic byte)
# yerine güvenli ve deterministik kontroller uygulanır:
#   - dosya varlığı ve okunabilirliği,
#   - en fazla N MB boyut sınırı,
#   - opsiyonel uzantı beyaz listesi,
#   - null bayt (NUL) içeren dosya adlarının reddi,
#   - path traversal giriş adlarının reddi (.., mutlak yol, backslash kaçağı),
#   - UTF-8 güvenli dosya adı (geçersiz çok baytlı dizi reddi).
# Fonksiyon yan etkisizdir; kararı list(ok=, error=, code=) olarak döndürür.
# ==============================================================================

# Bayt cinsinden üst sınırı MB üzerinden hesaplar.
.upload_mb_to_bytes <- function(mb) {
  as.numeric(mb) * 1024 * 1024
}

# Dosya adında ASCII denetim baytı olup olmadığını bayt düzeyinde denetler.
# POSIX [[:cntrl:]] + useBytes bazı Windows/R yerellerinde geçerli UTF-8 Türkçe
# karakterleri yanlışlıkla riskli sayabildiği için burada ham bayt kontrolü yapılır.
.upload_has_control_bytes <- function(name) {
  bytes <- charToRaw(as.character(name)[1])
  any(as.integer(bytes) %in% c(0:31, 127))
}

# Dosya adında Unicode iki-yönlü (bidi) kontrol/override karakteri olup
# olmadığını denetler. U+200E/200F, U+202A-202E ve U+2066-2069 karakterleri
# "Trojan Source" / sağdan-sola override saldırılarında gerçek uzantıyı gizlemek
# için kullanılır (örn. "fatura<U+202E>cod.exe" ekranda "faturaexe.doc" görünür).
# Bu karakterlerin meşru dosya adlarında hiçbir kullanımı yoktur; Türkçe metin de
# içermez. Kod nokta düzeyinde denetlenir, böylece geçerli UTF-8 Türkçe etkilenmez.
.upload_has_bidi_control <- function(name) {
  kod_noktalari <- utf8ToInt(enc2utf8(as.character(name)[1]))
  if (length(kod_noktalari) == 0L || anyNA(kod_noktalari)) return(FALSE)
  bidi <- c(0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069)
  any(kod_noktalari %in% bidi)
}

# Dosya adını normalleştirerek path traversal denemesi olup olmadığını anlar.
# Beklenen: basename(name) ile birebir eşleşmesi. Aksi takdirde "/", "\" veya
# ".." ile kaçış yapılmaya çalışılmıştır. Bidi override karakterleri de güvensiz
# sayılır (uzantı gizleme / görsel spoofing).
.upload_has_traversal <- function(name) {
  if (!nzchar(name)) return(TRUE)
  if (.upload_has_control_bytes(name)) return(TRUE)
  if (.upload_has_bidi_control(name)) return(TRUE)
  if (grepl("\\.\\.", name, fixed = FALSE)) return(TRUE)
  if (grepl("/", name, fixed = TRUE)) return(TRUE)
  if (grepl("\\\\", name, fixed = FALSE)) return(TRUE)
  # Windows mutlak yolu (C:\ gibi) ve POSIX mutlak yolu.
  if (grepl("^[A-Za-z]:", name)) return(TRUE)
  if (substr(name, 1, 1) == "/" || substr(name, 1, 1) == "\\") return(TRUE)
  FALSE
}

# Windows ayrılmış aygıt adları (CON, PRN, AUX, NUL, COM1-9, LPT1-9): uzantı
# olsa bile Windows'ta gerçek dosya oluşmaz; yükleme içeriği sessizce kaybolur.
# Windows üst simge rakamlarını (U+00B9 / U+00B2 / U+00B3) da aygıt numarası
# olarak çözer; COM<üst simge 1>.txt gibi adlar da ayrılmıştır.
.upload_is_windows_reserved_name <- function(name) {
  # `trimws()` yalnızca adın BAŞINDAKİ/SONUNDAKİ boşlukları kaldırır; uzantı
  # atıldıktan sonra gövdede kalan boşluk (`NUL .txt` -> `"NUL "`) ayrılmış
  # aygıt listesiyle eşleşmiyordu. Windows ad bileşeninin sonundaki noktalar da
  # yok sayılır.
  govde <- trimws(sub("\\..*$", "", trimws(as.character(name)[1])))
  govde <- sub("\\.+$", "", govde)
  govde <- chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", govde)
  # Üst simge rakamlar sıradan rakama indirgenir (kaçış dizisi kullanılır:
  # bu karakterlerin bir kısmının CP1254 karşılığı yoktur - CLAUDE.md 1G).
  govde <- chartr("\u00B9\u00B2\u00B3", "123", govde)
  govde %in% c("CON", "PRN", "AUX", "NUL", paste0("COM", 1:9), paste0("LPT", 1:9))
}

# Dosya adının UTF-8 geçerli olup olmadığını test eder. Geçersiz çok baytlı
# dizi iconv tarafından NA olarak raporlanır.
.upload_filename_is_utf8 <- function(name) {
  donusturulmus <- suppressWarnings(iconv(name, from = "UTF-8", to = "UTF-8"))
  !is.na(donusturulmus)
}

# Uzantıyı küçük harfe çevirerek döndürür; uzantı yoksa "" döner.
.upload_extract_ext <- function(name) {
  parts <- strsplit(name, "\\.", fixed = FALSE)[[1]]
  if (length(parts) <= 1L) return("")
  tolower(parts[length(parts)])
}

# Ana doğrulama fonksiyonu.
# path:         fiziksel olarak diskte var olan (veya en azından erişilebilir) yol
# filename:     kullanıcının sunduğu görünen ad; varsayılan basename(path)
# max_size_mb:  üst boyut sınırı; NULL verilirse sınır uygulanmaz
# allowed_ext:  uzantı beyaz listesi (nokta olmadan, küçük harf); NULL ise tümü kabul
#
# Döndürdüğü liste: list(ok = TRUE/FALSE, error = "<mesaj>" | NULL, code = "<kod>" | NULL)
# code değerleri: "missing_path", "not_readable", "too_large", "bad_filename",
#                 "bad_encoding", "ext_not_allowed"
validate_uploaded_file <- function(path,
                                   filename = NULL,
                                   max_size_mb = getOption("mergen.upload_max_mb", 25L),
                                   allowed_ext = NULL) {
  if (is.null(path) || !is.character(path) || length(path) != 1L || !nzchar(path)) {
    return(list(ok = FALSE, error = "Yol parametresi boş veya geçersiz.", code = "missing_path"))
  }

  # filename parametresi Shiny/file input dışından testlerde veya yardımcı
  # çağrılarda character(0), NA veya vektör olarak gelebilir. Tek, güvenli
  # görünen ada indir; boş/NA ise fiziksel yolun basename değerine düş.
  if (is.null(filename) ||
      length(filename) == 0L ||
      is.na(filename[1]) ||
      !nzchar(as.character(filename[1]))) {
    filename <- basename(path)
  } else {
    filename <- as.character(filename[1])
  }

  if (!file.exists(path)) {
    return(list(ok = FALSE, error = "Dosya bulunamadı.", code = "missing_path"))
  }

  # Okunabilirlik kontrolü (Windows ACL'lerinde normal file.exists yetmeyebilir).
  okunabilir <- file.access(path, mode = 4L) == 0L
  if (!isTRUE(okunabilir)) {
    return(list(ok = FALSE, error = "Dosya okunamıyor (izin yok).", code = "not_readable"))
  }

  # UTF-8 güvenliği.
  if (!.upload_filename_is_utf8(filename)) {
    return(list(ok = FALSE, error = "Dosya adı UTF-8 olarak geçerli değil.", code = "bad_encoding"))
  }

  # Path traversal / NUL kontrolü.
  if (.upload_has_traversal(filename)) {
    return(list(
      ok = FALSE,
      error = "Dosya adı güvenli değil: path karakterleri veya çıkış denemesi.",
      code = "bad_filename"
    ))
  }

  # Windows normal dosya adlarında `< > : " | ? *` karakterlerine izin vermez;
  # doğrulama "başarılı" bildirdikten SONRA kalıcı kopyalama hata veriyordu.
  # `:` de listededir: sürücü öneki denetimi yalnızca BAŞTAKİ `X:` biçimini
  # yakaladığı için `rapor:final.txt` doğrulamadan geçiyordu (Windows'ta bu ad
  # alternatif veri akışı sözdizimidir ve kopyalama hata verir).
  if (grepl("[<>:\"|?*]", filename, perl = TRUE)) {
    return(list(
      ok = FALSE,
      error = "Dosya adı Windows'ta geçersiz karakter içeriyor.",
      code = "bad_filename"
    ))
  }

  if (.upload_is_windows_reserved_name(filename)) {
    return(list(
      ok = FALSE,
      error = "Dosya adı Windows'ta ayrılmış bir aygıt adı (CON, NUL, COM1 vb.).",
      code = "bad_filename"
    ))
  }

  # Boyut sınırı.
  if (!is.null(max_size_mb)) {
    max_size_mb <- suppressWarnings(as.numeric(max_size_mb[1]))

    if (is.na(max_size_mb) || max_size_mb <= 0) {
      return(list(
        ok = FALSE,
        error = "Dosya boyutu sınırı geçersiz.",
        code = "bad_max_size"
      ))
    }

    finfo <- suppressWarnings(file.info(path))
    size_bytes <- as.numeric(finfo$size[1])
    if (is.na(size_bytes)) size_bytes <- 0

    if (size_bytes > .upload_mb_to_bytes(max_size_mb)) {
      return(list(
        ok = FALSE,
        error = sprintf(
          "Dosya boyutu sınırı aşıldı (%.1f MB > %.0f MB).",
          size_bytes / (1024 * 1024),
          max_size_mb
        ),
        code = "too_large"
      ))
    }
  }

  # Uzantı beyaz listesi.
  if (!is.null(allowed_ext) && length(allowed_ext) > 0L) {
    normalized <- tolower(gsub("^\\.+", "", as.character(allowed_ext)))
    ext <- .upload_extract_ext(filename)
    if (!nzchar(ext) || !(ext %in% normalized)) {
      return(list(
        ok = FALSE,
        error = sprintf("Dosya uzantısı '%s' izin verilen listede değil.", ext),
        code = "ext_not_allowed"
      ))
    }
  }

  list(ok = TRUE, error = NULL, code = NULL)
}