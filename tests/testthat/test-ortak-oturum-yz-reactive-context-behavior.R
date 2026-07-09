# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-yz-reactive-context-behavior.R
# Açıklama: Ortak Oturum yapay zekâ üretim motorunun REAKTİF BAĞLAM güvenliği
#           regresyon testi. Kritik hata: "Yapay Zekâya Sor" sonrası ağır üretim
#           işi session$onFlushed'a (ve kuyruk zincirinde promise callback'ine)
#           ertelenir. Bu callback'ler reaktif ALAN içinde ama reaktif BAĞLAM
#           (consumer) DIŞINDA koşar. etkin_model() secili_model reactiveVal'ını
#           doğrudan okuduğu için orada "Operation not allowed without an active
#           reactive context" hatasıyla patlıyor ve HER soruda "Yapay zekâ yanıtı
#           başlatılamadı; lütfen tekrar deneyin." olarak yüzeye çıkıyordu.
#
#           NOT: shiny::testServer test gövdesini aktif bir reaktif bağlamda
#           çalıştırdığı için bu hatayı MASKELER. Bu yüzden test, gerçek uygulama
#           onFlushed koşulunu (withReactiveDomain + bağlam YOK) çıplak
#           MockShinySession ile yeniden üretir. Gerçek DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")
testthat::skip_if_not_installed("shiny")
testthat::skip_if_not_installed("promises")

local({
  repo_root <- resolve_repo_root_for_tests()

  # Modül gövdesi çıplak shiny fonksiyonları (reactiveVal/reactiveValues/observe/
  # renderUI) kullandığından bağlayıcıyı testServer olmadan çağırmak için shiny
  # search path'e eklenir.
  suppressPackageStartupMessages(library(shiny))

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_encoding.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_unicode_escape.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("get_character_record", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_characters.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_rol_yetkileri", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_oturum_persona_kimligi", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_sunum.R"), encoding = "UTF-8", local = globalenv())
  }
  for (dosya in c(
    "helpers_ortak_oturum_db.R",
    "helpers_ortak_oturum_db_katilim.R",
    "helpers_ortak_oturum_db_davet.R",
    "helpers_ortak_oturum_db_mesajlar.R",
    "helpers_ortak_oturum_db_kuyruk.R"
  )) {
    if (!exists("ortak_db_mesaj_ekle", mode = "function", inherits = TRUE) ||
        identical(dosya, "helpers_ortak_oturum_db_kuyruk.R")) {
      source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
    }
  }
  source(file.path(repo_root, "R", "module_ortak_oturum_yz.R"), encoding = "UTF-8", local = globalenv())
})

.ooc_conn <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(conn, "CREATE TABLE MB_Users (UserID INTEGER PRIMARY KEY AUTOINCREMENT, KullaniciAdi TEXT, KaynakAdi TEXT, Email TEXT, Departman TEXT, Sicil TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturumlar (OrtakOturumID INTEGER PRIMARY KEY AUTOINCREMENT, KaynakTuru TEXT NOT NULL, KaynakID INTEGER, Baslik TEXT, OlusturanKullaniciID INTEGER NOT NULL, OturumDurumu TEXT NOT NULL, PaylasimBaslangicTipi TEXT, SonEtkinlikZamani TEXT, OlusturmaZamani TEXT, GuncellemeZamani TEXT, SecilenPersona TEXT, MetaJson TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Katilimcilar (KatilimciID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, KullaniciID INTEGER NOT NULL, Rol TEXT NOT NULL, KatilimDurumu TEXT NOT NULL, KullaniciGorunumDurumu TEXT NOT NULL, DavetEdenKullaniciID INTEGER, DavetZamani TEXT, KatilmaZamani TEXT, SonGorulmeZamani TEXT, OlusturmaZamani TEXT, UNIQUE (OrtakOturumID, KullaniciID))")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Mesajlar (OrtakMesajID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, GonderenKullaniciID INTEGER, MesajTuru TEXT NOT NULL, Hedef TEXT NOT NULL, MesajMetni TEXT, BagliMesajID INTEGER, MesajSirasi INTEGER NOT NULL, LLMGonderildiMi INTEGER NOT NULL DEFAULT 0, OlusturmaZamani TEXT, MetaJson TEXT, UNIQUE (OrtakOturumID, MesajSirasi))")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_YapayZekaKuyrugu (KuyrukID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, OrtakMesajID INTEGER NOT NULL, SiraNo INTEGER NOT NULL, Durum TEXT NOT NULL, OlusturmaZamani TEXT, BaslamaZamani TEXT, BitisZamani TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_AktifUretimler (OrtakOturumID INTEGER PRIMARY KEY, BaslatanKullaniciID INTEGER NOT NULL, OrtakMesajID INTEGER, IstekID TEXT NOT NULL, KilitDurumu TEXT NOT NULL, BaslamaZamani TEXT, GuncellemeZamani TEXT, KismiYanit TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Olaylar (OlayID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, OlayTuru TEXT NOT NULL, TetikleyenKullaniciID INTEGER, PayloadJson TEXT, OlusturmaZamani TEXT)")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi) VALUES ('ayse','Ayse Y')")
  conn
}

test_that("gerçek reaktif bağlam DIŞINDA reactiveVal okumak patlar (regresyonun temeli)", {
  # Bu test, hatanın mekanizmasını belgeler: reaktif ALAN içinde ama reaktif
  # BAĞLAM dışında bir reactiveVal doğrudan okumak hata fırlatır; isolate güvenlidir.
  sess <- shiny::MockShinySession$new()
  rv <- shiny::withReactiveDomain(sess, shiny::reactiveVal("model-x"))

  ham <- tryCatch(
    shiny::withReactiveDomain(sess, rv()),
    error = function(e) conditionMessage(e)
  )
  expect_true(grepl("reactive context", ham, fixed = TRUE))

  izole <- shiny::withReactiveDomain(sess, as.character(shiny::isolate(rv())))
  expect_identical(izole, "model-x")
})

# Bir dizi global sembolü stub'lar ve orijinallerini geri yükleyen kapatma döner.
# Test, tam suite'te (paylaşılan oturum) hangi LLM/future fonksiyonlarının yüklü
# olduğundan BAĞIMSIZ olmalıdır; bu yüzden üretim yolunun her iki dalı da (SSE /
# non-SSE) SENKRON çözülecek biçimde stub'lanır.
.ooc_stub_globals <- function(stubs) {
  eski <- list()
  vardi <- character(0)
  for (nm in names(stubs)) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) {
      eski[[nm]] <- get(nm, envir = globalenv(), inherits = FALSE)
      vardi <- c(vardi, nm)
    }
    assign(nm, stubs[[nm]], envir = globalenv())
  }
  function() {
    for (nm in names(stubs)) {
      if (nm %in% vardi) {
        assign(nm, eski[[nm]], envir = globalenv())
      } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
        rm(list = nm, envir = globalenv())
      }
    }
  }
}

test_that("motor$uret reaktif bağlam dışında (onFlushed benzeri) patlamaz ve yanıt üretir", {
  conn <- .ooc_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Bağlantı + LLM + future yardımcıları enjekte edilen SQLite'a / senkron
  # çözüme yönlendirilir. tracked_future_promise SENKRON çözülür ki sonuç
  # deterministik olsun (SSE veya non-SSE dalından bağımsız).
  geri_yukle <- .ooc_stub_globals(list(
    get_connection = function(target = "primary") list(conn = conn, pooled = FALSE, pool = NULL),
    release_connection = function(ci) invisible(NULL),
    db_acquire_tx_connection = function(target = "primary") list(conn = conn),
    db_release_tx_connection = function(info) invisible(NULL),
    call_local_llm = function(gecmis, ayarlar) list(content = "yapay zeka yaniti"),
    call_local_llm_sse_worker = function(chat_history, current_settings, stream_file, stop_file) list(content = "yapay zeka yaniti"),
    mergen_true_streaming_worker_globals = function(chat_history_for_sse, settings_for_sse, stream_file_for_sse, stop_file_for_sse) list(),
    mergen_stream_classify_poll_lines = function(lines) list(delta_text = ""),
    tracked_future_promise = function(task_fn, task_type = NULL, session_token = NULL, globals = NULL, ...) {
      promises::promise(function(resolve, reject) {
        tryCatch(resolve(task_fn()), error = function(e) reject(e))
      })
    }
  ))
  on.exit(geri_yukle(), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Bağlam Testi", 1L, conn = conn)

  toasts <- character(0)
  motor <- new.env(parent = emptyenv())
  sess <- shiny::MockShinySession$new()

  shiny::withReactiveDomain(sess, {
    secili_model <- shiny::reactiveVal("secilen-model")
    ctx <- list(
      aktif_oturum = shiny::reactiveVal(oturum_id),
      current_user_id = function() 1L,
      oturum_bilgisi = shiny::reactive(ortak_db_oturum_getir(oturum_id)),
      benim_katilimim = shiny::reactive(ortak_db_katilimci_getir(oturum_id, 1L)),
      katilimcilar = shiny::reactive(ortak_db_katilimci_listesi(oturum_id)),
      secili_model = secili_model,
      aktif_uretim = shiny::reactive(ortak_db_aktif_uretim_detay(oturum_id)),
      bekleyenler = shiny::reactive(ortak_db_kuyruk_bekleyenler(oturum_id)),
      parent_session = sess,
      bildir = function(mesaj, tur = "message") {
        toasts[[length(toasts) + 1L]] <<- paste0("[", tur, "] ", mesaj)
      },
      yenile = function() invisible(NULL)
    )
    scope <- sess$makeScope("oda")
    ortakOturumYzBind(scope$input, scope$output, scope, ctx = ctx, motor = motor)
  })

  # Soru + kilit senkron alınır (bunlar reaktif bağlam gerektirmez).
  soru_id <- ortak_db_mesaj_ekle(oturum_id, 1L, "YapayZekaSorusu", "Merhaba yapay zekâ",
                                 llm_gonderildi = TRUE, conn = conn)
  expect_false(is.null(soru_id))
  kilit <- ortak_db_uretim_kilidi_al(oturum_id = oturum_id, baslatan_kullanici_id = 1L,
                                     istek_id = "istek_ctx", mesaj_id = soru_id, conn = conn)
  expect_true(isTRUE(kilit))

  # KRİTİK: motor$uret reaktif ALAN içinde ama reaktif BAĞLAM DIŞINDA çağrılır
  # (gerçek uygulamada session$onFlushed / promise callback bu koşulda koşar).
  hata <- NULL
  shiny::withReactiveDomain(sess, {
    tryCatch(
      motor$uret(oturum_id, soru_id, 1L, "istek_ctx", "Merhaba yapay zekâ"),
      error = function(e) hata <<- conditionMessage(e)
    )
  })

  # Senkron çözülen promise'in then callback'i later kuyruğundadır; yanıt
  # kalıcılaşana kadar (ya da üst sınıra kadar) drain edilir.
  yanit_var <- function() {
    m <- DBI::dbGetQuery(conn, "SELECT MesajTuru FROM MB_OrtakOturum_Mesajlar")
    "YapayZekaYanıtı" %in% as.character(m$MesajTuru)
  }
  for (i in 1:100) {
    later::run_now()
    if (yanit_var()) break
  }

  # Reaktif bağlam hatası fırlatılmamalı; "başlatılamadı" toast'ı OLMAMALI.
  # (Bu, düzeltmeden ÖNCE başarısız olan asıl invariant'tır.)
  expect_null(hata)
  expect_false(any(grepl("reactive context", toasts, fixed = TRUE)))
  expect_false(any(grepl("başlatılamadı", toasts, fixed = TRUE)))

  # Yanıt üretildi ve YapayZekaYanıtı olarak kalıcılaştırıldı.
  expect_true(yanit_var())
})
