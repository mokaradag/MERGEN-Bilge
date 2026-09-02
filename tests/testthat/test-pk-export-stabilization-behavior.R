# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-export-stabilization-behavior.R
# Açıklama: PR #705 kararlılık düzeltmeleri — dışa aktarım hattı.
#
#           Kapsanan altı kök neden:
#             1. İzole `run_` dizini oluşturulamadığında PAYLAŞILAN köke geri
#                düşülüyordu; aynı saniyede aynı sorguyu aktaran iki oturum
#                aynı yola yazabilir ve bir kullanıcının kayıtlı bağlantısı
#                başka bir kullanıcının RLS ile süzülmüş verisini sunabilirdi.
#             2. XLSX kapısı yalnızca HÜCRE sayısına bakıyordu; hücre GENİŞLİĞİ
#                ölçülmüyordu.
#             3. CSV yedeği akışlı olduğu iddiasına rağmen tüm sonucu
#                dönüştürülmüş İKİNCİ bir çerçeveye kopyalıyordu.
#             4. CSV doğrulaması her parçayı BİR KEREDE belleğe geri okuyordu.
#             5. CSV hazırlık/yazım/doğrulama aşamaları iptal/son tarih
#                gözlemiyordu.
#             6. Son tarih aşımı KULLANICI İPTALİ olarak raporlanıyordu.
#
#           Tümü çevrimdışı ve deterministiktir: gerçek DB, LLM, tarayıcı,
#           SSO, ağ veya gerçek sır KULLANILMAZ. Fixture'lar sentetiktir.
# ==============================================================================

.pk_exps_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$safe_unlink_if_exists <- function(path) {
    if (!is.null(path) && is.character(path) && length(path) == 1L &&
        !is.na(path) && nzchar(path) && file.exists(path)) {
      try(unlink(path, force = TRUE), silent = TRUE)
    }
    invisible(TRUE)
  }
  for (dosya in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
                  "helpers_pk_async_cancel.R",
                  "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R", "helpers_pk_packet_keys.R", "helpers_pk_analysis_packet.R",
                  "helpers_pk_packet_render.R", "helpers_pk_export_plan.R",
                  "helpers_pk_export_csv.R", "helpers_pk_export_xlsx.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.pk_exps_frame <- function(n = 12L, genis = FALSE) {
  data.frame(
    Ad    = paste0("SENTETIK_", seq_len(n)),
    # DISTINCT degerler sart: R ayni karakter degeri icin TEK bir CHARSXP
    # paylasir, dolayisiyla `rep(strrep(...), n)` object.size'i buyutmez.
    Metin = if (isTRUE(genis)) {
      vapply(seq_len(n), function(i) paste0(strrep("x", 8192L), i), character(1))
    } else {
      paste0("deger_", seq_len(n))
    },
    Sayi  = as.numeric(seq_len(n)),
    stringsAsFactors = FALSE
  )
}

test_that("izole calisma dizini kurulamazsa PAYLASILAN koke DUSULMEZ", {
  env <- .pk_exps_env()

  kok <- file.path(tempdir(), paste0("pk_exps_", as.integer(runif(1, 1, 1e9))))
  dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE, force = TRUE), add = TRUE)

  # Normal yolda GERCEK izole bir alt dizin doner.
  izole <- env$pk_export_run_dir(kok)
  expect_false(is.null(izole))
  expect_true(dir.exists(izole))
  expect_false(identical(normalizePath(izole), normalizePath(kok)))

  # KUSUR: `dir.create` basarisiz oldugunda paylasilan kok donuyordu. Artik
  # NULL doner; cagiran disa aktarimi BASARISIZ sayar.
  local({
    sahte_dir_create <- function(...) invisible(FALSE)
    env2 <- new.env(parent = environment(env$pk_export_run_dir))
    env2$dir.create <- sahte_dir_create
    f <- env$pk_export_run_dir
    environment(f) <- env2
    expect_null(f(kok))
  })
})

test_that("izole dizin yoksa disa aktarim BASARISIZ olur, paylasilan koke yazilmaz", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame()

  # `pk_export_run_dir` NULL dondurecek sekilde golgelenir.
  env$pk_export_run_dir <- function(base_dir = NULL) NULL

  sonuc <- env$pk_export_build(veri, base_name = "sentetik")
  expect_identical(sonuc$status, "failed")
  expect_length(sonuc$files, 0L)
  expect_true(grepl("yalıtılmış", sonuc$message, fixed = TRUE))
})

test_that("XLSX kapisi HUCRE sayisinin yani sira BAYT tavanini da uygular", {
  skip_if_not_installed("withr")
  env <- .pk_exps_env()

  # Az hucre, COK genis hucreler: hucre tavaninin cok altinda ama byte olarak
  # buyuk. Eski kapi bunu XLSX'e gonderirdi.
  veri <- .pk_exps_frame(n = 200L, genis = TRUE)
  dizin <- file.path(tempdir(), paste0("pk_exps_b_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  toplam_hucre <- nrow(veri) * ncol(veri)
  expect_true(toplam_hucre < env$.pk_export_cell_ceiling(NULL))

  withr::with_envvar(list(MERGEN_PK_EXPORT_MAX_BYTES_MB = "1"), {
    expect_true(as.numeric(utils::object.size(veri)) > env$.pk_export_byte_ceiling(NULL))
    sonuc <- env$pk_export_build(veri, base_name = "sentetik", dir = dizin)
    # Bayt tavani asildigi icin akisli CSV yoluna gecilir.
    expect_identical(sonuc$status, "csv_fallback")
    expect_true(length(sonuc$files) > 0L)
  })
})

test_that("bayt tavani ALTINDA davranis DEGISMEZ", {
  skip_if_not_installed("writexl")
  # `pk_export_build()` "ok" dondurmek icin GERI OKUMA dogrulamasini gecmek
  # zorundadir; `readxl` yoksa dogrulama basarisiz olur ve CSV yedegine
  # dusulur. `readxl` opsiyoneldir, yani bu desteklenen bir yapilandirmadir
  # ve test o ortamda GERILEME yuzunden degil ORTAM yuzunden duserdi.
  skip_if_not_installed("readxl")
  skip_if_not_installed("withr")
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 8L)
  dizin <- file.path(tempdir(), paste0("pk_exps_c_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  withr::with_envvar(list(MERGEN_PK_EXPORT_MAX_BYTES_MB = "512"), {
    sonuc <- env$pk_export_build(veri, base_name = "sentetik", dir = dizin)
    # Tavanin ALTINDA XLSX yolu SECILMELIDIR. `%in% c("ok", "csv_fallback")`
    # her iki sonucu da kabul ettigi icin, bayt kapisi gerileyip HER ihraci CSV
    # yoluna itse bile iddia geciyordu; yani test korumasi gereken regresyonu
    # HIC yakalayamiyordu.
    expect_identical(sonuc$status, "ok")
    expect_true(length(sonuc$files) > 0L)
  })
})

test_that("CSV yedegi TAM BOYUTLU ikinci kopya olusturmaz (parca basina donusum)", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 30L)
  dizin <- file.path(tempdir(), paste0("pk_exps_d_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  # Donusum PARCA BASINA cagrilir; her cagri plan parcasi kadar satir gorur.
  gorulen_satirlar <- integer(0)
  # COK PARCALI plan SARTTIR: varsayilan satir tavani ile 30 satirlik cerceve
  # TEK parca uretir ve "tum cerceveyi tek seferde donustur" regresyonu da
  # asagidaki iddialari GECERDI (tek cagri = 30 satir = nrow(veri)).
  plan <- env$pk_export_plan(veri, base_name = "Veri", max_rows = 10L)
  expect_identical(length(plan$parts), 3L)

  paket <- env$pk_export_csv_bundle(
    dizin, "sentetik", plan, veri,
    transform = function(dilim) {
      gorulen_satirlar <<- c(gorulen_satirlar, nrow(dilim))
      dilim
    }
  )

  expect_true(isTRUE(paket$ok))
  # HICBIR cagri TUM cerceveyi gormedi: en buyuk dilim parca tavanindan kucuk
  # ya da esittir ve toplam satir sayisi korunur.
  expect_identical(length(gorulen_satirlar), 3L)
  expect_true(max(gorulen_satirlar) < nrow(veri))
  expect_true(max(gorulen_satirlar) <= 10L)
  expect_identical(sum(gorulen_satirlar), nrow(veri))

  # Donusum UYGULANIR: sutun adi degistiginde dosyaya o ad yazilir.
  paket2 <- env$pk_export_csv_bundle(
    dizin, "sentetik2", plan, veri,
    transform = function(dilim) { names(dilim)[1] <- "DONUSTURULDU"; dilim }
  )
  expect_true(isTRUE(paket2$ok))
  ilk <- readLines(paket2$files[[1]]$path, n = 1L, warn = FALSE)
  expect_true(grepl("DONUSTURULDU", ilk, fixed = TRUE))
})

test_that("transform verilmezse eski davranis BIREBIR korunur", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 10L)
  dizin <- file.path(tempdir(), paste0("pk_exps_e_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  plan <- env$pk_export_plan(veri, base_name = "Veri")
  paket <- env$pk_export_csv_bundle(dizin, "sentetik", plan, veri)
  expect_true(isTRUE(paket$ok))
  ilk <- readLines(paket$files[[1]]$path, n = 1L, warn = FALSE)
  expect_true(grepl("Ad", ilk, fixed = TRUE))
})

test_that("CSV paketi PARCALAR ARASINDA iptal yoklar", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 20L)
  dizin <- file.path(tempdir(), paste0("pk_exps_f_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  plan <- env$pk_export_plan(veri, base_name = "Veri")

  # KUSUR: kapi yalnizca TUM paket uretildikten SONRA yoklaniyordu.
  paket <- env$pk_export_csv_bundle(dizin, "sentetik", plan, veri,
                                    stop_check = function() TRUE)
  expect_false(isTRUE(paket$ok))
  expect_length(paket$files, 0L)
  # Yarim kume BIRAKILMAZ.
  expect_length(list.files(dizin, pattern = "\\.csv$"), 0L)
})

test_that("CSV dogrulamasi PARCA PARCA okur ve dogru karar verir", {
  env <- .pk_exps_env()
  dizin <- file.path(tempdir(), paste0("pk_exps_g_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  # Parca sinirindan (5000) BUYUK cerceve: dongu birden fazla tur doner.
  n <- 12000L
  df <- data.frame(
    Ad = paste0("SENTETIK_", seq_len(n)),
    Sayi = as.numeric(seq_len(n)),
    Oran = c(Inf, -Inf, rep(1.5, n - 2L)),
    stringsAsFactors = FALSE
  )
  yol <- file.path(dizin, "buyuk.csv")
  env$.pk_export_write_csv_bom(yol, df)

  expect_true(isTRUE(env$pk_export_csv_verify(yol, df)$ok))

  # Bozulmus beklenti REDDEDILIR.
  bozuk <- df
  bozuk$Sayi[7000L] <- -1
  expect_false(isTRUE(env$pk_export_csv_verify(yol, bozuk)$ok))

  # Satir sayisi uyusmazligi REDDEDILIR.
  expect_false(isTRUE(env$pk_export_csv_verify(yol, df[1:100, , drop = FALSE])$ok))
})

test_that("satir sayisi PARCA KATI oldugunda dosya sonu korumasi calisir", {
  env <- .pk_exps_env()
  dizin <- file.path(tempdir(), paste0("pk_exps_gk_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  # `pk_export_csv_verify()` dosya sonu korumasinin TETIKLEYICISI, parca satir
  # sayisinin `.PK_CSV_CHUNK_ROWS` TAM KATI olmasidir: son okuma tam dolar,
  # dongu kirilmaz ve tukenmis baglantida bir okuma daha denenirdi. 12000 satir
  # tam kat DEGILDIR, dolayisiyla korunan yol hic calismiyordu.
  n <- 2L * env$.PK_CSV_CHUNK_ROWS
  df <- data.frame(
    Ad = paste0("SENTETIK_", seq_len(n)),
    Sayi = as.numeric(seq_len(n)),
    stringsAsFactors = FALSE
  )
  yol <- file.path(dizin, "tam_kat.csv")
  env$.pk_export_write_csv_bom(yol, df)

  expect_true(isTRUE(env$pk_export_csv_verify(yol, df)$ok))

  # FAZLADAN icerik hala ACIKCA reddedilir (koruma "sessizce kabul et" degildir).
  # Gerekce KORUMANIN KENDISINDEN gelmelidir: koruma kaldirildiginda ret yine
  # olusur ama gerekce genel satir-sayisi mesajidir, dolayisiyla yalnizca
  # `expect_false` korunan yolu AYIRT EDEMEZDI.
  con <- file(yol, open = "ab")
  # BAGLANTI HATA YOLUNDA DA KAPANIR: `writeLines()` hata verirse `close(con)`
  # hic calismaz; Windows'ta acik tanitici `tam_kat.csv` dosyasini KILITLER ve
  # yukaridaki `on.exit(unlink(dizin, ...))` dizini silemez, gecici veri oturum
  # boyunca diskte kalirdi.
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeLines("SENTETIK_FAZLA,999", con, sep = "\n")
  close(con)
  fazla_sonuc <- env$pk_export_csv_verify(yol, df)
  expect_false(isTRUE(fazla_sonuc$ok))
  gerekce <- as.character(fazla_sonuc$reason)
  expect_true(length(gerekce) == 1L &&
                grepl("fazladan satir", gerekce, fixed = TRUE))
})

test_that("TIRNAKLI gomulu satir sonu parca okumada BOZULMAZ", {
  env <- .pk_exps_env()
  dizin <- file.path(tempdir(), paste0("pk_exps_h_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  # Satir bazli (kayit bazli olmayan) bir okuyucu bu fixture'da bozulurdu.
  df <- data.frame(
    Metin = c("bir\nsatir", "iki", "uc\ndort", "İstanbul\nÇağrı"),
    Sayi = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  yol <- file.path(dizin, "gomulu.csv")
  env$.pk_export_write_csv_bom(yol, df)
  expect_true(isTRUE(env$pk_export_csv_verify(yol, df)$ok))
})

test_that("SON TARIH asimi KULLANICI IPTALI olarak raporlanmaz", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 10L)
  dizin <- file.path(tempdir(), paste0("pk_exps_i_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  # KUSUR: `iptal_sonucu()` her yolu "cancelled" olarak sabitliyordu; yalnizca
  # analiz son tarihine ulasan buyuk bir disa aktarim kullanici iptali gibi
  # raporlaniyordu.
  eski <- options(mergen.pk.async.deadline_at = Sys.time() - 60)
  on.exit(options(eski), add = TRUE)

  sonuc <- env$pk_export_build(veri, base_name = "sentetik", dir = dizin)
  expect_identical(sonuc$status, "deadline")
  expect_false(grepl("kullanıcı", sonuc$message, fixed = TRUE))
})

test_that("KULLANICI iptali hala 'cancelled' olarak raporlanir", {
  env <- .pk_exps_env()
  veri <- .pk_exps_frame(n = 10L)
  dizin <- file.path(tempdir(), paste0("pk_exps_j_", as.integer(runif(1, 1, 1e9))))
  dir.create(dizin, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dizin, recursive = TRUE, force = TRUE), add = TRUE)

  sonuc <- env$pk_export_build(veri, base_name = "sentetik", dir = dizin,
                               stop_check = function() TRUE)
  expect_identical(sonuc$status, "cancelled")
})
