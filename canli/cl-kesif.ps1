$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-kesif.ps1"
if ([Environment]::Is64BitProcess) {
    & "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex"
    return
}

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }
function Cut($v) { $s = [string]$v; if ($s.Length -gt 40) { $s.Substring(0, 40) + "..." } else { $s } }

Say "CL Works veritabani aramasi ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan

if ($env:FG_MDB -and (Test-Path -LiteralPath $env:FG_MDB)) {
    Say "Verilen dosya kullanilacak: $env:FG_MDB" Cyan
    $files = @(Get-Item -LiteralPath $env:FG_MDB)
} else {
    $roots = @("C:\", ${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramData, "$env:USERPROFILE\Documents", "$env:PUBLIC\Documents", "$env:USERPROFILE\Desktop") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $dirs = foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)cl.?works|cas|cl.?5000|clp|terazi|scale|label|etiket' } }
    $isDb = { $_.Extension -match '(?i)^\.(mdb|accdb)$' }
    $files = @(foreach ($d in ($dirs | Select-Object -Unique)) { Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object $isDb })
    if (-not $files.Count) {
        Say "Bilinen klasorlerde bulunamadi, tum C: diski taraniyor (birkac dakika surebilir)..." Yellow
        $files = @(Get-ChildItem -LiteralPath "C:\" -Recurse -Depth 5 -File -ErrorAction SilentlyContinue | Where-Object $isDb | Where-Object { $_.FullName -notmatch '(?i)\\Windows\\|\\Microsoft Office\\|\\WinSxS\\' })
    }
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
    $pw = ""
    for ($deneme = 0; $deneme -lt 2 -and -not $conn; $deneme++) {
        $pwPart = if ($pw) { "Jet OLEDB:Database Password=$pw;" } else { "" }
        foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
            try {
                $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$($f.FullName);Mode=Read;Persist Security Info=False;$pwPart")
                $c.Open()
                $conn = $c
                Say "Acildi ($prov)" Green
                break
            } catch { $err = $_.Exception.Message }
        }
        if (-not $conn -and $deneme -eq 0 -and ($err -match "(?i)password|parola|sifre|not a valid")) {
            Write-Host "  Bu veritabani sifreli. Sifreyi biliyorsaniz yazin, bilmiyorsaniz bos birakip Enter'a basin." -ForegroundColor Yellow
            $sec = Read-Host "  Veritabani sifresi" -AsSecureString
            $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            if (-not $pw) { break }
        }
    }
    if (-not $conn) { Say "Acilamadi: $err" Red; continue }
    try {
        $tableRows = @()
        try { $tableRows = @($conn.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Tables, $null)) } catch { Say "  Tablo listesi (yontem 1) alinamadi: $($_.Exception.Message)" DarkGray }
        if (-not $tableRows.Count) {
            try { $tableRows = @($conn.GetSchema("Tables")) } catch { Say "  Tablo listesi (yontem 2) alinamadi: $($_.Exception.Message)" DarkGray }
        }
        $tables = @($tableRows | Where-Object { $t = [string]$_.TABLE_TYPE; $n = [string]$_.TABLE_NAME; $t -notmatch "(?i)system|access" -and $n -notlike "MSys*" -and $n -notlike "~*" } | ForEach-Object { [string]$_.TABLE_NAME })
        Say ("  Toplam tablo: " + $tableRows.Count + ", kullanici tablosu: " + $tables.Count)
        if (-not $tables.Count -and $tableRows.Count) {
            Say "  Tum tablolar (tip ile):"
            $tableRows | ForEach-Object { Say ("    " + [string]$_.TABLE_NAME + "  [" + [string]$_.TABLE_TYPE + "]") }
        }
        foreach ($t in $tables) {
            try {
                $cols = @($conn.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Columns, @($null, $null, $t, $null)) | Sort-Object { [int]$_.ORDINAL_POSITION } | ForEach-Object { [string]$_.COLUMN_NAME })
                $n = "?"
                try { $cmd = $conn.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$t]"; $n = $cmd.ExecuteScalar() } catch { }
                Say "`n[$t] $n satir" Yellow
                Say ("  Sutunlar: " + ($cols -join ", "))
                if ($n -ne "?" -and [int]$n -gt 0) {
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
                }
            } catch { Say "  [$t] okunamadi: $($_.Exception.Message)" DarkGray }
        }
    } catch { Say "  Okuma hatasi: $($_.Exception.Message)" Red } finally { $conn.Close() }
}

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-kesif.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-kesif.txt" }
[System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true)))
try { Set-Clipboard -Value $out.ToString(); Say "`nSonuc panoya kopyalandi. Sohbete yapistirabilirsiniz. Dosya: $target" Green } catch { Say "`nSonuc dosyaya yazildi: $target" Green }
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
