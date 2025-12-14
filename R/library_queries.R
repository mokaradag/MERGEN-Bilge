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

query_library <- list(
  
  # ÖRNEK SORGU 1
  list(
    id = "q001",
    name = "Genel Proje KPI Listesi",
    description = "Tüm projelerin anahtar performans göstergelerini (KPI) ve genel durumlarını listeler. Proje durumu, ilerleme yüzdesi gibi veriler içerir.",
    sql = "
      SELECT 
        ProjeKodu,
        ProjeAdi,
        MasrafYeri,
        ProgMdlKodu,
        Durum,
        TamamlanmaYuzdesi
      FROM 
        TB_Proje_Ozet_Tablosu
    ",
    # Bu sorgunun sonucundaki sütun isimleri RLS için şunlara karşılık gelir:
    rls_columns = list(
      masraf_yeri_col = "MasrafYeri",  # Tabloda departman kodu hangi sütunda?
      proje_kodu_col = "ProjeKodu",    # Tabloda proje kodu hangi sütunda?
      eps_kodu_col = "ProgMdlKodu"     # Tabloda EPS kodu hangi sütunda?
    )
  ),

  # ÖRNEK SORGU 2 (Buraya kendi sorgularınızı ekleyin...)
  list(
    id = "q002",
    name = "Departman Bütçe Analizi",
    description = "Departman bazında bütçe gerçekleşme oranlarını getirir.",
    sql = "
      SELECT * FROM TB_Butce_Analiz_View
    ",
    rls_columns = list(
      masraf_yeri_col = "MasrafYeriKodu",
      proje_kodu_col = NULL, # Bu sorguda proje detayı yok
      eps_kodu_col = NULL
    )
  )
  
  # Yeni sorguları buraya virgül koyarak ekleyebilirsiniz...
)