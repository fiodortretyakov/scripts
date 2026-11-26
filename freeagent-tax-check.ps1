#Requires -Version 7.4
<#
.SYNOPSIS
    Read-only FreeAgent export for tax checks. Sends only GET requests to the FreeAgent API.
.DESCRIPTION
    First run (interactive): -Setup asks for the OAuth identifier and secret, opens the FreeAgent approval page in
    Chrome (Default profile), catches the redirect on http://localhost:8765/callback and stores the identifier,
    secret and refresh token DPAPI-encrypted (current Windows user only) in D:\config\freeagent\credentials.xml.
    Every run then refreshes the access token and writes JSON files to D:\data\freeagent\<date>\.
.EXAMPLE
    D:\bin\freeagent-tax-check.ps1 -Setup
.EXAMPLE
    D:\bin\freeagent-tax-check.ps1 -From 2025-04-06 -To 2026-04-05
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [datetime]$From,
    [datetime]$To = (Get-Date).Date,
    [string]$OutDir = (Join-Path 'D:\data\freeagent' (Get-Date -Format 'yyyy-MM-dd')),
    [switch]$Sandbox
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$credPath = 'D:\config\freeagent\credentials.xml'
$redirectUri = 'http://localhost:8765/callback'
$apiBase = $Sandbox ? 'https://api.sandbox.freeagent.com/v2' : 'https://api.freeagent.com/v2'

if (-not $PSBoundParameters.ContainsKey('From')) {
    # Start of the previous UK tax year (6 April), so the last completed year and the current one are both covered.
    $today = (Get-Date).Date
    $thisStart = [datetime]::new($today.Year, 4, 6)
    if ($today -lt $thisStart) { $thisStart = $thisStart.AddYears(-1) }
    $From = $thisStart.AddYears(-1)
}
$fromDate = $From.ToString('yyyy-MM-dd')
$toDate = $To.ToString('yyyy-MM-dd')

function ConvertTo-PlainText([securestring]$Value) { (ConvertFrom-SecureString -SecureString $Value -AsPlainText).Trim() }

function Request-FreeAgentToken([hashtable]$Body, [hashtable]$Cred) {
    $pair = '{0}:{1}' -f (ConvertTo-PlainText $Cred.ClientId), (ConvertTo-PlainText $Cred.ClientSecret)
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    Invoke-RestMethod -Method Post -Uri "$apiBase/token_endpoint" -Body $Body `
        -ContentType 'application/x-www-form-urlencoded' `
        -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' }
}

function Save-FreeAgentCredential([hashtable]$Cred) {
    New-Item -ItemType Directory -Force -Path (Split-Path $credPath) | Out-Null
    $Cred | Export-Clixml -Path $credPath
}

if ($Setup) {
    $cred = @{
        ClientId     = Read-Host 'FreeAgent OAuth identifier' -AsSecureString
        ClientSecret = Read-Host 'FreeAgent OAuth secret' -AsSecureString
    }
    $state = [guid]::NewGuid().ToString('N')
    $approveUrl = '{0}/approve_app?client_id={1}&response_type=code&redirect_uri={2}&state={3}' -f $apiBase,
        [uri]::EscapeDataString((ConvertTo-PlainText $cred.ClientId)), [uri]::EscapeDataString($redirectUri), $state

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add('http://localhost:8765/')
    $listener.Start()
    try {
        $chrome = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe').'(default)'
        Start-Process -FilePath $chrome -ArgumentList '--profile-directory="Default"', $approveUrl
        Write-Host 'Approve the app in Chrome. Waiting up to 5 minutes for the redirect...'
        $deadline = (Get-Date).AddMinutes(5)
        $query = $null
        while ($null -eq $query) {
            $pending = $listener.GetContextAsync()
            $left = $deadline - (Get-Date)
            if ($left -le [TimeSpan]::Zero -or -not $pending.Wait($left)) { throw 'No redirect within 5 minutes.' }
            $ctx = $pending.Result
            $isCallback = $ctx.Request.Url.AbsolutePath -eq '/callback'
            if ($isCallback) { $query = [System.Web.HttpUtility]::ParseQueryString($ctx.Request.Url.Query) }
            $bytes = [Text.Encoding]::UTF8.GetBytes($isCallback ? 'FreeAgent redirect received. You can close this tab.' : '')
            $ctx.Response.ContentType = 'text/plain; charset=utf-8'
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $ctx.Response.Close()
        }
    } finally {
        $listener.Stop()
        $listener.Close()
    }
    if ($query['state'] -ne $state) { throw 'The redirect state does not match; nothing was saved.' }
    if (-not $query['code']) { throw "FreeAgent returned no code: $($query['error']) $($query['error_description'])" }

    $token = Request-FreeAgentToken -Cred $cred -Body @{
        grant_type = 'authorization_code'; code = $query['code']; redirect_uri = $redirectUri
    }
    $cred.RefreshToken = ConvertTo-SecureString -String $token.refresh_token -AsPlainText -Force
    Save-FreeAgentCredential $cred
    Write-Host "Saved encrypted credentials to $credPath"
}

if (-not (Test-Path $credPath)) { throw "No credentials at $credPath. Run once with -Setup." }
$cred = Import-Clixml -Path $credPath
$token = Request-FreeAgentToken -Cred $cred -Body @{
    grant_type = 'refresh_token'; refresh_token = (ConvertTo-PlainText $cred.RefreshToken)
}
if ($token.PSObject.Properties['refresh_token'] -and $token.refresh_token) {
    $cred.RefreshToken = ConvertTo-SecureString -String $token.refresh_token -AsPlainText -Force
    Save-FreeAgentCredential $cred
}
$apiHeaders = @{ Authorization = "Bearer $($token.access_token)"; Accept = 'application/json'; 'User-Agent' = 'tax-check' }

# The only function that talks to the API after authentication. It is hard-wired to GET.
function Get-FreeAgentResource([string]$Path, [string]$ArrayKey) {
    $uri = $Path -match '^https://' ? $Path : "$apiBase/$Path"
    if (-not $ArrayKey) {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $apiHeaders -MaximumRetryCount 2 -RetryIntervalSec 10
    }
    $uri += ($uri.Contains('?') ? '&' : '?') + 'per_page=100'
    $items = [System.Collections.Generic.List[object]]::new()
    while ($uri) {
        $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $apiHeaders -MaximumRetryCount 2 -RetryIntervalSec 10
        $json = $resp.Content | ConvertFrom-Json
        if ($json.PSObject.Properties[$ArrayKey]) { foreach ($item in @($json.$ArrayKey)) { $items.Add($item) } }
        $uri = $null
        if ($resp.Headers.ContainsKey('Link')) {
            $next = [regex]::Match(($resp.Headers['Link'] -join ','), '<([^>]+)>;\s*rel="next"')
            if ($next.Success) { $uri = $next.Groups[1].Value }
        }
    }
    return , $items.ToArray()
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$summary = [System.Collections.Generic.List[object]]::new()

function Export-FreeAgentResource([string]$Name, [string]$Path, [string]$ArrayKey) {
    try {
        $data = Get-FreeAgentResource -Path $Path -ArrayKey $ArrayKey
        ConvertTo-Json -InputObject $data -Depth 30 | Set-Content -Path (Join-Path $OutDir "$Name.json") -Encoding utf8
        $count = $ArrayKey ? @($data).Count : 1
        $summary.Add([pscustomobject]@{ Resource = $Name; Items = $count; Error = '' })
        return $data
    } catch {
        $summary.Add([pscustomobject]@{ Resource = $Name; Items = 0; Error = $_.Exception.Message })
        return $null
    }
}

$company = Export-FreeAgentResource 'company' 'company'
if ($company -and $company.company.PSObject.Properties['company_start_date']) {
    # Reports reject a from_date before the company existed.
    $started = [datetime]$company.company.company_start_date
    if ($From -lt $started) { $From = $started; $fromDate = $From.ToString('yyyy-MM-dd') }
}
$range = "from_date=$fromDate&to_date=$toDate"
$me = Export-FreeAgentResource 'user' 'users/me'
$null = Export-FreeAgentResource 'categories' 'categories'
$null = Export-FreeAgentResource 'profit_and_loss' "accounting/profit_and_loss/summary?$range"
$null = Export-FreeAgentResource 'trial_balance' "accounting/trial_balance/summary?to_date=$toDate"
$null = Export-FreeAgentResource 'bills' "bills?$range" 'bills'
$null = Export-FreeAgentResource 'expenses' "expenses?$range" 'expenses'
$null = Export-FreeAgentResource 'invoices' "invoices?view=all&$range" 'invoices'
$null = Export-FreeAgentResource 'vat_returns' 'vat_returns' 'vat_returns'
$null = Export-FreeAgentResource 'corporation_tax_returns' 'corporation_tax_returns' 'corporation_tax_returns'
$null = Export-FreeAgentResource 'final_accounts_reports' 'final_accounts_reports' 'final_accounts_reports'
if ($me -and $me.PSObject.Properties['user']) {
    $null = Export-FreeAgentResource 'self_assessment_returns' "$($me.user.url)/self_assessment_returns" 'self_assessment_returns'
}

$accounts = Export-FreeAgentResource 'bank_accounts' 'bank_accounts' 'bank_accounts'
foreach ($account in @($accounts | Where-Object { $_ })) {
    $id = ($account.url -split '/')[-1]
    $bank = [uri]::EscapeDataString($account.url)
    $null = Export-FreeAgentResource "bank_transactions_$id" "bank_transactions?bank_account=$bank&$range" 'bank_transactions'
    $null = Export-FreeAgentResource "bank_explanations_$id" `
        "bank_transaction_explanations?bank_account=$bank&$range" 'bank_transaction_explanations'
}

Write-Host "FreeAgent export $fromDate to $toDate in $OutDir"
$summary | Format-Table -AutoSize
