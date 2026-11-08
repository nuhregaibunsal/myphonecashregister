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
    if ($ctx.Request.ContentLength64 -gt 10000) { throw "istek cok buyuk" }
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
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Item $plu -Price $price 2>&1
        $env:FG_CLPW = ""
        return ([string](@($out) | Where-Object { $_ } | Select-Object -Last 1)).Trim()
    } catch {
        $env:FG_CLPW = ""
        return "ERR $($_.Exception.Message)"
    }
}

function Invoke-CLSend([int]$item) {
    $mdb = Get-CLMdb
    if (-not $mdb) { return @() }
    $helper = Join-Path $root "cl-terazi-gonder.ps1"
    if (-not (Test-Path $helper)) { return @("ERR yardimci-yok") }
    $ps32 = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $ps32)) { $ps32 = "powershell.exe" }
    try {
        $env:FG_CLPW = Get-CLPw
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $helper -Mdb $mdb -Item $item 2>&1
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
                        $son = @($lines | Where-Object { $_ -like "SONUC *" }) | Select-Object -Last 1
                        $fails = @($lines | Where-Object { $_ -like "FAIL *" })
                        if ($son -and $son -match '^SONUC (\d+)/(\d+)') {
                            $okN = [int]$Matches[1]; $allN = [int]$Matches[2]
                            if ($okN -eq $allN) { $teraziMesaj = "Terazilere gonderildi ($okN/$allN, urun kodu $plu)." }
                            elseif ($okN -gt 0) { $teraziMesaj = "Terazilerin bir kismina gonderildi ($okN/$allN). Ulasilamayanlar: " + (($fails | ForEach-Object { ($_ -split " ")[1] }) -join ", ") + ". Onlar icin CL Works'te Gonder'e basin." }
                            else { $teraziMesaj = "CL veritabani guncellendi ama hicbir teraziye ulasilamadi. CL Works'te Gonder'e basin." }
                        } else {
                            $teraziMesaj = "CL veritabani guncellendi, terazilere gonderilemedi. CL Works'te Gonder'e basin."
                        }
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
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT IND, ACIKLAMA, KDV FROM dbo.F0101TBLKDVGRUPLARI ORDER BY IND; SELECT DEGER FROM dbo.TBLBIRIMTAN ORDER BY IND; SELECT DEGER FROM dbo.TBLFIYATTAN ORDER BY IND; SELECT ISNULL(MAX(TRY_CAST(b.BARCODE AS int)), 0) + 1 FROM dbo.F0101TBLBIRIMLEREX b JOIN dbo.F0101TBLSTOKLAR s ON s.IND = b.STOKNO WHERE s.STOKKODU LIKE 'TRZ-%' AND LEN(b.BARCODE) BETWEEN 1 AND 6 AND b.BARCODE NOT LIKE '%[^0-9]%'"
        $r = $cmd.ExecuteReader()
        [void]$sb.Append('{"ok":true,"kdv":[')
        $i = 0
        while ($r.Read()) {
            if ($i -gt 0) { [void]$sb.Append(',') }
            [void]$sb.Append('{"ind":').Append([int]$r["IND"]).Append(',"ad":').Append((J ([string]$r["ACIKLAMA"]))).Append(',"oran":').Append((N $r["KDV"])).Append('}')
            $i++
        }
        [void]$r.NextResult()
        [void]$sb.Append('],"birim":[')
        $i = 0
        while ($r.Read()) { if ($i -gt 0) { [void]$sb.Append(',') }; [void]$sb.Append((J ([string]$r["DEGER"]).Trim())); $i++ }
        [void]$r.NextResult()
        [void]$sb.Append('],"fiyatAdi":[')
        $i = 0
        while ($r.Read()) { if ($i -gt 0) { [void]$sb.Append(',') }; [void]$sb.Append((J ([string]$r["DEGER"]).Trim())); $i++ }
        [void]$r.NextResult()
        $next = 1
        if ($r.Read()) { $next = [int]$r[0] }
        [void]$sb.Append('],"sonrakiPlu":').Append((J ($next.ToString().PadLeft(5, "0")))).Append('}')
        $r.Close()
    } finally {
        $conn.Close()
    }
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
  KOD1, KOD2, KOD3, KOD4, KOD5, KOD6, KOD7, KOD8, TAKSITSAYISI, ALISFIYATI, ESKIALISFIYATI, KARTINACILMATARIHI, MALIYET, KDVGRUBU, AKTIF,
  ISCILIKIND, ISCILIKBIRIMIND, ISCILIKACIKLAMA, STATUS, OIV, KARORANI, OTV, ALISKDVORANI)
VALUES (@ad, @kod, 1, NULLIF(@uretici, N''), 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  N'', N'', N'', N'', N'', N'', N'', N'', 0, @alis, 0, GETDATE(), @maliyet, @kdvGrubu, 0,
  0, 0, N'', 1, 0, 0, 0, @alisKdv);
DECLARE @s int = SCOPE_IDENTITY();
INSERT INTO dbo.F0101TBLBIRIMLEREX (BIRIMADI, CARPAN, BARCODE, BARCODESTD, STOKNO, ACIKLAMA, KDV, KDVDAHIL, EN, BOY, YUKSEKLIK, AGIRLIK, HACIM,
  SATISFIYATI1, SATISFIYATI2, SATISFIYATI3, PB1, PB2, PB3, ESKIFIYAT1, ESKIFIYAT2, ESKIFIYAT3, FIYATDEGISMETARIHI1, VARSAYILAN, ANABIRIM)
VALUES (@birim, 1, @barkod, @std, @s, @fiyatAdi, @kdv, @kdvDahil, 0, 0, 0, 0, 0,
  @f1, @f2, @f3, N'TL', N'TL', N'TL', 0, 0, 0, GETDATE(), 1, 1);
DECLARE @bi int = SCOPE_IDENTITY();
UPDATE dbo.F0101TBLSTOKLAR SET ANABIRIM = @bi, BIRIMEX = @bi WHERE IND = @s;
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
    SendJson $ctx 200 @{ ok = $true; stok = [int]$sonuc; birimind = [int]$adOut }
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
