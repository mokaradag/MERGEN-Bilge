# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-session-persistence-behavior.R
# Açıklama: Bilge Yolaç kalıcı oturum runtime köprüsünün
#           (R/helpers_claude_code_session_persistence.R) davranış testleri.
#           DB katmanı yerel stub'larla taklit edilir; gerçek DB, LLM,
#           tarayıcı veya ağ GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Kalıcılaştırma kullanılabilirlik önbelleği (rv üzerinde).
#   - Oturum başlatma: ilk çağrıda kayıt açar, sonraki çağrıda tekrar açmaz.
#   - Persist hatası çalıştırmayı ASLA kırmaz (hata fırlatılmaz).
#   - Detach kalıcı geçmişi silmez; yalnızca rv bağlarını temizler.
#   - Araç kullanımı / indirme metadata küçültme ve kesme işaretleri.
#   - Hidrasyon planı: resume güvenlik kontrolü, workdir geri yükleme,
#     mesaj yeniden oynatma, XSS kaçışlama ve başarısız çalıştırma balonu.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("cc_db_generate_session_title", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_claude_code_session_queries.R"),
           encoding = "UTF-8", local = globalenv())
  }

  if (!exists("cc_persist_session_begin", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_claude_code_session_persistence.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# rv taklidi: reactiveValues yerine $ erişimli sade environment yeterlidir.
.ccsp_new_rv <- function() new.env(parent = emptyenv())

# Testler globalenv'e geçici DB stub'ları kurar ve bitince temizler.
.ccsp_with_db_stubs <- function(stubs, code) {
  isimler <- names(stubs)
  eski <- list()

  for (ad in isimler) {
    eski[[ad]] <- if (exists(ad, envir = globalenv(), inherits = FALSE)) {
      get(ad, envir = globalenv(), inherits = FALSE)
    } else {
      NULL
    }
    assign(ad, stubs[[ad]], envir = globalenv())
  }

  on.exit({
    for (ad in isimler) {
      if (is.null(eski[[ad]])) {
        if (exists(ad, envir = globalenv(), inherits = FALSE)) {
          rm(list = ad, envir = globalenv())
        }
      } else {
        assign(ad, eski[[ad]], envir = globalenv())
      }
    }
  }, add = TRUE)

  force(code)
}

# ------------------------------------------------------------------------------
test_that("cc_persist_enabled sonucu rv üzerinde önbelleğe alır", {
  rv <- .ccsp_new_rv()

  cagri_sayisi <- 0L
  .ccsp_with_db_stubs(
    list(cc_db_claude_tables_available = function(...) {
      cagri_sayisi <<- cagri_sayisi + 1L
      TRUE
    }),
    {
      expect_true(cc_persist_enabled(rv))
      expect_true(cc_persist_enabled(rv))
      expect_identical(cagri_sayisi, 1L)
      expect_true(isTRUE(rv$claude_session_persistence_available))
    }
  )

  # Tablolar yoksa FALSE önbelleğe alınır ve uyarı üretimi çalıştırmayı kırmaz.
  rv2 <- .ccsp_new_rv()
  .ccsp_with_db_stubs(
    list(cc_db_claude_tables_available = function(...) FALSE),
    {
      expect_no_error(suppressWarnings(sonuc <- cc_persist_enabled(rv2)))
      expect_false(sonuc)
      expect_false(isTRUE(rv2$claude_session_persistence_available))
    }
  )
})

test_that("oturum başlatma ilk çağrıda kayıt açar, sonraki çağrıda açmaz", {
  rv <- .ccsp_new_rv()

  create_cagri <- 0L
  yakalanan <- NULL

  .ccsp_with_db_stubs(
    list(
      cc_db_claude_tables_available = function(...) TRUE,
      cc_db_create_session = function(...) {
        create_cagri <<- create_cagri + 1L
        yakalanan <<- list(...)
        42L
      }
    ),
    {
      id1 <- cc_persist_session_begin(
        rv = rv,
        user_id = 7L,
        prompt = "Türkçe başlık: proje dosyalarını incele",
        workdir = "C:/proje",
        source_workdir = "C:/proje",
        runtime_workdir = "C:/tmp/rt",
        model = "m1",
        runtime_model = "m1-rt",
        character_id = "emre"
      )

      expect_identical(id1, 42L)
      expect_identical(rv$claude_session_record_id, 42L)
      expect_true(grepl("Türkçe başlık", rv$claude_session_title, fixed = TRUE))
      expect_identical(create_cagri, 1L)
      expect_identical(yakalanan$user_id, 7L)
      expect_identical(yakalanan$character_id, "emre")

      # İkinci çağrı mevcut kaydı döndürür; yeni kayıt AÇMAZ.
      id2 <- cc_persist_session_begin(rv = rv, user_id = 7L, prompt = "ikinci")
      expect_identical(id2, 42L)
      expect_identical(create_cagri, 1L)
    }
  )
})

test_that("persist hatası çalıştırmayı kırmaz (begin ve run_result)", {
  rv <- .ccsp_new_rv()

  .ccsp_with_db_stubs(
    list(
      cc_db_claude_tables_available = function(...) TRUE,
      cc_db_create_session = function(...) stop("DB koptu"),
      cc_db_save_run = function(...) stop("DB koptu"),
      cc_db_update_session_resume_state = function(...) stop("DB koptu")
    ),
    {
      expect_no_error(suppressWarnings(
        sonuc <- cc_persist_session_begin(rv = rv, user_id = 7L, prompt = "p")
      ))
      expect_null(sonuc)
      expect_null(rv$claude_session_record_id)

      # Kayıt bağlıyken save_run patlasa bile hata fırlatılmaz.
      rv$claude_session_record_id <- 10L
      env <- list(prompt = "p", tum_satirlar = c("{}"),
                  calisma_dizini = "C:/rt", kaynak_calisma_dizini = "C:/src")

      expect_no_error(suppressWarnings(
        ok <- cc_persist_run_result(rv, env, status = "completed",
                                    final_output = "çıktı")
      ))
      expect_false(isTRUE(ok))
    }
  )
})

test_that("run_result başarılı/başarısız durumları DB katmanına doğru geçirir", {
  rv <- .ccsp_new_rv()
  rv$claude_session_record_id <- 5L
  rv$claude_session_persistence_available <- TRUE
  rv$current_runtime_model <- "model-rt"

  save_args <- NULL
  update_args <- NULL

  env <- list(
    prompt = "Türkçe komut: özet çıkar",
    tum_satirlar = c("{\"a\":1}", "{\"b\":2}"),
    calisma_dizini = "C:/tmp/rt",
    kaynak_calisma_dizini = "//paylasim/Türkçe_proje"
  )

  .ccsp_with_db_stubs(
    list(
      cc_db_save_run = function(...) {
        save_args <<- list(...)
        99L
      },
      cc_db_update_session_resume_state = function(...) {
        update_args <<- list(...)
        TRUE
      }
    ),
    {
      ok <- cc_persist_run_result(
        rv = rv,
        env = env,
        status = "failed",
        final_output = "hata mesajı",
        exit_code = 1L,
        duration = 3.2,
        tool_uses = list(list(name = "Bash", input = list(command = "ls"), result = "out")),
        downloads = list(list(display_name = "rapor.docx", download_path = "/x/rapor.docx",
                              url = "u", size = 10, size_label = "10 B")),
        cli_session_id = "cli-xyz"
      )

      expect_true(ok)
      expect_identical(save_args$session_record_id, 5L)
      expect_identical(save_args$status, "failed")
      expect_identical(save_args$exit_code, 1L)
      expect_true(grepl("özet çıkar", save_args$prompt, fixed = TRUE))
      expect_null(save_args$raw_stream_jsonl)
      expect_identical(save_args$tool_uses[[1]]$name, "Bash")
      expect_identical(save_args$tool_uses[[1]]$result, "out")
      expect_identical(save_args$generated_downloads[[1]]$display_name, "rapor.docx")

      expect_identical(update_args$cli_session_id, "cli-xyz")
      expect_identical(update_args$runtime_model, "model-rt")
      expect_identical(update_args$status, "failed")
      expect_true(grepl("Türkçe_proje", update_args$source_workdir, fixed = TRUE))
    }
  )

  # Kayıt bağlı değilse persist sessizce atlanır.
  rv_bos <- .ccsp_new_rv()
  rv_bos$claude_session_persistence_available <- TRUE
  expect_false(isTRUE(cc_persist_run_result(rv_bos, env, status = "completed")))
})

test_that("detach yalnızca rv bağlarını temizler; silme çağrısı YAPMAZ", {
  rv <- .ccsp_new_rv()
  rv$claude_session_record_id <- 5L
  rv$claude_session_title <- "t"
  rv$claude_session_loaded <- TRUE

  silme_cagrildi <- FALSE
  .ccsp_with_db_stubs(
    list(cc_db_soft_delete_session = function(...) {
      silme_cagrildi <<- TRUE
      TRUE
    }),
    {
      cc_persist_detach_session(rv)
      expect_null(rv$claude_session_record_id)
      expect_null(rv$claude_session_title)
      expect_false(isTRUE(rv$claude_session_loaded))
      expect_false(silme_cagrildi)
    }
  )
})

test_that("araç/indirme küçültme yalnızca güvenli metadata bırakır ve keser", {
  slim <- cc_persist_slim_tool_uses(
    list(list(
      name = "Write",
      id = "t1",
      input = list(
        file_path = "a.txt",
        content = strrep("x", 3000L),
        karmasik = list(a = 1)
      ),
      result = strrep("y", 5000L)
    )),
    max_input_chars = 100L,
    max_result_chars = 100L
  )

  expect_identical(slim[[1]]$name, "Write")
  expect_identical(slim[[1]]$input$file_path, "a.txt")
  expect_true(grepl("[[MERGEN-TRUNCATED]]", slim[[1]]$input$content, fixed = TRUE))
  expect_true(grepl("[[MERGEN-TRUNCATED]]", slim[[1]]$result, fixed = TRUE))

  gizli_slim <- cc_persist_slim_tool_uses(list(list(
    name = "Bash",
    input = list(command = "env", note = "API_KEY=sk-testSECRET123456789"),
    result = "TOKEN=ghp_secretSECRET123456789\nnormal çıktı"
  )))
  expect_false(grepl("sk-testSECRET", gizli_slim[[1]]$input$note, fixed = TRUE))
  expect_false(grepl("ghp_secretSECRET", gizli_slim[[1]]$result, fixed = TRUE))
  expect_true(grepl("[[MERGEN-REDACTED]]", gizli_slim[[1]]$input$note, fixed = TRUE))
  expect_true(grepl("[[MERGEN-REDACTED]]", gizli_slim[[1]]$result, fixed = TRUE))

  # Skaler olmayan girdiler kalıcılaştırılmaz.
  expect_null(slim[[1]]$input$karmasik)

  indirme <- cc_persist_slim_downloads(list(list(
    display_name = "Türkçe_rapor.docx",
    download_name = "Türkçe_rapor.docx",
    download_path = "/dl/x.docx",
    url = "bilge_yolac_downloads/u/s/x.docx",
    size = 2048,
    size_label = "2 KB",
    original_path = "/gizli/sunucu/yolu/x.docx",
    beklenmeyen_alan = "atlanmali"
  )))

  expect_identical(indirme[[1]]$display_name, "Türkçe_rapor.docx")
  expect_identical(indirme[[1]]$size, 2048)
  expect_null(indirme[[1]]$original_path)
  expect_null(indirme[[1]]$beklenmeyen_alan)

  expect_identical(cc_persist_slim_tool_uses(NULL), list())
  expect_identical(cc_persist_slim_downloads(list()), list())
})

# ------------------------------------------------------------------------------
# Hidrasyon planı
# ------------------------------------------------------------------------------

.ccsp_fake_record <- function(cli_id = "cli-1",
                              runtime_dir = "C:/tmp/rt",
                              source_dir = "C:/proje") {
  list(
    session = list(
      ClaudeSessionRecordID = 5L,
      UserID = 1L,
      ClaudeCliSessionID = cli_id,
      SessionTitle = "Türkçe oturum başlığı",
      Workdir = source_dir,
      SourceWorkdir = source_dir,
      RuntimeWorkdir = runtime_dir,
      ModelUsed = "m1",
      RuntimeModel = "m1-rt",
      CharacterID = "emre",
      Status = "completed"
    ),
    runs = data.frame(
      ClaudeRunID = c(1L, 2L),
      RunOrder = c(1L, 2L),
      Prompt = c("ilk komut <script>alert(1)</script>", "ikinci komut şı"),
      FinalOutput = c("ilk çıktı ğü", "hata: bir şeyler ters gitti"),
      Status = c("completed", "failed"),
      ExitCode = c(0L, 1L),
      DurationSeconds = c(2.5, NA_real_),
      ToolUsesJson = c('[{"name":"Write","input":{"file_path":"a.txt"},"result":"ok"}]', "[]"),
      GeneratedDownloadsJson = c('[{"display_name":"r.docx","download_path":"/dl/r.docx"}]', "[]"),
      CreatedAt = c("2026-07-01 10:00:00", "2026-07-01 10:05:00"),
      stringsAsFactors = FALSE
    )
  )
}

test_that("hidrasyon planı resume güvenliğini ve mesaj oynatmayı üretir", {
  kayit <- .ccsp_fake_record()

  arac_html_args <- NULL
  plan <- cc_session_hydration_plan(
    kayit,
    format_output_fn = function(x) paste0("<div class='fmt'>", htmltools::htmlEscape(x), "</div>"),
    tool_uses_html_fn = function(araclar) {
      arac_html_args <<- araclar
      "<div class='tools'>1 araç</div>"
    },
    downloads_html_fn = function(d) "<div class='dl'>kart</div>",
    dir_exists_fn = function(p) TRUE,
    file_exists_fn = function(p) TRUE
  )

  # Resume: CLI kimliği + var olan runtime dizini -> uygun
  expect_true(plan$resume$ok)
  expect_identical(plan$resume$cli_session_id, "cli-1")
  expect_identical(plan$resume$runtime_workdir, "C:/tmp/rt")
  expect_identical(plan$workdir_restore, "C:/proje")
  expect_identical(plan$warnings, character(0))
  expect_identical(plan$title, "Türkçe oturum başlığı")

  # Mesajlar: user + assistant + user + error = 4
  expect_length(plan$messages, 4L)
  expect_identical(plan$messages[[1]]$type, "user")
  # XSS sınırı: kullanıcı promptu kaçışlanır.
  expect_false(grepl("<script>", plan$messages[[1]]$content, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", plan$messages[[1]]$content, fixed = TRUE))

  expect_identical(plan$messages[[2]]$type, "assistant")
  expect_true(grepl("class='fmt'", plan$messages[[2]]$content, fixed = TRUE))
  expect_true(grepl("class='dl'", plan$messages[[2]]$content, fixed = TRUE))
  expect_identical(plan$messages[[2]]$toolContent, "<div class='tools'>1 araç</div>")
  expect_identical(arac_html_args[[1]]$name, "Write")

  xss_kayit <- .ccsp_fake_record()
  xss_kayit$runs$FinalOutput[1] <- "<img src=x onerror=alert(1)> **kalın**"
  xss_plan <- cc_session_hydration_plan(
    xss_kayit,
    format_output_fn = function(x) paste0("<div class='fmt'>", x, "</div>"),
    dir_exists_fn = function(p) TRUE,
    file_exists_fn = function(p) FALSE
  )
  expect_false(grepl("<img", xss_plan$messages[[2]]$content, fixed = TRUE))
  expect_true(grepl("&lt;img", xss_plan$messages[[2]]$content, fixed = TRUE))

  # Başarısız çalıştırma hata balonu olarak oynatılır.
  expect_identical(plan$messages[[4]]$type, "error")
  expect_true(grepl("ters gitti", plan$messages[[4]]$content, fixed = TRUE))

  # Konuşma bağlamı: başarısız çalıştırma asistan yanıtı EKLEMEZ.
  roller <- vapply(plan$conversation_context, function(x) x$role, character(1))
  expect_identical(roller, c("user", "assistant", "user"))
})

test_that("hidrasyon planı erişilemeyen dizinlerde güvenli düşer", {
  kayit <- .ccsp_fake_record()

  plan <- cc_session_hydration_plan(
    kayit,
    dir_exists_fn = function(p) FALSE,
    file_exists_fn = function(p) FALSE
  )

  # Runtime dizini yok -> resume güvenli değil; geçmiş yine de oynatılır.
  expect_false(plan$resume$ok)
  expect_null(plan$resume$cli_session_id)
  expect_identical(plan$resume$reason, "calisma_dizini_bulunamadi")
  expect_null(plan$workdir_restore)
  expect_true(length(plan$warnings) >= 1L)
  expect_length(plan$messages, 4L)

  # İndirme dosyası fiziksel olarak yoksa kart üretilmez.
  expect_false(grepl("class='dl'", plan$messages[[2]]$content, fixed = TRUE))

  # CLI kimliği hiç yoksa nedeni farklı raporlanır ve uyarı üretilmez.
  plan_cli_yok <- cc_session_hydration_plan(
    .ccsp_fake_record(cli_id = ""),
    dir_exists_fn = function(p) TRUE
  )
  expect_false(plan_cli_yok$resume$ok)
  expect_identical(plan_cli_yok$resume$reason, "cli_oturum_kimligi_yok")

  # Boş kayıt güvenli boş plan döndürür.
  bos <- cc_session_hydration_plan(NULL)
  expect_false(bos$resume$ok)
  expect_length(bos$messages, 0L)
})
