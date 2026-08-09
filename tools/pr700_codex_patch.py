from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(path, old, new):
    text = read(path)
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one old block, found {count}")
    write(path, text.replace(old, new, 1))


# P2: prior-query seeding stays inside the configured recall_n budget.
p = "R/helpers_pk_query_selection_ai.R"
text = read(p)
new_seed = '''#' Geçiş A adaylarını, ÖNCEKİ kararlı sorgu kimliğiyle tohumla (§5.2)
#'
#' Eksiltili takip sorularında ("peki 2024 için?") soru metninde artık hiçbir
#' sorgu-taşıyıcı terim yoktur; Geçiş A doğru sorguyu bulamaz. Önceki kararlı
#' kimlik bu nedenle SON aday kümesi kurulmadan önce başa tohumlanır.
#'
#' `recall_n` Geçiş B'nin SERT aday tavanıdır. Önceki kimlik taze recall'da
#' yoksa onun için bir yuva ayrılır; kalan yuvalar Geçiş A sırasından doldurulur.
#' Böylece takip bağlamı korunurken istem/çıktı bütçesi recall_n+1'e büyümez.
pk_select_seed_candidates <- function(recalled_ids, prior_query_id, cfg) {
  aday <- as.character(recalled_ids)
  aday <- unique(aday[!is.na(aday) & nzchar(aday)])
  sinir <- suppressWarnings(as.integer(cfg$recall_n)[1])
  if (!length(sinir) || is.na(sinir) || sinir < 1L) return(character(0))

  if (is.null(prior_query_id) || !length(prior_query_id) ||
      is.na(prior_query_id[1]) || !nzchar(trimws(as.character(prior_query_id)[1]))) {
    return(utils::head(aday, sinir))
  }

  onceki <- trimws(as.character(prior_query_id)[1])
  utils::head(unique(c(onceki, aday)), sinir)
}

'''
if new_seed not in text:
    text, n = re.subn(
        r"#' Geçiş A adaylarını, ÖNCEKİ kararlı sorgu kimliğiyle tohumla \(§5\.2\).*?(?=#' Kullanıcı SUNULAN)",
        new_seed,
        text,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise SystemExit("helpers_pk_query_selection_ai.R: seed block mismatch")
    write(p, text)

# P2: isolated module load includes the extracted v1 AI selector.
p = "R/module_proje_kaynak_analizi.R"
text = read(p)
selector_entry = '''  list(
    functions = c("find_best_query_with_ai", "find_multiple_queries_with_ai"),
    path = file.path("R", "helpers_pk_analysis_ai_selector.R")
  ),
'''
if selector_entry not in text:
    anchor = '''  # Faz 5 (§5.2) iki geçişli seçim zinciri.'''
    if text.count(anchor) != 1:
        raise SystemExit("module_proje_kaynak_analizi.R: helper anchor mismatch")
    text = text.replace(anchor, selector_entry + anchor, 1)
    write(p, text)

# P2: confidence and margin gates constrain different quantities.
replace_once(
    ".Renviron.example",
    '''#   Tepe aday ile ikinci aday arasındaki asgari fark. Altında kalırsa yakın
#   beraberlik sayılır ve yine sorulur. MIN_CONFIDENCE + MIN_MARGIN toplamı
#   100'ü aşarsa hiçbir aday geçemez; bu yapılandırma AÇIK hata verir.
# MERGEN_PK_SELECT_MIN_MARGIN=15''',
    '''#   Tepe aday ile ikinci aday arasındaki asgari fark. Altında kalırsa yakın
#   beraberlik sayılır ve yine sorulur. MIN_CONFIDENCE ile MIN_MARGIN farklı
#   nicelikleri sınırlar; toplamlarının 100'ü aşması geçersiz DEĞİLDİR. Her iki
#   kapının da 0 olması otomatik seçimi korumasız bırakacağı için reddedilir.
# MERGEN_PK_SELECT_MIN_MARGIN=15''',
)

# P1: v2 Deep Thinking uses the gated multi-query selector instead of forcing one query.
p = "R/helpers_deep_analysis.R"
text = read(p)
new_deep = '''  # Faz 5 motor sınırı (§5.2 / §10): `MERGEN_PK_ENGINE=v2` iken Derin Düşünme de
  # aynı iki geçişli güven/marj/yetenek kapılarından geçer. Ek sorgular yalnızca
  # Geçiş B'nin kararlı-kimlikli ve bağımsız metadata/yetenek kontrollerini geçen
  # alternatiflerinden alınır; legacy konum-kimlikli çoklu seçici v2'de çağrılmaz.
  pk_v2_secim <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
    isTRUE(pk_engine_is_v2()) &&
    exists("pk_select_queries_v2", mode = "function", inherits = TRUE)

  v2_secim_sonucu <- NULL
  if (pk_v2_secim) {
    v2_secim_sonucu <- pk_select_queries_v2(
      user_prompt, query_library, chat_history,
      session = session, stop_check = stop_check, max_queries = 5L
    )
    selected_queries <- v2_secim_sonucu$queries %||% list()
  } else {
    selected_queries <- find_multiple_queries_with_ai(
      user_prompt, query_library, session, max_queries = 5
    )
  }

  if (is.null(selected_queries) || length(selected_queries) == 0) {
    cat("[DEEP_ANALYSIS] Tekil secime dusuluyor.\\n")
    single <- if (pk_v2_secim && is.list(v2_secim_sonucu)) {
      v2_secim_sonucu$primary
    } else {
      select_smart_query(
        user_prompt, query_library, chat_history,
        session = session, stop_check = stop_check
      )
    }

    if (is.list(single) && is.null(single$id) && !is.null(single$refusal_message)) {
      pk_observe_deep(list(
        query_name = "Derin analiz", filter_status = "not_reached",
        filters = list(), outcome = "Reddedildi"
      ))
      return(as.character(single$refusal_message)[1])
    }

    if (!is.null(single) && !is.null(single$id)) {
      selected_queries <- list(single)
    } else {
      pk_observe_deep(list(
        query_name = "Derin analiz",
        filter_status = "not_reached",
        filters = list(),
        outcome = "EslesmeYok"
      ))
      return("\\U0001F914 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. Lütfen sorunuzu farklı kelimelerle deneyin.")
    }
  }

'''
if new_deep not in text:
    start = text.index('  # Faz 5 motor sınırı (§5.2 / §10):')
    end = text.index('  cat(sprintf("[DEEP_ANALYSIS] %d sorgu işlenecek.', start)
    text = text[:start] + new_deep + text[end:]

commit_block = '''  if (pk_v2_secim && length(selected_queries) > 0L &&
      exists("pk_select_commit_selection", mode = "function", inherits = TRUE)) {
    try(pk_select_commit_selection(selected_queries[[1]], session), silent = TRUE)
  }

'''
if commit_block not in text:
    anchor = "  query_results <- list()\n"
    if text.count(anchor) != 1:
        raise SystemExit("helpers_deep_analysis.R: execution anchor mismatch")
    text = text.replace(anchor, commit_block + anchor, 1)
write(p, text)

# Remove compatibility-only shims from apply now the reviewed source lines own the fixes.
p = "R/helpers_pk_query_selection_apply.R"
text = read(p)
text = re.sub(
    r'\n# İZOLE `module_proje_kaynak_analizi\.R` yüklemesinde.*?\nrm\(\.pk_v1_selector_path\)\n',
    '\n', text, count=1, flags=re.S,
)
text = re.sub(
    r"\n# Geçiş A'dan gelen taze adaylar.*?\n}\n\n#' Karardan v1 uyumlu",
    "\n#' Karardan v1 uyumlu", text, count=1, flags=re.S,
)
marker = "\n# Derin analiz dosyası bu helper'dan ÖNCE yüklenir."
if marker in text:
    text = text.split(marker, 1)[0].rstrip() + "\n"
write(p, text)

# Contract tests: prior query consumes one slot when absent from fresh recall.
p = "tests/testthat/test-pk-query-selection-contract.R"
text = read(p)
old_tests = re.compile(
    r'test_that\("eksiltili takipte önceki kimlik KIRPMADAN ÖNCE tohumlanır".*?(?=test_that\("tohumlanan kimlik TEKİLLEŞTİRİLİR)',
    re.S,
)
new_tests = '''test_that("eksiltili takipte önceki kimlik SON recall_n kümesine tohumlanır", {
  cfg <- .pk_sel_cfg(recall_n = 3L)
  adaylar <- pk_select_seed_candidates(c("q002", "q003", "q004"), "q001", cfg)

  expect_identical(adaylar, c("q001", "q002", "q003"))
  expect_equal(length(adaylar), cfg$recall_n)
  expect_false("q004" %in% adaylar)
})

test_that("tohum için ayrılan yuva recall_n bütçesini büyütmez", {
  cfg <- .pk_sel_cfg(recall_n = 3L)
  adaylar <- pk_select_seed_candidates(c("q002", "q003", "q004"), "q001", cfg)

  expect_identical(adaylar, c("q001", "q002", "q003"))
  expect_equal(length(adaylar), 3L)
  expect_equal(length(pk_select_seed_candidates(c("q001", "q002", "q003", "q004"), NULL, cfg)), 3L)
})

'''
if new_tests not in text:
    text, n = old_tests.subn(new_tests, text, count=1)
    if n != 1:
        raise SystemExit("test-pk-query-selection-contract.R: seed tests mismatch")

old = '.pk_sel_pass_b(id = "q001", candidate_ids = c("q001", "q002", "q003", "q004"))'
new = '.pk_sel_pass_b(id = "q001", candidate_ids = c("q001", "q002", "q003"))'
if old in text:
    text = text.replace(old, new, 1)
write(p, text)

# Five reviewed findings must all have a concrete marker after patching.
checks = {
    "R/helpers_pk_query_selection_ai.R": ["utils::head(unique(c(onceki, aday)), sinir)"],
    "R/module_proje_kaynak_analizi.R": ["helpers_pk_analysis_ai_selector.R"],
    ".Renviron.example": ["toplamlarının 100'ü aşması geçersiz DEĞİLDİR"],
    "R/helpers_deep_analysis.R": ["pk_select_queries_v2(", "pk_select_commit_selection(selected_queries[[1]], session)"],
    "R/helpers_pk_query_selection_session.R": ["history_signatures", "intersect(imzalar, onceki)"],
}
for path, needles in checks.items():
    body = read(path)
    for needle in needles:
        if needle not in body:
            raise SystemExit(f"{path}: missing regression marker {needle}")
