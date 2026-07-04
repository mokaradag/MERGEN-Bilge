# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-sessions-db-behavior.R
# Açıklama: Bilge Yolaç kalıcı oturum DB katmanının (helpers_db_claude_code_
#           sessions.R + _session_queries.R) davranış testleri. GERÇEK bir
#           DBI arka ucu (RSQLite, geçici dosya) üzerinde çalışır; gerçek
#           SQL Server/ODBC GEREKMEZ ve ağ/gizli değer kullanılmaz.
#
# Kapsanan sözleşmeler:
#   - Tablo erişilebilirlik tespiti (var/yok) ve önbellek sıfırlama.
#   - Oturum oluşturma + Türkçe başlık/çalışma dizini gidiş-dönüşü.
#   - Çalıştırma kaydı: RunOrder artışı, Türkçe prompt/çıktı gidiş-dönüşü.
#   - Devam durumu güncelleme (CLI oturum kimliği + durum + LastRunAt).
#   - Kullanıcı izolasyonu: A kullanıcısı B'nin oturumlarını listeleyemez,
#     yükleyemez ve arşivleyemez.
#   - Yumuşak silme: fiziksel silme yapılmaz; arşiv görünümünde erişilir.
#   - Tablolar yokken tüm fonksiyonlar güvenli boş/NULL/FALSE döner.
#   - Başlık üretimi ve ham stream kesme saf yardımcıları.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }

  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_unicode_escape.R"),
           encoding = "UTF-8", local = globalenv())
  }

  if (!exists("cc_db_generate_session_title", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_claude_code_session_queries.R"),
           encoding = "UTF-8", local = globalenv())
  }

  if (!exists("cc_db_create_session", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_claude_code_sessions.R"),
           encoding = "UTF-8", local = globalenv())
  }

  # Arşiv geri yükleme + KALICI silme yaşam döngüsü ayrı dosyada; orkestrasyon
  # dosyasından sonra yüklenir (paylaşılan iç yardımcılara bağımlı).
  if (!exists("cc_db_hard_delete_session", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_claude_code_session_lifecycle.R"),
           encoding = "UTF-8", local = globalenv())
  }

  # KALICI silme üretilen dosyaları indirme kökü altında kaldırır; kök-içi
  # kontrol ve kök çözümleyici yardımcıları bu testler için yüklenir.
  if (!exists("cc_policy_path_inside_roots", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_claude_code_path_policy.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("get_claude_code_download_root", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_claude_code_downloads.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# SQLite lehçesinde test şeması kurar (üretim T-SQL DDL'i DEĞİL; bkz.
# docs/sql/2026-07-bilge-yolac-sessions.sql).
.ccs_test_create_schema <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE MB_ClaudeCode_Sessions (
      ClaudeSessionRecordID INTEGER PRIMARY KEY AUTOINCREMENT,
      UserID INTEGER NOT NULL,
      ClaudeCliSessionID TEXT,
      SessionTitle TEXT,
      Workdir TEXT,
      SourceWorkdir TEXT,
      RuntimeWorkdir TEXT,
      ModelUsed TEXT,
      RuntimeModel TEXT,
      CharacterID TEXT,
      Status TEXT,
      CreatedAt TEXT NOT NULL DEFAULT (datetime('now')),
      LastRunAt TEXT,
      IsDeleted INTEGER NOT NULL DEFAULT 0,
      SessionMetaJson TEXT
    )")

  DBI::dbExecute(conn, "
    CREATE TABLE MB_ClaudeCode_Runs (
      ClaudeRunID INTEGER PRIMARY KEY AUTOINCREMENT,
      ClaudeSessionRecordID INTEGER NOT NULL,
      RunOrder INTEGER NOT NULL,
      Prompt TEXT NOT NULL,
      FinalOutput TEXT,
      Status TEXT NOT NULL,
      ExitCode INTEGER,
      DurationSeconds REAL,
      ToolUsesJson TEXT,
      GeneratedDownloadsJson TEXT,
      RawStreamJsonl TEXT,
      CreatedAt TEXT NOT NULL DEFAULT (datetime('now'))
    )")

  invisible(TRUE)
}

# Şemalı geçici SQLite bağlantısıyla test bloğu çalıştırır.
.ccs_with_test_db <- function(code, create_schema = TRUE) {
  dbfile <- tempfile(fileext = ".sqlite")
  conn <- DBI::dbConnect(RSQLite::SQLite(), dbname = dbfile)

  on.exit({
    suppressWarnings(try(DBI::dbDisconnect(conn), silent = TRUE))
    suppressWarnings(unlink(dbfile))
    cc_db_sessions_reset_availability_cache()
  }, add = TRUE)

  if (isTRUE(create_schema)) {
    .ccs_test_create_schema(conn)
  }

  cc_db_sessions_reset_availability_cache()
  code(conn)
}

turkce_prompt <- paste(
  "Türkçe test: ç ğ ı İ ö ş ü",
  "- proje dosyalarını özetle"
)

# ------------------------------------------------------------------------------
test_that("tablo erişilebilirlik tespiti var/yok durumlarını doğru raporlar", {
  .ccs_with_test_db(function(conn) {
    expect_true(cc_db_claude_tables_available(conn = conn, force_refresh = TRUE))
  })

  .ccs_with_test_db(function(conn) {
    expect_false(cc_db_claude_tables_available(conn = conn, force_refresh = TRUE))
  }, create_schema = FALSE)
})

test_that("oturum başlığı üretimi Türkçe metni ve sınırları doğru işler", {
  baslik <- cc_db_generate_session_title(paste0("  ", turkce_prompt, "\nikinci satir  "))
  expect_false(grepl("\n", baslik, fixed = TRUE))
  expect_true(grepl("Türkçe test", baslik, fixed = TRUE))

  uzun <- cc_db_generate_session_title(strrep("abc ", 60), max_chars = 40L)
  expect_lte(nchar(uzun), 40L)
  expect_true(endsWith(uzun, "..."))

  bos <- cc_db_generate_session_title("", fallback_time = as.POSIXct("2026-07-01 10:00:00", tz = "UTC"))
  expect_true(grepl("Bilge Yolaç Oturumu", bos, fixed = TRUE))
})

test_that("ham stream metni boyut sınırında açık işaretle kesilir", {
  kucuk <- cc_db_truncate_raw_stream("abc", max_chars = 5000L)
  expect_identical(kucuk$text, "abc")
  expect_false(kucuk$truncated)

  buyuk <- cc_db_truncate_raw_stream(strrep("x", 5000L), max_chars = 2000L)
  expect_true(buyuk$truncated)
  expect_lte(nchar(buyuk$text), 2000L)
  expect_true(grepl("[[MERGEN-RAW-STREAM-TRUNCATED]]", buyuk$text, fixed = TRUE))

  expect_null(cc_db_truncate_raw_stream(NULL)$text)
  expect_null(cc_db_truncate_raw_stream(character(0))$text)
})

test_that("oturum oluşturma Türkçe başlık/dizin değerlerini korur", {
  .ccs_with_test_db(function(conn) {
    kayit_id <- cc_db_create_session(
      user_id = 7L,
      title = turkce_prompt,
      workdir = "C:/Projeler/Türkçe_çalışma",
      source_workdir = "//paylasim/Türkçe_çalışma",
      runtime_workdir = "C:/temp/runtime_1",
      model = "test-model-a",
      runtime_model = "test-model-a-runtime",
      character_id = "emre",
      metadata = list(created_from = "test"),
      conn = conn
    )

    expect_identical(kayit_id, 1L)

    satir <- DBI::dbGetQuery(
      conn,
      "SELECT * FROM MB_ClaudeCode_Sessions WHERE ClaudeSessionRecordID = 1"
    )
    expect_identical(nrow(satir), 1L)
    expect_identical(enc2utf8(satir$SessionTitle[1]), enc2utf8(turkce_prompt))
    expect_true(grepl("çalışma", enc2utf8(satir$Workdir[1]), fixed = TRUE))
    expect_identical(satir$Status[1], "active")
    expect_identical(as.integer(satir$IsDeleted[1]), 0L)

    # Geçersiz kullanıcı kimliği oturum oluşturmaz.
    expect_null(cc_db_create_session(user_id = 0L, title = "x", conn = conn))
    expect_null(cc_db_create_session(user_id = NA, title = "x", conn = conn))
  })
})

test_that("çalıştırma kaydı RunOrder artışı ve Türkçe gidiş-dönüşü korur", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 7L, title = "t", conn = conn)

    run1 <- cc_db_save_run(
      session_record_id = sid,
      prompt = turkce_prompt,
      final_output = "Sonuç: başarılı özet",
      status = "completed",
      exit_code = 0L,
      duration_seconds = 12.345,
      tool_uses = list(list(name = "Write", input = list(file_path = "a.txt"), result = "ok")),
      generated_downloads = list(list(display_name = "rapor.docx", size = 1024)),
      raw_stream_jsonl = "{\"type\":\"result\"}",
      conn = conn
    )
    run2 <- cc_db_save_run(
      session_record_id = sid,
      prompt = "ikinci komut",
      final_output = "",
      status = "failed",
      exit_code = 1L,
      conn = conn
    )

    expect_identical(run1, 1L)
    expect_identical(run2, 2L)

    runs <- DBI::dbGetQuery(
      conn,
      "SELECT * FROM MB_ClaudeCode_Runs ORDER BY RunOrder"
    )
    expect_identical(nrow(runs), 2L)
    expect_identical(as.integer(runs$RunOrder), c(1L, 2L))
    expect_identical(enc2utf8(runs$Prompt[1]), enc2utf8(turkce_prompt))
    expect_true(grepl("başarılı", enc2utf8(runs$FinalOutput[1]), fixed = TRUE))
    expect_identical(runs$Status[2], "failed")
    expect_identical(round(runs$DurationSeconds[1], 2), 12.35)
    expect_true(grepl("Write", runs$ToolUsesJson[1], fixed = TRUE))
    expect_true(grepl("rapor.docx", runs$GeneratedDownloadsJson[1], fixed = TRUE))

    # Boş prompt ve geçersiz oturum kimliği kayıt üretmez.
    expect_null(cc_db_save_run(sid, prompt = "", conn = conn))
    expect_null(cc_db_save_run(0L, prompt = "x", conn = conn))
  })
})

test_that("devam durumu güncellemesi yalnızca verilen alanları yazar", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 7L, title = "t", conn = conn)

    ok <- cc_db_update_session_resume_state(
      session_record_id = sid,
      cli_session_id = "cli-abc-123",
      runtime_workdir = "C:/temp/runtime_2",
      status = "completed",
      conn = conn
    )
    expect_true(ok)

    satir <- DBI::dbGetQuery(
      conn,
      "SELECT ClaudeCliSessionID, RuntimeWorkdir, Status, LastRunAt, SessionTitle
       FROM MB_ClaudeCode_Sessions WHERE ClaudeSessionRecordID = ?",
      params = list(sid)
    )
    expect_identical(satir$ClaudeCliSessionID[1], "cli-abc-123")
    expect_identical(satir$Status[1], "completed")
    expect_false(is.na(satir$LastRunAt[1]))
    # Verilmeyen alanlar (SessionTitle) değişmedi.
    expect_identical(satir$SessionTitle[1], "t")

    # Hiç alan verilmezse (touch_last_run = FALSE) FALSE döner.
    expect_false(cc_db_update_session_resume_state(sid, touch_last_run = FALSE, conn = conn))
  })
})

test_that("oturum listesi kullanıcı-izole çalışır ve filtreleri uygular", {
  .ccs_with_test_db(function(conn) {
    a1 <- cc_db_create_session(user_id = 1L, title = "A projesi özeti",
                               workdir = "C:/a", model = "model-x", conn = conn)
    a2 <- cc_db_create_session(user_id = 1L, title = "başka analiz",
                               workdir = "C:/b", model = "model-y", conn = conn)
    b1 <- cc_db_create_session(user_id = 2L, title = "B kullanıcı oturumu",
                               workdir = "C:/gizli", conn = conn)

    cc_db_save_run(a1, prompt = "p1", status = "completed", conn = conn)
    cc_db_update_session_resume_state(a1, cli_session_id = "cli-1", conn = conn)

    liste_a <- cc_db_list_sessions(user_id = 1L, conn = conn)
    expect_identical(nrow(liste_a), 2L)
    expect_true(all(as.integer(liste_a$UserID) == 1L))
    expect_false(any(grepl("gizli", c(liste_a$Workdir, liste_a$SessionTitle), fixed = TRUE)))

    # RunCount ve LastPrompt zenginleştirmesi
    a1_satir <- liste_a[as.integer(liste_a$ClaudeSessionRecordID) == a1, , drop = FALSE]
    expect_identical(as.integer(a1_satir$RunCount), 1L)
    expect_identical(a1_satir$LastPrompt[1], "p1")

    # Metin araması (Türkçe)
    arama <- cc_db_list_sessions(user_id = 1L, query = "özeti", conn = conn)
    expect_identical(nrow(arama), 1L)
    expect_identical(as.integer(arama$ClaudeSessionRecordID), a1)

    # resumable filtresi: yalnızca CLI oturum kimliği olan
    devam <- cc_db_list_sessions(user_id = 1L, status = "resumable", conn = conn)
    expect_identical(as.integer(devam$ClaudeSessionRecordID), a1)

    # Model filtresi
    model_y <- cc_db_list_sessions(user_id = 1L, model = "model-y", conn = conn)
    expect_identical(as.integer(model_y$ClaudeSessionRecordID), a2)

    # limit
    tek <- cc_db_list_sessions(user_id = 1L, limit = 1L, conn = conn)
    expect_identical(nrow(tek), 1L)

    # Geçersiz kullanıcı kimliği boş döner.
    expect_identical(nrow(cc_db_list_sessions(user_id = 0L, conn = conn)), 0L)
  })
})

test_that("oturum yükleme kullanıcı-izole çalışır ve run sırası korunur", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 1L, title = "yükleme testi", conn = conn)
    cc_db_save_run(sid, prompt = "ilk", final_output = "bir", status = "completed", conn = conn)
    cc_db_save_run(sid, prompt = "ikinci", final_output = "iki", status = "failed", conn = conn)

    kayit <- cc_db_load_session(user_id = 1L, session_record_id = sid, conn = conn)
    expect_false(is.null(kayit))
    expect_identical(as.integer(kayit$session$ClaudeSessionRecordID), sid)
    expect_identical(nrow(kayit$runs), 2L)
    expect_identical(kayit$runs$Prompt, c("ilk", "ikinci"))
    expect_identical(kayit$runs$Status, c("completed", "failed"))

    # KULLANICI İZOLASYONU: B kullanıcısı A'nın oturumunu yükleyemez.
    expect_null(cc_db_load_session(user_id = 2L, session_record_id = sid, conn = conn))
    expect_null(cc_db_load_session(user_id = 1L, session_record_id = 9999L, conn = conn))
  })
})

test_that("yumuşak silme kullanıcı-izole çalışır ve fiziksel silmez", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 1L, title = "arşiv testi", conn = conn)
    cc_db_save_run(sid, prompt = "p", status = "completed", conn = conn)

    # KULLANICI İZOLASYONU: B kullanıcısı A'nın oturumunu arşivleyemez.
    expect_false(cc_db_soft_delete_session(user_id = 2L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 1L)

    # A kendi oturumunu arşivler; satır fiziksel olarak durur.
    expect_true(cc_db_soft_delete_session(user_id = 1L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 0L)

    arsiv <- cc_db_list_sessions(user_id = 1L, include_deleted = TRUE, conn = conn)
    expect_identical(nrow(arsiv), 1L)
    expect_identical(as.integer(arsiv$IsDeleted[1]), 1L)

    # Çalıştırma kayıtları da fiziksel olarak durur.
    kalan_run <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Runs")
    expect_identical(as.integer(kalan_run$n[1]), 1L)
  })
})

test_that("include_deleted TRUE aktif ve arşivlenmiş oturumları birlikte listeler", {
  .ccs_with_test_db(function(conn) {
    aktif <- cc_db_create_session(
      user_id = 1L,
      title = "aktif oturum",
      model = "model-a",
      conn = conn
    )
    arsiv <- cc_db_create_session(
      user_id = 1L,
      title = "arşiv oturumu",
      model = "model-b",
      conn = conn
    )

    expect_true(cc_db_soft_delete_session(
      user_id = 1L,
      session_record_id = arsiv,
      conn = conn
    ))

    varsayilan <- cc_db_list_sessions(user_id = 1L, conn = conn)
    expect_identical(nrow(varsayilan), 1L)
    expect_identical(as.integer(varsayilan$ClaudeSessionRecordID[1]), aktif)
    expect_identical(as.integer(varsayilan$IsDeleted[1]), 0L)

    tumu <- cc_db_list_sessions(
      user_id = 1L,
      include_deleted = TRUE,
      conn = conn
    )

    expect_identical(nrow(tumu), 2L)
    expect_setequal(
      as.integer(tumu$ClaudeSessionRecordID),
      c(aktif, arsiv)
    )
    expect_setequal(
      as.integer(tumu$IsDeleted),
      c(0L, 1L)
    )
  })
})

test_that("arşivden çıkarma (geri yükleme) kullanıcı-izole çalışır", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 1L, title = "geri yükleme testi", conn = conn)
    expect_true(cc_db_soft_delete_session(user_id = 1L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 0L)

    # KULLANICI İZOLASYONU: B kullanıcısı A'nın oturumunu geri yükleyemez.
    expect_false(cc_db_restore_session(user_id = 2L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 0L)

    # A kendi oturumunu geri yükler; normal listede yeniden görünür.
    expect_true(cc_db_restore_session(user_id = 1L, session_record_id = sid, conn = conn))
    liste <- cc_db_list_sessions(user_id = 1L, conn = conn)
    expect_identical(nrow(liste), 1L)
    expect_identical(as.integer(liste$IsDeleted[1]), 0L)
  })
})

test_that("kalıcı silme kullanıcı-izole ve geri alınamaz; alt kayıtları da siler", {
  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 1L, title = "kalıcı silme testi", conn = conn)
    cc_db_save_run(sid, prompt = "p1", status = "completed", conn = conn)
    cc_db_save_run(sid, prompt = "p2", status = "failed", conn = conn)

    # KULLANICI İZOLASYONU: B kullanıcısı A'nın oturumunu silemez; satırlar durur.
    expect_false(cc_db_hard_delete_session(user_id = 2L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 1L)
    expect_identical(
      as.integer(DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Runs")$n[1]),
      2L
    )

    # A oturumu KALICI siler: oturum VE tüm çalıştırmalar fiziksel olarak gider.
    expect_true(cc_db_hard_delete_session(user_id = 1L, session_record_id = sid, conn = conn))
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 0L)
    expect_identical(
      nrow(cc_db_list_sessions(user_id = 1L, include_deleted = TRUE, conn = conn)),
      0L
    )
    expect_identical(
      as.integer(DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Sessions")$n[1]),
      0L
    )
    expect_identical(
      as.integer(DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_ClaudeCode_Runs")$n[1]),
      0L
    )

    # Var olmayan / geçersiz kimlik güvenli FALSE döner.
    expect_false(cc_db_hard_delete_session(user_id = 1L, session_record_id = 9999L, conn = conn))
    expect_false(cc_db_hard_delete_session(user_id = 0L, session_record_id = 1L, conn = conn))
  })
})

test_that("kalıcı silme üretilen dosyaları indirme kökü altında kaldırır (kök dışını korur)", {
  # İndirme kökünü geçici bir dizine sabitle; bitince eski değeri geri yükle.
  kok_dizin <- file.path(tempdir(), paste0("byd_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(kok_dizin, recursive = TRUE, showWarnings = FALSE)
  eski_opt <- options(mergen.claude_code_download_root = kok_dizin)
  on.exit({
    options(eski_opt)
    suppressWarnings(unlink(kok_dizin, recursive = TRUE))
  }, add = TRUE)

  # Kök İÇİNDE bir üretilen dosya (silinmeli) ve kök DIŞINDA bir dosya
  # (kullanıcı izolasyonu/güvenlik: asla silinmemeli).
  ic_dosya <- file.path(kok_dizin, "rapor.docx")
  writeLines("ic", ic_dosya)
  dis_dosya <- tempfile(fileext = ".txt")
  writeLines("dis", dis_dosya)

  .ccs_with_test_db(function(conn) {
    sid <- cc_db_create_session(user_id = 1L, title = "silme + dosya", conn = conn)
    cc_db_save_run(
      sid, prompt = "belge üret", status = "completed",
      generated_downloads = list(
        list(display_name = "rapor.docx", download_path = ic_dosya),
        list(display_name = "harici.txt", download_path = dis_dosya)
      ),
      conn = conn
    )

    expect_true(file.exists(ic_dosya))
    expect_true(file.exists(dis_dosya))

    expect_true(cc_db_hard_delete_session(user_id = 1L, session_record_id = sid, conn = conn))

    # Kök içi üretilen dosya kaldırıldı; kök dışı dosya korundu.
    expect_false(file.exists(ic_dosya))
    expect_true(file.exists(dis_dosya))

    # DB satırları da fiziksel olarak gitti.
    expect_identical(nrow(cc_db_list_sessions(user_id = 1L, include_deleted = TRUE, conn = conn)), 0L)
  })

  suppressWarnings(unlink(dis_dosya))
})

test_that("tablolar yokken tüm fonksiyonlar güvenli boş/NULL/FALSE döner", {
  .ccs_with_test_db(function(conn) {
    expect_false(cc_db_claude_tables_available(conn = conn, force_refresh = TRUE))

    expect_no_error({
      expect_null(cc_db_create_session(user_id = 1L, title = "x", conn = conn))
      expect_null(cc_db_save_run(1L, prompt = "x", conn = conn))
      expect_false(cc_db_update_session_resume_state(1L, status = "completed", conn = conn))
      expect_identical(nrow(cc_db_list_sessions(user_id = 1L, conn = conn)), 0L)
      expect_null(cc_db_load_session(user_id = 1L, session_record_id = 1L, conn = conn))
      expect_false(cc_db_soft_delete_session(user_id = 1L, session_record_id = 1L, conn = conn))
      expect_false(cc_db_restore_session(user_id = 1L, session_record_id = 1L, conn = conn))
      expect_false(cc_db_hard_delete_session(user_id = 1L, session_record_id = 1L, conn = conn))
    })
  }, create_schema = FALSE)
})

test_that("liste sorgusu üretici güvenlik filtrelerini ve sıralamayı içerir", {
  plan <- .cc_db_sessions_list_query(
    user_id = 5L, limit = 10L, include_deleted = FALSE,
    query = "abc", status = "completed", model = "m", workdir = "C:/x",
    date_from = "2026-01-01", date_to = "2026-02-01",
    sort = "created", sqlite_yolu = TRUE
  )

  expect_true(grepl("s.UserID = ?", plan$sql, fixed = TRUE))
  expect_true(grepl("s.IsDeleted = 0", plan$sql, fixed = TRUE))
  expect_true(grepl("ORDER BY s.CreatedAt DESC", plan$sql, fixed = TRUE))
  expect_true(grepl("LIMIT ?", plan$sql, fixed = TRUE))
  expect_identical(plan$params[[1]], 5L)
  expect_identical(plan$params[[length(plan$params)]], 10L)

  # Üretim yolu (T-SQL) LIMIT yerine OFFSET/FETCH kullanır.
  plan_tsql <- .cc_db_sessions_list_query(
    user_id = 5L, limit = 10L, include_deleted = TRUE,
    query = NULL, status = "resumable", model = NULL, workdir = NULL,
    date_from = NULL, date_to = NULL,
    sort = "last_activity", sqlite_yolu = FALSE
  )
  expect_true(grepl("OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY", plan_tsql$sql, fixed = TRUE))
  expect_false(grepl("s.IsDeleted = 0", plan_tsql$sql, fixed = TRUE))
  expect_true(grepl("ClaudeCliSessionID IS NOT NULL", plan_tsql$sql, fixed = TRUE))
})