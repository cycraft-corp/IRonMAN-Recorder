<#
    .SYNOPSIS
    Collects 4688 event logs within a specified date range.

    .DESCRIPTION
    This script collects event logs from the Windows Event Viewer within a specified date range.
    The script requires the start and end dates for the collection, and allows you to specify an output filename and maximum number of events.

    .PARAMETER StartDate
    Specifies the start date for collecting event logs. Only logs generated on or after this date will be included.
    This parameter is mandatory.

    .PARAMETER EndDate
    Specifies the end date for collecting event logs. Only logs generated before or on this date will be included.
    This parameter is mandatory.

    .PARAMETER OutputFilename
    Specifies the filename for the output file where the collected event logs will be saved.
    If not provided, the script will use a default filename "ironman-output.json".

    .PARAMETER MaxEvents
    Specifies the maximum number of events to collect.
    If not provided, the script will collect up to 500 events.

    .INPUTS
    None. You should run this script on a Windows machine with access to the Event Viewer.

    .OUTPUTS
    The script generates an output file containing the collected event logs.
    
    .EXAMPLE
    PS> .\CollectEventLogs.ps1 -StartDate "2023-07-01" -EndDate "2023-07-15"

    .EXAMPLE
    PS> .\CollectEventLogs.ps1 -StartDate "2023-07-01" -EndDate "2023-07-15" -OutputFilename "MyOutput.json" -MaxEvents 1000
#>

param (
    [Parameter(Mandatory)]
    [DateTime]$StartDate,

    [Parameter(Mandatory)]
    [DateTime]$EndDate,

    [Parameter()]
    [string]$OutputFilename = "ironman-output.json",

    [Parameter()]
    [int]$MaxEvents = 500
)

function Strip-String {
    param (
        [Parameter(ValueFromPipeline)]
        [String]$InputString,

        [Parameter()]
        [int]$Limit = 100
    )

    return $InputString.Substring(0, [Math]::Min($Limit, $InputString.Length))
}

function Replace-EmptySID {
    param (
        [Parameter(ValueFromPipeline)]
        [String]$InputString
    )

    if ($InputString -eq "S-1-0-0") {
        return ""
    } else {
        return $InputString
    }
}

# https://stackoverflow.com/questions/33145377/how-to-change-tab-width-when-converting-to-json-in-powershell
function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String] $json) {
    $indent = 0;
    ($json -Split "`r`n" | % {
        if ($_ -match '[\}\]]\s*,?\s*$') {
            # This line ends with ] or }, decrement the indentation level
            $indent--
        }
        $line = ('  ' * $indent) + $($_.TrimStart() -replace '":  (["{[])', '": $1' -replace ':  ', ': ')
        if ($_ -match '[\{\[]\s*$') {
            # This line ends with [ or {, increment the indentation level
            $indent++
        }
        $line
    }) -Join "`n"
}

# turn relative path to absolute path
if (![System.IO.Path]::IsPathRooted($OutputFilename)) {
    $OutputFilename = Join-Path -Path $(Get-Location) -ChildPath $OutputFilename
}

if ($EndDate -lt $StartDate) {
    Write-Host "$EndDate is smaller than $StartDate, please check your parameters"
    exit -1
}

$events = @(Get-WinEvent -MaxEvents $MaxEvents -FilterHashtable @{
    ID = 4688
    LogName = 'Security'
    StartTime = $StartDate
    EndTime = $EndDate
} | ForEach-Object {
    @{
        Time = [Math]::Round((New-TimeSpan -Start (Get-Date "01/01/1970") -End ($_.TimeCreated)).TotalSeconds)
        PID = $_.Properties[4].Value
        PPID = $_.Properties[7].Value
        ExeFile = $_.Properties[5].Value | Strip-String -Limit 1024
        ParentFile = $_.Properties[13].Value | Strip-String -Limit 1024
        Cmdline = $_.Properties[8].Value | Strip-String -Limit 2048
        SID = $_.Properties[9].Value.Value | Replace-EmptySID | Strip-String -Limit 100
        ExtraTags = @()
    }
})

if ($events.Count -eq 0) {
    Write-Host "Unable to find any event"
    exit -1
}

$result = @{
    Title = "IRonMAN-Recorder"
    Endpoint = $env:COMPUTERNAME | Strip-String -Limit 32
    ReportTime = [Math]::Round((Get-Date -UFormat %s))
    ReportID = [System.Guid]::NewGuid().ToString()
    Version = "1.0.0"
    Events = $events.Count
    Priority = 1
    LanuchEvents = $events
}

$resultJson = $result | ConvertTo-Json | Format-Json

[System.IO.File]::WriteAllLines($OutputFilename, $resultJson)
