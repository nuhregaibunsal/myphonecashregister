param(
    [string]$Sunucu = "",
    [string]$Veritabani = "",
    [string]$Kullanici = "",
    [string]$Sifre = "",
    [string]$Mdb = "",
    [switch]$Kesfet,
    [string]$Tablo = "",
    [string]$Sorgu = "",
    [string]$Cikti = "urunler.csv",
    [switch]$Sessiz
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
if ($PSScriptRoot) { Set-Location $PSScriptRoot }

$script:Log = New-Object System.Text.StringBuilder
function Say($text, $color = "Gray") {
    Write-Host $text -ForegroundColor $color
    [void]$script:Log.AppendLine($text)
}

function Save-Log {
    try { [System.IO.File]::WriteAllText((Join-Path (Get-Location) "rapor.txt"), $script:Log.ToString(), (New-Object System.Text.UTF8Encoding($true))) } catch { }
}

function Get-SqlInstances {
    $list = New-Object System.Collections.ArrayList
    foreach ($path in @("HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL")) {
        if (Test-Path $path) {
            (Get-ItemProperty $path).PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                if ($_.Name -eq "MSSQLSERVER") { [void]$list.Add("") } else { [void]$list.Add($_.Name) }
            }
        }
    }
    try {
        Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "MSSQLSERVER" -or $_.Name -like 'MSSQL$*' } | ForEach-Object {
            if ($_.Name -eq "MSSQLSERVER") { [void]$list.Add("") } else { [void]$list.Add($_.Name.Substring(6)) }
        }
    } catch { }
    $list | Select-Object -Unique
}

function Show-Services {
    Say "`n--- SQL Server servisleri ---" Cyan
    try {
        $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "MSSQL*" -or $_.Name -like "SQL*" -or $_.DisplayName -like "*SQL*" }
        if (-not $svc) { Say "Bu bilgisayarda SQL Server servisi yok. Veritabani baska bir bilgisayarda olabilir." Yellow }
        foreach ($s in $svc) {
            $state = if ($s.Status -eq "Running") { "CALISIYOR" } else { "DURMUS ($($s.Status))" }
            Say ("  {0,-30} {1,-12} {2}" -f $s.Name, $state, $s.DisplayName)
        }
    } catch { Say "Servisler okunamadi: $($_.Exception.Message)" DarkGray }
}

function Find-ConfigHints {
    Say "`n--- Program ayar dosyalarinda baglanti bilgisi ---" Cyan
    $roots = @("C:\", $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ -and (Test-Path $_) }
    $dirs = foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)vega|faster|pos|kasa|market' } }
    $found = 0
    foreach ($d in ($dirs | Select-Object -Unique)) {
        $files = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue -Include *.ini, *.config, *.xml, *.udl, *.cfg, *.txt, *.json, *.conf | Where-Object { $_.Length -lt 2MB } | Select-Object -First 400
        foreach ($f in $files) {
            try {
                $lines = Select-String -LiteralPath $f.FullName -Pattern '(?i)(data source|server\s*=|sunucu|database\s*=|initial catalog|veritaban|\\sqlexpress|user id|uid\s*=)' -ErrorAction SilentlyContinue | Select-Object -First 8
                foreach ($l in $lines) {
                    $t = $l.Line.Trim() -replace '(?i)((password|pwd|sifre)\s*[=:]\s*)[^;"<\s]+', '$1****'
                    if ($t.Length -gt 220) { $t = $t.Substring(0, 220) }
                    Say "  $($f.FullName): $t"
                    $found++
                }
            } catch { }
        }
    }
    if ($found -eq 0) { Say "  Bulunamadi." DarkGray }
}

function Short($msg) { (($msg -split "`n")[0]).Trim() }

function Try-Open($server, $user, $pass) {
    $db = if ($Veritabani) { $Veritabani } else { "master" }
    $sqlAuth = if ($user) { "User Id=$user;Password=$pass;" } else { "Integrated Security=SSPI;" }
    $num = 0
    try {
        $c = New-Object System.Data.SqlClient.SqlConnection("Server=$server;Database=$db;Connect Timeout=6;$sqlAuth")
        $c.Open()
        Say "Baglandi: $server (SqlClient)" Green
        return $c
    } catch {
        $ex = $_.Exception
        if ($ex.InnerException) { $ex = $ex.InnerException }
        if ($ex -is [System.Data.SqlClient.SqlException]) { $num = $ex.Number }
        Say "  $server [SqlClient, hata $num] -> $(Short $ex.Message)" DarkYellow
        if ($ex.InnerException) { Say "      $(Short $ex.InnerException.Message)" DarkGray }
    }
    if (@(2, 26, 53, -1, -2, 18456, 4060) -contains $num) { return $null }
    $oleAuth = if ($user) { "User ID=$user;Password=$pass;" } else { "Integrated Security=SSPI;" }
    foreach ($prov in @("MSOLEDBSQL", "SQLNCLI11", "SQLNCLI10", "SQLNCLI", "SQLOLEDB")) {
        try {
            $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$server;Initial Catalog=$db;Connect Timeout=6;$oleAuth")
            $c.Open()
            Say "Baglandi: $server ($prov)" Green
            return $c
        } catch {
            $ex = $_.Exception
            if ($ex.InnerException) { $ex = $ex.InnerException }
            $m = Short $ex.Message
            if ($m -notmatch '(?i)not registered|kay.tl. de.il|kayitli degil') { Say "  $server [$prov] -> $m" DarkYellow }
        }
    }
    return $null
}

function Open-Connection {
    if ($Mdb) {
        $full = (Resolve-Path $Mdb).Path
        foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
            try {
                $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$full;Persist Security Info=False;")
                $c.Open()
                Say "MDB acildi ($prov)" Green
                return $c
            } catch { Say "  [$prov] -> $(Short $_.Exception.Message)" DarkYellow }
        }
        throw "MDB acilamadi. 32 bit PowerShell ile deneyin: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    }

    $servers = New-Object System.Collections.ArrayList
    if ($Sunucu) { [void]$servers.Add($Sunucu) }
    else {
        foreach ($i in @(Get-SqlInstances) + @("SQLEXPRESS", "")) {
            foreach ($h in @(".", "127.0.0.1")) {
                $s = if ($i) { "$h\$i" } else { $h }
                if (-not $servers.Contains($s)) { [void]$servers.Add($s) }
            }
        }
        [void]$servers.Add("(localdb)\MSSQLLocalDB")
    }

    Say "`n--- Baglanti denemeleri ---" Cyan
    $user = $Kullanici; $pass = $Sifre
    foreach ($s in $servers) { $c = Try-Open $s $user $pass; if ($c) { return $c } }

    if (-not $user -and -not $Sessiz) {
        Say "`nWindows girisiyle olmadi. Kasa programinin SQL kullanici adi biliniyorsa yazin (genelde sa). Bos birakip Enter'a basarsaniz atlanir." Yellow
        $user = Read-Host "Kullanici adi"
        if ($user) {
            $sec = Read-Host "Sifre" -AsSecureString
            $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            foreach ($s in $servers) { $c = Try-Open $s $user $pass; if ($c) { $script:Kullanici = $user; $script:Sifre = $pass; return $c } }
        }
    }
    throw "Hicbir SQL Server'a baglanilamadi."
}

function Invoke-Query($conn, $sql) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 120
    $t = New-Object System.Data.DataTable
    $t.Load($cmd.ExecuteReader())
    return ,$t
}

function Write-Csv($table, $path) {
    $sb = New-Object System.Text.StringBuilder
    $cols = $table.Columns | ForEach-Object { $_.ColumnName }
    $esc = { param($v) $s = [string]$v; if ($s -match '[;"\r\n]') { '"' + $s.Replace('"', '""') + '"' } else { $s } }
    [void]$sb.AppendLine((($cols | ForEach-Object { & $esc $_ }) -join ";"))
    foreach ($r in $table.Rows) {
        $vals = foreach ($c in $cols) {
            $v = $r[$c]
            if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) { $v.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { & $esc $v }
        }
        [void]$sb.AppendLine(($vals -join ";"))
    }
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}

function Run-Main {
    Say "Fiyat Gor - disari aktarma  ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))" Cyan
    Say "Bilgisayar: $env:COMPUTERNAME  PowerShell: $($PSVersionTable.PSVersion)  64 bit: $([Environment]::Is64BitProcess)"

    $conn = $null
    try {
        if (-not $Mdb) { Show-Services }
        try { $conn = Open-Connection }
        catch {
            Say "`n$($_.Exception.Message)" Red
            if (-not $Mdb) { Find-ConfigHints }
            Say "`nYukaridaki yazilarin tamami rapor.txt dosyasina kaydedildi. Bu dosyayi gonderin." Yellow
            return
        }

        if (-not $Mdb -and -not $Veritabani) {
            $dbs = Invoke-Query $conn "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name"
            Say "`n--- Veritabanlari ---" Cyan
            $dbs.Rows | ForEach-Object { Say "  $($_.name)" }
            if ($dbs.Rows.Count -eq 1) {
                $script:Veritabani = $dbs.Rows[0].name
                $script:Kesfet = $true
                $conn.ChangeDatabase($script:Veritabani)
                Say "`nTek veritabani var, onu inceliyorum: $script:Veritabani" Yellow
            } else {
                Say "`nTekrar calistirin: -Veritabani <ad> -Kesfet" Yellow
                return
            }
        }

        if ($script:Kesfet) {
            $pattern = '(?i)barkod|barcode|fiyat|price|plu|malin|stokad|urunad|birim'
            if ($Mdb) {
                $schema = $conn.GetSchema("Columns")
                $rows = $schema.Rows | Where-Object { $_.TABLE_NAME -notlike "MSys*" } | ForEach-Object { [pscustomobject]@{ Tablo = $_.TABLE_NAME; Sutun = $_.COLUMN_NAME } }
            } else {
                $t = Invoke-Query $conn "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS Tablo, COLUMN_NAME AS Sutun FROM INFORMATION_SCHEMA.COLUMNS"
                $rows = $t.Rows | ForEach-Object { [pscustomobject]@{ Tablo = $_.Tablo; Sutun = $_.Sutun } }
            }
            $groups = $rows | Group-Object Tablo | Where-Object { @($_.Group.Sutun -match $pattern).Count -ge 2 } | Sort-Object { -@($_.Group.Sutun -match $pattern).Count }
            Say "`n--- Barkod/fiyat iceren tablolar ---" Cyan
            foreach ($g in $groups) {
                $name = $g.Name
                $count = ""
                try {
                    $q = if ($Mdb) { "SELECT COUNT(*) FROM [$name]" } else { "SELECT COUNT(*) FROM " + (($name -split '\.' | ForEach-Object { "[$_]" }) -join '.') }
                    $count = (Invoke-Query $conn $q).Rows[0][0]
                } catch { }
                Say ("$name ($count satir): " + (($g.Group.Sutun) -join ", "))
            }
            Say "`nListe rapor.txt dosyasina kaydedildi. Bu dosyayi gonderin." Yellow
            return
        }

        if (-not $Sorgu -and $Tablo) { $script:Sorgu = "SELECT * FROM $Tablo" }
        if (-not $script:Sorgu) { throw "-Kesfet, -Tablo veya -Sorgu verin." }
        $data = Invoke-Query $conn $script:Sorgu
        Write-Csv $data $Cikti
        Say "$($data.Rows.Count) satir yazildi: $(Join-Path (Get-Location) $Cikti)" Green
    } catch {
        Say "`nHATA: $($_.Exception.Message)" Red
    } finally {
        if ($conn) { $conn.Close() }
        Save-Log
    }
}

Run-Main
if (-not $Sessiz) { Write-Host ""; Read-Host "Kapatmak icin Enter'a basin" | Out-Null }
