$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-icerik-kesif.ps1"
if ([Environment]::Is64BitProcess) {
    & "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex"
    return
}

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }

$mdb = $env:FG_MDB
if (-not $mdb -and (Test-Path "C:\FiyatGor\cl.txt")) { $mdb = ([System.IO.File]::ReadAllText("C:\FiyatGor\cl.txt")).Trim() }
if (-not $mdb) { $mdb = Read-Host "CL Works mdb yolu" }
$mdb = $mdb.Trim('"')
if (-not (Test-Path -LiteralPath $mdb)) { Write-Host "Dosya bulunamadi: $mdb" -ForegroundColor Red; Read-Host "Enter"; return }
$pw = ""
if (Test-Path "C:\FiyatGor\clpw.txt") { $pw = ([System.IO.File]::ReadAllText("C:\FiyatGor\clpw.txt")).TrimEnd("`r", "`n") }
if (-not $pw) {
    $sec = Read-Host "CL mdb sifresi" -AsSecureString
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$pwPart = if ($pw) { "Jet OLEDB:Database Password=$pw;" } else { "" }
$conn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$mdb;Mode=Read;Persist Security Info=False;$pwPart")
try { $conn.Open() } catch { Write-Host "Acilamadi: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Enter"; return }

Say "CL ICERIK KESFI ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) - sadece okur" Cyan
try {
    $tables = $conn.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Tables, @($null, $null, $null, "TABLE"))
    $names = @($tables.Rows | ForEach-Object { [string]$_["TABLE_NAME"] } | Sort-Object)
    Say "`nTablolar:" Yellow
    Say ("  " + ($names -join ", ")) White

    $hedef = @($names | Where-Object { $_ -match '(?i)ingr|icer|text|msg|nutri|allerg' })
    $hedef += @($names | Where-Object { $_ -match '(?i)^TbScale$' })
    foreach ($t in $hedef) {
        Say "`n=== $t ===" Yellow
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM [$t]"
        $r = $cmd.ExecuteReader()
        $cols = @(); for ($i = 0; $i -lt $r.FieldCount; $i++) { $cols += ("{0} ({1})" -f $r.GetName($i), $r.GetFieldType($i).Name) }
        Say ("Sutunlar: " + ($cols -join ", ")) White
        $n = 0
        while ($r.Read()) {
            $n++
            if ($n -le 4 -or ($t -match '(?i)scale')) {
                $vals = @(); for ($i = 0; $i -lt $r.FieldCount; $i++) {
                    $v = $r.GetValue($i)
                    if ($v -is [byte[]]) { $s = "[{0} bayt]" -f $v.Length } else { $s = [string]$v }
                    $s = $s.Replace("`r", "\r").Replace("`n", "\n")
                    $vals += ($r.GetName($i) + "=" + $s)
                }
                Say ("  " + ($vals -join " | ")) Gray
            }
        }
        Say ("Toplam satir: $n") White
        $r.Close()
    }
} finally { $conn.Close() }

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-icerik-kesif.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-icerik-kesif.txt" }
[System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Say "`nRapor: $target" Green
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
