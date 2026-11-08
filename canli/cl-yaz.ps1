param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [int]$Item = 0,
    [decimal]$Price = -1,
    [string]$Name = "",
    [string]$Pw = "",
    [switch]$SadeceOku,
    [switch]$Liste,
    [switch]$Ekle,
    [int]$Plu = 0,
    [int]$Dept = 1,
    [int]$PluType = 1,
    [int]$Ingredient = 0,
    [int]$SellBy = 366,
    [string]$NameB64 = "",
    [switch]$IcerikListe,
    [switch]$IcerikYaz,
    [string]$TextB64 = ""
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not (Test-Path -LiteralPath $Mdb)) { Write-Output "ERR dosya-yok"; exit 2 }

if (-not $Pw -and $env:FG_CLPW) { $Pw = $env:FG_CLPW }
$pwPart = if ($Pw) { "Jet OLEDB:Database Password=$Pw;" } else { "" }

$conn = $null
foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
    try {
        $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$Mdb;Persist Security Info=False;$pwPart")
        $c.Open()
        $conn = $c
        break
    } catch { $err = $_.Exception.Message }
}
if (-not $conn) { Write-Output "ERR acilamadi: $err"; exit 3 }

try {
    if ($Liste) {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DeptNo, PluNo, ItemCode, Name1, UnitPrice FROM TbPLU"
        $r = $cmd.ExecuteReader()
        while ($r.Read()) {
            $ad = if ($r["Name1"] -is [DBNull]) { "" } else { [string]$r["Name1"] }
            $f = if ($r["UnitPrice"] -is [DBNull]) { 0 } else { [double]$r["UnitPrice"] }
            $k = if ($r["ItemCode"] -is [DBNull]) { 0 } else { [int64]$r["ItemCode"] }
            $d = if ($r["DeptNo"] -is [DBNull]) { 1 } else { [int]$r["DeptNo"] }
            Write-Output ("PLU`t{0}`t{1}`t{2}`t{3}`t{4}" -f [int64]$r["PluNo"], $k, $d, $f.ToString($inv), [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ad)))
        }
        $r.Close()
        Write-Output "OK liste"
        exit 0
    }
    if ($IcerikListe) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT Code, IngText FROM TbIngredient ORDER BY Code"
        $r = $cmd.ExecuteReader()
        while ($r.Read()) {
            $t = if ($r["IngText"] -is [DBNull]) { "" } else { [string]$r["IngText"] }
            Write-Output ("ING`t{0}`t{1}" -f [int]$r["Code"], [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($t)))
        }
        $r.Close()
        Write-Output "OK icerik-liste"
        exit 0
    }
    if ($IcerikYaz) {
        if ($Item -le 0 -or $Item -gt 9999) { Write-Output "ERR kod-gecersiz"; exit 4 }
        $metin = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TextB64))
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE TbIngredient SET IngText = @t WHERE Code = @c"
        [void]$cmd.Parameters.AddWithValue("@t", $metin)
        [void]$cmd.Parameters.AddWithValue("@c", $Item)
        $n = $cmd.ExecuteNonQuery()
        if ($n -eq 0) {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "INSERT INTO TbIngredient (Code, IngText) VALUES (@c, @t)"
            [void]$cmd.Parameters.AddWithValue("@c", $Item)
            [void]$cmd.Parameters.AddWithValue("@t", $metin)
            $n = $cmd.ExecuteNonQuery()
            Write-Output "OK icerik-eklendi $n"
        } else { Write-Output "OK icerik-guncellendi $n" }
        exit 0
    }
    if ($Ekle) {
        if ($Plu -le 0 -or $Plu -ge 1000) { Write-Output "ERR plu-gecersiz"; exit 4 }
        if ($Item -le 0) { Write-Output "ERR urun-kodu-yok"; exit 4 }
        if ($Price -le 0) { Write-Output "ERR fiyat-yok"; exit 4 }
        $ad = if ($NameB64) { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameB64)) } else { $Name }
        if (-not $ad) { Write-Output "ERR ad-yok"; exit 4 }
        $used = New-Object 'System.Collections.Generic.HashSet[int]'
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT PluNo FROM TbPLU WHERE DeptNo = @d"
        [void]$cmd.Parameters.AddWithValue("@d", $Dept)
        $r = $cmd.ExecuteReader()
        while ($r.Read()) { if (-not ($r["PluNo"] -is [DBNull])) { [void]$used.Add([int]$r["PluNo"]) } }
        $r.Close()
        if ($used.Contains($Plu)) {
            $oneri = 1; while ($oneri -lt 1000 -and $used.Contains($oneri)) { $oneri++ }
            Write-Output "ERR plu-dolu $oneri"; exit 6
        }
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT TOP 1 * FROM TbPLU WHERE DeptNo = @d AND PluNo < 1000 AND PluType = 1 ORDER BY PluNo"
        [void]$cmd.Parameters.AddWithValue("@d", $Dept)
        $r = $cmd.ExecuteReader([System.Data.CommandBehavior]::KeyInfo)
        $schema = $r.GetSchemaTable()
        if (-not $r.Read()) { $r.Close(); Write-Output "ERR ornek-urun-yok"; exit 7 }
        $vals = [ordered]@{}
        $meta = @{}
        foreach ($row in $schema.Rows) {
            $cn = [string]$row["ColumnName"]
            $meta[$cn] = $row
            if ($row["IsAutoIncrement"] -eq $true -or $row["IsRowVersion"] -eq $true) { continue }
            $vals[$cn] = $r[$cn]
        }
        $r.Close()
        $set = @{ DeptNo = $Dept; PluNo = $Plu; ItemCode = $Item; Name1 = $ad; UnitPrice = [double]$Price; PluType = $PluType; IngredientNo = $Ingredient; SellByDate = $SellBy; UseFixedPrice = 0; FixedWeight = 0; SendFlag = 1; WorkFlag = 1 }
        $keys = @($vals.Keys)
        foreach ($cn in $keys) {
            if ($vals[$cn] -is [byte[]]) { $vals[$cn] = [DBNull]::Value; continue }
            if ($cn -match '^Name([2-9]|\d{2,})$' -and $vals[$cn] -is [string]) { $vals[$cn] = ""; continue }
            if ($set.ContainsKey($cn)) {
                $dt = $meta[$cn]["DataType"]
                $vals[$cn] = [Convert]::ChangeType($set[$cn], $dt, [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
        $size = [int]$meta["Name1"]["ColumnSize"]
        if ($size -gt 0 -and $ad.Length -gt $size) { Write-Output "ERR ad-uzun $size"; exit 4 }
        $cols = @($vals.Keys | Where-Object { -not ($vals[$_] -is [DBNull]) })
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO TbPLU (" + (($cols | ForEach-Object { "[$_]" }) -join ", ") + ") VALUES (" + (($cols | ForEach-Object { "?" }) -join ", ") + ")"
        $i = 0
        foreach ($cn in $cols) { $i++; [void]$cmd.Parameters.AddWithValue("p$i", $vals[$cn]) }
        $n = $cmd.ExecuteNonQuery()
        Write-Output "OK eklendi $n"
        exit 0
    }
    if ($Item -le 0) { Write-Output "ERR urun-kodu-yok"; exit 4 }
    if ($SadeceOku) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DeptNo, PluNo, ItemCode, Name1, UnitPrice, SendFlag, WorkFlag FROM TbPLU WHERE ItemCode = @p AND PluNo < 1000"
        [void]$cmd.Parameters.AddWithValue("@p", $Item)
        $r = $cmd.ExecuteReader()
        if ($r.Read()) {
            Write-Output ("OKU DeptNo={0} PluNo={1} ItemCode={2} Name1={3} UnitPrice={4} SendFlag={5} WorkFlag={6}" -f $r["DeptNo"], $r["PluNo"], $r["ItemCode"], $r["Name1"], $r["UnitPrice"], $r["SendFlag"], $r["WorkFlag"])
        } else {
            Write-Output "OKU bulunamadi"
        }
        $r.Close()
        exit 0
    }

    if ($Price -lt 0) { Write-Output "ERR fiyat-yok"; exit 4 }

    $setName = ""
    if ($Name -ne "") { $setName = ", Name1 = @name" }
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "UPDATE TbPLU SET UnitPrice = @price$setName, SendFlag = 1, WorkFlag = 1 WHERE ItemCode = @p AND PluNo < 1000"
    [void]$cmd.Parameters.AddWithValue("@price", [double]$Price)
    if ($Name -ne "") { [void]$cmd.Parameters.AddWithValue("@name", $Name) }
    [void]$cmd.Parameters.AddWithValue("@p", $Item)
    $n = $cmd.ExecuteNonQuery()
    Write-Output "OK $n"
    exit 0
} catch {
    Write-Output "ERR $($_.Exception.Message)"
    exit 5
} finally {
    $conn.Close()
}
