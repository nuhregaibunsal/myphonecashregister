$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-istatistik.ps1"
if ([Environment]::Is64BitProcess) {
    & "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex"
    return
}

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }

$mdb = $env:FG_MDB
if (-not $mdb) { $mdb = Read-Host "CL Works mdb yolu" }
$mdb = $mdb.Trim('"')
if (-not (Test-Path -LiteralPath $mdb)) { Write-Host "Dosya bulunamadi: $mdb" -ForegroundColor Red; Read-Host "Enter"; return }
$sec = Read-Host "CL Works mdb sifresi (sifresizse bos Enter)" -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$pwPart = if ($pw) { "Jet OLEDB:Database Password=$pw;" } else { "" }

$conn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$mdb;Mode=Read;Persist Security Info=False;$pwPart")
try { $conn.Open() } catch { Write-Host "Acilamadi: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Enter"; return }

Say "TbPLU sutun kullanim istatistigi ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan
Say "Sadece okur. Her sutun icin: kac urunde bos/sifir DEGIL, ornek degerler (PLU no ile)." Gray

try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT * FROM TbPLU"
    $t = New-Object System.Data.DataTable
    $t.Load($cmd.ExecuteReader())
} finally { $conn.Close() }

Say ("Toplam urun: " + $t.Rows.Count) Yellow
foreach ($col in $t.Columns) {
    $name = $col.ColumnName
    $used = 0
    $examples = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($row in $t.Rows) {
        $v = $row[$name]
        if ($v -is [DBNull]) { continue }
        $s = [string]$v
        if ($s -eq "" -or $s -eq "0" -or $s -eq "False") { continue }
        $used++
        if (-not $seen.ContainsKey($s) -and $examples.Count -lt 6) {
            $seen[$s] = 1
            $short = if ($s.Length -gt 25) { $s.Substring(0, 25) + "..." } else { $s }
            $examples.Add("PLU" + [string]$row["PluNo"] + "=" + $short)
        }
    }
    $line = "{0,-20} dolu: {1,4}   {2}" -f $name, $used, ($examples -join " | ")
    if ($used -gt 0) { Say $line White } else { Say $line DarkGray }
}

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-istatistik.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-istatistik.txt" }
[System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true)))
try { Set-Clipboard -Value $out.ToString(); Say "`nSonuc panoya kopyalandi. Dosya: $target" Green } catch { Say "`nDosya: $target" Green }
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
