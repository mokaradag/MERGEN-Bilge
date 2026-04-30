# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_dir_ui.R
# Açıklama: Bilge Yolaç dizin gezgini UI ve yenileme koruması yardımcıları.
# ==============================================================================

cc_create_dir_refresh_guard <- function() {
  env <- new.env(parent = emptyenv())
  env$current_id <- 0L

  list(
    next_id = function() {
      env$current_id <- env$current_id + 1L
      env$current_id
    },
    is_latest = function(id) {
      identical(as.integer(id), as.integer(env$current_id))
    },
    current_id = function() {
      env$current_id
    }
  )
}

cc_format_dir_file_size <- function(size) {
  boyut <- suppressWarnings(as.numeric(size))

  if (length(boyut) == 0L || is.na(boyut[1])) {
    return("")
  }

  boyut <- boyut[1]

  if (boyut < 1024) {
    paste0(boyut, " B")
  } else if (boyut < 1048576) {
    paste0(round(boyut / 1024, 1), " KB")
  } else {
    paste0(round(boyut / 1048576, 1), " MB")
  }
}

cc_dir_item_tooltip <- function(item) {
  gorunen_ad <- item$gorunen_ad %||% item$ad

  if (!identical(gorunen_ad, item$ad)) {
    paste0(
      "Yüklenen ad: ", gorunen_ad,
      "\nSistem adı: ", item$ad,
      "\nYol: ", item$yol
    )
  } else {
    item$yol
  }
}

cc_build_dir_item_ui <- function(item, ns) {
  ikon <- if (identical(item$tip, "klasor")) "folder" else "file"
  gorunen_ad <- item$gorunen_ad %||% item$ad
  ek_sinif <- if (identical(item$tip, "klasor")) " cc-dir-clickable" else ""

  ek_olay <- if (identical(item$tip, "klasor")) {
    sprintf(
      "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
      ns("dir_navigate"),
      gsub("'", "\\\\'", item$yol)
    )
  } else {
    NULL
  }

  shiny::tags$div(
    class = paste0("cc-dir-item cc-dir-", item$tip, ek_sinif),
    onclick = ek_olay,
    title = cc_dir_item_tooltip(item),
    shiny::icon(ikon),
    shiny::tags$span(class = "cc-dir-name", gorunen_ad),
    shiny::tags$span(class = "cc-dir-size", cc_format_dir_file_size(item$boyut))
  )
}

cc_build_dir_contents_ui <- function(contents, ns) {
  if (!isTRUE(contents$success)) {
    return(shiny::tags$p(class = "cc-dir-error", contents$error))
  }

  if (length(contents$items) == 0L) {
    return(shiny::tags$p(class = "cc-dir-empty", "Dizin boş."))
  }

  toplam <- suppressWarnings(as.integer(contents$toplam %||% length(contents$items)))
  if (is.na(toplam)) {
    toplam <- length(contents$items)
  }

  shiny::tags$div(
    class = "cc-dir-list",
    if (toplam > length(contents$items)) {
      shiny::tags$small(
        class = "cc-dir-count",
        paste0(toplam, " ögeden ilk ", length(contents$items), " tanesi")
      )
    },
    lapply(contents$items, cc_build_dir_item_ui, ns = ns)
  )
}