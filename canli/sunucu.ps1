param([int]$Port = 8443)

$ErrorActionPreference = "Stop"
$selfPath = $MyInvocation.MyCommand.Path
$selfHash = (Get-FileHash -LiteralPath $selfPath).Hash
$root = Split-Path -Parent $selfPath
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
        $ProgressPreference = "SilentlyContinue"
        (New-Object System.Net.WebClient).DownloadFile($zipUrl, $zip)
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

function Update-Web {
    try {
        $ProgressPreference = "SilentlyContinue"
        $zip = Join-Path $env:TEMP "fiyatgor_web.zip"
        $tmp = Join-Path $env:TEMP "fiyatgor_web"
        (New-Object System.Net.WebClient).DownloadFile($zipUrl, $zip)
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
        $ok = $false
        if ($src -and (Test-Path (Join-Path $src.FullName "web\index.html"))) {
            Copy-Item -Path (Join-Path $src.FullName "web\*") -Destination $web -Recurse -Force
            Copy-Item -Path (Join-Path $src.FullName "araclar\urunler.sql") -Destination $root -Force
            Copy-Item -Path (Join-Path $src.FullName "canli\*.ps1") -Destination $root -Force
            $ok = $true
        }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        if ($ok) { Log "Web dosyalari guncellendi (istek uzerine)" }
        return $ok
    } catch { Log "Web guncelleme hatasi: $($_.Exception.Message)"; return $false }
}

Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue

$script:cache = $null
$script:cacheAt = [datetime]::MinValue
$script:lastError = ""

function Get-ProductsJson {
    if ($script:cache -and ((Get-Date) - $script:cacheAt).TotalSeconds -lt 30) { return ,$script:cache }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $query = [System.IO.File]::ReadAllText((Join-Path $root "urunler.sql"))
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $sb = New-Object System.Text.StringBuilder
    $ms = [long]([datetime]::UtcNow - [datetime]"1970-01-01").TotalMilliseconds
    [void]$sb.Append('{"updated":').Append($ms.ToString($inv)).Append(',"products":[')
    $count = 0
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        $cmd.CommandTimeout = 60
        $r = $cmd.ExecuteReader()
        $has = @{}
        for ($ci = 0; $ci -lt $r.FieldCount; $ci++) { $has[$r.GetName($ci)] = $true }
        $col = { param($name) if ($has.ContainsKey($name) -and -not ($r[$name] -is [DBNull])) { [string]$r[$name] } else { "" } }
        while ($r.Read()) {
            $fiyat = [double]0
            if ($has.ContainsKey("fiyat") -and -not ($r["fiyat"] -is [DBNull])) { $fiyat = [double]$r["fiyat"] }
            $bi = 0
            if ($has.ContainsKey("birimind") -and -not ($r["birimind"] -is [DBNull])) { $bi = [int]$r["birimind"] }
            if ($count -gt 0) { [void]$sb.Append(',') }
            [void]$sb.Append('{"barkod":').Append([System.Web.HttpUtility]::JavaScriptStringEncode((& $col "barkod"), $true))
            [void]$sb.Append(',"ad":').Append([System.Web.HttpUtility]::JavaScriptStringEncode((& $col "ad"), $true))
            [void]$sb.Append(',"fiyat":').Append($fiyat.ToString($inv))
            [void]$sb.Append(',"birim":').Append([System.Web.HttpUtility]::JavaScriptStringEncode((& $col "birim"), $true))
            [void]$sb.Append(',"plu":').Append([System.Web.HttpUtility]::JavaScriptStringEncode((& $col "plu"), $true))
            [void]$sb.Append(',"birimind":').Append($bi.ToString($inv))
            [void]$sb.Append(',"kod":').Append([System.Web.HttpUtility]::JavaScriptStringEncode((& $col "kod"), $true)).Append('}')
            $count++
        }
        $r.Close()
    } finally {
        $conn.Close()
    }
    [void]$sb.Append('],"count":').Append($count.ToString($inv)).Append('}')
    $script:cache = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
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
    if ($ctx.Request.ContentLength64 -gt 20000) { throw "istek cok buyuk" }
    $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    return $ser.DeserializeObject($text)
}

function Get-Units([int]$birimInd) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $sb = New-Object System.Text.StringBuilder
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT s.IND AS STOK, s.MALINCINSI, s.STOKKODU, s.ANABIRIM, b.IND, b.BIRIMADI, b.ACIKLAMA, b.CARPAN, b.AGIRLIK, b.BARCODE, CASE WHEN ISNULL(b.SATISFIYATI1, 0) > 0 THEN b.SATISFIYATI1 ELSE ISNULL(b.SATISFIYATI, 0) END AS FIYAT FROM dbo.F0101TBLBIRIMLEREX b JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE b.STOKNO = (SELECT STOKNO FROM dbo.F0101TBLBIRIMLEREX WHERE IND = @ind) ORDER BY CASE WHEN b.IND = s.ANABIRIM THEN 0 ELSE 1 END, b.IND"
        [void]$cmd.Parameters.AddWithValue("@ind", $birimInd)
        $r = $cmd.ExecuteReader()
        $i = 0
        while ($r.Read()) {
            if ($i -eq 0) {
                $ana = 0
                if (-not ($r["ANABIRIM"] -is [DBNull])) { $ana = [int]$r["ANABIRIM"] }
                [void]$sb.Append('{"ok":true,"stok":').Append([int]$r["STOK"]).Append(',"ad":').Append((J ([string]$r["MALINCINSI"]))).Append(',"kod":').Append((J ([string]$r["STOKKODU"]))).Append(',"anaBirim":').Append($ana).Append(',"birimler":[')
            } else { [void]$sb.Append(',') }
            $carpan = 0; if (-not ($r["CARPAN"] -is [DBNull])) { $carpan = [double]$r["CARPAN"] }
            $agirlik = 0; if (-not ($r["AGIRLIK"] -is [DBNull])) { $agirlik = [double]$r["AGIRLIK"] }
            [void]$sb.Append('{"ind":').Append([int]$r["IND"]).Append(',"birim":').Append((J ([string]$r["BIRIMADI"]))).Append(',"aciklama":').Append((J ([string]$r["ACIKLAMA"]))).Append(',"carpan":').Append((N $carpan)).Append(',"agirlik":').Append((N $agirlik)).Append(',"barkod":').Append((J ([string]$r["BARCODE"]).Trim())).Append(',"fiyat":').Append((N $r["FIYAT"])).Append('}')
            $i++
        }
        $r.Close()
        if ($i -eq 0) { return $null }
        [void]$sb.Append(']}')
    } finally {
        $conn.Close()
    }
    return ,([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
}

$clFile = Join-Path $root "cl.txt"

function Get-CLMdb {
    try { if (Test-Path $clFile) { $p = ([System.IO.File]::ReadAllText($clFile)).Trim(); if ($p -and (Test-Path -LiteralPath $p)) { return $p } } } catch { }
    return ""
}

$clPwFile = Join-Path $root "clpw.txt"
function Get-CLPw { try { if (Test-Path $clPwFile) { return ([System.IO.File]::ReadAllText($clPwFile)).TrimEnd("`r", "`n") } } catch { }; return "" }

function Invoke-CL([int]$plu, [decimal]$price) {
    $mdb = Get-CLMdb
    if (-not $mdb) { return $null }
    $helper = Join-Path $root "cl-yaz.ps1"
    if (-not (Test-Path $helper)) { return "ERR yardimci-yok" }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    try {
        $env:FG_CLPW = Get-CLPw
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Item $plu -Price ($price.ToString([System.Globalization.CultureInfo]::InvariantCulture)) 2>&1
        $env:FG_CLPW = ""
        return ([string](@($out) | Where-Object { $_ } | Select-Object -Last 1)).Trim()
    } catch {
        $env:FG_CLPW = ""
        return "ERR $($_.Exception.Message)"
    }
}

function Invoke-CLSend([int]$item, [int]$plu = 0) {
    $mdb = Get-CLMdb
    if (-not $mdb) { return @() }
    $helper = Join-Path $root "cl-terazi-gonder.ps1"
    if (-not (Test-Path $helper)) { return @("ERR yardimci-yok") }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    try {
        $env:FG_CLPW = Get-CLPw
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Item $item -Plu $plu 2>&1
        $env:FG_CLPW = ""
        return @(@($out) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    } catch {
        $env:FG_CLPW = ""
        return @("ERR $($_.Exception.Message)")
    }
}

$script:clList = $null
$script:clListAt = [datetime]::MinValue

function Get-CLList {
    if ($script:clList -and ((Get-Date) - $script:clListAt).TotalSeconds -lt 60) { return $script:clList }
    $mdb = Get-CLMdb
    if (-not $mdb) { throw "CL veritabani ayarli degil." }
    $helper = Join-Path $root "cl-yaz.ps1"
    if (-not (Test-Path $helper)) { throw "cl-yaz.ps1 yok." }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    try {
        $env:FG_CLPW = Get-CLPw
        $out = @(& $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Liste 2>&1 | ForEach-Object { [string]$_ })
    } finally { $env:FG_CLPW = "" }
    if (-not ($out | Where-Object { $_ -eq "OK liste" })) { throw ("CL okunamadi: " + (($out | Select-Object -Last 1) -join "")) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{"ok":true,"urunler":[')
    $first = $true
    foreach ($l in $out) {
        $p = $l -split "`t"
        if ($p.Count -lt 6 -or $p[0] -ne "PLU") { continue }
        $ad = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p[5]))
        if (-not $first) { [void]$sb.Append(",") }
        $first = $false
        [void]$sb.Append(('{{"plu":{0},"kod":{1},"bolum":{2},"fiyat":{3},"ad":{4}}}' -f [int64]$p[1], [int64]$p[2], [int]$p[3], $p[4], (J $ad)))
    }
    [void]$sb.Append("]}")
    $script:clList = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $script:clListAt = Get-Date
    return $script:clList
}

function Format-Send($lines, [string]$etiket) {
    $okIp = @{}; $badIp = @{}
    foreach ($l in $lines) {
        $pp = $l -split " "
        if ($pp.Count -lt 2) { continue }
        if ($pp[0] -eq "OK") { $okIp[$pp[1]] = 1 } elseif ($pp[0] -eq "FAIL") { $badIp[$pp[1]] = 1 }
    }
    foreach ($k in @($badIp.Keys)) { if ($okIp.ContainsKey($k)) { $okIp.Remove($k) } }
    $allN = $okIp.Count + $badIp.Count
    $okN = $okIp.Count
    if ($allN -eq 0) { return "CL veritabani guncellendi, terazilere gonderilemedi. CL Works'te Gonder'e basin." }
    if ($okN -eq $allN) { return "Terazilere gonderildi ($okN/$allN terazi, $etiket)." }
    if ($okN -gt 0) { return "$okN/$allN teraziye gonderildi. Ulasilamayanlar: " + ((@($badIp.Keys) | Sort-Object) -join ", ") + ". Onlar acilinca CL Works'te Gonder'e basin." }
    return "CL veritabani guncellendi ama hicbir teraziye ulasilamadi. CL Works'te Gonder'e basin."
}

function Invoke-CLAdd([int]$plu, [int]$item, [decimal]$price, [string]$ad, [int]$tip, [int]$icerik, [int]$skt) {
    $mdb = Get-CLMdb
    if (-not $mdb) { return "ERR cl-yok" }
    $helper = Join-Path $root "cl-yaz.ps1"
    if (-not (Test-Path $helper)) { return "ERR yardimci-yok" }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ad))
    $fiyat = $price.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    try {
        $env:FG_CLPW = Get-CLPw
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Ekle -Plu $plu -Item $item -Price $fiyat -NameB64 $b64 -PluType $tip -Ingredient $icerik -SellBy $skt 2>&1
        return ([string](@($out) | Where-Object { $_ } | Select-Object -Last 1)).Trim()
    } catch {
        return "ERR $($_.Exception.Message)"
    } finally { $env:FG_CLPW = "" }
}

function Get-CLUsed {
    $script:clList = $null
    $j = $ser.DeserializeObject([System.Text.Encoding]::UTF8.GetString((Get-CLList)))
    $used = @{}
    foreach ($u in $j["urunler"]) { if ([int]$u["bolum"] -eq 1) { $used[[int]$u["plu"]] = [string]$u["ad"] } }
    return $used
}

$ozelNo = @(1, 2, 3, 4, 5, 6, 7, 9, 10)

function Get-Ozel([int]$stok) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT STOKKODU, MALINCINSI, " + (($ozelNo | ForEach-Object { "KOD$_" }) -join ", ") + " FROM dbo.F0101TBLSTOKLAR WHERE IND = @s"
        [void]$cmd.Parameters.AddWithValue("@s", $stok)
        $r = $cmd.ExecuteReader()
        try {
            if (-not $r.Read()) { return $null }
            $parts = foreach ($n in $ozelNo) { $v = if ($r["KOD$n"] -is [DBNull]) { "" } else { ([string]$r["KOD$n"]).Trim() }; '"' + $n + '":' + (J $v) }
            $json = '{"ok":true,"stok":' + $stok + ',"ad":' + (J ([string]$r["MALINCINSI"])) + ',"ozel":{' + ($parts -join ",") + '}}'
            return ,([System.Text.Encoding]::UTF8.GetBytes($json))
        } finally { $r.Close() }
    } finally { $conn.Close() }
}

function Set-Ozel($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Degistirme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $stok = [int]$b["stok"]
    $oz = $b["ozel"]
    if ($stok -le 0 -or -not $oz) { SendJson $ctx 400 @{ ok = $false; error = "Gecersiz istek." }; return }
    $vals = @{}
    foreach ($n in $ozelNo) {
        if (-not $oz.ContainsKey("$n")) { continue }
        $v = ([string]$oz["$n"]).Trim()
        if ($v.Length -gt 100) { SendJson $ctx 400 @{ ok = $false; error = "Ozel kod cok uzun (en fazla 100 karakter)." }; return }
        $vals["$n"] = $v
    }
    if ($vals.Count -eq 0) { SendJson $ctx 400 @{ ok = $false; error = "Degisiklik yok." }; return }
    $keys = @($vals.Keys | Sort-Object { [int]$_ })
    $sql = "SET XACT_ABORT ON; BEGIN TRAN; UPDATE dbo.F0101TBLSTOKLAR SET " + (($keys | ForEach-Object { "KOD$_ = NULLIF(@k$_, N'')" }) -join ", ") + " WHERE IND = @s; DECLARE @n int = @@ROWCOUNT; "
    foreach ($k in $keys) { $sql += "IF @n = 1 AND @k$k <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = $k AND KOD = @k$k) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k$k, $k); " }
    $sql += "COMMIT; SELECT @n;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        [void]$cmd.Parameters.AddWithValue("@s", $stok)
        foreach ($k in $keys) { [void]$cmd.Parameters.AddWithValue("@k$k", [string]$vals[$k]) }
        $n = [int]$cmd.ExecuteScalar()
    } finally { $conn.Close() }
    if ($n -ne 1) { SendJson $ctx 404 @{ ok = $false; error = "Urun bulunamadi." }; return }
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    $ozet = ($keys | ForEach-Object { "KOD$_=" + $vals[$_] }) -join " "
    Add-Content -Path $changeLog -Value ("{0:yyyy-MM-dd HH:mm:ss};OZELKOD;{1};{2};{3}" -f (Get-Date), $stok, $ozet.Replace(";", " "), $ip) -Encoding UTF8
    Log "Ozel kod degisti: stok $stok, $ozet ($ip)"
    SendJson $ctx 200 @{ ok = $true }
}

$script:icerikCache = $null
$script:icerikAt = [datetime]::MinValue

function Invoke-CLHelper([string[]]$argList) {
    $mdb = Get-CLMdb
    if (-not $mdb) { throw "CL veritabani ayarli degil." }
    $helper = Join-Path $root "cl-yaz.ps1"
    if (-not (Test-Path $helper)) { throw "cl-yaz.ps1 yok." }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    try {
        $env:FG_CLPW = Get-CLPw
        return @(& $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb @argList 2>&1 | ForEach-Object { [string]$_ })
    } finally { $env:FG_CLPW = "" }
}

function Get-Icerikler {
    if ($script:icerikCache -and ((Get-Date) - $script:icerikAt).TotalSeconds -lt 60) { return $script:icerikCache }
    $out = Invoke-CLHelper @("-IcerikListe")
    if (-not ($out | Where-Object { $_ -eq "OK icerik-liste" })) { throw ("CL okunamadi: " + (($out | Select-Object -Last 1) -join "")) }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($l in $out) {
        $p = $l -split "`t"
        if ($p.Count -lt 3 -or $p[0] -ne "ING") { continue }
        $t = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p[2]))
        [void]$parts.Add(('{"kod":' + [int]$p[1] + ',"metin":' + (J $t) + '}'))
    }
    $script:icerikCache = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"icerikler":[' + ($parts -join ",") + ']}')
    $script:icerikAt = Get-Date
    return $script:icerikCache
}

$paketFile = Join-Path $root "paket-terazi.txt"
function Get-PaketTerazileri {
    $txt = "192.168.1.153,192.168.1.204"
    try { if (Test-Path $paketFile) { $t = ([System.IO.File]::ReadAllText($paketFile)).Trim(); if ($t) { $txt = $t } } } catch { }
    return @($txt -split '[,;\s]+' | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
}

function Build-IcerikPaket([int]$kod, [string]$metin) {
    $enc = [System.Text.Encoding]::GetEncoding(1254)
    $t = $enc.GetBytes(($metin -replace "`r`n", "`n"))
    $bas = [System.Text.Encoding]::ASCII.GetBytes(("X=00.D={0:X3}." -f $t.Length))
    $body = New-Object byte[] ($bas.Length + $t.Length)
    [Array]::Copy($bas, 0, $body, 0, $bas.Length)
    [Array]::Copy($t, 0, $body, $bas.Length, $t.Length)
    $cs = 0
    foreach ($b in $body) { $cs = $cs -bxor $b }
    $hdr = [System.Text.Encoding]::ASCII.GetBytes(("W30F01,{0:X4}L{1:X3}:" -f $kod, $body.Length))
    $pk = New-Object byte[] ($hdr.Length + $body.Length + 1)
    [Array]::Copy($hdr, 0, $pk, 0, $hdr.Length)
    [Array]::Copy($body, 0, $pk, $hdr.Length, $body.Length)
    $pk[$pk.Length - 1] = [byte]$cs
    return , $pk
}

function Send-Paket([string]$ip, [byte[]]$pk, [string]$beklenen) {
    $cl = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $cl.BeginConnect($ip, 20304, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { return "baglanti zaman asimi" }
        $cl.EndConnect($iar)
        $cl.ReceiveTimeout = 4000; $cl.SendTimeout = 4000
        $ns = $cl.GetStream()
        $ns.Write($pk, 0, $pk.Length); $ns.Flush()
        $buf = New-Object byte[] 256
        $txt = ""
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalMilliseconds -lt 4000) {
            if ($ns.DataAvailable) {
                $n = $ns.Read($buf, 0, 256)
                for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -ge 32 -and $buf[$i] -lt 127) { $txt += [char]$buf[$i] } }
                if ($txt -match 'W\d\d:O\d+') { break }
            } else { Start-Sleep -Milliseconds 80 }
        }
        if ($txt -match [regex]::Escape($beklenen)) { return "OK" }
        if ($txt) { return "cevap=$txt" }
        return "cevap yok"
    } catch { return $_.Exception.Message } finally { $cl.Close() }
}

function Send-Icerik([int]$kod, [string]$metin) {
    $pk = Build-IcerikPaket $kod $metin
    $sonuc = New-Object System.Collections.Generic.List[string]
    foreach ($ip in (Get-PaketTerazileri)) {
        $r = Send-Paket $ip $pk "W30:O0001"
        Log "Icerik $kod -> $ip : $r"
        [void]$sonuc.Add($(if ($r -eq "OK") { "OK $ip" } else { "FAIL $ip $r" }))
    }
    return , $sonuc
}

function Set-Icerik($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Degistirme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $kod = [int]$b["kod"]
    $metin = [string]$b["metin"]
    if ($kod -le 0 -or $kod -gt 9999) { SendJson $ctx 400 @{ ok = $false; error = "Icerik kodu 1-9999 olmali." }; return }
    if (-not $metin.Trim() -or $metin.Length -gt 3000) { SendJson $ctx 400 @{ ok = $false; error = "Icerik metni bos ya da cok uzun." }; return }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($metin))
    $res = (Invoke-CLHelper @("-IcerikYaz", "-Item", "$kod", "-TextB64", $b64) | Where-Object { $_ } | Select-Object -Last 1)
    $script:icerikCache = $null
    if (-not ($res -like "OK icerik-*")) { Log "Icerik yazilamadi: $kod -> $res"; SendJson $ctx 500 @{ ok = $false; error = "CL'ye yazilamadi: $res" }; return }
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    Add-Content -Path $changeLog -Value ("{0:yyyy-MM-dd HH:mm:ss};ICERIK;{1};{2};{3}" -f (Get-Date), $kod, ($res -split " ")[1], $ip) -Encoding UTF8
    Log "Icerik kaydedildi: $kod ($res, $ip)"
    $teraziMesaj = ""
    if ([bool]$b["gonder"]) {
        $lines = Send-Icerik $kod $metin
        $ok = @($lines | Where-Object { $_ -like "OK *" } | ForEach-Object { ($_ -split " ")[1] })
        $bad = @($lines | Where-Object { $_ -like "FAIL *" } | ForEach-Object { ($_ -split " ")[1] })
        if ($bad.Count -eq 0 -and $ok.Count -gt 0) { $teraziMesaj = "Paket terazilerine gonderildi (" + ($ok -join ", ") + ")." }
        elseif ($ok.Count -gt 0) { $teraziMesaj = "Gonderildi: " + ($ok -join ", ") + ". Ulasilamadi: " + ($bad -join ", ") + ", onlar icin CL Works'te Gonder'e basin." }
        else { $teraziMesaj = "Paket terazilerine ulasilamadi (" + ($bad -join ", ") + "). CL Works'te Gonder'e basin." }
    }
    SendJson $ctx 200 @{ ok = $true; kod = $kod; yeni = [bool]($res -like "OK icerik-eklendi*"); teraziMesaj = [string]$teraziMesaj }
}

function Add-Unit($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Degistirme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $stok = [int]$b["stok"]
    $birim = ([string]$b["birim"]).Trim().ToUpperInvariant()
    $barkod = ([string]$b["barkod"]).Trim()
    $agirlik = [decimal]$b["agirlik"]
    $fiyat = [decimal]$b["fiyat"]
    if ($stok -le 0 -or -not $birim -or $birim.Length -gt 30) { SendJson $ctx 400 @{ ok = $false; error = "Birim adi gecersiz." }; return }
    if (-not $barkod -or $barkod.Length -gt 50) { SendJson $ctx 400 @{ ok = $false; error = "Barkod bos ya da cok uzun." }; return }
    if ($agirlik -lt 0 -or $agirlik -gt 1000) { SendJson $ctx 400 @{ ok = $false; error = "Agirlik gecersiz." }; return }
    if ($fiyat -le 0 -or $fiyat -ge 1000000) { SendJson $ctx 400 @{ ok = $false; error = "Fiyat gecersiz." }; return }
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $sonuc = 0; $neden = ""; $adOut = ""
    try {
        $conn.Open()
        $cc = $conn.CreateCommand()
        $cc.CommandText = "SELECT c.name FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.F0101TBLBIRIMLEREX') AND c.is_identity = 0 AND c.is_computed = 0 AND t.name NOT IN ('timestamp', 'rowversion') ORDER BY c.column_id"
        $cr = $cc.ExecuteReader()
        $cols = New-Object System.Collections.Generic.List[string]
        while ($cr.Read()) { [void]$cols.Add([string]$cr[0]) }
        $cr.Close()
        $over = @{
            BIRIMADI = "@birim"; AGIRLIK = "@agirlik"; BARCODE = "@barkod"
            BARCODESTD = "CASE WHEN LEN(@barkod) = 13 AND @barkod NOT LIKE '%[^0-9]%' THEN 1 WHEN t.IND = @ana AND t.BARCODESTD = 5 THEN 0 ELSE t.BARCODESTD END"
            VARSAYILAN = "0"; ANABIRIM = "0"; SATISFIYATI1 = "@fiyat"; SATISFIYATI2 = "0"; SATISFIYATI3 = "0"
            ESKIFIYAT1 = "0"; ESKIFIYAT2 = "0"; ESKIFIYAT3 = "0"; FIYATDEGISMETARIHI1 = "GETDATE()"
        }
        $sel = ($cols | ForEach-Object { if ($over.ContainsKey($_)) { $over[$_] } else { "t.[" + $_ + "]" } }) -join ", "
        $ins = ($cols | ForEach-Object { "[" + $_ + "]" }) -join ", "
        $sql = @"
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @ana int = (SELECT ANABIRIM FROM dbo.F0101TBLSTOKLAR WHERE IND = @s);
IF @ana IS NULL BEGIN ROLLBACK; SELECT -1 AS sonuc, N'stok' AS neden, N'' AS ad; RETURN; END;
DECLARE @var nvarchar(200) = (SELECT TOP 1 s.MALINCINSI FROM dbo.F0101TBLBIRIMLEREX b WITH (UPDLOCK, HOLDLOCK) JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE b.BARCODE = @barkod);
IF @var IS NOT NULL BEGIN ROLLBACK; SELECT -1 AS sonuc, N'barkod' AS neden, @var AS ad; RETURN; END;
DECLARE @tpl int = (SELECT TOP 1 IND FROM dbo.F0101TBLBIRIMLEREX WHERE STOKNO = @s AND IND <> @ana ORDER BY IND DESC);
IF @tpl IS NULL SET @tpl = @ana;
INSERT INTO dbo.F0101TBLBIRIMLEREX ($ins) SELECT $sel FROM dbo.F0101TBLBIRIMLEREX t WHERE t.IND = @tpl AND t.STOKNO = @s;
IF @@ROWCOUNT <> 1 BEGIN ROLLBACK; SELECT -1 AS sonuc, N'sablon' AS neden, N'' AS ad; RETURN; END;
DECLARE @yeni int = SCOPE_IDENTITY();
COMMIT;
SELECT @yeni AS sonuc, N'' AS neden, N'' AS ad;
"@
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        [void]$cmd.Parameters.AddWithValue("@s", $stok)
        [void]$cmd.Parameters.AddWithValue("@birim", $birim)
        [void]$cmd.Parameters.AddWithValue("@barkod", $barkod)
        [void]$cmd.Parameters.AddWithValue("@agirlik", $agirlik)
        [void]$cmd.Parameters.AddWithValue("@fiyat", $fiyat)
        $r = $cmd.ExecuteReader()
        if ($r.Read()) { $sonuc = [int]$r["sonuc"]; $neden = [string]$r["neden"]; $adOut = [string]$r["ad"] }
        $r.Close()
    } finally { $conn.Close() }
    if ($sonuc -le 0) {
        $msg = "Birim eklenemedi."
        if ($neden -eq "barkod") { $msg = "Bu barkod zaten kayitli: $adOut" }
        elseif ($neden -eq "stok") { $msg = "Urun bulunamadi." }
        SendJson $ctx 409 @{ ok = $false; error = [string]$msg }
        return
    }
    $script:cache = $null
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    Add-Content -Path $changeLog -Value ("{0:yyyy-MM-dd HH:mm:ss};BIRIM;{1};{2};{3};{4};{5};{6}" -f (Get-Date), $stok, $birim, $agirlik, $barkod, $fiyat, $ip) -Encoding UTF8
    Log "Birim eklendi: stok $stok, $birim $agirlik kg, $barkod, $fiyat ($ip)"
    SendJson $ctx 200 @{ ok = $true; ind = [int]$sonuc }
}

function Get-LabelData([int]$ind) {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT s.*, b.BARCODE AS E_BARKOD, CASE WHEN ISNULL(b.SATISFIYATI1,0)>0 THEN b.SATISFIYATI1 ELSE ISNULL(b.SATISFIYATI,0) END AS E_FIYAT, b.FIYATDEGISMETARIHI1 AS E_TARIH, b.AGIRLIK AS E_AGIRLIK, b.BIRIMADI AS E_BIRIM FROM dbo.F0101TBLBIRIMLEREX b JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE b.IND = @i"
        [void]$cmd.Parameters.AddWithValue("@i", $ind)
        $r = $cmd.ExecuteReader()
        try {
            if (-not $r.Read()) { return $null }
            $cols = @{}
            for ($i = 0; $i -lt $r.FieldCount; $i++) { if (-not $cols.ContainsKey($r.GetName($i))) { $cols[$r.GetName($i)] = $i } }
            $v = { param($n) if ($cols.ContainsKey($n) -and -not $r.IsDBNull($cols[$n])) { $r.GetValue($cols[$n]) } else { $null } }
            $tarih = & $v "E_TARIH"
            $tarihTxt = if ($tarih) { ([datetime]$tarih).ToString("yyyy-MM-ddTHH:mm:ss") } else { "" }
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append('{"ok":true,"ad":').Append((J ([string](& $v "MALINCINSI"))))
            [void]$sb.Append(',"barkod":').Append((J ([string](& $v "E_BARKOD")).Trim()))
            [void]$sb.Append(',"fiyat":').Append((N ([double](& $v "E_FIYAT"))))
            [void]$sb.Append(',"agirlik":').Append((N ([double](& $v "E_AGIRLIK"))))
            [void]$sb.Append(',"birim":').Append((J ([string](& $v "E_BIRIM"))))
            [void]$sb.Append(',"tarih":').Append((J $tarihTxt))
            foreach ($k in @("KOD6", "KOD7", "KOD10")) { [void]$sb.Append(',"' + $k.ToLowerInvariant() + '":').Append((J ([string](& $v $k)).Trim())) }
            [void]$sb.Append('}')
            return ,([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
        } finally { $r.Close() }
    } finally { $conn.Close() }
}

$printerFile = Join-Path $root "yazici.txt"
function Get-LabelPrinter {
    Add-Type -AssemblyName System.Drawing
    $all = @([System.Drawing.Printing.PrinterSettings]::InstalledPrinters)
    if (Test-Path $printerFile) {
        $n = ([System.IO.File]::ReadAllText($printerFile)).Trim()
        if ($n -and ($all -contains $n)) { return $n }
    }
    $hit = @($all | Where-Object { $_ -match '(?i)barkod|sbarco|etiket' }) | Select-Object -First 1
    return [string]$hit
}

function Print-Label([byte[]]$png, [int]$kopya) {
    Add-Type -AssemblyName System.Drawing
    $name = Get-LabelPrinter
    if (-not $name) { throw "Etiket yazicisi bulunamadi. C:\FiyatGor\yazici.txt dosyasina yazicinin adini yazin." }
    $ms = New-Object System.IO.MemoryStream(, $png)
    $img = [System.Drawing.Image]::FromStream($ms)
    $doc = New-Object System.Drawing.Printing.PrintDocument
    try {
        $doc.PrinterSettings.PrinterName = $name
        if (-not $doc.PrinterSettings.IsValid) { throw "Yazici kullanilamiyor: $name" }
        $doc.DocumentName = "FiyatGor etiket"
        $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
        $doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
        $ps = $null
        foreach ($p in $doc.PrinterSettings.PaperSizes) { if ([math]::Abs($p.Width - 150) -le 3 -and [math]::Abs($p.Height - 389) -le 3) { $ps = $p; break } }
        if (-not $ps) { $ps = New-Object System.Drawing.Printing.PaperSize("Etiket 38x98.8", 150, 389) }
        $doc.DefaultPageSettings.PaperSize = $ps
        $doc.DefaultPageSettings.Landscape = $false
        $state = @{ kalan = $kopya; img = $img }
        $doc.add_PrintPage({
                param($sender, $e)
                $e.Graphics.PageUnit = [System.Drawing.GraphicsUnit]::Millimeter
                $e.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $e.Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $e.Graphics.DrawImage($state.img, (New-Object System.Drawing.RectangleF(0, 0, 38, 98.8)))
                $state.kalan--
                $e.HasMorePages = $state.kalan -gt 0
            }.GetNewClosure())
        $doc.Print()
    } finally {
        $doc.Dispose(); $img.Dispose(); $ms.Dispose()
    }
    return $name
}

function TeraziPlu([string]$stokKodu) {
    if ($stokKodu -match '(?i)TRZ[^0-9]*0*([0-9]+)') { return [int]$Matches[1] }
    return 0
}

function Set-Price($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Fiyat degistirme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $stok = [int]$b["stok"]
    $list = @($b["degisiklikler"])
    if ($stok -le 0 -or $list.Count -lt 1 -or $list.Count -gt 30) { SendJson $ctx 400 @{ ok = $false; error = "Gecersiz istek." }; return }
    foreach ($d in $list) {
        $y = [decimal]$d["yeni"]
        if ([int]$d["ind"] -le 0 -or $y -le 0 -or $y -ge 1000000) { SendJson $ctx 400 @{ ok = $false; error = "Gecersiz fiyat." }; return }
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $done = New-Object System.Collections.Generic.List[string]
    try {
        $conn.Open()
        $tx = $conn.BeginTransaction()
        foreach ($d in $list) {
            $cmd = $conn.CreateCommand()
            $cmd.Transaction = $tx
            $cmd.CommandText = "UPDATE dbo.F0101TBLBIRIMLEREX SET ESKIFIYAT1 = SATISFIYATI1, SATISFIYATI1 = @yeni, FIYATDEGISMETARIHI1 = GETDATE() WHERE IND = @ind AND STOKNO = @stok AND (ABS(ISNULL(SATISFIYATI1, 0) - @eski) < 0.005 OR (ISNULL(SATISFIYATI1, 0) = 0 AND ABS(ISNULL(SATISFIYATI, 0) - @eski) < 0.005))"
            [void]$cmd.Parameters.AddWithValue("@yeni", [decimal]$d["yeni"])
            [void]$cmd.Parameters.AddWithValue("@eski", [decimal]$d["eski"])
            [void]$cmd.Parameters.AddWithValue("@ind", [int]$d["ind"])
            [void]$cmd.Parameters.AddWithValue("@stok", $stok)
            if ($cmd.ExecuteNonQuery() -ne 1) {
                $tx.Rollback()
                $script:cache = $null
                SendJson $ctx 409 @{ ok = $false; error = "Bu urunun fiyati bu arada degismis. Hicbir birim degistirilmedi, liste yenilendi, tekrar deneyin." }
                return
            }
            [void]$done.Add(("{0}:{1}->{2}" -f [int]$d["ind"], [decimal]$d["eski"], [decimal]$d["yeni"]))
        }
        $tx.Commit()
    } finally {
        $conn.Close()
    }
    $script:cache = $null
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    $line = "{0:yyyy-MM-dd HH:mm:ss};FIYAT;{1};{2};{3};{4}" -f (Get-Date), $stok, ([string]$b["ad"]).Replace(";", " "), ($done -join " "), $ip
    Add-Content -Path $changeLog -Value $line -Encoding UTF8
    Log "Fiyat degisti: stok $stok, $($done -join ' ') ($ip)"

    $teraziMesaj = ""
    if (Get-CLMdb) {
        try {
            $q = New-Object System.Data.SqlClient.SqlConnection($connStr)
            $q.Open()
            $qc = $q.CreateCommand()
            $qc.CommandText = "SELECT s.STOKKODU, CASE WHEN ISNULL(b.SATISFIYATI1,0)>0 THEN b.SATISFIYATI1 ELSE ISNULL(b.SATISFIYATI,0) END AS KGFIYAT FROM dbo.F0101TBLSTOKLAR s JOIN dbo.F0101TBLBIRIMLEREX b ON b.IND = s.ANABIRIM WHERE s.IND = @s"
            [void]$qc.Parameters.AddWithValue("@s", $stok)
            $rr = $qc.ExecuteReader()
            $sk = ""; $kg = [decimal]0
            if ($rr.Read()) { $sk = [string]$rr["STOKKODU"]; $kg = [decimal]$rr["KGFIYAT"] }
            $rr.Close(); $q.Close()
            $plu = TeraziPlu $sk
            if ($plu -gt 0 -and $kg -gt 0) {
                $cl = Invoke-CL $plu $kg
                $script:clList = $null
                Log "CL yazma: PLU $plu, fiyat $kg -> $cl"
                if ($cl -like "OK *") {
                    $n = ($cl -split " ")[1]
                    if ([int]$n -ge 1) {
                        $lines = Invoke-CLSend $plu
                        foreach ($l in $lines) { Log "Terazi gonderim: $l" }
                        $teraziMesaj = Format-Send $lines "urun kodu $plu"
                    }
                    else { $teraziMesaj = "Terazide urun kodu $plu bulunamadi, terazi fiyati degismedi. CL Works'te bu urunun kodunu $plu yapin." }
                } elseif ($cl) { $teraziMesaj = "Terazi guncellenemedi." }
            }
        } catch { Log "CL yazma hatasi: $($_.Exception.Message)"; $teraziMesaj = "Terazi guncellenemedi." }
    }
    SendJson $ctx 200 @{ ok = $true; adet = [int]$done.Count; teraziMesaj = [string]$teraziMesaj }
}

function J([string]$v) { return [System.Web.HttpUtility]::JavaScriptStringEncode($v, $true) }
function N($v) { return ([double]$v).ToString([System.Globalization.CultureInfo]::InvariantCulture) }

function Get-Lists {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $sb = New-Object System.Text.StringBuilder
    $hatalar = New-Object System.Collections.Generic.List[string]
    $kdv = New-Object System.Collections.Generic.List[string]
    $birim = New-Object System.Collections.Generic.List[string]
    $fiyatAdi = New-Object System.Collections.Generic.List[string]
    $ozel = @{}
    $next = 1
    $nextBox = New-Object System.Collections.Generic.List[int]
    try {
        $conn.Open()
        $q = {
            param([string]$sql, [string]$ad, [scriptblock]$satir)
            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $sql
                $r = $cmd.ExecuteReader()
                try { while ($r.Read()) { & $satir $r } } finally { $r.Close() }
            } catch {
                [void]$hatalar.Add("$ad`: $($_.Exception.Message)")
                Log "Liste okunamadi ($ad): $($_.Exception.Message)"
            }
        }
        & $q "SELECT IND, ACIKLAMA, KDV FROM dbo.F0101TBLKDVGRUPLARI ORDER BY IND" "kdv" { param($r) [void]$kdv.Add(('{"ind":' + [int]$r["IND"] + ',"ad":' + (J ([string]$r["ACIKLAMA"])) + ',"oran":' + (N $r["KDV"]) + '}')) }
        & $q "SELECT DEGER FROM dbo.TBLBIRIMTAN ORDER BY IND" "birim" { param($r) $v = ([string]$r["DEGER"]).Trim(); if ($v) { [void]$birim.Add((J $v)) } }
        & $q "SELECT DEGER FROM dbo.TBLFIYATTAN ORDER BY IND" "fiyatAdi" { param($r) $v = ([string]$r["DEGER"]).Trim(); if ($v) { [void]$fiyatAdi.Add((J $v)) } }
        & $q "SELECT ISNULL(MAX(CASE WHEN LEN(b.BARCODE) BETWEEN 1 AND 6 AND b.BARCODE NOT LIKE '%[^0-9]%' THEN CAST(b.BARCODE AS int) END), 0) + 1 FROM dbo.F0101TBLBIRIMLEREX b JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE s.STOKKODU LIKE 'TRZ-%'" "sonrakiPlu" { param($r) if (-not ($r[0] -is [DBNull])) { [void]$nextBox.Add([int]$r[0]) } }
        & $q "SELECT KOD, CATEGORY FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY IN (1, 2, 3, 4, 5, 6, 7, 9, 10) AND KOD IS NOT NULL ORDER BY IND DESC" "ozelKodlar" {
            param($r)
            $v = ([string]$r["KOD"]).Trim(); $k = [string][int]$r["CATEGORY"]
            if (-not $v) { return }
            if (-not $ozel.ContainsKey($k)) { $ozel[$k] = New-Object System.Collections.Generic.List[string] }
            if (-not ($ozel[$k] -contains $v)) { [void]$ozel[$k].Add($v) }
        }
        & $q "SELECT ISNULL(MAX(CASE WHEN LEN(SUBSTRING(STOKKODU, 5, 20)) BETWEEN 1 AND 6 AND SUBSTRING(STOKKODU, 5, 20) NOT LIKE '%[^0-9]%' THEN CAST(SUBSTRING(STOKKODU, 5, 20) AS int) END), 0) + 1 FROM dbo.F0101TBLSTOKLAR WHERE STOKKODU LIKE 'TRZ-%'" "sonrakiKod" { param($r) if (-not ($r[0] -is [DBNull])) { [void]$nextBox.Add([int]$r[0]) } }
    } finally {
        $conn.Close()
    }
    if ($nextBox.Count -gt 0) { $next = [int]($nextBox | Measure-Object -Maximum).Maximum }
    if ($birim.Count -eq 0) { foreach ($v in @("ADET", "KG")) { [void]$birim.Add((J $v)) } }
    if ($fiyatAdi.Count -eq 0) { [void]$fiyatAdi.Add((J "FIYAT")) }
    [void]$sb.Append('{"ok":true,"kdv":[').Append(($kdv -join ",")).Append('],"birim":[').Append(($birim -join ",")).Append('],"fiyatAdi":[').Append(($fiyatAdi -join ","))
    [void]$sb.Append('],"ozel":{').Append((($ozel.Keys | Sort-Object | ForEach-Object { '"' + $_ + '":[' + (($ozel[$_] | ForEach-Object { J $_ }) -join ",") + ']' }) -join ",")).Append('}')
    [void]$sb.Append(',"sonrakiPlu":').Append((J ($next.ToString().PadLeft(5, "0")))).Append(',"hatalar":[').Append((($hatalar | ForEach-Object { J $_ }) -join ",")).Append(']}')
    return ,([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
}

function Add-Product($ctx) {
    $b = Read-JsonBody $ctx
    $pinState = Test-Pin ([string]$b["pin"])
    if ($pinState -eq "kapali") { SendJson $ctx 403 @{ ok = $false; error = "Urun ekleme kapali. Kurulumda PIN belirlenmedi." }; return }
    if ($pinState -eq "kilitli") { SendJson $ctx 423 @{ ok = $false; error = "Cok fazla yanlis PIN. 5 dakika bekleyin." }; return }
    if ($pinState -ne "ok") { SendJson $ctx 401 @{ ok = $false; error = "PIN yanlis." }; return }
    $ad = ([string]$b["ad"]).Trim()
    $kod = ([string]$b["stokKodu"]).Trim()
    $barkod = ([string]$b["barkod"]).Trim()
    $birim = ([string]$b["birim"]).Trim().ToUpperInvariant()
    $fiyatAdi = ([string]$b["fiyatAdi"]).Trim()
    $uretici = ([string]$b["uretici"]).Trim()
    $f1 = [decimal]$b["fiyat1"]; $f2 = [decimal]$b["fiyat2"]; $f3 = [decimal]$b["fiyat3"]
    $alis = [decimal]$b["alisFiyati"]
    $alisKdv = [int]$b["alisKdv"]
    $kdvGrubu = [int]$b["kdvGrubu"]
    $kdvDahil = [bool]$b["kdvDahil"]
    $terazi = [bool]$b["terazi"]
    if (-not $ad -or $ad.Length -gt 100) { SendJson $ctx 400 @{ ok = $false; error = "Stok adi bos ya da cok uzun." }; return }
    if (-not $kod -or $kod.Length -gt 50) { SendJson $ctx 400 @{ ok = $false; error = "Stok kodu bos ya da cok uzun." }; return }
    if ($barkod.Length -gt 50) { SendJson $ctx 400 @{ ok = $false; error = "Barkod cok uzun." }; return }
    if ($f1 -le 0 -or $f1 -ge 1000000 -or $f2 -lt 0 -or $f3 -lt 0 -or $alis -lt 0) { SendJson $ctx 400 @{ ok = $false; error = "Fiyatlari kontrol edin." }; return }
    if (-not $birim) { $birim = "ADET" }
    if (-not $fiyatAdi) { $fiyatAdi = "FIYAT" }
    $ozelKod = @{}
    $oz = $b["ozel"]
    foreach ($n in @(1, 2, 3, 4, 5, 6, 7, 9, 10)) {
        $v = ""
        if ($oz -and $oz.ContainsKey("$n")) { $v = ([string]$oz["$n"]).Trim() }
        if ($v.Length -gt 100) { SendJson $ctx 400 @{ ok = $false; error = "Ozel kod cok uzun (en fazla 100 karakter)." }; return }
        $ozelKod["$n"] = $v
    }
    $clIstek = $null
    if ($terazi -and $b["cl"] -and (Get-CLMdb)) {
        $c = $b["cl"]
        $clIstek = @{ plu = [int]$c["plu"]; tip = [int]$c["tip"]; icerik = [int]$c["icerik"]; skt = [int]$c["skt"]; ad = ([string]$c["ad"]).Trim(); item = (TeraziPlu $kod) }
        if ($clIstek.plu -le 0 -or $clIstek.plu -ge 1000) { SendJson $ctx 400 @{ ok = $false; error = "Terazi PLU no 1 ile 999 arasinda olmali." }; return }
        if ($clIstek.tip -ne 1 -and $clIstek.tip -ne 2) { SendJson $ctx 400 @{ ok = $false; error = "Terazi tipi 1 (Agirlik) ya da 2 (Adet) olmali." }; return }
        if ($clIstek.icerik -lt 0 -or $clIstek.icerik -gt 65535) { SendJson $ctx 400 @{ ok = $false; error = "Icerik no gecersiz." }; return }
        if ($clIstek.skt -lt 0 -or $clIstek.skt -gt 9999) { SendJson $ctx 400 @{ ok = $false; error = "Son kullanma gecersiz." }; return }
        if (-not $clIstek.ad -or $clIstek.ad.Length -gt 60) { SendJson $ctx 400 @{ ok = $false; error = "Terazideki ad bos ya da cok uzun." }; return }
        if ($clIstek.item -le 0) { SendJson $ctx 400 @{ ok = $false; error = "Terazi urunu icin stok kodu TRZ-sayi seklinde olmali (ornek TRZ-650)." }; return }
        $used = Get-CLUsed
        if ($used.ContainsKey($clIstek.plu)) {
            $oneri = 1; while ($oneri -lt 1000 -and $used.ContainsKey($oneri)) { $oneri++ }
            SendJson $ctx 409 @{ ok = $false; error = ("Terazide PLU {0} dolu ({1}). Ilk bos PLU: {2}. Hicbir sey eklenmedi." -f $clIstek.plu, $used[$clIstek.plu], $oneri); oneri = [int]$oneri }
            return
        }
    }
    $std = 0
    if ($terazi) { $std = 5 }
    elseif ($barkod -match '^\d{13}$') { $std = 1 }
    $maliyet = if ($alis -gt 0) { $alis } else { $f1 }
    $sql = @"
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @kdv decimal(18, 8) = (SELECT KDV FROM dbo.F0101TBLKDVGRUPLARI WHERE IND = @kdvGrubu);
IF @kdv IS NULL BEGIN ROLLBACK; SELECT -1 AS sonuc, N'kdv' AS neden, N'' AS ad; RETURN; END;
DECLARE @var nvarchar(200) = (SELECT TOP 1 MALINCINSI FROM dbo.F0101TBLSTOKLAR WITH (UPDLOCK, HOLDLOCK) WHERE STOKKODU = @kod);
IF @var IS NOT NULL BEGIN ROLLBACK; SELECT -1 AS sonuc, N'kod' AS neden, @var AS ad; RETURN; END;
IF @barkod <> N''
BEGIN
  SET @var = (SELECT TOP 1 s.MALINCINSI FROM dbo.F0101TBLBIRIMLEREX b WITH (UPDLOCK, HOLDLOCK) JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE b.BARCODE = @barkod);
  IF @var IS NOT NULL BEGIN ROLLBACK; SELECT -1 AS sonuc, N'barkod' AS neden, @var AS ad; RETURN; END;
END;
INSERT INTO dbo.F0101TBLSTOKLAR (MALINCINSI, STOKKODU, DEPOSEVIYESI, URETICI, AYLIKVADE, DEPO, GARANTI, PRIM, IPTAL, STOKTIPI, STOKTAKIP, TEMINYERI, RAFOMRU, KALAN, REZERV,
  KOD1, KOD2, KOD3, KOD4, KOD5, KOD6, KOD7, KOD8, KOD9, KOD10, TAKSITSAYISI, ALISFIYATI, ESKIALISFIYATI, KARTINACILMATARIHI, MALIYET, KDVGRUBU, AKTIF,
  ISCILIKIND, ISCILIKBIRIMIND, ISCILIKACIKLAMA, STATUS, OIV, KARORANI, OTV, ALISKDVORANI)
VALUES (@ad, @kod, 1, NULLIF(@uretici, N''), 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  @k1, @k2, @k3, @k4, @k5, @k6, @k7, N'', NULLIF(@k9, N''), NULLIF(@k10, N''), 0, @alis, 0, GETDATE(), @maliyet, @kdvGrubu, 0,
  0, 0, N'', 1, 0, 0, 0, @alisKdv);
DECLARE @s int = SCOPE_IDENTITY();
INSERT INTO dbo.F0101TBLBIRIMLEREX (BIRIMADI, CARPAN, BARCODE, BARCODESTD, STOKNO, ACIKLAMA, KDV, KDVDAHIL, EN, BOY, YUKSEKLIK, AGIRLIK, HACIM,
  SATISFIYATI1, SATISFIYATI2, SATISFIYATI3, PB1, PB2, PB3, ESKIFIYAT1, ESKIFIYAT2, ESKIFIYAT3, FIYATDEGISMETARIHI1, VARSAYILAN, ANABIRIM)
VALUES (@birim, 1, @barkod, @std, @s, @fiyatAdi, @kdv, @kdvDahil, 0, 0, 0, 0, 0,
  @f1, @f2, @f3, N'TL', N'TL', N'TL', 0, 0, 0, GETDATE(), 1, 1);
DECLARE @bi int = SCOPE_IDENTITY();
UPDATE dbo.F0101TBLSTOKLAR SET ANABIRIM = @bi, BIRIMEX = @bi WHERE IND = @s;
IF @k1 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 1 AND KOD = @k1) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k1, 1);
IF @k2 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 2 AND KOD = @k2) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k2, 2);
IF @k3 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 3 AND KOD = @k3) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k3, 3);
IF @k4 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 4 AND KOD = @k4) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k4, 4);
IF @k5 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 5 AND KOD = @k5) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k5, 5);
IF @k6 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 6 AND KOD = @k6) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k6, 6);
IF @k7 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 7 AND KOD = @k7) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k7, 7);
IF @k9 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 9 AND KOD = @k9) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k9, 9);
IF @k10 <> N'' AND NOT EXISTS (SELECT 1 FROM dbo.F0101TBLSTOKKODTAN WHERE CATEGORY = 10 AND KOD = @k10) INSERT INTO dbo.F0101TBLSTOKKODTAN (KOD, CATEGORY) VALUES (@k10, 10);
COMMIT;
SELECT @s AS sonuc, N'' AS neden, CAST(@bi AS nvarchar(20)) AS ad;
"@
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $sonuc = 0; $neden = ""; $adOut = ""
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        [void]$cmd.Parameters.AddWithValue("@ad", $ad)
        [void]$cmd.Parameters.AddWithValue("@kod", $kod)
        [void]$cmd.Parameters.AddWithValue("@barkod", $barkod)
        [void]$cmd.Parameters.AddWithValue("@birim", $birim)
        [void]$cmd.Parameters.AddWithValue("@fiyatAdi", $fiyatAdi)
        [void]$cmd.Parameters.AddWithValue("@uretici", $uretici)
        [void]$cmd.Parameters.AddWithValue("@f1", $f1)
        [void]$cmd.Parameters.AddWithValue("@f2", $f2)
        [void]$cmd.Parameters.AddWithValue("@f3", $f3)
        [void]$cmd.Parameters.AddWithValue("@alis", $alis)
        [void]$cmd.Parameters.AddWithValue("@maliyet", [decimal]$maliyet)
        [void]$cmd.Parameters.AddWithValue("@alisKdv", $alisKdv)
        [void]$cmd.Parameters.AddWithValue("@kdvGrubu", $kdvGrubu)
        [void]$cmd.Parameters.AddWithValue("@kdvDahil", $kdvDahil)
        [void]$cmd.Parameters.AddWithValue("@std", $std)
        foreach ($n in @(1, 2, 3, 4, 5, 6, 7, 9, 10)) { [void]$cmd.Parameters.AddWithValue("@k$n", [string]$ozelKod["$n"]) }
        $r = $cmd.ExecuteReader()
        if ($r.Read()) { $sonuc = [int]$r["sonuc"]; $neden = [string]$r["neden"]; $adOut = [string]$r["ad"] }
        $r.Close()
    } finally {
        $conn.Close()
    }
    if ($sonuc -le 0) {
        $msg = "Urun eklenemedi."
        if ($neden -eq "kod") { $msg = "Bu stok kodu zaten kayitli: $adOut" }
        elseif ($neden -eq "barkod") { $msg = "Bu barkod zaten kayitli: $adOut" }
        elseif ($neden -eq "kdv") { $msg = "KDV grubu bulunamadi." }
        SendJson $ctx 409 @{ ok = $false; error = [string]$msg }
        return
    }
    $script:cache = $null
    $ip = [string]$ctx.Request.RemoteEndPoint.Address
    $line = "{0:yyyy-MM-dd HH:mm:ss};EKLE;{1};{2};{3};{4};{5}" -f (Get-Date), $sonuc, $kod, $ad.Replace(";", " "), $f1, $ip
    Add-Content -Path $changeLog -Value $line -Encoding UTF8
    Log "Urun eklendi: $kod $ad ($ip)"
    $clMesaj = ""
    if ($clIstek) {
        $res = Invoke-CLAdd $clIstek.plu $clIstek.item $f1 $clIstek.ad $clIstek.tip $clIstek.icerik $clIstek.skt
        Log "CL ekleme: PLU $($clIstek.plu), urun kodu $($clIstek.item) -> $res"
        $script:clList = $null
        if ($res -like "OK eklendi*") {
            $lines = Invoke-CLSend 0 $clIstek.plu
            foreach ($l in $lines) { Log "Terazi gonderim: $l" }
            $clMesaj = "CL'ye PLU $($clIstek.plu) olarak eklendi. " + (Format-Send $lines "PLU $($clIstek.plu)")
        } elseif ($res -like "ERR plu-dolu*") {
            $clMesaj = "Kasaya eklendi ama terazide PLU $($clIstek.plu) bu arada dolmus. CL'ye elle ekleyin. Ilk bos PLU: " + ($res -split " ")[2]
        } else {
            $clMesaj = "Kasaya eklendi ama CL'ye eklenemedi ($res). CL Works'te elle ekleyin."
        }
    }
    SendJson $ctx 200 @{ ok = $true; stok = [int]$sonuc; birimind = [int]$adOut; clMesaj = [string]$clMesaj }
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
            SendJson $ctx 503 @{ ok = $false; error = [string]$script:lastError }
        }
        return
    }
    if ($path -eq "/api/yetki") {
        $pinVar = [bool](Test-Path $pinFile)
        SendJson $ctx 200 @{ ok = $true; fiyat = $pinVar }
        return
    }
    if ($path -eq "/api/birimler") {
        try {
            $q = [int]("0" + [string]$ctx.Request.QueryString["ind"])
            $res = Get-Units $q
            if ($res) { Send $ctx 200 "application/json; charset=utf-8" $res $true } else { SendJson $ctx 404 @{ ok = $false; error = "Urun bulunamadi." } }
        } catch {
            Log "Birimler okunamadi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/guncelle") {
        if ($ctx.Request.HttpMethod -ne "POST") { SendJson $ctx 405 @{ ok = $false; error = "POST gerekli" }; return }
        try {
            $ok = Update-Web
            $script:cache = $null
            SendJson $ctx 200 @{ ok = [bool]$ok; mesaj = $(if ($ok) { "Guncellendi" } else { "Guncellenemedi" }) }
        } catch { SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message } }
        return
    }
    if ($path -eq "/api/terazi") {
        try { Send $ctx 200 "application/json; charset=utf-8" (Get-CLList) $true } catch {
            Log "CL listesi okunamadi: $($_.Exception.Message)"
            SendJson $ctx 503 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/birim") {
        if ($ctx.Request.HttpMethod -ne "POST") { SendJson $ctx 405 @{ ok = $false; error = "POST gerekli" }; return }
        try { Add-Unit $ctx } catch {
            Log "Birim eklenemedi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = "Birim eklenemedi: $($_.Exception.Message)" }
        }
        return
    }
    if ($path -eq "/api/icerik") {
        try {
            if ($ctx.Request.HttpMethod -eq "POST") { Set-Icerik $ctx }
            else { Send $ctx 200 "application/json; charset=utf-8" (Get-Icerikler) $true }
        } catch {
            Log "Icerik hatasi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/ozel") {
        try {
            if ($ctx.Request.HttpMethod -eq "POST") { Set-Ozel $ctx }
            else {
                $res = Get-Ozel ([int]("0" + [string]$ctx.Request.QueryString["stok"]))
                if ($res) { Send $ctx 200 "application/json; charset=utf-8" $res $true } else { SendJson $ctx 404 @{ ok = $false; error = "Urun bulunamadi." } }
            }
        } catch {
            Log "Ozel kod hatasi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/etiket") {
        try {
            if ($ctx.Request.HttpMethod -eq "POST") {
                $kopya = [int]("0" + [string]$ctx.Request.QueryString["kopya"])
                if ($kopya -lt 1 -or $kopya -gt 50) { SendJson $ctx 400 @{ ok = $false; error = "Kopya sayisi 1-50 olmali." }; return }
                if ($ctx.Request.ContentLength64 -le 0 -or $ctx.Request.ContentLength64 -gt 2MB) { SendJson $ctx 400 @{ ok = $false; error = "Etiket resmi gecersiz." }; return }
                $buf = New-Object System.IO.MemoryStream
                $ctx.Request.InputStream.CopyTo($buf)
                $png = $buf.ToArray()
                if ($png.Length -lt 8 -or $png[0] -ne 0x89 -or $png[1] -ne 0x50) { SendJson $ctx 400 @{ ok = $false; error = "Etiket resmi PNG degil." }; return }
                $yazici = Print-Label $png $kopya
                Log ("Etiket yazdirildi: {0} kopya, {1} ({2})" -f $kopya, ([string]$ctx.Request.QueryString["ad"]), $yazici)
                SendJson $ctx 200 @{ ok = $true; yazici = [string]$yazici; kopya = $kopya }
            } else {
                $q = [int]("0" + [string]$ctx.Request.QueryString["ind"])
                $res = Get-LabelData $q
                if ($res) { Send $ctx 200 "application/json; charset=utf-8" $res $true } else { SendJson $ctx 404 @{ ok = $false; error = "Birim bulunamadi." } }
            }
        } catch {
            Log "Etiket hatasi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/listeler") {
        try { Send $ctx 200 "application/json; charset=utf-8" (Get-Lists) $true } catch {
            Log "Listeler okunamadi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = [string]$_.Exception.Message }
        }
        return
    }
    if ($path -eq "/api/urun") {
        if ($ctx.Request.HttpMethod -ne "POST") { SendJson $ctx 405 @{ ok = $false; error = "POST gerekli" }; return }
        try { Add-Product $ctx } catch {
            Log "Urun eklenemedi: $($_.Exception.Message)"
            SendJson $ctx 500 @{ ok = $false; error = "Urun eklenemedi: $($_.Exception.Message)" }
        }
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
        SendJson $ctx 200 @{ ok = $true; sql = [bool]$sqlOk; error = [string]$script:lastError; computer = [string]$env:COMPUTERNAME }
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
if (-not $env:FG_YENIDEN -and (Get-FileHash -LiteralPath $selfPath).Hash -ne $selfHash) {
    Log "Sunucu dosyasi guncellendi, yeni surumle yeniden baslatiliyor"
    $env:FG_YENIDEN = "1"
    & $selfPath -Port $Port
    exit
}

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
