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
