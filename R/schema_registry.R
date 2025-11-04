# R/schema_registry.R
# -------------------------------------------------------------
# Şema Kayıt Defteri: Uygulamanın ihtiyaç duyduğu kanonik alanlar
# ve kaynaklardaki gerçek sütun adları (varyantlar) burada tanımlanır.
# Bu dosyayı KENDİNİZE GÖRE DÜZENLEYİN. Uygulamadaki kodlar buraya bakar.
# -------------------------------------------------------------

# Tek bir ortam, diğer dosyalar bu ortamdan okur
SCHEMA <- new.env(parent = emptyenv())

# ---- Tür eşlemeleri (DuckDB cast'ları) ----
SCHEMA$TYPES <- list(
  ProjeAdi                 = "VARCHAR",
  ProjeKodu                = "VARCHAR",
  Yil                      = "INTEGER",
  Ay                       = "INTEGER",
  GerceklesenIscilik_sa    = "DOUBLE",
  KalanIscilik_sa          = "DOUBLE",
  ToplamIscilik_sa         = "DOUBLE",
  AktiviteBitis            = "DATE",
  TemelHatAktiviteBitis    = "DATE",
  KritikYolAktivitesi      = "VARCHAR",
  SicilNo                  = "VARCHAR",
  KaynakAdi                = "VARCHAR",
  Donem                    = "VARCHAR",
  Iscilik_sa               = "DOUBLE",
  ProjeDurumu              = "VARCHAR",
  Direktorluk              = "VARCHAR",
  MasrafYeri               = "VARCHAR",
  MasrafYeriKodu           = "VARCHAR",
  RolAdi                   = "VARCHAR",
  ProjeYoneticisi          = "VARCHAR",
  AktiviteBaslangic        = "DATE",
  Tarih                    = "DATE",
  DataDate                 = "DATE"
)
