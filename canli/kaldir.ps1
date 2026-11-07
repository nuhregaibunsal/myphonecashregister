$Port = 8443
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Yonetici olarak calistirin." -ForegroundColor Red
    Read-Host "Kapatmak icin Enter'a basin" | Out-Null
    return
}
if (Get-ScheduledTask -TaskName "FiyatGor" -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName "FiyatGor" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "FiyatGor" -Confirm:$false
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*FiyatGor\sunucu.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
& netsh http delete sslcert ipport=0.0.0.0:$Port 2>&1 | Out-Null
& netsh http delete urlacl url=https://+:$Port/ 2>&1 | Out-Null
Get-NetFirewallRule -DisplayName "FiyatGor" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq "FiyatGor" } | Remove-Item
Write-Host "Fiyat Gor sunucusu kaldirildi. C:\FiyatGor klasorunu elle silebilirsiniz." -ForegroundColor Green
Read-Host "Kapatmak icin Enter'a basin" | Out-Null
