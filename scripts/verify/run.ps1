#Requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('all','stylua','selene','tests','harness','analyze','build','package')][string]$Check = 'all')
. (Join-Path $PSScriptRoot 'tools.ps1')
$repoRoot = Get-PackageRoot
Set-Location -LiteralPath $repoRoot
$checks = if ($Check -eq 'all') { @('stylua','selene','tests','harness','analyze','build','package') } else { @($Check) }
foreach ($name in $checks) {
    Write-Host "--- $name ---"
    if ($name -in @('tests','harness')) {
        $scriptName = if ($name -eq 'tests') { 'tests.ps1' } else { 'test-harness.ps1' }
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot $scriptName)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        continue
    }
    if ($name -eq 'stylua') {
        $tool = Resolve-PackageTool 'stylua'
        $result = Invoke-PackageTool $tool.Path @('--check', 'src', 'tests', 'analyzer-expectations')
    } elseif ($name -eq 'selene') {
        $tool = Resolve-PackageTool 'selene'
        $result = Invoke-PackageTool $tool.Path @('src', 'tests', 'analyzer-expectations')
    } elseif ($name -eq 'build') {
        New-Item -ItemType Directory -Force (Join-Path $repoRoot '.verification') | Out-Null
        $tool = Resolve-PackageTool 'rojo'
        $result = Invoke-PackageTool $tool.Path @('build', 'default.project.json', '--output', '.verification/fixedSlotPool.rbxm')
    } elseif ($name -eq 'package') {
        $tool = Resolve-PackageTool 'pesde'
        $result = Invoke-PackageTool $tool.Path @('install')
    } else {
        $definitions = Join-Path $repoRoot 'scripts/luau-lsp/globalTypes.d.luau'
        if (-not (Test-Path -LiteralPath $definitions)) { throw 'Supply Roblox definitions as described in docs/verification.md.' }
        $rojo = Resolve-PackageTool 'rojo'
        $map = Invoke-PackageTool $rojo.Path @('sourcemap', 'dev.project.json', '--output', 'sourcemap.json')
        if ($map.ExitCode -ne 0) { throw $map.Output }
        function Test-Children($node) {
            $names = [Collections.Generic.HashSet[string]]::new()
            foreach ($child in $node.children) {
                if (-not $names.Add($child.name)) { throw "Duplicate Rojo child: $($child.name)" }
                Test-Children $child
            }
        }
        Test-Children (Get-Content sourcemap.json -Raw | ConvertFrom-Json)
        $tool = Resolve-PackageTool 'luau-lsp'
        $arguments = @('analyze', '--flag:LuauSolverV2=true', '--sourcemap=sourcemap.json', "--definitions:@roblox=$definitions")
        $result = Invoke-PackageTool $tool.Path ($arguments + @('src', 'tests/types.luau'))
        Write-Host "Analyzer $($tool.Version) ($($tool.Source)); override SHA256=$($tool.Sha256)"
        if ($result.ExitCode -eq 0) {
            . (Join-Path $PSScriptRoot 'type-diagnostics.ps1')
            $fixture = 'analyzer-expectations/fixedSlotPool.luau'
            $expected = Get-ContractExpectations @((Join-Path $repoRoot $fixture)) $repoRoot
            $negative = Invoke-PackageTool $tool.Path ($arguments + @($fixture))
            $count = Test-ContractDiagnostics $negative.Output $negative.ExitCode $expected $repoRoot
            Write-Host "PASS: $count rejected contract expressions; other fixture expressions accepted."
        }
    }
    Write-Output $result.Output
    if ($result.ExitCode -ne 0) { exit $result.ExitCode }
}
exit 0
