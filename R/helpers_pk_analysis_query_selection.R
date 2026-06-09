# R/helpers_pk_analysis_query_selection.R
#
# Proje/Kaynak Analizi "Akıllı Sorgu Seçici" sezgisel (heuristic) skorlama ve
# skor tablosu raporlama yardımcıları. Bu sorumluluk, büyük modül
# (R/module_proje_kaynak_analizi.R) içinden ayrılmıştır.
#
# Bu dosya saf/yan-etkisiz karar mantığını barındırır: prompt ile sorgu
# kütüphanesi arasındaki ilgililik skorlaması (ağırlıklar, alan anahtar kelime
# bonusları, normalizasyon ve eşik kararı). Tek izinli yan etki, konsola tanılama
# yazan print_score_table()'ın cat() çıktısıdır. Bu dosya Shiny
# observer/render/runtime, canlı DB bağlantısı veya LLM çağrısı içermez; AI tabanlı
# seçim ve oturum/cat orkestrasyonu modüldeki select_smart_query() içinde kalır.
#
# Davranış sözleşmesi: skorlama formülü (isim alt-dize +50, isim kelime eşleşmesi
# ×10, açıklama kelime eşleşmesi ×2, 7 alan bonusu +8, max'a göre %100
# normalizasyon, THRESHOLD_RAW=2 / THRESHOLD_PCT=30 eşiği) ve all_scores tablo
# yapısı (query_id, query_name, ai_score, heuristic_score, final_score) BİREBİR
# korunmalıdır.

# Skor tablosu iskeletini üretir. Hem AI dalı (ai_score doldurur) hem de heuristic
# dalı (heuristic_score/final_score doldurur) bu ortak iskeleti kullanır.
pk_init_query_score_table <- function(library) {
  all_scores <- data.frame(
    query_id = character(length(library)),
    query_name = character(length(library)),
    ai_score = numeric(length(library)),
    heuristic_score = numeric(length(library)),
    final_score = numeric(length(library)),
    stringsAsFactors = FALSE
  )

  for (i in seq_along(library)) {
    all_scores$query_id[i] <- library[[i]]$id %||% as.character(i)
    all_scores$query_name[i] <- library[[i]]$name %||% ""
    all_scores$ai_score[i] <- 0
    all_scores$heuristic_score[i] <- 0
    all_scores$final_score[i] <- 0
  }

  all_scores
}

# Tek bir sorgunun prompt'a göre ham (normalize edilmemiş) ilgililik skorunu üretir.
# `q` bir sorgu kaydı (name/description alanlı liste); `prompt_clean` küçük harfe
# çevrilmiş prompt; `prompt_words` prompt'tan türetilen (nchar > 2) kelimelerdir.
pk_score_query_relevance <- function(q, prompt_clean, prompt_words) {
  score <- 0

  desc_clean <- tolower(q$description)
  name_clean <- tolower(q$name)

  desc_words <- unlist(strsplit(desc_clean, "\\W+"))
  name_words <- unlist(strsplit(name_clean, "\\W+"))

  if (grepl(name_clean, prompt_clean, fixed = TRUE)) {
    score <- score + 50
  }

  name_matches <- sum(prompt_words %in% name_words)
  score <- score + (name_matches * 10)

  desc_matches <- sum(prompt_words %in% desc_words)
  score <- score + (desc_matches * 2)

  if (grepl("bütçe|maliyet|harcama|fiyat|tutar", prompt_clean) && grepl("bütçe|maliyet|cost|budget|tutar|fiyat", desc_clean)) score <- score + 8
  if (grepl("zaman|süre|tarih|gecikme|başlangıç|bitiş", prompt_clean) && grepl("date|start|finish|tarih|süre|gecikme", desc_clean)) score <- score + 8
  if (grepl("kaynak|adam|personel|çalışan|ekip", prompt_clean) && grepl("resource|kaynak|personel|ekip", desc_clean)) score <- score + 8
  if (grepl("aktivite|faaliyet|iş|görev", prompt_clean) && grepl("aktivite|activity|task|iş|görev", desc_clean)) score <- score + 8
  if (grepl("proje|program|portföy", prompt_clean) && grepl("proje|project|program|portföy", desc_clean)) score <- score + 8
  if (grepl("wbs|iş kırılım|kırılım", prompt_clean) && grepl("wbs|kırılım|work breakdown", desc_clean)) score <- score + 8
  if (grepl("rol|atama|görevlendirme", prompt_clean) && grepl("rol|role|atama|assignment", desc_clean)) score <- score + 8

  score
}

# Tüm kütüphane için sezgisel skorları hesaplar, max'a göre %100 normalize eder ve
# eşik kararını üretir. Geri dönen liste: doldurulmuş all_scores tablosu, en iyi
# indeks, ham/yüzde max skor ve eşik geçiş bayrağı.
pk_compute_heuristic_query_scores <- function(prompt, library) {
  all_scores <- pk_init_query_score_table(library)

  prompt_clean <- tolower(prompt)
  prompt_words <- unlist(strsplit(prompt_clean, "\\W+"))
  prompt_words <- prompt_words[nchar(prompt_words) > 2]

  scores <- sapply(seq_along(library), function(i) {
    pk_score_query_relevance(library[[i]], prompt_clean, prompt_words)
  })

  max_heuristic <- max(scores, na.rm = TRUE)
  if (max_heuristic > 0) {
    scores_normalized <- (scores / max_heuristic) * 100
  } else {
    scores_normalized <- scores
  }

  all_scores$heuristic_score <- round(scores_normalized, 1)
  all_scores$final_score <- all_scores$heuristic_score

  best_idx <- which.max(scores)
  max_score <- if (length(best_idx) > 0) scores[best_idx] else 0
  max_score_pct <- if (length(best_idx) > 0) scores_normalized[best_idx] else 0

  THRESHOLD_RAW <- 2
  THRESHOLD_PCT <- 30

  passes_threshold <- (max_score >= THRESHOLD_RAW) || (max_score_pct >= THRESHOLD_PCT)

  list(
    all_scores = all_scores,
    best_idx = best_idx,
    max_score_raw = max_score,
    max_score_pct = max_score_pct,
    passes_threshold = passes_threshold
  )
}

print_score_table <- function(scores_df) {
  scores_df <- scores_df[order(-scores_df$final_score), ]

  cat("\n")
  cat("+==============================================================================+\n")
  cat("|                        SORGU İLGİLİLİK SKORLARI                             |\n")
  cat("+==============================================================================+\n")
  cat("\n")

  max_name_len <- max(nchar(scores_df$query_name), na.rm = TRUE)
  max_name_len <- min(max_name_len, 40)

  cat(sprintf("%-6s %-*s %10s %12s %11s\n",
              "ID", max_name_len, "Sorgu Adı", "AI Skor", "Heur. Skor", "Final Skor"))
  cat(strrep("-", 6 + max_name_len + 10 + 12 + 11 + 5), "\n")

  for (i in seq_len(nrow(scores_df))) {
    row <- scores_df[i, ]
    name_display <- substr(row$query_name, 1, max_name_len)
    if (nchar(row$query_name) > max_name_len) {
      name_display <- paste0(substr(name_display, 1, max_name_len - 3), "...")
    }

    ai_str <- if (row$ai_score > 0) sprintf("%.1f%%", row$ai_score) else "-"
    heur_str <- sprintf("%.1f%%", row$heuristic_score)
    final_str <- sprintf("%.1f%%", row$final_score)

    cat(sprintf("%-6s %-*s %10s %12s %11s\n",
                row$query_id, max_name_len, name_display, ai_str, heur_str, final_str))
  }

  cat(strrep("-", 6 + max_name_len + 10 + 12 + 11 + 5), "\n")
  cat("\n")
}
