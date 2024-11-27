<# 
.SYNOPSIS
    This script launches the Remote Desktop Client for Windows and automatically subscribes to the Feed. It performs different monitoring
    actions depending on the parameters or user for who the script is running (i.e., it will create a WMI Event Subscription with actions
    if the $Autologon or $Yubikey are set to $true.). The script also monitors the Remote Desktop client for Windows process and takes actions
    when the process exits depending on exit code.

.DESCRIPTION 
    This script first creates a WMI Event Subscriber that looks for the removal of a PNP device that matches either a YUBIKEY (Vendor ID 1050)
    or a Smart Card (PNPDeviceID always starts with SCFILTER). This subscription is configured with an action to relaunch this script and kill
    the PowerShell process executing this instance if the logged in user is 'KioskUser0' because this is an autologon kiosk user and lock the
    computer if it is any other user.

    After the WMI Subscriber is created, the script then launches the AVD Client with a command line that it determines based on the signed-in
    user and whether there is cached credential information for the user in the AVD client. When launching the client, the process details are
    passed through to this script.

    The script monitors the MSRDCW process (AVD Client) every 5 seconds until there is an exit code. Once there is an exit code, the script
    either restarts this script and kills the parent PowerShell process when the signed-in user is 'KioskUser0' or logs the user off if the
    signed-in user was not 'KioskUser0' and the exit code is 0 indicating that the user clicked the 'X' button at the top right of the AVD
    Client.
 
.NOTES 
    The query for the WMI Event Subscription can be adjusted to run more/less frequently on the line that begins with '$Query'. The time is an
    integer value in Seconds and found after 'WITHIN'. Default is 5 seconds.

.COMPONENT 
    No PowerShell modules required.

.LINK 
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/register-wmievent?view=powershell-5.1
    https://learn.microsoft.com/en-us/azure/virtual-desktop/uri-scheme

.PARAMETER AutoLogon
    This boolean value determines if the Thin Client is configured with the Autologon account. If not, and without DeviceQuery Parameters, then the WMI
    event subscription is not created.

.PARAMETER DeviceVendorID
    This string value is the Vendor ID of the device to monitor for removal. The default is an empty string.

.PARAMETER SmartCard
    This boolean value determines if the WMI Event Subscription monitors for Smart Card Removal. Default = $True

.PARAMETER SubscribeUrl
    This value determines the Url of the Remote Desktop Feed which varies by environment. The placeholder in this script is/was automatically
    updated by the installation script.
    The list of Urls can be found at
    https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-microsoft-store?source=recommendations#subscribe-to-a-workspace.

.PARAMETER Timeout
    This integer value determines the time in seconds that can pass with cached credentials in the Remote Desktop Client and no remote sessions connections. Default = 900 seconds.

.PARAMETER Triggers
    This array value determines the triggers for the actions that this script will take. The choices are ( 'SessionDisconnect', 'SessionDisconnect' and 'IdleTimer' or 'IdleTimer' )  or 'DeviceRemoval'.

.PARAMETER TriggerAction
    The action this script executes when the Trigger occurs. The choices are 'Lock', 'Logoff', 'ResetClient'.

#>

[CmdletBinding()]
param (

    [string]$DeviceVendorID,
  
    [bool]$SmartCard,

    [string]$SubscribeUrl,

    [int]$Timeout,

    [string[]]$Triggers,
    
    [ValidateSet('Lock', 'Logoff', 'ResetClient')]
    [string]$TriggerAction
)

$VBScriptPath = $PSCommandPath.Replace('.ps1', '.vbs')
Start-Transcript -Path "$env:Temp\$(($MyInvocation.MyCommand.Name).Replace('.ps1', '.log'))" -Force

Function Restart-Script {
    Write-Output "Relaunching this script."
    $ProcessList = 'Microsoft.AAD.BrokerPlugin', 'msrdc', 'msrdcw'
    $Processes = Get-Process
    ForEach ($Process in $ProcessList) {
        $Processes | Where-Object { $_.Name -eq $Process } | Stop-Process -Force
    }
    Stop-Transcript
    Start-Process -FilePath "wscript.exe" -ArgumentList "`"$VBScriptPath`""
    # Kill current Powershell process to prevent multiple powershell processes from running.
    Get-Process -Id $PID | Stop-Process -Force
}

# Handle Client Reset in the Autologon scenario
If ($Env:UserName -eq 'KioskUser0' -and (Test-Path -Path 'HKCU:\Software\Microsoft\RdClientRadc')) {
    Write-Output 'User Information Cached. Resetting the Remote Desktop Client.'
    Get-Process | Where-Object { $_.Name -eq 'msrdcw' } | Stop-Process -Force
    Get-Process | Where-Object { $_.Name -eq 'Microsoft.AAD.BrokerPlugin' } | Stop-Process -Force
    $reset = Start-Process -FilePath "$env:ProgramFiles\Remote Desktop\msrdcw.exe" -ArgumentList "/reset /f" -wait -PassThru
    Write-Output "msrdcw.exe /reset exit code: [$($reset.ExitCode)]"
}
# Turn off Telemetry on every launch since this is not a policy.
$RegKey = 'HKCU:\Software\Microsoft\RdClientRadc'
$RegValue = 'EnableMSRDCTelemetry'
New-Item -Path $RegKey -Force | Out-Null
New-ItemProperty -Path $RegKey -Name $RegValue -PropertyType DWORD -Value 0 -Force | Out-Null

Write-Output "Starting Remote Desktop Client."
If ($Env:UserName -eq 'KioskUser0') {
    # Always start client with subscribe Url in Autologon scenario
    $MSRDCW = Start-Process -FilePath "$env:ProgramFiles\Remote Desktop\Msrdcw.exe" -ArgumentList "ms-rd:subscribe?url=$SubscribeUrl" -PassThru -WindowStyle Maximized
}
Else {
    # Start client without subscribe Url in non-Autologon scenario because GPO will handle the subscription.
    $MSRDCW = Start-Process -FilePath "$env:ProgramFiles\Remote Desktop\Msrdcw.exe" -PassThru -WindowStyle Maximized
}
# Remove this condition when this feature is available in Azure US Government
if ($SubscribeUrl -notmatch '.us') {
    $ClientDir = "$env:UserProfile\AppData\Local\rdclientwpf"
    $JSONFile = Join-Path -Path $ClientDir -ChildPath 'ISubscription.json'

    # Wait for JSON File to be populated or catch the case where the Remote Desktop Client window is closed.
    # We have to catch ExitCode 0 as a separate condition since it evaluates as null.
    do {
        If (Test-Path $JSONFile) {
            $AVDInfo = Get-Content $JSONFile | ConvertFrom-Json
            $WorkSpaceOID = $AVDInfo.TenantCollection.TenantID
            $User = $AVDInfo.Username
        }
        Start-Sleep -Seconds 1
    } until ($null -ne $User -or $null -ne $MSRDCW.ExitCode)

    If ($User) {
        $Apps = $AVDInfo.TenantCollection.remoteresourcecollection
        If ($SubscribeUrl -match '.us') { $env = 'avdgov' } Else { $env = 'avdarm' }
        If ($apps.count -eq 1) {
            $URL = -join ("ms-avd:connect?workspaceId=", $WorkSpaceOID, "&resourceid=", $apps.ID, "&username=", $User, "&env=", $env, "&version=0")
            Start-Process -FilePath "$URL"
        }
    }
}

If ($Triggers -contains 'DeviceRemoval' -or $Triggers -contains 'SessionDisconnect') {
    # Must set up a WMI Event Subscription to monitor for device removal or session disconnect events.
    If ($Triggers -contains 'DeviceRemoval') {
        Write-Output "Creating WMI Event Subscription for Device Removal."
        If ($null -ne $DeviceVendorID -and $DeviceVendorID -ne '') {
            If ($SmartCard) {
                $InstanceDevicePropsQuery = "TargetInstance.PNPClass = 'SmartCard' OR TargetInstance.PNPDeviceID LIKE '%VID_$DeviceVendorID%'"
            }
            Else {
                $InstanceDevicePropsQuery = "TargetInstance.PNPDeviceID LIKE '%VID_$DeviceVendorID%'"
            }
        }
        Elseif ($SmartCard) {
            $InstanceDevicePropsQuery = "TargetInstance.PNPClass = 'SmartCard'"
        }
            
        $Query = "SELECT * FROM __InstanceDeletionEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_PnPEntity' AND ($InstanceDevicePropsQuery)"
        $SourceIdentifier = "Remove_Security_Device_Event"
    }
    Else {
        Write-Output "Creating WMI Event Subscription for Remote Session Disconnect."
        $Query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_NTLogEvent' AND TargetInstance.Logfile = 'Microsoft-Windows-TerminalServices-RDPClient/Operational' AND TargetInstance.EventCode = '1026'"
        $SourceIdentifier = "Session_Disconnect_Event"
    }

    Get-EventSubscriber -Force | Where-Object { $_.SourceIdentifier -eq $SourceIdentifier } | Unregister-Event -Force -ErrorAction SilentlyContinue

    If ($Env:UserName -eq 'KioskUser0' -and $Triggers -contains 'DeviceRemoval') {
        $Action = {
            Function Restart-Script {
                Write-Output "Relaunching this script."
                $ProcessList = 'Microsoft.AAD.BrokerPlugin', 'msrdc', 'msrdcw'
                $Processes = Get-Process
                ForEach ($Process in $ProcessList) {
                    $Processes | Where-Object { $_.Name -eq $Process } | Stop-Process -Force
                }
                Stop-Transcript
                Start-Process -FilePath "wscript.exe" -ArgumentList "`"$VBScriptPath`""
                # Kill current Powershell process to prevent multiple powershell processes from running.
                Get-Process -Id $PID | Stop-Process -Force
            }

            If (Test-Path -Path 'HKCU:\Software\Microsoft\RdClientRadc') { $CachePresent = $true }
            If (Get-Process | Where-Object { $_.Name -eq 'msrdcw' }) { $MSRDCWOpen = $true }

            $pnpEntity = $EventArgs.NewEvent.TargetInstance
            Write-Output "Device Removed:`n`tCaption: $($pnpEntity.Caption)`n`tPNPDeviceID: $($pnpEntity.PNPDeviceID)`n`tManufacturer: $($pnpEntity.Manufacturer)"
            If ($MSRDCWOpen -and -not $CachePresent) {
                Write-Output "The MSRDCW window is open and there are no cached credentials. Nothing to do."
            }
            Else {
                Restart-Script
            }
        }
    }
    ElseIf ($Env:UserName -eq 'KioskUser0' -and $Triggers -contains 'SessionDisconnect') {
        $Action = {
            Function Restart-Script {
                Write-Output "Relaunching this script."
                $ProcessList = 'Microsoft.AAD.BrokerPlugin', 'msrdc', 'msrdcw'
                $Processes = Get-Process
                ForEach ($Process in $ProcessList) {
                    $Processes | Where-Object { $_.Name -eq $Process } | Stop-Process -Force
                }
                Stop-Transcript
                Start-Process -FilePath "wscript.exe" -ArgumentList "`"$VBScriptPath`""
                # Kill current Powershell process to prevent multiple powershell processes from running.
                Get-Process -Id $PID | Stop-Process -Force
            }
            
            If (Test-Path -Path 'HKCU:\Software\Microsoft\RdClientRadc') { $CachePresent = $true }
            If (Get-Process | Where-Object { $_.Name -eq 'msrdcw' }) { $MSRDCWOpen = $true }
            If (Get-Process | Where-Object { $_.Name -eq 'msrdc' }) { $MSRDC = $true }

            If ($MSRDCWOpen -and -not $CachePresent) {
                Write-Output "The MSRDCW window is open and there are no cached credentials. Nothing to do."
            }
            Else {
                If (-Not $MSRDCWOpen) {
                    Write-Output "MSRDCW is not running. Assuming that the user closed the client window."
                    Restart-Script                
                }
                # This is main section where we look at session host disconnect events in the event log and determine if we need to reset the client.
                Write-Output "Filtering Session Disconnect (EventId: 1026) messages in the 'Microsoft-Windows-TerminalServices-RDPClient/Operational' log."
                # Initial event filter
                $TwoMinsAgo = (Get-Date).AddMinutes(-2)
                $EventFilter = @{
                    LogName   = 'Microsoft-Windows-TerminalServices-RDPClient/Operational'
                    Id        = '1026'
                    StartTime = $TwoMinsAgo
                }
                $Events = Get-WinEvent -FilterHashtable $EventFilter
                <#
                        There are three reasons that we need to reset the client in the autologon scenario.
                        Reason 1:
                        Occurs when X is select on the RDP window. Need to test in session disconnect option.

                        Reason 2
                        Occurs when disconnect is selected in start menu on Session Host
                        Occurs when logoff is select in session

                        Reason 3
                        Occurs when session is disconnected by a connection to the same host from another endpoint. Must be treated differently to prevent cached credentials from remaining.
                    #>
                # Find the interesting events
                $MessageFilter = { $_.message -like '*(Reason= 1)' -or $_.message -like '*(Reason= 2)' }
                $logoffEvents = $Events | where-object $MessageFilter
                $MessageFilter = { $_.message -like '*(Reason= 3)' }
                $remoteConnectionEvents = $Events | Where-Object $MessageFilter
                [int]$totalFilteredEvents = $logoffEvents.Count + $remoteConnectionEvents.Count
                
                Write-Output "Event Log Filtering Results:`n`nTotal unfiltered 1026 events: $($Events.count) ; Total filtered by reason code: $totalFilteredEvents"
                # Must consider remote connection initiated events first because they tell us that the user is not present at the local terminal and we want to close connections
                # and clear the client cache immediately
                If ($remoteConnectionEvents) {
                    Write-Output "A local session was disconnected due to a remote session logon. Resetting the client after closing any remaining sessions and stopping the client."
                    Restart-Script
                }
                ElseIf ($logoffEvents) {
                    # Found logoff events, now determine if there are any active connections to a session host. The idea is to support multiple session host connections
                    # and allow the user to cleanly logoff of remote session hosts or have one disconnect while working in another. Common scenario for an administrative
                    # user utilizing a General User host pool and a Priveleged User host pool.
                    Write-Output "There are local logoff or disconnection events that may warrant a client reset."
                    If ($MSRDC) {
                        $counter = 0
                        Write-Output 'Detected open MSRDC connections. Waiting up to 30 seconds for them to disconnect.'
                        Do {
                            $counter ++
                            Start-Sleep -Seconds 1
                        } Until ($counter -eq 30 -or ($null -eq (Get-Process | Where-Object { $_.Name -eq 'msrdc' })))
                        If ($Counter -lt 30) {
                            Write-Output "Open connections closed after $counter seconds."
                        }
                    }
                    # Support for multiple remote sessions. Check for msrdc processes again after waiting for them to close for 30 seconds. If they are not present we can reset the client, else we can quit.
                    If ($null -eq (Get-Process | Where-Object { $_.Name -eq 'msrdc' })) {
                        Write-Output "No open session host connections. Resetting client."
                        Restart-Script                                
                    }
                    Else {
                        Write-Output "There are still active remote desktop sessions. Assuming that user is still active and therefore, not resetting client."
                    }
                }
                Else {
                    Write-Output "All 1026 events were filtered out. There is no reason to perform a client reset."
                }
            }
        }
    }
    ElseIf ($Triggers -contains 'DeviceRemoval' -and $TriggerAction -eq 'Lock') {
        $Action = {
            $pnpEntity = $EventArgs.NewEvent.TargetInstance
            Write-Output "Device Removed:`n`tCaption: $($pnpEntity.Caption)`n`tPNPDeviceID: $($pnpEntity.PNPDeviceID)`n`tManufacturer: $($pnpEntity.Manufacturer)"                   
            Write-Output "Locking the computer."
            Start-Process -FilePath 'rundll32.exe' -ArgumentList "user32.dll`,LockWorkStation"
        }
    }
    Elseif ($Triggers -contains 'DeviceRemoval' -and $TriggerAction -eq 'Logoff') {
        $Action = {
            $pnpEntity = $EventArgs.NewEvent.TargetInstance
            Write-Output "Device Removed:`n`tCaption: $($pnpEntity.Caption)`n`tPNPDeviceID: $($pnpEntity.PNPDeviceID)`n`tManufacturer: $($pnpEntity.Manufacturer)"
            Write-Output "Logging off user."
            Stop-Transcript
            Get-WmiObject -Class Win32_OperatingSystem | Invoke-WmiMethod -Name Win32Shutdown -Argument 0
        }
    }
    Register-WmiEvent -Query $Query -Action $Action -SourceIdentifier $SourceIdentifier -SupportEvent
}

if ($Env:UserName -eq 'KioskUser0' -and $Triggers -contains 'IdleTimer') {
    $timer = 0
    $interval = 60 # Check every 60 seconds
    Do {
        if (Test-Path -Path 'HKCU:\Software\Microsoft\RdClientRadc') {
            if (-not (Get-Process | Where-Object { $_.Name -eq 'msrdc' })) {
                $timer += $interval
                if ($timer -ge $timeout) {
                    # Perform the action after 15 minutes of inactivity
                    Restart-Script
                }
            } else {
                # Reset the timer if the process is found
                $timer = 0
            }
        } else {
            $timer = 0
        }
        Start-Sleep -Seconds $interval
    } Until ($null -ne $MSRDCW.ExitCode)
}
Else {
    # Check again to make sure the MSRDCW window has not been closed. If it has not then wait for the window to exit before continuing.
    Do {
        Start-Sleep -Seconds 5
    } Until ($null -ne $MSRDCW.ExitCode)
}

Write-Output "The Remote Desktop Client closed with exit code [$($MSRDCW.exitcode)]."

If ($Env:UserName -eq 'KioskUser0' -and $MSRDCW.ExitCode -ne -1) {
    # ExitCode -1 is returned when the AVD client is forceably closed with Stop-Process.
    Restart-Script  
}
Elseif ($MSRDCW.ExitCode -eq 0) {
    # Sign out the user if they closed the Remote Desktop Client using the [X] at the top right of the window.
    Write-Output "Logging off user."
    Write-Output "Exiting `"$PSCommandPath`""
    Stop-Transcript
    Get-WmiObject -Class Win32_OperatingSystem | Invoke-WmiMethod -Name Win32Shutdown -Argument 0
}
Write-Output "Exiting `"$PSCommandPath`""
Stop-Transcript