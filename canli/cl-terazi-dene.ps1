$url = "https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-terazi-dene.ps1"
if ([Environment]::Is64BitProcess) {
    & "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm $url | iex"
    return
}

Write-Host "CL terazi dogrudan gonderme denemesi" -ForegroundColor Cyan
Write-Host "Bu islem CL Works'teki Gonder dugmesinin yaptigini yapar. CL veritabanina yazmaz, sadece okur." -ForegroundColor Gray

$varsayilan = Join-Path ([Environment]::GetFolderPath("Desktop")) ("d" + [char]0xFC + "zeltme.mdb")
$mdb = Read-Host "CL mdb yolu (bos Enter = $varsayilan)"
if (-not $mdb) { $mdb = $varsayilan }
$mdb = $mdb.Trim('"')
if (-not (Test-Path -LiteralPath $mdb)) { Write-Host "Dosya bulunamadi: $mdb" -ForegroundColor Red; Read-Host "Enter"; return }

$sec = Read-Host "CL mdb sifresi" -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$item = Read-Host "Gonderilecek urunun Urun Kodu (ItemCode)"
if ($item -notmatch '^\d+$') { Write-Host "Urun kodu sayi olmali." -ForegroundColor Red; Read-Host "Enter"; return }

$ip = Read-Host "Terazi IP (bos Enter = 192.168.1.201, hepsi icin 'hepsi' yazin)"
if (-not $ip) { $ip = "192.168.1.201" }
if ($ip -eq "hepsi") { $ip = "" }

$yol = Join-Path $env:TEMP "cl-terazi-gonder.ps1"
try {
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $wc = New-Object System.Net.WebClient
    $kod = $wc.DownloadString("https://raw.githubusercontent.com/nuhregaibunsal/myphonecashregister/HEAD/canli/cl-terazi-gonder.ps1")
    [System.IO.File]::WriteAllText($yol, $kod, (New-Object System.Text.UTF8Encoding($true)))
} catch { Write-Host "Indirilemedi: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Enter"; return }

Write-Host "Gonderiliyor..." -ForegroundColor Yellow
$sonuc = & $yol -Mdb $mdb -Pw $pw -Item ([int]$item) -TekIp $ip 2>&1
foreach ($s in $sonuc) {
    $t = [string]$s
    if ($t -like "OK*") { Write-Host $t -ForegroundColor Green }
    elseif ($t -like "SONUC*") { Write-Host $t -ForegroundColor Cyan }
    else { Write-Host $t -ForegroundColor Red }
}
Read-Host "`nKapatmak icin Enter'a basin" | Out-Null
