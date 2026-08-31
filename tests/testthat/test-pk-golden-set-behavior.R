# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-golden-set-behavior.R
# Açıklama: Faz 5 (§7) — TAAHHÜT EDİLEN altın küme koşum takımı (harness).
#           Tamamen çevrimdışı ve belirlenimcidir: LLM `llm_fn` ile ENJEKTE
#           edilir ve kaydedilmiş çıktıları döndürür (§7 "Offline (default
#           suite): stubbed LLM returning recorded outputs").
#
# ÖLÇÜLEN: recall@N — Geçiş A'ya giden yükün, beklenen sorguyu GÖRÜNÜR kılıp
#          kılmadığı. Bu, sözlüksel getirimin izin verilen üçüncü rolüdür
#          (altın küme tanılaması) ve KARAR VERMEZ.
#
# Bu dosya "modeli" ölçmez — model burada sahtedir. Ölçtüğü şey, doğru sorgunun
# Geçiş A penceresinde ULAŞILABİLİR olup olmadığıdır. Kaçırılan bir aday,
# Geçiş B'nin asla telafi edemeyeceği tek geri dönülmez kayıptır (§5.2).
#
# Gerçek trafikle çalışan puanlı koşum VM tarafındadır ve taahhüt EDİLMEZ.
# ==============================================================================

pk_select_source_chain_for_tests()

.pk_golden_path <- function() {
  file.path(resolve_repo_root_for_tests(), "tests", "fixtures", "pk_golden_set.json")
}

.pk_golden_load <- function() {
  jsonlite::fromJSON(.pk_golden_path(), simplifyVector = FALSE)
}

# Kaydedilmiş çıktılar SÖZLEŞMEYE UYGUN olmalıdır. Aksi hâlde altın küme,
# seçim davranışını değil ayrıştırıcı toleransını ölçer: eksik `missing_info`
# ya da `requirements` alanı, bir vakayı "doğru reddedildi" gibi gösterirken
# gerçekte cevap BOZUK olduğu için reddedilmiş olurdu.
.pk_golden_pass_a <- function(ids) {
  sprintf("{\"candidates\": [%s]}", paste(sprintf("\"%s\"", ids), collapse = ", "))
}

.pk_golden_pass_b <- function(selected, candidate_ids, confidence = 88L,
                              requirements = NULL) {
  digerleri <- setdiff(candidate_ids, selected)
  alternatifler <- paste(
    vapply(digerleri, function(k) sprintf("{\"id\":\"%s\",\"confidence\":30}", k), character(1)),
    collapse = ","
  )

  sprintf(
    paste0("{\"id\":\"%s\",\"confidence\":%d,\"reason\":\"altin kume\",",
           "\"alternates\":[%s],\"requirements\":%s,\"missing_info\":null}"),
    selected, as.integer(confidence), alternatifler,
    .pk_golden_requirements_json(requirements)
  )
}

# `requirements` TAM şemayla ve DÜZ dizilerle serileştirilir.
#
# `jsonlite::toJSON(auto_unbox = FALSE)` fixture'daki `list("x")` değerini
# `[["x"]]` yapar; iç içe dizi sözleşme dışıdır ve cevabı BOZUK yapar. Altın
# küme, ayrıştırıcı toleransını değil SEÇİM davranışını ölçmelidir.
.pk_golden_requirements_json <- function(requirements) {
  alanlar <- c("measures", "dates", "dimensions", "group_by", "unsupported")
  parcalar <- vapply(alanlar, function(alan) {
    deger <- if (is.list(requirements)) requirements[[alan]] else NULL
    deger <- as.character(unlist(deger, use.names = FALSE))
    deger <- deger[!is.na(deger) & nzchar(deger)]
    sprintf("\"%s\":[%s]", alan, paste(sprintf("\"%s\"", deger), collapse = ","))
  }, character(1), USE.NAMES = FALSE)

  varlik <- if (is.list(requirements)) requirements$entity else NULL
  varlik_json <- if (is.null(varlik) || !length(varlik)) {
    "\"entity\":null"
  } else {
    sprintf("\"entity\":\"%s\"", as.character(unlist(varlik))[1])
  }

  paste0("{", paste(c(varlik_json, parcalar), collapse = ","), "}")
}



test_that("altın küme fixture'ı vardır ve YALNIZCA sentetik veri taşır", {
  expect_true(file.exists(.pk_golden_path()))

  golden <- .pk_golden_load()
  expect_true(length(golden$cases) >= 5L)

  ham <- readBin(.pk_golden_path(), "raw", file.info(.pk_golden_path())$size)
  txt <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # §7: taahhüt edilen korpus gerçek satır sayısı taşımaz; şekil iddiası kullanır.
  expect_false(
    grepl("expected_row_count", txt, fixed = TRUE, useBytes = TRUE),
    info = "Gerçek satır sayısı taahhüt edilen fixture'a GİRMEZ (§7)."
  )

  # Her vakanın kimliği ve sorusu olmalıdır.
  for (vaka in golden$cases) {
    expect_true(nzchar(vaka$id %||% ""), info = "Her vakanın kimliği olmalıdır.")
    expect_true(nzchar(vaka$soru %||% ""), info = "Her vakanın sorusu olmalıdır.")
    expect_true("expected_selection" %in% names(vaka))
  }
})

test_that("fixture, ayırt edici terimi YALNIZCA sample_questions'ta taşıyan vaka içerir", {
  golden <- .pk_golden_load()
  ayirt <- Filter(function(v) identical(v$distinguishing_field, "sample_questions"), golden$cases)

  expect_true(
    length(ayirt) >= 1L,
    info = paste(
      "§8 Faz 5 kabul ölçütü: ayırt edici ifadesi YALNIZCA sample_questions'ta",
      "geçen en az bir vaka bulunmalıdır."
    )
  )

  # BOŞ SONUÇ ÖNCE DENETLENİR: testthat 3e'de başarısız bir beklenti gövdeyi
  # DURDURMAZ, bu yüzden `ayirt[[1]]` boş listede "subscript out of bounds"
  # gibi OPAK bir hata verir ve gerçek kabul ölçütü kaybolurdu.
  if (!length(ayirt)) return(invisible(NULL))

  # Ve bu iddia GERÇEKTEN doğru olmalıdır: terim başka alanda geçmemelidir.
  lib <- pk_select_library_index(pk_select_test_library())
  vaka <- ayirt[[1]]
  # ADI OLMAYAN KİMLİK `[[` İLE ARANMAZ: liste üzerinde `lib[["yok"]]`
  # "subscript out of bounds" FIRLATIR, `NULL` DÖNDÜRMEZ; blok aşağıdaki
  # tanılayıcı iddiaya HİÇ ulaşamıyor ve okuyucu amaçlanan mesaj yerine opak
  # indeks hatasını görüyordu.
  .hedef_kimlik <- as.character(vaka$expected_query_id %||% "")[1]
  hedef <- if (!is.na(.hedef_kimlik) && nzchar(.hedef_kimlik) &&
               .hedef_kimlik %in% names(lib)) {
    lib[[.hedef_kimlik]]
  } else {
    NULL
  }

  # EKSIK KUTUPHANE GIRDISI OPAK HATAYA DONUSMEZ: `hedef` NULL iken
  # `grepl(..., NULL)` `logical(0)` doner ve `expect_false()` amaclanan kabul
  # olcutu yerine bir UZUNLUK hatasi raporlardi (satir 117'deki bos-sonuc
  # muhafizasiyla ayni gerekce).
  expect_false(
    is.null(hedef),
    info = sprintf("Fikstur kimligi sentetik kutuphanede yok: %s",
                   vaka$expected_query_id %||% "<NA>")
  )
  if (is.null(hedef)) return(invisible(NULL))

  expect_false(grepl("ertelen", hedef$name, fixed = TRUE))
  expect_false(grepl("ertelen", hedef$description, fixed = TRUE))
  expect_false(any(grepl("ertelen", unlist(hedef$meta$keywords), fixed = TRUE)))
  expect_true(any(grepl("ertelen", unlist(hedef$meta$sample_questions), fixed = TRUE)))
})

test_that("fixture, eksiltili takip vakası içerir", {
  golden <- .pk_golden_load()
  eksiltili <- Filter(function(v) isTRUE(v$elliptical), golden$cases)

  expect_true(length(eksiltili) >= 1L)
  for (vaka in eksiltili) {
    expect_true(
      nzchar(vaka$prior_query_id %||% ""),
      info = "Eksiltili vaka, korunması gereken ÖNCEKİ kararlı kimliği taşımalıdır."
    )
  }
})

test_that("recall@N: beklenen sorgu Geçiş A YÜKÜNDE görünür kalır", {
  golden <- .pk_golden_load()
  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  ))

  payload <- pk_select_pass_a_payload(lib, cfg)
  satirlar <- strsplit(payload$text, "\n", fixed = TRUE)[[1]]
  names(satirlar) <- payload$ids

  # EN AZ BİR VAKA AYIRT EDİCİ TERİM TAŞIMALIDIR: hiçbiri taşımazsa
  # `nzchar(terim)` her turda FALSE olur, terim denetimi HİÇ koşmaz ve test
  # doğrulamadığı bir sözleşmeyi doğruluyormuş gibi geçer.
  terimli <- vapply(
    golden$cases,
    function(v) nzchar(as.character(v$distinguishing_term %||% "")[1]),
    logical(1)
  )
  expect_true(
    any(terimli),
    info = "Altin kume fiksturunde `distinguishing_term` tasiyan hic vaka yok."
  )

  kacirilan <- character(0)

  for (vaka in golden$cases) {
    beklenen <- vaka$expected_query_id
    if (is.null(beklenen)) next

    # Beklenen sorgunun satırı yükte OLMALI ve ayırt edici terimi TAŞIMALIDIR.
    if (!beklenen %in% payload$ids) {
      kacirilan <- c(kacirilan, vaka$id)
      next
    }

    # AYIRT EDICI TERIM DENETIMI DONGU ICINDE: eskiden yalnizca dongu DISINDA
    # ve YALNIZCA `q003` icin kosuyordu; ikinci bir ayirt edici alan tasiyan
    # vaka eklendiginde dongu hicbir sey denetlemeden basari raporlardi.
    # Terim FIKSTURDEN gelir, teste sabit kodlanmaz.
    terim <- vaka$distinguishing_term %||% ""
    if (nzchar(terim) &&
        !isTRUE(grepl(terim, unname(satirlar[beklenen]), fixed = TRUE))) {
      kacirilan <- c(kacirilan, paste0(vaka$id, " (terim: ", terim, ")"))
    }
  }

  expect_equal(
    kacirilan, character(0),
    info = paste(
      "Geçiş A yükü, beklenen her sorguyu içermelidir. Kaçan vakalar:",
      paste(kacirilan, collapse = ", ")
    )
  )

  # Kırpma, ayırt edici terimi YOK ETMEMELİDİR.
  # TEK KOSELI PARANTEZ: `[[` eksik adda "subscript out of bounds" firlatir ve
  # asagidaki `info` tanilamasi HIC calismaz; okuyucu amaclanan recall
  # tanilamasi yerine kapali bir hata gorurdu. `[` eksik adda `NA` doner,
  # `grepl()` FALSE olur ve iddia KENDI mesajini raporlar.
  expect_true(
    isTRUE(grepl("ertelendi", unname(satirlar["q003"]), fixed = TRUE)),
    info = paste(
      "Ayırt edici terim örnek sorudan kırpılırsa Geçiş A onu göremez ve",
      "Geçiş B geri getiremez (§5.2)."
    )
  )
})

test_that("recall@N: beklenen sorgu Geçiş A ÇIKTISINDA (ilk N aday) yer alır", {
  # Yükün İÇERMESİ yetmez: yük zaten TÜM kütüphanedir, yani bu koşul her vaka
  # için önemsiz biçimde doğrudur. Ölçülmesi gereken, `pk_select_run_pass_a()`
  # çıktısının beklenen kimliği GERÇEKTEN döndürüp döndürmediğidir.
  golden <- .pk_golden_load()
  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 2L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  ))
  payload <- pk_select_pass_a_payload(lib, cfg)

  # Kaydedilmiş recall çıktısı: sözlüksel sıralamanın ilk N kimliği. Bu, bir
  # modelin makul biçimde döndüreceği kümedir ve YENİDEN ÜRETİLEBİLİRDİR.
  index <- pk_retrieval_build_index(lib)

  for (vaka in golden$cases) {
    beklenen <- vaka$expected_query_id
    if (is.null(beklenen) || isTRUE(vaka$elliptical)) next

    ilk_n <- utils::head(pk_retrieval_score(index, vaka$soru)$query_id, cfg$recall_n)
    stub <- pk_select_stub_llm(list(.pk_golden_pass_a(ilk_n)))
    sonuc <- pk_select_run_pass_a(
      vaka$soru, payload,
      pk_select_follow_up_context(NULL, NULL, payload$ids, cfg, user_prompt = vaka$soru),
      cfg, llm_fn = stub$fn
    )

    expect_true(isTRUE(sonuc$ok), info = sprintf("Vaka %s: Geçiş A çözülemedi.", vaka$id))
    expect_equal(length(sonuc$ids), cfg$recall_n)
    # STUB'IN SAĞLAYAMAYACAĞI ÖZELLİK (PR #705 incelemesi, P3): `ilk_n` aynı
    # sözlüksel sıralamadan türetildiği için `sonuc$ids` KURULUŞ GEREĞİ
    # `head(lexical, recall_n)` ile eşitti ve blok Geçiş A'yı ÖLÇMÜYORDU.
    # Ayrıştırıcının `payload$ids` kümesine bağlı kalması stub'a bağlı DEĞİLDİR.
    expect_true(all(sonuc$ids %in% payload$ids),
                info = sprintf("Vaka %s: aday kümesi DIŞINDA kimlik.", vaka$id))
    disarida <- pk_select_run_pass_a(
      vaka$soru, payload,
      pk_select_follow_up_context(NULL, NULL, payload$ids, cfg, user_prompt = vaka$soru),
      cfg,
      llm_fn = pk_select_stub_llm(list(.pk_golden_pass_a("q_var_olmayan_kimlik")))$fn
    )
    expect_false(isTRUE(disarida$ok) && "q_var_olmayan_kimlik" %in% (disarida$ids %||% character(0)),
                 info = sprintf("Vaka %s: aday dışı kimlik REDDEDİLMELİDİR.", vaka$id))
    expect_true(
      beklenen %in% sonuc$ids,
      info = sprintf(
        "Vaka %s ('%s'): beklenen %s, ilk %d aday arasında OLMALIDIR (recall@N).",
        vaka$id, vaka$soru, beklenen, cfg$recall_n
      )
    )
  }
})

test_that("sözlüksel getirim, altın kümede beklenen sorguyu ilk-3'e taşır", {
  golden <- .pk_golden_load()
  index <- pk_retrieval_build_index(pk_select_test_library())

  # Bu SADECE tanılamadır: bozulma kipi kalitesini ölçer, karar vermez.
  # Eksiltili vaka hariç tutulur — sözlüksel sinyal orada zaten yoktur ve
  # olmaması BEKLENİR (bağlam tohumlaması bu yüzden vardır).
  for (vaka in golden$cases) {
    beklenen <- vaka$expected_query_id
    if (is.null(beklenen) || isTRUE(vaka$elliptical)) next

    siralama <- pk_retrieval_score(index, vaka$soru)
    sira <- match(beklenen, siralama$query_id)

    expect_true(
      !is.na(sira) && sira <= 3L,
      info = sprintf(
        "Vaka %s ('%s'): beklenen %s sözlüksel ilk-3'te değil (sıra: %s).",
        vaka$id, vaka$soru, beklenen, sira
      )
    )
  }
})

test_that("kapsam dışı soru için sözlüksel sinyal ZAYIFTIR", {
  golden <- .pk_golden_load()
  index <- pk_retrieval_build_index(pk_select_test_library())

  disarida <- Filter(function(v) is.null(v$expected_query_id), golden$cases)
  expect_true(length(disarida) >= 1L, info = "Kapsam dışı en az bir vaka olmalıdır.")

  for (vaka in disarida) {
    siralama <- pk_retrieval_score(index, vaka$soru)
    expect_lt(max(siralama$score), 0.35)
  }
})

test_that("uçtan uca: altın küme vakaları kaydedilmiş LLM çıktısıyla çözülür", {
  golden <- .pk_golden_load()
  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 5L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  ))

  # Kütüphanedeki TÜM kararlı kimlikler; `recall_n = 5` ve dört sorgu olduğu
  # için Geçiş A sözleşmesi "mevcut olanların TAMAMI"dır. Eksik doldurulmuş bir
  # kayıt, tam olarak geri alınamaz recall kaybı hatasını kutsardı.
  tum_kimlikler <- vapply(lib, function(q) q$id, character(1))

  dogru <- 0L
  toplam <- 0L

  for (vaka in golden$cases) {
    toplam <- toplam + 1L
    beklenen <- vaka$expected_query_id

    if (identical(vaka$expected_selection, "refuse")) {
      # Kapsam dışı: model düşük güven verir -> seçim REDDETMELİDİR. Cevap
      # SÖZLEŞMEYE UYGUNDUR; ret, bozuk ayrıştırma yüzünden değil DÜŞÜK GÜVEN
      # yüzünden gelmelidir.
      stub <- pk_select_stub_llm(list(
        .pk_golden_pass_a(tum_kimlikler),
        .pk_golden_pass_b("q001", tum_kimlikler, confidence = 12L)
      ))
      karar <- pk_select_run(vaka$soru, lib, llm_fn = stub$fn, cfg = cfg)

      expect_identical(
        karar$status, PK_SELECT_STATUS_LOW_CONFIDENCE,
        info = sprintf(
          "Vaka %s kapsam dışıdır; DÜŞÜK GÜVEN nedeniyle reddedilmelidir.", vaka$id
        )
      )
      if (identical(karar$status, PK_SELECT_STATUS_LOW_CONFIDENCE)) dogru <- dogru + 1L
      next
    }

    # Kaydedilmiş Geçiş A/B çıktıları: TAM kütüphane recall'ı ve net bir
    # kazanan. `requirements` fixture'dan gelir.
    stub <- pk_select_stub_llm(list(
      .pk_golden_pass_a(tum_kimlikler),
      .pk_golden_pass_b(beklenen, tum_kimlikler,
                        requirements = vaka$expected_requirements)
    ))

    karar <- pk_select_run(
      vaka$soru, lib,
      prior_query_id = vaka$prior_query_id %||% NULL,
      llm_fn = stub$fn, cfg = cfg
    )

    expect_identical(
      karar$status, PK_SELECT_STATUS_AUTO,
      info = sprintf("Vaka %s ('%s') otomatik seçilmeliydi.", vaka$id, vaka$soru)
    )
    expect_identical(
      karar$query_id, beklenen,
      info = sprintf("Vaka %s beklenen sorguyu seçmelidir.", vaka$id)
    )
    if (identical(karar$query_id, beklenen)) dogru <- dogru + 1L
  }

  expect_equal(
    dogru, toplam,
    info = sprintf("Altın küme doğruluğu: %d/%d", dogru, toplam)
  )
})

test_that("eksiltili vaka, önceki kimlik OLMADAN aday kümesine giremez", {
  golden <- .pk_golden_load()
  # BOŞ SONUÇ ÖNCE DENETLENİR: `[[1]]` fixture eksikken opak bir indeks hatası
  # verir ve gerçek neden ("eksiltili vaka fixture'dan DÜŞMÜŞ") kaybolur.
  eksiltililer <- Filter(function(v) isTRUE(v$elliptical), golden$cases)
  expect_true(length(eksiltililer) >= 1L,
              info = "Altın küme en az bir eksiltili vaka taşımalıdır.")
  eksiltili <- eksiltililer[[1]]

  lib <- pk_select_test_library()
  cfg <- pk_select_normalize_config(list(
    timeout_sec = 20L, recall_n = 2L, min_confidence = 50L, min_margin = 15L,
    disagree_penalty = 15L, desc_chars = 220L, sample_chars = 120L,
    sample_n = 2L, history_turns = 2L, name_chars = 120L, keyword_chars = 160L,
    history_chars = 240L, pass_b_chars = 24000L, pass_a_chars = 60000L
  ))

  # Geçiş A, eksiltili soruda beklenen sorguyu bulamaz (gerçekçi senaryo).
  gecis_a <- "{\"candidates\":[\"q003\",\"q004\"]}"

  # Önceki kimlik OLMADAN: beklenen sorgu aday kümesinde YOK.
  stub_yok <- pk_select_stub_llm(list(
    gecis_a, .pk_golden_pass_b("q003", c("q003", "q004"), confidence = 80L)
  ))
  karar_yok <- pk_select_run(eksiltili$soru, lib, llm_fn = stub_yok$fn, cfg = cfg)
  expect_false(eksiltili$expected_query_id %in% karar_yok$candidate_ids)

  # Önceki kimlik İLE: tohum, taze adayları DÜŞÜRMEDEN kümeye eklenir.
  adaylar_var <- c(eksiltili$expected_query_id, "q003", "q004")
  stub_var <- pk_select_stub_llm(list(
    gecis_a,
    .pk_golden_pass_b(eksiltili$expected_query_id, adaylar_var, confidence = 85L)
  ))
  karar_var <- pk_select_run(
    eksiltili$soru, lib,
    prior_query_id = eksiltili$prior_query_id,
    llm_fn = stub_var$fn, cfg = cfg
  )

  expect_true(eksiltili$expected_query_id %in% karar_var$candidate_ids)
  expect_identical(karar_var$query_id, eksiltili$expected_query_id)
  expect_identical(karar_var$status, PK_SELECT_STATUS_AUTO)
  # Tohum, Geçiş A'nın taze adaylarını DÜŞÜRMEZ: küme bir eleman büyüyebilir.
  expect_true(all(c("q003", "q004") %in% karar_var$candidate_ids))
})
