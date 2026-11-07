USE UNSALDB;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb.dbo.fg_snap') IS NOT NULL DROP TABLE tempdb.dbo.fg_snap;
CREATE TABLE tempdb.dbo.fg_snap (Tablo nvarchar(300) PRIMARY KEY, Satir bigint, Ozet int NULL);

INSERT INTO tempdb.dbo.fg_snap (Tablo, Satir)
SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name), SUM(p.rows)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name;

DECLARE @t nvarchar(300), @sql nvarchar(max), @o int;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Tablo FROM tempdb.dbo.fg_snap WHERE Satir BETWEEN 1 AND 5000;
OPEN c;
FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    SET @sql = N'SELECT @o = CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM ' + @t;
    EXEC sp_executesql @sql, N'@o int OUTPUT', @o = @o OUTPUT;
    UPDATE tempdb.dbo.fg_snap SET Ozet = @o WHERE Tablo = @t;
  END TRY
  BEGIN CATCH
  END CATCH;
  FETCH NEXT FROM c INTO @t;
END;
CLOSE c;
DEALLOCATE c;

SELECT COUNT(*) AS KaydedilenTabloSayisi, N'Simdi Vega''dan deneme urununu ekleyin, sonra 2. sorguyu calistirin' AS Sonraki
FROM tempdb.dbo.fg_snap;
