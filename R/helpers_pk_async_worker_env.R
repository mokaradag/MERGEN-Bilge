# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker_env.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ ORTAMI YAŞAM DÖNGÜSÜ: içerik tabanlı kaynak
#           parmak izi, TEMİZ ortama yeniden yükleme ve bootstrap ÖNCESİ
#           yardımcıların işçi `globalenv()`'ine kurulması.
#
# `R/helpers_pk_async_bootstrap.R` içinden BÖLÜNMÜŞTÜR: orası bootstrap
# SÖZLEŞMESİDİR (hangi dosyalar, hangi giriş noktaları) ve 24-fonksiyon bakım
# tavanına dayanmıştı. Ortam yaşam döngüsü ayrı bir sorumluluktur.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca dosya sistemi ve ortam işler.
# ==============================================================================

# ------------------------------------------------------------------------------
# BOOTSTRAP ÖNCESİ YARDIMCILARIN İŞÇİYE KURULMASI
# ------------------------------------------------------------------------------
# `dependency_mode = "explicit"` globals'ı görev fonksiyonunun İZOLE ortamına
# yazar. `pk_async_run_analysis()` ise ANA SÜREÇTE tanımlanmış bir kapanıştır ve
# serileştirildiğinde lexical ortamı İŞÇİNİN `globalenv()`'i olur — yani izole
# globals ortamını GÖRMEZ. Bootstrap henüz çalışmadığı için o `globalenv()`
# BOŞTUR ve temiz bir PSOCK işçisi ham bir "could not find function" ile ölerdi.
#
# Bu yüzden görev fonksiyonu, kendi ortamındaki paketi analiz başlamadan ÖNCE
# işçinin `globalenv()`'ine kurar. Bootstrap sonradan aynı sembolleri repo
# dosyalarından yeniden tanımlar; iki kaynak da AYNI revizyondur.
#
# Ana süreçte (senkron/test yolu) bu işlem NO-OP'a yakındır: aynı isimler aynı
# nesnelerle üzerine yazılır.
#
# Paket, işçi globals paketi olduğunu kanıtlayan bir İŞARET taşır; işaretsiz
# hiçbir ortam `globalenv()`'e kopyalanmaz.
.PK_ASYNC_WORKER_BUNDLE_MARK <- ".pk_async_worker_bundle"

# ORTAK `tryCatch` HATA İŞLEYİCİSİ: "boş karakter vektörüne düş" davranışı bu
# dosyada dört ayrı yerde geçiyordu. Tek isimli işleyiciyi paylaşmak davranışı
# AYNI tutar ve bakım oranı fonksiyon bütçesini adsız kopyalarla tüketmez.
.pk_async_chr0 <- function(e) character(0)

pk_async_worker_install_globals <- function(env, exclude = c("request", "task_fn")) {
  if (!is.environment(env)) return(invisible(character(0)))

  hedef <- globalenv()
  adlar <- tryCatch(ls(env, all.names = TRUE), error = .pk_async_chr0)

  # GÜVENLİK KAPISI: yalnızca AÇIKÇA işaretlenmiş işçi paketi kurulur. Bu
  # olmadan, kip yanlışlıkla "auto"ya çevrilirse bir gözlemci/oturum kapanışının
  # tüm bağları `globalenv()`'e kopyalanabilirdi.
  if (!(.PK_ASYNC_WORKER_BUNDLE_MARK %in% adlar)) return(invisible(character(0)))

  adlar <- setdiff(adlar, c(as.character(exclude %||% character(0)),
                            .PK_ASYNC_WORKER_BUNDLE_MARK))
  if (!length(adlar)) return(invisible(character(0)))

  kurulan <- character(0)
  for (ad in adlar) {
    ok <- tryCatch({
      deger <- get(ad, envir = env, inherits = FALSE)
      # Ana süreçte kendi kendini üzerine yazmak gereksiz iş olurdu.
      if (!identical(hedef, env)) assign(ad, deger, envir = hedef)
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) kurulan <- c(kurulan, ad)
  }

  # KURULAN ADLAR KAYDEDİLİR: sahneleme ortamı bu "bilinçli kararlı bağımlılık"
  # kümesini AÇIKÇA enjekte eder (bkz. `pk_async_worker_stage_env()`), çünkü
  # sahneleme artık `globalenv()`'i ebeveyn olarak KULLANMAZ.
  try(assign(.PK_ASYNC_INSTALLED_GLOBALS_SLOT, kurulan, envir = hedef), silent = TRUE)
  invisible(kurulan)
}

# Ana süreçten kurulan (bayat OLMAYAN) global adların kaydı.
.PK_ASYNC_INSTALLED_GLOBALS_SLOT <- ".mergen_pk_async_installed_globals"

# ------------------------------------------------------------------------------
# SINIRLI DOSYA SİSTEMİ ÇAĞRISI
# ------------------------------------------------------------------------------
# Bootstrap dosya sistemine SENKRON dokunur (`file.info()`, `file()`/`readBin()`,
# `file.exists()`, `sys.source()`). Repo/SQL ağacı ASKIDA bir UNC/NFS yolundaysa
# bu çağrılardan HERHANGİ BİRİ analiz son tarihini aşabilir ve dönene kadar
# Durdur GÖZLENEMEZ; aşamalar arasına kapı koymak bunu ÇÖZMEZ (PR #703).
#
# DÜRÜSTLÜK NOTU: `setTimeLimit()` İŞ BİRLİĞİNE dayalıdır ve tek bir askıda
# yerli syscall'ı GARANTİLİ kesemez. Bu yüzden Faz 6'nın sert son tarih iddiası
# ANA SÜREÇTEKİ BEKÇİYE dayanır (bkz. `server_handler_pk_async.R`): işçi askıda
# kalsa bile kullanıcı ve oturum beklemez. Buradaki sınır, kesilebilir olan
# çoğu durumu (R döngüleri, yeniden denenen G/Ç) erken keser.
pk_async_bounded_fs <- function(fn, deadline_at = NULL) {
  butce <- Inf
  if (!is.null(deadline_at) &&
      exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) {
    butce <- suppressWarnings(as.numeric(tryCatch(
      pk_deadline_remaining_sec(deadline_at), error = function(e) Inf
    ))[1])
  }
  if (length(butce) != 1L || is.na(butce)) butce <- Inf
  if (is.finite(butce) && butce <= 0) {
    return(list(ok = FALSE, value = NULL, error = "budget_exhausted"))
  }
  if (is.finite(butce)) {
    on.exit(try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE),
            add = TRUE)
    setTimeLimit(cpu = Inf, elapsed = max(0.05, butce), transient = TRUE)
  }
  tryCatch(list(ok = TRUE, value = fn(), error = NA_character_),
           error = function(e) list(ok = FALSE, value = NULL,
                                    error = conditionMessage(e)))
}

# ------------------------------------------------------------------------------
# İÇERİK TABANLI KAYNAK PARMAK İZİ
# ------------------------------------------------------------------------------
# Kalıcı bir PSOCK işçisi ilk yüklediği uygulamayı ömrü boyunca saklar. Parmak
# izi değiştiğinde önbellek geçersizleşir ve işçi yeniden yüklenir.
#
# mtime + boyut YETMEZ: zaman damgalarını koruyan bir dağıtım/kopya, bir dosyayı
# AYNI uzunlukta FARKLI içerikle değiştirebilir; işçi o zaman eski kodu süresiz
# çalıştırmaya devam ederdi. Bu yüzden parmak izi DOSYA İÇERİĞİNDEN türetilir.
.pk_async_file_digest <- function(path) {
  boyut <- suppressWarnings(file.info(path)$size[1])
  if (is.na(boyut) || boyut <= 0) return(paste0(basename(path), ":yok"))

  ham <- tryCatch({
    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)
    readBin(con, what = "raw", n = boyut)
  }, error = function(e) NULL)
  if (is.null(ham)) return(paste0(basename(path), ":okunamadi"))

  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(ham, algo = "sha256", serialize = FALSE))
  }
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(paste(as.character(openssl::sha256(ham)), collapse = ""))
  }
  # Son çare: uzunluk + konum ağırlıklı toplam. `digest`/`openssl` üretimde
  # ZORUNLU bağımlılıktır; bu dal yalnızca çıplak test ortamları içindir.
  paste0(boyut, ":", sum(as.integer(ham) * seq_along(ham)) %% .Machine$integer.max)
}

# `config_sql_loader.R` her sorgunun HARİCİ `sql_file` dosyasını source anında
# `query_library` içine okur. Bir operatör `library_queries.R` dosyasına HİÇ
# dokunmadan bir `.sql` dosyasını güncellerse, ana süreç yeni SQL'i yüklerken
# kalıcı işçi aynı parmak izini görüp `cached = TRUE` döndürür ve ESKİ SQL'i
# süresiz çalıştırır. Bu yüzden çözülen SQL bağımlılıkları da parmak izine girer.
pk_async_worker_sql_dependencies <- function(repo_root) {
  kutuphane <- get0("query_library", inherits = TRUE)
  if (!is.list(kutuphane) || !length(kutuphane)) return(character(0))

  yollar <- vapply(kutuphane, function(sorgu) {
    if (!is.list(sorgu)) return("")
    yol <- tryCatch(as.character(sorgu$sql_file)[1], error = function(e) "")
    if (is.null(yol) || is.na(yol)) "" else yol
  }, character(1))

  yollar <- unique(yollar[nzchar(yollar)])
  if (!length(yollar)) return(character(0))

  # Göreli yollar repo köküne göre çözülür (loader `getwd()` kullanır).
  mutlak <- ifelse(
    grepl("^([A-Za-z]:)?[/\\\\]", yollar),
    yollar,
    file.path(repo_root, yollar)
  )
  sort(unique(mutlak))
}

#' Bootstrap kaynak parmak izi (İÇERİK tabanlı, SQL bağımlılıkları dahil)
pk_async_bootstrap_fingerprint <- function(repo_root, files) {
  tam <- file.path(repo_root, files)
  sql <- tryCatch(pk_async_worker_sql_dependencies(repo_root), error = .pk_async_chr0)

  hedefler <- c(tam, sql)
  parcalar <- vapply(hedefler, function(p) {
    paste0(basename(p), "@", .pk_async_file_digest(p))
  }, character(1), USE.NAMES = FALSE)

  ham <- paste(c(length(files), parcalar), collapse = "|")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(ham, algo = "sha256"))
  }
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(paste(as.character(openssl::sha256(ham)), collapse = ""))
  }
  paste0(length(hedefler), ":", nchar(ham))
}

# ------------------------------------------------------------------------------
# TEMİZ ORTAMA YENİDEN YÜKLEME
# ------------------------------------------------------------------------------
# Sıcak bir işçiye yeni revizyonu doğrudan `globalenv()` üzerine source etmek,
# KALDIRILMIŞ veya YENİDEN ADLANDIRILMIŞ sembolleri geride bırakır: işçi eski ve
# yeni güvenlik mantığının KARIŞIMINI çalıştırabilirdi. Bu yüzden yeni revizyon
# önce bir SAHNELEME ortamına yüklenir ve YALNIZCA tamamı başarılı olduğunda
# `globalenv()`'e alınır; bir önceki bootstrap'ın sahiplendiği isimler o anda
# temizlenir.
.PK_ASYNC_OWNED_NAMES_SLOT <- ".mergen_pk_async_bootstrap_names"

#' TEMİZ sahneleme ortamı
#'
#' EBEVEYN `globalenv()` DEĞİLDİR (PR #703 incelemesi). `globalenv()` ebeveyn
#' olduğunda sahneleme sırasındaki `exists(..., inherits = TRUE)` /
#' `get(..., inherits = TRUE)` çağrıları ÖNCEKİ bootstrap'ın sembollerini
#' görebilir. Somut vaka: `config_sql_loader.R` guard'ı, yeni `library_queries.R`
#' yerel bir `query_library` üretemediğinde ESKİ işçinin global `query_library`
#' değerini bulup BAYAT SQL ile devam edebilirdi — yani "atomik temiz yeniden
#' yükleme" garantisi kırılır ve eski SQL + yeni kod KARIŞIMI commit edilirdi.
#'
#' Ebeveyn olarak `parent.env(globalenv())` (attach edilmiş paket arama yolu)
#' kullanılır: paketler görünür kalır, ÖNCEKİ bootstrap SEMBOLLERİ görünmez.
#' Ana süreçten AÇIKÇA kurulan globals paketi (bayat değildir; bu isteğe aittir)
#' bilinçli olarak enjekte edilir.
#' Sahneleme ebeveynini TAZELE (yeni attach edilen paketleri görünür kılar)
#'
#' ZORUNLUDUR: `library()` paketi arama yolunun BAŞINA, yani
#' `parent.env(globalenv())` konumuna ekler. Sahneleme ortamı ebeveynini
#' KURULUM ANINDA dondurursa, bootstrap sırasında `R/config_packages.R`
#' tarafından attach edilen paketler (logger, DBI, ...) sonraki dosyalara
#' GÖRÜNMEZ ve `R/config_logging.R` "could not find function log_threshold"
#' ile düşer. Ebeveyn her dosyadan ÖNCE yeniden bağlanır; böylece hem paketler
#' güncel kalır hem de ÖNCEKİ bootstrap'ın `globalenv()` sembolleri görünmez.
pk_async_worker_stage_refresh <- function(stage, target = globalenv()) {
  if (!is.environment(stage)) return(invisible(FALSE))
  yeni_ebeveyn <- tryCatch(parent.env(target), error = function(e) NULL)
  if (!is.environment(yeni_ebeveyn)) return(invisible(FALSE))
  if (identical(parent.env(stage), yeni_ebeveyn)) return(invisible(TRUE))
  isTRUE(tryCatch({ parent.env(stage) <- yeni_ebeveyn; TRUE }, error = function(e) FALSE))
}

pk_async_worker_stage_env <- function(target = globalenv()) {
  sahne <- new.env(parent = parent.env(target))

  adlar <- get0(.PK_ASYNC_INSTALLED_GLOBALS_SLOT, envir = target, inherits = FALSE)
  adlar <- as.character(adlar %||% character(0))
  for (ad in adlar) {
    deger <- get0(ad, envir = target, inherits = FALSE)
    if (is.null(deger)) next
    try(assign(ad, deger, envir = sahne), silent = TRUE)
  }
  sahne
}

#' Sahneleme ortamını `globalenv()`'e al (önceki bootstrap isimlerini temizler)
#'
#' ATOMİK COMMIT SÖZLEŞMESİ (PR #703 incelemesi): her `rm`/`assign` DENETLENİR.
#' Bir tek hedef bile yazılamazsa commit BAŞARISIZDIR; çağıran bootstrap'ı
#' düşürür. Eskiden hatalar yutuluyordu, bu yüzden kilitli/aktif bir bağ eski
#' uygulamayı YERİNDE bırakırken işçi "tam güncellendi" işaretleniyor ve
#' `pk_async_worker_ready()` (yalnızca ad varlığına bakar) bunu onaylıyordu.
#'
#' @return `list(ok = TRUE/FALSE, names = <chr>, failed = <chr>)`.
pk_async_worker_commit_env <- function(stage, target = globalenv()) {
  if (!is.environment(stage)) return(list(ok = FALSE, names = character(0), failed = "stage"))

  onceki <- get0(.PK_ASYNC_OWNED_NAMES_SLOT, envir = target, inherits = FALSE)
  onceki <- as.character(onceki %||% character(0))

  yeni <- tryCatch(ls(stage, all.names = TRUE), error = .pk_async_chr0)
  basarisiz <- character(0)

  # Yeni revizyonda ARTIK OLMAYAN eski bootstrap sembolleri kaldırılır.
  atilacak <- setdiff(onceki, yeni)
  for (ad in atilacak) {
    if (!exists(ad, envir = target, inherits = FALSE)) next
    silindi <- try({ rm(list = ad, envir = target); TRUE }, silent = TRUE)
    if (!identical(silindi, TRUE) || exists(ad, envir = target, inherits = FALSE)) {
      basarisiz <- c(basarisiz, paste0(ad, " (silinemedi)"))
    }
  }

  for (ad in yeni) {
    yazildi <- try({
      deger <- get(ad, envir = stage, inherits = FALSE)
      # TOP-LEVEL kapanışlar `globalenv()` üzerinden çözülmeye devam etsin:
      # sahneleme ebeveyni artık `globalenv()` DEĞİL, bu yüzden commit edilen
      # fonksiyonların ortamı hedefe çevrilir (davranış commit ÖNCESİ hâlle
      # aynıdır; sahnedeki her sembol zaten hedefe kopyalanır).
      if (is.function(deger) && identical(environment(deger), stage)) {
        environment(deger) <- target
      }
      assign(ad, deger, envir = target)
      TRUE
    }, silent = TRUE)
    if (!identical(yazildi, TRUE)) basarisiz <- c(basarisiz, paste0(ad, " (yazilamadi)"))
  }

  if (length(basarisiz)) {
    # KISMİ COMMIT: sahiplik listesi GÜNCELLENMEZ, böylece bir sonraki bootstrap
    # eski isimleri hâlâ kendi sahipliğinde görür ve temizleyebilir.
    return(list(ok = FALSE, names = yeni, failed = basarisiz))
  }

  assign(.PK_ASYNC_OWNED_NAMES_SLOT, yeni, envir = target)
  list(ok = TRUE, names = yeni, failed = character(0))
}

# ------------------------------------------------------------------------------
# ÜRETİLEN ARTIFACT KAYDI
# ------------------------------------------------------------------------------
# Terminal temizlik YOLLARI yalnızca `sonuc` üzerinden ERİŞİLEBİLEN dosyaları
# silebilir. Ancak `.pk_result_v2()` dışa aktarımı ürettikten HEMEN SONRA
# Durdur gelirse `list(type = "pk_stopped")` döner (yollar kaybolur) ve bir
# istisna `pk_async_pipeline_error`'a dönüşürken de aynı şey olur. Her iki
# durumda da büyük XLSX/CSV dosyaları işçinin kalıcı temp dizininde ÖKSÜZ
# kalırdı. Bu yüzden dosyalar ÜRETİLDİKLERİ anda kaydedilir.
#
# KAYIT İSTEK KAPSAMLIDIR (PR #703 incelemesi).
#
# `pk_artifact_track()` NORMAL çalışma zamanında da tanımlıdır, yani
# `MERGEN_PK_ASYNC=false` (varsayılan) iken ANA SHINY SÜRECİNDE de çalışıyordu.
# Serbest bırakma ise YALNIZCA `pk_async_run_analysis()` içindeydi: başarılı her
# SENKRON dışa aktarım yolunu süreç-global deftere ekliyor ve orada SONSUZA
# KADAR bırakıyordu. Sonuç iki yönlü kötüydü — defter sınırsız büyüyordu ve
# sonraki HERHANGİ bir `pk_artifact_discard_tracked()` çağrısı ÖNCEKİ başarılı
# isteklerin dosyalarını silebiliyordu.
#
# Artık kayıt yalnızca AÇIK BİR KAPSAM içinde tutulur. Kapsamı açan tek yer
# asenkron istek yürütücüsüdür; kapsam yokken `pk_artifact_track()` NO-OP'tur
# ve senkron dışa aktarımların yaşam döngüsü (oturum-sonu temizlik defteri)
# değişmeden kalır.
.pk_artifact_registry <- new.env(parent = emptyenv())
.pk_artifact_registry$paths <- character(0)
.pk_artifact_registry$scope <- NA_character_

#' İSTEK KAPSAMINI aç (yalnızca asenkron istek yürütücüsü çağırır)
pk_artifact_scope_begin <- function(scope_id = NULL) {
  kimlik <- tryCatch(as.character(scope_id %||% "")[1], error = function(e) "")
  if (is.null(kimlik) || is.na(kimlik) || !nzchar(kimlik)) kimlik <- "pk_request"
  # Önceki kapsamdan artakalan yollar yeni isteğe TAŞINMAZ.
  .pk_artifact_registry$paths <- character(0)
  .pk_artifact_registry$scope <- kimlik
  invisible(kimlik)
}

#' Kapsam AÇIK MI?
pk_artifact_scope_active <- function() {
  !is.na(.pk_artifact_registry$scope)
}

#' Üretilen artifact yollarını kaydet (YALNIZCA açık kapsamda)
pk_artifact_track <- function(paths) {
  if (!isTRUE(pk_artifact_scope_active())) return(invisible(character(0)))
  yollar <- tryCatch(as.character(paths %||% character(0)), error = .pk_async_chr0)
  yollar <- yollar[!is.na(yollar) & nzchar(yollar)]
  if (!length(yollar)) return(invisible(character(0)))
  .pk_artifact_registry$paths <- unique(c(.pk_artifact_registry$paths, yollar))
  invisible(.pk_artifact_registry$paths)
}

#' Kaydı SİLMEDEN boşalt ve KAPSAMI KAPAT (başarılı yolda sahiplik geçer)
pk_artifact_release_tracked <- function() {
  onceki <- .pk_artifact_registry$paths
  .pk_artifact_registry$paths <- character(0)
  .pk_artifact_registry$scope <- NA_character_
  invisible(onceki)
}

#' Kaydedilmiş artifact'leri SİL (her başarısız terminal yolda)
pk_artifact_discard_tracked <- function() {
  yollar <- pk_artifact_release_tracked()
  if (!length(yollar)) return(invisible(FALSE))

  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  # Her dışa aktarım KENDİ `run_*` dizinine yazar; boşalan dizin de kaldırılır.
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(TRUE)
}
