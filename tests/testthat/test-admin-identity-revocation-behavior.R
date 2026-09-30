# Yönetici modülleri açıkken kimlik ve yetki kaybı erişimi keser.

.admin_identity_env <- function() {
  env <- new.env(parent = globalenv())
  env$JS <- htmlwidgets::JS
  env$`%>%` <- magrittr::`%>%`
  for (ad in c("helpers_user_session_identity.R", "helpers_admin_analytics.R",
                "module_admin_analytics.R", "module_admin_geri_bildirim.R",
                "module_admin_hata_analizi.R", "module_admin_yanit_analizi.R",
                "helpers_admin_hata_detail_runtime.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", ad), encoding = "UTF-8", local = env)
  }
  env
}

test_that("dört açık yönetici modülünde önbellek ve sorgular canlı yetkiye bağlıdır", {
  env <- .admin_identity_env()
  sorgu <- 0L
  getir <- function(...) { sorgu <<- sorgu + 1L; list(gizli = "ADMIN") }
  env$admin_safe_query <- function(...) { sorgu <<- sorgu + 1L; data.frame(cnt = 0L) }
  env$admin_bilge_yolac_queries <- env$admin_gb_fetch_data <- env$admin_ha_fetch_data <-
    env$admin_yanit_collect_data <- getir
  env$admin_gb_outputs <- env$admin_yanit_outputs <- env$admin_ha_register_detail_runtime <-
    function(...) invisible(NULL)
  env$admin_ha_category_labels <- env$admin_ha_priority_labels <- env$admin_ha_status_labels <-
    function() character(0)
  env$admin_refresh_setup <- function(...) list(trigger = shiny::reactiveVal(0L))
  for (fn in c("admin_overview_outputs", "admin_users_outputs", "admin_ai_perf_outputs",
                "admin_feedback_outputs", "admin_chat_quality_outputs", "admin_time_analysis_outputs",
                "admin_advanced_analytics_outputs", "admin_bilge_yolac_outputs")) {
    env[[fn]] <- function(...) invisible(NULL)
  }
  moduller <- c(adminAnalyticsServer = "analytics_data", adminGeriBildirimServer = "gb_data",
                 adminHataAnaliziServer = "ha_data", adminYanitAnaliziServer = "ya_data")
  for (ad in names(moduller)) {
    shiny::testServer(env[[ad]], {
      veri <- env$make_user_session_data_accessors(session)
      veri$write_identity(list(username = "a"), 7L, list(auth_level = "ADMIN"), TRUE, "keycloak")
      saglayici <- get(moduller[[ad]])
      expect_type(saglayici(), "list")
      once <- sorgu
      veri$write_identity(list(username = "b"), 8L, list(auth_level = "USER"), TRUE, "keycloak")
      expect_error(saglayici(), class = "shiny.silent.error")
      expect_error(output$tab_content_area, class = "shiny.silent.error")
      expect_identical(sorgu, once)
      veri$write_identity(list(username = "b"), 8L, list(auth_level = "ADMIN"), TRUE, "keycloak")
      expect_type(saglayici(), "list")
      expect_gt(sorgu, once)
      once <- sorgu
      veri$write_identity(list(username = "b"), 8L, list(auth_level = "USER"), TRUE, "keycloak")
      expect_error(saglayici(), class = "shiny.silent.error")
      expect_identical(sorgu, once)
      veri$set_auth_placeholder()
      expect_error(saglayici(), class = "shiny.silent.error")
    })
  }
})

test_that("önceden açılmış hata ekleri ve doğrudan durum girdileri yetki kaybında reddedilir", {
  env <- .admin_identity_env()
  yazim <- 0L
  env$destek_hata_durum_guncelle <- function(...) yazim <<- yazim + 1L
  env$showToast <- env$admin_ha_show_modal <- function(...) invisible(NULL)
  env$admin_ha_attachment_content <- function(...) shiny::div("GIZLI_EK")
  shiny::testServer(function(input, output, session) {
    veri <- env$make_user_session_data_accessors(session)
    veri$write_identity(list(username = "a"), 7L, list(auth_level = "ADMIN"), TRUE, "keycloak")
    env$admin_ha_register_detail_runtime(input, output, session,
      function() list(tumu = data.frame(HataBildirimID = 1L, EkDosyaYollari = "gizli.txt", Durum = "acik")),
      list(trigger = shiny::reactiveVal(0L)), character(0), character(0), character(0))
  }, {
    session$setInputs(dosya_goster = 1L)
    expect_match(output$ek_dosya_content$html, "GIZLI_EK")
    veri$write_identity(list(username = "b"), 8L, list(auth_level = "USER"), TRUE, "keycloak")
    session$setInputs(dosya_goster = 2L, durum_guncelle = 1L, durum_kaydet = 1L,
                      durum_bildirim_id_val = 1L, yeni_durum = "cozuldu")
    expect_error(output$ek_dosya_content, class = "shiny.silent.error")
    expect_identical(yazim, 0L)
  })
})
