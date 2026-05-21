# ==============================================================================
# Dosya Yolu: tests/testthat/test-character-personas-contract.R
# Açıklama: Modern AI persona sistemi sözleşmesini doğrular. Eski mitolojik
#           karakterlerin (mergen, ulgen, kayra, erlik, umay) yeni persona'lara
#           (emre, selin, deniz, can, ipek) tam geçişini ve normalize_character_id
#           migrasyon sınırını test eder.
# ==============================================================================

# İzole testthat::test_file(...) koşumunda da çalışabilmek için config'i yükle.
.personas_repo_root <- resolve_repo_root_for_tests()
if (!exists("get_characters_data", mode = "function")) {
  source(
    file.path(.personas_repo_root, "R", "config_characters.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

# Yeni persona kimlikleri ve eski mitolojik kimlikler
.new_persona_ids <- c("emre", "selin", "deniz", "can", "ipek")
.old_character_ids <- c("mergen", "ulgen", "kayra", "erlik", "umay")

# JS/metin dosyalarını Windows VM güvenli biçimde okumak için ham bayt okuyucu
.read_file_bytes_safe <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
  if (is.na(txt)) txt <- rawToChar(raw_bytes)
  txt
}

# --- normalize_character_id() ---

test_that("normalize_character_id eski mitolojik kimlikleri yeni persona'lara çevirir", {
  expect_identical(normalize_character_id("mergen"), "emre")
  expect_identical(normalize_character_id("ulgen"), "selin")
  expect_identical(normalize_character_id("ülgen"), "selin")
  expect_identical(normalize_character_id("kayra"), "deniz")
  expect_identical(normalize_character_id("erlik"), "can")
  expect_identical(normalize_character_id("umay"), "ipek")
  expect_identical(normalize_character_id("umay_ana"), "ipek")
  expect_identical(normalize_character_id("umay ana"), "ipek")
})

test_that("normalize_character_id ASCII büyük/küçük harf ve boşluk varyantlarını çözer", {
  # Yalnızca ASCII varyantlar test edilir; Türkçe İ/ı küçültme locale'e bağlıdır
  expect_identical(normalize_character_id("MERGEN"), "emre")
  expect_identical(normalize_character_id("  Kayra  "), "deniz")
  expect_identical(normalize_character_id("Erlik"), "can")
})

test_that("normalize_character_id yeni kimlikleri olduğu gibi döndürür", {
  for (id in .new_persona_ids) {
    expect_identical(normalize_character_id(id), id)
  }
})

test_that("normalize_character_id geçersiz/boş/NULL değerleri emre'ye düşürür", {
  expect_identical(normalize_character_id(NULL), "emre")
  expect_identical(normalize_character_id(""), "emre")
  expect_identical(normalize_character_id("   "), "emre")
  expect_identical(normalize_character_id(NA), "emre")
  expect_identical(normalize_character_id(NA_character_), "emre")
  expect_identical(normalize_character_id("bilinmeyen_karakter"), "emre")
  expect_identical(normalize_character_id(character(0)), "emre")
})

# --- get_characters_data() ---

test_that("get_characters_data varsayılan persona olarak emre'yi döndürür", {
  chars <- get_characters_data()
  expect_identical(chars$default_style, "emre")
})

test_that("get_characters_data tam olarak beş yeni persona içerir", {
  chars <- get_characters_data()
  ids <- vapply(chars$styles, function(x) x$id, character(1))

  expect_length(chars$styles, 5L)
  expect_identical(sort(ids), sort(.new_persona_ids))
})

test_that("get_characters_data hiçbir eski mitolojik kimlik içermez", {
  chars <- get_characters_data()
  ids <- vapply(chars$styles, function(x) x$id, character(1))

  for (old_id in .old_character_ids) {
    expect_false(old_id %in% ids)
  }
  expect_false("umay_ana" %in% ids)
})

test_that("her persona uygulamanın beklediği tüm alanlara sahiptir", {
  required_fields <- c(
    "id", "label", "full_name", "display_name", "subtitle",
    "avatar", "image", "accent", "accent_hover", "accent_active",
    "selection_card_tr", "lore_tr", "style_tr", "profile_metrics",
    "signature_moves", "system_prompt_en", "parameters", "tts_voice",
    "video_key", "music_key"
  )

  chars <- get_characters_data()
  for (persona in chars$styles) {
    for (field in required_fields) {
      expect_true(
        field %in% names(persona),
        info = paste0("Persona '", persona$id, "' '", field, "' alanını içermeli")
      )
    }
    # Metin alanları boş olmamalı
    expect_true(nzchar(persona$label))
    expect_true(nzchar(persona$full_name))
    expect_true(nzchar(persona$display_name))
    expect_true(nzchar(persona$lore_tr))
    # video_key ve music_key kimlikle aynı olmalı
    expect_identical(persona$video_key, persona$id)
    expect_identical(persona$music_key, persona$id)
  }
})

test_that("persona lore metinleri mitolojik çerçeve içermez", {
  chars <- get_characters_data()
  forbidden <- c("mitoloj", "Altay", "tanrı", "şaman", "okçu", "destan")

  for (persona in chars$styles) {
    lore_lower <- tolower(persona$lore_tr)
    for (term in forbidden) {
      expect_false(
        grepl(tolower(term), lore_lower, fixed = TRUE),
        info = paste0("Persona '", persona$id, "' lore metni '", term, "' içermemeli")
      )
    }
  }
})

test_that("Emre Onat varsayılan persona kimliği ve etiketlerini taşır", {
  emre <- get_character_record("emre")
  expect_identical(emre$id, "emre")
  expect_identical(emre$full_name, "Emre Onat")
  expect_identical(emre$display_name, "EMRE ONAT")
  expect_identical(emre$subtitle, "Ana Asistan")
})

# --- get_character_record() ---

test_that("get_character_record eski kimlikleri normalleştirerek çözer", {
  expect_identical(get_character_record("mergen")$id, "emre")
  expect_identical(get_character_record("ulgen")$id, "selin")
  expect_identical(get_character_record("kayra")$id, "deniz")
  expect_identical(get_character_record("erlik")$id, "can")
  expect_identical(get_character_record("umay_ana")$id, "ipek")
})

test_that("get_character_record geçersiz kimlik için emre döndürür", {
  expect_identical(get_character_record(NULL)$id, "emre")
  expect_identical(get_character_record("yok")$id, "emre")
})

# --- get_character_asset_paths() ---

test_that("get_character_asset_paths yeni dizin yapısını kullanır", {
  for (id in .new_persona_ids) {
    paths <- get_character_asset_paths(id)
    expect_identical(paths$id, id)
    expect_identical(paths$avatar, paste0("characters/avatar/", id, "/avatar.png"))
    expect_identical(paths$image, paste0("characters/resim/", id, "/portrait.png"))
    expect_identical(paths$video_dir, file.path("characters", "video", id))
    expect_identical(paths$music_dir, file.path("Karakter", id))
  }
})

test_that("get_character_asset_paths eski kimliği yeni yola taşır", {
  paths <- get_character_asset_paths("kayra")
  expect_identical(paths$id, "deniz")
  expect_identical(paths$video_dir, file.path("characters", "video", "deniz"))
})

# --- Dizin yapısı ---

test_that("yeni persona varlık dizinleri mevcut, eskileri kaldırılmış", {
  for (id in .new_persona_ids) {
    for (t in c("intro", "loop", "select")) {
      expect_true(
        dir.exists(file.path(.personas_repo_root, "www", "characters", "video", id, t)),
        info = paste0("www/characters/video/", id, "/", t, " mevcut olmalı")
      )
    }
    expect_true(dir.exists(file.path(.personas_repo_root, "www", "music", "Karakter", id)))
    expect_true(dir.exists(file.path(.personas_repo_root, "www", "assets", "bilge_yolac", "worlds", id)))
    expect_true(dir.exists(file.path(.personas_repo_root, "www", "assets", "bilge_yolac", "projectiles", id)))
  }

  for (old_id in .old_character_ids) {
    expect_false(
      dir.exists(file.path(.personas_repo_root, "www", "characters", "video", old_id)),
      info = paste0("Eski video klasörü www/characters/video/", old_id, " kaldırılmış olmalı")
    )
    expect_false(dir.exists(file.path(.personas_repo_root, "www", "music", "Karakter", old_id)))
  }
})

# --- JavaScript statik sözleşmeleri ---

test_that("explore_character_step.js varsayılan persona olarak emre kullanır", {
  js_path <- file.path(.personas_repo_root, "www", "js", "explore_character_step.js")
  js <- .read_file_bytes_safe(js_path)
  expect_true(grepl("_selectedCharId = 'emre'", js, fixed = TRUE))
})

test_that("Bilge Yolaç oyun dosyaları yalnızca yeni persona kimliklerini kullanır", {
  game_files <- c(
    "bilge_yolac_karakterler.js",
    "bilge_yolac_cephanelik.js",
    "bilge_yolac_varliklar.js",
    "bilge_yolac_motor.js",
    "bilge_yolac_dunya.js",
    "bilge_yolac_seviye.js",
    "bilge_yolac_dusmanlar.js",
    "bilge_yolac_efektler.js"
  )

  # Kelime sınırı kullanılır; aksi halde "erlik", "rehberlik" gibi Türkçe
  # kelimelerin içinde yanlış eşleşir.
  for (fname in game_files) {
    js <- .read_file_bytes_safe(file.path(.personas_repo_root, "www", "js", fname))
    for (old_id in .old_character_ids) {
      expect_false(
        grepl(paste0("\\b", old_id, "\\b"), js, perl = TRUE),
        info = paste0(fname, " dosyası eski kimlik '", old_id, "' içermemeli")
      )
    }
    expect_false(
      grepl("umay_ana", js, fixed = TRUE),
      info = paste0(fname, " dosyası eski 'umay_ana' kimliğini içermemeli")
    )
  }
})

test_that("Bilge Yolaç oyuncu profilleri ve persona tanımları yeni kimlikleri taşır", {
  karakterler <- .read_file_bytes_safe(
    file.path(.personas_repo_root, "www", "js", "bilge_yolac_karakterler.js")
  )
  expect_true(grepl('"emre", "selin", "deniz", "can", "ipek"', karakterler, fixed = TRUE))

  cephanelik <- .read_file_bytes_safe(
    file.path(.personas_repo_root, "www", "js", "bilge_yolac_cephanelik.js")
  )
  for (id in .new_persona_ids) {
    expect_true(
      grepl(paste0(id, ":"), cephanelik, fixed = TRUE),
      info = paste0("OYUNCU_PROFILLERI '", id, "' profilini içermeli")
    )
  }
  expect_true(grepl("OYUNCU_PROFILLERI.emre", cephanelik, fixed = TRUE))
})

test_that("claude_code pixel persona verisi yeni kimlikleri kullanır", {
  pixel_js <- .read_file_bytes_safe(
    file.path(.personas_repo_root, "www", "js", "claude_code_pixel_chars.js")
  )
  for (id in .new_persona_ids) {
    expect_true(grepl(paste0(id, ":"), pixel_js, fixed = TRUE))
  }
  for (old_id in .old_character_ids) {
    expect_false(grepl(paste0(old_id, ":"), pixel_js, fixed = TRUE))
  }
})

# --- Dokümantasyon ---

test_that("README mitolojik karakter çerçevesini içermez", {
  readme <- .read_file_bytes_safe(file.path(.personas_repo_root, "README.md"))
  expect_false(grepl("Altay mitoloji", readme, fixed = TRUE))
  expect_false(grepl("mitolojik temadan beslenir", readme, fixed = TRUE))
  expect_true(grepl("Emre Onat", readme, fixed = TRUE))
  expect_true(grepl("İpek Duru", readme, fixed = TRUE))
})
