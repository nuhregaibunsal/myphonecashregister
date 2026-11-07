SELECT
  s.name + '.' + t.name AS Tablo,
  p.rows AS SatirSayisi,
  STUFF((
    SELECT ', ' + c.name
    FROM sys.columns c
    WHERE c.object_id = t.object_id
      AND (
        c.name LIKE '%barkod%' OR c.name LIKE '%barcode%' OR c.name LIKE '%ean%'
        OR c.name LIKE '%plu%'
        OR c.name LIKE '%fiyat%' OR c.name LIKE '%price%' OR c.name LIKE '%satis%'
        OR c.name LIKE '%malin%' OR c.name LIKE '%cins%' OR c.name LIKE '%stokad%'
        OR c.name LIKE '%urunad%' OR c.name LIKE '%adi%' OR c.name LIKE '%isim%'
        OR c.name LIKE '%birim%'
      )
    ORDER BY c.column_id
    FOR XML PATH('')), 1, 2, '') AS IlgiliSutunlar
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN (
  SELECT object_id, SUM(rows) AS rows
  FROM sys.partitions
  WHERE index_id IN (0, 1)
  GROUP BY object_id
) p ON p.object_id = t.object_id
WHERE EXISTS (
    SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id
    AND (c.name LIKE '%barkod%' OR c.name LIKE '%barcode%' OR c.name LIKE '%plu%' OR c.name LIKE '%ean%')
  )
  AND EXISTS (
    SELECT 1 FROM sys.columns c WHERE c.object_id = t.object_id
    AND (c.name LIKE '%fiyat%' OR c.name LIKE '%price%' OR c.name LIKE '%satis%')
  )
ORDER BY p.rows DESC;
