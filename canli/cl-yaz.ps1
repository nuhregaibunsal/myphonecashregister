param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [Parameter(Mandatory = $true)][int]$Plu,
    [int]$Dept = 1,
    [decimal]$Price = -1,
    [string]$Name = "",
    [switch]$SadeceOku
)

# Bu yardimci 32-bit calisir (Jet OLEDB 32-bit oldugu icin). Ana sunucu bunu cagirir.
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not (Test-Path -LiteralPath $Mdb)) { Write-Output "ERR dosya-yok"; exit 2 }

$conn = $null
foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
    try {
        $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$Mdb;Persist Security Info=False;")
        $c.Open()
        $conn = $c
        break
    } catch { $err = $_.Exception.Message }
}
if (-not $conn) { Write-Output "ERR acilamadi: $err"; exit 3 }

try {
    if ($SadeceOku) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DeptNo, PluNo, Name1, UnitPrice, SendFlag, WorkFlag FROM TbPLU WHERE PluNo = @p AND DeptNo = @d"
        [void]$cmd.Parameters.AddWithValue("@p", $Plu)
        [void]$cmd.Parameters.AddWithValue("@d", $Dept)
        $r = $cmd.ExecuteReader()
        if ($r.Read()) {
            Write-Output ("OKU DeptNo={0} PluNo={1} Name1={2} UnitPrice={3} SendFlag={4} WorkFlag={5}" -f $r["DeptNo"], $r["PluNo"], $r["Name1"], $r["UnitPrice"], $r["SendFlag"], $r["WorkFlag"])
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
    $cmd.CommandText = "UPDATE TbPLU SET UnitPrice = @price$setName, SendFlag = 1, WorkFlag = 1 WHERE PluNo = @p AND DeptNo = @d"
    [void]$cmd.Parameters.AddWithValue("@price", [double]$Price)
    if ($Name -ne "") { [void]$cmd.Parameters.AddWithValue("@name", $Name) }
    [void]$cmd.Parameters.AddWithValue("@p", $Plu)
    [void]$cmd.Parameters.AddWithValue("@d", $Dept)
    $n = $cmd.ExecuteNonQuery()
    Write-Output "OK $n"
    exit 0
} catch {
    Write-Output "ERR $($_.Exception.Message)"
    exit 5
} finally {
    $conn.Close()
}
