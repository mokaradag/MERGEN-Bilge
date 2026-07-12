# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-sources-behavior.R
# Açıklama: Langflow belge kaynak üstverisi çıkarımı (başlık/yol/sayfa/tür),
#           Kaynakça işaretleyici bloğu (üretim/ayrıştırma) ve güvenli
#           tıklanabilir kaynak HTML'i davranış testleri. PDF/DOCX kaynakların
#           mevcut kaynak tıklama -> güvenli önizleme mekanizmasına giden
#           .source-link işaretlemesini ürettiği, kaynak uydurulmadığı ve XSS
#           kaçış sınırının korunduğu doğrulanır. Tüm testler çevrimdışı ve
#           deterministiktir (gerçek Langflow/ağ/DB/tarayıcı yoktur).
# ==============================================================================

.source_langflow_sources_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/helpers_api_model_config.R",
    "R/helpers_api_model_tool_runtime.R",
    "R/helpers_langflow_runtime.R",
    "R/helpers_langflow_sources.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  env
}

# Gerçekçi Langflow Chat Output yanıt iskeleti: message düğümüne kaynak alanı
# yerleştirmek için ortak kurucu.
.langflow_sources_response <- function(message_extra = list(), output_extra = list()) {
  message_node <- c(list(text = "Cevap metni"), message_extra)
  output_node <- c(list(results = list(message = message_node)), output_extra)
  list(
    session_id = "mergen_1_2",
    outputs = list(list(
      inputs = list(input_value = "soru"),
      outputs = list(output_node)
    ))
  )
}

test_that("extract_langflow_chat_sources results$message$sources altındaki PDF/DOCX kayıtlarını çıkarır", {
  env <- .source_langflow_sources_env()

  parsed <- .langflow_sources_response(message_extra = list(
    sources = list(
      list(title = "Kalite Prosedürü", file_path = "surecler/kalite/prosedur.pdf", page = 3, type = "pdf"),
      # Eski RAG proxy biçimi: metadata dizisi + source yolundan başlık türetme
      list(metadata = list(list(source = "rehber/kullanim_kilavuzu.docx", page_number = "12")))
    )
  ))

  src <- env$extract_langflow_chat_sources(parsed)
  expect_length(src, 2L)

  expect_identical(src[[1]]$title, "Kalite Prosedürü")
  expect_identical(src[[1]]$path, "surecler/kalite/prosedur.pdf")
  expect_identical(src[[1]]$page, "3")
  expect_identical(src[[1]]$type, "pdf")

  # Başlık verilmediyse yol basename'inden türetilir; tür uzantıdan çözülür.
  expect_identical(src[[2]]$title, "kullanim_kilavuzu.docx")
  expect_identical(src[[2]]$page, "12")
  expect_identical(src[[2]]$type, "docx")
})

test_that("extract_langflow_chat_sources data$sources, artifacts$sources, source_documents ve üst düzey sources şekillerini destekler", {
  env <- .source_langflow_sources_env()

  data_shape <- .langflow_sources_response(message_extra = list(
    data = list(sources = list(list(name = "veri.pdf", file_path = "docs/veri.pdf")))
  ))
  expect_identical(env$extract_langflow_chat_sources(data_shape)[[1]]$title, "veri.pdf")

  artifacts_shape <- .langflow_sources_response(output_extra = list(
    artifacts = list(sources = list(list(title = "Artefakt Raporu", path = "raporlar/artefakt.docx")))
  ))
  art <- env$extract_langflow_chat_sources(artifacts_shape)
  expect_identical(art[[1]]$title, "Artefakt Raporu")
  expect_identical(art[[1]]$type, "docx")

  sd_shape <- .langflow_sources_response(message_extra = list(
    source_documents = list(list(metadata = list(source = "sd/el_kitabi.pdf", page = 7)))
  ))
  sd <- env$extract_langflow_chat_sources(sd_shape)
  expect_identical(sd[[1]]$title, "el_kitabi.pdf")
  expect_identical(sd[[1]]$page, "7")

  top_shape <- list(sources = list(list(name = "ust_duzey.pdf")), text = "x")
  expect_identical(env$extract_langflow_chat_sources(top_shape)[[1]]$title, "ust_duzey.pdf")

  single_object_shape <- list(sources = list(name = "tekil.pdf", file_path = "docs/tekil.pdf"))
  expect_identical(env$extract_langflow_chat_sources(single_object_shape)[[1]]$path, "docs/tekil.pdf")
})

test_that("extract_langflow_chat_sources görünen başlık + file_name/filename (yol yokken) dosya adını yol adayı sayar", {
  env <- .source_langflow_sources_env()

  # Yaygın kaynak biçimi: dosya-benzeri olmayan görünen başlık + file_name.
  # file_name yol adayı olmasaydı path_like(title) başlığı reddederdi.
  fn_shape <- .langflow_sources_response(message_extra = list(
    sources = list(list(title = "Kalite Prosedürü", file_name = "prosedur.pdf"))
  ))
  fn <- env$extract_langflow_chat_sources(fn_shape)
  expect_length(fn, 1L)
  expect_identical(fn[[1]]$title, "Kalite Prosedürü")
  expect_identical(fn[[1]]$path, "prosedur.pdf")
  expect_identical(fn[[1]]$type, "pdf")

  # filename varyantı da desteklenir.
  filename_shape <- .langflow_sources_response(message_extra = list(
    sources = list(list(display_name = "Kullanım Kılavuzu", filename = "kilavuz.docx"))
  ))
  fl <- env$extract_langflow_chat_sources(filename_shape)
  expect_length(fl, 1L)
  expect_identical(fl[[1]]$path, "kilavuz.docx")

  # Gerçek yol alanı varsa o önceliklidir; file_name yalnızca yedektir.
  both_shape <- .langflow_sources_response(message_extra = list(
    sources = list(list(title = "Rapor", file_path = "docs/rapor.pdf", file_name = "rapor.pdf"))
  ))
  expect_identical(env$extract_langflow_chat_sources(both_shape)[[1]]$path, "docs/rapor.pdf")
})

test_that("extract_langflow_chat_sources kaynak uydurmaz: üstveri yoksa/ilgisizse boş liste döner", {
  env <- .source_langflow_sources_env()

  # Kaynak alanı hiç yok
  expect_length(env$extract_langflow_chat_sources(.langflow_sources_response()), 0L)

  # properties$source model/bileşen bilgisidir; belge kaynağı DEĞİLDİR.
  props <- .langflow_sources_response(message_extra = list(
    properties = list(source = list(id = "m1", display_name = "Model", source = "ornek-model"))
  ))
  expect_length(env$extract_langflow_chat_sources(props), 0L)

  # Ad/yol içermeyen veya liste olmayan kaynak öğeleri atlanır.
  junk <- .langflow_sources_response(message_extra = list(
    sources = list(list(page = 3), "duz-metin", 42)
  ))
  expect_length(env$extract_langflow_chat_sources(junk), 0L)

  expect_length(env$extract_langflow_chat_sources(NULL), 0L)
  expect_length(env$extract_langflow_chat_sources(list()), 0L)

  # Tek başına düz source/model adı dosya kaynağı gibi uydurulmaz.
  source_scalar <- .langflow_sources_response(message_extra = list(
    sources = list(list(source = "OpenAIModelComponent"))
  ))
  expect_length(env$extract_langflow_chat_sources(source_scalar), 0L)

  url_source <- .langflow_sources_response(message_extra = list(
    sources = list(list(title = "Dış URL", source = "https://example.invalid/doc.pdf"))
  ))
  expect_length(env$extract_langflow_chat_sources(url_source), 0L)

  executable_name <- .langflow_sources_response(message_extra = list(
    sources = list(list(name = "kurulum.exe"))
  ))
  expect_length(env$extract_langflow_chat_sources(executable_name), 0L)

  slash_component <- .langflow_sources_response(message_extra = list(
    sources = list(list(source = "components/vector_store"))
  ))
  expect_length(env$extract_langflow_chat_sources(slash_component), 0L)

  traversal_source <- .langflow_sources_response(message_extra = list(
    sources = list(list(title = "Kaçış", source = "../gizli/rapor.pdf"))
  ))
  expect_length(env$extract_langflow_chat_sources(traversal_source), 0L)

  drive_source <- .langflow_sources_response(message_extra = list(
    sources = list(list(title = "Sürücü", source = "C:/gizli/rapor.pdf"))
  ))
  expect_length(env$extract_langflow_chat_sources(drive_source), 0L)
})

test_that("extract_langflow_chat_sources kayıtları (yol, sayfa) anahtarıyla tekler ve üst sınırı uygular", {
  env <- .source_langflow_sources_env()

  parsed <- .langflow_sources_response(message_extra = list(
    sources = list(
      list(name = "ayni.pdf", file_path = "d/ayni.pdf", page = 1),
      list(name = "ayni.pdf", file_path = "d/ayni.pdf", page = 1),  # birebir tekrar
      list(name = "ayni.pdf", file_path = "d/ayni.pdf", page = 2)   # farklı sayfa korunur
    )
  ))
  src <- env$extract_langflow_chat_sources(parsed)
  expect_length(src, 2L)

  many <- .langflow_sources_response(message_extra = list(
    sources = lapply(seq_len(30), function(i) list(name = paste0("dok", i, ".pdf")))
  ))
  expect_length(env$extract_langflow_chat_sources(many), 20L)
  expect_length(env$extract_langflow_chat_sources(many, max_sources = NA), 0L)
  expect_length(env$extract_langflow_chat_sources(many, max_sources = 0), 0L)
})

test_that("call_langflow_chat başarı sonucunda sources alanını taşır (yapı sözleşmesi)", {
  env <- .source_langflow_sources_env()

  # HTTP yapılmadan yapı sözleşmesi: başarısız (eksik yapılandırma) dönüşte bile
  # liste alanları tanımlıdır; başarı dalındaki sources ekleme yolu statik olarak
  # doğrulanır (çıkarıcı fonksiyona güvenli exists() köprüsüyle bağlanır).
  res <- env$call_langflow_chat(input_value = "q", base_url = "", flow_id = "")
  expect_false(res$success)

  runtime_path <- file.path(resolve_repo_root_for_tests(), "R", "helpers_langflow_runtime.R")
  raw_bytes <- readBin(runtime_path, what = "raw", n = file.info(runtime_path)$size)
  txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_true(grepl("mergen_langflow_safe_sources(parsed)", txt, fixed = TRUE))
  expect_true(grepl("sources = sources", txt, fixed = TRUE))

  # Güvenli sarmalayıcı hatada boş listeye düşer (yanıt metni asla düşmez).
  expect_identical(env$mergen_langflow_safe_sources(structure(list(), class = "hatalı")), list())
})

test_that("mergen_langflow_kaynakca_marker_block düz metin işaretleyici bloğunu üretir ve gramer bozucu karakterleri temizler", {
  env <- .source_langflow_sources_env()

  blok <- env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf"),
    # Başlıkta '|' alan ayracıdır ve temizlenir; köşeli parantezler ise geçerli
    # dosya adı karakteri olduğundan hem başlıkta hem YOLDA korunur.
    list(title = "Kılavuz | [Rev 2]", path = "rehber/Kılavuz [Rev 2].docx", page = "", type = "docx")
  ))

  expect_match(blok, "\n\nKaynakça:\n", fixed = TRUE)
  expect_match(blok, "\\[KAYNAK 1\\] Kalite Prosedürü \\| yol=surecler/kalite/prosedur\\.pdf \\| kod=[0-9a-f]+ \\| sayfa=3 \\| tur=pdf")
  # '|' temizlenir; köşeli parantezler korunur ve yol=... değerinde diskteki
  # dosya adıyla eşleşebilmesi için olduğu gibi kalır.
  expect_match(blok, "\\[KAYNAK 2\\] Kılavuz \\[Rev 2\\] \\| yol=rehber/Kılavuz \\[Rev 2\\]\\.docx \\| kod=[0-9a-f]+ \\| tur=docx")

  expect_identical(env$mergen_langflow_kaynakca_marker_block(list()), "")
  expect_identical(env$mergen_langflow_kaynakca_marker_block(NULL), "")
  # Başlıksız kayıt satır üretmez (kaynak uydurulmaz).
  expect_identical(env$mergen_langflow_kaynakca_marker_block(list(list(path = "x.pdf"))), "")
  # Güvenli göreli yol dışındaki kayıtlar marker bloğuna yazılmaz.
  expect_identical(env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Kaçış", path = "../gizli/rapor.pdf", page = "", type = "pdf")
  )), "")
})

test_that("mergen_kaynakca_marker_split yalnızca mesaj sonundaki geçerli bloğu ayırır; bozuk blok tümüyle reddedilir", {
  env <- .source_langflow_sources_env()

  full <- paste0(
    "Cevap metni.",
    env$mergen_langflow_kaynakca_marker_block(list(
      list(title = "Prosedür", path = "a/b.pdf", page = "3", type = "pdf"),
      list(title = "Kılavuz", path = "c/d.docx", page = "", type = "docx")
    ))
  )
  sp <- env$mergen_kaynakca_marker_split(full)
  expect_false(is.null(sp))
  expect_identical(sp$prose, "Cevap metni.")
  expect_length(sp$entries, 2L)
  expect_identical(sp$entries[[1]]$path, "a/b.pdf")
  expect_identical(sp$entries[[2]]$type, "docx")

  # Blok yoksa NULL
  expect_null(env$mergen_kaynakca_marker_split("Sade cevap."))
  expect_null(env$mergen_kaynakca_marker_split(""))
  expect_null(env$mergen_kaynakca_marker_split(NULL))

  # Modelin kendi yazdığı düz Kaynakça listesi ([KAYNAK ...] satırı yok) yükseltilmez.
  expect_null(env$mergen_kaynakca_marker_split("Cevap.\n\nKaynakça:\n1) dosya.pdf\n"))

  # Bütünlük kodu olmayan [KAYNAK] benzeri metin tıklanabilir kaynağa yükseltilmez.
  expect_null(env$mergen_kaynakca_marker_split(
    "Cevap.\n\nKaynakça:\n[KAYNAK 1] Başlık | yol=a.pdf | tur=pdf\n"
  ))

  tampered <- paste0("Cevap.", env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Başlık", path = "a.pdf", page = "", type = "pdf")
  )))
  tampered <- sub("Başlık", "Başka Başlık", tampered, fixed = TRUE)
  expect_null(env$mergen_kaynakca_marker_split(tampered))

  # Bilinmeyen alan anahtarı: blok tümüyle reddedilir (kısmi yükseltme yok).
  expect_null(env$mergen_kaynakca_marker_split(
    "Cevap.\n\nKaynakça:\n[KAYNAK 1] Başlık | zararli=deger\n"
  ))

  # Rakam olmayan sayfa değeri de bloğu geçersiz kılar.
  bad_page <- paste0("Cevap.", env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Başlık", path = "a.pdf", page = "1", type = "")
  )))
  bad_page <- sub("sayfa=1", "sayfa=abc", bad_page, fixed = TRUE)
  expect_null(env$mergen_kaynakca_marker_split(bad_page))

  # Blok mesajın SONUNDA değilse ayrılmaz.
  trailing <- paste0("Cevap.", env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Başlık", path = "a.pdf", page = "", type = "pdf")
  )), "\nDevam eden metin.")
  expect_null(env$mergen_kaynakca_marker_split(trailing))
})

test_that("mergen_kaynakca_marker_html mevcut tıklanabilir kaynak işaretlemesini (source-link) güvenli biçimde üretir", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_sources_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf"),
    list(title = "Kullanım Kılavuzu", path = "rehber/kilavuz.docx", page = "", type = "docx")
  ))

  # Mevcut tıklama mekanizmasının beklediği sınıf/veri öznitelikleri.
  expect_match(html, "class='kaynakca-entry' data-entry='1'", fixed = TRUE)
  expect_match(html, "class='source-link'", fixed = TRUE)
  expect_match(html, "data-filename='surecler&amp;&amp;kalite&amp;&amp;prosedur.pdf'", fixed = TRUE)
  expect_match(html, "data-filename='rehber&amp;&amp;kilavuz.docx'", fixed = TRUE)
  # PDF ve Word ikonları tür bilgisinden seçilir.
  expect_match(html, "fa-file-pdf", fixed = TRUE)
  expect_match(html, "fa-file-word", fixed = TRUE)
  # Sayfa bilgisi görünür eke dönüşür.
  expect_match(html, "(Sayfa 3)", fixed = TRUE)

  expect_identical(env$mergen_kaynakca_marker_html(list()), "")
  expect_identical(env$mergen_kaynakca_marker_html(NULL), "")
})

test_that("mergen_kaynakca_marker_html işaretleyiciden gelen değerleri kaçışlar (XSS sınırı) ve gezinme ipuçlarını temizler", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_sources_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "<img src=x onerror=alert(1)>", path = "a'b/<script>.pdf", page = "2", type = "pdf"),
    list(title = "Kök Deneme", path = "../../etc/passwd", page = "", type = ""),
    list(title = "Sürücü Deneme", path = "C:\\gizli\\dosya.docx", page = "", type = "")
  ))

  # Ham HTML/script asla çıkmaz; tüm değerler kaçışlıdır.
  expect_false(grepl("<img", html, fixed = TRUE))
  expect_false(grepl("<script", html, fixed = TRUE))
  expect_match(html, "&lt;img src=x onerror=alert(1)&gt;", fixed = TRUE)

  # Tıklama ipucunda ".." ve sürücü/kök parçaları ayıklanır (gezinme ipucu üretilemez).
  expect_false(grepl("..&", html, fixed = TRUE))
  expect_false(grepl("\\.\\.", gsub("&amp;", "&", html)))
  expect_match(html, "data-filename='etc&amp;&amp;passwd'", fixed = TRUE)
  expect_match(html, "data-filename='gizli&amp;&amp;dosya.docx'", fixed = TRUE)
})

test_that("köşeli parantez içeren dosya adı üret->ayır->tıklama ipucu turunda korunur (disk eşleşmesi)", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_sources_env()

  # Gerçek dosya adı köşeli parantez içerir: "Prosedür [Rev 2].pdf". Değer
  # işaretleyiciye yazılır, geri ayrıştırılır ve tıklama ipucuna dönüşürken
  # parantezler korunmalı; aksi halde handle_source_file_click diskteki dosyayı
  # bulamaz.
  full <- paste0(
    "Cevap.",
    env$mergen_langflow_kaynakca_marker_block(list(
      list(title = "Prosedür [Rev 2]", path = "surecler/Prosedür [Rev 2].pdf", page = "5", type = "pdf")
    ))
  )
  sp <- env$mergen_kaynakca_marker_split(full)
  expect_false(is.null(sp))
  expect_length(sp$entries, 1L)
  # Ayrıştırılan yol parantezleri korur (bütünlük kodu da bu yol üzerinden doğrular).
  expect_identical(sp$entries[[1]]$path, "surecler/Prosedür [Rev 2].pdf")

  html <- env$mergen_kaynakca_marker_html(sp$entries)
  # Tıklama ipucu (data-filename) dosya adını parantezlerle taşır (HTML kaçışlı).
  expect_match(html, "data-filename='surecler&amp;&amp;Prosedür [Rev 2].pdf'", fixed = TRUE)
})

test_that("process_message_content yapay zekâ mesajındaki işaretleyici bloğu tıklanabilir Kaynakça'ya yükseltir", {
  testthat::skip_if_not_installed("htmltools")
  testthat::skip_if_not_installed("commonmark")
  testthat::skip_if_not_installed("stringr")

  repo_root <- resolve_repo_root_for_tests()
  env <- .source_langflow_sources_env()
  env$HTML <- htmltools::HTML
  for (f in c("R/helpers_markdown_safety.R", "R/helpers_language.R", "R/helpers_messaging.R")) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  full <- paste0(
    "Langflow cevabı **kalın** metin içerir.",
    env$mergen_langflow_kaynakca_marker_block(list(
      list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf"),
      list(title = "Kullanım Kılavuzu", path = "rehber/kilavuz.docx", page = "12", type = "docx")
    ))
  )

  out <- env$process_message_content(full, "ai")

  # Düzyazı normal güvenli markdown yolundan geçti.
  expect_match(out$html, "<strong>kalın</strong>", fixed = TRUE)
  # İşaretleyici görünmez; tıklanabilir kaynak işaretlemesi üretildi.
  expect_false(grepl("[KAYNAK", out$html, fixed = TRUE))
  expect_match(out$html, "class='source-link'", fixed = TRUE)
  expect_match(out$html, "data-filename='surecler&amp;&amp;kalite&amp;&amp;prosedur.pdf'", fixed = TRUE)
  expect_match(out$html, "(Sayfa 3)", fixed = TRUE)
  # Türkçe başlık bozulmadan render edildi.
  expect_match(out$html, "Kullanım Kılavuzu", fixed = TRUE)

  # assistant tipi de yükseltilir (DB yeniden yükleme yolu).
  out_assistant <- env$process_message_content(full, "assistant")
  expect_match(out_assistant$html, "class='source-link'", fixed = TRUE)
})

test_that("process_message_content kullanıcı mesajını ve kaynaksız yanıtı yükseltmez; ham span geçirmez", {
  testthat::skip_if_not_installed("htmltools")
  testthat::skip_if_not_installed("commonmark")
  testthat::skip_if_not_installed("stringr")

  repo_root <- resolve_repo_root_for_tests()
  env <- .source_langflow_sources_env()
  env$HTML <- htmltools::HTML
  for (f in c("R/helpers_markdown_safety.R", "R/helpers_language.R", "R/helpers_messaging.R")) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  marker_text <- paste0("Metin.", env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "Deneme", path = "a/b.pdf", page = "", type = "pdf")
  )))

  # Kullanıcı mesajı ASLA tıklanabilir kaynağa yükseltilmez.
  user_out <- env$process_message_content(marker_text, "user")
  expect_false(grepl("class='source-link'", user_out$html, fixed = TRUE))

  # Kaynak üstverisi olmayan yanıt değişmeden normal yoldan geçer.
  plain_out <- env$process_message_content("Sade Langflow cevabı.", "ai")
  expect_false(grepl("kaynakca-block", plain_out$html, fixed = TRUE))
  expect_match(plain_out$html, "Sade Langflow cevabı.", fixed = TRUE)

  # Modelin uydurduğu bozuk blok yükseltilmez ve içindeki ham HTML kaçışlı kalır.
  fake <- "Cevap.\n\nKaynakça:\n[KAYNAK 1] <b>x</b> | yol=a.pdf | zararli=1\n"
  fake_out <- env$process_message_content(fake, "ai")
  expect_false(grepl("class='source-link'", fake_out$html, fixed = TRUE))
  expect_false(grepl("<b>x</b>", fake_out$html, fixed = TRUE))
})
