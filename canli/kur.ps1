$ErrorActionPreference = "Stop"
$Port = 8443
$dir = "C:\FiyatGor"
$zipUrl = "https://github.com/nuhregaibunsal/myphonecashregister/archive/HEAD.zip"
$taskName = "FiyatGor"

function Step($m) { Write-Host "`n>> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "   $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "   $m" -ForegroundColor Red }
function Done { Write-Host ""; Read-Host "Kapatmak icin Enter'a basin" | Out-Null }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Fail "Bu kurulum yonetici olarak calismali."
    Fail "Baslat'a sag tiklayin, 'Windows PowerShell (Yonetici)' secin ve komutu orada yapistirin."
    Done
    return
}

$user = "$env:USERDOMAIN\$env:USERNAME"
Write-Host "Fiyat Gor canli baglanti kurulumu" -ForegroundColor Cyan
Write-Host "Bilgisayar: $env:COMPUTERNAME   Kullanici: $user"

try {
    Step "Dosyalar indiriliyor"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $zip = Join-Path $env:TEMP "fiyatgor_kurulum.zip"
    $tmp = Join-Path $env:TEMP "fiyatgor_kurulum"
    Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip -TimeoutSec 120
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not (Test-Path "$dir\web")) { New-Item -ItemType Directory -Path "$dir\web" | Out-Null }
    Copy-Item -Path (Join-Path $src.FullName "web\*") -Destination "$dir\web" -Recurse -Force
    Copy-Item -Path (Join-Path $src.FullName "araclar\urunler.sql") -Destination $dir -Force
    Copy-Item -Path (Join-Path $src.FullName "canli\*.ps1") -Destination $dir -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip -Force
    Ok "Dosyalar $dir klasorune kopyalandi"

    Step "Kasa veritabanina okuma izni kontrol ediliyor"
    $sqlOk = $false
    try {
        $c = New-Object System.Data.SqlClient.SqlConnection("Server=.;Database=UNSALDB;Integrated Security=SSPI;Connect Timeout=5")
        $c.Open()
        $cmd = $c.CreateCommand()
        $cmd.CommandText = "SELECT COUNT(*) FROM dbo.F0101TBLBIRIMLEREX"
        $n = $cmd.ExecuteScalar()
        $c.Close()
        Ok "Baglanti tamam, $n birim kaydi okunabiliyor"
        $sqlOk = $true
    } catch {
        Warn "Bu Windows hesabi ($user) veritabanini okuyamiyor."
        Warn "SSMS'te canli\izin.sql sorgusunu calistirin. Sunucu kurulur, izin verilince kendiliginden calisir."
        Warn "Hata: $($_.Exception.Message)"
    }

    Step "Guvenli baglanti sertifikasi hazirlaniyor"
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq "FiyatGor" -and $_.NotAfter -gt (Get-Date).AddDays(30) } | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -DnsName "fiyatgor", $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(10) -FriendlyName "FiyatGor" -KeyAlgorithm RSA -KeyLength 2048 -KeyExportPolicy Exportable
    }
    & netsh http delete sslcert ipport=0.0.0.0:$Port 2>&1 | Out-Null
    $out = & netsh http add sslcert ipport=0.0.0.0:$Port certhash=$($cert.Thumbprint) appid="{3f6a2b1c-8d4e-4f5a-9b7c-2e1d0a9f8c7b}" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Sertifika baglanamadi: $out" }
    & netsh http delete urlacl url=https://+:$Port/ 2>&1 | Out-Null
    $out = & netsh http add urlacl url=https://+:$Port/ sddl="D:(A;;GX;;;WD)" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Adres izni verilemedi: $out" }
    Ok "Sertifika hazir"

    Step "Guvenlik duvarinda $Port portu aciliyor"
    Get-NetFirewallRule -DisplayName "FiyatGor" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName "FiyatGor" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any | Out-Null
    Ok "Port acildi"

    Step "Bilgisayar acilinca otomatik baslama ayarlaniyor"
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*FiyatGor\sunucu.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\sunucu.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Ok "Sunucu baslatildi, her oturum acilisinda kendiliginden baslayacak"

    Step "Sunucu kontrol ediliyor"
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $durum = $null
    for ($i = 0; $i -lt 40 -and -not $durum; $i++) {
        Start-Sleep -Seconds 2
        try { $durum = (Invoke-WebRequest -UseBasicParsing -Uri "https://localhost:$Port/api/durum" -TimeoutSec 10).Content | ConvertFrom-Json } catch { }
    }
    if (-not $durum) {
        Fail "Sunucu cevap vermedi. Kayit dosyasi: $dir\sunucu.log"
    } elseif ($durum.sql) {
        Ok "Sunucu calisiyor ve fiyatlari okuyabiliyor"
    } else {
        Warn "Sunucu calisiyor ama veritabanini okuyamiyor: $($durum.error)"
        Warn "SSMS'te canli\izin.sql sorgusunu calistirin. Sonra telefonda sayfayi yenileyin."
    }

    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -ExpandProperty IPAddress
    $urls = @($ips | ForEach-Object { "https://$($_):$Port/" })
    Step "Telefondan acilacak adres"
    $urls | ForEach-Object { Write-Host "   $_" -ForegroundColor White }

    $items = ($urls | ForEach-Object { "<div class='q'><div class='code' data-url='$_'></div><p>$_</p></div>" }) -join ""
    $html = @"
<!doctype html><html lang="tr"><head><meta charset="utf-8"><title>Fiyat Gor baglanti</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;text-align:center;padding:24px;background:#f7f2ea;color:#2a1d12}
.q{display:inline-block;margin:16px;padding:16px;background:#fff;border-radius:16px}.q p{font-size:22px;font-weight:600}
li{text-align:left;max-width:560px;margin:6px auto;font-size:18px}</style></head><body>
<h1>Telefonun kamerasiyla okut</h1>$items
<ol><li>Telefon dukkanin Wi-Fi agina bagli olmali.</li><li>"Baglantiniz gizli degil" uyarisinda <b>Gelismis</b>, sonra <b>Devam et</b>.</li><li>Acilinca tarayici menusunden <b>Ana ekrana ekle</b>.</li></ol>
<script src="web/vendor/zxing.min.js"></script><script>
document.querySelectorAll('.code').forEach(function(d){d.appendChild(new ZXing.BrowserQRCodeSvgWriter().write(d.dataset.url,280,280));});
</script></body></html>
"@
    [System.IO.File]::WriteAllText("$dir\baglan.html", $html, (New-Object System.Text.UTF8Encoding($false)))
    Start-Process "$dir\baglan.html"
    Ok "Ekrandaki karekodu telefonla okutun. Karekod sayfasi: $dir\baglan.html"
} catch {
    Fail "Kurulum yarida kaldi: $($_.Exception.Message)"
}
Done
