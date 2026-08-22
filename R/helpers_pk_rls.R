# ==============================================================================
# Dosya Yolu: R/helpers_pk_rls.R
# Açıklama: Proje ve Kaynak Analizi satır düzeyi güvenlik (RLS) kararları —
#           KAPALI BAŞARISIZ (fail-closed) (D6 / D6b).
#
#           Eski davranış iki ayrı delik içeriyordu:
#             D6  — beyan edilen RLS sütunu sonuç kümesinde yoksa predikat
#                   SESSİZCE atlanıyor, kullanıcı TÜM satırları görüyordu.
#             D6b — PY / KY-P / DIR-P rollerinde izin sorgusu hata verdiğinde
#                   VEYA kullanıcı izin tablosunda hiç bulunmadığında kapsam
#                   NULL kalıyor ve predikat yine SESSİZCE atlanıyordu. İkincisi
#                   geçici değil KALICI bir delikti.
#
#           Bu dosya kararı saf olarak üretir; veri filtrelemesi ve hata
#           yükseltmesi helpers_pk_analysis_security_summary.R içinde kalır.
#           Karar KOŞULSUZDUR: master plan §10 uyarınca güvenlik düzeltmesi
#           MERGEN_PK_ENGINE bayrağının arkasına saklanamaz.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur.
# ==============================================================================

# Kapsam ima eden roller. Bu rollerde kapsam çözülemeden hiçbir predikat
# atlanamaz.
PK_RLS_SCOPED_ROLES <- c("PY", "KY-P", "DIR-P")

# Kapsam durumları. "not_applicable" = rol bu kapsamı hiç ima etmiyor.
PK_RLS_SCOPE_STATES <- c("not_applicable", "available", "empty", "unavailable")

#' Yetkilendirme kodu için asgari normalleştirme
#'
#' `pk_tr_fold()` BİLEREK kullanılmaz. O boru hattı ekleri/iyelik takılarını
#' atar ve noktalama daraltır; bu bir proje ADINI eşleştirmek için doğru, bir
#' yetkilendirme KODU için tehlikelidir: yalnızca noktalama veya ek benzeri bir
#' sonla ayrılan iki farklı MasrafYeriKodu/EPSKodu aynı anahtara çökebilir ve
#' kullanıcı kapsamı dışındaki satırları görebilir.
#'
#' Burada yapılanlar yalnızca: UTF-8'e sabitleme, NFC birleştirme ve baş/son
#' boşluk kırpma. Büyük/küçük harf dönüşümü YOKTUR (Türkçe I/İ eşlemesi
#' kodlarda anlam değiştirebilir), ek/noktalama işlemi YOKTUR.
pk_rls_code_norm <- function(x) {
  if (is.null(x)) return(character(0))

  out <- as.character(x)
  out <- enc2utf8(out)

  if (requireNamespace("stringi", quietly = TRUE)) {
    out <- stringi::stri_trans_nfc(out)
  }

  trimws(out)
}

# Anlamsız varyasyonları eleyen REFERANS normalleştirme. Yalnızca baş/son
# boşluk ve Unicode kanonik birleştirme; bunlar aynı kodun farklı yazımlarıdır.
.pk_rls_reference_key <- function(x) {
  out <- enc2utf8(as.character(x))
  if (requireNamespace("stringi", quietly = TRUE)) {
    out <- stringi::stri_trans_nfc(out)
  }
  trimws(out)
}

#' Yetkilendirme kodu kümesinde çakışma olmadığını doğrula
#'
#' İki FARKLI kod aynı normalleştirilmiş anahtara düşerse bu bir birleştirme
#' değil, SERT HATADIR: kapsamı sessizce genişletebilir.
#'
#' "Farklı kod" tanımı REFERANS anahtara göredir: yalnızca boşluk veya Unicode
#' yazım farkı taşıyan iki değer AYNI koddur ve çakışma sayılmaz. Bugünkü
#' asgari `pk_rls_code_norm()` ile çakışma üretmek mümkün değildir; bu muhafaza
#' tam da normalleştirme İLERİDE gevşetilirse (büyük/küçük harf katlama, ek
#' atma, noktalama daraltma) devreye girmesi için vardır.
#'
#' @return list(ok, collisions)
pk_rls_assert_code_keys <- function(codes) {
  ham <- as.character(codes %||% character(0))
  ham <- ham[!is.na(ham) & nzchar(trimws(ham))]
  if (!length(ham)) return(list(ok = TRUE, collisions = character(0)))

  referans <- .pk_rls_reference_key(ham)
  anahtar <- pk_rls_code_norm(ham)
  cakisan <- character(0)

  for (key in unique(anahtar)) {
    farkli <- unique(referans[anahtar == key])
    if (length(farkli) > 1L) {
      cakisan <- c(cakisan, sprintf("%s -> %s", key, paste(farkli, collapse = " | ")))
    }
  }

  list(ok = !length(cakisan), collisions = cakisan)
}

#' Bir kapsam vektörünün durumunu belirle
#'
#' `state` çağıran tarafından açıkça verilebilir (get_user_rls_info bunu yapar).
#' Verilmediğinde GERİYE DÖNÜK GÜVENLİ varsayım uygulanır: kapsam NULL ise
#' "unavailable" kabul edilir. Böylece durum alanını taşımayan eski bir çağrı
#' yolu kazara "filtre yok" davranışına düşemez.
pk_rls_scope_state <- function(values, declared_state = NULL, applicable = TRUE) {
  if (!isTRUE(applicable)) return("not_applicable")

  if (!is.null(declared_state)) {
    durum <- as.character(declared_state)[1]
    if (!is.na(durum) && durum %in% PK_RLS_SCOPE_STATES) return(durum)
  }

  if (is.null(values)) return("unavailable")

  temiz <- pk_rls_code_norm(values)
  temiz <- temiz[!is.na(temiz) & nzchar(temiz)]
  if (!length(temiz)) return("empty")

  "available"
}

# Bir kapsam boyutunu değerlendirir ve plana katkısını döndürür.
.pk_rls_scope_step <- function(values, declared_state, applicable, column, actual_columns, label) {
  durum <- pk_rls_scope_state(values, declared_state, applicable)

  if (identical(durum, "not_applicable")) {
    # ETİKET KORUNUR: `pk_rls_plan()` durum haritasını `adim$label %||% "?"`
    # ile anahtarlar. Etiketsiz dönüş, uygulanamayan TÜM boyutları paylaşılan
    # `"?"` anahtarına yazıyor ve `plan$states$proje` gibi alanlar NULL kalıyordu.
    return(list(state = durum, label = label))
  }

  if (identical(durum, "unavailable")) {
    return(list(state = durum, abort = TRUE, reason = "scope_unavailable", label = label))
  }

  if (identical(durum, "empty")) {
    # İzin tablosunda hiç satırı olmayan kapsamlı kullanıcı SIFIR satır görür;
    # ASLA tüm satırlar değil.
    return(list(state = durum, zero_rows = TRUE, label = label))
  }

  sutun <- if (is.null(column)) NA_character_ else as.character(column)[1]
  if (is.na(sutun) || !nzchar(trimws(sutun))) {
    # UYGULANAMAYAN KAPSAM ARTIK KAPALI BAŞARISIZDIR.
    #
    # Eskiden bu dal yalnızca `unenforced` işaretini kaldırıyor ve çağıran
    # taraf bir `cat()` uyarısı yazıp DEVAM EDİYORDU. Sonuç, yetki sistemi
    # kullanıcı için bir kapsam ÇÖZMÜŞken (yani kısıtlı bir kullanıcıyken) o
    # boyutta HİÇBİR kısıt uygulanmadan satır döndürmekti; kısıtlı kullanıcı
    # kapsamı dışındaki kayıtları görebiliyordu. Bir yetkilendirme sınırının
    # "beyan edilmemiş" olması, o sınırın YOK sayılması anlamına gelemez.
    #
    # `not_applicable` ve `empty` durumları bu dala GELMEZ: rol için kısıt
    # tanımlı değilse zaten yukarıda dönülür, izin tablosu boşsa sıfır satır
    # verilir. Buraya yalnızca ÇÖZÜLMÜŞ ama uygulanamayan kapsam düşer.
    return(list(
      state = durum, abort = TRUE, reason = "unenforceable_column",
      unenforced = TRUE, label = label
    ))
  }

  sutun <- trimws(sutun)
  if (!(sutun %in% actual_columns)) {
    # D6: beyan edilen sütun sonuçta yok -> ATLAMA, DURDUR.
    return(list(
      state = durum, abort = TRUE, reason = "missing_column",
      label = label, column = sutun
    ))
  }

  kodlar <- pk_rls_code_norm(values)
  kodlar <- unique(kodlar[!is.na(kodlar) & nzchar(kodlar)])

  cakisma <- pk_rls_assert_code_keys(values)
  if (!isTRUE(cakisma$ok)) {
    return(list(
      state = durum, abort = TRUE, reason = "code_collision",
      label = label, column = sutun, collisions = cakisma$collisions
    ))
  }

  list(state = durum, predicate = list(column = sutun, values = kodlar), label = label)
}

#' RLS uygulama planını üret (saf karar katmanı)
#'
#' @param user_info `get_user_rls_info()` çıktısı.
#' @param rls_cols Sorgunun `rls_columns` beyanı.
#' @param actual_columns Gerçek sonuç kümesinin sütun adları.
#' @return list(ok, abort, reason, detail, admin, zero_rows, predicates, unenforced, states)
pk_rls_plan <- function(user_info, rls_cols, actual_columns) {
  user_info <- if (is.list(user_info)) user_info else list()
  actual_columns <- as.character(actual_columns %||% character(0))
  actual_columns <- trimws(actual_columns[!is.na(actual_columns)])

  # DİKKAT: burada `utils::modifyList()` KULLANILMAZ. O, liste değerli alanları
  # ada göre ÖZYİNELEMELİ birleştirir; `predicates` gibi ADSIZ listeler
  # sessizce düşer ve plan boş predikatla döner (Faz 0 kaydındaki D9 tuzağının
  # aynısı). Düz atama kullanılır.
  bos_plan <- function(...) {
    temel <- list(
      ok = TRUE, abort = FALSE, reason = NA_character_, detail = NA_character_,
      admin = FALSE, zero_rows = FALSE, predicates = list(),
      unenforced = character(0), states = list()
    )
    ust <- list(...)
    if (length(ust) > 0) temel[names(ust)] <- ust
    temel
  }

  yetki_ham <- user_info$Yetki
  yetki <- if (is.null(yetki_ham) || length(yetki_ham) == 0L) NA_character_ else as.character(yetki_ham)[1]

  # D6 ek: Yetki NA/boş iken eski kod `yetki == "ADMIN"` ile HATA veriyordu.
  # Artık temiz ve kapalı başarısız bir karara dönüşür.
  if (is.na(yetki) || !nzchar(trimws(yetki))) {
    return(bos_plan(
      ok = FALSE, abort = TRUE, reason = "missing_role",
      detail = "Kullanici yetki tipi (Yetki) cozulemedi."
    ))
  }

  yetki <- trimws(yetki)

  if (identical(yetki, "ADMIN")) {
    return(bos_plan(admin = TRUE, states = list(role = yetki)))
  }

  rls_cols <- if (is.list(rls_cols)) rls_cols else list()

  # DEPARTMAN KAPSAMININ UYGULANABİLİRLİĞİ (PR #705, P1).
  #
  # `allowed_depts = NULL` İKİ AYRI durumdan gelir: (a) MasrafYeriKodu "ADMIN"
  # olduğu için departman kısıtı BİLEREK yok, (b) kapsam ÇÖZÜLEMEDİ. Eski
  # `applicable = !is.null(allowed_depts)` ifadesi ikisini de "kısıt yok"
  # sayıyordu; kapsamı çözülemeyen KISITLI bir kullanıcı, başka daraltıcı
  # kapsamı olmadığında TÜM satırları görebiliyordu.
  #
  # Artık BEYAN EDİLEN durum belirleyicidir. Beyan yoksa (yalnızca eski/sentetik
  # çağrılar) `pk_rls_scope_state()`in belgelenmiş GERİYE DÖNÜK GÜVENLİ
  # varsayımı devreye girer: NULL kapsam "unavailable" sayılır ve plan DURUR.
  # "ADMIN departman kapsamı" iddiası artık AÇIKÇA beyan edilmelidir.
  dept_state_ham <- user_info$scope_state_depts
  dept_beyan_var <- is.character(dept_state_ham) && length(dept_state_ham) >= 1L &&
    !is.na(dept_state_ham[1]) && nzchar(trimws(dept_state_ham[1]))
  dept_uygulanabilir <- if (dept_beyan_var) {
    !identical(trimws(dept_state_ham[1]), "not_applicable")
  } else {
    TRUE
  }

  adimlar <- list(
    .pk_rls_scope_step(
      values = user_info$allowed_depts,
      declared_state = user_info$scope_state_depts,
      applicable = dept_uygulanabilir,
      column = rls_cols$masraf_yeri_col,
      actual_columns = actual_columns,
      label = "masraf_yeri"
    ),
    .pk_rls_scope_step(
      values = user_info$allowed_projects,
      declared_state = user_info$scope_state_projects,
      applicable = identical(yetki, "PY"),
      column = rls_cols$proje_kodu_col,
      actual_columns = actual_columns,
      label = "proje"
    ),
    .pk_rls_scope_step(
      values = user_info$allowed_eps,
      declared_state = user_info$scope_state_eps,
      applicable = yetki %in% c("KY-P", "DIR-P"),
      column = rls_cols$eps_kodu_col,
      actual_columns = actual_columns,
      label = "eps"
    )
  )

  durumlar <- list(role = yetki)
  predikatlar <- list()
  uygulanamayan <- character(0)
  sifir_satir <- FALSE

  for (adim in adimlar) {
    durumlar[[adim$label %||% "?"]] <- adim$state
    if (identical(adim$state, "not_applicable")) next

    if (isTRUE(adim$abort)) {
      ayrinti <- switch(
        adim$reason,
        missing_column = sprintf(
          "Beyan edilen RLS sutunu sonuc kumesinde yok: %s (%s).",
          adim$column %||% "?", adim$label %||% "?"
        ),
        scope_unavailable = sprintf(
          "Yetki kapsami cozulemedi (%s); izin sorgusu basarisiz.", adim$label %||% "?"
        ),
        code_collision = sprintf(
          "Farkli yetkilendirme kodlari ayni anahtara cokuyor (%s): %s",
          adim$label %||% "?", paste(adim$collisions, collapse = "; ")
        ),
        unenforceable_column = sprintf(
          "Kullanici icin cozulmus yetki kapsami var ama sorgu bu boyut icin sutun beyan etmiyor (%s); kisit uygulanamaz.",
          adim$label %||% "?"
        ),
        sprintf("RLS plani uretilemedi (%s).", adim$label %||% "?")
      )

      return(bos_plan(
        ok = FALSE, abort = TRUE, reason = adim$reason, detail = ayrinti,
        states = durumlar
      ))
    }

    if (isTRUE(adim$zero_rows)) sifir_satir <- TRUE
    if (isTRUE(adim$unenforced)) uygulanamayan <- c(uygulanamayan, adim$label)
    if (!is.null(adim$predicate)) predikatlar[[length(predikatlar) + 1L]] <- adim$predicate
  }

  bos_plan(
    zero_rows = sifir_satir,
    predicates = predikatlar,
    unenforced = uygulanamayan,
    states = durumlar
  )
}

# Kullanıcıya gösterilen mesajlar: iç ayrıntı (sütun adı, kod, DSN) taşımaz ve
# kapsamlı kullanıcıya kapsamı dışında satır olup olmadığını söylemez.
PK_RLS_ABORT_USER_MESSAGE <- paste0(
  "\U000026A0\U0000FE0F **Yetki Doğrulaması Başarısız:** Bu sorgu için satır ",
  "düzeyi yetki kuralları güvenli biçimde uygulanamadı, bu nedenle analiz ",
  "durduruldu. Sorgu yapılandırması gözden geçirilene kadar veri gösterilmez. ",
  "Lütfen sistem yöneticisiyle iletişime geçin."
)

#' İstek anı gerçek-sütun kapısı (Faz 3a M8 bağlantısı)
#'
#' Faz 3a `pk_meta_validate_actual_columns()` fonksiyonunu yazdı ve test etti
#' ama BİLEREK bağlamadı; bağlama işi Faz 1'e bırakılmıştı. Kapı burada
#' bağlanır ve iki ayrı verdikt üretir:
#'
#'   * `fail_closed = TRUE` (beyan edilen RLS sütunu sonuçta yok / geçersiz /
#'     mükerrer) -> KOŞULSUZ durdurma. Bu bir güvenlik verdiktidir ve motor
#'     bayrağının arkasına saklanamaz.
#'   * yalnızca RLS DIŞI metadata sütunu eşleşmiyor -> v2'de durdurma, v1'de
#'     yalnızca uyarı. v1 metadata'yı hiçbir karar için kullanmadığından onu
#'     bu yüzden durdurmak §10'un dört çapraz-motor maddesi dışında bir
#'     davranış değişikliği olurdu.
#'
#' @return list(abort, engine_abort, warn, result)
pk_meta_actual_column_gate <- function(query, actual_columns, engine_is_v2 = FALSE) {
  bos <- list(abort = FALSE, engine_abort = FALSE, warn = character(0), result = NULL)

  if (!exists("pk_meta_validate_actual_columns", mode = "function", inherits = TRUE)) {
    return(bos)
  }

  # Doğrulayıcı hatası SESSİZCE yutulmaz. Kapı burada bilerek açık kalır
  # (asıl fail-closed karar `pk_rls_plan()` içindedir ve beyan edilen RLS
  # sütunu eksikse zaten durdurur) ama gerekçe operatör loguna taşınır;
  # aksi halde metadata katmanındaki bir bozukluk hiçbir iz bırakmazdı.
  dogrulama_hatasi <- NULL
  sonuc <- tryCatch(
    pk_meta_validate_actual_columns(query, actual_columns),
    error = function(e) {
      dogrulama_hatasi <<- conditionMessage(e)
      NULL
    }
  )
  if (!is.list(sonuc)) {
    if (!is.null(dogrulama_hatasi)) {
      bos$warn <- sprintf(
        "Metadata sutun dogrulayicisi calistirilamadi: %s", dogrulama_hatasi
      )
    }
    return(bos)
  }

  list(
    abort = isTRUE(sonuc$fail_closed),
    engine_abort = isTRUE(engine_is_v2) && !isTRUE(sonuc$ok) && !isTRUE(sonuc$fail_closed),
    warn = as.character(sonuc$errors %||% character(0)),
    result = sonuc
  )
}

#' Kapalı başarısız RLS hatasını sınıflandırılmış koşul olarak yükselt
pk_rls_stop <- function(plan, context_label = "PK_ANALIZ") {
  try(
    cat(sprintf(
      "[%s] RLS KAPALI BASARISIZ | gerekce=%s | ayrinti=%s\n",
      context_label, plan$reason %||% "?", plan$detail %||% "?"
    )),
    silent = TRUE
  )

  kosul <- structure(
    class = c("pk_rls_error", "error", "condition"),
    list(
      message = PK_RLS_ABORT_USER_MESSAGE,
      call = NULL,
      reason = plan$reason %||% NA_character_,
      detail = plan$detail %||% NA_character_
    )
  )

  stop(kosul)
}
