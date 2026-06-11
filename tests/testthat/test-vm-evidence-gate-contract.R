# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-evidence-gate-contract.R
# Açıklama: tests/scripts/run_vm_evidence_gate.R tek tekrarlanabilir preflight
#           doğrulama yolunun yapısal sözleşmesini dondurur. Ağır adımları
#           ÇALIŞTIRMAZ: kapı betiğini parse/statik düzeyde ve hafif yardımcı
#           davranış düzeyinde doğrular. Gerçek DB, LLM, tarayıcı, SSO yok.
#
#           Korunan sözleşmeler:
#             - Betik parse edilir, quit() çağırmaz (source-safe).
#             - Dondurulmuş kanıt adım listesi bilinçli güncelleme gerektirir.
#             - VM-yalnız kapılar (vm_preflight_real, db_encoding_preflight,
#               renv_status) yalnızca vm profilinde zorunludur.
#             - Secret-güvenlik: metadata yardımcı + redaksiyon yardımcı +
#               secret_policy alanı mevcuttur; evidence.json ham değer taşımaz.
#             - Adımlar temiz çocuk R oturumlarında koşulur (Rscript --vanilla).
#             - Artifact yolu artifacts/vm-evidence altındadır.
#             - DB kodlama adımı transactional write-probe bayrağını açar.
# ==============================================================================

.evg_repo_root <- resolve_repo_root_for_tests()
.evg_script_path <- file.path(.evg_repo_root, "tests", "scripts", "run_vm_evidence_gate.R")
.evg_wrapper_path <- file.path(.evg_repo_root, "tools", "vm_evidence_gate.sh")

# Windows-güvenli bayt okuyucu: Türkçe yorumlu dosyalar için byte-safe tarama.
.evg_read_text <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  text <- rawToChar(raw_bytes)
  Encoding(text) <- "UTF-8"
  iconv(text, from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("kanit kapisi betigi mevcuttur ve parse edilir", {
  expect_true(file.exists(.evg_script_path))
  expect_true(file.exists(.evg_wrapper_path))

  parsed <- tryCatch(
    parse(file = .evg_script_path, encoding = "UTF-8"),
    error = function(e) NULL
  )
  expect_false(is.null(parsed), info = "run_vm_evidence_gate.R parse edilebilir olmalıdır.")
})

test_that("kanit kapisi quit() cagirmaz ve stop() ile biter (source-safe)", {
  text <- .evg_read_text(.evg_script_path)

  # Yorum satırları taramadan önce çıkarılır; açıklayıcı yorumlar yanlış
  # pozitif üretmemelidir (repo kuralı).
  code_lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  code_lines <- code_lines[!grepl("^\\s*#", code_lines, perl = TRUE)]
  code_text <- paste(code_lines, collapse = "\n")

  expect_false(
    grepl("\\bquit\\s*\\(", code_text, perl = TRUE),
    info = "Kapı betiği quit() çağırmamalıdır; source(...) ile güvenli kalmalıdır."
  )
  expect_true(
    grepl("stop(", code_text, fixed = TRUE),
    info = "Zorunlu adım başarısızlığı stop() ile bildirilmelidir."
  )
})

# Dondurulmuş kanıt adımları: ekleme/çıkarma bilinçli güncelleme gerektirir ve
# docs ile birlikte yapılmalıdır.
.evg_expected_steps <- c(
  "env_config",
  "parse_sanity",
  "app_boot_smoke",
  "full_testthat",
  "maintainability_report",
  "frontend_ratchet",
  "seam_doctor",
  "source_manifest_contracts",
  "ui_asset_manifest_contracts",
  "browser_ux_smoke",
  "vm_preflight_real",
  "db_encoding_preflight",
  "renv_status"
)

test_that("dondurulmus kanit adim listesi betikte tanimlidir", {
  text <- .evg_read_text(.evg_script_path)

  for (step_id in .evg_expected_steps) {
    expect_true(
      grepl(sprintf('id = "%s"', step_id), text, fixed = TRUE),
      info = sprintf("Kanıt adımı betikte tanımlı olmalıdır: %s", step_id)
    )
  }
})

test_that("VM-yalniz kapilar yalnizca vm profilinde zorunludur", {
  text <- .evg_read_text(.evg_script_path)

  # vm_preflight_real, db_encoding_preflight ve renv_status adımları
  # required_in = c("vm") taşımalıdır; cloud bunları gerekçeli SKIP eder.
  vm_only_count <- length(gregexpr('required_in = c("vm")', text, fixed = TRUE)[[1]])
  expect_gte(vm_only_count, 3L)

  expect_true(
    grepl("VM-yalniz kapi; cloud profilinde gerekceli SKIP", text, fixed = TRUE),
    info = "Cloud profili VM-yalnız adımları gerekçeli SKIP olarak raporlamalıdır."
  )
})

test_that("secret-guvenlik sozlesmesi: metadata + redaksiyon + policy alani", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("evidence_value_metadata", text, fixed = TRUE),
    info = "Ortam değişkenleri yalnızca metadata olarak raporlanmalıdır."
  )
  expect_true(
    grepl('value = "<hidden>"', text, fixed = TRUE),
    info = "Metadata value alanı daima <hidden> olmalıdır."
  )
  expect_true(
    grepl("evidence_redact_text", text, fixed = TRUE),
    info = "Adım logları ve JSON çıktı redaksiyon yardımcısından geçmelidir."
  )
  expect_true(
    grepl("secret_policy", text, fixed = TRUE),
    info = "evidence.json secret_policy alanı taşımalıdır."
  )
})

test_that("adimlar temiz cocuk R oturumlarinda kosulur", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("--vanilla", text, fixed = TRUE),
    info = "Çocuk oturumlar Rscript --vanilla ile koşulmalıdır."
  )
  expect_true(
    grepl("system2(", text, fixed = TRUE),
    info = "Adım izolasyonu system2 çocuk süreciyle sağlanmalıdır."
  )
})

test_that("artifact yolu ve dogrulama-kanit alanlari sabittir", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl('file.path("artifacts", "vm-evidence"', text, fixed = TRUE),
    info = "Kanıt artifact'ı artifacts/vm-evidence altına yazılmalıdır."
  )
  expect_true(
    grepl("ran_by_vm_evidence_gate", text, fixed = TRUE),
    info = "validation_execution_status alanı kapıya özgü olmalıdır."
  )
  expect_true(
    grepl("proof_boundary_notes", text, fixed = TRUE),
    info = "Kanıt sınırı notları evidence.json içinde olmalıdır."
  )
  expect_true(
    grepl("does_not_prove", text, fixed = TRUE),
    info = "Her adım neyi KANITLAMADIĞINI da bildirmelidir."
  )
})

test_that("tarayici smoke adimi yalnizca UX_SMOKE_DONE:PASS kanitiyla passed sayilir", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl("UX_SMOKE_DONE:PASS", text, fixed = TRUE),
    info = "Tarayıcı smoke adımı gerçek PASS işaretini aramalıdır; exit 0 tek başına kanıt değildir."
  )
  expect_true(
    grepl("ux_smoke_pass_marker", text, fixed = TRUE),
    info = "PASS işareti gözlemi evidence.json detail alanına yazılmalıdır."
  )
})

test_that("db kodlama adimi transactional write-probe bayragini acar", {
  text <- .evg_read_text(.evg_script_path)

  expect_true(
    grepl('MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST = "TRUE"', text, fixed = TRUE),
    info = "DB kodlama preflight adımı yazma probunu açmalıdır."
  )
  expect_true(
    grepl("run_vm_encoding_preflight_real.R", text, fixed = TRUE),
    info = "DB kodlama adımı mevcut kodlama preflight betiğini kullanmalıdır."
  )
  expect_true(
    grepl("run_vm_preflight_real.R", text, fixed = TRUE),
    info = "VM preflight adımı mevcut gerçek preflight betiğini kullanmalıdır."
  )
})

test_that("sarmalayici betik repo kokunden Rscript ile kapiyi cagirir", {
  text <- .evg_read_text(.evg_wrapper_path)

  expect_true(grepl("set -euo pipefail", text, fixed = TRUE))
  expect_true(grepl("run_vm_evidence_gate.R", text, fixed = TRUE))
  expect_true(
    grepl("command -v Rscript", text, fixed = TRUE),
    info = "Sarmalayıcı Rscript yokluğunda açık hata vermelidir."
  )
})

test_that("gecersiz profil degeri acik hata uretir (hafif davranis kontrolu)", {
  # Yalnızca profil doğrulama dalını tetikler; hiçbir adım koşulmaz.
  rscript_bin <- file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") rscript_bin <- paste0(rscript_bin, ".exe")
  skip_if_not(file.exists(rscript_bin), "Rscript bulunamadı.")

	out_log <- tempfile(fileext = ".log")
	# Çocuk oturum testin çalışma dizinini miras alır; betik mutlak yolla verilir.
	# Windows'ta system2(env=...) davranışı kırılgan olabildiği için profil değeri
	# çocuk R ifadesinin içinde set edilir.
	child_expr <- sprintf(
	  'Sys.setenv(MERGEN_EVIDENCE_PROFILE = "bozuk_profil"); source(%s, encoding = "UTF-8")',
	  dQuote(normalizePath(.evg_script_path, winslash = "/", mustWork = TRUE))
	)
	status <- suppressWarnings(system2(
	  rscript_bin,
	  args = c("--vanilla", "-e", shQuote(child_expr)),
	  stdout = out_log,
	  stderr = out_log
	))

  expect_false(identical(status, 0L), info = "Geçersiz profil sıfır-dışı çıkış üretmelidir.")

	log_text <- .evg_read_text(out_log)
	expect_true(
	  grepl("MERGEN_EVIDENCE_PROFILE", log_text, fixed = TRUE, useBytes = TRUE),
	  info = "Hata mesajı geçersiz profil değişkenini açıkça adlandırmalıdır."
	)
	unlink(out_log, force = TRUE)
})