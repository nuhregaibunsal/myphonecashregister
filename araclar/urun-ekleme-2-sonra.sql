USE UNSALDB;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb.dbo.fg_snap') IS NULL
BEGIN
  SELECT N'Once 1. sorguyu calistirin' AS Hata;
  RETURN;
END;

IF OBJECT_ID('tempdb..#simdi') IS NOT NULL DROP TABLE #simdi;
SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS Tablo, SUM(p.rows) AS Satir
INTO #simdi
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name;

IF OBJECT_ID('tempdb..#sonuc') IS NOT NULL DROP TABLE #sonuc;
CREATE TABLE #sonuc (Tablo nvarchar(300), Degisim nvarchar(100), Satirlar nvarchar(max));

DECLARE @t nvarchar(300), @once bigint, @simdi bigint, @ozet int, @yeniOzet int, @sql nvarchar(max), @json nvarchar(max), @n int;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
  SELECT n.Tablo, ISNULL(o.Satir, 0), n.Satir, o.Ozet
  FROM #simdi n LEFT JOIN tempdb.dbo.fg_snap o ON o.Tablo = n.Tablo;
OPEN c;
FETCH NEXT FROM c INTO @t, @once, @simdi, @ozet;
WHILE @@FETCH_STATUS = 0
BEGIN
  BEGIN TRY
    IF @simdi > @once
    BEGIN
      SET @n = CASE WHEN @simdi - @once > 20 THEN 20 ELSE @simdi - @once END;
      SET @sql = N'SELECT @j = (SELECT TOP (' + CAST(@n AS nvarchar(10)) + N') * FROM ' + @t + N' ORDER BY 1 DESC FOR JSON PATH, INCLUDE_NULL_VALUES)';
      EXEC sp_executesql @sql, N'@j nvarchar(max) OUTPUT', @j = @json OUTPUT;
      INSERT INTO #sonuc VALUES (@t, N'+' + CAST(@simdi - @once AS nvarchar(20)) + N' satir', @json);
    END
    ELSE IF @ozet IS NOT NULL AND @simdi BETWEEN 1 AND 5000
    BEGIN
      SET @sql = N'SELECT @o = CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM ' + @t;
      EXEC sp_executesql @sql, N'@o int OUTPUT', @o = @yeniOzet OUTPUT;
      IF @yeniOzet <> @ozet
      BEGIN
        SET @sql = N'SELECT @j = (SELECT TOP (50) * FROM ' + @t + N' ORDER BY 1 DESC FOR JSON PATH, INCLUDE_NULL_VALUES)';
        EXEC sp_executesql @sql, N'@j nvarchar(max) OUTPUT', @j = @json OUTPUT;
        INSERT INTO #sonuc VALUES (@t, N'icerik degisti', @json);
      END
    END
  END TRY
  BEGIN CATCH
    INSERT INTO #sonuc VALUES (@t, N'okunamadi', ERROR_MESSAGE());
  END CATCH;
  FETCH NEXT FROM c INTO @t, @once, @simdi, @ozet;
END;
CLOSE c;
DEALLOCATE c;

SELECT Tablo, Degisim, LEN(Satirlar) AS Uzunluk FROM #sonuc ORDER BY Tablo;

SELECT (
  SELECT Tablo, Degisim, JSON_QUERY(CASE WHEN ISJSON(Satirlar) = 1 THEN Satirlar ELSE N'[]' END) AS Satirlar
  FROM #sonuc ORDER BY Tablo FOR JSON PATH
) AS KopyalaYapistir;
