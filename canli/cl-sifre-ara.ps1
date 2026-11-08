$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }

Say "CL Works ayar dosyasi aramasi ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan
Say "Bu komut sadece okur, hicbir seyi degistirmez.`n"

$roots = @("C:\", ${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramData, "$env:APPDATA", "$env:LOCALAPPDATA", "$env:USERPROFILE\Documents", "$env:PUBLIC\Documents", "$env:USERPROFILE\Desktop") |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$dirs = foreach ($r in $roots) {
    Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)cl.?works|^cas$|cas.?scale|cl.?5000|clp|terazi|scale|label|etiket|duzenlenen' }
}
$dirs = $dirs | Select-Object -Unique
if (-not $dirs) {
    Say "CL Works klasoru bulunamadi. Programin kurulu oldugu klasorun yolunu bana yazin." Yellow
} else {
    Say "Bakilan klasorler:" Cyan
    $dirs | ForEach-Object { Say "  $($_.FullName)" }
}

$pattern = '(?i)(pwd|password|parola|sifre|passwd|database\s*password|jet\s*oledb|data\s*source|provider\s*=|connectionstring|conn[^a-z]|\.mdb|\.accdb|server\s*=|uid\s*=|user\s*id)'
$found = 0
foreach ($d in $dirs) {
    $files = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue -Include *.ini, *.config, *.xml, *.cfg, *.conf, *.txt, *.dat, *.udl, *.json, *.properties, *.settings |
        Where-Object { $_.Length -lt 3MB } | Select-Object -First 500
    foreach ($f in $files) {
        try {
            $hits = Select-String -LiteralPath $f.FullName -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -First 10
            if ($hits) {
                Say "`n--- $($f.FullName) ---" Yellow
                foreach ($h in $hits) {
                    $line = $h.Line.Trim()
                    if ($line.Length -gt 300) { $line = $line.Substring(0, 300) + "..." }
                    Say "  $line"
                    $found++
                }
            }
        } catch { }
    }
}

Say "`n--- Windows kayit defterinde CL Works izleri ---" Cyan
foreach ($rk in @("HKCU:\Software", "HKLM:\Software", "HKLM:\Software\WOW6432Node")) {
    try {
        Get-ChildItem $rk -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '(?i)cl.?works|cas|terazi|scale' } | ForEach-Object {
            Say "  Kayit: $($_.Name)"
            try {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" -and ($_.Value -match '(?i)pwd|pass|parola|sifre|\.mdb|data source|provider') } | ForEach-Object {
                    Say "    $($_.Name) = $($_.Value)"
                }
            } catch { }
        }
    } catch { }
}

if ($found -eq 0) { Say "`nAyar dosyalarinda baglanti bilgisi bulunamadi." Yellow }

$target = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor\cl-sifre.txt" } else { Join-Path ([Environment]::GetFolderPath("Desktop")) "cl-sifre.txt" }
try { [System.IO.File]::WriteAllText($target, $out.ToString(), (New-Object System.Text.UTF8Encoding($true))); Say "`nSonuc dosyaya da yazildi: $target" Green } catch { }
Say "`nDIKKAT: Asagidaki satirlarda sifre gorunuyorsa BANA SIFRENIN KENDISINI YAZMAYIN." Red
Say "Sadece 'Database Password' ya da 'Pwd' gibi bir sey buldum deyin, keşif komutunda kendiniz girersiniz." Red
Read-Host "`nKapatmak icin Enter'a basin" | Out-Null
