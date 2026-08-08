# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_prompt.R
# Açıklama: Faz 5 (§5.2) — iki geçişli sorgu seçiminin YAPILANDIRMASI ve
#           İSTEM YÜKÜ (payload) kurucuları.
#
#           Geçiş A (recall): TÜM kütüphane, sorgu başına TEK kompakt satır.
#           Geçiş B (precision): yalnızca çözümlenmiş adaylar, TAM ayrıntı.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# LLM çağrısı `helpers_pk_query_selection_ai.R` içindedir; buradaki her şey
# deterministik metin kurulumudur ve testlerde uç nokta olmadan doğrulanabilir.
#
# KARARLI KİMLİK SÖZLEŞMESİ (D13): her iki geçiş de `q042` gibi KARARLI `id`
# alanını taşır. Liste KONUMU asla gönderilmez ve asla geri okunmaz; böylece
# `R/library_queries.R` içinde sıra değişmesi hiçbir istemin anlamını
# değiştirmez.
# ==============================================================================

.PK_SELECT_CONFIG_KEYS <- c(
  "MERGEN_PK_SELECT_TIMEOUT_SEC",
  "MERGEN_PK_SELECT_RECALL_N",
  "MERGEN_PK_SELECT_MIN_CONFIDENCE",
  "MERGEN_PK_SELECT_MIN_MARGIN",
  "MERGEN_PK_SELECT_DISAGREE_PENALTY",
  "MERGEN_PK_SELECT_DESC_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_N",
  "MERGEN_PK_SELECT_HISTORY_TURNS"
)

# Yapılandırma alan adı -> anahtar eşlemesi. Tek kaynak: hem çözümleme hem de
# dışarıdan verilen nesnenin yeniden doğrulanması bunu kullanır.
.PK_SELECT_FIELD_MAP <- c(
  timeout_sec       = "MERGEN_PK_SELECT_TIMEOUT_SEC",
  recall_n          = "MERGEN_PK_SELECT_RECALL_N",
  min_confidence    = "MERGEN_PK_SELECT_MIN_CONFIDENCE",
  min_margin        = "MERGEN_PK_SELECT_MIN_MARGIN",
  disagree_penalty  = "MERGEN_PK_SELECT_DISAGREE_PENALTY",
  desc_chars        = "MERGEN_PK_SELECT_DESC_CHARS",
  sample_chars      = "MERGEN_PK_SELECT_SAMPLE_CHARS",
  sample_n          = "MERGEN_PK_SELECT_SAMPLE_N",
  history_turns     = "MERGEN_PK_SELECT_HISTORY_TURNS"
)

#' Seçim yapılandırmasını KAPALI BAŞARISIZ biçimde çöz (§5.2 / §9)
#'
#' `pk_config_resolve()` geçersiz bir kaynağı SESSİZCE atlar ve varsayılana
#' düşer. Seçim eşikleri için bu kabul edilemez: `MERGEN_PK_SELECT_RECALL_N=1`
#' yazan bir operatör, marj kapısını devre dışı bıraktığını sanmadan
#' varsayılan 5 ile çalışmaya devam ederdi. Bu yüzden `pk_config_probe()` ile
#' ATLANAN kaynak tespit edilir ve geçersiz kaynak otomatik seçimi kapatır
#' (Faz 4 `pk_resolve_thresholds()` deseninin aynısı).
#'
#' @return `valid`, `errors` ve çözümlenmiş alanları taşıyan liste.
pk_select_config <- function(query_meta = NULL) {
  degerler <- list()
  hatalar <- character(0)

  for (anahtar in .PK_SELECT_CONFIG_KEYS) {
    sonda <- tryCatch(
      pk_config_probe(anahtar, query_meta = query_meta),
      error = function(e) NULL
    )

    if (is.null(sonda)) {
      hatalar <- c(hatalar, sprintf("%s çözümlenemedi.", anahtar))
      next
    }

    if (length(sonda$invalid_sources)) {
      hatalar <- c(hatalar, sprintf(
        "%s geçersiz bir değer taşıyor (kaynak: %s); sessizce varsayılana düşülmedi.",
        anahtar, paste(sonda$invalid_sources, collapse = ", ")
      ))
    }

    degerler[[anahtar]] <- sonda$value
  }

  ham <- list()
  for (alan in names(.PK_SELECT_FIELD_MAP)) {
    ham[[alan]] <- degerler[[.PK_SELECT_FIELD_MAP[[alan]]]]
  }

  cfg <- pk_select_normalize_config(ham)
  cfg$errors <- unique(c(hatalar, cfg$errors))
  cfg$valid <- !length(cfg$errors)
  cfg
}

#' Dışarıdan verilen seçim yapılandırmasını NORMALLEŞTİR ve DOĞRULA
#'
#' Çağıranın `valid = TRUE` iddiasına GÜVENİLMEZ (Faz 4 incelemesinin
#' `thresholds=` bulgusu). Alan varlığı, tipi, tam sayılığı ve aralığı burada
#' YENİDEN denetlenir; `pk_config_spec` sınırları tek kaynaktır.
pk_select_normalize_config <- function(x) {
  hatalar <- character(0)
  cikti <- list()

  for (alan in names(.PK_SELECT_FIELD_MAP)) {
    anahtar <- .PK_SELECT_FIELD_MAP[[alan]]
    spec <- pk_config_spec[[anahtar]]
    deger <- if (is.list(x) && !is.null(x[[alan]])) x[[alan]] else NULL

    if (is.null(deger) || length(deger) != 1L || is.na(deger[1]) ||
        !is.numeric(deger[1]) || !is.finite(deger[1]) ||
        deger[1] != as.integer(deger[1])) {
      hatalar <- c(hatalar, sprintf("%s tek bir tam sayı olmalıdır.", anahtar))
      next
    }

    deger <- as.integer(deger[1])

    if (!is.null(spec$min) && deger < as.integer(spec$min)) {
      hatalar <- c(hatalar, sprintf(
        "%s en az %d olmalıdır (verilen: %d).", anahtar, as.integer(spec$min), deger
      ))
      next
    }
    if (!is.null(spec$max) && deger > as.integer(spec$max)) {
      hatalar <- c(hatalar, sprintf(
        "%s en fazla %d olmalıdır (verilen: %d).", anahtar, as.integer(spec$max), deger
      ))
      next
    }

    cikti[[alan]] <- deger
  }

  # İlişki denetimi: tek tek geçerli iki değer BİRLİKTE tutarsız olabilir.
  # Asgari güven ile marj toplamı 100'ü aşarsa hiçbir aday çifti kapıyı
  # geçemez; bu, sessiz "hep sor" davranışı yerine AÇIK yapılandırma hatasıdır.
  if (!is.null(cikti$min_confidence) && !is.null(cikti$min_margin) &&
      (cikti$min_confidence + cikti$min_margin) > 100L) {
    hatalar <- c(hatalar, sprintf(
      paste0(
        "MERGEN_PK_SELECT_MIN_CONFIDENCE (%d) + MERGEN_PK_SELECT_MIN_MARGIN (%d) ",
        "100'ü aşıyor; bu yapılandırmada hiçbir aday otomatik seçilemez."
      ),
      cikti$min_confidence, cikti$min_margin
    ))
  }

  cikti$errors <- hatalar
  cikti$valid <- !length(hatalar)
  cikti
}

#' Metni deterministik biçimde kırp
#'
#' Kırpma karakter tabanlıdır ve kırpıldığı AÇIKÇA işaretlenir; sessiz kayıp
#' yoktur. `substr()` karakter tabanlı çalıştığı için Türkçe çok baytlı
#' karakterler ortasından bölünmez.
.pk_select_clip <- function(text, budget) {
  if (is.null(text) || !length(text)) return("")

  # NA ÖNCE düşürülür: `paste(NA_character_)` düz metin "NA" üretir ve bu
  # değer Geçiş A satırına sorgunun ADI/AÇIKLAMASI gibi girerdi (ölçüldü).
  # Eksik alan İÇERİK değil YOKLUK demektir.
  ham <- as.character(text)
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return("")

  metin <- trimws(paste(ham, collapse = " "))
  metin <- gsub("[[:space:]]+", " ", metin, perl = TRUE)
  if (!nzchar(metin)) return("")

  budget <- as.integer(budget)[1]
  if (is.na(budget) || budget < 1L) return("")
  if (nchar(metin) <= budget) return(metin)

  paste0(substr(metin, 1L, max(budget - 1L, 1L)), "…")
}

#' Satır içi ayraç ve satır sonu temizliği
#'
#' Geçiş A yükü SATIR TABANLIDIR; içeriğe kaçak `|` veya `\n` girmesi satır
#' yapısını bozar ve modelin kimlikleri yanlış eşlemesine yol açar.
.pk_select_inline <- function(text) {
  # `as.character(character(0))[1]` NA verir ve `%||%` bunu YAKALAMAZ (yalnızca
  # NULL denetler); sonuç Geçiş A satırına düz "NA" olarak sızardı (ölçüldü).
  ham <- as.character(text)
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return("")

  metin <- gsub("[\r\n]+", " ", ham[1], perl = TRUE)
  metin <- gsub("|", "/", metin, fixed = TRUE)
  gsub("[[:space:]]+", " ", trimws(metin), perl = TRUE)
}

.pk_select_meta_chr <- function(meta, alan) {
  deger <- if (is.list(meta)) meta[[alan]] else NULL
  if (is.null(deger)) return(character(0))
  if (is.list(deger)) deger <- unlist(deger, use.names = FALSE)
  deger <- as.character(deger)
  deger[!is.na(deger) & nzchar(trimws(deger))]
}

#' Sorgunun KARARLI kimliğini oku (D13)
#'
#' Kimlik yoksa `NA` döner; konum kimliği UYDURULMAZ.
pk_select_query_id <- function(query) {
  if (!is.list(query)) return(NA_character_)
  kimlik <- query$id
  if (is.null(kimlik) || !length(kimlik) || is.na(kimlik[1])) return(NA_character_)
  kimlik <- trimws(as.character(kimlik)[1])
  if (!nzchar(kimlik)) return(NA_character_)
  kimlik
}

#' Geçiş A için tek sorgu satırı (§5.2)
#'
#' Biçim: `id | name | short description | keywords | sample_questions[1:N]`
#'
#' Alanların HİÇBİRİ küresel olarak düşürülmez. Kullanıcının terminolojisi çoğu
#' zaman YALNIZCA açıklamada, anahtar kelimelerde veya örnek soruda geçer;
#' Geçiş A onu göremezse Geçiş B o adayı asla geri getiremez (§5.2 açık uyarısı).
pk_select_pass_a_line <- function(query, cfg) {
  kimlik <- pk_select_query_id(query)
  if (is.na(kimlik)) return(NA_character_)

  meta <- if (is.list(query$meta)) query$meta else list()

  ad <- .pk_select_inline(query$name %||% "")
  aciklama <- .pk_select_inline(.pk_select_clip(query$description %||% "", cfg$desc_chars))

  anahtarlar <- .pk_select_meta_chr(meta, "keywords")
  anahtar_metin <- .pk_select_inline(paste(anahtarlar, collapse = ", "))

  ornekler <- .pk_select_meta_chr(meta, "sample_questions")
  if (length(ornekler) > cfg$sample_n) ornekler <- ornekler[seq_len(cfg$sample_n)]
  ornekler <- vapply(
    ornekler,
    function(s) .pk_select_inline(.pk_select_clip(s, cfg$sample_chars)),
    character(1), USE.NAMES = FALSE
  )
  ornek_metin <- paste(ornekler, collapse = " ; ")

  sprintf(
    "%s | %s | %s | %s | %s",
    kimlik, ad, aciklama, anahtar_metin, ornek_metin
  )
}

#' Geçiş A kütüphane yükü
#'
#' Kararlı kimliği olmayan sorgular DIŞARIDA bırakılır ve `skipped` alanında
#' AÇIKÇA raporlanır; konum kimliğine düşülmez (D13).
pk_select_pass_a_payload <- function(library, cfg) {
  if (!is.list(library) || !length(library)) {
    return(list(text = "", ids = character(0), skipped = character(0)))
  }

  satirlar <- vapply(library, function(q) pk_select_pass_a_line(q, cfg), character(1))
  kimlikler <- vapply(library, pk_select_query_id, character(1))

  gecerli <- !is.na(satirlar) & !is.na(kimlikler)
  atlanan <- vapply(which(!gecerli), function(i) {
    ad <- if (is.list(library[[i]])) as.character(library[[i]]$name %||% "")[1] else ""
    if (is.na(ad) || !nzchar(ad)) sprintf("#%d", i) else ad
  }, character(1))

  list(
    text = paste(satirlar[gecerli], collapse = "\n"),
    ids = kimlikler[gecerli],
    skipped = atlanan
  )
}

#' Sınırlı takip bağlamı zarfı (§5.2)
#'
#' Son N konuşma turu + hâlâ kütüphanede var olan ÖNCEKİ kararlı sorgu kimliği.
#' Kimlik artık kütüphanede yoksa taşınmaz: silinmiş bir sorguyu tohumlamak,
#' Geçiş B'nin var olmayan bir adayı doğrulamasına yol açardı.
pk_select_follow_up_context <- function(chat_history, prior_query_id, library_ids, cfg) {
  turlar <- character(0)

  if (is.list(chat_history) && length(chat_history) && cfg$history_turns > 0L) {
    son <- utils::tail(chat_history, cfg$history_turns)
    turlar <- vapply(son, function(m) {
      if (!is.list(m)) return(NA_character_)
      rol <- as.character(m$role %||% m$type %||% "")[1]
      icerik <- as.character(m$content %||% "")[1]
      if (is.na(icerik) || !nzchar(trimws(icerik))) return(NA_character_)
      sprintf("%s: %s", if (is.na(rol) || !nzchar(rol)) "user" else rol,
              .pk_select_inline(.pk_select_clip(icerik, cfg$sample_chars)))
    }, character(1))
    turlar <- turlar[!is.na(turlar)]
  }

  onceki <- NA_character_
  if (!is.null(prior_query_id) && length(prior_query_id) && !is.na(prior_query_id[1])) {
    aday <- trimws(as.character(prior_query_id)[1])
    if (nzchar(aday) && aday %in% library_ids) onceki <- aday
  }

  list(turns = turlar, prior_query_id = onceki)
}

#' Takip bağlamını istem metnine çevir
.pk_select_context_text <- function(context) {
  if (!length(context$turns) && is.na(context$prior_query_id)) return("")

  parcalar <- character(0)
  if (length(context$turns)) {
    parcalar <- c(parcalar, "### ONCEKI KONUSMA (son turlar):", context$turns)
  }
  if (!is.na(context$prior_query_id)) {
    parcalar <- c(parcalar, sprintf(
      "### ONCEKI SECILEN SORGU KIMLIGI: %s", context$prior_query_id
    ))
    parcalar <- c(parcalar, paste0(
      "Kullanicinin sorusu eksiltili bir takip sorusuysa (ornegin 'peki 2024 icin?'), ",
      "bu kimlik guclu bir adaydir; ancak yeni bir konu acildiysa dikkate alma."
    ))
  }

  paste0(paste(parcalar, collapse = "\n"), "\n\n")
}

#' Geçiş A mesajları (recall — TÜM kütüphane)
#'
#' `cfg$recall_n` doğrudan metne yazılır; hiçbir yerde sabit 5 YOKTUR.
pk_select_pass_a_messages <- function(user_prompt, payload, context, cfg,
                                      repair_error = NULL) {
  onarim <- if (!is.null(repair_error) && nzchar(trimws(as.character(repair_error)[1]))) {
    paste0(
      "### ONCEKI DENEMEN GECERSIZDI - DUZELT:\n",
      .pk_select_inline(repair_error), "\n",
      "Ayni cevabi tekrarlama; yukaridaki hatayi gider.\n\n"
    )
  } else {
    ""
  }

  sistem <- paste0(
    "Sen bir Veritabani Sorgu Yonlendiricisisin. Kullanicinin Turkce sorusuna ",
    "CEVAP VEREBILECEK sorgu adaylarini bulacaksin.\n\n",

    .pk_select_context_text(context),

    "### MEVCUT SORGULAR (bicim: id | isim | aciklama | anahtar kelimeler | ornek sorular):\n",
    payload$text, "\n\n",

    "### GOREV:\n",
    sprintf("Tam olarak %d adet aday sorgu KIMLIGI dondur.\n", cfg$recall_n),
    "Kimlikler yukaridaki listede AYNEN gecen kararli kimliklerdir (ornegin q042).\n",
    "Sira ONEMLIDIR: en olasi aday basta olsun.\n",
    sprintf(
      "Listede %d'den az sorgu varsa mevcut olanlarin TAMAMINI dondur.\n",
      cfg$recall_n
    ),
    "Genis dusun: bu asamada AMAC dogru sorguyu KACIRMAMAKTIR, secmek degil.\n\n",

    onarim,

    "### ZORUNLU JSON CIKTISI:\n",
    "{\"candidates\": [\"q042\", \"q108\"]}\n\n",
    "SADECE JSON dondur, baska hicbir sey yazma."
  )

  list(
    list(role = "system", content = sistem),
    list(role = "user", content = as.character(user_prompt)[1])
  )
}

#' Geçiş B için tek aday bloğu (TAM ayrıntı)
.pk_select_pass_b_block <- function(query, cfg) {
  kimlik <- pk_select_query_id(query)
  if (is.na(kimlik)) return(NA_character_)

  meta <- if (is.list(query$meta)) query$meta else list()

  satirlar <- c(
    sprintf("--- SORGU %s ---", kimlik),
    sprintf("ISIM: %s", .pk_select_inline(query$name %||% "")),
    sprintf("ACIKLAMA: %s", .pk_select_inline(query$description %||% ""))
  )

  ornekler <- .pk_select_meta_chr(meta, "sample_questions")
  if (length(ornekler)) {
    satirlar <- c(satirlar, sprintf(
      "ORNEK SORULAR: %s",
      .pk_select_inline(paste(ornekler, collapse = " ; "))
    ))
  }

  niyetler <- .pk_select_meta_chr(meta, "intents")
  if (length(niyetler)) {
    satirlar <- c(satirlar, sprintf("NIYETLER: %s", paste(niyetler, collapse = ", ")))
  }

  uygun_degil <- .pk_select_meta_chr(meta, "not_for")
  if (length(uygun_degil)) {
    satirlar <- c(satirlar, sprintf("BU SORGU SUNLAR ICIN DEGILDIR: %s",
                                    paste(uygun_degil, collapse = ", ")))
  }

  sutunlar <- meta$column_meta
  if (is.list(sutunlar) && length(sutunlar) && !is.null(names(sutunlar))) {
    tanimlar <- vapply(names(sutunlar), function(ad) {
      cm <- sutunlar[[ad]]
      if (!is.list(cm)) return(NA_character_)
      etiket <- as.character(cm$label %||% ad)[1]
      yetenek <- as.character(cm$capability %||% "")[1]
      if (is.na(yetenek) || !nzchar(yetenek)) {
        .pk_select_inline(etiket)
      } else {
        .pk_select_inline(sprintf("%s [%s]", etiket, yetenek))
      }
    }, character(1), USE.NAMES = FALSE)
    tanimlar <- tanimlar[!is.na(tanimlar)]
    if (length(tanimlar)) {
      satirlar <- c(satirlar, sprintf("SUTUNLAR: %s", paste(tanimlar, collapse = " ; ")))
    }
  }

  paste(satirlar, collapse = "\n")
}

#' Geçiş B mesajları (precision — YALNIZCA çözümlenmiş adaylar)
#'
#' `candidates` Geçiş A'nın çözülmüş sorgu nesneleridir; sayıları
#' `cfg$recall_n` ile SINIRLIDIR ve bu değer her iki geçişte de aynıdır.
pk_select_pass_b_messages <- function(user_prompt, candidates, context, cfg,
                                      capability_ids = character(0),
                                      repair_error = NULL) {
  bloklar <- vapply(candidates, function(q) .pk_select_pass_b_block(q, cfg), character(1))
  bloklar <- bloklar[!is.na(bloklar)]

  yetenek_metni <- if (length(capability_ids)) {
    paste0(
      "### IZINLI YETENEK KIMLIKLERI (requirements icinde YALNIZCA bunlar kullanilabilir):\n",
      paste(capability_ids, collapse = ", "), "\n",
      "Listede OLMAYAN bir kimlik uydurma; emin degilsen ilgili alani bos dizi birak.\n\n"
    )
  } else {
    paste0(
      "### YETENEK KIMLIKLERI:\n",
      "Bu kurulumda tanimli yetenek kimligi yoktur; requirements icindeki ",
      "measures/dates/dimensions alanlarini BOS DIZI birak.\n\n"
    )
  }

  onarim <- if (!is.null(repair_error) && nzchar(trimws(as.character(repair_error)[1]))) {
    paste0(
      "### ONCEKI DENEMEN GECERSIZDI - DUZELT:\n",
      .pk_select_inline(repair_error), "\n",
      "Ayni cevabi tekrarlama; yukaridaki hatayi gider.\n\n"
    )
  } else {
    ""
  }

  sistem <- paste0(
    "Sen bir Veritabani Sorgu Yonlendiricisisin. Asagidaki ADAYLAR arasindan ",
    "kullanicinin sorusuna en iyi cevabi verecek TEK sorguyu sec.\n\n",

    .pk_select_context_text(context),

    "### ADAYLAR:\n",
    paste(bloklar, collapse = "\n\n"), "\n\n",

    yetenek_metni,
    onarim,

    "### ZORUNLU JSON CIKTISI:\n",
    "{\"id\":\"q042\",\"confidence\":78,\"reason\":\"Kisa gerekce\",\n",
    " \"alternates\":[{\"id\":\"q108\",\"confidence\":63}],\n",
    " \"requirements\":{\"entity\":null,\"measures\":[],\"dates\":[],\"dimensions\":[],\"group_by\":null},\n",
    " \"missing_info\":null}\n\n",

    "### KURALLAR:\n",
    "1. id: YALNIZCA yukaridaki adaylardan birinin kararli kimligi.\n",
    "2. confidence: 0-100 arasi TAM SAYI. Emin degilsen DUSUK ver; ",
    "yanlis sorguyu calistirmaktansa kullaniciya sormak yeglenir.\n",
    "3. alternates: diger adaylar, HER BIRI KENDI confidence degeriyle. ",
    "Bu alan zorunludur: ikinci adayin guveni olmadan yakin beraberlik ",
    "tespit edilemez.\n",
    "4. requirements: sorunun GEREKTIRDIGI anlamsal yetenekler. Kolon adi ya da ",
    "etiket YAZMA; yalnizca izinli yetenek kimligi kullan.\n",
    "5. missing_info: cevaplamak icin eksik bilgi varsa kisa Turkce aciklama, ",
    "yoksa null.\n\n",
    "SADECE JSON dondur, baska hicbir sey yazma."
  )

  list(
    list(role = "system", content = sistem),
    list(role = "user", content = as.character(user_prompt)[1])
  )
}
