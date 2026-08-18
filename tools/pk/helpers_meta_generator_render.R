# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_render.R
# Açıklama: Faz 3b metadata üreticisi -- R kaynağı üretimi ve ATOMİK yazma.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# UÇ SERT KURAL:
#   1) YASAKLI HEDEF KAPISI. Üretici YALNIZCA R/library_query_meta_local.R
#      dosyasına yazabilir. Operatörün alias dosyası ve izlenen metadata
#      dosyaları çalışma zamanında REDDEDİLİR (yorum değil, kapı). Kapı
#      TEMEL ADA DEĞİL, TAM YOLA bakar.
#   2) ÜRETİLEN KAYNAK SAF ASCII'DIR. ASCII dışı her karakter "\uXXXX" kaçışıyla
#      yazılır. Windows VM'de R'in yerel kod sayfası WINDOWS-1254'tür ve
#      `source(..., encoding = "UTF-8")` dosyayı o sayfaya çevirir; CP1254'te
#      karşılığı olmayan TEK bir karakter dosyayı O NOKTADA KESER (CLAUDE.md
#      §1G). Saf ASCII çıktı bu sınıfın tamamını imkânsız kılar.
#   3) YERİNE GEÇİŞ ATOMİKTİR. Yazma AYRI iki adıma bölünür: HAZIRLA (geçici
#      dosyaya yaz + parse + ASCII doğrula) ve YAYIMLA (yerine taşı). Böylece
#      çağıran, zorunlu denetim artefaktlarını YAZDIKTAN SONRA yayımlayabilir;
#      artefakt yazımı düşerse üretimden türetilmiş metadata devreye ALINMAZ.
# ==============================================================================

#' ASCII-güvenli R karakter sabiti üret
#'
#' ASCII dışı her kod noktası kaçışla yazılır; sonuç dizesi DEĞİŞMEZ.
#' BMP dışı kod noktaları için 8 haneli `\U` biçimi kullanılır.
pkgr_encode_string <- function(x) {
  if (is.na(x)) return("NA_character_")

  metin <- enc2utf8(as.character(x)[1])
  kod_noktalari <- utf8ToInt(metin)
  if (is.null(kod_noktalari)) return("\"\"")

  parcalar <- vapply(kod_noktalari, function(kod) {
    if (kod == 92L) return("\\\\")      # ters bölü
    if (kod == 34L) return("\\\"")      # çift tırnak
    if (kod == 10L) return("\\n")
    if (kod == 13L) return("\\r")
    if (kod == 9L)  return("\\t")
    if (kod >= 32L && kod <= 126L) return(intToUtf8(kod))
    if (kod <= 0xFFFF) return(sprintf("\\u%04X", kod))
    sprintf("\\U%08X", kod)
  }, character(1))

  paste0("\"", paste(parcalar, collapse = ""), "\"")
}

# ONDALIK AYRACI YEREL AYARDAN BAĞIMSIZDIR.
#
# `format()` `options("OutDec")` değerini ONURLANDIRIR. `OutDec = ","` olan bir
# oturumda 0.125 değeri `0,125` olarak yazılırdı; üretilen `list(...)`/`c(...)`
# kaynağında bu virgül ARGÜMAN AYIRICI olarak ayrışır. Dosya başarıyla parse
# edilir ama DEĞER ya da yapının şekli SESSİZCE değişir -- parse kapısı bu
# dönüşü yakalayamaz. Bu yüzden ondalık ayracı açıkça sabitlenir.
.pkgr_format_number <- function(x) {
  format(x, digits = 17L, scientific = FALSE, trim = TRUE, decimal.mark = ".")
}

.pkgr_encode_atomic <- function(x) {
  if (is.character(x)) return(pkgr_encode_string(x))
  if (is.logical(x)) {
    if (is.na(x)) return("NA")
    return(if (isTRUE(x)) "TRUE" else "FALSE")
  }
  if (is.integer(x)) {
    if (is.na(x)) return("NA_integer_")
    return(sprintf("%dL", x))
  }
  if (is.numeric(x)) {
    if (is.na(x)) return("NA_real_")
    if (!is.finite(x)) return(.pkgr_format_number(x))
    # 17 anlamlı hane çift duyarlıklı sayıyı TAM olarak geri okur.
    return(.pkgr_format_number(x))
  }
  pkgr_encode_string(as.character(x)[1])
}

# SIFIR UZUNLUKLU ATOMİK VEKTÖR.
#
# Genel vektör dalı `c(<öge yok>)` üretir ve R'de `c()` değeri NULL'dur:
# `character(0)` gibi bir alan geri okunduğunda TÜRÜNÜ ve VARLIĞINI kaybeder.
# Bu yüzden tür açıkça yazılır.
.pkgr_encode_empty_atomic <- function(x) {
  if (is.character(x)) return("character(0)")
  if (is.integer(x))   return("integer(0)")
  if (is.logical(x))   return("logical(0)")
  if (is.complex(x))   return("complex(0)")
  if (is.raw(x))       return("raw(0)")
  if (is.numeric(x))   return("numeric(0)")
  "character(0)"
}

#' Herhangi bir R değerini kaynak metnine çevir
#'
#' Desteklenen: NULL, atomik skaler, atomik vektör (adlı/adsız), liste (adlı/adsız).
#' Fonksiyon/ortam/S4 GİBİ seri hâle getirilemeyen değerler REDDEDİLİR: üretilen
#' dosya salt VERİ olmalıdır.
pkgr_encode_value <- function(x, indent = 0L) {
  girinti <- strrep("  ", indent)
  ic_girinti <- strrep("  ", indent + 1L)

  if (is.null(x)) return("NULL")

  if (is.function(x) || is.environment(x)) {
    stop("[PK_META_GEN] Uretilen metadata yalnizca veri icerebilir (fonksiyon/ortam reddedildi).",
         call. = FALSE)
  }

  if (is.list(x)) {
    if (!length(x)) return("list()")
    adlar <- names(x)
    ogeler <- vapply(seq_along(x), function(i) {
      deger <- pkgr_encode_value(x[[i]], indent + 1L)
      ad <- if (!is.null(adlar) && !is.na(adlar[i]) && nzchar(adlar[i])) {
        paste0(pkgr_encode_string(adlar[i]), " = ")
      } else {
        ""
      }
      paste0(ic_girinti, ad, deger)
    }, character(1))
    return(paste0("list(\n", paste(ogeler, collapse = ",\n"), "\n", girinti, ")"))
  }

  if (!is.atomic(x)) {
    stop("[PK_META_GEN] Desteklenmeyen metadata degeri turu.", call. = FALSE)
  }

  if (!length(x)) return(.pkgr_encode_empty_atomic(x))

  if (length(x) == 1L && is.null(names(x))) return(.pkgr_encode_atomic(x))

  adlar <- names(x)
  ogeler <- vapply(seq_along(x), function(i) {
    deger <- .pkgr_encode_atomic(x[[i]])
    ad <- if (!is.null(adlar) && !is.na(adlar[i]) && nzchar(adlar[i])) {
      paste0(pkgr_encode_string(adlar[i]), " = ")
    } else {
      ""
    }
    paste0(ic_girinti, ad, deger)
  }, character(1))

  paste0("c(\n", paste(ogeler, collapse = ",\n"), "\n", girinti, ")")
}

#' `pk_query_meta_local` atamasını içeren tam dosya metnini üret
#'
#' Başlık ASCII'dir ve dosyanın ÜRETİLDİĞİNİ, GITIGNORE'LU olduğunu ve ELLE
#' DÜZENLENMEMESİ gerektiğini söyler.
pkgr_render_local_meta_file <- function(meta, header_info = list()) {
  meta <- if (is.list(meta)) meta else list()

  baslik <- c(
    "# =============================================================================",
    "# Dosya Yolu: R/library_query_meta_local.R",
    "# URETILEN DOSYA -- ELLE DUZENLEMEYIN.",
    "#",
    "# Uretici: tools/pk/generate_query_meta.R (Faz 3b, yalnizca Windows VM).",
    "# Bu dosya GITIGNORE'LUDUR ve uretimden turetilmis sema envanteri icerir.",
    "# ASLA commit edilmez; her uretici kosusunda YENIDEN yazilir.",
    "#",
    "# Kuresyon bu dosyaya YAZILMAZ: izlenen R/library_query_meta.R kazanir.",
    "# Operator alias'lari ayri dosyadadir: R/library_query_aliases_local.R",
    "# (uretici o dosyaya ASLA dokunmaz).",
    "#",
    "# ICERIK YALNIZCA YAPISALDIR: sutun adi, R sinifi, tipten turetilen role.",
    "# Anlamsal yetenek (capability) kimlikleri BURADA URETILMEZ; onlar insan",
    "# kuresyonudur ve eksikliklerinde anlamsal istekler SQL'den ONCE",
    "# 'unknown_no_semantic_metadata' ile durur.",
    "#",
    sprintf("# Kip           : %s", as.character(header_info$mode %||% "?")[1]),
    sprintf("# Uretim zamani : %s", as.character(header_info$timestamp %||% "?")[1]),
    sprintf("# Sorgu sayisi  : %d", length(meta)),
    sprintf("# Saglik raporu : %s", as.character(header_info$artifact_rel %||% "?")[1]),
    "# ============================================================================="
  )

  govde <- paste0("pk_query_meta_local <- ", pkgr_encode_value(meta, indent = 0L))

  paste0(paste(c(baslik, "", govde, ""), collapse = "\n"))
}

.pkgr_normalize_rel <- function(path) {
  gsub("\\\\", "/", as.character(path)[1])
}

# Yolu, VAR OLMAYAN bir hedef için de karşılaştırılabilir hâle getir: üzerine
# yazılacak dosya henüz yoksa `normalizePath()` onu genişletemez, bu yüzden
# DİZİN normalize edilir ve temel ad geri eklenir.
.pkgr_canonical_path <- function(path) {
  ham <- .pkgr_normalize_rel(path)
  dizin <- dirname(ham)
  cozulmus <- tryCatch(
    normalizePath(dizin, winslash = "/", mustWork = FALSE),
    error = function(e) dizin
  )
  .pkgr_normalize_rel(file.path(cozulmus, basename(ham)))
}

#' Yasaklı hedef kapısı
#'
#' Yol NORMALIZE edilerek karşılaştırılır; `./R/library_query_aliases_local.R`
#' ya da mutlak bir yol da yakalanır.
#'
#' TEMEL AD YETMEZ: yalnızca `basename()` kontrol edildiğinde
#' `/tmp/library_query_meta_local.R` gibi TAMAMEN BAŞKA bir dizindeki bir hedef
#' de kapıdan geçerdi. Bu yüzden hedefin `R/` dizininde olması ZORUNLUDUR ve
#' `repo_root` verildiğinde tam yol birebir karşılaştırılır.
pkgr_assert_writable_target <- function(path, forbidden = PKG_META_FORBIDDEN_TARGETS,
                                        repo_root = NULL) {
  hedef <- .pkgr_normalize_rel(path)
  temel <- basename(hedef)

  yasak_temel <- basename(.pkgr_normalize_rel(forbidden))
  if (temel %in% yasak_temel) {
    stop(sprintf(
      paste0(
        "[PK_META_GEN] YASAKLI HEDEF: '%s'. Uretici yalnizca %s dosyasina yazar; ",
        "operator alias dosyasina ve izlenen metadata dosyalarina ASLA dokunmaz."
      ),
      hedef, PKG_META_OUTPUT_FILE
    ), call. = FALSE)
  }

  if (!identical(temel, basename(PKG_META_OUTPUT_FILE))) {
    stop(sprintf(
      "[PK_META_GEN] Beklenmeyen cikti hedefi: '%s' (beklenen: %s).",
      hedef, PKG_META_OUTPUT_FILE
    ), call. = FALSE)
  }

  if (!identical(basename(dirname(hedef)), basename(dirname(PKG_META_OUTPUT_FILE)))) {
    stop(sprintf(
      "[PK_META_GEN] Cikti hedefi '%s' dizininde degil: '%s'.",
      dirname(PKG_META_OUTPUT_FILE), hedef
    ), call. = FALSE)
  }

  if (!is.null(repo_root)) {
    beklenen <- .pkgr_canonical_path(file.path(repo_root, PKG_META_OUTPUT_FILE))
    if (!identical(.pkgr_canonical_path(hedef), beklenen)) {
      stop(sprintf(
        "[PK_META_GEN] Cikti hedefi depo kokundeki beklenen yol degil: '%s' (beklenen: '%s').",
        .pkgr_canonical_path(hedef), beklenen
      ), call. = FALSE)
    }
  }

  invisible(TRUE)
}

#' Üretilen dosyayı HAZIRLA (geçici dosyaya yaz + DOĞRULA)
#'
#' Sıra: geçici dosyaya yaz -> PARSE ET -> saf ASCII doğrula. Hiçbir aşamada
#' canlı dosyaya DOKUNULMAZ; dolayısıyla hazırlama düşerse önceki GEÇERLİ dosya
#' olduğu gibi kalır.
#'
#' @return Yayımlanmayı bekleyen geçici dosya yolu.
pkgr_stage_local_meta_file <- function(text, path, forbidden = PKG_META_FORBIDDEN_TARGETS,
                                       repo_root = NULL) {
  pkgr_assert_writable_target(path, forbidden, repo_root = repo_root)

  dizin <- dirname(path)
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  gecici <- paste0(path, ".tmp-", Sys.getpid())
  basarili <- FALSE
  on.exit(if (!basarili && file.exists(gecici)) unlink(gecici), add = TRUE)

  con <- file(gecici, open = "wb")
  # Bağlantı AÇILIR AÇILMAZ kapatma kaydedilir: `writeBin()` disk dolu/G-C
  # hatasında YÜKSELİRSE, tutamaç açık kalırdı ve Windows'ta kilitli dosya
  # yüzünden temizlik de başarısız olurdu.
  acik <- TRUE
  on.exit(if (acik) tryCatch(close(con), error = function(e) NULL), add = TRUE)
  writeBin(charToRaw(enc2utf8(text)), con)
  close(con)
  acik <- FALSE

  # DOĞRULAMA: üretilen kaynak gerçekten parse edilebiliyor mu?
  ayrisma <- tryCatch({
    parse(gecici, encoding = "UTF-8")
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(ayrisma)) {
    stop(sprintf(
      "[PK_META_GEN] Uretilen metadata dosyasi parse edilemedi; ONCEKI dosya korundu. Hata: %s",
      as.character(ayrisma)[1]
    ), call. = FALSE)
  }

  # Saf ASCII sözleşmesi: WINDOWS-1254 kesilme sınıfını tamamen kapatır.
  ham <- readBin(gecici, what = "raw", n = file.info(gecici)$size)
  if (length(ham) && any(as.integer(ham) > 127L)) {
    stop("[PK_META_GEN] Uretilen dosya ASCII disi bayt iceriyor; yazma iptal edildi.",
         call. = FALSE)
  }

  basarili <- TRUE
  gecici
}

# Kilitli/kirli bir hedef için YEDEKLİ ATOMİK TAKAS.
#
# Canlı dosyanın üzerine `file.copy(overwrite = TRUE)` YAPILMAZ: kopyalama
# ortasında süreç düşerse hedef yarım kalabilir. Aynı dizindeki dosyalar yalnızca
# `file.rename()` ile taşınır. Önceki geçerli dosya ayrı bir yedek adında bütün
# hâliyle tutulur; yeni dosya yerleştirilemezse yedek geri taşınır.
.pkgr_replace_with_backup <- function(staged, path, attempts = 3L) {
  if (!file.exists(path)) return(FALSE)

  yedek <- paste0(path, ".bak-", Sys.getpid(), "-", format(Sys.time(), "%Y%m%d%H%M%OS6"))
  yedek <- gsub(":", "", yedek, fixed = TRUE)
  if (file.exists(yedek)) unlink(yedek)

  tasi <- function(from, to) {
    deneme <- max(1L, suppressWarnings(as.integer(attempts)[1]))
    for (i in seq_len(deneme)) {
      if (isTRUE(tryCatch(file.rename(from, to), error = function(e) FALSE))) return(TRUE)
      if (i < deneme) Sys.sleep(0.05)
    }
    FALSE
  }

  if (!tasi(path, yedek)) return(FALSE)

  if (!tasi(staged, path)) {
    geri <- tasi(yedek, path)
    if (!geri) {
      stop(sprintf(
        "[PK_META_GEN] Atomik takas basarisiz; onceki dosya YEDEKTE korundu: %s",
        yedek
      ), call. = FALSE)
    }
    return(FALSE)
  }

  if (file.exists(yedek)) unlink(yedek)
  TRUE
}

#' HAZIRLANMIŞ dosyayı yerine taşı (YAYIMLA)
#'
#' `file.rename()` aynı dosya sisteminde ATOMİKTİR ve tercih edilen yoldur.
#' Windows'ta kilit/anlık virüs taraması yüzünden düşebildiği için sınırlı
#' sayıda yeniden denenir; yine de olmazsa yedekli takasa geçilir.
pkgr_publish_staged_file <- function(staged, path, attempts = 3L) {
  if (!file.exists(staged)) {
    stop(sprintf("[PK_META_GEN] Hazirlanan gecici dosya bulunamadi: %s", staged),
         call. = FALSE)
  }
  on.exit(if (file.exists(staged)) unlink(staged), add = TRUE)

  deneme <- max(1L, suppressWarnings(as.integer(attempts)[1]))
  for (i in seq_len(deneme)) {
    if (isTRUE(tryCatch(file.rename(staged, path), error = function(e) FALSE))) {
      return(invisible(path))
    }
    if (i < deneme) Sys.sleep(0.05)
  }

  if (!.pkgr_replace_with_backup(staged, path, attempts = deneme)) {
    stop(sprintf("[PK_META_GEN] Cikti dosyasi yazilamadi: %s", path), call. = FALSE)
  }

  invisible(path)
}

#' Üretilen dosyayı ATOMİK ve DOĞRULANMIŞ olarak yaz (hazırla + yayımla)
#'
#' Denetim artefaktlarını önce yazmak isteyen çağıran, iki adımı ayrı ayrı
#' çağırmalıdır (bkz. `pkgr_stage_local_meta_file()` / `pkgr_publish_staged_file()`).
pkgr_write_local_meta_file <- function(text, path, forbidden = PKG_META_FORBIDDEN_TARGETS,
                                       repo_root = NULL) {
  gecici <- pkgr_stage_local_meta_file(text, path, forbidden, repo_root = repo_root)
  pkgr_publish_staged_file(gecici, path)
}
