# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet-contract.R
# Açıklama: Büyük dosyaların daha da büyümesini engelleyen bakım borcu ratchet
#           sözleşmesini doğrular. Üretilen büyük veri/metadata dosyaları hariçtir.
# ==============================================================================

.read_repo_text_maintainability <- function(path) {
  # BOŞ/OKUNAMAYAN DOSYA VACUOUS GEÇİRİR: `""` döndüğünde rapor sıfır satır ve
  # sıfır fonksiyon ölçer, ratchet'in TÜM `<=` iddiaları geçer. Kısmi bir
  # checkout ya da bozuk birleştirme sonucu KULLANILAMAZ bir çalışma zamanı
  # dosyası bu yolla "bakım borcu yok" diye raporlanırdı.
  if (!file.exists(path)) {
    stop(sprintf("Kaynak dosya bulunamadı: %s", path), call. = FALSE)
  }
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", path), call. = FALSE)
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.count_functions_maintainability <- function(txt) {
  hits <- gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]]

  if (identical(hits[1], -1L)) {
    return(0L)
  }

  length(hits)
}

.normalize_path_maintainability <- function(path) {
  out <- normalizePath(path, winslash = "/", mustWork = FALSE)
  out <- gsub("\\\\", "/", out)
  out <- gsub("/+", "/", out)
  out <- sub("/+$", "", out)
  enc2utf8(out)
}

.relative_repo_path_maintainability <- function(path, repo_root) {
  repo_norm <- .normalize_path_maintainability(repo_root)
  path_norm <- .normalize_path_maintainability(path)

  if (identical(path_norm, repo_norm)) {
    return("")
  }

  prefix <- paste0(repo_norm, "/")

  if (startsWith(path_norm, prefix)) {
    return(substring(path_norm, nchar(prefix) + 1L))
  }

  # Windows/UNC edge case:
  # normalizePath() bazı ağ yollarında repo kökü ile dosya yolunu farklı
  # biçimlerde döndürebilir. Bu durumda R klasöründen itibaren göreli yol
  # üretmeye çalışıyoruz.
  r_match <- regexpr("(^|/)R/[^:]+\\.R$", path_norm, perl = TRUE)
  if (!identical(r_match[1], -1L)) {
    rel <- substring(path_norm, r_match[1])
    rel <- sub("^/", "", rel)
    return(rel)
  }

  root_files <- c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R")
  base_name <- basename(path_norm)
  if (base_name %in% root_files) {
    return(base_name)
  }

  path_norm
}

.collect_runtime_report_maintainability <- function(repo_root) {
  repo_root <- .normalize_path_maintainability(repo_root)

  runtime_paths <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(
      file.path(repo_root, "R"),
      pattern = "\\.R$",
      recursive = TRUE,
      full.names = TRUE
    )
  )

  runtime_paths <- unique(runtime_paths[file.exists(runtime_paths)])

  # KAPSAM DIŞI DOSYA HİÇ OKUNMAZ (PR #705 inceleme, P2/P3).
  #
  # Süzgeç eskiden okuma bittikten SONRA (aşağıda) uygulanıyordu.
  # `.read_repo_text_maintainability()` sıfır baytlık bir dosya için bilinçli
  # olarak `stop()` eder; yerelde üretilen (gitignore'lu) `library_query_*_local.R`
  # artefaktı yarıda kalmış bir üretimde BOŞ kalabilir ve o zaman bu sözleşmenin
  # HER İKİ testi de -- hiçbir taban aşılmamışken -- `Kaynak dosya BOŞ ya da
  # okunamıyor` ile düşüyordu (`tests/testthat.R` `stop_on_failure = TRUE`).
  # Süzgeci yola taşımak ayrıca bilgi tabanı dosyasının tamamen belleğe
  # alınmasını da önler.
  .kapsam_disi <- "(^|/)(library_queries|library_query_meta(_auto|_local)?|library_query_aliases_local)\\.R$"
  runtime_paths <- runtime_paths[!grepl(.kapsam_disi, runtime_paths, perl = TRUE)]

  rows <- lapply(runtime_paths, function(path) {
    rel_path <- .relative_repo_path_maintainability(path, repo_root)

    txt <- .read_repo_text_maintainability(path)
    split_lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

    data.frame(
      path = rel_path,
      lines = length(split_lines),
      functions = .count_functions_maintainability(txt),
      stringsAsFactors = FALSE
    )
  })

  report <- do.call(rbind, rows)

  if (is.null(report) || nrow(report) == 0L) {
    return(data.frame(
      path = character(0),
      lines = integer(0),
      functions = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  report$path <- gsub("\\\\", "/", report$path)
  report$path <- sub("^/+", "", report$path)
  report$path <- enc2utf8(report$path)

  # library_queries.R bilgi tabanı; library_query_meta*.R dosyaları ise sorgu
  # kütüphanesinin metadata katmanıdır (curated meta, tracked auto iskelet ve
  # yerelde üretilen gitignore'lu local artefakt). Üretim VM'indeki gerçek
  # kütüphane on binlerce satıra ulaşabildiği için hiçbiri ratchet kapsamına
  # alınmaz. Süzgeç OKUMA ÖNCESİNDE uygulanır (bkz. yukarıdaki `.kapsam_disi`);
  # burada yalnızca normalize edilmiş yol biçimine karşı SON bir güvence olarak
  # tekrarlanır.
  keep <- !grepl(.kapsam_disi, report$path, perl = TRUE)
  report <- report[keep, , drop = FALSE]

  report[order(report$lines, decreasing = TRUE), , drop = FALSE]
}

# NOT: module_startup_screen.R ve helpers_ai_expert.R taban değerleri, önceki
# birleştirilen PR'lardaki meşru büyüme (skip-intro nöral renk; AI Expert
# staleness + TTS parçalama) sonrası ölçülen gerçek değerlere güncellendi.
#
# PR #705 P1 incelemesi — BİLİNÇLİ taban güncellemesi:
#   * R/helpers_chat_runtime.R 523 -> 532. `block` kipinde köken doğrulaması
#     artık AKIŞTAN VE TTS'TEN ÖNCE çalışır; aksi hâlde TTS motoru HAM
#     `full_response` ile çağrılıyor ve kullanıcı hiç GÖSTERİLMEYEN sayıları
#     DUYUYORDU (söylenmiş ses geri alınamaz). Karar/metin üretimi
#     `mergen_pk_block_mode_texts()` içine ÇIKARILDI; bu dosyada kalan yalnızca
#     sonucun uygulanmasıdır. Fonksiyon sayısı 14 -> 15 (yalnızca bu delege).
#
# PR #705 inceleme takibi — BİLİNÇLİ taban güncellemesi:
#   * R/helpers_chat_runtime.R 532/14 -> 579/17 (ÖLÇÜLEN). İki neden:
#     (a) `mergen_pk_block_mode_texts()` çağrısı `tryCatch` ile sarıldı — metin
#     üretimi hata verdiğinde TÜM yanıt teslimi düşüyor ve kullanıcı hazır
#     cevabı hiç göremiyordu; (b) dönen alanlar `.cr_metin()` ile SKALER'e
#     indirgenir, çünkü çok elemanlı bir alan `if (nzchar(x))` içinde koşul
#     uzunluğu hatası fırlatıyordu. Küresel eşikler (100/100, 800+ = 0,
#     25+ fonksiyon = 0, en büyük dosya 796, en yüksek fonksiyon 24) KORUNDU.
.maintainability_baseline <- data.frame(
  path = c(
    "R/helpers_mcp_tools.R",
    "R/module_claude_code.R",
    "R/helpers_claude_code.R",
    "R/module_proje_kaynak_analizi.R",
    "R/module_file_manager.R",
    "R/module_admin_yanit_analizi.R",
    "R/module_admin_geri_bildirim.R",
    "R/module_admin_hata_analizi.R",
    "R/helpers_database.R",
    "R/module_settings_yapilandirma.R",
    "R/helpers_llm_worker.R",
    "R/helpers_claude_code_documents.R",
    "R/server_send_message.R",
    "R/config_api.R",
    "R/helpers_llm_sse.R",
    "R/config_file_store.R",
    "R/module_image_generation.R",
    "R/server_ai_expert_handlers.R",
    "R/module_startup_screen.R",
    "R/module_ai_expert.R",
    "R/helpers_claude_code_workdir_snapshot.R",
    "R/module_claude_code_workdir_snapshots.R",
    "R/server_handler_true_streaming.R",
    "R/helpers_deep_analysis.R",
    "R/helpers_ai_expert.R",
    "R/helpers_chartlab.R",
    "R/helpers_language.R",
    "ui.R",
    "R/module_chartlab.R",
    "R/helpers_chat_runtime.R",
    "R/helpers_health_checks.R",
    "R/helpers_files.R"
  ),
  baseline_lines = c(
    2378L,
    1749L,
    1672L,
    1580L,
    1496L,
    1273L,
    1247L,
    1225L,
    1099L,
    1065L,
    1027L,
    941L,
    878L,
    866L,
    858L,
    788L,
    765L,
    726L,
    740L,
    686L,
    662L,
    662L,
    707L,  # BİLİNÇLİ GÜNCELLEME: R/server_handler_true_streaming.R -- `defer_visible_text` TRUE iken boş yanıt balonu AÇILMAZ + `pk_provenance_decorate()` çağrısı tryCatch ile sarıldı (ÖLÇÜLEN 707)
    627L,
    662L,
    577L,
    572L,
    539L,
    532L,
    579L,
    385L,
    341L
  ),
  baseline_functions = c(
    99L,
    30L,
    66L,
    28L,
    50L,
    8L,
    10L,
    13L,
    38L,
    5L,
    13L,
    31L,
    17L,
    26L,
    27L,
    45L,
    22L,
    23L,
    6L,
    22L,
    31L,
    31L,
    17L,
    12L,
    23L,
    44L,
    3L,
    0L,
    20L,
    17L,
    27L,
    32L
  ),
  stringsAsFactors = FALSE
)

test_that("mevcut büyük dosyalar kontrolsüz şekilde büyümüyor", {
  repo_root <- resolve_repo_root_for_tests()
  current <- .collect_runtime_report_maintainability(repo_root)

  merged <- merge(
    .maintainability_baseline,
    current,
    by = "path",
    all.x = TRUE
  )

  # Bir dosya refactor edilip küçültülmüş/taşınmış olabilir; bu iyi bir şeydir.
  merged <- merged[!is.na(merged$lines), , drop = FALSE]

  line_limit <- merged$baseline_lines + pmax(
    25L,
    ceiling(merged$baseline_lines * 0.05)
  )

  function_limit <- merged$baseline_functions + pmax(
    3L,
    ceiling(merged$baseline_functions * 0.10)
  )

  line_violations <- merged$path[merged$lines > line_limit]
  function_violations <- merged$path[merged$functions > function_limit]

  expect_equal(
    line_violations,
    character(0),
    info = paste(
      "Satır sayısı ratchet limitini aşan dosyalar:",
      paste(line_violations, collapse = ", ")
    )
  )

  expect_equal(
    function_violations,
    character(0),
    info = paste(
      "Fonksiyon sayısı ratchet limitini aşan dosyalar:",
      paste(function_violations, collapse = ", ")
    )
  )
})

test_that("yeni büyük monolit dosya eklenmiyor", {
  repo_root <- resolve_repo_root_for_tests()
  current <- .collect_runtime_report_maintainability(repo_root)

  known_paths <- .maintainability_baseline$path
  is_new <- !(current$path %in% known_paths)
  new_paths <- current[is_new, , drop = FALSE]

  is_large <- new_paths$lines >= 800L | new_paths$functions >= 25L
  new_large_paths <- new_paths[is_large, , drop = FALSE]

  expect_equal(
    new_large_paths$path,
    character(0),
    info = paste(
      "Yeni büyük/monolit aday dosyalar:",
      paste(new_large_paths$path, collapse = ", ")
    )
  )
})