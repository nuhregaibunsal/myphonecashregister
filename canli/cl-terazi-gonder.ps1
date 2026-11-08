param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [string]$Pw = "",
    [Parameter(Mandatory = $true)][int]$Item,
    [string]$TekIp = "",
    [int]$Zaman = 4000
)

# 32-bit calisir (Jet). TbPLU'dan urunu okur, W02 paketini kurar, terazilere gonderir.
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
if (-not $Pw -and $env:FG_CLPW) { $Pw = $env:FG_CLPW }

if (-not (Test-Path -LiteralPath $Mdb)) { Write-Output "ERR dosya-yok"; exit 2 }
$pwPart = if ($Pw) { "Jet OLEDB:Database Password=$Pw;" } else { "" }
$conn = $null
foreach ($prov in @("Microsoft.ACE.OLEDB.16.0", "Microsoft.ACE.OLEDB.12.0", "Microsoft.Jet.OLEDB.4.0")) {
    try { $c = New-Object System.Data.OleDb.OleDbConnection("Provider=$prov;Data Source=$Mdb;Persist Security Info=False;$pwPart"); $c.Open(); $conn = $c; break } catch { $err = $_.Exception.Message }
}
if (-not $conn) { Write-Output "ERR acilamadi: $err"; exit 3 }

function LE([int64]$v, [int]$n) { $b = New-Object byte[] $n; for ($i = 0; $i -lt $n; $i++) { $b[$i] = [byte](($v -shr ($i * 8)) -band 0xFF) }; return , $b }
$tr = [System.Text.Encoding]::GetEncoding(1254)

try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT DeptNo, PluNo, PluType, ItemCode, UnitPrice, SellByDate, IngredientNo, UseFixedPrice, UnitWeight, Name1 FROM TbPLU WHERE ItemCode = @i"
    [void]$cmd.Parameters.AddWithValue("@i", $Item)
    $r = $cmd.ExecuteReader()
    if (-not $r.Read()) { Write-Output "ERR urun-yok (ItemCode=$Item)"; $conn.Close(); exit 4 }
    $g = { param($n, $d = 0) if ($r[$n] -is [DBNull]) { $d } else { $r[$n] } }
    $dept = [int](& $g "DeptNo" 1)
    $plu = [int](& $g "PluNo")
    $ptype = [int](& $g "PluType" 1)
    $price = [int64][math]::Round([double](& $g "UnitPrice") * 100)
    $sellby = [int](& $g "SellByDate")
    $ing = [int](& $g "IngredientNo")
    $ufp = [int](& $g "UseFixedPrice")
    $uw = [int](& $g "UnitWeight")
    $name = [string](& $g "Name1" "")
    $r.Close()
} finally { $conn.Close() }

$nameBytes = $tr.GetBytes($name)
$fields = @(
    @("01", "57", (LE $dept 2)), @("02", "4C", (LE $plu 4)), @("04", "4D", ([byte[]]@($ptype))),
    @("05", "42", ([byte[]]@($uw))), @("06", "4C", (LE $price 4)), @("09", "57", (New-Object byte[] 2)),
    @("0B", "4C", (LE $Item 4)), @("0D", "4C", (New-Object byte[] 4)), @("0E", "57", (New-Object byte[] 2)),
    @("0F", "42", (New-Object byte[] 1)), @("10", "4C", (LE $sellby 4)), @("11", "42", (New-Object byte[] 2)),
    @("12", "57", (New-Object byte[] 2)), @("19", "57", (LE $ing 2)), @("1A", "42", ([byte[]]@($ufp))),
    @("37", "57", (New-Object byte[] 2)), @("51", "57", (New-Object byte[] 2)), @("55", "57", (New-Object byte[] 2)),
    @("5B", "42", (New-Object byte[] 4)), @("64", "4C", (New-Object byte[] 4)), @("0A", "53", $nameBytes),
    @("1E", "53", (New-Object byte[] 0)), @("1F", "53", (New-Object byte[] 0))
)
$body = New-Object System.Collections.Generic.List[byte]
foreach ($f in $fields) {
    $val = [byte[]]$f[2]
    $body.AddRange([System.Text.Encoding]::ASCII.GetBytes(("F={0}.{1},{2:X}:" -f $f[0], $f[1], $val.Length)))
    if ($val.Length) { $body.AddRange($val) }
}
$cs = 0; foreach ($b in $body) { $cs = $cs -bxor $b }
$pk = New-Object System.Collections.Generic.List[byte]
$pk.AddRange([System.Text.Encoding]::ASCII.GetBytes(("W02A{0:X5},{1:D2}L{2:X4}:" -f $plu, $dept, $body.Count)))
$pk.AddRange($body); $pk.Add([byte]$cs)
$packet = $pk.ToArray()

# Terazi listesi
$ips = New-Object System.Collections.Generic.List[object]
$conn2 = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$Mdb;Persist Security Info=False;$pwPart")
try {
    $conn2.Open()
    if ($TekIp) { $ips.Add(@($TekIp, 20304)) }
    else {
        $sc = $conn2.CreateCommand(); $sc.CommandText = "SELECT IPAddress, TCPPort FROM TbScale WHERE IPAddress IS NOT NULL AND IPAddress <> ''"
        $rs = $sc.ExecuteReader()
        while ($rs.Read()) { $ip = [string]$rs["IPAddress"]; $port = if ($rs["TCPPort"] -is [DBNull]) { 20304 } else { [int]$rs["TCPPort"] }; if ($ip) { $ips.Add(@($ip, $port)) } }
        $rs.Close()
    }
} finally { $conn2.Close() }
if ($ips.Count -eq 0) { Write-Output "ERR terazi-yok"; exit 5 }

$okCount = 0
foreach ($pair in $ips) {
    $ip = $pair[0]; $port = $pair[1]
    $cl = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $cl.BeginConnect($ip, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { throw "baglanti zaman asimi" }
        $cl.EndConnect($iar)
        $cl.ReceiveTimeout = $Zaman; $cl.SendTimeout = $Zaman
        $ns = $cl.GetStream()
        Start-Sleep -Milliseconds 150
        $buf = New-Object byte[] 256
        if ($ns.DataAvailable) { [void]$ns.Read($buf, 0, 256) }
        $ns.Write($packet, 0, $packet.Length); $ns.Flush()
        $resp = New-Object System.Collections.Generic.List[byte]; $t0 = Get-Date
        while (((Get-Date) - $t0).TotalMilliseconds -lt $Zaman) {
            if ($ns.DataAvailable) { $n = $ns.Read($buf, 0, 256); for ($i = 0; $i -lt $n; $i++) { $resp.Add($buf[$i]) } }
            else { Start-Sleep -Milliseconds 120; if ($resp.Count -gt 0) { break } }
        }
        $txt = -join ($resp | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { "" } })
        if ($txt -match "O01") { Write-Output "OK $ip"; $okCount++ } else { Write-Output "FAIL $ip cevap=$txt" }
    } catch { Write-Output "FAIL $ip $($_.Exception.Message)" } finally { $cl.Close() }
}
Write-Output ("SONUC {0}/{1} terazi guncellendi (PLU {2}, kod {3}, fiyat {4})" -f $okCount, $ips.Count, $plu, $Item, ($price / 100))
if ($okCount -ge 1) { exit 0 } else { exit 6 }
