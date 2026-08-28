# ==============================================================================
# Dosya Yolu: tests/testthat/helper_pk_entity.R
# Açıklama: Faz 4 varlık çözümleme dosyalarının TEK bağımlılık zinciri.
#
#           Zincir dört ayrı test dosyasında tekrarlanıyordu; bir dosya
#           bölündüğünde dördü birden bozuluyor ve kaynak sırası dosyadan
#           dosyaya kayabiliyordu. Tek yer bunu engeller ve sıra çalışma
#           zamanı manifestiyle AYNI kalır.
#
#           Tamamen çevrimdışıdır: DB, LLM, tarayıcı, SSO, ağ veya gizli
#           değer GEREKMEZ.
# ==============================================================================

# Bağımlılık sırası R/config_source_manifest.R ile BİREBİR aynıdır.
PK_ENTITY_SOURCE_CHAIN <- c(
  "helpers_pk_config.R",
  "helpers_pk_text_turkish.R",
  "helpers_pk_entity_morph.R",
  "helpers_pk_entity_normalize.R",
  "helpers_pk_entity_mention.R",
  "helpers_pk_entity_alias.R",
  "helpers_pk_entity_score.R",
  "helpers_pk_entity_scan.R",
  "helpers_pk_entity_resolver.R",
  "helpers_pk_entity_history.R"
)

# Faz 4 çalışma zamanı dosyalarının TAM listesi (bağlam/bağlama katmanı DÂHİL).
#
# Bu vektörü gezen sözleşme testleri (saflık, motor bayrağı, katlama, manifest)
# yalnızca burada listelenen dosyalara bakar. Bağlam/ağaç/uygulama katmanı eksik
# bırakıldığında o dört dosyaya inen bir gerileme HİÇ denetlenmiyor ve suite
# yeşil kalıyordu.
PK_ENTITY_RUNTIME_FILES <- c(
  "helpers_pk_entity_morph.R",
  "helpers_pk_entity_normalize.R",
  "helpers_pk_entity_mention.R",
  "helpers_pk_entity_alias.R",
  "helpers_pk_entity_score.R",
  "helpers_pk_entity_scan.R",
  "helpers_pk_entity_resolver.R",
  "helpers_pk_entity_history.R",
  "helpers_pk_entity_context.R",
  "helpers_pk_entity_tree.R",
  "helpers_pk_entity_apply_leaf.R",
  "helpers_pk_entity_apply.R"
)

# SAF katman: Shiny/reactive/DB/ağ bağımlılığı TAŞIMAYAN Faz 4 dosyaları.
#
# `helpers_pk_entity_context.R` BİLEREK dışarıdadır: oturum bağlam deposu
# `session$userData` üzerinden çalışır ve saflık taramasına giremez. Ayrım iki
# vektörle yapılır ki yeni bir dosya sessizce "saf değil" sayılıp saflık
# taramasından DÜŞMESİN; sözleşme testi ikisi arasındaki farkın TAM OLARAK bu
# tek bağlam dosyası olduğunu ayrıca doğrular.
PK_ENTITY_PURE_FILES <- setdiff(
  PK_ENTITY_RUNTIME_FILES,
  "helpers_pk_entity_context.R"
)

pk_entity_source_chain_for_tests <- function(extra = character(0),
                                             env = globalenv()) {
  repo_root <- resolve_repo_root_for_tests()
  for (dosya in c(PK_ENTITY_SOURCE_CHAIN, extra)) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  invisible(TRUE)
}

# Test yerelinde eşikleri EZİP geri alan yardımcı.
#
# Dağıtım yapılandırmasından YALITIM: yalnızca test tarafından açıkça
# verilen değişkenler değil, aşağıda listelenen çözümleme anahtarlarının
# TAMAMI ve karşılık gelen `options()` girdileri kaydedilir/temizlenir.
# Aksi hâlde yapılandırılmış
# bir VM'de veya geliştirici checkout'unda ortamdaki `AMBIGUITY_MARGIN` /
# `MAX_CANDIDATES` değerleri dal davranışını değiştirir ve testler ya geçerli
# kodu düşürür ya da gerçek bir regresyonu maskeler.
PK_ENTITY_RESOLVE_ENV_KEYS <- c(
  "MERGEN_PK_RESOLVE_MIN_SCORE",
  "MERGEN_PK_RESOLVE_MULTI_SCORE",
  "MERGEN_PK_RESOLVE_AUTO_SCORE",
  "MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN",
  "MERGEN_PK_RESOLVE_MAX_CANDIDATES",
  "MERGEN_PK_RESOLVE_MAX_PHRASE_CHARS",
  "MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES",
  "MERGEN_PK_RESOLVE_ENABLED"
)

# ÜRETİM EŞLEMESİ kullanılır, `tolower()` DEĞİL.
#
# Bu paket Türkçe `LC_CTYPE` altında BİLEREK koşar; orada `tolower("MIN")`
# noktasız `mın` üretir ve `mergen.pk.resolve_mın_score` gibi GERÇEKTE VAR
# OLMAYAN bir option adı oluşur. Sonuç: `pk_entity_with_resolve_env()` gerçek
# option'ları ne temizler ne geri yükler; makine/dağıtım ayarları testlere
# sızar, yanlış başarısızlık üretir ya da gerçek bir regresyonu maskeler.
pk_entity_resolve_option_keys <- function() {
  if (exists("pk_config_option_key", mode = "function", inherits = TRUE)) {
    return(vapply(PK_ENTITY_RESOLVE_ENV_KEYS, pk_config_option_key,
                  character(1), USE.NAMES = FALSE))
  }
  # Üretim yardımcısı yüklenmemişse yerelden BAĞIMSIZ ASCII katlama uygulanır.
  paste0(
    "mergen.pk.",
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
           sub("^MERGEN_PK_", "", PK_ENTITY_RESOLVE_ENV_KEYS))
  )
}

# DOSYA SEVİYESİ TABAN YALITIMI.
#
# `pk_entity_with_resolve_env()` YALNIZCA sardığı çağrıyı korur; bir test
# dosyasındaki sarılmamış onlarca varsayılan-eşik çağrısı dağıtım değerlerini
# okumaya devam eder ve yapılandırılmış bir VM'de dal davranışı değişir.
# Bu yardımcı dosyanın TAMAMI için ortam VE `options()` basamaklarını temizler,
# `teardown_env()` üzerinden eski hâline döndürür. Dosya başında BİR KEZ
# çağrılır; sarmalayıcılar bunun üzerine çalışmaya devam eder.
pk_entity_isolate_resolve_config <- function() {
  env_keys <- PK_ENTITY_RESOLVE_ENV_KEYS
  opt_keys <- pk_entity_resolve_option_keys()

  eski_env <- Sys.getenv(env_keys, unset = NA_character_, names = TRUE)
  eski_opt <- lapply(opt_keys, function(k) getOption(k, default = NULL))
  names(eski_opt) <- opt_keys

  for (ad in env_keys) Sys.unsetenv(ad)
  bos <- vector("list", length(opt_keys))
  names(bos) <- opt_keys
  do.call(options, bos)

  # `withr` YOKKEN DE GERİ YÜKLEME ZORUNLUDUR (PR #705 incelemesi, P3).
  #
  # Temizleme yukarıda KOŞULSUZ yapılıyor, geri yükleme kancası ise yalnızca
  # `withr` kuruluysa kaydediliyordu. Paket kurulu değilse süreç, temizlenmiş
  # sekiz `MERGEN_PK_RESOLVE_*` ortam değişkeni ve eşleşen `mergen.pk.*`
  # seçenekleriyle DEVAM ediyor; sonraki dosyalar ve dağıtım yapılandırması bu
  # değerleri SESSİZCE kaybediyordu (hata da nedeninden çok uzakta çıkıyordu).
  .geri_yukle <- function() {
    for (ad in names(eski_env)) {
      if (is.na(eski_env[[ad]])) Sys.unsetenv(ad)
      else do.call(Sys.setenv, stats::setNames(list(eski_env[[ad]]), ad))
    }
    do.call(options, eski_opt)
  }

  if (requireNamespace("withr", quietly = TRUE)) {
    withr::defer(.geri_yukle(), envir = testthat::teardown_env())
  } else {
    # `testthat::teardown_env()` `withr` OLMADAN da bir ortamdır; `reg.finalizer`
    # süit sonunda (ya da en geç oturum kapanışında) geri yüklemeyi çalıştırır.
    reg.finalizer(testthat::teardown_env(), function(e) .geri_yukle(),
                  onexit = TRUE)
  }
  invisible(TRUE)
}

pk_entity_with_resolve_env <- function(vars = character(0), code) {
  env_keys <- PK_ENTITY_RESOLVE_ENV_KEYS
  opt_keys <- pk_entity_resolve_option_keys()

  eski_env <- Sys.getenv(env_keys, unset = NA_character_, names = TRUE)
  eski_opt <- lapply(opt_keys, function(k) getOption(k, default = NULL))
  names(eski_opt) <- opt_keys

  on.exit({
    for (ad in names(eski_env)) {
      if (is.na(eski_env[[ad]])) {
        Sys.unsetenv(ad)
      } else {
        do.call(Sys.setenv, stats::setNames(list(eski_env[[ad]]), ad))
      }
    }
    do.call(options, eski_opt)
  }, add = TRUE)

  # Önce TEMİZ bir taban: dağıtım değerleri hiçbir dala sızmasın.
  for (ad in env_keys) Sys.unsetenv(ad)
  bos <- vector("list", length(opt_keys))
  names(bos) <- opt_keys
  do.call(options, bos)

  if (length(vars)) do.call(Sys.setenv, as.list(vars))

  force(code)
}
