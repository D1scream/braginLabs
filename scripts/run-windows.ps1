#Requires -Version 7.4

[CmdletBinding()]
param([switch] $Lab6)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ([string]::IsNullOrWhiteSpace($env:DATABASE_URL)) {
    throw 'Set DATABASE_URL to your local PostgreSQL database.'
}
if ([string]::IsNullOrWhiteSpace($env:APP_ADDR) -and [string]::IsNullOrWhiteSpace($env:PORT)) {
    $env:APP_ADDR = '127.0.0.1:3000'
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Lab6) {
        sqlx migrate run --target-version 1
        cargo run --locked --features lab6
    } else {
        sqlx migrate run
        cargo run --locked
    }
} finally {
    Pop-Location
}
