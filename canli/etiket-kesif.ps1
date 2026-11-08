$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/etiket-kesif.ps1"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex`""
    return
}

$out = New-Object System.Text.StringBuilder
function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c; [void]$out.AppendLine($t) }
$hedef = if (Test-Path "C:\FiyatGor") { "C:\FiyatGor" } else { [Environment]::GetFolderPath("Desktop") }

Say "ETIKET YAZICISI KESFI ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan
Say "Bu arac hicbir seyi silmez. Sadece yazicilari listeler ve Vega'nin yaziciya gonderdigi isi bir kere kopyalar." Gray

Say "`n1) Yazicilar" Yellow
$printers = @(Get-Printer | Sort-Object Name)
$i = 0
foreach ($p in $printers) {
    $i++
    Say ("  [{0}] {1} | surucu: {2} | port: {3} | varsayilan veri: {4}" -f $i, $p.Name, $p.DriverName, $p.PortName, $p.Datatype) White
}

Say "`n2) Vega / Faster klasorlerindeki etiket tasarim dosyalari" Yellow
$kokler = @()
foreach ($d in @("C:\", "C:\Program Files", "C:\Program Files (x86)", "D:\")) {
    if (Test-Path $d) { $kokler += @(Get-ChildItem $d -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)vega|faster' }) }
}
foreach ($k in $kokler) {
    Say ("  Klasor: " + $k.FullName) White
    Get-ChildItem $k.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '(?i)^\.(frx|fr3|frf|rpt|rep|lbl|lab|btw|prn|qrp|rav|rdl|xml|ini|cfg)$' -and ($_.Name -match '(?i)etiket|barkod|barcode|label|raf' -or $_.Extension -match '(?i)^\.(frx|fr3|frf|lbl|lab|btw|prn|qrp|rav)$') } |
        Select-Object -First 40 |
        ForEach-Object { Say ("    {0}  ({1} bayt, {2:yyyy-MM-dd})" -f $_.FullName, $_.Length, $_.LastWriteTime) Gray }
}

$sec = Read-Host "`nEtiket yazicisinin numarasini yazin (yukaridaki listeden)"
$n = 0
if (-not [int]::TryParse($sec, [ref]$n) -or $n -lt 1 -or $n -gt $printers.Count) { Say "Gecersiz secim." Red; Read-Host "Enter"; return }
$pr = $printers[$n - 1]
Say ("Secilen: " + $pr.Name) Green

$spool = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
$eski = $pr.KeepPrintedJobs
try {
    Set-Printer -Name $pr.Name -KeepPrintedJobs $true
    $once = @{}
    Get-ChildItem $spool -File -ErrorAction SilentlyContinue | ForEach-Object { $once[$_.Name] = 1 }
    Say "`n3) Simdi Vega'dan TEK bir urunun etiketini, 1 kopya olarak yazdirin." Yellow
    Read-Host "Etiket yazicidan ciktiktan sonra buraya donup Enter'a basin" | Out-Null
    Start-Sleep -Seconds 2
    $yeni = @(Get-ChildItem $spool -File -ErrorAction SilentlyContinue | Where-Object { -not $once.ContainsKey($_.Name) } | Sort-Object LastWriteTime)
    $spl = @($yeni | Where-Object { $_.Extension -ieq ".SPL" }) | Select-Object -Last 1
    if (-not $spl) { Say "Yazdirma isi yakalanamadi. Yazici kuyrugunda is gorundu mu?" Red }
    else {
        $dosya = Join-Path $hedef "etiket-ornek.spl"
        Copy-Item -LiteralPath $spl.FullName -Destination $dosya -Force
        $b = [System.IO.File]::ReadAllBytes($dosya)
        Say ("Yakalandi: {0} bayt -> {1}" -f $b.Length, $dosya) Green
        $bas = [System.Text.Encoding]::ASCII.GetString($b, 0, [Math]::Min(400, $b.Length))
        $tur = "bilinmiyor"
        if ($b.Length -ge 4 -and $b[0] -eq 1 -and $b[1] -eq 0 -and $b[2] -eq 1 -and $b[3] -eq 0) { $tur = "EMF (Windows cizimi, surucu ceviriyor)" }
        elseif ($bas -match '(?i)SIZE|GAP|CLS|PRINT') { $tur = "TSPL komutlari (duz metin)" }
        elseif ($bas -match '\^XA') { $tur = "ZPL komutlari" }
        elseif ($bas -match '(?m)^N\r?$|\bq\d+') { $tur = "EPL komutlari" }
        Say ("Icerik turu: " + $tur) Cyan
        Say "Ilk 400 bayt (okunabilir kisim):" Gray
        Say (($bas.ToCharArray() | ForEach-Object { if ([int]$_ -ge 32 -and [int]$_ -lt 127 -or $_ -eq "`n") { $_ } else { "." } }) -join "") DarkGray
    }
} finally {
    Set-Printer -Name $pr.Name -KeepPrintedJobs $eski
    Say ("Yazici ayari eski haline getirildi (KeepPrintedJobs={0})." -f $eski) Gray
}

$rapor = Join-Path $hedef "etiket-kesif.txt"
[System.IO.File]::WriteAllText($rapor, $out.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Say "`nRapor: $rapor" Green
Say "Bu rapor dosyasini ve etiket-ornek.spl dosyasini gonderin." Green
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
