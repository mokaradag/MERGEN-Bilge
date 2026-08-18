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

# AYRIŞTIRILMIŞ ifade ağacındaki HER çağrı başını topla.
#
# Metin taraması `q()`, `q("no")`, `q(runLast = FALSE)` gibi biçimleri kaçırır;
# oysa hepsi `quit()` ile AYNI şeyi yapar ve operatörün RStudio oturumunu
# kapatır. Çağrı başını ayrıştırılmış ağaçtan okumak bu sınıfın tamamını kapar.
# `f(x[, 1])` gibi biçimlerde bir argüman BOŞ SEMBOLDÜR; onu bir fonksiyona
# geçirmek "argument is missing" hatası verir. Boş sembol NULL'a indirgenir.
.pkgc_arg_at <- function(x, i) {
  # BOŞ ARGÜMAN, DEĞER BİR YEREL DEĞİŞKENE BAĞLANMADAN saptanır.
  #
  # `missing()` BELGELENMİŞ olarak yalnızca BİÇİMSEL ARGÜMANLAR içindir; bir
  # yerel değişken üzerinde çalışması R'nin iç temsiline bağlı bir yan etkidir.
  # Öte yandan boş sembolü bir değişkene bağlayıp SONRA incelemek de olmaz:
  # `is.symbol(oge)` değeri zorlar ve "argument is missing" hatası verir.
  #
  # `identical(x[[i]], quote(expr = ))` ifadesi ikisini de kapar: ara bağlama
  # YAPILMAZ, dolayısıyla ne belgesiz `missing()` davranışına ne de zorlamaya
  # ihtiyaç kalır.
  if (isTRUE(tryCatch(identical(x[[i]], quote(expr = )), error = function(e) FALSE))) {
    return(NULL)
  }
  tryCatch(x[[i]], error = function(e) NULL)
}

.pkgc_call_heads <- function(path) {
  ifadeler <- tryCatch(parse(path, encoding = "UTF-8", keep.source = FALSE),
                       error = function(e) NULL)
  if (is.null(ifadeler)) return(character(0))

  basliklar <- character(0)
  gez <- function(x) {
    if (is.call(x)) {
      bas <- x[[1]]
      if (is.name(bas)) basliklar <<- c(basliklar, as.character(bas))
      for (i in seq_along(x)) gez(.pkgc_arg_at(x, i))
    } else if (is.pairlist(x) || is.list(x)) {
      for (i in seq_along(x)) gez(.pkgc_arg_at(x, i))
    }
  }

  for (ifade in ifadeler) gez(ifade)
  unique(basliklar)
}

test_that("uretici source(...) guvenlidir: quit()/q() cagirmaz", {
  for (dosya in .pkgc_tool_files()) {
    basliklar <- .pkgc_call_heads(dosya)
    # `quit()` bir RStudio oturumunu kapatır; depo kuralı gereği
    # `source(...)` ile çalıştırılan operatör betikleri bunu ASLA yapmaz.
    expect_false(
      "quit" %in% basliklar,
      info = sprintf("%s icinde quit() bulundu", basename(dosya))
    )
    expect_false(
      "q" %in% basliklar,
      info = sprintf("%s icinde q(...) bulundu", basename(dosya))
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

  # ÖNCE Git'in gerçekten çalışabildiği KANITLANIR. Bu güvenlik/provenans
  # sözleşmesi Git yokken ya da kaynak bir çalışma ağacı değilken SKIP edilmez:
  # kontrolün yapılmadığı durum BAŞARI değildir.
  if (!nzchar(Sys.which("git"))) {
    fail("git kullanilamiyor; izlenme/provenans sozlesmesi dogrulanamadi")
  }

  calisma_agaci <- suppressWarnings(system2(
    "git", c("-C", shQuote(kok), "rev-parse", "--is-inside-work-tree"),
    stdout = TRUE, stderr = TRUE
  ))
  if (!identical(trimws(paste(calisma_agaci, collapse = "")), "true")) {
    fail("depo koku bir Git calisma agaci degil; izlenme/provenans sozlesmesi dogrulanamadi")
  }

  # `git ls-files --error-unmatch` için 0=IZLENIYOR, 1=eslesme yok. 128 gibi
  # başka bir durum Git'in kontrolü yapamadığını gösterir ve BAŞARI sayılmaz.
  for (dosya in c("R/library_query_meta_local.R", "R/library_query_aliases_local.R")) {
    izlenen <- suppressWarnings(system2(
      "git", c("-C", shQuote(kok), "ls-files", "--error-unmatch", shQuote(dosya)),
      stdout = FALSE, stderr = FALSE
    ))
    expect_identical(
      as.integer(izlenen), 1L,
      info = sprintf(
        "%s izlenmiyor diye kanitlanamadi (git ls-files durum=%s; beklenen=1)",
        dosya, as.character(izlenen)
      )
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

  # Veri değiştiren DBI çağrıları üreticinin HİÇBİR dosyasında bulunmamalıdır.
  # Tek dosyayı taramak, çağrının komşu bir yardımcıya taşınmasıyla sınırı
  # sessizce açardı.
  for (dosya in .pkgc_tool_files()) {
    kod <- .pkgc_code_only(dosya)
    for (yasak in c("dbExecute(", "dbWriteTable(", "dbRemoveTable(", "dbCreateTable(",
                    "dbAppendTable(", "sqlAppendTable(")) {
      expect_false(
        grepl(yasak, kod, fixed = TRUE, useBytes = TRUE),
        info = sprintf("%s icinde %s cagrisi var", basename(dosya), yasak)
      )
    }
  }
})

test_that("tek izinli EXEC uretimin UNICODE PARAMETRE sarmalayicisidir", {
  kok <- .pkgc_root()

  for (dosya in .pkgc_tool_files()) {
    kod <- .pkgc_code_only(dosya)
    if (!grepl("sp_executesql", kod, fixed = TRUE, useBytes = TRUE)) next

    # `sp_executesql` yalnızca DB katmanında ve yalnızca üretimin de kullandığı
    # NVARCHAR(MAX) PARAMETRE yolu olarak geçebilir: kapıdan GEÇEN metin
    # PARAMETRE olarak gider, batch olarak DEĞİL.
    expect_identical(
      basename(dosya), "helpers_meta_generator_db.R",
      info = sprintf("%s icinde beklenmeyen sp_executesql", basename(dosya))
    )
    expect_true(grepl("sp_executesql", kod, fixed = TRUE, useBytes = TRUE))
    expect_true(grepl("NVARCHAR(MAX)", kod, fixed = TRUE, useBytes = TRUE))
  }
})

test_that("ornekleme SQL metnini DEGISTIRMEZ", {
  kok <- .pkgc_root()
  db_metin <- .pkgc_code_only(file.path(kok, "tools", "pk", "helpers_meta_generator_db.R"))

  # SQL sarmalamak (SELECT TOP n FROM (...)) hem üretim sorgularını bozar
  # (ORDER BY / CTE / OPTION), hem de salt-okunur kapısından GEÇEN metin ile
  # ÇALIŞAN metni ayırır. Sınırlama imleçten N satır çekerek yapılır.
  expect_true(grepl("dbFetch(", db_metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("dbClearResult(", db_metin, fixed = TRUE, useBytes = TRUE))

  for (dosya in .pkgc_tool_files()) {
    expect_false(
      grepl("SELECT TOP", .pkgc_code_only(dosya), fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s SQL sarmalama izi iceriyor", basename(dosya))
    )
  }
})

test_that("giris noktasi TUM yardimcilari yukler", {
  kok <- .pkgc_root()
  metin <- .pkgc_read_bytes(file.path(kok, "tools", "pk", "generate_query_meta.R"))

  yardimcilar <- setdiff(basename(.pkgc_tool_files()), "generate_query_meta.R")
  expect_gt(length(yardimcilar), 0L)

  # Yardımcı dosya eklenip giriş noktasında source EDİLMEZSE, üretici VM'de
  # "fonksiyon bulunamadi" ile düşer; bu ancak operatör koşusunda görülürdü.
  for (dosya in yardimcilar) {
    expect_true(
      grepl(dosya, metin, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s giris noktasinda source edilmiyor", dosya)
    )
  }
})

test_that("uretici yapilandirma anahtarlari .Renviron.example icinde belgelenir", {
  kok <- .pkgc_root()
  ornek <- .pkgc_read_bytes(file.path(kok, ".Renviron.example"))

  # Depo sözleşmesi: her yeni ayar şablonda görünmelidir; aksi hâlde depodan
  # sağlanan/denetlenen bir VM bu ayarları KEŞFEDEMEZ.
  for (anahtar in c(
    "MERGEN_PK_META_MODE", "MERGEN_PK_META_SAMPLE_ROWS",
    "MERGEN_PK_META_HIGH_CARD_MIN", "MERGEN_PK_META_SQL_TIMEOUT_SEC",
    "MERGEN_PK_META_MAX_RESULT_MB", "MERGEN_PK_META_RESUME"
  )) {
    expect_true(
      grepl(anahtar, ornek, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s .Renviron.example icinde yok", anahtar)
    )
  }
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
