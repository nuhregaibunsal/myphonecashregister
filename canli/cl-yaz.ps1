param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [Parameter(Mandatory = $true)][int]$Item,
    [decimal]$Price = -1,
    [string]$Name = "",
    [string]$Pw = "",
    [switch]$SadeceOku
)

# Bu yardimci 32-bit calisir (Jet OLEDB 32-bit oldugu icin). Ana sunucu bunu cagirir.
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
