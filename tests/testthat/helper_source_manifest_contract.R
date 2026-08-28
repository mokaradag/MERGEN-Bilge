# ==============================================================================
# Dosya Yolu: tests/testthat/helper_source_manifest_contract.R
# Açıklama: Manifest tabanlı source-order test yardımcıları.
#           global.R artık dev safe_source listesi taşımadığı için source-order
#           sözleşmeleri R/config_source_manifest.R üzerinden okunmalıdır.
# ==============================================================================

source_manifest_contract_repo_root <- function() {
  if (exists("resolve_repo_root_for_tests", mode = "function")) {
    return(resolve_repo_root_for_tests())
  }

  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Manifest test helper repo kökünü bulamadı.", call. = FALSE)
}

source_manifest_paths_for_tests <- function() {
  repo_root <- source_manifest_contract_repo_root()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  if (!exists("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)) {
    stop(
      "Test manifesti source_manifest_runtime_paths nesnesini bulamadı.",
      call. = FALSE
    )
  }

  paths <- get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)

  if (!is.character(paths) || length(paths) == 0L) {
    stop("Test manifesti boş veya geçersiz.", call. = FALSE)
  }

  enc2utf8(paths)
}

# Bölümlenmiş manifesti (source_manifest_sections) ad -> yol vektörü olarak
# döndürür. Bölüm İÇİ sırayı doğrulayan testler bunu kullanmalıdır; manifesti
# elle yeniden source etmek gereksiz tekrar üretir.
source_manifest_sections_for_tests <- function() {
  repo_root <- source_manifest_contract_repo_root()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  if (!exists("source_manifest_sections", envir = manifest_env, inherits = FALSE)) {
    stop("Test manifesti source_manifest_sections nesnesini bulamadı.", call. = FALSE)
  }

  sections <- get("source_manifest_sections", envir = manifest_env, inherits = FALSE)

  # ŞEKİL DOĞRULANIR: adsız ya da boş bir bölüm listesi, bölüm bazlı
  # sözleşmeleri SESSİZCE vacuous geçirir (her `for` döngüsü boş küme üzerinde
  # koşar ve hiçbir iddia çalışmaz).
  if (!is.list(sections) || length(sections) == 0L ||
      is.null(names(sections)) || !all(nzchar(names(sections)))) {
    stop("Test manifesti bölüm listesi boş veya adsız.", call. = FALSE)
  }

  # HER BÖLÜM AYRI AYRI DOĞRULANIR.
  #
  # Üstteki denetim yalnızca LİSTENİN kendisine bakıyordu: tek bir bölüm
  # `character(0)` olduğunda ya da karakter olmayan bir değere düştüğünde
  # bölüm bazlı sözleşmeler o bölüm için SIFIR iddia çalıştırıp GEÇİYORDU.
  # Çalışma zamanı manifestinden bir bölümün tüm yolları silinse bile
  # kaynak-sıra paketi yeşil kalırdı.
  for (bolum_adi in names(sections)) {
    yollar <- sections[[bolum_adi]]
    if (!is.character(yollar) || length(yollar) == 0L ||
        any(is.na(yollar)) || !all(nzchar(trimws(yollar)))) {
      stop(
        sprintf("Test manifesti bölümü boş ya da geçersiz: %s", bolum_adi),
        call. = FALSE
      )
    }
  }

  sections
}

# BOŞ/GEÇERSİZ BEKLENTİ VEKTÖRÜ SESSİZCE GEÇMEZ: `match(character(0), ...)`
# boş döner, `any(is.na(...))` FALSE olur ve `all(diff(...) > 0)` da TRUE
# olur; iddia HİÇBİR ŞEY doğrulamadan yeşil kalırdı.
.source_manifest_require_expectation <- function(x, label) {
  if (!is.character(x) || length(x) == 0L || any(is.na(x)) ||
      !all(nzchar(trimws(x)))) {
    stop(sprintf("%s: beklenen yol vektörü boş ya da geçersiz.", label),
         call. = FALSE)
  }
  invisible(TRUE)
}

expect_source_manifest_contains_for_tests <- function(required_paths,
                                                     paths = source_manifest_paths_for_tests(),
                                                     label = "Manifest içinde eksik kaynak kayıtları:") {
  .source_manifest_require_expectation(required_paths, label)
  positions <- match(required_paths, paths)

  testthat::expect_false(
    any(is.na(positions)),
    info = paste(
      label,
      paste(required_paths[is.na(positions)], collapse = ", ")
    )
  )

  invisible(positions)
}

expect_source_manifest_order_for_tests <- function(expected_order,
                                                   paths = source_manifest_paths_for_tests(),
                                                   label = "Manifest source sırası bozulmuş:") {
  .source_manifest_require_expectation(expected_order, label)
  positions <- match(expected_order, paths)

  testthat::expect_false(
    any(is.na(positions)),
    info = paste(
      "Manifest içinde eksik kaynak kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  testthat::expect_true(
    all(diff(positions) > 0L),
    info = paste(
      label,
      paste(expected_order, collapse = " -> ")
    )
  )

  invisible(positions)
}