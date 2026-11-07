param([int]$Port = 8443)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$web = Join-Path $root "web"
$webFull = [System.IO.Path]::GetFullPath($web).TrimEnd('\') + '\'
$logFile = Join-Path $root "sunucu.log"
$zipUrl = "https://github.com/nuhregaibunsal/myphonecashregister/archive/HEAD.zip"
$connStr = "Server=.;Database=UNSALDB;Integrated Security=SSPI;Connect Timeout=5;Application Name=FiyatGor"

function Log($m) {
    try {
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) { Remove-Item $logFile -Force }
        Add-Content -Path $logFile -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8
    } catch { }
}

function Update-App {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $env:TEMP "fiyatgor.zip"
        $tmp = Join-Path $env:TEMP "fiyatgor_guncelleme"
        Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip -TimeoutSec 30
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
        if (-not (Test-Path (Join-Path $src.FullName "web\index.html"))) { throw "zip icinde web klasoru yok" }
        if (-not (Test-Path $web)) { New-Item -ItemType Directory -Path $web | Out-Null }
        Copy-Item -Path (Join-Path $src.FullName "web\*") -Destination $web -Recurse -Force
        Copy-Item -Path (Join-Path $src.FullName "araclar\urunler.sql") -Destination $root -Force
        Copy-Item -Path (Join-Path $src.FullName "canli\*.ps1") -Destination $root -Force
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force
        Log "Uygulama guncellendi"
    } catch {
        Log "Guncelleme yapilamadi, eldeki surum kullaniliyor: $($_.Exception.Message)"
    }
}

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue

$script:cache = $null
$script:cacheAt = [datetime]::MinValue
$script:lastError = ""

function Get-ProductsJson {
    if ($script:cache -and ((Get-Date) - $script:cacheAt).TotalSeconds -lt 30) { return ,$script:cache }
    $query = [System.IO.File]::ReadAllText((Join-Path $root "urunler.sql"))
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $list = New-Object System.Collections.Generic.List[object]
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        $cmd.CommandTimeout = 60
        $r = $cmd.ExecuteReader()
        while ($r.Read()) {
            $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
            $d["barkod"] = [string]$r["barkod"]
            $d["ad"] = [string]$r["ad"]
            $d["fiyat"] = if ($r["fiyat"] -is [DBNull]) { 0 } else { [double]$r["fiyat"] }
            $d["birim"] = [string]$r["birim"]
            $d["plu"] = [string]$r["plu"]
            $d["birimind"] = if ($r["birimind"] -is [DBNull]) { 0 } else { [int]$r["birimind"] }
            $list.Add($d)
        }
        $r.Close()
    } finally {
        $conn.Close()
    }
    $payload = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $payload["updated"] = [long]([datetime]::UtcNow - [datetime]"1970-01-01").TotalMilliseconds
    $payload["count"] = $list.Count
    $payload["products"] = $list
    $script:cache = [System.Text.Encoding]::UTF8.GetBytes($ser.Serialize($payload))
    $script:cacheAt = Get-Date
    $script:lastError = ""
    return ,$script:cache
}

$pinFile = Join-Path $root "pin.txt"
$changeLog = Join-Path $root "fiyat-degisiklikleri.csv"
$script:pinFails = 0
$script:lockUntil = [datetime]::MinValue

function Hash-Pin([string]$salt, [string]$pin) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($salt + ":" + $pin))
    return ([System.BitConverter]::ToString($bytes)).Replace("-", "")
}

function Test-Pin([string]$pin) {
    if (-not (Test-Path $pinFile)) { return "kapali" }
    if ((Get-Date) -lt $script:lockUntil) { return "kilitli" }
    $parts = ([System.IO.File]::ReadAllText($pinFile)).Trim().Split(":")
    if ($parts.Length -eq 2 -and (Hash-Pin $parts[0] $pin) -eq $parts[1]) {
        $script:pinFails = 0
        return "ok"
    }
    $script:pinFails++
    if ($script:pinFails -ge 5) {
        $script:lockUntil = (Get-Date).AddMinutes(5)
        $script:pinFails = 0
        Log "PIN 5 kez yanlis girildi, 5 dakika kilitlendi"
        return "kilitli"
    }
    return "yanlis"
}

function Read-JsonBody($ctx) {
    if ($ctx.Request.ContentLength64 -gt 10000) { throw "istek cok buyuk" }
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    return $ser.DeserializeObject($text)
}

function Set-Price($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Fiyat degistirme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $ind = [int]$b["birimind"]
    $eski = [decimal]$b["eski"]
    $yeni = [decimal]$b["yeni"]
    if ($ind -le 0 -or $yeni -le 0 -or $yeni -ge 1000000) { SendJson $ctx 400 @{ ok = $false; error = "Gecersiz fiyat." }; return }
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE dbo.F0101TBLBIRIMLEREX SET ESKIFIYAT1 = SATISFIYATI1, SATISFIYATI1 = @yeni, FIYATDEGISMETARIHI1 = GETDATE() WHERE IND = @ind AND (ABS(ISNULL(SATISFIYATI1, 0) - @eski) < 0.005 OR (ISNULL(SATISFIYATI1, 0) = 0 AND ABS(ISNULL(SATISFIYATI, 0) - @eski) < 0.005))"
        [void]$cmd.Parameters.AddWithValue("@yeni", $yeni)
        [void]$cmd.Parameters.AddWithValue("@eski", $eski)
        [void]$cmd.Parameters.AddWithValue("@ind", $ind)
        $n = $cmd.ExecuteNonQuery()
    } finally {
        $conn.Close()
    }
    $script:cache = $null
    if ($n -ne 1) {
        SendJson $ctx 409 @{ ok = $false; error = "Bu urunun fiyati bu arada degismis. Liste yenilendi, tekrar deneyin." }
        return
    }
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    $line = "{0:yyyy-MM-dd HH:mm:ss};{1};{2};{3};{4};{5}" -f (Get-Date), $ind, ([string]$b["ad"]).Replace(";", " "), $eski, $yeni, $ip
    Add-Content -Path $changeLog -Value $line -Encoding UTF8
    Log "Fiyat degisti: birim $ind, $eski -> $yeni ($ip)"
    SendJson $ctx 200 @{ ok = $true; eski = $eski; yeni = $yeni }
}

$types = @{
    ".html" = "text/html; charset=utf-8"; ".js" = "application/javascript; charset=utf-8"
    ".css" = "text/css; charset=utf-8"; ".json" = "application/json; charset=utf-8"
    ".webmanifest" = "application/manifest+json"; ".png" = "image/png"; ".svg" = "image/svg+xml"
    ".ico" = "image/x-icon"; ".gz" = "application/gzip"; ".wasm" = "application/wasm"; ".txt" = "text/plain; charset=utf-8"
}

function Send($ctx, [int]$status, [string]$type, [byte[]]$body, [bool]$noCache) {
    $res = $ctx.Response
    $res.StatusCode = $status
    $res.ContentType = $type
    if ($noCache) { $res.Headers["Cache-Control"] = "no-store" }
    $res.ContentLength64 = $body.Length
    $res.OutputStream.Write($body, 0, $body.Length)
    $res.OutputStream.Close()
}

function SendJson($ctx, [int]$status, $obj) {
    Send $ctx $status "application/json; charset=utf-8" ([System.Text.Encoding]::UTF8.GetBytes($ser.Serialize($obj))) $true
}

function Handle($ctx) {
    $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($path -eq "/api/urunler") {
        try {
            Send $ctx 200 "application/json; charset=utf-8" (Get-ProductsJson) $true
        } catch {
            $script:lastError = $_.Exception.Message
            Log "SQL hatasi: $($script:lastError)"
            SendJson $ctx 503 @{ ok = $false; error = $script:lastError }
        }
        return
    }
    if ($path -eq "/api/yetki") {
        SendJson $ctx 200 @{ ok = $true; fiyat = (Test-Path $pinFile) }
        return
    }
    if ($path -eq "/api/fiyat") {
        if ($ctx.Request.HttpMethod -ne "POST") { SendJson $ctx 405 @{ ok = $false; error = "POST gerekli" }; return }
        try { Set-Price $ctx } catch {
            Log "Fiyat degistirilemedi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = "Fiyat degistirilemedi: $($_.Exception.Message)" }
        }
        return
    }
    if ($path -eq "/api/durum") {
        $sqlOk = $true
        try { [void](Get-ProductsJson) } catch { $sqlOk = $false; $script:lastError = $_.Exception.Message }
        SendJson $ctx 200 @{ ok = $true; sql = $sqlOk; error = $script:lastError; computer = $env:COMPUTERNAME }
        return
    }
    if ($path -eq "/" -or $path -eq "") { $path = "/index.html" }
    $full = [System.IO.Path]::GetFullPath((Join-Path $web ($path.TrimStart('/') -replace '/', '\')))
    if (-not $full.StartsWith($webFull, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
        Send $ctx 404 "text/plain; charset=utf-8" ([System.Text.Encoding]::UTF8.GetBytes("Bulunamadi")) $true
        return
    }
    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $type = if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" }
    $noCache = $ext -in @(".html", ".js", ".css", ".webmanifest")
    Send $ctx 200 $type ([System.IO.File]::ReadAllBytes($full)) $noCache
}

Log "Baslatiliyor"
Update-App

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("https://+:$Port/")
try {
    $listener.Start()
} catch {
    Log "Sunucu baslatilamadi: $($_.Exception.Message)"
    exit 1
}
Log "Dinleniyor: https://+:$Port/"

while ($listener.IsListening) {
    $ctx = $null
    try {
        $ctx = $listener.GetContext()
        Handle $ctx
    } catch {
        Log "Istek hatasi: $($_.Exception.Message)"
        if ($ctx) { try { $ctx.Response.Abort() } catch { } }
    }
}
