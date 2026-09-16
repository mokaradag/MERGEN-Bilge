# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_resolver.R
# Açıklama: Bilge Yolaç runtime çalışma dizini için relaxed kaynak dizin
#           çözümleme yardımcıları.
# ==============================================================================

# Adayın gerçekten DİZİN olduğunu doğrular: `path_exists_relaxed()` dosyaları da
# "var" sayar ve kaynak dizin çözümünde dosya yolu hatalı çalışma dizini üretir.
.cc_runtime_dizin_mi <- function(aday) {
  # `file.exists()` DOSYA ile DİZİNİ ayırmaz. Eski kısa devre, UNC üzerinde
  # `file.exists()` TRUE / `dir.exists()` FALSE dönen GEÇERLİ bir dizini de
  # reddediyor ve aynalama atlanıyordu. Tür bilgisi `file.info()$isdir` ile
  # alınır; yalnızca AÇIKÇA dosya olduğu belirlenen yol reddedilir.
  isdir <- tryCatch(file.info(aday)$isdir[1], error = function(e) NA)
  if (isTRUE(identical(isdir, FALSE))) return(FALSE)

  # Denetimler AYRI korunur. Ortak `tryCatch` içinde `fs::dir_exists()` hata
  # verdiğinde (`fs` zorunlu paket listesinde değildir) relaxed denetime hiç
  # ulaşılmıyor ve `dir.exists()` FALSE dönen GEÇERLİ bir UNC dizini
  # reddediliyordu; kaynak dizin boş çözülünce aynalama atlanıyordu.
  guvenli <- function(ifade) isTRUE(tryCatch(ifade, error = function(e) FALSE))

  guvenli(dir.exists(aday)) ||
    guvenli(fs::dir_exists(aday)) ||
    guvenli(path_exists_relaxed(aday))
}

# Runtime aynalama için mevcut dizini relaxed şekilde çözer
resolve_claude_runtime_source_dir <- function(workdir) {
  ham_yol <- as.character(workdir %||% "")[1]
  if (is.na(ham_yol) || !nzchar(ham_yol)) {
    return("")
  }

  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    relaxed <- tryCatch(
      cc_resolve_existing_dir_relaxed(ham_yol),
      error = function(e) ""
    )

    # BİRİNCİL sonuç da DİZİN olarak doğrulanır. Paylaşılan relaxed çözümleyici,
    # `dir.exists()`/`fs::dir_exists()` başarısız olup `path_exists_relaxed()`
    # başarılı olduğunda bir DOSYA yolunu kabul edebiliyor; erken dönüş
    # aşağıdaki dizin denetimini atlıyor ve dosya yolu runtime çalışma dizini
    # olarak kullanılıyordu (UNC/native yol durumunda ulaşılabilir).
    if (nzchar(relaxed) && .cc_runtime_dizin_mi(relaxed)) {
      return(relaxed)
    }
  }

  # NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
  # eşler. `\\server\share\sub` girdisini kanonik `//server/share/sub` formuna
  # çevirebilmek için tek ters slash'a göre değiştirme yaparız.
  yol_slash <- gsub("\\", "/", ham_yol, fixed = TRUE)

  adaylar <- unique(Filter(nzchar, c(
    ham_yol,
    yol_slash,
    enc2utf8(yol_slash),
    enc2native(yol_slash),
    if (grepl("^/[^/]", yol_slash) && !grepl("^//", yol_slash)) {
      paste0("/", yol_slash)
    } else {
      NULL
    },
    tryCatch(normalize_mcp_path(ham_yol, must_exist = FALSE), error = function(e) ""),
    tryCatch(normalize_mcp_path(yol_slash, must_exist = FALSE), error = function(e) "")
  )))

  for (aday in adaylar) {
    # path_exists_relaxed() dosyaları da "var" sayar; kaynak DİZİN çözümünde
    # bir dosya yolunun dizin gibi kabul edilmesi hatalı çalışma dizini üretirdi.
    if (!isTRUE(.cc_runtime_dizin_mi(aday))) next

    return(tryCatch(
      normalize_mcp_path(aday, must_exist = FALSE),
      error = function(e) aday
    ))
  }

  ""
}