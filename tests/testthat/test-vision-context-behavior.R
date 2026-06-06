# ==============================================================================
# Dosya Yolu: tests/testthat/test-vision-context-behavior.R
# Açıklama: Model Bağlamı görsel (vision) yardımcılarının ve send_message dosya
#           bağlamı entegrasyonunun davranışını doğrular. Vision yalnızca bayrak
#           + model yeteneği birlikte açıkken devreye girer; aksi halde metin
#           yolu birebir korunur ve görseller için açık not eklenir.
#           Çevrimdışı/deterministik: gerçek LLM/ağ/DB yok.
# ==============================================================================

repo_root_vision <- resolve_repo_root_for_tests()

.vision_env <- new.env(parent = globalenv())
source(file.path(repo_root_vision, "R/utils_common.R"), encoding = "UTF-8", local = .vision_env)
source(file.path(repo_root_vision, "R/utils_session_cleanup.R"), encoding = "UTF-8", local = .vision_env)
source(file.path(repo_root_vision, "R/helpers_file_manager_policy.R"), encoding = "UTF-8", local = .vision_env)
source(file.path(repo_root_vision, "R/helpers_vision_context.R"), encoding = "UTF-8", local = .vision_env)
source(file.path(repo_root_vision, "R/helpers_send_message_prompting.R"), encoding = "UTF-8", local = .vision_env)

# Test boyunca vision bayraklarını temiz tutan yardımcı.
.with_vision_flags <- function(enabled, code) {
  old_opt <- getOption("mergen.vision_enabled", NULL)
  old_env <- Sys.getenv("MERGEN_ENABLE_VISION", unset = NA)
  on.exit({
    options(mergen.vision_enabled = old_opt)
    if (is.na(old_env)) Sys.unsetenv("MERGEN_ENABLE_VISION") else Sys.setenv(MERGEN_ENABLE_VISION = old_env)
  }, add = TRUE)
  options(mergen.vision_enabled = enabled)
  Sys.unsetenv("MERGEN_ENABLE_VISION")
  force(code)
}

# Küçük geçici görsel dosyası üretir (PNG imzası ile).
.make_tmp_png <- function() {
  tf <- tempfile(fileext = ".png")
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02)), tf)
  tf
}

test_that("mergen_is_image_file uzantıyı doğru sınıflandırır", {
  expect_true(.vision_env$mergen_is_image_file("kedi.png"))
  expect_true(.vision_env$mergen_is_image_file("FOTO.JPG"))
  expect_true(.vision_env$mergen_is_image_file("logo.svg"))
  expect_false(.vision_env$mergen_is_image_file("rapor.pdf"))
  expect_false(.vision_env$mergen_is_image_file("veri.xlsx"))
  expect_false(.vision_env$mergen_is_image_file(""))
  expect_false(.vision_env$mergen_is_image_file(NA_character_))
})

test_that("mergen_image_mime_type doğru MIME döndürür", {
  expect_identical(.vision_env$mergen_image_mime_type("a.jpg"), "image/jpeg")
  expect_identical(.vision_env$mergen_image_mime_type("a.jpeg"), "image/jpeg")
  expect_identical(.vision_env$mergen_image_mime_type("a.png"), "image/png")
  expect_identical(.vision_env$mergen_image_mime_type("a.svg"), "image/svg+xml")
  expect_identical(.vision_env$mergen_image_mime_type("a.bin"), "application/octet-stream")
})

test_that("mergen_vision_enabled varsayılan KAPALI, bayrakla açılır", {
  .with_vision_flags(NULL, {
    expect_false(.vision_env$mergen_vision_enabled())
  })
  .with_vision_flags(TRUE, {
    expect_true(.vision_env$mergen_vision_enabled())
  })
  # Ortam değişkeni yolu
  old_env <- Sys.getenv("MERGEN_ENABLE_VISION", unset = NA)
  on.exit(if (is.na(old_env)) Sys.unsetenv("MERGEN_ENABLE_VISION") else Sys.setenv(MERGEN_ENABLE_VISION = old_env), add = TRUE)
  options(mergen.vision_enabled = NULL)
  Sys.setenv(MERGEN_ENABLE_VISION = "true")
  expect_true(.vision_env$mergen_vision_enabled())
  Sys.setenv(MERGEN_ENABLE_VISION = "garbage")
  expect_false(.vision_env$mergen_vision_enabled())
})

test_that("mergen_is_vision_model yalnızca yapılandırılmış yeteneğe güvenir", {
  cfg <- list(local_model_capabilities = list(
    "vmod" = list(vision = TRUE),
    "tmod" = list(thinking = TRUE)
  ))
  expect_true(.vision_env$mergen_is_vision_model("vmod", cfg))
  expect_false(.vision_env$mergen_is_vision_model("tmod", cfg))
  expect_false(.vision_env$mergen_is_vision_model("bilinmeyen", cfg))
  expect_false(.vision_env$mergen_is_vision_model("", cfg))
  expect_false(.vision_env$mergen_is_vision_model(NA_character_, cfg))
})

test_that("mergen_vision_active iki kapıyı birlikte ister", {
  cfg <- list(local_model_capabilities = list("vmod" = list(vision = TRUE)))
  .with_vision_flags(TRUE, {
    expect_true(.vision_env$mergen_vision_active("vmod", cfg))
    expect_false(.vision_env$mergen_vision_active("tmod", cfg))
  })
  .with_vision_flags(NULL, {
    expect_false(.vision_env$mergen_vision_active("vmod", cfg))
  })
})

test_that("mergen_build_image_data_url base64 data-url üretir, sınırları korur", {
  tf <- .make_tmp_png()
  on.exit(unlink(tf), add = TRUE)
  du <- .vision_env$mergen_build_image_data_url(tf)
  expect_true(is.character(du))
  expect_true(startsWith(du, "data:image/png;base64,"))
  # Boyut sınırı aşılırsa NULL
  expect_null(.vision_env$mergen_build_image_data_url(tf, max_bytes = 1))
  # Olmayan dosya NULL
  expect_null(.vision_env$mergen_build_image_data_url("/yok/dosya.png"))
  # Boş/NA girdi NULL
  expect_null(.vision_env$mergen_build_image_data_url(""))
  expect_null(.vision_env$mergen_build_image_data_url(NA_character_))
})

test_that("mergen_build_vision_user_content OpenAI çok-kipli yapı üretir", {
  content <- .vision_env$mergen_build_vision_user_content(
    "Bu görselde ne var?",
    c("data:image/png;base64,AAA", "data:image/jpeg;base64,BBB")
  )
  expect_length(content, 3L)
  expect_identical(content[[1]]$type, "text")
  expect_identical(content[[1]]$text, "Bu görselde ne var?")
  expect_identical(content[[2]]$type, "image_url")
  expect_identical(content[[2]]$image_url$url, "data:image/png;base64,AAA")
  expect_identical(content[[3]]$type, "image_url")
  # Boş metin atlanır, geçersiz url atlanır
  c2 <- .vision_env$mergen_build_vision_user_content("", c("", "data:image/png;base64,CCC"))
  expect_length(c2, 1L)
  expect_identical(c2[[1]]$type, "image_url")
})

test_that("mergen_vision_unavailable_note dosya adını ve açık uyarıyı içerir", {
  note <- .vision_env$mergen_vision_unavailable_note("kedi.png")
  expect_true(grepl("kedi.png", note, fixed = TRUE))
  expect_true(grepl("analiz edilemiyor", note, fixed = TRUE))
})

test_that("prepare_context_blocks: vision KAPALI görsel için açık not, metin değişmez", {
  stores <- list("rapor.pdf" = "PDF ozet metni")
  files <- list("kedi.png" = list(datapath = .make_tmp_png()))
  on.exit(unlink(files[["kedi.png"]]$datapath), add = TRUE)

  res <- .vision_env$mergen_vision_prepare_context_blocks(
    uploaded_names = c("rapor.pdf", "kedi.png"),
    summary_store = stores,
    current_file_store = files,
    per_file_cap = 5000,
    vision_active = FALSE
  )
  expect_length(res$image_data_urls, 0L)
  blob <- paste(res$file_blocks, collapse = "\n")
  expect_true(grepl("PDF ozet metni", blob, fixed = TRUE))
  expect_true(grepl("analiz edilemiyor", blob, fixed = TRUE))
  expect_false(grepl("data:image", blob, fixed = TRUE))
})

test_that("prepare_context_blocks: vision AÇIK görseli data-url'e çevirir", {
  tf <- .make_tmp_png()
  on.exit(unlink(tf), add = TRUE)
  files <- list("kedi.png" = list(datapath = tf))

  res <- .vision_env$mergen_vision_prepare_context_blocks(
    uploaded_names = c("kedi.png"),
    summary_store = list(),
    current_file_store = files,
    per_file_cap = 5000,
    vision_active = TRUE
  )
  expect_length(res$image_data_urls, 1L)
  expect_true(startsWith(res$image_data_urls[1], "data:image/png;base64,"))
  expect_true(grepl("analiz için isteğe eklendi", paste(res$file_blocks, collapse = "\n"), fixed = TRUE))
})

test_that("send_message none dalı: vision KAPALI metin (string) içerik üretir", {
  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$file_summaries <- list()
  session$userData$current_session_files <- list("kedi.png" = list(datapath = .make_tmp_png()))
  on.exit(unlink(session$userData$current_session_files[["kedi.png"]]$datapath), add = TRUE)

  recent_messages <- list(list(type = "user", content = "Bu görselde ne var?"))

  .with_vision_flags(NULL, {
    plan <- .vision_env$mergen_build_uploaded_files_context_messages(
      tool_family = "none",
      uploaded_count = 1L,
      uploaded_names = c("kedi.png"),
      recent_messages = recent_messages,
      system_msg = list(type = "system", content = "SYS"),
      session = session,
      messages_to_process = recent_messages,
      model_selected = "vmod",
      api_config = list(local_model_capabilities = list("vmod" = list(vision = TRUE)))
    )
  })

  final <- plan$messages_to_process[[2]]$content
  expect_true(is.character(final))
  expect_true(grepl("analiz edilemiyor", final, fixed = TRUE))
  expect_true(grepl("Kaynakça:", final, fixed = TRUE))
})

test_that("send_message none dalı: vision AÇIK çok-kipli image_url parçası ekler", {
  tf <- .make_tmp_png()
  on.exit(unlink(tf), add = TRUE)
  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$file_summaries <- list()
  session$userData$current_session_files <- list("kedi.png" = list(datapath = tf))

  recent_messages <- list(list(type = "user", content = "Bu görselde ne var?"))

  plan <- .with_vision_flags(TRUE, {
    .vision_env$mergen_build_uploaded_files_context_messages(
      tool_family = "none",
      uploaded_count = 1L,
      uploaded_names = c("kedi.png"),
      recent_messages = recent_messages,
      system_msg = list(type = "system", content = "SYS"),
      session = session,
      messages_to_process = recent_messages,
      model_selected = "vmod",
      api_config = list(local_model_capabilities = list("vmod" = list(vision = TRUE)))
    )
  })

  final <- plan$messages_to_process[[2]]$content
  expect_true(is.list(final))
  types <- vapply(final, function(p) p$type %||% "", character(1))
  expect_true("text" %in% types)
  expect_true("image_url" %in% types)
  img_part <- Find(function(p) identical(p$type, "image_url"), final)
  expect_true(startsWith(img_part$image_url$url, "data:image/png;base64,"))
})

test_that("vision AÇIK ama görsel okunamazsa metin yoluna güvenli düşer", {
  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$file_summaries <- list()
  # datapath olmayan dosya -> data-url üretilemez -> açık not, string içerik
  session$userData$current_session_files <- list("kedi.png" = list(datapath = "/yok/kedi.png"))

  recent_messages <- list(list(type = "user", content = "Bu görselde ne var?"))

  plan <- .with_vision_flags(TRUE, {
    .vision_env$mergen_build_uploaded_files_context_messages(
      tool_family = "none",
      uploaded_count = 1L,
      uploaded_names = c("kedi.png"),
      recent_messages = recent_messages,
      system_msg = list(type = "system", content = "SYS"),
      session = session,
      messages_to_process = recent_messages,
      model_selected = "vmod",
      api_config = list(local_model_capabilities = list("vmod" = list(vision = TRUE)))
    )
  })

  final <- plan$messages_to_process[[2]]$content
  expect_true(is.character(final))
  expect_true(grepl("analiz edilemiyor", final, fixed = TRUE))
})

test_that("çok-kipli içerik OpenAI uyumlu JSON gövdeye serileşir", {
  content <- .vision_env$mergen_build_vision_user_content(
    "Bu görselde ne var?",
    c("data:image/png;base64,AAAB")
  )
  body <- list(
    model = "vmod",
    messages = list(list(role = "user", content = content)),
    stream = FALSE
  )
  json <- as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
  expect_true(grepl('"type":"image_url"', json, fixed = TRUE))
  expect_true(grepl('"url":"data:image/png;base64,AAAB"', json, fixed = TRUE))
  expect_true(grepl('"type":"text"', json, fixed = TRUE))
  # role tek string olarak kalmalı (auto_unbox)
  expect_true(grepl('"role":"user"', json, fixed = TRUE))
})
