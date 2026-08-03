# ==============================================================================
# Dosya Yolu: R/library_query_meta.R
# Açıklama: İNSAN TARAFINDAN KÜRE EDİLEN sorgu metadata katmanı ve kararlı
#           yetenek (capability) kaydı. Master plan §5.1.
#
# BU DOSYA GIT'TE İZLENİR. Bu yüzden içine YALNIZCA şunlar girer:
#   * kararlı, anlamsal yetenek kimlikleri (sütun adı veya etiket DEĞİL),
#   * sentetik ya da dışa aktarımı açıkça onaylanmış alias eşlemeleri,
#   * makinenin çıkaramayacağı anlam alanları: grain, additive, unit,
#     percent_scale, primary_entity, intents, default_measures, row_cap ...
#
# BURAYA ASLA GİRMEYECEK OLANLAR:
#   * gerçek VM proje/program adları ve üretimden türetilmiş kanonik değerler
#     -> yalnızca gitignore'lu R/library_query_aliases_local.R içinde,
#   * üreticinin (generator) çıkardığı sütun envanteri
#     -> yalnızca gitignore'lu R/library_query_meta_local.R içinde.
#
# NEDEN `pk_query_meta` BOŞ:
#   Bu checkout'ta yalnızca 4 adet YER TUTUCU sorgu vardır (q001..q_ornek_id);
#   üretimde ~169 gerçek sorgu bulunur. Aynı id'ler için burada metadata
#   uydurmak, VM'deki GERÇEK sorguya uydurulmuş anlam bilgisi bağlamak
#   demektir. Bu, master plan §11'in "Never invent query metadata" kuralının
#   tam olarak yasakladığı şeydir. Gerçek metadata VM'de, Faz 3b üreticisiyle
#   ve insan küresyonuyla doldurulur.
# ==============================================================================

# ------------------------------------------------------------------------------
# YETENEK KAYDI (capability registry)
# ------------------------------------------------------------------------------
# Yetenek kimlikleri KARARLI ve ASCII'dir. Bunlar ne etikettir ne de sütun adı:
# "İşçilik" gibi bir etiket, `KalanIscilik_sa` gibi somut bir sütun ya da
# `iscilik` gibi uydurulmuş geniş bir jeton asla sözlüksel olarak
# karşılaştırılmaz. Seçim kapısı, planlanan işçilik ile kalan işçiliği ya da
# proje başlangıcı ile bitişini SQL'den ÖNCE bu kimlikler sayesinde ayırır.
#
# role: measure | dimension | date   (sütun `role` sözlüğünün anlamsal alt kümesi)
# unit: ölçüler için birim; boyut/tarih için NULL.
#
# Operatör yeni yetenek eklerken bu listeye girdi ekler. Kayıtta OLMAYAN bir
# yetenek kimliği başlangıçta HATA verir (fail-closed); sessizce kabul edilmez.
pk_capability_registry <- list(
  "labor.remaining_hours"   = list(role = "measure",    unit = "saat"),
  "labor.planned_hours"     = list(role = "measure",    unit = "saat"),
  "progress.completion_pct" = list(role = "measure",    unit = "%"),
  "dimension.resource"      = list(role = "dimension",  unit = NULL),
  "date.project_start"      = list(role = "date",       unit = NULL),
  "date.project_finish"     = list(role = "date",       unit = NULL)
)

# ------------------------------------------------------------------------------
# KÜRE EDİLMİŞ SORGU METADATA'SI
# ------------------------------------------------------------------------------
# Sorgu id -> metadata. Yukarıdaki gerekçeyle Git'te BİLİNÇLİ olarak boştur.
#
# Şablon (VM'de doldurulacak — master plan §5.1'deki "q042" örneği):
#
#   "q042" = list(
#     keywords         = c("rol", "atama", "görevlendirme"),
#     sample_questions = c("X projesinde kimler görevli?"),
#     intents          = c("kim_calisiyor"),
#     not_for          = c("bütçe", "maliyet"),
#     grain            = "activity_assignment",
#     grain_columns    = c("ProjeKodu", "AktiviteKodu", "KaynakKodu"),
#     primary_entity   = "ProjeAdi",
#     default_group_by = c("ProjeKodu"),
#     default_measures = c("KalanIscilik_sa"),
#     row_cap          = 50000L,
#     column_meta = list(
#       ProjeKodu = list(label = "Proje Kodu", role = "id",
#                        entity = "project", match = "exact"),
#       KalanIscilik_sa = list(label = "Kalan İşçilik", role = "measure",
#                        capability = "labor.remaining_hours",
#                        unit = "saat", decimals = 1, additive = TRUE)
#     )
#   )
#
# Alias eklenirken: izlenen bu dosyadaki her alias haritası
# `alias_provenance = "synthetic"` ya da `alias_provenance = "approved"`
# taşımak ZORUNDADIR. Üretimden gelen kanonik hedefler buraya değil,
# gitignore'lu R/library_query_aliases_local.R dosyasına yazılır.
pk_query_meta <- list()
