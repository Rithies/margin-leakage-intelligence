# Runs the DAX test files in tests/ against the model open in Power BI Desktop and prints the results.
# Usage (with MarginLeakage.pbip open and refreshed):
#   powershell -ExecutionPolicy Bypass -File tests\run_dax_tests.ps1
# Needs DAX Studio installed (it provides the ADOMD.NET client library).

$ErrorActionPreference = 'Stop'
[void][Reflection.Assembly]::LoadFrom("C:\Program Files\DAX Studio\bin\Microsoft.AnalysisServices.AdomdClient.dll")

# Desktop runs a local Analysis Services engine (msmdsrv) per open file; find the one that belongs to MarginLeakage.
$desktop = Get-Process PBIDesktop | Where-Object { $_.MainWindowTitle -like 'MarginLeakage*' } | Select-Object -First 1
if (-not $desktop) { throw "Open MarginLeakage.pbip in Power BI Desktop first." }
$engine = Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" | Where-Object { $_.ParentProcessId -eq $desktop.Id }
$port = (Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen | Select-Object -First 1).LocalPort

$cn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=localhost:$port")
$cn.Open()
$failed = 0
foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '*.dax')) {
    Write-Host "`n== $($file.Name)" -ForegroundColor Cyan
    $cmd = $cn.CreateCommand(); $cmd.CommandText = Get-Content $file.FullName -Raw; $cmd.CommandTimeout = 600
    $reader = $cmd.ExecuteReader()
    $names = 0..($reader.FieldCount - 1) | ForEach-Object { $reader.GetName($_) -replace '^.*\[|\]$', '' }
    $rows = while ($reader.Read()) {
        $row = [ordered]@{}; for ($i = 0; $i -lt $reader.FieldCount; $i++) { $row[$names[$i]] = $reader.GetValue($i) }
        if ($row.Contains('Result') -and $row['Result'] -ne 'PASS') { $failed++ }
        [pscustomobject]$row
    }
    $reader.Close()
    $rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}
$cn.Close()
if ($failed -gt 0) { Write-Host "$failed test(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "All tests passed" -ForegroundColor Green }
