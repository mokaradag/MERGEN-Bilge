# R/library_queries.R
# Bu dosya T-SQL sorgularını ve Yetki sorgularını barındırır.

# ==============================================================================
# BÖLÜM 1: YETKİ SORGULARI (PERMISSION QUERIES)
# ==============================================================================
# Kullanıcıların yetkilerini (Hangi proje/EPS görebileceklerini) belirleyen sorgular.
# Lütfen ilgili T-SQL kodlarını tırnak içine yapıştırın.

# 1. PY (Proje Yöneticisi) Yetki Sorgusu
# Beklenen Sütunlar: KullaniciAdi, SicilNo, ProjeKodu
# Not: 'ProjeKodu' virgülle ayrılmış birden fazla değer içerebilir.
sql_permission_py <- "
SELECT 
    KullaniciAdi, 
    SicilNo, 
    ProjeKodu 
FROM 
    Your_PY_Permission_Table_Here
"

# 2. KY-P ve DIR-P (Program Yöneticileri) Yetki Sorgusu
# Beklenen Sütunlar: KullaniciAdi, SicilNo, EPSKodu, EPSTanimi
# Not: 'EPSKodu' virgülle ayrılmış birden fazla değer içerebilir.
sql_permission_eps <- "
SELECT 
    KullaniciAdi, 
    SicilNo, 
    EPSKodu,
    EPSTanimi
FROM 
    Your_EPS_Permission_Table_Here
"

# ==============================================================================
# BÖLÜM 2: ANALİZ SORGULARI KÜTÜPHANESİ (200 QUERIES)
# ==============================================================================
# Her bir sorguyu aşağıdaki formatta listeye ekleyin.
# rls_columns: Sorgu sonucunda dönen tablodaki sütun isimleridir. Eşleşme için gereklidir.
#   - masraf_yeri_col: MasrafYeriKodu filtresi uygulanacak sütun adı (yoksa NULL)
#   - proje_kodu_col: Proje bazlı yetki (PY) için filtre uygulanacak sütun adı (yoksa NULL)
#   - eps_kodu_col: EPS bazlı yetki (KY-P/DIR-P) için filtre uygulanacak sütun adı (yoksa NULL)
#
# pre_aggregated_columns: SQL sorgusunda zaten toplulaştırılmış (SUM/AVG/COUNT OVER
#   PARTITION BY gibi) sayısal sütunlar. Bu sütunlar birden fazla satırda tekrarlandığı
#   için R tarafından yeniden toplam/ortalama hesaplanmamalıdır.
#   AI bu sütunları yalnızca satır bazında yorumlamalı, istatistiksel özete dahil etmemelidir.
#   Örnek: pre_aggregated_columns = c("PartitionToplamı", "GrupOrtalaması")

query_library <- list(
  
  # ----------------------------------------------------------------------------
  # SORGU 1: Genel Proje KPI Listesi
  # ----------------------------------------------------------------------------
  list(
    id = "q001",
    name = "Genel Proje KPI Listesi",
    description = "Tüm projelerin anahtar performans göstergelerini listeler.",
    db_target = DB_TARGETS$PRIMARY, 
    sql_file = "sql_queries/q001_kpi.sql",
    
    date_columns = c("GuncellemeTarihi", "BaslangicTarihi", "BitisTarihi"),
    
    rls_columns = list(
      masraf_yeri_col = "MasrafYeri",
      proje_kodu_col = "ProjeKodu",
      eps_kodu_col = "ProgMdlKodu"
    )
  ),

  # ----------------------------------------------------------------------------
  # SORGU 2: Departman Bütçe Analizi
  # ----------------------------------------------------------------------------
  list(
    id = "q002",
    name = "Departman Bütçe Analizi",
    description = "Departman bazında bütçe özetlerini getirir.",
    
    # YENİ: İleride bu sorguyu 'Arşiv' veritabanına (Secondary) taşımak isterseniz:
    # db_target = DB_TARGETS$SECONDARY,
    db_target = DB_TARGETS$PRIMARY,
    
    # Hibrit yapı (Dosya yolu)
    sql_file = "sql_queries/q002_butce.sql",
    
    rls_columns = list(
      masraf_yeri_col = "MasrafYeriKodu",
      proje_kodu_col = NULL,
      eps_kodu_col = NULL
    )
  ),
  
  # ----------------------------------------------------------------------------
  # SORGU 3: Basit Test Sorgusu (Örnek)
  # ----------------------------------------------------------------------------
  list(
    id = "q003",
    name = "Basit Test",
    description = "Test amaçlı basit sorgu.",
    
    # YENİ: Hedef veritabanı
    db_target = DB_TARGETS$PRIMARY,
    
    # Direkt SQL kullanımı
    sql = "SELECT TOP 10 * FROM Tbl_Test",
	
	# Dosya için (www klasörü içindeki yol olmalı):
    info_file = "dosyalar/butce_kilavuzu.pdf", 
    
    # Web URL için:
    info_url = "https://wiki.sirket.com/prosedurler",
    
    rls_columns = list(
      masraf_yeri_col = NULL,
      proje_kodu_col = NULL,
      eps_kodu_col = NULL
    )
  ),
  
  # ... (Sorgu listesi içinde)
  list(
    id = "q_ornek_id",
    name = "Örnek Sorgu Adı",
    description = "...",
    db_target = "primary", 
    sql_file = "sql_queries/query.sql",
    
    disable_ai_filters = TRUE,

    rls_columns = list(
      masraf_yeri_col = "MasrafYeri",
      proje_kodu_col = "ProjeKodu"
    )
  ),
)