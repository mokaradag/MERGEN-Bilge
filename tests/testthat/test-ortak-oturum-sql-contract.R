# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-sql-contract.R
# Açıklama: docs/sql/2026-07-ortak-oturumlar.sql ve rollback betiğinin yapısal
#           sözleşmesi: gerekli tablolar, idempotent guard'lar, Türkçe N'...'
#           iş kuralı değerleri, ana betikte yıkıcı ifade olmaması, rollback'in
#           yalnızca yeni ortak tabloları düşürmesi ve betiğin uygulama
#           açılışına BAĞLANMAMIŞ olması. Uygulamayı başlatmaz; DB gerekmez.
# ==============================================================================

# Windows/Türkçe yerel ayar güvenli bayt okuyucu (repo kuralı).
.oo_sql_oku <- function(yol) {
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- rawToChar(baytlar)
  iconv(metin, from = "UTF-8", to = "UTF-8", sub = "byte")
}

.oo_sql_tablolar <- c(
  "MB_OrtakOturumlar",
  "MB_OrtakOturum_Katilimcilar",
  "MB_OrtakOturum_Davetler",
  "MB_Kullanici_CanliDurum",
  "MB_Bildirimler",
  "MB_OrtakOturum_Mesajlar",
  "MB_OrtakOturum_YapayZekaKuyrugu",
  "MB_OrtakOturum_AktifUretimler",
  "MB_OrtakBilgeYolac_Oturumlar",
  "MB_OrtakBilgeYolac_Calistirmalar",
  "MB_OrtakOturum_Dosyalar",
  "MB_OrtakOturum_DosyaKopyalari",
  "MB_OrtakOturum_Olaylar"
)

test_that("ana SQL betiği gerekli tabloları idempotent guard'larla oluşturur", {
  repo_root <- resolve_repo_root_for_tests()
  yol <- file.path(repo_root, "docs", "sql", "2026-07-ortak-oturumlar.sql")
  expect_true(file.exists(yol))

  sql <- .oo_sql_oku(yol)

  for (tablo in .oo_sql_tablolar) {
    expect_true(
      grepl(paste0("CREATE TABLE dbo.", tablo), sql, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Tablo eksik: %s", tablo)
    )
    expect_true(
      grepl(sprintf("IF OBJECT_ID(N'dbo.%s', N'U') IS NULL", tablo), sql,
            fixed = TRUE, useBytes = TRUE),
      info = sprintf("Idempotent OBJECT_ID guard eksik: %s", tablo)
    )
  }

  # Operasyon güvenliği başlıkları.
  expect_true(grepl("SET XACT_ABORT ON", sql, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("SET LOCK_TIMEOUT 15000", sql, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("IF NOT EXISTS", sql, fixed = TRUE, useBytes = TRUE))

  # Ana betik yıkıcı ifade içermez.
  expect_false(grepl("DROP TABLE", sql, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("TRUNCATE", sql, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("DELETE FROM", sql, fixed = TRUE, useBytes = TRUE))
})

test_that("SQL betiği Türkçe iş kuralı değerlerini N'...' ile saklar", {
  repo_root <- resolve_repo_root_for_tests()
  sql <- .oo_sql_oku(file.path(repo_root, "docs", "sql", "2026-07-ortak-oturumlar.sql"))

  turkce_degerler <- c(
    "N'Sahip'", "N'Katılımcı'", "N'İzleyici'",
    "N'DavetEdildi'", "N'Katıldı'", "N'Reddetti'",
    "N'Aktif'", "N'Arşivlendi'", "N'Kapandı'",
    "N'OdaMesajı'", "N'YapayZekaSorusu'", "N'YapayZekaYanıtı'",
    "N'Katılımcılar'", "N'YapayZeka'",
    "N'Bekliyor'", "N'Çalışıyor'", "N'Tamamlandı'",
    "N'Üretildi'", "N'Kopyalandı'", "N'KullanıcıArşivledi'",
    "N'Çevrimİçi'", "N'Boşta'", "N'ÇevrimDışı'"
  )

  for (deger in turkce_degerler) {
    expect_true(
      grepl(enc2utf8(deger), sql, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Türkçe N'...' değeri eksik: %s", deger)
    )
  }

  # İngilizce iş kuralı değerleri SAKLANMAZ (kolon/kısıt adları hariç metin
  # sabiti olarak): tipik sızıntı kalıpları taranır.
  yasakli <- c("N'owner'", "N'editor'", "N'viewer'", "N'pending'",
               "N'accepted'", "N'completed'", "N'failed'", "N'archived'",
               "N'user'", "N'assistant'")
  for (deger in yasakli) {
    expect_false(
      grepl(deger, sql, fixed = TRUE, useBytes = TRUE),
      info = sprintf("İngilizce durum değeri betiğe sızmış: %s", deger)
    )
  }
})

test_that("rollback betiği yalnızca yeni ortak tabloları düşürür ve mevcutlara dokunmaz", {
  repo_root <- resolve_repo_root_for_tests()
  yol <- file.path(repo_root, "docs", "sql", "2026-07-ortak-oturumlar-rollback.sql")
  expect_true(file.exists(yol))

  sql <- .oo_sql_oku(yol)

  for (tablo in .oo_sql_tablolar) {
    expect_true(
      grepl(paste0("DROP TABLE dbo.", tablo), sql, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Rollback tablo düşürmesi eksik: %s", tablo)
    )
  }

  # Mevcut üretim tablolarına ASLA dokunulmaz.
  korunanlar <- c("MB_Chats", "MB_Messages", "MB_Feedback",
                  "MB_ClaudeCode_Sessions", "MB_ClaudeCode_Runs")
  for (tablo in korunanlar) {
    expect_false(
      grepl(paste0("DROP TABLE dbo.", tablo), sql, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Rollback mevcut tabloya dokunuyor: %s", tablo)
    )
  }

  # MB_Users guard: rollback MB_Users'ı hiçbir şekilde düşürmez/değiştirmez.
  expect_false(grepl("DROP TABLE dbo.MB_Users", sql, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("ALTER TABLE dbo.MB_Users", sql, fixed = TRUE, useBytes = TRUE))
})

test_that("SQL betikleri uygulama açılışına bağlanmamıştır (manuel DBA yolu)", {
  repo_root <- resolve_repo_root_for_tests()

  calisma_zamani <- c(
    "app.R", "global.R", "server.R",
    file.path("R", list.files(file.path(repo_root, "R"), pattern = "\\.R$"))
  )

  for (dosya in calisma_zamani) {
    tam_yol <- file.path(repo_root, dosya)
    if (!file.exists(tam_yol)) {
      next
    }

    icerik <- .oo_sql_oku(tam_yol)
    expect_false(
      grepl("2026-07-ortak-oturumlar.sql", icerik, fixed = TRUE, useBytes = TRUE) &&
        grepl("dbExecute", icerik, fixed = TRUE, useBytes = TRUE) &&
        grepl("readLines", icerik, fixed = TRUE, useBytes = TRUE),
      info = sprintf("SQL kurulum betiği çalışma zamanından çalıştırılıyor olabilir: %s", dosya)
    )
  }

  # DB katmanı tablo yokken güvenli düşer; DDL üretmez.
  db_katmani <- .oo_sql_oku(file.path(repo_root, "R", "helpers_ortak_oturum_db.R"))
  expect_false(grepl("CREATE TABLE", db_katmani, fixed = TRUE, useBytes = TRUE))
})
