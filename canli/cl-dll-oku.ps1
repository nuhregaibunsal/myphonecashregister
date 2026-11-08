param([string]$Dosya = "")

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }

Say "CL Works dosya icerigi okuma ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan
Say "Sadece okur, hicbir seyi degistirmez.`n"

$hedefler = @()
if ($Dosya -and (Test-Path $Dosya)) { $hedefler += (Get-Item $Dosya) }
else {
    $roots = @("C:\", ${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramData, "$env:APPDATA", "$env:LOCALAPPDATA", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents") |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($r in $roots) {
        $dirs = Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)cl.?works|cas|terazi|scale|duzenlenen' }
        foreach ($d in $dirs) {
            $hedefler += Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue -Include AppSettings.dll, *.config, *.exe.config, Settings.dll, *.dll |
                Where-Object { $_.Name -match '(?i)appsetting|setting|config|baglanti|connect' -and $_.Length -lt 8MB }
        }
    }
    $hedefler = $hedefler | Select-Object -Unique | Select-Object -First 8
}

if (-not $hedefler) {
    Say "AppSettings.dll bulunamadi. Dosyaya sag tiklayip 'Farkli adres olarak kopyala' / 'Yol olarak kopyala' deyip" Yellow
    Say "komutu soyle calistirin:" Yellow
    Say '  irm https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-dll-oku.ps1 | iex; cl-dll-oku -Dosya "C:\...\AppSettings.dll"' White
}

function Extract-Strings([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sb = New-Object System.Text.StringBuilder
    $res = New-Object System.Collections.Generic.List[string]
    # ASCII dizileri
    foreach ($b in $bytes) {
        if ($b -ge 32 -and $b -le 126) { [void]$sb.Append([char]$b) }
        else { if ($sb.Length -ge 4) { $res.Add($sb.ToString()) }; [void]$sb.Clear() }
    }
    if ($sb.Length -ge 4) { $res.Add($sb.ToString()) }
    # UTF-16 (Unicode) dizileri
    [void]$sb.Clear()
    for ($i = 0; $i -lt $bytes.Length - 1; $i += 2) {
        $b = $bytes[$i]; $b2 = $bytes[$i + 1]
        if ($b2 -eq 0 -and $b -ge 32 -and $b -le 126) { [void]$sb.Append([char]$b) }
        else { if ($sb.Length -ge 4) { $res.Add($sb.ToString()) }; [void]$sb.Clear() }
    }
    if ($sb.Length -ge 4) { $res.Add($sb.ToString()) }
    return $res
}

$pattern = '(?i)(password|pwd|parola|sifre|data\s*source|provider\s*=|\.mdb|\.accdb|jet\s*oledb|ace\.oledb|connectionstring|initial\s*catalog|user\s*id|uid\s*=|database\s*=)'
foreach ($h in $hedefler) {
    Say "`n===== $($h.FullName)  ($([math]::Round($h.Length / 1KB)) KB) =====" Cyan
    try {
        $strings = Extract-Strings $h.FullName
        $hits = $strings | Where-Object { $_ -match $pattern } | Select-Object -Unique -First 40
        if ($hits) {
            foreach ($line in $hits) {
                $t = if ($line.Length -gt 300) { $line.Substring(0, 300) + "..." } else { $line }
                Say "  $t"
            }
        } else { Say "  Baglanti/sifre ile ilgili yazi bulunamadi." DarkGray }
    } catch { Say "  Okunamadi: $($_.Exception.Message)" Red }
}

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-dll.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-dll.txt" }
try { [System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true))); Say "`nSonuc dosyaya da yazildi: $target" Green } catch { }
Say "`nDIKKAT: Bir baglanti cumlesi ('Data Source=...;Password=...') gorurseniz BANA SIFREYI YAZMAYIN." Red
Say "Sadece 'Password=... diye bir sey var' deyin. Sifreyi kesif komutunda kendiniz girersiniz." Red
Read-Host "`nKapatmak icin Enter'a basin" | Out-Null
