param(
    [ValidateSet("all", "cdn")]
    [string] $Command = "all",

    [string] $Assembler = "sjasmplus",

    [switch] $Clean
)

$ErrorActionPreference = "Stop"

$source = (Join-Path $PSScriptRoot "src/cdn.asm").Replace("\", "/")
$output = (Join-Path $PSScriptRoot "dot/cdn").Replace("\", "/")

if ($Clean) {
    Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
}

if ($Command -eq "all" -or $Command -eq "cdn") {
    & $Assembler --nologo --cleanonerror "--raw=$output" $source
    if ($LASTEXITCODE -ne 0) {
        throw "SJAsmPlus failed with exit code $LASTEXITCODE"
    }

    $size = (Get-Item -LiteralPath $output).Length
    if ($size -gt 8192) {
        Remove-Item -LiteralPath $output
        throw "dot/cdn is $size bytes; a standard dot command may not exceed 8192 bytes"
    }

    Write-Host "Built dot/cdn ($size bytes)"
}
