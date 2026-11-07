$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-kesif.ps1"
if ([Environment]::Is64BitProcess) {
    & "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex"
    return
}

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }
function Cut($v) { $s = [string]$v; if ($s.Length -gt 40) { $s.Substring(0, 40) + "..." } else { $s } }

Say "CL Works veritabani aramasi ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan

$roots = @("C:\", ${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramData, "$env:USERPROFILE\Documents", "$env:PUBLIC\Documents", "$env:USERPROFILE\Desktop") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
$dirs = foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)cl.?works|cas|cl.?5000|clp|terazi|scale|label|etiket' } }
$files = @(foreach ($d in ($dirs | Select-Object -Unique)) { Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Include *.mdb, *.accdb -ErrorAction SilentlyContinue })
if (-not $files.Count) {
    Say "Bilinen klasorlerde bulunamadi, tum C: diski taraniyor (birkac dakika surebilir)..." Yellow
    $files = @(Get-ChildItem -LiteralPath "C:\" -Recurse -Depth 5 -File -Include *.mdb, *.accdb -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '(?i)\\Windows\\|\\Microsoft Office\\|\\WinSxS\\' })
}
if (-not $files.Count) {
    Say "Hic MDB dosyasi bulunamadi. CL Works ayarlarindaki veritabani yolunu bana yazin." Red
} else {
    Say "Bulunan dosyalar:" Cyan
    $files | Sort-Object LastWriteTime -Descending | ForEach-Object { Say ("  {0}  ({1:N0} KB, {2:yyyy-MM-dd HH:mm})" -f $_.FullName, ($_.Length / 1KB), $_.LastWriteTime) }
}

foreach ($f in ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 4)) {
    Say "`n===== $($f.FullName) =====" Cyan
    $conn = $null
    foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
        try {
            $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$($f.FullName);Mode=Read;Persist Security Info=False;")
            $c.Open()
            $conn = $c
            Say "Acildi ($prov)" Green
            break
        } catch { $err = $_.Exception.Message }
    }
    if (-not $conn) { Say "Acilamadi: $err" Red; continue }
    try {
        $tables = $conn.GetSchema("Tables") | Where-Object { $_.TABLE_TYPE -eq "TABLE" } | ForEach-Object { $_.TABLE_NAME }
        foreach ($t in $tables) {
            $cols = $conn.GetSchema("Columns", [string[]]@($null, $null, $t, $null)) | Sort-Object { [int]$_.ORDINAL_POSITION } | ForEach-Object { $_.COLUMN_NAME }
            $n = "?"
            try { $cmd = $conn.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$t]"; $n = $cmd.ExecuteScalar() } catch { }
            Say "`n[$t] $n satir" Yellow
            Say ("  Sutunlar: " + ($cols -join ", "))
            if ($n -ne "?" -and [int]$n -gt 0) {
                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT TOP 3 * FROM [$t]"
                    $rd = $cmd.ExecuteReader()
                    $i = 0
                    while ($rd.Read() -and $i -lt 3) {
                        $vals = for ($k = 0; $k -lt $rd.FieldCount; $k++) { "$($rd.GetName($k))=$(Cut $rd.GetValue($k))" }
                        Say ("  ornek: " + ($vals -join " | "))
                        $i++
                    }
                    $rd.Close()
                } catch { Say "  ornek okunamadi: $($_.Exception.Message)" DarkGray }
            }
        }
    } finally { $conn.Close() }
}

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-kesif.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-kesif.txt" }
[System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true)))
try { Set-Clipboard -Value $out.ToString(); Say "`nSonuc panoya kopyalandi. Sohbete yapistirabilirsiniz. Dosya: $target" Green } catch { Say "`nSonuc dosyaya yazildi: $target" Green }
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
