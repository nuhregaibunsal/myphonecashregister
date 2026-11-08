param(
    [string]$Ip = "192.168.1.201",
    [int]$Port = 20304,
    [int]$Plu = 19,
    [int]$Dept = 1,
    [double]$Fiyat = 242.42,
    [int]$UrunKodu = 9,
    [string]$Isim = "AY CEKIRDEGI",
    [int]$Icindekiler = 20,
    [int]$F10 = 373
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function LE([int64]$v, [int]$n) { $b = New-Object byte[] $n; for ($i = 0; $i -lt $n; $i++) { $b[$i] = [byte](($v -shr ($i * 8)) -band 0xFF) }; return , $b }

$tr = [System.Text.Encoding]::GetEncoding(1254)
$fiyatKurus = [int64][math]::Round($Fiyat * 100)
$isimBytes = $tr.GetBytes($Isim)

# Alanlar (CL Works'un gonderdigi sirayla)
$fields = @(
    @("01", "57", (LE $Dept 2)),
    @("02", "4C", (LE $Plu 4)),
    @("04", "4D", ([byte[]]@(1))),
    @("05", "42", ([byte[]]@(0))),
    @("06", "4C", (LE $fiyatKurus 4)),
    @("09", "57", (New-Object byte[] 2)),
    @("0B", "4C", (LE $UrunKodu 4)),
    @("0D", "4C", (New-Object byte[] 4)),
    @("0E", "57", (New-Object byte[] 2)),
    @("0F", "42", (New-Object byte[] 1)),
    @("10", "4C", (LE $F10 4)),
    @("11", "42", (New-Object byte[] 2)),
    @("12", "57", (New-Object byte[] 2)),
    @("19", "57", (LE $Icindekiler 2)),
    @("1A", "42", (New-Object byte[] 1)),
    @("37", "57", (New-Object byte[] 2)),
    @("51", "57", (New-Object byte[] 2)),
    @("55", "57", (New-Object byte[] 2)),
    @("5B", "42", (New-Object byte[] 4)),
    @("64", "4C", (New-Object byte[] 4)),
    @("0A", "53", $isimBytes),
    @("1E", "53", (New-Object byte[] 0)),
    @("1F", "53", (New-Object byte[] 0))
)

$body = New-Object System.Collections.Generic.List[byte]
foreach ($f in $fields) {
    $val = [byte[]]$f[2]
    $spec = [System.Text.Encoding]::ASCII.GetBytes(("F={0}.{1},{2:X}:" -f $f[0], $f[1], $val.Length))
    $body.AddRange($spec)
    if ($val.Length) { $body.AddRange($val) }
}
$csum = 0
foreach ($b in $body) { $csum = $csum -bxor $b }
$hdr = [System.Text.Encoding]::ASCII.GetBytes(("W02A{0:X5},{1:D2}L{2:X4}:" -f $Plu, $Dept, $body.Count))
$packet = New-Object System.Collections.Generic.List[byte]
$packet.AddRange($hdr)
$packet.AddRange($body)
$packet.Add([byte]$csum)
$pk = $packet.ToArray()

Write-Host ("Paket hazir: {0} bayt, checksum 0x{1:X2}" -f $pk.Length, $csum) -ForegroundColor Cyan
Write-Host ("Hedef: {0}:{1}  PLU={2} UrunKodu={3} Fiyat={4} ({5} kurus) Isim='{6}'" -f $Ip, $Port, $Plu, $UrunKodu, $Fiyat, $fiyatKurus, $Isim) -ForegroundColor Gray

$client = New-Object System.Net.Sockets.TcpClient
try {
    $client.Connect($Ip, $Port)
    $client.ReceiveTimeout = 4000
    $client.SendTimeout = 4000
    $ns = $client.GetStream()
    Start-Sleep -Milliseconds 200
    $buf = New-Object byte[] 256
    if ($ns.DataAvailable) { $n = $ns.Read($buf, 0, 256); Write-Host ("Terazi karsilama: " + ([BitConverter]::ToString($buf, 0, $n))) -ForegroundColor DarkGray }
    $ns.Write($pk, 0, $pk.Length)
    $ns.Flush()
    Write-Host "Paket gonderildi, cevap bekleniyor..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    $resp = New-Object System.Collections.Generic.List[byte]
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 4) {
        if ($ns.DataAvailable) { $n = $ns.Read($buf, 0, 256); for ($i = 0; $i -lt $n; $i++) { $resp.Add($buf[$i]) } }
        else { Start-Sleep -Milliseconds 150; if ($resp.Count -gt 0 -and -not $ns.DataAvailable) { break } }
    }
    $txt = -join ($resp | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { "." } })
    Write-Host ("Terazi cevabi ({0} bayt): {1}" -f $resp.Count, $txt) -ForegroundColor Green
    if ($txt -match "O01") { Write-Host "SONUC: Terazi kabul etti (O01). Basarili." -ForegroundColor Green }
    elseif ($resp.Count -gt 0) { Write-Host "SONUC: Cevap geldi ama O01 yok, yukaridaki cevaba bakin." -ForegroundColor Yellow }
    else { Write-Host "SONUC: Terazi cevap vermedi." -ForegroundColor Red }
} catch {
    Write-Host ("HATA: " + $_.Exception.Message) -ForegroundColor Red
} finally {
    $client.Close()
}
Read-Host "`nKapatmak icin Enter'a basin" | Out-Null
