test_that("ek HTTP isteği canlı yetki, sahip nesli ve kök sınırını doğrular", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("openssl")
  env <- new.env(parent = globalenv())
  env$JS <- htmlwidgets::JS
  for (ad in c("helpers_user_session_identity.R", "helpers_files_path.R",
                "helpers_admin_analytics.R", "helpers_admin_attachments.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", ad), encoding = "UTF-8", local = env)
  }
  env$destek_uploads_dir <- withr::local_tempdir()
  writeBin(charToRaw("gizli"), file.path(env$destek_uploads_dir, "ek.png"))
  kayit <- NULL
  shiny::testServer(function(input, output, session) NULL, {
    session$registerDataObj <- function(name, data, filterFunc) {
      kayit <<- list(name = name, data = data, filter = filterFunc)
      "/session/data?w=1"
    }
    veri <- env$make_user_session_data_accessors(session)
    veri$write_identity(list(username = "a"), 7L, list(auth_level = "ADMIN"), TRUE, "keycloak")
    urls <- env$admin_ha_attachment_urls(session, c("ek.png", "../disarida.txt"))
    expect_identical(unname(urls[2]), "")
    istek <- list(QUERY_STRING = sub("^[^?]*\\?", "", urls[1]))
    yanit <- kayit$filter(kayit$data, istek)
    expect_identical(yanit$status, 200L)
    expect_identical(readBin(yanit$content$file, "raw", 5L), charToRaw("gizli"))
    expect_identical(yanit$headers$`Cache-Control`, "no-store")
    eski <- kayit
    veri$write_identity(list(username = "a"), 7L, list(auth_level = "USER"), TRUE, "keycloak")
    expect_identical(eski$filter(eski$data, istek)$status, 403L)
    veri$write_identity(list(username = "b"), 8L, list(auth_level = "ADMIN"), TRUE, "keycloak")
    expect_identical(eski$filter(eski$data, istek)$status, 403L)
    yeni <- env$admin_ha_attachment_urls(session, "ek.png")
    expect_false(identical(yeni, urls[1]))
    expect_identical(kayit$filter(kayit$data, istek)$status, 403L)
    istek$QUERY_STRING <- sub("^[^?]*\\?", "", yeni[1])
    expect_identical(kayit$filter(kayit$data, istek)$status, 200L)
    if (.Platform$OS.type != "windows") {
      dis <- withr::local_tempfile()
      writeLines("disarida", dis)
      expect_true(file.symlink(dis, file.path(env$destek_uploads_dir, "bag.png")))
      expect_identical(unname(env$admin_ha_attachment_urls(session, "bag.png")), "")
    }
  })
})

test_that("destek eki dizini global statik kaynak olarak kayıt edilmez", {
  s <- readLines(file.path(resolve_repo_root_for_tests(), "global.R"), encoding = "UTF-8", warn = FALSE)
  expect_false(any(grepl('register_global_resource_path("destek_uploads"', s, fixed = TRUE)))
})
