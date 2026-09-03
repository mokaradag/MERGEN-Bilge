# ==============================================================================
# Dosya Yolu: R/config_ui_asset_tags.R
# Açıklama: Frontend CSS/JS varlık manifestinin htmltools etiket (tag) render
#           katmanı. ui.R bu dosyadaki ui_asset_tags() ile tüm <link>/<script>
#           etiketlerini üretir.
#
#           Varlık VERİSİ R/config_ui_assets.R, çözümleyici/doğrulayıcılar
#           R/config_ui_asset_validators.R dosyasındadır. Bu dosya yalnızca
#           render planından ve manifest yollarından etiket üretir; veri veya
#           doğrulayıcı yeniden tanımlamaz (tek kaynak korunur). Çağrı anında
#           ui_asset_all_css() / ui_asset_validate() / ui_asset_js_render_plan
#           çözülür, bu yüzden VERİ ve DOĞRULAYICI dosyalarından SONRA
#           yüklenmelidir.
# ==============================================================================

ui_asset_css_tag <- function(path) {
  if (grepl("^codemirror/", path)) {
    return(tags$link(rel = "stylesheet", href = path))
  }

  tags$link(rel = "stylesheet", type = "text/css", href = path)
}

ui_asset_script_tag <- function(path, defer = FALSE) {
  if (isTRUE(defer)) {
    return(tags$script(src = path, defer = "defer"))
  }

  tags$script(src = path)
}

ui_asset_css_tags <- function() {
  htmltools::tagList(lapply(ui_asset_all_css(), ui_asset_css_tag))
}

ui_asset_js_tags <- function() {
  js_tags <- unlist(
    lapply(ui_asset_js_render_plan, function(item) {
      lapply(
        ui_asset_js_groups[[item$group]],
        ui_asset_script_tag,
        defer = item$defer
      )
    }),
    recursive = FALSE,
    use.names = FALSE
  )

  htmltools::tagList(js_tags)
}

ui_asset_tags <- function(root = getwd(), check_files = FALSE) {
  ui_asset_validate(root = root, check_files = check_files)

  htmltools::tagList(
    ui_asset_css_tags(),
    ui_asset_js_tags()
  )
}
