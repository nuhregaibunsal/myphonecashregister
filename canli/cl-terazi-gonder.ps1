param(
    [Parameter(Mandatory = $true)][string]$Mdb,
    [string]$Pw = "",
    [Parameter(Mandatory = $true)][int]$Item,
    [string]$TekIp = "",
    [int]$Zaman = 4000
)

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

function Build-Packet($p) {
    $fields = @(
        @("01", "57", (LE $p.Dept 2)), @("02", "4C", (LE $p.Plu 4)), @("04", "4D", ([byte[]]@($p.PluType))),
        @("05", "42", ([byte[]]@($p.UnitWeight))), @("06", "4C", (LE $p.Price 4)), @("09", "57", (New-Object byte[] 2)),
        @("0B", "4C", (LE $p.ItemCode 4)), @("0D", "4C", (New-Object byte[] 4)), @("0E", "57", (New-Object byte[] 2)),
        @("0F", "42", (New-Object byte[] 1)), @("10", "4C", (LE $p.SellBy 4)), @("11", "42", (New-Object byte[] 2)),
        @("12", "57", (New-Object byte[] 2)), @("19", "57", (LE $p.Ingredient 2)), @("1A", "42", ([byte[]]@($p.FixedPrice))),
        @("37", "57", (New-Object byte[] 2)), @("51", "57", (New-Object byte[] 2)), @("55", "57", (New-Object byte[] 2)),
        @("5B", "42", (New-Object byte[] 4)), @("64", "4C", (New-Object byte[] 4)), @("0A", "53", $tr.GetBytes($p.Name)),
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
    $pk.AddRange([System.Text.Encoding]::ASCII.GetBytes(("W02A{0:X5},{1:D2}L{2:X4}:" -f $p.Plu, $p.Dept, $body.Count)))
    $pk.AddRange($body); $pk.Add([byte]$cs)
    return , $pk.ToArray()
}

$products = New-Object System.Collections.Generic.List[object]
$ips = New-Object System.Collections.Generic.List[object]
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT DeptNo, PluNo, PluType, ItemCode, UnitPrice, SellByDate, IngredientNo, UseFixedPrice, UnitWeight, Name1 FROM TbPLU WHERE ItemCode = @i"
    [void]$cmd.Parameters.AddWithValue("@i", $Item)
    $r = $cmd.ExecuteReader()
    while ($r.Read()) {
        $g = { param($n, $d = 0) if ($r[$n] -is [DBNull]) { $d } else { $r[$n] } }
        $products.Add([pscustomobject]@{
                Dept       = [int](& $g "DeptNo" 1)
                Plu        = [int](& $g "PluNo")
                PluType    = [int](& $g "PluType" 1)
                ItemCode   = [int](& $g "ItemCode")
                Price      = [int64][math]::Round([double](& $g "UnitPrice") * 100)
                SellBy     = [int](& $g "SellByDate")
                Ingredient = [int](& $g "IngredientNo")
                FixedPrice = [int](& $g "UseFixedPrice")
                UnitWeight = [int](& $g "UnitWeight")
                Name       = [string](& $g "Name1" "")
            })
    }
    $r.Close()
    if ($TekIp) { $ips.Add(@($TekIp, 20304)) }
    else {
        $sc = $conn.CreateCommand(); $sc.CommandText = "SELECT IPAddress, TCPPort FROM TbScale WHERE IPAddress IS NOT NULL AND IPAddress <> ''"
        $rs = $sc.ExecuteReader()
        while ($rs.Read()) { $ip = [string]$rs["IPAddress"]; $port = if ($rs["TCPPort"] -is [DBNull]) { 20304 } else { [int]$rs["TCPPort"] }; if ($ip) { $ips.Add(@($ip, $port)) } }
        $rs.Close()
    }
} finally { $conn.Close() }

if ($products.Count -eq 0) { Write-Output "ERR urun-yok (ItemCode=$Item)"; exit 4 }
if ($ips.Count -eq 0) { Write-Output "ERR terazi-yok"; exit 5 }

function Send-One([string]$ip, [int]$port, [byte[]]$packet) {
    $cl = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $cl.BeginConnect($ip, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { return "baglanti zaman asimi" }
        $cl.EndConnect($iar)
        $cl.ReceiveTimeout = $Zaman; $cl.SendTimeout = $Zaman
        $ns = $cl.GetStream()
        $ns.Write($packet, 0, $packet.Length); $ns.Flush()
        $buf = New-Object byte[] 256
        $txt = ""
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalMilliseconds -lt $Zaman) {
            if ($ns.DataAvailable) {
                $n = $ns.Read($buf, 0, 256)
                for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -ge 32 -and $buf[$i] -lt 127) { $txt += [char]$buf[$i] } }
                if ($txt -match "W02:O\d\d") { break }
            } else { Start-Sleep -Milliseconds 80 }
        }
        if ($txt -match "W02:O01") { return "OK" }
        if ($txt) { return "cevap=$txt" }
        return "cevap yok"
    } catch { return $_.Exception.Message } finally { $cl.Close() }
}

$total = 0; $okCount = 0
foreach ($p in $products) {
    $packet = Build-Packet $p
    foreach ($pair in $ips) {
        $total++
        $res = Send-One $pair[0] $pair[1] $packet
        if ($res -eq "OK") { $okCount++; Write-Output ("OK {0} PLU {1}" -f $pair[0], $p.Plu) }
        else { Write-Output ("FAIL {0} PLU {1} {2}" -f $pair[0], $p.Plu, $res) }
    }
}
$first = $products[0]
Write-Output ("SONUC {0}/{1} (urun kodu {2}, PLU {3}, fiyat {4})" -f $okCount, $total, $Item, (($products | ForEach-Object { $_.Plu }) -join ","), ($first.Price / 100))
if ($okCount -ge 1) { exit 0 } else { exit 6 }
