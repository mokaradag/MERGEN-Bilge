# ==============================================================================
# Dosya Yolu: R/helpers_admin_geri_bildirim_queries.R
# Açıklama: Yönetici geri bildirim analizi modülü için SQL sorgu paketi ve
#           enjekte edilebilir veri çekim yardımcısı. Shiny reactive/observer
#           içermez; testlerde query_fn enjekte edilerek DB'ye dokunmadan
#           sözleşme doğrulanır.
# ==============================================================================

admin_gb_feedback_queries <- function() {
  list(
    tumu = "
      SELECT
        gb.GeriBildirimID, gb.UserID, u.KaynakAdi AS KullaniciAdi,
        gb.Memnuniyet, gb.NPS_Puan, gb.Etiketler,
        gb.EnCokSevilen, gb.Gelistirme, gb.IletisimIzni,
        gb.OlusturmaTarihi,
        dc.EmailAddress
      FROM MB_Destek_Geri_Bildirim gb
      LEFT JOIN MB_Users u ON gb.UserID = u.UserID
      LEFT JOIN DC01_userr dc ON u.KullaniciAdi = dc.Name
      ORDER BY gb.OlusturmaTarihi DESC
    ",

    toplam = "
      SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
    ",

    ort_memnuniyet = "
      SELECT AVG(CAST(Memnuniyet AS FLOAT)) as ort
      FROM MB_Destek_Geri_Bildirim
    ",

    memnuniyet_dagilim = "
      SELECT Memnuniyet, COUNT(*) as cnt
      FROM MB_Destek_Geri_Bildirim
      GROUP BY Memnuniyet
      ORDER BY Memnuniyet
    ",

    nps_dagilim = "
      SELECT
        SUM(CASE WHEN NPS_Puan >= 9 THEN 1 ELSE 0 END) as promoter,
        SUM(CASE WHEN NPS_Puan >= 7 AND NPS_Puan <= 8 THEN 1 ELSE 0 END) as passive,
        SUM(CASE WHEN NPS_Puan <= 6 THEN 1 ELSE 0 END) as detractor,
        COUNT(NPS_Puan) as toplam
      FROM MB_Destek_Geri_Bildirim
      WHERE NPS_Puan IS NOT NULL
    ",

    iletisim_izni = "
      SELECT
        SUM(CASE WHEN IletisimIzni = 1 THEN 1 ELSE 0 END) as izinli,
        COUNT(*) as toplam
      FROM MB_Destek_Geri_Bildirim
    ",

    gunluk_trend = "
      SELECT
        CAST(OlusturmaTarihi AS DATE) as tarih,
        COUNT(*) as cnt,
        AVG(CAST(Memnuniyet AS FLOAT)) as ort_memnuniyet
      FROM MB_Destek_Geri_Bildirim
      WHERE OlusturmaTarihi >= DATEADD(day, -30, GETDATE())
      GROUP BY CAST(OlusturmaTarihi AS DATE)
      ORDER BY tarih
    ",

    memnuniyet_trend = "
      SELECT
        DATEPART(ISO_WEEK, OlusturmaTarihi) as hafta,
        DATEPART(YEAR, OlusturmaTarihi) as yil,
        MIN(CAST(OlusturmaTarihi AS DATE)) as hafta_basi,
        AVG(CAST(Memnuniyet AS FLOAT)) as ort_memnuniyet,
        COUNT(*) as cnt
      FROM MB_Destek_Geri_Bildirim
      WHERE OlusturmaTarihi >= DATEADD(week, -12, GETDATE())
      GROUP BY DATEPART(ISO_WEEK, OlusturmaTarihi), DATEPART(YEAR, OlusturmaTarihi)
      ORDER BY yil, hafta
    ",

    nps_trend = "
      SELECT
        DATEPART(ISO_WEEK, OlusturmaTarihi) as hafta,
        DATEPART(YEAR, OlusturmaTarihi) as yil,
        MIN(CAST(OlusturmaTarihi AS DATE)) as hafta_basi,
        SUM(CASE WHEN NPS_Puan >= 9 THEN 1 ELSE 0 END) as promoter,
        SUM(CASE WHEN NPS_Puan >= 7 AND NPS_Puan <= 8 THEN 1 ELSE 0 END) as passive,
        SUM(CASE WHEN NPS_Puan <= 6 THEN 1 ELSE 0 END) as detractor,
        COUNT(NPS_Puan) as toplam
      FROM MB_Destek_Geri_Bildirim
      WHERE NPS_Puan IS NOT NULL AND OlusturmaTarihi >= DATEADD(week, -12, GETDATE())
      GROUP BY DATEPART(ISO_WEEK, OlusturmaTarihi), DATEPART(YEAR, OlusturmaTarihi)
      ORDER BY yil, hafta
    ",

    etiketler_ham = "
      SELECT Etiketler FROM MB_Destek_Geri_Bildirim
      WHERE Etiketler IS NOT NULL AND Etiketler <> ''
    ",

    bugun = "
      SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
      WHERE CAST(OlusturmaTarihi AS DATE) = CAST(GETDATE() AS DATE)
    ",

    bu_hafta = "
      SELECT COUNT(*) as cnt FROM MB_Destek_Geri_Bildirim
      WHERE OlusturmaTarihi >= DATEADD(day, -7, GETDATE())
    ",

    kullanici_memnuniyet = "
      SELECT
        u.KaynakAdi AS KullaniciAdi,
        COUNT(*) as bildirim_sayisi,
        AVG(CAST(gb.Memnuniyet AS FLOAT)) as ort_memnuniyet,
        AVG(CAST(gb.NPS_Puan AS FLOAT)) as ort_nps,
        MAX(gb.OlusturmaTarihi) as son_bildirim
      FROM MB_Destek_Geri_Bildirim gb
      LEFT JOIN MB_Users u ON gb.UserID = u.UserID
      GROUP BY gb.UserID, u.KaynakAdi
      ORDER BY bildirim_sayisi DESC
    ",

    nps_puan_dagilim = "
      SELECT NPS_Puan, COUNT(*) as cnt
      FROM MB_Destek_Geri_Bildirim
      WHERE NPS_Puan IS NOT NULL
      GROUP BY NPS_Puan
      ORDER BY NPS_Puan
    ",

    memnuniyet_nps_korelasyon = "
      SELECT Memnuniyet,
        AVG(CAST(NPS_Puan AS FLOAT)) as ort_nps,
        COUNT(*) as cnt
      FROM MB_Destek_Geri_Bildirim
      WHERE NPS_Puan IS NOT NULL
      GROUP BY Memnuniyet
      ORDER BY Memnuniyet
    "
  )
}

admin_gb_fetch_data <- function(query_fn = NULL) {
  if (is.null(query_fn)) {
    if (!exists("admin_safe_query", mode = "function", inherits = TRUE)) {
      stop("admin_gb_fetch_data için admin_safe_query bulunamadı.", call. = FALSE)
    }

    query_fn <- get("admin_safe_query", mode = "function", inherits = TRUE)
  }

  if (!is.function(query_fn)) {
    stop("query_fn bir fonksiyon olmalıdır.", call. = FALSE)
  }

  queries <- admin_gb_feedback_queries()
  result <- lapply(queries, function(sql) {
    query_fn(sql)
  })

  names(result) <- names(queries)
  result
}