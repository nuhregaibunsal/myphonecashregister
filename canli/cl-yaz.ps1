param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [int]$Item = 0,
    [decimal]$Price = -1,
    [string]$Name = "",
    [string]$Pw = "",
    [switch]$SadeceOku,
    [switch]$Liste
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
    if ($Item -le 0) { Write-Output "ERR urun-kodu-yok"; exit 4 }
    if ($SadeceOku) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DeptNo, PluNo, ItemCode, Name1, UnitPrice, SendFlag, WorkFlag FROM TbPLU WHERE ItemCode = @p"
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
    $cmd.CommandText = "UPDATE TbPLU SET UnitPrice = @price$setName, SendFlag = 1, WorkFlag = 1 WHERE ItemCode = @p"
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
