USE UNSALDB;
SET NOCOUNT ON;

SELECT
  CASE WHEN x.kod <> '' AND x.kod NOT LIKE '%[^0-9]%' THEN x.kod ELSE '' END AS barkod,
  REPLACE(REPLACE(REPLACE(x.ad, ',', ' '), ';', ' '), '"', '') AS ad,
  x.fiyat,
  x.birim,
  x.plu
FROM (
  SELECT
    LTRIM(RTRIM(ISNULL(b.BARCODE, ''))) AS kod,
    COALESCE(
      NULLIF(LTRIM(RTRIM(s.MALINCINSI)), ''),
      NULLIF(LTRIM(RTRIM(b.ACIKLAMA)), ''),
      NULLIF(LTRIM(RTRIM(b.BARCODE)), '')
    ) AS ad,
    CAST(CASE WHEN b.SATISFIYATI1 > 0 THEN b.SATISFIYATI1 ELSE ISNULL(b.SATISFIYATI, 0) END AS decimal(18, 2)) AS fiyat,
    LTRIM(RTRIM(ISNULL(b.BIRIMADI, ''))) AS birim,
    ISNULL((
      SELECT TOP 1 CAST(fs.PLU AS varchar(20))
      FROM dbo.TBLFASTERSTOKLAR fs
      WHERE fs.BIRIMIND = b.IND
        AND fs.PLU IS NOT NULL
        AND CAST(fs.PLU AS varchar(20)) NOT IN ('', '0')
    ), '') AS plu,
    s.DELETED,
    s.IPTAL
  FROM dbo.F0101TBLBIRIMLEREX b
  JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO
) x
WHERE x.ad IS NOT NULL
  AND x.ad NOT IN ('VADE FARKI', 'KUR FARKI', 'DEVIR')
  AND ISNULL(x.DELETED, 0) = 0
  AND ISNULL(x.IPTAL, 0) = 0
  AND (x.fiyat > 0 OR x.kod <> '')
ORDER BY x.ad;
