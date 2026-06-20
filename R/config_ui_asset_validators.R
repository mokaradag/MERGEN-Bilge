# ==============================================================================
# Dosya Yolu: R/config_ui_asset_validators.R
# Açıklama: Frontend CSS/JS varlık manifestinin SAF çözümleyici (resolver) ve
#           DOĞRULAYICI (validator) API'si.
#
#           Varlık VERİSİ (gruplar + sıra kuralları + render planı) tek sahip
#           olarak R/config_ui_assets.R dosyasında kalır; bu dosya o veriyi
#           okuyup düzleştirme, çözümleme ve sıra/render planı doğrulaması
#           sağlayan saf fonksiyonları taşır. Bu, frontend bölge VERİSİ
#           (config_ui_asset_zones.R) ile bölge DOĞRULAYICI
#           (config_ui_asset_zone_validators.R) ayrımının aynı desenidir.
#
#           Bu dosya runtime davranışını değiştirmez: tüm fonksiyonlar veri
#           nesnelerini ÇAĞRI ANINDA çözer (tembel değerlendirme), bu yüzden
#           veri dosyasından hemen SONRA yüklenmesi yeterlidir. Boot'ta yalnızca
#           ui_asset_tags() üzerinden dolaylı çağrılır; sıra/render doğrulaması
#           manifest bakımında yanlış sıralamayı erken yakalamak içindir.
# ==============================================================================

ui_asset_render_plan_groups <- function(render_plan = ui_asset_js_render_plan) {
  vapply(render_plan, function(item) item$group, character(1))
}

ui_asset_render_plan_deferred <- function(render_plan = ui_asset_js_render_plan) {
  deferred <- vapply(render_plan, function(item) isTRUE(item$defer), logical(1))
  ui_asset_render_plan_groups(render_plan)[deferred]
}

ui_asset_validate_js_render_plan <- function(render_plan = ui_asset_js_render_plan,
                                             groups = ui_asset_js_groups) {
  if (!is.list(render_plan) || length(render_plan) == 0) {
    stop("UI JS render planı boş olamaz.", call. = FALSE)
  }

  for (item in render_plan) {
    if (!is.list(item) ||
        !is.character(item$group) ||
        length(item$group) != 1 ||
        !is.logical(item$defer) ||
        length(item$defer) != 1 ||
        is.na(item$defer)) {
      stop(
        "UI JS render planı her kayıt için group ve defer alanlarını içermelidir.",
        call. = FALSE
      )
    }
  }

  render_groups <- ui_asset_render_plan_groups(render_plan)
  duplicate_groups <- sort(unique(render_groups[duplicated(render_groups)]))

  if (length(duplicate_groups) > 0) {
    stop(
      "UI JS render planında yinelenen grup var: ",
      paste(duplicate_groups, collapse = ", "),
      call. = FALSE
    )
  }

  missing_groups <- setdiff(names(groups), render_groups)
  extra_groups <- setdiff(render_groups, names(groups))

  if (length(missing_groups) > 0) {
    stop(
      "UI JS render planında eksik grup var: ",
      paste(missing_groups, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(extra_groups) > 0) {
    stop(
      "UI JS render planında manifestte olmayan grup var: ",
      paste(extra_groups, collapse = ", "),
      call. = FALSE
    )
  }

  if (!identical(ui_asset_render_plan_deferred(render_plan), ui_asset_deferred_js_groups)) {
    stop(
      "UI JS render planı ile ertelenmiş grup listesi uyuşmuyor.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

ui_asset_all_css <- function() {
  ui_asset_flatten_groups(ui_asset_css_groups)
}

ui_asset_all_js <- function() {
  ui_asset_flatten_groups(ui_asset_js_groups)
}

ui_asset_deferred_js_paths <- function() {
  missing_groups <- setdiff(ui_asset_deferred_js_groups, names(ui_asset_js_groups))

  if (length(missing_groups) > 0) {
    stop(
      "UI ertelenmiş JS grup tanımı manifestte yok: ",
      paste(missing_groups, collapse = ", "),
      call. = FALSE
    )
  }

  ui_asset_flatten_groups(ui_asset_js_groups[ui_asset_deferred_js_groups])
}

ui_asset_validate_css_order <- function(css_paths = ui_asset_all_css()) {
  for (rule in ui_asset_css_order_rules) {
    if (!is.character(rule) || length(rule) != 2) {
      stop("UI CSS sıra kuralı iki dosyadan oluşmalıdır.", call. = FALSE)
    }

    before_path <- rule[[1]]
    after_path <- rule[[2]]

    before_pos <- match(before_path, css_paths)
    after_pos <- match(after_path, css_paths)

    if (is.na(before_pos)) {
      stop(
        "UI CSS sıra kuralının ilk dosyası manifestte yok: ",
        before_path,
        call. = FALSE
      )
    }

    if (is.na(after_pos)) {
      stop(
        "UI CSS sıra kuralının ikinci dosyası manifestte yok: ",
        after_path,
        call. = FALSE
      )
    }

    if (before_pos >= after_pos) {
      stop(
        "UI CSS varlık yükleme sırası bozuldu: ",
        before_path,
        " dosyası ",
        after_path,
        " dosyasından önce yüklenmelidir.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

ui_asset_validate_js_order <- function(js_paths = ui_asset_all_js()) {
  for (rule in ui_asset_js_order_rules) {
    if (!is.character(rule) || length(rule) != 2) {
      stop("UI JS sıra kuralı iki dosyadan oluşmalıdır.", call. = FALSE)
    }

    before_path <- rule[[1]]
    after_path <- rule[[2]]

    before_pos <- match(before_path, js_paths)
    after_pos <- match(after_path, js_paths)

    if (is.na(before_pos)) {
      stop(
        "UI JS sıra kuralının ilk dosyası manifestte yok: ",
        before_path,
        call. = FALSE
      )
    }

    if (is.na(after_pos)) {
      stop(
        "UI JS sıra kuralının ikinci dosyası manifestte yok: ",
        after_path,
        call. = FALSE
      )
    }

    if (before_pos >= after_pos) {
      stop(
        "UI JS varlık yükleme sırası bozuldu: ",
        before_path,
        " dosyası ",
        after_path,
        " dosyasından önce yüklenmelidir.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

ui_asset_duplicate_paths <- function(paths) {
  sort(unique(paths[duplicated(paths)]))
}

ui_asset_public_root <- function(root = getwd()) {
  if (dir.exists(file.path(root, "css")) &&
      dir.exists(file.path(root, "js"))) {
    return(root)
  }

  file.path(root, "www")
}

ui_asset_validate <- function(root = getwd(), check_files = FALSE) {
  css_paths <- ui_asset_all_css()
  js_paths <- ui_asset_all_js()

  duplicate_css <- ui_asset_duplicate_paths(css_paths)
  duplicate_js <- ui_asset_duplicate_paths(js_paths)

  if (length(duplicate_css) > 0) {
    stop(
      "UI CSS varlık manifestinde yinelenen kayıt var: ",
      paste(duplicate_css, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(duplicate_js) > 0) {
    stop(
      "UI JS varlık manifestinde yinelenen kayıt var: ",
      paste(duplicate_js, collapse = ", "),
      call. = FALSE
    )
  }

  ui_asset_validate_css_order(css_paths)
  ui_asset_validate_js_order(js_paths)
  ui_asset_deferred_js_paths()
  ui_asset_validate_js_render_plan()

  if (isTRUE(check_files)) {
    all_paths <- c(css_paths, js_paths)
    asset_root <- ui_asset_public_root(root)
    missing_paths <- all_paths[!file.exists(file.path(asset_root, all_paths))]

    if (length(missing_paths) > 0) {
      stop(
        "UI varlık manifestinde bulunamayan dosya var: ",
        paste(missing_paths, collapse = ", "),
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}
