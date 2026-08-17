# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_render.R
# Aciklama: Faz 3b metadata ureticisi -- R kaynagi uretimi ve ATOMIK yazma.
#
# BU DOSYA CALISMA ZAMANI KODU DEGILDIR; kaynak manifestine EKLENMEZ.
#
# IKI SERT KURAL:
#   1) YASAKLI HEDEF KAPISI. Uretici YALNIZCA R/library_query_meta_local.R
#      dosyasina yazabilir. Operatorun alias dosyasi ve izlenen metadata
#      dosyalari calisma zamaninda REDDEDILIR (yorum degil, kapi).
#   2) URETILEN KAYNAK SAF ASCII'DIR. ASCII disi her karakter "\uXXXX" kacisiyla
#      yazilir. Windows VM'de R'in yerel kod sayfasi WINDOWS-1254'tur ve
#      `source(..., encoding = "UTF-8")` dosyayi o sayfaya cevirir; CP1254'te
#      karsiligi olmayan TEK bir karakter dosyayi O NOKTADA KESER (CLAUDE.md
#      §1G). Saf ASCII cikti bu sinifin tamamini imkansiz kilar.
# ==============================================================================

#' ASCII-guvenli R karakter sabiti uret
#'
#' ASCII disi her kod noktasi kacisla yazilir; sonuc dizesi DEGISMEZ.
#' BMP disi kod noktalari icin 8 haneli `\U` bicimi kullanilir.
pkgr_encode_string <- function(x) {
  if (is.na(x)) return("NA_character_")

  metin <- enc2utf8(as.character(x)[1])
  kod_noktalari <- utf8ToInt(metin)
  if (is.null(kod_noktalari)) return("\"\"")

  parcalar <- vapply(kod_noktalari, function(kod) {
    if (kod == 92L) return("\\\\")      # ters bolu
    if (kod == 34L) return("\\\"")      # cift tirnak
    if (kod == 10L) return("\\n")
    if (kod == 13L) return("\\r")
    if (kod == 9L)  return("\\t")
    if (kod >= 32L && kod <= 126L) return(intToUtf8(kod))
    if (kod <= 0xFFFF) return(sprintf("\\u%04X", kod))
    sprintf("\\U%08X", kod)
  }, character(1))

  paste0("\"", paste(parcalar, collapse = ""), "\"")
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
    if (!is.finite(x)) return(format(x))
    # 17 anlamli hane cift duyarlikli sayiyi TAM olarak geri okur.
    return(format(x, digits = 17L, scientific = FALSE, trim = TRUE))
  }
  pkgr_encode_string(as.character(x)[1])
}

#' Herhangi bir R degerini kaynak metnine cevir
#'
#' Desteklenen: NULL, atomik skaler, atomik vektor (adli/adsiz), liste (adli/adsiz).
#' Fonksiyon/ortam/S4 GIBI seri hale getirilemeyen degerler REDDEDILIR: uretilen
#' dosya salt VERI olmalidir.
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

#' `pk_query_meta_local` atamasini iceren tam dosya metnini uret
#'
#' Baslik ASCII'dir ve dosyanin URETILDIGINI, GITIGNORE'LU oldugunu ve ELLE
#' DUZENLENMEMESI gerektigini soyler.
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

#' Yasakli hedef kapisi
#'
#' Yol NORMALIZE edilerek karsilastirilir; `./R/library_query_aliases_local.R`
#' ya da mutlak bir yol da yakalanir.
pkgr_assert_writable_target <- function(path, forbidden = PKG_META_FORBIDDEN_TARGETS) {
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

  invisible(TRUE)
}

#' Uretilen dosyayi ATOMIK ve DOGRULANMIS olarak yaz
#'
#' Sira: gecici dosyaya yaz -> PARSE ET -> yalnizca parse basariliysa yerine
#' tasi. Yarim/bozuk bir dosya ASLA yerine gecmez; kosu ortasinda kesilirse
#' onceki GECERLI dosya oldugu gibi kalir.
pkgr_write_local_meta_file <- function(text, path, forbidden = PKG_META_FORBIDDEN_TARGETS) {
  pkgr_assert_writable_target(path, forbidden)

  dizin <- dirname(path)
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  gecici <- paste0(path, ".tmp-", Sys.getpid())
  on.exit(if (file.exists(gecici)) unlink(gecici), add = TRUE)

  con <- file(gecici, open = "wb")
  writeBin(charToRaw(enc2utf8(text)), con)
  close(con)

  # DOGRULAMA: uretilen kaynak gercekten parse edilebiliyor mu?
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

  # Saf ASCII sozlesmesi: WINDOWS-1254 kesilme sinifini tamamen kapatir.
  ham <- readBin(gecici, what = "raw", n = file.info(gecici)$size)
  if (length(ham) && any(as.integer(ham) > 127L)) {
    stop("[PK_META_GEN] Uretilen dosya ASCII disi bayt iceriyor; yazma iptal edildi.",
         call. = FALSE)
  }

  tasindi <- tryCatch(file.rename(gecici, path), error = function(e) FALSE)
  if (!isTRUE(tasindi)) {
    # Farkli dosya sistemi/kilit durumunda kopyala-sil yedegi.
    kopyalandi <- tryCatch(file.copy(gecici, path, overwrite = TRUE), error = function(e) FALSE)
    if (!isTRUE(kopyalandi)) {
      stop(sprintf("[PK_META_GEN] Cikti dosyasi yazilamadi: %s", path), call. = FALSE)
    }
    unlink(gecici)
  }

  invisible(path)
}
