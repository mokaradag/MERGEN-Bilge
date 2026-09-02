# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-provenance-footer-behavior.R
# Açıklama: Proje ve Kaynak Analizi köken (provenance) alt bilgisinin davranış
#           testleri. Tamamen saf ve çevrimdışıdır: DB, LLM, tarayıcı, ağ veya
#           gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Alt bilgi kapsamı sınırlı kullanıcı için RLS ÖNCESİ sayımı ASLA içermez.
#     (Yetki dışındaki satır sayısı da korunan bilgidir; sorgular arasında
#     sondalanarak kullanıcının göremeyeceği veri haritalanabilir.)
#   - Kapsamı tüm veri olan ADMIN kendi yetkili popülasyonunun tamamını görür.
#   - Alt bilgi sorgu kimliğini/adını, uygulanan filtreleri ve bozulmaları adlandırır.
#   - İliştirme idempotenttir ve bayat istek kimliğinde iliştirme YAPILMAZ.
# ==============================================================================

# İZOLE ORTAM: yardımcı `globalenv()` yerine özel bir ortama kaynaklanır.
#
# `globalenv()`e kaynaklamak ve `%||%` operatörünü `<<-` ile atamak, AYNI
# oturumda sonra çalışan HER test dosyası için kalıcı olur; sonraki bir dosya
# `pk_build_provenance_footer()` ya da `%||%` değerini bu SIZAN durumdan
# çözüp kendi kopyasını kaynaklamadan geçebilir ve sonuçlar DOSYA SIRASINA
# bağlı hâle gelir. Bu gruptaki diğer PK test dosyaları da özel ortam kurar.
.pk_prov_footer_env <- local({
  repo_root <- resolve_repo_root_for_tests()
  ortam <- new.env(parent = globalenv())
  assign("%||%", function(a, b) if (is.null(a)) b else a, envir = ortam)
  source(file.path(repo_root, "R", "helpers_pk_provenance.R"),
         encoding = "UTF-8", local = ortam)
  ortam
})

# Test gövdeleri yardımcıları bu ortamdan çözer (üretim adları korunur).
#
# KOPYALAR DOSYA ORTAMINA BAĞLANIR VE DOSYA BİTİNCE KALDIRILIR.
#
# `envir = environment()` AÇIKÇA verilir: kopyaların nereye yazıldığı
# örtük kalmamalıdır. testthat 3. sürümde her dosya kendi ortamında
# değerlendirilir, ama tek dosya koşumları ve gelecekteki koşucu
# değişiklikleri ortamı PAYLAŞABİLİR; o durumda sonraki bir test dosyası
# `pk_build_provenance_footer()` ya da `%||%` değerini bu SIZAN durumdan
# çözüp kendi kopyasını hiç kaynaklamadan geçer ve sonuçlar DOSYA SIRASINA
# bağlı hâle gelirdi. Yıkım kancası bu olasılığı kapatır; `withr` yoksa
# davranış eskisiyle aynıdır.
.pk_prov_kopyalanan <- ls(.pk_prov_footer_env, all.names = TRUE)
for (.pk_prov_ad in .pk_prov_kopyalanan) {
  assign(.pk_prov_ad, get(.pk_prov_ad, envir = .pk_prov_footer_env),
         envir = environment())
}
rm(.pk_prov_ad)
# `teardown_env()` YALNIZCA bir testthat koşumunun İÇİNDE geçerlidir; bu dosya
# doğrudan `source()` edildiğinde hata fırlatır. Kanca bu yüzden savunmalıdır.
if (requireNamespace("withr", quietly = TRUE)) {
  local({
    dosya_ortami <- environment()
    adlar <- .pk_prov_kopyalanan
    tryCatch(
      withr::defer(
        suppressWarnings(rm(list = adlar, envir = parent.env(dosya_ortami))),
        envir = testthat::teardown_env()
      ),
      error = function(e) invisible(NULL)
    )
  })
}

# DİKKAT: utils::modifyList() liste değerli alanları ada göre ÖZYİNELEMELİ
# birleştirir; `filters = list()` ile geçersiz kılma çalışmaz. Bu yüzden düz
# atama kullanılır.
.pk_prov_base <- function(...) {
  over <- list(...)

  base <- list(
    query_id = "q042",
    query_name = "Aktivite Rol Atamaları",
    filter_status = "ok_filtered",
    filters = list(list(column = "ProjeAdi", value = "Radar", operation = "contains")),
    authorized_rows = 12405L,
    filtered_rows = 312L,
    degradations = list()
  )

  if (length(over) > 0) base[names(over)] <- over
  base
}

test_that("alt bilgi sorgu kimliğini, adını, filtreyi ve satır sayılarını adlandırır", {
  footer <- pk_build_provenance_footer(.pk_prov_base())

  expect_true(nzchar(footer))
  expect_true(grepl("Analiz Kaynağı", footer, fixed = TRUE))
  expect_true(grepl("q042", footer, fixed = TRUE))
  expect_true(grepl("Aktivite Rol Atamaları", footer, fixed = TRUE))
  expect_true(grepl("ProjeAdi", footer, fixed = TRUE))
  expect_true(grepl("Radar", footer, fixed = TRUE))
  expect_true(grepl("içerir", footer, fixed = TRUE))

  # Türkçe binlik ayracı; bilimsel gösterim yok (D19).
  expect_true(grepl("12.405", footer, fixed = TRUE))
  expect_true(grepl("312", footer, fixed = TRUE))
  expect_false(grepl("e+", footer, fixed = TRUE))
})

test_that("kapsamı sınırlı kullanıcı için RLS öncesi sayım alt bilgide GÖRÜNMEZ", {
  # Kullanıcının yetkisi 12.405 satır; ham sonuç 41.930 satırdı. 41.930
  # kullanıcıya ASLA gösterilmez.
  footer <- pk_build_provenance_footer(.pk_prov_base())

  expect_false(grepl("41.930", footer, fixed = TRUE))
  expect_false(grepl("41930", footer, fixed = TRUE))

  # Alan kazara alt bilgi girdisine eklense bile yok sayılır (yapısal güvence).
  footer_kirli <- pk_build_provenance_footer(
    .pk_prov_base(pre_rls_rows = 41930L, rls_total_rows = 41930L)
  )
  expect_false(grepl("41.930", footer_kirli, fixed = TRUE))
  expect_false(grepl("41930", footer_kirli, fixed = TRUE))

  # Sayım daima yetkili popülasyondan BAŞLAR.
  expect_true(grepl("12.405 (yetkiniz dâhilinde)", footer, fixed = TRUE))
})

test_that("kapsamı tüm veri olan ADMIN kendi yetkili popülasyonunun tamamını görür", {
  # ADMIN için RLS bir işlem yapmaz; 41.930 onun yetkili popülasyonudur, bu
  # yüzden gösterilmesi doğrudur. Kural "belirli bir alanı gizle" değil,
  # "görebildiğinden başla".
  footer <- pk_build_provenance_footer(
    .pk_prov_base(authorized_rows = 41930L, filtered_rows = 312L)
  )

  expect_true(grepl("41.930 (yetkiniz dâhilinde)", footer, fixed = TRUE))
  expect_true(grepl("312 (filtre sonrası)", footer, fixed = TRUE))
})

test_that("filtre uygulanmadığında satır satırı tek sayı gösterir", {
  footer <- pk_build_provenance_footer(
    .pk_prov_base(filter_status = "ok_no_filter", filters = list(),
                  authorized_rows = 500L, filtered_rows = 500L)
  )

  expect_true(grepl("Uygulanmadı", footer, fixed = TRUE))
  expect_true(grepl("500 (yetkiniz dâhilinde)", footer, fixed = TRUE))
  expect_false(grepl("filtre sonrası", footer, fixed = TRUE))
})

test_that("AI filtrelemesi kapalı sorgu bunu açıkça belirtir", {
  footer <- pk_build_provenance_footer(.pk_prov_base(filter_status = "disabled", filters = list()))
  expect_true(grepl("AI filtreleme kapalıdır", footer, fixed = TRUE))
})

test_that("filtre aşamasına hiç gelinmediğinde bu durum 'filtre yok' gibi sunulmaz", {
  # Yetki sonrası 0 satır kaldığında filtre adımı HİÇ çalışmaz. Bunu
  # `ok_no_filter` diye kaydetmek, modelin çalışıp filtre üretmediğini iddia
  # etmek olurdu; Faz 0 gözleyemediği bir durumu iddia etmez.
  expect_true(pk_filter_status_valid("not_reached"))
  expect_false(pk_filter_status_is_degraded("not_reached"))
  expect_length(pk_degradations_from_filter_status("not_reached"), 0L)

  footer <- pk_build_provenance_footer(
    .pk_prov_base(filter_status = "not_reached", filters = list(),
                  authorized_rows = 0L, filtered_rows = 0L)
  )
  expect_true(grepl("filtre aşamasına ulaşmadı", footer, fixed = TRUE))
})

test_that("bozulmalar alt bilgide görünür", {
  footer <- pk_build_provenance_footer(.pk_prov_base(
    filter_status = "timeout",
    filters = list(),
    degradations = pk_degradations_from_filter_status("timeout")
  ))

  expect_true(grepl("Uyarı", footer, fixed = TRUE))
  expect_true(grepl("zaman aşımına", footer, fixed = TRUE))
  expect_true(grepl("UYGULANAMADI", footer, fixed = TRUE))
})

test_that("filtre değerleri markdown yapısını bozamaz", {
  # Filtre değeri LLM/kullanıcı kaynaklıdır; satır sonu ve markdown ayracı
  # etkisizleştirilir (ham HTML kaçışı ayrıca merkezî markdown sınırında yapılır).
  footer <- pk_build_provenance_footer(.pk_prov_base(
    filters = list(list(column = "ProjeAdi",
                        value = "Bir\nSatir | Tablo `kod`",
                        operation = "contains"))
  ))

  # Alt bilgi satır sayısı beklendiği gibi kalmalı (değer satırı bölmemeli).
  satirlar <- strsplit(trimws(footer), "\n", fixed = TRUE)[[1]]
  expect_true(all(!grepl("^Satir \\| Tablo", satirlar)))
  expect_false(grepl("`kod`", footer, fixed = TRUE))
})

test_that("boş/eksik girdi alt bilgi üretmez veya güvenle küçülür", {
  expect_identical(pk_build_provenance_footer(NULL), "")
  expect_identical(pk_build_provenance_footer(list()), "")

  # Sorgu adı yoksa bile filtre satırı üretilir.
  footer <- pk_build_provenance_footer(list(filter_status = "ok_no_filter"))
  expect_true(grepl("Filtre", footer, fixed = TRUE))
})

test_that("filtre durumu tipleri doğrulanır ve bozulma yalnızca gerçek arızada üretilir", {
  expect_true(pk_filter_status_valid("ok_no_filter"))
  expect_false(pk_filter_status_valid("uydurma"))
  expect_identical(pk_filter_status_normalize("uydurma"), "error")

  # Meşru "filtre gerekmiyordu" bir bozulma DEĞİLDİR.
  expect_length(pk_degradations_from_filter_status("ok_no_filter"), 0L)
  expect_length(pk_degradations_from_filter_status("ok_filtered"), 0L)
  expect_length(pk_degradations_from_filter_status("disabled"), 0L)
  expect_length(pk_degradations_from_filter_status("stopped"), 0L)

  for (bozuk in c("timeout", "error", "malformed")) {
    expect_length(pk_degradations_from_filter_status(bozuk), 1L)
  }
})

test_that("istek kapsamlı yuva: sakla, al, tüket", {
  session <- list(userData = new.env(parent = emptyenv()))

  pk_provenance_clear(session, request_id = "req-1")
  expect_identical(pk_provenance_current_request_id(session), "req-1")

  pk_provenance_stash(session, "ALT-BILGI", request_id = "req-1")

  expect_identical(pk_provenance_take(session, request_id = "req-1"), "ALT-BILGI")
  # İkinci alışta yuva boştur (tüketildi).
  expect_null(pk_provenance_take(session, request_id = "req-1"))
})

test_that("bayat istek kimliğinde alt bilgi İLİŞTİRİLMEZ", {
  session <- list(userData = new.env(parent = emptyenv()))
  pk_provenance_clear(session, request_id = "req-1")
  pk_provenance_stash(session, "ESKI-ALT-BILGI", request_id = "req-1")

  # Yeni istek eski alt bilgiyi almamalı: eksik alt bilgi güvenlidir,
  # YANLIŞ alt bilgi değildir.
  expect_null(pk_provenance_take(session, request_id = "req-2"))
})

test_that("yeni istek başlangıcı bekleyen alt bilgiyi temizler", {
  session <- list(userData = new.env(parent = emptyenv()))
  # ÖNCE ETKİN İSTEK KURULUR VE SAKLAMANIN BAŞARILI OLDUĞU KANITLANIR.
  #
  # Taze oturumda etkin istek kimliği YOKTUR; `pk_provenance_stash()` o
  # durumda `FALSE` döner (bkz. test-pk-provenance-delivery-contract.R).
  # Yuva zaten boş kaldığı için aşağıdaki `expect_null()`, temizleme HİÇBİR
  # ŞEY yapmasa bile geçiyordu.
  pk_provenance_clear(session, request_id = "req-1")
  expect_true(isTRUE(pk_provenance_stash(session, "ESKI", request_id = "req-1")))

  pk_provenance_clear(session, request_id = "req-2")
  expect_null(pk_provenance_take(session))
})

test_that("iliştirme idempotenttir ve hata fırlatmaz", {
  session <- list(userData = new.env(parent = emptyenv()))
  footer <- pk_build_provenance_footer(.pk_prov_base())

  pk_provenance_clear(session, request_id = "req-1")
  pk_provenance_stash(session, footer, request_id = "req-1")

  metin <- pk_provenance_decorate("Yanıt metni.", session, request_id = "req-1")
  expect_true(grepl("Yanıt metni.", metin, fixed = TRUE))
  expect_true(grepl("Analiz Kaynağı", metin, fixed = TRUE))

  # İkinci çağrı (yuva boş) metni değiştirmez.
  expect_identical(pk_provenance_decorate(metin, session, request_id = "req-1"), metin)

  # Alt bilgi zaten varsa tekrar eklenmez.
  pk_provenance_stash(session, footer, request_id = "req-1")
  expect_identical(pk_provenance_decorate(metin, session, request_id = "req-1"), metin)
})

test_that("PK dışı yanıtlarda metin aynen kalır", {
  session <- list(userData = new.env(parent = emptyenv()))
  pk_provenance_clear(session, request_id = "req-1")

  expect_identical(pk_provenance_decorate("Sıradan yanıt", session), "Sıradan yanıt")
  expect_no_error(pk_provenance_decorate("x", NULL))
  expect_identical(pk_provenance_decorate("x", NULL), "x")
})
