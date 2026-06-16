# ==============================================================================
# Dosya Yolu: R/config_ui_asset_zone_validators.R
# Açıklama: Frontend bölge (zone) sahiplik haritası için saf çözümleme ve
#           bölümleme (partition) doğrulama API'si.
#
#           Bu dosya yalnızca DAVRANIŞ (saf fonksiyonlar) barındırır; VERİ
#           (ui_asset_ownership_zones + ui_asset_unmanifested_ownership)
#           R/config_ui_asset_zones.R içinde kalır. Veri dosyası bu dosyadan
#           ÖNCE yüklenir (config_source_manifest.R config_ui_assets bölümü).
#           Bu, R/config_source_manifest.R (veri) + R/bootstrap_source_manifest.R
#           (doğrulayıcı) ayrımıyla aynı desendir.
#
#           Bu fonksiyonlar çalışma zamanında (boot/UI render) ÇAĞRILMAZ:
#           yükleme sırasının tek sahibi R/config_ui_assets.R kalır. Yalnızca
#           seam doctor (tests/scripts/seam_doctor.R) ve sözleşme testleri
#           bu API'yi sahiplik bölümlemesini doğrulamak için kullanır.
#
#           Varsayılan argümanlar (ui_asset_ownership_zones,
#           ui_asset_all_css(), ui_asset_css_groups vb.) R'de tembel
#           değerlendirilir; fonksiyon çağrıldığı ortamda veri görünür olduğu
#           sürece çalışır (veri dosyası + manifest dosyası aynı ortama yüklenir).
#
#           Koruyan sözleşme testleri:
#             - tests/testthat/test-ui-asset-zones-contract.R
#             - tests/testthat/test-ui-asset-zone-validators-split-contract.R
# ==============================================================================

ui_asset_zone_ids <- function(zones = ui_asset_ownership_zones) {
  names(zones)
}

ui_asset_zone_get <- function(id, zones = ui_asset_ownership_zones) {
  if (!is.character(id) || length(id) != 1L || !nzchar(id)) {
    stop("Bölge id tek bir boş olmayan karakter değeri olmalıdır.", call. = FALSE)
  }

  zone <- zones[[id]]

  if (is.null(zone)) {
    stop(sprintf("Frontend bölge haritasında bulunamadı: %s", id), call. = FALSE)
  }

  zone
}

# Bir bölgenin CSS yollarını çözer: açık liste + manifest grup referansları.
ui_asset_zone_css_paths <- function(zone, css_groups = ui_asset_css_groups) {
  paths <- zone$css

  for (group_name in zone$css_groups) {
    group_paths <- css_groups[[group_name]]

    if (is.null(group_paths)) {
      stop(sprintf("Bölge bilinmeyen CSS grubuna işaret ediyor: %s", group_name), call. = FALSE)
    }

    paths <- c(paths, unname(unlist(group_paths, use.names = FALSE)))
  }

  paths
}

# Bir bölgenin JS yollarını çözer: açık liste + manifest grup referansları.
ui_asset_zone_js_paths <- function(zone, js_groups = ui_asset_js_groups) {
  paths <- zone$js

  for (group_name in zone$js_groups) {
    group_paths <- js_groups[[group_name]]

    if (is.null(group_paths)) {
      stop(sprintf("Bölge bilinmeyen JS grubuna işaret ediyor: %s", group_name), call. = FALSE)
    }

    paths <- c(paths, unname(unlist(group_paths, use.names = FALSE)))
  }

  paths
}

# Bölge -> sahip seam haritası. Seam kayıt defteri doğrulaması, buradaki
# sahiplerin gerçek seam id'leri olduğunu çapraz kontrol eder.
ui_asset_zone_owner_seams <- function(zones = ui_asset_ownership_zones) {
  owners <- character(0)

  for (zone_id in names(zones)) {
    owners <- c(owners, stats::setNames(zones[[zone_id]]$owner_seam, zone_id))
  }

  owners
}

# Verilen seam'in sahiplendiği bölge id'lerini türetir (tek kaynak: zones).
ui_asset_zones_for_seam <- function(seam_id, zones = ui_asset_ownership_zones) {
  owners <- ui_asset_zone_owner_seams(zones)
  names(owners[owners == seam_id])
}

# Saf bölümleme doğrulaması: manifest CSS/JS listeleri ile bölge haritası
# birebir örtüşmelidir. Sorun yoksa character(0) döner.
ui_asset_zones_validate <- function(zones = ui_asset_ownership_zones,
                                    css_paths = ui_asset_all_css(),
                                    js_paths = ui_asset_all_js(),
                                    css_groups = ui_asset_css_groups,
                                    js_groups = ui_asset_js_groups,
                                    unmanifested = ui_asset_unmanifested_ownership,
                                    repo_root = NULL) {
  problems <- character(0)

  if (!is.list(zones) || length(zones) == 0L) {
    return("Frontend bölge haritası boş olmayan bir liste olmalıdır.")
  }

  zone_ids <- names(zones)

  if (is.null(zone_ids) || any(!nzchar(zone_ids)) || anyDuplicated(zone_ids) > 0L) {
    problems <- c(problems, "Frontend bölgeleri benzersiz ve boş olmayan adlarla adlandırılmalıdır.")
  }

  required_fields <- c("title", "owner_seam", "css_groups", "js_groups", "css", "js", "guard_tests")

  zone_css <- character(0)
  zone_js <- character(0)

  for (zone_id in zone_ids) {
    zone <- zones[[zone_id]]

    missing_fields <- setdiff(required_fields, names(zone))

    if (length(missing_fields) > 0L) {
      problems <- c(problems, sprintf(
        "Bölge '%s' zorunlu alanları eksik: %s",
        zone_id,
        paste(missing_fields, collapse = ", ")
      ))
      next
    }

    if (!is.character(zone$owner_seam) || length(zone$owner_seam) != 1L || !nzchar(zone$owner_seam)) {
      problems <- c(problems, sprintf("Bölge '%s' için owner_seam tek seam id olmalıdır.", zone_id))
    }

    if (!is.character(zone$guard_tests) || length(zone$guard_tests) == 0L) {
      problems <- c(problems, sprintf("Bölge '%s' en az bir guard testi bildirmelidir.", zone_id))
    }

    resolved_css <- tryCatch(
      ui_asset_zone_css_paths(zone, css_groups = css_groups),
      error = function(e) {
        problems <<- c(problems, sprintf("Bölge '%s': %s", zone_id, conditionMessage(e)))
        character(0)
      }
    )

    resolved_js <- tryCatch(
      ui_asset_zone_js_paths(zone, js_groups = js_groups),
      error = function(e) {
        problems <<- c(problems, sprintf("Bölge '%s': %s", zone_id, conditionMessage(e)))
        character(0)
      }
    )

    zone_css <- c(zone_css, resolved_css)
    zone_js <- c(zone_js, resolved_js)
  }

  duplicate_css <- sort(unique(zone_css[duplicated(zone_css)]))
  duplicate_js <- sort(unique(zone_js[duplicated(zone_js)]))

  if (length(duplicate_css) > 0L) {
    problems <- c(problems, sprintf(
      "CSS varlığı birden fazla bölgeye atanmış: %s",
      paste(duplicate_css, collapse = ", ")
    ))
  }

  if (length(duplicate_js) > 0L) {
    problems <- c(problems, sprintf(
      "JS varlığı birden fazla bölgeye atanmış: %s",
      paste(duplicate_js, collapse = ", ")
    ))
  }

  missing_css <- setdiff(css_paths, zone_css)
  unknown_css <- setdiff(zone_css, css_paths)
  missing_js <- setdiff(js_paths, zone_js)
  unknown_js <- setdiff(zone_js, js_paths)

  if (length(missing_css) > 0L) {
    problems <- c(problems, sprintf(
      "Sahipsiz manifest CSS varlığı var (bir bölgeye atayın): %s",
      paste(missing_css, collapse = ", ")
    ))
  }

  if (length(unknown_css) > 0L) {
    problems <- c(problems, sprintf(
      "Bölge haritası manifestte olmayan CSS varlığına işaret ediyor: %s",
      paste(unknown_css, collapse = ", ")
    ))
  }

  if (length(missing_js) > 0L) {
    problems <- c(problems, sprintf(
      "Sahipsiz manifest JS varlığı var (bir bölgeye atayın): %s",
      paste(missing_js, collapse = ", ")
    ))
  }

  if (length(unknown_js) > 0L) {
    problems <- c(problems, sprintf(
      "Bölge haritası manifestte olmayan JS varlığına işaret ediyor: %s",
      paste(unknown_js, collapse = ", ")
    ))
  }

  unmanifested_paths <- names(unmanifested)
  overlap_with_manifest <- intersect(unmanifested_paths, c(css_paths, js_paths))

  if (length(overlap_with_manifest) > 0L) {
    problems <- c(problems, sprintf(
      "Manifest dışı sahiplik kaydı manifestte de listelenmiş: %s",
      paste(overlap_with_manifest, collapse = ", ")
    ))
  }

  for (path in unmanifested_paths) {
    entry <- unmanifested[[path]]

    if (!is.list(entry) ||
        !is.character(entry$owner_seam) ||
        length(entry$owner_seam) != 1L ||
        !nzchar(entry$owner_seam) ||
        !is.character(entry$reason) ||
        length(entry$reason) != 1L ||
        !nzchar(entry$reason)) {
      problems <- c(problems, sprintf(
        "Manifest dışı sahiplik kaydı owner_seam ve reason alanlarını içermelidir: %s",
        path
      ))
    }
  }

  if (!is.null(repo_root)) {
    guard_files <- character(0)

    for (zone_id in zone_ids) {
      guard_files <- c(guard_files, zones[[zone_id]]$guard_tests)
    }

    guard_files <- unique(guard_files)
    missing_guards <- guard_files[!file.exists(file.path(repo_root, guard_files))]

    if (length(missing_guards) > 0L) {
      problems <- c(problems, sprintf(
        "Bölge guard testleri repoda yok: %s",
        paste(missing_guards, collapse = ", ")
      ))
    }

    # optional_in_checkout girdileri yalnızca on-prem VM kopyasında bulunur;
    # cloud/CI checkout'unda yoklukları yapısal sorun sayılmaz.
    required_unmanifested <- unmanifested_paths[!vapply(
      unmanifested_paths,
      function(path) isTRUE(unmanifested[[path]]$optional_in_checkout),
      logical(1)
    )]

    missing_unmanifested <- required_unmanifested[
      !file.exists(file.path(repo_root, "www", required_unmanifested))
    ]

    if (length(missing_unmanifested) > 0L) {
      problems <- c(problems, sprintf(
        "Manifest dışı sahiplik kaydındaki dosya repoda yok: %s",
        paste(missing_unmanifested, collapse = ", ")
      ))
    }
  }

  problems
}

# www/css ve www/js altındaki fiziksel dosyalar için sahiplik boşluğu raporu.
# Bir dosya ya manifest bölgesi üzerinden ya da manifest dışı sahiplik
# kaydıyla sahiplenilmelidir. Boşluk yoksa character(0) döner.
ui_asset_frontend_ownership_gaps <- function(repo_root = getwd(),
                                             zones = ui_asset_ownership_zones,
                                             css_paths = ui_asset_all_css(),
                                             js_paths = ui_asset_all_js(),
                                             unmanifested = ui_asset_unmanifested_ownership) {
  www_root <- file.path(repo_root, "www")

  physical <- character(0)

  for (sub in c("css", "js")) {
    sub_dir <- file.path(www_root, sub)

    if (!dir.exists(sub_dir)) {
      next
    }

    files <- list.files(sub_dir, pattern = "\\.(css|js)$", recursive = FALSE)

    if (length(files) > 0L) {
      physical <- c(physical, file.path(sub, files))
    }
  }

  owned <- c(css_paths, js_paths, names(unmanifested))

  sort(setdiff(physical, owned))
}
