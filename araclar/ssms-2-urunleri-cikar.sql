USE UNSALDB;

SELECT
  LTRIM(RTRIM(b.BARCODE))                              AS barkod,
  LTRIM(RTRIM(s.MALINCINSI))                           AS ad,
  CAST(CASE WHEN b.SATISFIYATI1 > 0 THEN b.SATISFIYATI1
            ELSE b.SATISFIYATI END AS decimal(18,2))   AS fiyat,
  LTRIM(RTRIM(b.BIRIMADI))                             AS birim,
  LTRIM(RTRIM(CAST(b.PLU AS varchar(30))))             AS plu
FROM dbo.F0101TBLBIRIMLEREX b
JOIN dbo.F0101TBLSTOKLAR s ON s.STOKNO = b.STOKNO
WHERE LTRIM(RTRIM(ISNULL(s.MALINCINSI, ''))) <> ''
  AND (s.DELETED IS NULL OR s.DELETED = 0)
  AND (s.IPTAL   IS NULL OR s.IPTAL   = 0)
  AND (s.STOKTIPI IS NULL OR s.STOKTIPI <> 5)
ORDER BY ad;
