# ==============================================================================
# Dosya Yolu: tests/testthat/test-post-deploy-smoke-contract.R
# Açıklama: mergen_post_deploy_smoke_evaluate() saf değerlendiricisini ve
#           run_post_deploy_smoke.R kapı betiğinin sözleşmesini doğrular.
#           Betik çalıştırılmaz; saf karar mantığı ve kaynak sözleşmesi denetlenir.
#           Shiny/DB/HTTP gerektirmez.
# ==============================================================================

.find_smoke_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Post-deploy smoke testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_smoke <- .find_smoke_repo_root()

source(
  file.path(repo_root_smoke, "tests", "scripts", "helpers_post_deploy_smoke.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Byte-güvenli okuyucu (Windows VM'de geçersiz UTF-8 baytlarına dayanıklı).
.read_repo_text_smoke <- function(rel_path) {
  abs_path <- file.path(repo_root_smoke, rel_path)
  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }
  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}

# --- Saf değerlendirici davranışı -------------------------------------------

test_that("tum kontroller ok ise genel durum pass ve should_fail FALSE", {
  checks <- list(
    list(id = "app.boot", status = "ok"),
    list(id = "db.primary", status = "ok"),
    list(id = "storage.disk_free", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_identical(res$overall, "pass")
  expect_false(res$should_fail)
  expect_identical(res$total, 3L)
  expect_identical(as.integer(res$counts[["ok"]]), 3L)
})

test_that("kritik olmayan warning degraded yapar ama bloklamaz", {
  checks <- list(
    list(id = "llm.endpoint", status = "warning"),
    list(id = "app.boot", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_identical(res$overall, "degraded")
  expect_false(res$should_fail)
})

test_that("herhangi bir critical durum bloklar", {
  checks <- list(list(id = "some.check", status = "critical"))
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_true(res$should_fail)
  expect_identical(res$overall, "fail")
  expect_true("some.check" %in% res$failing)
})

test_that("data frame kontrol seti satir bazinda degerlendirilir (sutun degil)", {
  # health_collect_checks() do.call(rbind, ...) ile bir DATA FRAME döndürür:
  # satır başına bir kontrol. Değerlendirici satırları gezmeli; aksi halde
  # sütun iterasyonu tüm id'leri boş / tüm durumları "unknown" yapar ve gerçek
  # bir kritik bozulma kapıyı bloklayamaz.
  df <- do.call(rbind, list(
    data.frame(id = "app.boot",   status = "ok",       stringsAsFactors = FALSE),
    data.frame(id = "db.primary", status = "critical", stringsAsFactors = FALSE),
    data.frame(id = "llm.endpoint", status = "ok",     stringsAsFactors = FALSE)
  ))
  res <- mergen_post_deploy_smoke_evaluate(df)
  expect_true(res$should_fail)
  expect_identical(res$overall, "fail")
  expect_true("db.primary" %in% res$failing)
  expect_true("db.primary" %in% res$critical_failures)
  expect_identical(res$total, 3L)
  expect_identical(as.integer(res$counts[["ok"]]), 2L)
  expect_identical(as.integer(res$counts[["critical"]]), 1L)

  # Tümü ok olan data frame -> pass, bloklamaz.
  df_ok <- do.call(rbind, list(
    data.frame(id = "app.boot",   status = "ok", stringsAsFactors = FALSE),
    data.frame(id = "db.primary", status = "ok", stringsAsFactors = FALSE)
  ))
  res_ok <- mergen_post_deploy_smoke_evaluate(df_ok)
  expect_identical(res_ok$overall, "pass")
  expect_false(res_ok$should_fail)

  # 0 satırlı data frame -> no_checks ile bloklar (sütun sayısı > 0 olsa bile).
  df_empty <- data.frame(id = character(0), status = character(0), stringsAsFactors = FALSE)
  res_empty <- mergen_post_deploy_smoke_evaluate(df_empty)
  expect_true(res_empty$should_fail)
  expect_identical(res_empty$reason, "no_checks")
})

test_that("kritik kimlikli kontrolun warning olmasi bloklar", {
  checks <- list(
    list(id = "db.primary", status = "warning"),
    list(id = "app.boot", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_true(res$should_fail)
  expect_identical(res$overall, "fail")
  expect_true("db.primary" %in% res$critical_failures)
})

test_that("bos veya NULL kontrol seti no_checks ile bloklar", {
  res_empty <- mergen_post_deploy_smoke_evaluate(list())
  expect_true(res_empty$should_fail)
  expect_identical(res_empty$overall, "unknown")
  expect_identical(res_empty$reason, "no_checks")
  expect_identical(res_empty$total, 0L)

  res_null <- mergen_post_deploy_smoke_evaluate(NULL)
  expect_true(res_null$should_fail)
  expect_identical(res_null$reason, "no_checks")
})

test_that("durum takma adlari fallback ile normalize edilir", {
  expect_identical(
    mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "pass")))$overall,
    "pass"
  )
  res_fail <- mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "fail")))
  expect_true(res_fail$should_fail)
  expect_true("x" %in% res_fail$failing)
  expect_identical(
    mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "warn")))$overall,
    "degraded"
  )
})

test_that("fail_on_unknown kritik unknown davranisini kontrol eder", {
  checks <- list(
    list(id = "db.primary", status = "unknown"),
    list(id = "app.boot", status = "ok")
  )
  res_default <- mergen_post_deploy_smoke_evaluate(checks)
  expect_false(res_default$should_fail)
  expect_identical(res_default$overall, "degraded")

  res_strict <- mergen_post_deploy_smoke_evaluate(checks, fail_on_unknown = TRUE)
  expect_true(res_strict$should_fail)
  expect_identical(res_strict$overall, "fail")
})

test_that("eksik status alani unknown sayilir ve bloklamaz", {
  res <- mergen_post_deploy_smoke_evaluate(list(list(id = "x")))
  expect_false(res$should_fail)
  expect_identical(res$overall, "degraded")
})

test_that("ozel normalize_fn onurlandirilir", {
  always_ok <- function(s) "ok"
  res <- mergen_post_deploy_smoke_evaluate(
    list(list(id = "x", status = "critical")),
    normalize_fn = always_ok
  )
  expect_false(res$should_fail)
  expect_identical(res$overall, "pass")
})

# --- Artifact kaydı (mergen_post_deploy_smoke_artifact_record) ---------------

test_that("artifact kaydi gecen sonuctan secret-safe durustluk alanlari uretir", {
  res <- mergen_post_deploy_smoke_evaluate(list(
    list(id = "app.boot", status = "ok"),
    list(id = "db.primary", status = "ok"),
    list(id = "storage.disk_free", status = "ok")
  ))

  rec <- mergen_post_deploy_smoke_artifact_record(
    res,
    generated_at_utc = "2026-06-24T10:00:00Z",
    git_info = list(branch = "test-branch", sha = "abc1234", dirty = FALSE),
    r_version = "4.6.0"
  )

  expect_identical(rec$gate, "run_post_deploy_smoke")
  expect_identical(rec$validation_execution_status, "ran_by_post_deploy_smoke")
  expect_identical(rec$overall, "pass")
  expect_false(rec$should_fail)
  expect_identical(rec$generated_at_utc, "2026-06-24T10:00:00Z")
  expect_identical(rec$r_version, "4.6.0")
  expect_identical(rec$git$branch, "test-branch")
  expect_identical(rec$git$sha, "abc1234")
  expect_false(rec$git$dirty)

  # Dürüstlük alanları zorunludur (does_prove / does_not_prove / sınır notu).
  expect_true(is.character(rec$does_prove) && nzchar(rec$does_prove))
  expect_true(is.character(rec$does_not_prove) && nzchar(rec$does_not_prove))
  expect_true(is.character(rec$proof_boundary_notes) && nzchar(rec$proof_boundary_notes))
  expect_true(is.character(rec$secret_policy) && nzchar(rec$secret_policy))

  # counts isimli tam-sayı listesi olmalı (table değil); ok=3.
  expect_true(is.list(rec$counts))
  expect_identical(as.integer(rec$counts$ok), 3L)
})

test_that("artifact kaydi kritik basarisizligi ve sayaclari tasir", {
  res <- mergen_post_deploy_smoke_evaluate(list(
    list(id = "db.primary", status = "critical"),
    list(id = "app.boot", status = "ok")
  ))

  rec <- mergen_post_deploy_smoke_artifact_record(res, fail_on_unknown = TRUE)

  expect_identical(rec$overall, "fail")
  expect_true(rec$should_fail)
  expect_true("db.primary" %in% rec$critical_failures)
  expect_true("db.primary" %in% rec$failing)
  expect_true(rec$fail_on_unknown)
  # Kritik kimlikler kayda işlenir (varsayılan kümeden).
  expect_true("db.primary" %in% rec$critical_ids)
})

test_that("artifact kaydi generated_at_utc bos verilince UTC zaman damgasi uretir", {
  res <- mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "ok")))
  rec <- mergen_post_deploy_smoke_artifact_record(res)
  expect_true(is.character(rec$generated_at_utc) && nzchar(rec$generated_at_utc))
  # ISO benzeri UTC formatı (…Z ile biter).
  expect_true(grepl("Z$", rec$generated_at_utc))
})

test_that("kanit kaydi calisan-servis kanitini abartmaz (in-process snapshot)", {
  rec <- mergen_post_deploy_smoke_artifact_record(
    mergen_post_deploy_smoke_evaluate(list(list(id = "app.boot", status = "ok"))),
    generated_at_utc = "2026-06-24T10:00:00Z"
  )
  # does_prove yalnızca in-process / güvenli-boot dilini taşımalı (Shiny servisi
  # başlatılmadığı için "çalışan uygulama" abartısı kaldırıldı).
  expect_true(grepl("in-process", rec$does_prove, fixed = TRUE))
  expect_true(grepl("MERGEN_RUN_APP=false", rec$does_prove, fixed = TRUE))
  # does_not_prove servis ayakta/app URL probe edilmediğini açıkça söylemeli.
  expect_true(grepl("app URL", rec$does_not_prove, fixed = TRUE))
})

# --- Artifact redaksiyon güvenliği (şema-koruyan, yalnızca string değerler) ---

test_that("redact-record yalnizca string degerleri redakte eder; anahtar/sayaclari korur", {
  rec <- mergen_post_deploy_smoke_artifact_record(
    mergen_post_deploy_smoke_evaluate(list(
      list(id = "db.primary", status = "critical"),
      list(id = "app.boot", status = "ok")
    )),
    generated_at_utc = "2026-06-24T10:00:00Z"
  )

  # 1) Bir kontrol kimliğindeki alt-dize redakte edilse bile counts anahtarları
  #    ve sayıları AYNEN korunur (okuyucu yanlış sıfır sayım raporlamaz).
  redacted <- mergen_post_deploy_smoke_redact_record(
    rec, redact_fn = function(x) gsub("primary", "<hidden>", x, fixed = TRUE)
  )
  expect_identical(redacted$counts, rec$counts)
  expect_identical(redacted$total, rec$total)
  expect_identical(redacted$overall, rec$overall)
  expect_identical(redacted$should_fail, rec$should_fail)
  # string DEĞER (critical_failures içindeki db.primary) redakte edilmiş olmalı
  expect_true(any(grepl("<hidden>", unlist(redacted$critical_failures), fixed = TRUE)))

  # 2) Şema token'ı simülasyonu: secret değeri "ok" olsa bile counts ANAHTARI
  #    "ok" bozulmaz (anahtarlar redaktöre verilmez, yalnızca değerler verilir).
  #    Önceki "serileştirilmiş JSON'u kör redakte et" yaklaşımı counts.ok anahtarını
  #    <hidden> ile ezip okuyucunun yanlış sıfır sayım raporlamasına yol açabilirdi.
  redacted2 <- mergen_post_deploy_smoke_redact_record(
    rec, redact_fn = function(x) gsub("ok", "<hidden>", x, fixed = TRUE)
  )
  expect_true("ok" %in% names(redacted2$counts))
  expect_identical(redacted2$counts, rec$counts)

  # 3) Redakte edilmiş kayıt her zaman GEÇERLİ JSON üretir (şema bozulmaz).
  j <- as.character(jsonlite::toJSON(redacted2, auto_unbox = TRUE, pretty = TRUE, null = "null"))
  expect_true(isTRUE(jsonlite::validate(j)))

  # 4) NULL/geçersiz redaktör -> kayıt değişmeden döner.
  expect_identical(mergen_post_deploy_smoke_redact_record(rec, NULL), rec)
  expect_identical(mergen_post_deploy_smoke_redact_record(rec, "x"), rec)
})

test_that("redact-record durum enum/kimlik alanlarini redaksiyondan korur", {
  # degraded (geçen-ama-uyarılı) kapı: secret değeri "degraded"e denk gelse bile
  # overall ezilmemeli — aksi halde panel geçen/degraded kapıyı nötr/unknown gösterir.
  rec_deg <- mergen_post_deploy_smoke_artifact_record(
    mergen_post_deploy_smoke_evaluate(list(
      list(id = "llm.endpoint", status = "warning"),
      list(id = "app.boot", status = "ok")
    )),
    generated_at_utc = "2026-06-24T10:00:00Z"
  )
  expect_identical(rec_deg$overall, "degraded")
  red_deg <- mergen_post_deploy_smoke_redact_record(
    rec_deg, redact_fn = function(x) gsub("degraded", "<hidden>", x, fixed = TRUE)
  )
  expect_identical(red_deg$overall, "degraded")

  # fail kapı: overall/reason/gate/validation_execution_status redaksiyon SONRASI
  # orijinalden geri yüklenir (kısa enum/kimlik token'ı secret'e denk gelse bile).
  rec_fail <- mergen_post_deploy_smoke_artifact_record(
    mergen_post_deploy_smoke_evaluate(list(list(id = "db.primary", status = "critical"))),
    generated_at_utc = "2026-06-24T10:00:00Z"
  )
  red_fail <- mergen_post_deploy_smoke_redact_record(
    rec_fail,
    redact_fn = function(x) gsub("fail|run_post_deploy_smoke|ran_by_post_deploy_smoke", "<hidden>", x)
  )
  expect_identical(red_fail$overall, rec_fail$overall)
  expect_identical(red_fail$reason, rec_fail$reason)
  expect_identical(red_fail$gate, "run_post_deploy_smoke")
  expect_identical(red_fail$validation_execution_status, "ran_by_post_deploy_smoke")
})

test_that("failure-result erken-cikis icin fail kaydi uretir", {
  fr <- mergen_post_deploy_smoke_failure_result("app_boot_failed")
  expect_identical(fr$overall, "fail")
  expect_true(fr$should_fail)
  expect_identical(fr$reason, "app_boot_failed")
  expect_identical(fr$total, 0L)
  expect_identical(fr$failing, character(0))

  # Bu sonuç geçerli bir kanıt kaydına dönüşür (overall=fail, should_fail=TRUE).
  rec <- mergen_post_deploy_smoke_artifact_record(fr, generated_at_utc = "2026-06-24T10:00:00Z")
  expect_identical(rec$overall, "fail")
  expect_true(rec$should_fail)

  # Boş/NA neden güvenli fallback'e düşer.
  expect_identical(mergen_post_deploy_smoke_failure_result("")$reason, "unknown_failure")
  expect_identical(mergen_post_deploy_smoke_failure_result(NULL)$reason, "unknown_failure")
})

# --- git alan değeri temizleme (mergen_post_deploy_smoke_clean_git_value) ----

test_that("git hata ciktisi/sifir-disi cikis dal/sha yerine bos string verir", {
  # Üretim VM'i git deposu değilse system2 sıfır-dışı status + "fatal:" metni döner.
  fatal_out <- "fatal: not a git repository (or any of the parent directories): .git"
  expect_identical(
    mergen_post_deploy_smoke_clean_git_value(fatal_out, status = 128L),
    ""
  )
  # Status verilmese bile "fatal:" öneki dal/sha olamaz -> boş.
  expect_identical(mergen_post_deploy_smoke_clean_git_value(fatal_out, status = NULL), "")
  # Diğer git hata önekleri de korunur.
  expect_identical(mergen_post_deploy_smoke_clean_git_value("error: bir sey", NULL), "")
  expect_identical(mergen_post_deploy_smoke_clean_git_value("usage: git ...", NULL), "")
})

test_that("basarili git ciktisi gercek dal/sha degerini korur", {
  # Başarı: status sıfır (veya NULL/attr yok) -> gerçek değer aynen döner.
  expect_identical(
    mergen_post_deploy_smoke_clean_git_value("claude/admiring-ride-qajux6", status = 0L),
    "claude/admiring-ride-qajux6"
  )
  expect_identical(
    mergen_post_deploy_smoke_clean_git_value("abc1234", status = NULL),
    "abc1234"
  )
  # Birden çok satırda yalnızca ilk satır kullanılır; baştaki/sondaki boşluk kırpılır.
  expect_identical(
    mergen_post_deploy_smoke_clean_git_value(c("  main  ", "ek"), status = 0L),
    "main"
  )
})

test_that("bos/NULL git ciktisi guvenle bos string verir", {
  expect_identical(mergen_post_deploy_smoke_clean_git_value(character(0), NULL), "")
  expect_identical(mergen_post_deploy_smoke_clean_git_value(NULL, NULL), "")
  expect_identical(mergen_post_deploy_smoke_clean_git_value("", 0L), "")
})

# --- Kapı betiği sözleşmesi --------------------------------------------------

test_that("run_post_deploy_smoke.R kapi sozlesmesini icerir", {
  script_rel <- "tests/scripts/run_post_deploy_smoke.R"
  expect_true(
    file.exists(file.path(repo_root_smoke, script_rel)),
    info = "tests/scripts/run_post_deploy_smoke.R eklenmelidir."
  )

  txt <- .read_repo_text_smoke(script_rel)

  expect_true(grepl("health_collect_checks", txt, fixed = TRUE))
  expect_true(grepl("mergen_post_deploy_smoke_evaluate", txt, fixed = TRUE))
  expect_true(grepl("source(\"app.R\"", txt, fixed = TRUE))
  expect_true(grepl("stop(", txt, fixed = TRUE))
  expect_true(grepl("redact", txt, fixed = TRUE))

  # Makinece okunabilir secret-safe artifact üretimi sözleşmesi.
  expect_true(grepl("mergen_post_deploy_smoke_artifact_record", txt, fixed = TRUE))
  expect_true(grepl("post-deploy-smoke", txt, fixed = TRUE))
  expect_true(grepl("toJSON", txt, fixed = TRUE))
  expect_true(grepl("artifacts", txt, fixed = TRUE))
  # Redaksiyon JSON şemasını/sayaç anahtarlarını bozmamalı: kapı, yalnızca
  # string DEĞERLERİ redakte eden şema-koruyan kayıt redaktörünü kullanmalı.
  expect_true(grepl("mergen_post_deploy_smoke_redact_record", txt, fixed = TRUE))
  # Erken boot/env başarısızlıklarında bile stop'tan ÖNCE bir başarısızlık
  # artifact'ı yazılmalı (sağlık paneli koşumu "not_found" sanmasın).
  expect_true(grepl("mergen_post_deploy_smoke_failure_result", txt, fixed = TRUE))
})

test_that("smoke betikleri base R ile parse edilebilir", {
  for (rel in c(
    "tests/scripts/helpers_post_deploy_smoke.R",
    "tests/scripts/run_post_deploy_smoke.R"
  )) {
    abs_path <- file.path(repo_root_smoke, rel)
    # parse(file=) lokale bağlı uyarı üretebilir; suite stop_on_warning=TRUE
    # ile çalıştığı için uyarıyı bastırıp yalnızca parse başarısını doğrula.
    parsed <- tryCatch(
      suppressWarnings(parse(file = abs_path, encoding = "UTF-8")),
      error = function(e) NULL
    )
    expect_false(is.null(parsed), info = rel)
    expect_true(length(parsed) > 0L, info = rel)
  }
})
