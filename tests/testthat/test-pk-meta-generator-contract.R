# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-generator-contract.R
# Açıklama: Faz 3b — metadata üreticisinin YAPISAL sözleşmesi (statik).
#           Tamamen çevrimdışıdır: DB, LLM, tarayıcı, SSO, ağ GEREKMEZ ve
#           üreticiyi ÇALIŞTIRMAZ.
#
# Korunan sınırlar:
#   - Operatör giriş noktası TAM olarak tools/pk/generate_query_meta.R'dir.
#   - Üretici ÇALIŞMA ZAMANI kodu DEĞİLDİR: kaynak manifestine girmez.
#   - `source(...)` güvenlidir: `quit()` çağırmaz.
#   - Üretilen/yerel dosyalar ve artefakt dizini gitignore'ludur.
#   - Üretici izlenen metadata dosyalarına ve operatör alias dosyasına yazmaz.
#
# Dosya taramaları Windows VM'de geçerli olacak biçimde BAYT GÜVENLİ okunur
# (readBin + iconv(sub="byte") + useBytes); Türkçe yorumlu dosyalarda düz
# readLines(encoding="UTF-8") VM'de "invalid UTF-8" ile kırılır.
# ==============================================================================

.pkgc_read_bytes <- function(path) {
  boyut <- suppressWarnings(file.info(path)$size[1])
  if (is.na(boyut) || boyut <= 0) return("")

  ham <- readBin(path, what = "raw", n = boyut)
  metin <- suppressWarnings(iconv(list(ham), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(metin)) return("")
  gsub("\r\n?|\r", "\n", metin, perl = TRUE)
}

# YALNIZCA KOD (yorumlar hariç).
#
# Depo kuralı: yasaklı-desen taramaları taramadan ÖNCE yorum satırlarını
# yok saymalıdır; aksi hâlde bir sınırı AÇIKLAYAN yorum ("`quit()` çağırmaz",
# "SQL sarmalanmaz: SELECT TOP ...") o sınırı İHLAL ediyormuş gibi görünür.
# `parse()` + `deparse()` yorumları kesin biçimde düşürür ve dize sabitlerini
# olduğu gibi korur; satır bazlı `#` kesme ise dize içindeki `#` üzerinde
# yanlış çalışır.
.pkgc_code_only <- function(path) {
  ifadeler <- tryCatch(parse(path, encoding = "UTF-8", keep.source = FALSE),
                       error = function(e) NULL)
  if (is.null(ifadeler)) return("")
  paste(unlist(lapply(ifadeler, function(e) deparse(e, width.cutoff = 500L))),
        collapse = "\n")
}

.pkgc_root <- function() resolve_repo_root_for_tests()

.pkgc_tool_files <- function() {
  kok <- .pkgc_root()
  list.files(file.path(kok, "tools", "pk"), pattern = "\\.R$", full.names = TRUE)
}

test_that("operator giris noktasi TAM olarak beklenen yoldadir", {
  kok <- .pkgc_root()
  giris <- file.path(kok, "tools", "pk", "generate_query_meta.R")

  expect_true(file.exists(giris))

  metin <- .pkgc_read_bytes(giris)
  # Master plan §5.1'deki operatör komutları bu yola bağlıdır.
  expect_true(grepl("MERGEN_PK_META_MODE", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pkg_meta_run_inventory", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("uretici dosyalari parse edilebilir", {
  for (dosya in .pkgc_tool_files()) {
    expect_silent(parse(dosya, encoding = "UTF-8"))
  }
})

test_that("uretici source(...) guvenlidir: quit() cagirmaz", {
  for (dosya in .pkgc_tool_files()) {
    metin <- .pkgc_code_only(dosya)
    # `quit()` bir RStudio oturumunu kapatır; depo kuralı gereği
    # `source(...)` ile çalıştırılan operatör betikleri bunu ASLA yapmaz.
    expect_false(
      grepl("quit(", metin, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s icinde quit() bulundu", basename(dosya))
    )
    expect_false(
      grepl("q(save", metin, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s icinde q(save=...) bulundu", basename(dosya))
    )
  }
})

test_that("uretici CALISMA ZAMANI kaynak manifestine EKLENMEZ", {
  kok <- .pkgc_root()
  manifest <- .pkgc_read_bytes(file.path(kok, "R", "config_source_manifest.R"))

  # Üretici yalnızca operatör aracıdır; uygulama açılışında yüklenmemelidir.
  expect_false(grepl("tools/pk/", manifest, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("generate_query_meta", manifest, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("helpers_meta_generator", manifest, fixed = TRUE, useBytes = TRUE))
})

test_that("uretilen ve operator-yerel dosyalar gitignore'ludur", {
  kok <- .pkgc_root()
  gitignore <- .pkgc_read_bytes(file.path(kok, ".gitignore"))

  for (giris in c(
    "R/library_query_meta_local.R",     # üretici çıktısı
    "R/library_query_aliases_local.R",  # operatör alias'ları
    "artifacts/pk-meta/"                # sağlık raporu artefaktları
  )) {
    expect_true(
      grepl(giris, gitignore, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s .gitignore icinde degil", giris)
    )
  }
})

test_that("uretimden turetilen dosyalar depoda IZLENMEZ", {
  kok <- .pkgc_root()

  # Bulut checkout'unda yoklukları NORMALDİR (renv.lock ile aynı provenans
  # kalıbı). Buradaki sözleşme "izlenmiyor olmalı"dır, "var olmalı" değil.
  for (dosya in c("R/library_query_meta_local.R", "R/library_query_aliases_local.R")) {
    izlenen <- suppressWarnings(system2(
      "git", c("-C", shQuote(kok), "ls-files", "--error-unmatch", shQuote(dosya)),
      stdout = FALSE, stderr = FALSE
    ))
    expect_false(
      identical(izlenen, 0L),
      info = sprintf("%s Git tarafindan IZLENIYOR; uretimden turetilmis veri sizabilir", dosya)
    )
  }
})

test_that("yasakli yazma hedefleri sozlesmede tanimlidir", {
  kok <- .pkgc_root()
  metin <- .pkgc_read_bytes(file.path(kok, "tools", "pk", "helpers_meta_generator_config.R"))

  # Bunlar yorum değil, çalışma zamanında uygulanan bir kapıdır
  # (pkgr_assert_writable_target); listeden bir giriş düşerse üretici o dosyaya
  # yazabilir hâle gelir.
  for (yasak in c(
    "R/library_query_aliases_local.R",
    "R/library_query_meta.R",
    "R/library_query_meta_auto.R",
    "R/library_queries.R"
  )) {
    expect_true(
      grepl(yasak, metin, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s yasakli hedef listesinde degil", yasak)
    )
  }

  expect_true(grepl("PKG_META_OUTPUT_FILE", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("R/library_query_meta_local.R", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("uretici izlenen metadata dosyalarina YAZMA cagrisi icermez", {
  yazma_desenleri <- c("writeLines(", "writeBin(", "file.copy(", "file.rename(",
                       "cat(file", "saveRDS(")

  # İki dosya alias yolunu MEŞRU olarak taşır ve bu taramadan muaftır:
  #   * config : yasaklı hedef listesini TANIMLAR (kapının kendisi),
  #   * render : ÜRETİLEN dosyanın başlığına "alias dosyasına dokunulmaz"
  #              notunu yazar (operatörün okuyacağı çıktı metni).
  # Bu ikisinde yolun geçmesi sınırı ihlal etmez, sınırı KURAR/BELGELER.
  muaf <- c("helpers_meta_generator_config.R", "helpers_meta_generator_render.R")

  for (dosya in .pkgc_tool_files()) {
    metin <- .pkgc_code_only(dosya)
    if (!any(vapply(yazma_desenleri, function(d) {
      grepl(d, metin, fixed = TRUE, useBytes = TRUE)
    }, logical(1)))) next

    # Yazma yapan tek dosya render katmanıdır ve hedefi kapıdan geçirir.
    if (identical(basename(dosya), "helpers_meta_generator_render.R")) {
      expect_true(grepl("pkgr_assert_writable_target", metin, fixed = TRUE, useBytes = TRUE))
    }

    if (!(basename(dosya) %in% muaf)) {
      expect_false(
        grepl("R/library_query_aliases_local.R", metin, fixed = TRUE, useBytes = TRUE),
        info = sprintf("%s alias dosyasi yolunu iceriyor", basename(dosya))
      )
    }
  }
})

test_that("render katmani alias yolunu YALNIZCA aciklama metninde tasir", {
  kok <- .pkgc_root()
  metin <- .pkgc_code_only(file.path(kok, "tools", "pk", "helpers_meta_generator_render.R"))

  # Yol yalnızca ÜRETİLEN dosyanın başlık metnini kuran fonksiyonda geçmelidir;
  # bir yazma çağrısının hedefi olarak DEĞİL.
  expect_true(grepl("pkgr_render_local_meta_file", metin, fixed = TRUE, useBytes = TRUE))
  expect_false(
    grepl("writeBin(charToRaw(enc2utf8(text)), file(\"R/library_query_aliases_local.R",
          metin, fixed = TRUE, useBytes = TRUE)
  )
})

test_that("uretici SALT-OKUNUR kapisini kullanir ve veri degistiren ifade calistirmaz", {
  kok <- .pkgc_root()
  metin <- .pkgc_code_only(file.path(kok, "tools", "pk", "helpers_meta_generator_run.R"))

  # Üretimin kullandığı AYNI sınıflandırıcı; ayrı bir kapı YAZILMAZ.
  expect_true(grepl("pk_sql_classify_readonly", metin, fixed = TRUE, useBytes = TRUE))

  # Veri değiştiren DBI çağrıları üretici içinde bulunmamalıdır.
  for (yasak in c("dbExecute(", "dbWriteTable(", "dbRemoveTable(", "dbCreateTable(",
                  "dbAppendTable(", "sqlAppendTable(")) {
    expect_false(
      grepl(yasak, metin, fixed = TRUE, useBytes = TRUE),
      info = sprintf("uretici %s cagrisi iceriyor", yasak)
    )
  }
})

test_that("ornekleme SQL metnini DEGISTIRMEZ", {
  kok <- .pkgc_root()
  metin <- .pkgc_code_only(file.path(kok, "tools", "pk", "helpers_meta_generator_run.R"))

  # SQL sarmalamak (SELECT TOP n FROM (...)) hem üretim sorgularını bozar
  # (ORDER BY / CTE / OPTION), hem de salt-okunur kapısından GEÇEN metin ile
  # ÇALIŞAN metni ayırır. Sınırlama imleçten N satır çekerek yapılır.
  expect_true(grepl("dbFetch(", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("dbClearResult(", metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("SELECT TOP", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("uretici ANLAMSAL alan uretmedigini sozlesmede belgeler", {
  kok <- .pkgc_root()
  metin <- .pkgc_code_only(file.path(kok, "tools", "pk", "helpers_meta_generator_run.R"))

  # `pkgn_build_local_entry` yalnızca yapısal alanlar yazar; anlamsal alanların
  # üretilmediği davranış testiyle de kanıtlanır (bkz. behavior dosyası).
  expect_true(grepl("pkgn_build_local_entry", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("result_schema", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("column_meta", metin, fixed = TRUE, useBytes = TRUE))
})
