# ==============================================================================
# Dosya Yolu: tests/testthat/helper_pk_selection.R
# Açıklama: Faz 5 (§5.2) sorgu seçimi dosyalarının TEK bağımlılık zinciri ve
#           ortam yalıtımı.
#
#           Faz 4'ün `helper_pk_entity.R` deseniyle aynıdır: zincir tek yerde
#           tutulur, böylece bir dosya bölündüğünde her test dosyası ayrı ayrı
#           bozulmaz ve kaynak sırası çalışma zamanı manifestiyle AYNI kalır.
#
#           Tamamen çevrimdışıdır: DB, LLM, tarayıcı, SSO, ağ veya gizli değer
#           GEREKMEZ.
# ==============================================================================

# Bağımlılık sırası R/config_source_manifest.R ile BİREBİR aynıdır.
PK_SELECT_SOURCE_CHAIN <- c(
  # `.pk_select_log_safe()` seçici tanılamalarını KAPALI BAŞARISIZ biçimde
  # `redact_sensitive_text()` üzerinden geçirir; redaktör yüklenmezse metin
  # yayımlanmaz. Üretimde temel katman bunu her zaman yükler, izole zincir de
  # aynı sınırı taşımalıdır.
  "utils_log_redact.R",
  "helpers_pk_config.R",
  # `pk_ascii_lower()` YALNIZCA bu dosyada tanımlıdır (PR #705 incelemesi, P3).
  # Zincirde olmayınca `helpers_pk_query_selection_history.R` izole testlerde
  # KENDİ yedek yoluna düşüyor ve üretim yardımcısındaki bir gerileme
  # denetlenmemiş kalıyordu. Üretim manifesti de onu Türkçe katlamadan ÖNCE
  # yükler.
  "helpers_pk_ascii_tokens.R",
  "helpers_pk_text_turkish.R",
  # `.pk_meta_is_scalar_text()` şema dosyasında tanımlıdır; erişimci ondan
  # ÖNCE yüklenirse yetenek doğrulaması çalışma zamanında patlar. Üretimde
  # manifest tamamı yüklediği için görünmez; izole zincirde görünür olmalıdır.
  "helpers_pk_query_meta_schema.R",
  "helpers_pk_query_meta_access.R",
  # Yetenek kayıt defterinin GERÇEK kaynağı. Yüklenmezse
  # `pk_select_capability_ids()` boş döner ve HER anlamsal iddia
  # `unknown_capability` olur; yani doğru davranış "kapalı başarısızlık"tır
  # ama izole zincir üretimden ayrışır. Manifestte `pk_query_metadata`
  # bölümünde bulunur.
  "library_query_meta.R",
  "helpers_pk_analysis_query_selection.R",
  # Seçici HTTP zaman aşımı tabanı: v1 ve v2 hatlarının ORTAK kaynağı ve
  # manifestte ikisinden de ÖNCE gelir. İzole zincirde eksikse
  # `pk_select_llm_invoke()` "could not find function" ile düşer.
  "helpers_pk_select_timeout.R",
  "helpers_pk_query_retrieval.R",
  "helpers_pk_query_selection_json.R",
  "helpers_pk_query_selection_config.R",
  # İstem sığdırma (Geçiş A merdiveni + Geçiş B sütun payı); yük kurucusundan
  # ÖNCE gelir, üretim manifestiyle aynı sıradır.
  "helpers_pk_query_selection_compact.R",
  "helpers_pk_query_selection_payload.R",
  "helpers_pk_query_selection_prompt.R",
  # Varlık ("var mı?") -> sayım yetenek iması; doğrulayıcı bunu çağırır.
  "helpers_pk_query_selection_canonical.R",
  "helpers_pk_query_selection_requirements.R",
  "helpers_pk_query_selection_parse.R",
  "helpers_pk_query_selection_decide.R",
  "helpers_pk_query_selection_degraded.R",
  "helpers_pk_query_selection_history.R",
  "helpers_pk_query_selection_session.R",
  "helpers_pk_query_selection_seed.R",
  "helpers_pk_query_selection_ai.R",
  "helpers_pk_query_selection_deep.R",
  "helpers_pk_query_selection_apply.R"
)

# Saf seçim çalışma zamanı dosyaları. Motor kipine bağlı derin-analiz köprüsü
# ayrı tutulur; saflık sözleşmesi yalnızca bu küme üzerinde çalışır.
PK_SELECT_RUNTIME_FILES <- c(
  "helpers_pk_select_timeout.R",
  "helpers_pk_query_retrieval.R",
  "helpers_pk_query_selection_json.R",
  "helpers_pk_query_selection_config.R",
  "helpers_pk_query_selection_compact.R",
  "helpers_pk_query_selection_payload.R",
  "helpers_pk_query_selection_prompt.R",
  "helpers_pk_query_selection_canonical.R",
  "helpers_pk_query_selection_requirements.R",
  "helpers_pk_query_selection_parse.R",
  "helpers_pk_query_selection_decide.R",
  "helpers_pk_query_selection_degraded.R",
  "helpers_pk_query_selection_history.R",
  "helpers_pk_query_selection_session.R",
  "helpers_pk_query_selection_seed.R",
  "helpers_pk_query_selection_ai.R",
  "helpers_pk_query_selection_apply.R"
)

PK_SELECT_ENGINE_BRIDGE_FILES <- c(
  "helpers_pk_query_selection_deep.R"
)

pk_select_source_chain_for_tests <- function(extra = character(0),
                                             env = globalenv()) {
  repo_root <- resolve_repo_root_for_tests()

  # `%||%` çalışma zamanı yardımcısıdır; izole zincirde tanımlı olmayabilir.
  if (!exists("%||%", mode = "function", envir = env, inherits = TRUE)) {
    assign("%||%", function(x, y) if (is.null(x)) y else x, envir = env)
  }

  for (dosya in c(PK_SELECT_SOURCE_CHAIN, extra)) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  invisible(TRUE)
}

# Seçim hattının OKUDUĞU tüm anahtarlar. Yalıtım, testte açıkça verilenlerle
# sınırlı DEĞİLDİR: yapılandırılmış bir VM'de ortamdaki bir `MIN_MARGIN`
# değeri dal davranışını değiştirir ve testler ya geçerli kodu düşürür ya da
# gerçek bir regresyonu maskeler.
PK_SELECT_ENV_KEYS <- c(
  "MERGEN_PK_SELECT_TIMEOUT_SEC",
  "MERGEN_PK_SELECT_RECALL_N",
  "MERGEN_PK_SELECT_MIN_CONFIDENCE",
  "MERGEN_PK_SELECT_MIN_MARGIN",
  "MERGEN_PK_SELECT_DISAGREE_PENALTY",
  "MERGEN_PK_SELECT_DESC_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_N",
  "MERGEN_PK_SELECT_HISTORY_TURNS",
  "MERGEN_PK_SELECT_NAME_CHARS",
  "MERGEN_PK_SELECT_KEYWORD_CHARS",
  "MERGEN_PK_SELECT_HISTORY_CHARS",
  "MERGEN_PK_SELECT_PASS_B_CHARS",
  "MERGEN_PK_SELECT_PASS_A_CHARS",
  # Yetenek eşleşmesi KATI kipi seçim kararını değiştirir; dağıtım değeri
  # testlere sızmamalıdır.
  "MERGEN_PK_REQUIRE_CAPABILITY_MATCH",
  "MERGEN_PK_ENGINE"
)

# Üretim anahtar kümesiyle EŞLEŞME zorunludur. `pk_config_resolve()` ortamı
# `options()` ÖNCESİNDE okur; listede eksik kalan tek bir anahtar dağıtım
# değerinin testlere sızmasına yeter (Geçiş A karakter bütçesi bu yüzden
# gözden kaçmıştı). Üretim listesi yüklüyse fark burada raporlanır.
pk_select_env_keys_gap <- function() {
  # ÜRETİM LİSTESİ YOKSA SESSİZCE "boşluk yok" DENMEZ: sözleşme testi bu değeri
  # "fark yok" sayıyor; sabit yeniden adlandırılır, kaldırılır ya da kaynak
  # zincirinden düşerse HİÇBİR karşılaştırma yapılmadan yeşil kalır ve yeni bir
  # `MERGEN_PK_SELECT_*` anahtarı dağıtım değerini testlere sızdırabilir.
  if (!exists(".PK_SELECT_CONFIG_KEYS", inherits = TRUE)) {
    return("<.PK_SELECT_CONFIG_KEYS yüklenmedi>")
  }
  setdiff(get(".PK_SELECT_CONFIG_KEYS", inherits = TRUE), PK_SELECT_ENV_KEYS)
}

# ÜRETİM eşlemesi kullanılır: `pk_config_option_key()` bilinçli olarak ASCII
# `chartr()` uygular, çünkü Türkçe Windows yerelinde `tolower("I")` noktasız
# `ı` üretir. Testte `tolower()` kullanmak, hedef VM'de `SELECT_TIMEOUT_SEC` /
# `ENGINE` anahtarlarının YANLIŞ option adıyla temizlenmesine ve ortamdaki
# `mergen.pk.*` ayarlarının testlere sızmasına yol açar.
pk_select_option_keys <- function() {
  if (exists("pk_config_option_key", mode = "function", inherits = TRUE)) {
    return(vapply(PK_SELECT_ENV_KEYS, pk_config_option_key, character(1), USE.NAMES = FALSE))
  }
  paste0("mergen.pk.", chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
                              sub("^MERGEN_PK_", "", PK_SELECT_ENV_KEYS)))
}

# Tek bir yapılandırma anahtarını TESTİN SÜRESİNCE sabitler.
#
# `pk_config_resolve()` ortamı `options()` ÖNCESİNDE okur; yapılandırılmış bir
# VM'de dağıtım değeri testin ölçtüğü dalı değiştirir. ÖLÇÜLDÜ:
# `MERGEN_PK_ALLOW_UNBOUNDED_LOB=TRUE` LOB reddetme dallarını, `MERGEN_PK_ENGINE=v2`
# ise v1 gövdesi sözleşmelerini düşürüyordu. `NULL` değer anahtarı temizler.
pk_test_pin_config <- function(key, value, env = parent.frame()) {
  key <- as.character(key)[1]
  opt <- if (exists("pk_config_option_key", mode = "function", inherits = TRUE)) {
    pk_config_option_key(key)
  } else {
    paste0("mergen.pk.", chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
                                sub("^MERGEN_PK_", "", key)))
  }

  eski_env <- Sys.getenv(key, unset = NA_character_)
  eski_opt <- getOption(opt, default = NULL)
  withr::defer({
    if (is.na(eski_env)) {
      Sys.unsetenv(key)
    } else {
      do.call(Sys.setenv, stats::setNames(list(eski_env), key))
    }
    do.call(options, stats::setNames(list(eski_opt), opt))
  }, envir = env)

  if (is.null(value)) {
    Sys.unsetenv(key)
  } else {
    do.call(Sys.setenv, stats::setNames(list(as.character(value)[1]), key))
  }
  do.call(options, stats::setNames(list(value), opt))
  invisible(TRUE)
}

pk_select_with_env <- function(vars = character(0), code) {
  # ANAHTAR KÜMESİ ÇAĞRININ AYARLADIKLARINI DA KAPSAR: yalnızca
  # `PK_SELECT_ENV_KEYS` anlık görüntülenip geri yüklenirken, listede OLMAYAN
  # bir anahtar (ör. `MERGEN_PK_RESOLVE_*`) blok bittikten sonra süreç
  # ortamında KALIYOR ve aynı testthat oturumundaki sonraki dosyalara sızıyordu.
  env_keys <- union(PK_SELECT_ENV_KEYS,
                    if (length(vars)) names(vars) else character(0))
  env_keys <- env_keys[!is.na(env_keys) & nzchar(env_keys)]
  opt_keys <- pk_select_option_keys()

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

  for (ad in env_keys) Sys.unsetenv(ad)
  bos <- vector("list", length(opt_keys))
  names(bos) <- opt_keys
  do.call(options, bos)

  if (length(vars)) do.call(Sys.setenv, as.list(vars))

  force(code)
}

# --- SENTETİK sorgu kütüphanesi -----------------------------------------------
# Hiçbir gerçek proje/program adı kullanılmaz (§7: taahhüt edilen fixture
# yalnızca sentetik olabilir). Ayırt edici terimler bilinçli olarak FARKLI
# alanlara dağıtılmıştır; böylece Geçiş A'nın hangi alanı gördüğü ölçülebilir.
pk_select_test_library <- function() {
  list(
    list(
      id = "q001",
      name = "Sentetik Bütçe Özeti",
      description = "Sentetik projelerin bütçe ve harcama durumunu listeler.",
      meta = list(
        keywords = c("bütçe", "harcama"),
        sample_questions = c("Sentetik projelerin bütçesi nedir?"),
        intents = c("butce_durumu"),
        column_meta = list(
          PlanlananIscilik_sa = list(
            label = "Planlanan İşçilik", role = "measure",
            capability = "labor.planned_hours", unit = "saat"
          ),
          BaslangicTarihi = list(
            label = "Başlangıç Tarihi", role = "date",
            capability = "date.project_start"
          ),
          ProjeAdi = list(label = "Proje Adı", role = "id", entity = "project")
        )
      )
    ),
    list(
      id = "q002",
      name = "Sentetik Kaynak Atama Listesi",
      description = "Aktivitelere atanmış sentetik kaynakları listeler.",
      meta = list(
        keywords = c("kaynak", "atama"),
        sample_questions = c("Sentetik projede kimler görevliydi?"),
        column_meta = list(
          KalanIscilik_sa = list(
            label = "Kalan İşçilik", role = "measure",
            capability = "labor.remaining_hours", unit = "saat"
          ),
          KaynakAdi = list(
            label = "Kaynak Adı", role = "dimension",
            capability = "dimension.resource"
          )
        )
      )
    ),
    list(
      id = "q003",
      name = "Sentetik Takvim Görünümü",
      description = "Sentetik projelerin başlangıç ve bitiş tarihlerini gösterir.",
      meta = list(
        keywords = c("takvim", "tarih"),
        # AYIRT EDİCİ TERİM YALNIZCA BURADA: Geçiş A örnek soruları
        # göremezse bu sorgu asla aday olamaz (§5.2 açık uyarısı).
        sample_questions = c("Hangi sentetik işler ertelendi?"),
        column_meta = list(
          BitisTarihi = list(
            label = "Bitiş Tarihi", role = "date",
            capability = "date.project_finish"
          )
        )
      )
    ),
    list(
      id = "q004",
      name = "Sentetik İlerleme Yüzdesi",
      description = "Sentetik aktivitelerin tamamlanma yüzdesini raporlar.",
      meta = list(
        keywords = c("ilerleme", "tamamlanma"),
        sample_questions = c("Sentetik aktivitelerin ilerlemesi ne durumda?")
      )
    )
  )
}

# Sentetik yetenek kayıt defteri (R/library_query_meta.R ile aynı kimlikler).
pk_select_test_registry <- function() {
  list(
    "labor.remaining_hours"   = list(role = "measure",   unit = "saat"),
    "labor.planned_hours"     = list(role = "measure",   unit = "saat"),
    "progress.completion_pct" = list(role = "measure",   unit = "%"),
    "dimension.resource"      = list(role = "dimension", unit = NULL),
    "date.project_start"      = list(role = "date",      unit = NULL),
    "date.project_finish"     = list(role = "date",      unit = NULL)
  )
}

# --- Sahte (stub) LLM ---------------------------------------------------------
# Sırayla verilen cevapları döndürür ve GÖNDERİLEN istemleri kaydeder; böylece
# "Geçiş A kaç aday istedi", "Geçiş B'ye kaç aday gitti", "onarım denemesi ayrı
# bir istem mi" gibi sözleşmeler ÖLÇÜLEBİLİR.
pk_select_stub_llm <- function(responses) {
  kayit <- new.env(parent = emptyenv())
  kayit$calls <- list()
  kayit$i <- 0L

  fn <- function(messages, settings) {
    kayit$i <- kayit$i + 1L
    # Geçmiş artık SİSTEM mesajına gömülmez (istem enjeksiyonu sınırı); mesaj
    # dizisi `system -> bağlam/onarım -> kullanıcı` şeklindedir. Kayıt bu yüzden
    # ilk SİSTEM mesajını ve SON mesajı (gerçek istek) tutar.
    kayit$calls[[kayit$i]] <- list(
      system = messages[[1]]$content,
      user = messages[[length(messages)]]$content,
      messages = messages,
      settings = settings
    )

    if (kayit$i > length(responses)) return(list(content = "{}"))

    cevap <- responses[[kayit$i]]
    if (inherits(cevap, "condition")) stop(cevap)
    if (is.character(cevap) && length(cevap) == 1L && identical(cevap, "__TIMEOUT__")) {
      stop("Timeout was reached: operation timed out")
    }
    list(content = cevap)
  }

  list(fn = fn, log = kayit)
}
