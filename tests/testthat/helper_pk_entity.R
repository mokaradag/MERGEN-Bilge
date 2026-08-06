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

# Faz 4 çalışma zamanı dosyalarının tam listesi (bağlama katmanı dâhil).
PK_ENTITY_RUNTIME_FILES <- c(
  "helpers_pk_entity_morph.R",
  "helpers_pk_entity_normalize.R",
  "helpers_pk_entity_mention.R",
  "helpers_pk_entity_alias.R",
  "helpers_pk_entity_score.R",
  "helpers_pk_entity_scan.R",
  "helpers_pk_entity_resolver.R",
  "helpers_pk_entity_history.R"
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
# verilen değişkenler değil, BEŞ çözümleme anahtarının TAMAMI ve karşılık
# gelen `options()` girdileri kaydedilir/temizlenir. Aksi hâlde yapılandırılmış
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

pk_entity_resolve_option_keys <- function() {
  paste0(
    "mergen.pk.",
    tolower(sub("^MERGEN_PK_", "", PK_ENTITY_RESOLVE_ENV_KEYS))
  )
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
