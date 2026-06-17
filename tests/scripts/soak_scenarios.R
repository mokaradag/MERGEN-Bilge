# ==============================================================================
# Dosya Yolu: tests/scripts/soak_scenarios.R
# Aciklama:
#   Soak yuk senaryolari: sohbet promptlari (Turkce, markdown, kod, tablo, uzun),
#   anahtar-yonlendirme matrisi ve hata-enjeksiyon durum listesi. Promptlar
#   takma-ad/case-id ile temsil edilir; TAM prompt artifact'a yazilmaz.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok). Calisma zamani
#   Turkce promptlar \u kacislariyla uretilir (parser-guvenli).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Sohbet senaryo katalogu. Her senaryo: id, kategori, prompt, stream, agirlik.
# Promptlar bilerek Turkce ozel karakterler, markdown, kod ve tablo iceriklerini
# kapsar (DB/encoding/streaming yollarini zorlamak icin).
soak_scenario_catalog <- function() {
  list(
    list(id = "chat_short", category = "chat", stream = FALSE, weight = 25,
         prompt = "Merhaba, bug\u00fcn hava nas\u0131l? K\u0131sa yan\u0131t ver."),
    list(id = "chat_turkish", category = "turkish", stream = FALSE, weight = 20,
         prompt = "T\u00fcrkiye'nin ba\u015fkenti neresidir? \u00c7\u011f\u0131\u0130\u00f6\u015f\u00fc karakterleriyle a\u00e7\u0131kla."),
    list(id = "chat_code", category = "code", stream = TRUE, weight = 15,
         prompt = "R dilinde iki say\u0131y\u0131 toplayan k\u0131sa bir fonksiyon yaz."),
    list(id = "chat_markdown", category = "markdown", stream = TRUE, weight = 12,
         prompt = "Yapay zeka hakk\u0131nda madde i\u015faretli k\u0131sa bir \u00f6zet haz\u0131rla."),
    list(id = "chat_table", category = "table", stream = FALSE, weight = 10,
         prompt = "\u00dc\u00e7 \u015fehir i\u00e7in k\u00fc\u00e7\u00fck bir n\u00fcfus tablosu olu\u015ftur."),
    list(id = "chat_medium", category = "chat", stream = FALSE, weight = 10,
         prompt = paste(
           "A\u015fa\u011f\u0131daki konuyu orta uzunlukta a\u00e7\u0131kla:",
           "kurumsal bir uygulamada \u00f6nbellekleme neden \u00f6nemlidir?"
         )),
    list(id = "chat_stream", category = "chat", stream = TRUE, weight = 5,
         prompt = "Streaming yan\u0131t testi: l\u00fctfen birka\u00e7 c\u00fcmlelik bir paragraf yaz."),
    list(id = "chat_long", category = "long", stream = TRUE, weight = 3,
         prompt = paste(rep(
           "Bu uzun bir istektir ve modelin uzun ba\u011flam\u0131 i\u015flemesini test eder.", 6L
         ), collapse = " "))
  )
}

# Agirlikli rastgele senaryo secimi.
soak_pick_scenario <- function(catalog = soak_scenario_catalog()) {
  weights <- vapply(catalog, function(s) as.numeric(s$weight %||% 1), numeric(1))
  idx <- sample.int(length(catalog), 1, prob = weights / sum(weights))
  catalog[[idx]]
}

# Bir senaryo icin OpenAI-uyumlu sohbet govdesi (JSON metni).
soak_build_chat_body <- function(scenario, model = "soak-fake-model") {
  body <- list(
    model = model,
    messages = list(
      list(role = "system", content = "Sen yardimci bir soak test asistanisin."),
      list(role = "user", content = scenario$prompt %||% "merhaba")
    ),
    stream = isTRUE(scenario$stream),
    temperature = 0.4,
    max_tokens = 512L
  )
  as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
}

# Hata-davranis dogrulamasi icin zorlanacak durum listesi (Deliverable 5F).
soak_failure_probe_cases <- function() {
  c("normal", "slow", "timeout", "http500", "http429", "malformed", "empty",
    "interrupted", "long")
}

# Anahtar-yonlendirme politika matrisi (in-process exercise; Deliverable 5C).
# Her satir: etiket + politika env durumu + beklenen kaynak.
soak_key_routing_matrix <- function() {
  list(
    list(label = "personal_key_present",
         allow_default = TRUE, require_personal = FALSE,
         has_personal = TRUE, expected = "personal"),
    list(label = "no_personal_default_allowed",
         allow_default = TRUE, require_personal = FALSE,
         has_personal = FALSE, expected = "default"),
    list(label = "no_personal_default_disabled",
         allow_default = FALSE, require_personal = FALSE,
         has_personal = FALSE, expected = "missing"),
    list(label = "require_personal_no_personal",
         allow_default = TRUE, require_personal = TRUE,
         has_personal = FALSE, expected = "missing"),
    list(label = "personal_with_require_personal",
         allow_default = FALSE, require_personal = TRUE,
         has_personal = TRUE, expected = "personal")
  )
}

# Yukleme dogrulama senaryolari (in-process exercise; Deliverable 5E).
# Her satir: etiket + dosya adi + beklenen kabul (ok) durumu.
soak_upload_cases <- function() {
  list(
    list(label = "valid_pdf", filename = "rapor.pdf", expect_ok = TRUE),
    list(label = "valid_turkish",
         filename = "T\u00fcrk\u00e7e_\u00e7al\u0131\u015fma_\u00f6zeti_\u0130stanbul.pdf", expect_ok = TRUE),
    list(label = "valid_spaces", filename = "yil sonu raporu (2026).xlsx", expect_ok = TRUE),
    list(label = "traversal", filename = "../gizli.pdf", expect_ok = FALSE),
    list(label = "bad_ext", filename = "zararli.exe", expect_ok = FALSE),
    list(label = "subdir_slash", filename = "klasor/dosya.pdf", expect_ok = FALSE)
  )
}
