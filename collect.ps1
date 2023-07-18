param (
    [Parameter(Mandatory)]
    [DateTime]$StartDate,

    [Parameter(Mandatory)]
    [DateTime]$EndDate,

    [Parameter()]
    [string]$OutputFilename,

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

if ([string]::IsNullOrEmpty($OutputFilename)) {
    $OutputFilename = Join-Path -Path $(Get-Location) -ChildPath "ironman-output.json"
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
	TTime = $_.TimeCreated.ToString()
        PID = $_.Properties[4].Value
        PPID = $_.Properties[7].Value
        ExeFile = $_.Properties[5].Value | Strip-String -Limit 1024
        ParentFile = $_.Properties[13].Value | Strip-String -Limit 1024
        Cmdline = $_.Properties[8].Value | Strip-String -Limit 2048
        SID = $_.Properties[9].Value.Value | Strip-String -Limit 100
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
