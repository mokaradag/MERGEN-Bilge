# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-runtime-behavior.R
# Açıklama: Kurumsal Langflow akış entegrasyonu saf yardımcılarının davranışını
#           doğrular: URL üretimi, araç ailesi tespiti, yanıt metni çıkarımı,
#           kararlı session_id, eksik yapılandırma ve HTTP hata mesajları.
#           Tüm testler çevrimdışı ve deterministiktir (gerçek ağ/HTTP yoktur).
# ==============================================================================

.find_langflow_test_repo_root <- function() {
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
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Langflow runtime test repo kökünü bulamadı.", call. = FALSE)
}

repo_root_langflow <- .find_langflow_test_repo_root()

# %||%, get_tool_mode_config ve UTF-8 ad normalizasyonu (normalize_text_utf8)
# bağımlılıkları izole koşumda yüklenmelidir.
source(file.path(repo_root_langflow, "R", "utils_common.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_langflow, "R", "utils_text_encoding.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_langflow, "R", "helpers_api_model_config.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_langflow, "R", "helpers_api_model_tool_runtime.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_langflow, "R", "helpers_langflow_runtime.R"),
       encoding = "UTF-8", local = globalenv())

# Langflow yapılandırılmış örnek config (çoklu süreç akışı; Langflow araçlarında
# yerel model_id YOKTUR).
.langflow_test_config <- function(base_url = "https://langflow.example.com",
                                  process_flows = list(
                                    list(key = "flow_1", id = "flow-process-123", name = "Süreç Akışı 1"),
                                    list(key = "flow_2", id = "flow-process-456", name = "Süreç Akışı 2")
                                  ),
                                  app_expert_flow = "flow-app-456") {
  list(
    local_models = c("Model" = "technical name 1"),
    langflow = list(
      base_url = base_url,
      api_key = "fake-langflow-key",
      timeout_seconds = 300,
      process_flows = process_flows,
      flow_ids = list(
        app_expert = app_expert_flow
      )
    ),
    tool_mode_config = list(
      process = list(
        family = "process",
        setting_flag = "enable_process_tools",
        quick_action_id = "project-process",
        runtime = "langflow"
      ),
      app_expert = list(
        family = "app_expert",
        setting_flag = "enable_app_expert_tools",
        quick_action_id = "app-expert",
        runtime = "langflow",
        langflow_flow_id = app_expert_flow
      ),
      coding = list(
        family = "coding",
        setting_flag = "enable_coding_tools",
        quick_action_id = "coding-support",
        model_id = "technical name 5"
      )
    )
  )
}

test_that("build_langflow_run_url sondaki '/' karakterini çift slash üretmeden temizler", {
  expect_equal(
    build_langflow_run_url("https://langflow.example.com", "flow-1"),
    "https://langflow.example.com/flow-1"
  )
  expect_equal(
    build_langflow_run_url("https://langflow.example.com///", "flow-1"),
    "https://langflow.example.com/flow-1"
  )
  expect_equal(
    build_langflow_run_url("  https://langflow.example.com/  ", "  flow-1  "),
    "https://langflow.example.com/flow-1"
  )
})

test_that("build_langflow_run_url eksik taban/akış kimliğinde boş string döner", {
  expect_equal(build_langflow_run_url("", "flow-1"), "")
  expect_equal(build_langflow_run_url("https://x", ""), "")
  expect_equal(build_langflow_run_url(NULL, NULL), "")
})

test_that("normalize_langflow_base_url boş/NA değerleri güvenle ele alır", {
  expect_equal(normalize_langflow_base_url(NULL), "")
  expect_equal(normalize_langflow_base_url(NA), "")
  expect_equal(normalize_langflow_base_url("https://x/"), "https://x")
})

test_that("is_langflow_tool_family yalnızca runtime=langflow ve akış kimliği varken TRUE döner", {
  config <- .langflow_test_config()

  expect_true(is_langflow_tool_family("process", config))
  expect_true(is_langflow_tool_family("app_expert", config))

  # coding Langflow değil
  expect_false(is_langflow_tool_family("coding", config))
  # tanımsız aile
  expect_false(is_langflow_tool_family("none", config))
  expect_false(is_langflow_tool_family("", config))
  expect_false(is_langflow_tool_family(NULL, config))
})

test_that("is_langflow_tool_family taban URL veya akış kimliği eksikse (require_config=TRUE) FALSE döner", {
  # Taban URL yok -> yapılandırma eksik -> require_config TRUE ile FALSE
  no_base <- .langflow_test_config(base_url = "")
  expect_false(is_langflow_tool_family("process", no_base))

  # Hiç süreç akışı yapılandırılmamış -> process çözülemez
  no_flow <- .langflow_test_config(process_flows = list())
  expect_false(is_langflow_tool_family("process", no_flow))
  # app_expert hâlâ yapılandırılmış olmalı
  expect_true(is_langflow_tool_family("app_expert", no_flow))
})

test_that("is_langflow_tool_family require_config=FALSE ile yalnızca runtime'a bakar (yönlendirme için)", {
  # Yapılandırma eksik olsa bile runtime==langflow ise TRUE -> istek Langflow
  # işleyicisine gider ve orada net hata verilir (normal LLM'ye düşülmez).
  no_base <- .langflow_test_config(base_url = "")
  expect_true(is_langflow_tool_family("process", no_base, require_config = FALSE))
  expect_true(is_langflow_tool_family("app_expert", no_base, require_config = FALSE))

  no_flow <- .langflow_test_config(process_flows = list())
  expect_true(is_langflow_tool_family("process", no_flow, require_config = FALSE))

  # Langflow olmayan araç yine FALSE
  expect_false(is_langflow_tool_family("coding", .langflow_test_config(), require_config = FALSE))
})

test_that("mergen_langflow_flow_id_for_family process için seçili/varsayılan akışı, app_expert için tekil kimliği çözer", {
  config <- .langflow_test_config(app_expert_flow = "af-2")

  # process: seçim yoksa varsayılan ilk akış
  expect_equal(mergen_langflow_flow_id_for_family("process", config), "flow-process-123")
  # process: key ile seçim
  expect_equal(mergen_langflow_flow_id_for_family("process", config, selected_flow = "flow_2"), "flow-process-456")
  # process: id ile seçim
  expect_equal(mergen_langflow_flow_id_for_family("process", config, selected_flow = "flow-process-456"), "flow-process-456")
  # process: bilinmeyen AÇIK seçim -> "" (sessizce 1. akışa yönlendirilmez;
  # işleyici net "seçili süreç akışı bulunamadı" hatası gösterir)
  expect_equal(mergen_langflow_flow_id_for_family("process", config, selected_flow = "yok"), "")

  # app_expert tekil akış kimliği
  expect_equal(mergen_langflow_flow_id_for_family("app_expert", config), "af-2")

  # Araç moduna özel kimlik yoksa merkezi flow_ids haritasına düşülür
  config$tool_mode_config$app_expert$langflow_flow_id <- NULL
  config$langflow$flow_ids$app_expert <- "central-af"
  expect_equal(mergen_langflow_flow_id_for_family("app_expert", config), "central-af")

  expect_equal(mergen_langflow_flow_id_for_family("none", config), "")
})

test_that("mergen_parse_langflow_process_flows liste formatını, geriye dönük tekil kimliği ve ad yedeklemesini işler", {
  # Liste formatı (";" ayraçlı), boşluk temizlenir, boşlar atlanır
  flows <- mergen_parse_langflow_process_flows(
    ids_raw = " id-1 ; id-2 ;; id-3 ",
    names_raw = "Akış A; Akış B"
  )
  expect_length(flows, 3L)
  expect_equal(flows[[1]]$id, "id-1")
  expect_equal(flows[[1]]$name, "Akış A")
  expect_equal(flows[[1]]$key, "flow_1")
  expect_equal(flows[[2]]$name, "Akış B")
  # Ad eksikse güvenli yedek ad
  expect_equal(flows[[3]]$name, "Akış 3")
  expect_equal(flows[[3]]$key, "flow_3")

  # "," ayracı da desteklenir
  comma_flows <- mergen_parse_langflow_process_flows(ids_raw = "a,b", names_raw = "Bir,İki")
  expect_length(comma_flows, 2L)
  expect_equal(comma_flows[[2]]$id, "b")
  expect_equal(comma_flows[[2]]$name, "İki")

  # Liste yoksa eski tekil kimliğe düşer (geçici uyumluluk)
  legacy <- mergen_parse_langflow_process_flows(ids_raw = "", legacy_id = "legacy-flow")
  expect_length(legacy, 1L)
  expect_equal(legacy[[1]]$id, "legacy-flow")
  expect_equal(legacy[[1]]$name, "Akış 1")

  # Hiç kimlik yoksa boş liste
  expect_length(mergen_parse_langflow_process_flows(), 0L)
})

test_that("mergen_parse_langflow_process_flows boş ad konumlarını korur ve slot bazında yedek ada düşer", {
  # Operatör ilk adı boş bırakıp yedeği kullanmak isterse, boş konum atlanmamalı;
  # aksi halde "Flow 2" yanlışlıkla flow_1'e kayardı.
  flows <- mergen_parse_langflow_process_flows(
    ids_raw = "id1;id2",
    names_raw = ";Flow 2"
  )
  expect_length(flows, 2L)
  expect_equal(flows[[1]]$id, "id1")
  expect_equal(flows[[1]]$name, "Akış 1")   # boş konum -> yedek ad (KAYMAZ)
  expect_equal(flows[[2]]$id, "id2")
  expect_equal(flows[[2]]$name, "Flow 2")

  # Ortadaki boş ad konumu da korunur
  mid <- mergen_parse_langflow_process_flows(
    ids_raw = "a;b;c",
    names_raw = "Bir;;Üç"
  )
  expect_equal(mid[[1]]$name, "Bir")
  expect_equal(mid[[2]]$name, "Akış 2")     # ortadaki boş -> yedek
  expect_equal(mid[[3]]$name, "Üç")
})

test_that("mergen_parse_langflow_process_flows kimlik değerindeki satır içi '#' yorumunu ayıklar (yorumda ';' olsa bile)", {
  # readRenviron() satır içi yorumu değerin parçası olarak bırakır. Yorum ';'
  # içerdiğinde eski ayrıştırıcı yorumu üçüncü bir kimlik sanıp hem 2. akışın
  # URL'sini kirletiyor hem de sahte "Akış 3" üretiyordu.
  flows <- mergen_parse_langflow_process_flows(
    ids_raw = "3727f5a0-3fe2-42e4-976d-1eb671af3198;e0aac97f-1041-4463-a90d-7333fb811b71 #birinci-etiket;ikinci-etiket",
    names_raw = "REHİS Süreç Yönetimi;ASELSAN Süreç Yönetimi"
  )

  # TAM olarak yapılandırılmış iki akış; sahte "Akış 3" yok.
  expect_length(flows, 2L)
  expect_false(any(vapply(flows, function(fl) identical(fl$name, "Akış 3"), logical(1))))

  # 2. akışın kimliği yorum artıklarından arınmıştır ve URL güvenlidir.
  expect_equal(flows[[2]]$id, "e0aac97f-1041-4463-a90d-7333fb811b71")
  expect_equal(
    build_langflow_run_url("https://langflow.example.com/api/v1/run", flows[[2]]$id),
    "https://langflow.example.com/api/v1/run/e0aac97f-1041-4463-a90d-7333fb811b71"
  )

  # 2. akış seçimi (key ve id ile) sıradan bağımsız 2. akışı çağırır.
  cfg <- list(langflow = list(base_url = "https://x", process_flows = flows))
  expect_equal(mergen_langflow_process_flow_id(cfg, "flow_2"), "e0aac97f-1041-4463-a90d-7333fb811b71")
  expect_equal(
    mergen_langflow_process_flow_id(cfg, "e0aac97f-1041-4463-a90d-7333fb811b71"),
    "e0aac97f-1041-4463-a90d-7333fb811b71"
  )

  # Eski tekil kimlik değişkeninde de yorum ayıklanır.
  legacy <- mergen_parse_langflow_process_flows(ids_raw = "", legacy_id = "legacy-1 #eski not")
  expect_length(legacy, 1L)
  expect_equal(legacy[[1]]$id, "legacy-1")
})

test_that("mergen_parse_langflow_process_flows yorum ayıklandıktan sonra kalan bozuk belirteci net biçimde reddeder", {
  # Yorum ayıklama sonrası hâlâ boşluk/URL-dışı karakter taşıyan belirteç bozuk
  # yapılandırmadır. Tek belirteci atmak sonraki akışları kaydırıp seçimi yanlış
  # akışa yönlendirebileceğinden TÜM liste reddedilir (işleyicide net hata).
  bozuk <- mergen_parse_langflow_process_flows(
    ids_raw = "gecerli-akis-1;bozuk akis kimligi",
    names_raw = "Akış A;Akış B"
  )
  expect_length(bozuk, 0L)

  # Reddedilen yapılandırmada seçim çözümlemesi de "" verir (yapılandırma eksik).
  cfg <- list(langflow = list(
    base_url = "https://x",
    process_flow_ids_raw = "gecerli-akis-1;bozuk akis kimligi",
    process_flow_names_raw = "Akış A;Akış B"
  ))
  expect_equal(mergen_langflow_process_flow_id(cfg, "flow_2"), "")
})

test_that("Türkçe akış adları ortam değeri yerel/1254 işaretli ham UTF-8 baytları taşısa bile mojibake olmadan çözülür", {
  # Windows VM senaryosu: .Renviron UTF-8 kaydedilir, Sys.getenv() değeri yerel
  # (latin1/1254) işaretli ham UTF-8 baytları olarak döner. Deterministik
  # fixture: doğru UTF-8 baytları latin1 olarak İŞARETLENİR (bayt dizisi aynı,
  # bildirim yanlış) — enc2utf8() bu durumda çift kodlamalı mojibake üretir.
  dogru_ad <- "REHİS Süreç Yönetimi"  # REHİS Süreç Yönetimi
  ham_bayt <- rawToChar(charToRaw(enc2utf8(dogru_ad)))
  Encoding(ham_bayt) <- "latin1"

  flows <- mergen_parse_langflow_process_flows(
    ids_raw = "id-1;id-2",
    names_raw = paste0(ham_bayt, ";ASELSAN Akışı")
  )

  expect_length(flows, 2L)
  expect_identical(Encoding(flows[[1]]$name), "UTF-8")
  expect_identical(flows[[1]]$name, dogru_ad)
  # Çift kodlama artıkları (Ä, Ã¼, Ã§ ...) görünen adda bulunmaz.
  expect_false(grepl("Ã|Ä", flows[[1]]$name))

  # Değer daha üst katmanda zaten çift kodlanmış geldiyse (geçerli UTF-8 olarak
  # "REHÄ°S SÃ¼reÃ§ ..."), mojibake onarımı orijinal Türkçe adı geri kazanır.
  cift_kodlanmis <- enc2utf8(ham_bayt)
  expect_true(grepl("Ã|Ä", cift_kodlanmis))  # fixture gerçekten mojibake
  flows_cift <- mergen_parse_langflow_process_flows(ids_raw = "id-1", names_raw = cift_kodlanmis)
  expect_identical(flows_cift[[1]]$name, dogru_ad)
})

test_that("süreç akışı açılır menü seçenekleri tam olarak yapılandırılan akışlardan üretilir (UTF-8 etiketlerle)", {
  testthat::skip_if_not_installed("htmltools")

  # ui.R'deki seçenek üretimiyle aynı eşleme: tags$option(value = key, name).
  flows <- mergen_parse_langflow_process_flows(
    ids_raw = "3727f5a0-3fe2-42e4-976d-1eb671af3198;e0aac97f-1041-4463-a90d-7333fb811b71 #not;etiket",
    names_raw = "REHİS Süreç Yönetimi;ASELSAN Süreç Yönetimi"
  )
  options_html <- vapply(
    flows,
    function(fl) as.character(htmltools::tags$option(value = fl$key, fl$name)),
    character(1)
  )

  expect_length(options_html, 2L)
  expect_match(options_html[1], "value=\"flow_1\"")
  expect_match(options_html[1], "REHİS Süreç Yönetimi", fixed = TRUE)
  expect_match(options_html[2], "value=\"flow_2\"")
  expect_match(options_html[2], "ASELSAN Süreç Yönetimi", fixed = TRUE)
  expect_false(any(grepl("Akış 3", options_html, fixed = TRUE)))
  # Çift kodlama göstergesi yok (Ã/Ä dizileri).
  expect_false(any(grepl("Ã|Ä", options_html)))
})

test_that("mergen_langflow_process_flows ham env alanlarından da çözümlenir", {
  cfg_raw <- list(
    langflow = list(
      base_url = "https://x",
      process_flow_ids_raw = "raw-1;raw-2",
      process_flow_names_raw = "Ham 1;Ham 2"
    )
  )
  flows <- mergen_langflow_process_flows(cfg_raw)
  expect_length(flows, 2L)
  expect_equal(flows[[1]]$id, "raw-1")
  expect_equal(flows[[2]]$name, "Ham 2")

  # Önceden ayrıştırılmış process_flows varsa doğrudan döner
  parsed <- mergen_langflow_process_flows(.langflow_test_config())
  expect_length(parsed, 2L)
  expect_equal(parsed[[1]]$id, "flow-process-123")
})

test_that("mergen_langflow_process_flow_id seçim/varsayılan/boş durumlarını çözer", {
  config <- .langflow_test_config()
  expect_equal(mergen_langflow_process_flow_id(config), "flow-process-123")
  expect_equal(mergen_langflow_process_flow_id(config, "flow_2"), "flow-process-456")
  expect_equal(mergen_langflow_process_flow_id(config, "flow-process-456"), "flow-process-456")
  # Açık ama eşleşmeyen seçim sessizce 1. akışa yönlenmez; "" döner.
  expect_equal(mergen_langflow_process_flow_id(config, "bulunamaz"), "")

  # Akış yoksa "" döner (yapılandırma eksik)
  empty <- .langflow_test_config(process_flows = list())
  expect_equal(mergen_langflow_process_flow_id(empty), "")
})

test_that("mergen_langflow_process_flow_label görünen adı çözer (loglama için)", {
  config <- .langflow_test_config()
  expect_equal(mergen_langflow_process_flow_label(config), "Süreç Akışı 1")
  expect_equal(mergen_langflow_process_flow_label(config, "flow_2"), "Süreç Akışı 2")
  # Kimlik çözümlemesiyle tutarlı: eşleşmeyen açık seçim "" döndürür.
  expect_equal(mergen_langflow_process_flow_label(config, "yok"), "")
  expect_equal(mergen_langflow_process_flow_label(.langflow_test_config(process_flows = list())), "")
})

test_that("mergen_langflow_setting_flags yalnızca runtime=langflow araçlarının bayraklarını döndürür", {
  config <- .langflow_test_config()
  flags <- mergen_langflow_setting_flags(config)
  expect_true("enable_process_tools" %in% flags)
  expect_true("enable_app_expert_tools" %in% flags)
  expect_false("enable_coding_tools" %in% flags)

  expect_identical(mergen_langflow_setting_flags(list()), character(0))
})

test_that("mergen_build_langflow_session_id aynı sohbet için kararlı kimlik üretir", {
  sid1 <- mergen_build_langflow_session_id(42, 1001)
  sid2 <- mergen_build_langflow_session_id(42, 1001)
  expect_identical(sid1, sid2)
  expect_identical(sid1, "mergen_42_1001")

  # Farklı sohbet -> farklı kimlik
  expect_false(identical(
    mergen_build_langflow_session_id(42, 1001),
    mergen_build_langflow_session_id(42, 1002)
  ))

  # Eksik değerler güvenli yer tutuculara düşer
  expect_identical(mergen_build_langflow_session_id(NULL, NULL), "mergen_0_new")

  # flow_id verilmediğinde eski üç parçalı biçim korunur (geriye dönük uyumluluk)
  expect_identical(mergen_build_langflow_session_id(42, 1001, flow_id = NULL), "mergen_42_1001")
  expect_identical(mergen_build_langflow_session_id(42, 1001, flow_id = ""), "mergen_42_1001")
})

test_that("mergen_build_langflow_session_id oturumu seçilen akışa göre daraltır", {
  # Aynı kullanıcı + aynı sohbet + AYNI akış -> kararlı kimlik
  expect_identical(
    mergen_build_langflow_session_id(42, 1001, flow_id = "flow-abc"),
    mergen_build_langflow_session_id(42, 1001, flow_id = "flow-abc")
  )

  # Aynı sohbet, FARKLI akış -> farklı kimlik (bellek izolasyonu)
  expect_false(identical(
    mergen_build_langflow_session_id(42, 1001, flow_id = "flow-abc"),
    mergen_build_langflow_session_id(42, 1001, flow_id = "flow-xyz")
  ))

  # Akış kimliği kimliğe eklenir
  expect_identical(
    mergen_build_langflow_session_id(42, 1001, flow_id = "flow-abc"),
    "mergen_42_1001_flow-abc"
  )
})

test_that("extract_langflow_chat_text gerçekçi Chat Output yanıt şekillerinden metni çıkarır", {
  # results$message$text yolu
  shape_results <- list(
    session_id = "mergen_1_2",
    outputs = list(list(
      inputs = list(input_value = "soru"),
      outputs = list(list(
        results = list(message = list(text = "Yanıt metni A"))
      ))
    ))
  )
  expect_equal(extract_langflow_chat_text(shape_results), "Yanıt metni A")

  # artifacts$message yolu
  shape_artifacts <- list(
    outputs = list(list(
      outputs = list(list(
        artifacts = list(message = "Yanıt metni B")
      ))
    ))
  )
  expect_equal(extract_langflow_chat_text(shape_artifacts), "Yanıt metni B")

  # outputs$message$message yolu
  shape_msg_msg <- list(
    outputs = list(list(
      outputs = list(list(
        outputs = list(message = list(message = "Yanıt metni C"))
      ))
    ))
  )
  expect_equal(extract_langflow_chat_text(shape_msg_msg), "Yanıt metni C")

  # messages[[1]]$message yolu
  shape_messages <- list(
    outputs = list(list(
      outputs = list(list(
        messages = list(list(message = "Yanıt metni D"))
      ))
    ))
  )
  expect_equal(extract_langflow_chat_text(shape_messages), "Yanıt metni D")

  # Üst düzey message/text
  expect_equal(extract_langflow_chat_text(list(message = "Yanıt metni E")), "Yanıt metni E")
  expect_equal(extract_langflow_chat_text(list(text = "Yanıt metni F")), "Yanıt metni F")

  # Düz metin
  expect_equal(extract_langflow_chat_text("Düz yanıt"), "Düz yanıt")
})

test_that("extract_langflow_chat_text bilinmeyen yapıda outputs altında güvenli özyinelemeli arama yapar", {
  shape_nested <- list(
    outputs = list(list(
      component_outputs = list(
        chat = list(message = list(text = "Derin yanıt"))
      )
    ))
  )
  expect_equal(extract_langflow_chat_text(shape_nested), "Derin yanıt")

  # Metin bulunamazsa boş string
  expect_equal(extract_langflow_chat_text(list(outputs = list(list(foo = list(bar = 1))))), "")
  expect_equal(extract_langflow_chat_text(NULL), "")
  expect_equal(extract_langflow_chat_text(list()), "")
})

test_that("extract_langflow_chat_text kullanıcı girdisini (inputs) yanıt olarak döndürmez", {
  # inputs altındaki input_value, outputs altındaki gerçek yanıttan önce gelmemeli
  shape <- list(
    outputs = list(list(
      inputs = list(input_value = "Bu kullanıcının sorusudur"),
      outputs = list(list(
        results = list(message = list(text = "Bu gerçek cevaptır"))
      ))
    ))
  )
  expect_equal(extract_langflow_chat_text(shape), "Bu gerçek cevaptır")
})

test_that("call_langflow_chat yapılandırma eksikse HTTP yapmadan net hata döner", {
  res <- call_langflow_chat(
    input_value = "merhaba",
    base_url = "",
    flow_id = "",
    api_key = "k",
    session_id = "mergen_1_2"
  )
  expect_false(res$success)
  expect_true(nzchar(res$error))
  expect_true(is.na(res$status))
  expect_equal(res$text, "")
})

test_that("langflow_http_error_message durum koduna göre Türkçe mesaj üretir", {
  expect_match(langflow_http_error_message(401), "kimlik doğrulama", ignore.case = TRUE)
  expect_match(langflow_http_error_message(403), "kimlik doğrulama", ignore.case = TRUE)
  expect_match(langflow_http_error_message(404), "bulunamadı", ignore.case = TRUE)
  expect_match(langflow_http_error_message(500), "HTTP 500", ignore.case = TRUE)

  # Önizleme detayı eklenebilir ve kısaltılır
  msg <- langflow_http_error_message(500, paste(rep("x", 500), collapse = ""))
  expect_match(msg, "Detay:", ignore.case = TRUE)
  expect_true(nchar(msg) < 400)
})

test_that("mergen_langflow_config eksik/bozuk config'te boş liste döner", {
  expect_identical(mergen_langflow_config(list()), list())
  expect_identical(mergen_langflow_config(NULL), list())
  expect_identical(mergen_langflow_config(42), list())
  cfg <- .langflow_test_config()
  expect_equal(mergen_langflow_config(cfg)$base_url, "https://langflow.example.com")
})