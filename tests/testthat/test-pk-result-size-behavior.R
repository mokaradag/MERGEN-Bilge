# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-result-size-behavior.R
# Açıklama: Faz 6 (§5.10) — sonuç-boyutu ön kontrolü ve YETKİ FARKINDA satır
#           tavanı planının davranış testleri. Tamamen çevrimdışı.
#
# Kanıtlanan sözleşmeler:
#   - `varchar(max)` / `varbinary(max)` / bilinmeyen tip üst sınır ÜRETMEZ ve
#     tam materyalizasyonu YETKİLENDİREMEZ.
#   - Gözlemlenen/örnek genişlikler üst sınır DEĞİLDİR: tek sınırsız sütun tüm
#     sonucu sınırsız yapar.
#   - Tavanı aşacak parça KABUL EDİLMEDEN ÖNCE durulur.
#   - Yetkilendirmeden ÖNCE çıplak TOP asla bir strateji olarak dönmez.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # Satır tavanı planı Faz 6 bölünme sonrası AYNI dosyada tutulur (boyut ve
  # tavan kararları aynı sorumluluk ailesidir).
  # Per-query son tarih override'ı `pk_config_resolve()` üzerinden çözülür.
  source(file.path(repo_root, "R", "helpers_pk_config.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_exec_context.R"),
         encoding = "UTF-8", local = globalenv())
  # Sürücü metadata YORUMU ayrı dosyadadır ve boyut matematiğinden ÖNCE gelir.
  source(file.path(repo_root, "R", "helpers_pk_result_columns.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_result_size.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("sabit genişlikli tipler üst sınır üretir", {
  expect_equal(pk_column_width_upper_bound("int"), 4)
  expect_equal(pk_column_width_upper_bound("bigint"), 8)
  expect_equal(pk_column_width_upper_bound("datetime2"), 8)
  expect_equal(pk_column_width_upper_bound("uniqueidentifier"), 36)

  # Yerelden bağımsız küçültme: Türkçe yerelde tolower("INT") noktasız "ınt"
  # üretir ve eşleşme sessizce ıskalanırdı.
  expect_equal(pk_column_width_upper_bound("INT"), 4)
  expect_equal(pk_column_width_upper_bound("BIGINT"), 8)
  expect_equal(pk_column_width_upper_bound("int(11)"), 4)
})

test_that("varchar(max) ve varbinary(max) ÜST SINIR ÜRETMEZ", {
  # SQL Server'da max_length = -1, MAX demektir.
  expect_true(is.na(pk_column_width_upper_bound("varchar", -1)))
  expect_true(is.na(pk_column_width_upper_bound("nvarchar", -1)))
  expect_true(is.na(pk_column_width_upper_bound("varbinary", -1)))

  # Uzunluk hiç beyan edilmemişse de üst sınır İDDİA EDİLMEZ.
  expect_true(is.na(pk_column_width_upper_bound("nvarchar", NA)))
  expect_true(is.na(pk_column_width_upper_bound("varchar", 0)))
  expect_true(is.na(pk_column_width_upper_bound("text", 100)))  # text zaten MAX
  expect_true(is.na(pk_column_width_upper_bound("bilinmeyen_tip", 50)))
})

test_that("beyan edilmiş uzunluk üst sınır üretir; Unicode muhafazakâr çarpanla", {
  expect_equal(pk_column_width_upper_bound("varchar", 100), 100)
  # nvarchar: UTF-8'de karakter başına 4 bayta kadar çıkabilir.
  expect_equal(pk_column_width_upper_bound("nvarchar", 100), 400)
  expect_equal(pk_column_width_upper_bound("nchar", 10), 40)
})

test_that("TEK sınırsız sütun TÜM sonucu sınırsız yapar", {
  sinirli <- pk_result_width_upper_bound(list(
    id = list(type = "int"),
    ad = list(type = "nvarchar", max_length = 50)
  ))
  expect_true(sinirli$bounded)
  expect_equal(sinirli$bytes_per_row, 4 + 200)

  sinirsiz <- pk_result_width_upper_bound(list(
    id = list(type = "int"),
    aciklama = list(type = "nvarchar", max_length = -1)
  ))
  expect_false(sinirsiz$bounded)
  expect_true(is.na(sinirsiz$bytes_per_row))
  # Sınırsız sütunu ATLAYIP kalanı toplamak bir üst sınır DEĞİL, alt sınırdır.
  expect_equal(sinirsiz$unbounded_columns, "aciklama")
})

test_that("boş sütun listesi üst sınır üretmez", {
  expect_false(pk_result_width_upper_bound(list())$bounded)
  expect_false(pk_result_width_upper_bound(NULL)$bounded)
})

test_that("ön kontrol: kanıtlanmış sınır + tavan altı -> materialize", {
  genislik <- pk_result_width_upper_bound(list(a = list(type = "int")))
  karar <- pk_result_size_preflight(
    row_count = 1000, width = genislik, max_result_mb = 512, overhead_factor = 2.5
  )
  expect_equal(karar$decision, "materialize")
  expect_equal(karar$estimated_bytes, 1000 * 4 * 2.5)
})

test_that("ön kontrol: tavanı aşan tahmin -> AÇIK REDDETME", {
  genislik <- pk_result_width_upper_bound(list(a = list(type = "nvarchar", max_length = 4000)))
  karar <- pk_result_size_preflight(
    row_count = 200000, width = genislik, max_result_mb = 512
  )
  expect_equal(karar$decision, "refuse")
  expect_equal(karar$reason, "exceeds_max_result_mb")
  expect_true(nzchar(PK_RESULT_TOO_LARGE_MESSAGE))
})

test_that("kanıtlanmış sınır YOKSA tam materyalizasyon YETKİLENDİRİLMEZ", {
  sinirsiz <- pk_result_width_upper_bound(list(a = list(type = "nvarchar", max_length = -1)))
  karar <- pk_result_size_preflight(row_count = 10, width = sinirsiz, max_result_mb = 512)

  # Küçük satır sayısı bile tam materyalizasyona izin VERMEZ; zorunlu
  # sınırlı-parça yolu kullanılır.
  expect_equal(karar$decision, "chunk_required")
  expect_equal(karar$reason, "width_not_provably_bounded")
})

test_that("satır sayısı bilinmiyorsa da sınırlı-parça yolu zorunludur", {
  genislik <- pk_result_width_upper_bound(list(a = list(type = "int")))
  karar <- pk_result_size_preflight(row_count = NA, width = genislik, max_result_mb = 512)
  expect_equal(karar$decision, "chunk_required")
  expect_equal(karar$reason, "row_count_unknown")
})

test_that("tavan çözülemezse sınırlı-parça yolu zorunludur", {
  genislik <- pk_result_width_upper_bound(list(a = list(type = "int")))
  karar <- pk_result_size_preflight(row_count = 10, width = genislik, max_result_mb = NA)
  expect_equal(karar$decision, "chunk_required")
  expect_equal(karar$reason, "ceiling_unresolved")
})

test_that("parça kararı: tavanı AŞACAK parça kabul edilmeden önce durur", {
  tavan_mb <- 1
  bir_mb <- 1024 * 1024

  kabul <- pk_chunk_accumulate_decision(0, bir_mb * 0.4, tavan_mb)
  expect_equal(kabul$action, "accept")
  expect_equal(kabul$total_bytes, bir_mb * 0.4)

  ikinci <- pk_chunk_accumulate_decision(bir_mb * 0.4, bir_mb * 0.4, tavan_mb)
  expect_equal(ikinci$action, "accept")

  # Üçüncü parça tavanı aşar: KABUL EDİLMEZ.
  ucuncu <- pk_chunk_accumulate_decision(bir_mb * 0.8, bir_mb * 0.4, tavan_mb)
  expect_equal(ucuncu$action, "abort")
  expect_equal(ucuncu$reason, "would_exceed_max_result_mb")
})

test_that("parça baytı bilinmiyorsa durulur (iyimser davranılmaz)", {
  karar <- pk_chunk_accumulate_decision(0, NA, 512)
  expect_equal(karar$action, "abort")
  expect_equal(karar$reason, "chunk_bytes_unknown")
})

# ------------------------------------------------------------------------------
# YETKİ FARKINDA SATIR TAVANI
# ------------------------------------------------------------------------------

test_that("tavan altındaki sonuç kesilmez", {
  plan <- pk_row_cap_plan(50000, authorized_rows = 1200)
  expect_equal(plan$strategy, "none")
  expect_false(plan$applies)
  expect_false(plan$truncated)
  expect_equal(pk_row_cap_truncation_note(plan), "")
})

test_that("RLS SQL'e itilmişse tavan yetkili kümeye uygulanır", {
  plan <- pk_row_cap_plan(50000, authorized_rows = 200000, rls_pushdown = TRUE)
  expect_equal(plan$strategy, "sql_cap_after_authorization")
  expect_true(plan$applies)
  expect_true(plan$truncated)
  expect_equal(plan$delivered_rows, 50000)

  not <- pk_row_cap_truncation_note(plan)
  expect_true(nzchar(not))
  expect_true(grepl("SONRA", not, fixed = TRUE))
})

test_that("RLS itilemiyorsa istatistikler TAM kümede kalır, detay kırpılır", {
  plan <- pk_row_cap_plan(
    50000, authorized_rows = 200000,
    rls_pushdown = FALSE, aggregates_over_full_set = TRUE
  )
  expect_equal(plan$strategy, "aggregate_full_cap_detail")
  expect_true(plan$truncated)

  not <- pk_row_cap_truncation_note(plan)
  # Kullanıcı kırpılmış detayı tam popülasyon sanmamalıdır: not istatistiklerin
  # hangi küme üzerinde hesaplandığını AÇIKÇA söyler.
  expect_true(grepl("TÜM satırlar", not, fixed = TRUE))
})

test_that("güvenli strateji yoksa AÇIKÇA reddedilir (çıplak TOP asla)", {
  plan <- pk_row_cap_plan(
    50000, authorized_rows = 200000,
    rls_pushdown = FALSE, aggregates_over_full_set = FALSE
  )
  expect_equal(plan$strategy, "refuse")
  expect_false(plan$applies)
  expect_true(nzchar(PK_ROW_CAP_REFUSE_MESSAGE))

  # Yetkilendirmeden ÖNCE uygulanan bir tavan hiçbir koşulda strateji DEĞİLDİR.
  expect_false("naked_top" %in% PK_ROW_CAP_STRATEGIES)
  expect_true(all(
    vapply(
      list(
        pk_row_cap_plan(10, 100, rls_pushdown = TRUE),
        pk_row_cap_plan(10, 100, rls_pushdown = FALSE, aggregates_over_full_set = TRUE),
        pk_row_cap_plan(10, 100, rls_pushdown = FALSE, aggregates_over_full_set = FALSE)
      ),
      function(p) p$strategy %in% PK_ROW_CAP_STRATEGIES,
      logical(1)
    )
  ))
})

test_that("çözülemeyen tavan KESME YAPMAZ (0 satır gibi yorumlanmaz)", {
  for (bozuk in list(NA, 0, -1, "abc", NULL)) {
    plan <- pk_row_cap_plan(bozuk, authorized_rows = 100000)
    expect_equal(plan$strategy, "none", info = sprintf("tavan=%s", paste(bozuk)))
    expect_false(plan$applies)
    expect_equal(plan$reason, "cap_unresolved")
  }
})

test_that("satır sayısı bilinmiyorsa tavan uygulanır ama kesme İDDİA EDİLMEZ", {
  plan <- pk_row_cap_plan(50000, authorized_rows = NA, rls_pushdown = TRUE)
  expect_true(plan$applies)
  expect_false(plan$truncated)
  expect_equal(pk_row_cap_truncation_note(plan), "")
})

# ------------------------------------------------------------------------------
# PER-QUERY ANALİZ SON TARİHİ OVERRIDE'I
# ------------------------------------------------------------------------------
# Dispatch anında seçilen sorgu HENÜZ bilinmediği için istek küresel bütçeyle
# dondurulur; `pk_config_resolve()` sözleşmesi ise sorgu metadata'sına EN YÜKSEK
# önceliği verir. Seçimden sonra yeniden çözmezsek `analysis_deadline_sec`
# override'ı SESSİZCE ÖLÜ bir yapılandırma olurdu.
test_that("seçilen sorgu analiz son tarihini override edebilir", {
  skip_if_not(exists("pk_set_exec_context", mode = "function"))

  baslangic <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
  eski <- options(mergen.pk.async.started_at = baslangic,
                  mergen.pk.async.deadline_at = baslangic + 300,
                  mergen.pk.analysis_deadline_sec = 300L)
  on.exit(options(eski), add = TRUE)

  # Override YOKSA hiçbir şey değişmez (varsayılan davranış bit bazında korunur).
  geri <- pk_set_exec_context(query = list(id = "q1", meta = list()), engine = "v2")
  expect_equal(as.numeric(getOption("mergen.pk.async.deadline_at")),
               as.numeric(baslangic + 300))
  geri()

  # Override VARSA mutlak son tarih AYNI başlangıçtan yeniden hesaplanır
  # (geçen süre SIFIRLANMAZ).
  geri2 <- pk_set_exec_context(
    query = list(id = "q2", meta = list(analysis_deadline_sec = 30L)),
    engine = "v2"
  )
  expect_equal(as.numeric(getOption("mergen.pk.async.deadline_at")),
               as.numeric(baslangic + 30))
  geri2()
  # Geri yükleyici ÖNCEKİ son tarihi geri getirir.
  expect_equal(as.numeric(getOption("mergen.pk.async.deadline_at")),
               as.numeric(baslangic + 300))

  # `started_at` yayınlanmamışsa override UYGULANMAZ (kapalı başarısız).
  options(mergen.pk.async.started_at = NULL)
  geri3 <- pk_set_exec_context(
    query = list(id = "q3", meta = list(analysis_deadline_sec = 30L)),
    engine = "v2"
  )
  expect_equal(as.numeric(getOption("mergen.pk.async.deadline_at")),
               as.numeric(baslangic + 300))
  geri3()
})
