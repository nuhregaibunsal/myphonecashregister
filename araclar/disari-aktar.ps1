param(
    [string]$Sunucu = "",
    [string]$Veritabani = "",
    [string]$Kullanici = "",
    [string]$Sifre = "",
    [string]$Mdb = "",
    [switch]$Kesfet,
    [string]$Tablo = "",
    [string]$Sorgu = "",
    [string]$Cikti = "urunler.csv"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-SqlInstances {
    $list = @()
    foreach ($path in @("HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL")) {
        if (Test-Path $path) {
            (Get-ItemProperty $path).PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                if ($_.Name -eq "MSSQLSERVER") { $list += "." } else { $list += ".\" + $_.Name }
            }
        }
    }
    $list | Select-Object -Unique
}

function Open-Connection {
    if ($Mdb) {
        $full = (Resolve-Path $Mdb).Path
        foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
            try {
                $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$full;Persist Security Info=False;")
                $c.Open()
                Write-Host "MDB acildi ($prov)" -ForegroundColor Green
                return $c
            } catch { }
        }
        throw "MDB acilamadi. 32 bit PowerShell ile deneyin: C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    }
    $servers = if ($Sunucu) { @($Sunucu) } else { @(Get-SqlInstances) + @(".\SQLEXPRESS", ".", "(localdb)\MSSQLLocalDB") | Select-Object -Unique }
    foreach ($s in $servers) {
        $cs = "Server=$s;Connect Timeout=5;"
        if ($Veritabani) { $cs += "Database=$Veritabani;" }
        if ($Kullanici) { $cs += "User Id=$Kullanici;Password=$Sifre;" } else { $cs += "Integrated Security=True;" }
        try {
            $c = New-Object System.Data.SqlClient.SqlConnection($cs)
            $c.Open()
            Write-Host "SQL Server baglandi: $s" -ForegroundColor Green
            return $c
        } catch {
            Write-Host "Baglanilamadi: $s" -ForegroundColor DarkGray
        }
    }
    throw "Hicbir SQL Server'a baglanilamadi. -Sunucu ve gerekirse -Kullanici sa -Sifre ... verin."
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

$conn = Open-Connection
try {
    if (-not $Mdb -and -not $Veritabani) {
        $dbs = Invoke-Query $conn "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name"
        Write-Host "`nVeritabanlari:" -ForegroundColor Cyan
        $dbs.Rows | ForEach-Object { Write-Host "  $($_.name)" }
        Write-Host "`nTekrar calistirin: -Veritabani <ad> -Kesfet" -ForegroundColor Yellow
        return
    }

    if ($Kesfet) {
        $pattern = '(?i)barkod|barcode|fiyat|price|plu|malin|stokad|urunad|birim'
        if ($Mdb) {
            $schema = $conn.GetSchema("Columns")
            $rows = $schema.Rows | Where-Object { $_.TABLE_NAME -notlike "MSys*" } | ForEach-Object { [pscustomobject]@{ Tablo = $_.TABLE_NAME; Sutun = $_.COLUMN_NAME } }
        } else {
            $t = Invoke-Query $conn "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS Tablo, COLUMN_NAME AS Sutun FROM INFORMATION_SCHEMA.COLUMNS"
            $rows = $t.Rows | ForEach-Object { [pscustomobject]@{ Tablo = $_.Tablo; Sutun = $_.Sutun } }
        }
        $groups = $rows | Group-Object Tablo | Where-Object { ($_.Group.Sutun -match $pattern).Count -ge 2 } | Sort-Object { -($_.Group.Sutun -match $pattern).Count }
        $report = New-Object System.Text.StringBuilder
        foreach ($g in $groups) {
            $name = $g.Name
            $count = ""
            try {
                $q = if ($Mdb) { "SELECT COUNT(*) FROM [$name]" } else { "SELECT COUNT(*) FROM " + (($name -split '\.' | ForEach-Object { "[$_]" }) -join '.') }
                $count = (Invoke-Query $conn $q).Rows[0][0]
            } catch { }
            $line = "$name ($count satir): " + (($g.Group.Sutun) -join ", ")
            Write-Host $line
            [void]$report.AppendLine($line)
        }
        [System.IO.File]::WriteAllText((Join-Path (Get-Location) "kesif.txt"), $report.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Write-Host "`nListe kesif.txt dosyasina da yazildi." -ForegroundColor Yellow
        return
    }

    if (-not $Sorgu -and $Tablo) { $Sorgu = "SELECT * FROM $Tablo" }
    if (-not $Sorgu) { throw "-Kesfet, -Tablo veya -Sorgu verin." }
    $data = Invoke-Query $conn $Sorgu
    Write-Csv $data $Cikti
    Write-Host "$($data.Rows.Count) satir yazildi: $Cikti" -ForegroundColor Green
} finally {
    $conn.Close()
}
