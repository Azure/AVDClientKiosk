<# 
.SYNOPSIS
    This script creates a custom Remote Desktop client for Windows (AVD Client) kiosk configuration designed to only allow the use of the client.
    It uses a combination of Applocker policies, multi-local group policy settings, Shell Launcher configuration, provisioning packages, and
    registry edits to complete the configuration. There are basically four major options for configuration:

    * Remote Desktop client shell
    * Remote Desktop client shell with autologon
    * Custom Explorer shell (Windows 10) or Multi-App Kiosk Shell (Windows 11)
    * Custom Explorer shell (Windows 10) or Multi-App Kiosk Shell (Windows 11), both with autologon

    These options are controlled by the combination of the two switch parameters - AVDClientShell and Autologon.
    
    When the AVDClientShell switch parameter is not used, then you can utilize the -ShowDisplaySettings switch parameter to allow access to the Display Settings page.
    
    Additionally, you can choose to

    * Install the latest Remote Desktop client for Windows and Visual C++ Redistributables directly from the web.
    * Apply the latest applicable Security Technical Implementation Guides (STIG) group policy settings into the local group policy object via the
      local group policy object tool. This also applies several delta settings to maintain operability as a kiosk.
    * Monitor for FIDO Passkey device removals and perform the same actions as smart cards such as local computer lock or Remote Desktop
      client reset.

.DESCRIPTION 
    This script completes a series of configuration tasks based on the parameters chosen. These tasks can include:

    * Applocker policy application to block Internet Explorer, Edge, Wordpad, and Notepad
    * Provisioning packages to remove pinned items from the Start Menu for the custom explorer shell option with Windows 10.
    * Provisioning packages to enable SharedPC mode.
    * Multi-Local Group Policy configuration to limit interface elements.
    * Built-in application removal.
    * Shell Launcher configuration for the AVDClientShell and Windows 10 Autologon scenarios
    * Multi-App Kiosk configuration for Windows 11 when the AVDClientShell switch parameter is not used.
    * Remote Desktop client for Windows install (If selected)
    * STIG application (If selected)
    * Start Layout modIfication for the custom explorer shell options
    * Custom Azure Virtual Desktop client shortcuts that launches the Remote Desktop client for Windows
      via a script to enable WMI Event subscription.

.NOTES 
    The script will automatically remove older configurations by running 'Remove-KioskSettings.ps1' during the install process.    

.COMPONENT 
    No PowerShell modules required.

.LINK 
    https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-windows?tabs=subscribe
    https://learn.microsoft.com/en-us/azure/virtual-desktop/uri-scheme
    https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/applocker/applocker-overview
    https://learn.microsoft.com/en-us/windows/configuration/kiosk-shelllauncher
    https://public.cyber.mil/stigs/gpo/
 
.PARAMETER ApplySTIGs
This switch parameter determines If the latest DoD Security Technical Implementation Guide Group Policy Objects are automatically downloaded
from https://public.cyber.mil/stigs/gpo and applied via the Local Group Policy Object (LGPO) tool to the system. If they are, then several
delta settings are applied to allow the system to communicate with Azure Active Directory and complete autologon (If applicable).

.PARAMETER AutoLogon
This switch parameter determines If autologon is enabled through the Shell Launcher configuration. The Shell Launcher feature will automatically
create a new user - 'KioskUser0' - which will not have a password and be configured to automatically logon when Windows starts.

.PARAMETER AVDClientShell
This switch parameter determines whether the Windows Shell is replaced by the Remote Desktop client for Windows or remains the default 'explorer.exe'.
When the default 'explorer' shell is used additional local group policy settings and provisioning packages are applied to lock down the shell.

.PARAMETER EnvironmentAVD
This value determines the Azure environment to which you are connecting. It ultimately determines the Url of the Remote Desktop Feed which
varies by environment by setting the $SubscribeUrl variable and replacing placeholders in several files during installation.
The list of Urls can be found at
https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-microsoft-store?source=recommendations#subscribe-to-a-workspace.

.PARAMETER InstallAVDClient
This switch parameter determines If the latest Remote Desktop client for Windows is automatically downloaded from the Internet and installed
on the system prior to configuration.

.PARAMETER SharedPC
This switch parameter determines If the computer is setup as a shared PC. The account management process is enabled and all user profiles are automatically
deleted on logoff.

.PARAMETER ShowDisplaySettings
This switch parameter determines If the Settings App and Control Panel are restricted to only allow access to the Display Settings page. If this value is not set,
then the Settings app and Control Panel are not displayed or accessible.

.PARAMETER TimeOut
This integer value determines the number of seconds in the AutoLogon scenario with the Triggers value containing 'IdleTimeout' that the system will stay idle before resetting the client.

.PARAMETER Triggers
This string array value determines the trigger(s) that will cause the Trigger Action to be carried out.
When AutoLogon is true, you can choose any or all of the following: 'DeviceRemoval', 'SessionDisconnect', and 'IdleTimeout'.
When AutoLogon is false, you can leave this empty or choose 'IdleTimeout' or 'DeviceRemoval' (and must select either the SmartCard, the DeviceID option, or both).
If this value is not set then the TriggerAction is not used.

.PARAMETER TriggerAction
This string parameter determines what occurs when the specIfied trigger is detected. The possible values are dIfferent depending on the value of $Autologon.
When AutoLogon is true then 'ResetClient' is allowed.
When AutoLogon is false then 'Lock' or 'Logoff' are allowed.

.PARAMETER DeviceVendorID
This string parameter defines the Vendor ID of the hardware authentication token that If removed will trigger the action defined in "TriggerAction".
This value is only used when "Triggers" contains "DeviceRemoval".
    .EXAMPLE
    -DeviceVendorID '1050' # Yubikey Vendor ID

.PARAMETER SmartCard
This switch parameter determines If SmartCard removal will trigger the 'TriggerAction'. This value is only used when 'Triggers' contains 'DeviceRemoval'.

.PARAMETER Version
This version parameter allows tracking of the installed version using configuration management software such as Microsoft Endpoint Manager or Microsoft Endpoint Configuration Manager by querying the value of the registry value: HKLM\Software\Kiosk\version.

#>
[CmdletBinding()]
param (
    [switch]$ApplySTIGs,

    [Parameter(Mandatory, ParameterSetName = 'AutologonClientShell')]
    [Parameter(Mandatory, ParameterSetName = 'DirectLogonClientShell')]
    [switch]$AVDClientShell,

    [Parameter(Mandatory, ParameterSetName = 'AutologonClientShell')]
    [Parameter(Mandatory, ParameterSetName = 'AutologonExplorerShell')]
    [switch]$AutoLogon,

    [ValidatePattern("^[0-9A-Fa-f]{4}$")]
    [string]$DeviceVendorID,

    [ValidateSet('AzureCloud', 'AzureUSGovernment')]
    [string]$EnvironmentAVD = 'AzureUSGovernment',

    [switch]$InstallAVDClient,

    [Parameter(ParameterSetName = 'DirectLogonClientShell')]
    [Parameter(ParameterSetName = 'DirectLogonExplorerShell')]
    [switch]$SharedPC,

    [Parameter(ParameterSetName = 'AutologonExplorerShell')]
    [Parameter(ParameterSetName = 'DirectLogonExplorerShell')]
    [switch]$ShowDisplaySettings,

    [switch]$SmartCard,

    [int]$Timeout = 900,

    [ValidateSet('DeviceRemoval', 'SessionDisconnect', 'IdleTimeout')]
    [string[]]$Triggers,

    [ValidateSet('Lock', 'Logoff', 'ResetClient')]
    [string]$TriggerAction,

    [version]$Version = '6.0.0'
)

#region Parameter Validation and Configuration
# To do, convert to dynamic parameters with Parameter Sets and Validation Sets
If ($AutoLogon) {
    If ($TriggerAction -eq 'Lock' -or $TriggerAction -eq 'Logoff') {
        Throw 'You cannot specIfy a TriggerAction of Lock or Logoff with AutoLogon'
    } Else {
        $TriggerAction = 'ResetClient'
    }
}
Else {
    If ($TriggerAction -eq 'ResetClient') {
        Throw 'You cannot specIfy a TriggerAction of ResetClient without AutoLogon'
    }
    If ($Triggers -contains 'DeviceRemoval' -and $SmartCard -eq $false -and ($null -eq $DeviceVendorID -or $DeviceVendorID -eq '')) {
        Throw 'You must specIfy either a DeviceVendorID or SmartCard when Triggers contains "DeviceRemoval"'
    } ElseIf ($Triggers -contains 'DeviceRemoval' -and $SmartCard -and ($null -ne $DeviceVendorID -and $DeviceVendorID -ne '')) {
        Throw 'You cannot specIfy both a SmartCard and DeviceVendorID when the Triggers contain "DeviceRemoval"'
    }
}
#endegion

# Restart in 64-Bit PowerShell If not already running in 64-bit mode
# primarily designed to support Microsoft Endpoint Manager application deployment
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $scriptArguments = $null
    Try {
        foreach ($k in $PSBoundParameters.keys) {
            switch ($PSBoundParameters[$k].GetType().Name) {
                "SwitchParameter" { If ($PSBoundParameters[$k].IsPresent) { $scriptArguments += "-$k " } }
                "String" { If ($PSBoundParameters[$k] -match '_') { $scriptArguments += "-$k `"$($PSBoundParameters[$k].Replace('_',' '))`" " } Else { $scriptArguments += "-$k `"$($PSBoundParameters[$k])`" " } }
                "String[]" { $ScriptArguments += "-$k `"$($PSBoundParameters[$k] -join '`",`"')`" " }
                "Int32" { $scriptArguments += "-$k $($PSBoundParameters[$k]) " }
                "Boolean" { $scriptArguments += "-$k `$$($PSBoundParameters[$k]) " }
                "Version" { $scriptArguments += "-$k `"$($PSBoundParameters[$k])`" " }
            }
        }
        If ($null -ne $scriptArguments) {
            $RunScript = Start-Process -FilePath "$env:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -ArgumentList "-File `"$PSCommandPath`" $scriptArguments" -PassThru -Wait -NoNewWindow
        }
        Else {
            $RunScript = Start-Process -FilePath "$env:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -ArgumentList "-File `"$PSCommandPath`"" -PassThru -Wait -NoNewWindow
        }
    }
    Catch {
        Throw "Failed to start 64-bit PowerShell"
    }
    Exit $RunScript.ExitCode
}

$Script:FullName = $MyInvocation.MyCommand.Path
$Script:Dir = Split-Path $Script:FullName
# Windows Event Log (.evtx)
$EventLog = 'AVD Client Kiosk'
$EventSource = 'Configuration Script'
# Source Directories and supporting files
$DirAppLocker = Join-Path -Path $Script:Dir -ChildPath "AppLocker"
$FileAppLockerClear = Join-Path -Path $DirAppLocker -ChildPath "ClearAppLockerPolicy.xml"
$DirMultiAppSettings = Join-Path -Path $Script:Dir -ChildPath 'MultiAppConfigs'
$DirProvisioningPackages = Join-Path -Path $Script:Dir -ChildPath "ProvisioningPackages"
$DirStartMenu = Join-Path -Path $Script:Dir -ChildPath "StartMenu"
$DirShellLauncherSettings = Join-Path -Path $Script:Dir -ChildPath "ShellLauncherConfigs"
$DirGPO = Join-Path -Path $Script:Dir -ChildPath "GPOSettings"
$DirKiosk = Join-Path -Path $env:SystemDrive -ChildPath "KioskSettings"
$DirRegKeys = Join-Path -Path $Script:Dir -ChildPath "RegistryKeys"
$FileRegKeys = Join-Path -Path $DirRegKeys -ChildPath "RegKeys.csv"
$DirTools = Join-Path -Path $Script:Dir -ChildPath "Tools"
$DirUserLogos = Join-Path -Path $Script:Dir -ChildPath "UserLogos"
$DirConfigurationScripts = Join-Path -Path $Script:Dir -ChildPath "Scripts\Configuration"
$DirSchedTasksScripts = Join-Path -Path $Script:Dir -ChildPath "Scripts\ScheduledTasks"
# Find LTSC OS (and Windows IoT Enterprise)
$OS = Get-WmiObject -Class Win32_OperatingSystem
# Detect Windows 11
If ($OS.BuildNumber -lt 22000 -or $OS.Caption -match 'Windows 10') { $Windows10 = $true }
If ($OS.Name -match 'LTSC') { $LTSC = $true }
# Set AVD feed subscription Url.
If ($EnvironmentAVD -eq 'AzureUSGovernment') {
    $SubscribeUrl = 'https://rdweb.wvd.azure.us'
}
Else {
    $SubscribeUrl = 'https://client.wvd.microsoft.com'
}
If ($null -ne $DeviceVendorID -and $DeviceVendorID -ne '') {
    $SecurityKey = $true
}
If (($AutoLogon -eq $True) -or ($Triggers -contains 'DeviceRemoval' -and $SecurityKey) -or ($Triggers -contains 'IdleTimeout' -and $TriggerAction -eq 'Logoff')) {
    $CustomLaunchScript = $true
}
# Detect WIfi Adapter in order to show WIfi Settings in system tray when necessary.
$WifiAdapter = Get-NetAdapter | Where-Object { $_.Name -like '*Wi-Fi*' -or $_.Name -like '*Wifi*' -or $_.MediaType -like '*802.11*' }     
    
# Set default exit code to 0
$ScriptExitCode = 0

#region Functions

Function Get-PendingReboot {
    <#
    .SYNOPSIS
        Gets the pending reboot status on a local or remote computer.

    .DESCRIPTION
        This function will query the registry on a local or remote computer and determine If the
        system is pending a reboot, from Microsoft updates, Configuration Manager Client SDK, Pending Computer 
        Rename, Domain Join or Pending File Rename Operations. For Windows 2008+ the function will query the 
        CBS registry key as another factor in determining pending reboot state.  "PendingFileRenameOperations" 
        and "Auto Update\RebootRequired" are observed as being consistant across Windows Server 2003 & 2008.
        
        CBServicing = Component Based Servicing (Windows 2008+)
        WindowsUpdate = Windows Update / Auto Update (Windows 2003+)
        CCMClientSDK = SCCM 2012 Clients only (DetermineIfRebootPending method) otherwise $null value
        PendComputerRename = Detects either a computer rename or domain join operation (Windows 2003+)
        PendFileRename = PendingFileRenameOperations (Windows 2003+)
        PendFileRenVal = PendingFilerenameOperations registry value; used to filter If need be, some Anti-
                        Virus leverage this key for def/dat removal, giving a false positive PendingReboot

    .EXAMPLE
        Get-PendingReboot
        
    .LINK

    .NOTES
    #>
    Try {
        ## Setting pending values to false to cut down on the number of else statements
        $RebootPending = $false
        $CompPendRen = $false
        $PendFileRename = $false
        $SCCM = $false

        ## Setting CBSRebootPend to null since not all versions of Windows has this value
        $CBSRebootPend = $null

        ## Making registry connection to the local/remote computer
        $HKLM = [UInt32] "0x80000002"
        $WMI_Reg = [WMIClass] "\\.\root\default:StdRegProv"
						
        ## query the CBS Reg Key
	    
        $RegSubKeysCBS = $WMI_Reg.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")
        $CBSRebootPend = $RegSubKeysCBS.sNames -contains "RebootPending"		
	    							
        ## Query WUAU from the registry
        $RegWUAURebootReq = $WMI_Reg.EnumKey($HKLM, "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")
        $WUAURebootReq = $RegWUAURebootReq.sNames -contains "RebootRequired"
						
        ## Query PendingFileRenameOperations from the registry
        $RegSubKeySM = $WMI_Reg.GetMultiStringValue($HKLM, "SYSTEM\CurrentControlSet\Control\Session Manager\", "PendingFileRenameOperations")
        $RegValuePFRO = $RegSubKeySM.sValue

        ## Query JoinDomain key from the registry - These keys are present If pending a reboot from a domain join operation
        $Netlogon = $WMI_Reg.EnumKey($HKLM, "SYSTEM\CurrentControlSet\Services\Netlogon").sNames
        $PendDomJoin = ($Netlogon -contains 'JoinDomain') -or ($Netlogon -contains 'AvoidSpnSet')

        ## Query ComputerName and ActiveComputerName from the registry
        $ActCompNm = $WMI_Reg.GetStringValue($HKLM, "SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName\", "ComputerName")            
        $CompNm = $WMI_Reg.GetStringValue($HKLM, "SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\", "ComputerName")

        If (($ActCompNm -ne $CompNm) -or $PendDomJoin) {
            $CompPendRen = $true
        }
						
        ## If PendingFileRenameOperations has a value set $RegValuePFRO variable to $true
        If ($RegValuePFRO) {
            $PendFileRename = $true
        }

        ## Determine SCCM 2012 Client Reboot Pending Status
        ## To avoid nested 'If' statements and unneeded WMI calls to determine If the CCM_ClientUtilities class exist, setting EA = 0
        
        ## Try CCMClientSDK
        Try {
            $CCMClientSDK = Invoke-WmiMethod -ComputerName LocalHost -Namespace 'ROOT\ccm\ClientSDK' -Class 'CCM_ClientUtilities' -Name DetermineIfRebootPending -ErrorAction 'Stop'
        }
        Catch {
            $CCMClientSDK = $null
        }

        If ($CCMClientSDK) {
            If ($CCMClientSDK.ReturnValue -ne 0) {
                Write-Warning "Error: DetermineIfRebootPending returned error code $($CCMClientSDK.ReturnValue)"          
            }
            If ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending) {
                $SCCM = $true
            }
        }
        Else {
            $SCCM = $False
        }
        If ($CompPendRen -or $CBSRebootPend -or $WUAURebootReq -or $SCCM -or $PendFileRename) { $RebootPending = $true }
        Return $RebootPending

    }
    Catch {
        Write-Warning "$_"				
    }						
}

function Update-ACL {
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $Path,
        [Parameter(Mandatory = $true)]
        $Identity,
        [Parameter(Mandatory = $true)]
        $FileSystemRights,
        $InheritanceFlags = 'ContainerInherit,ObjectInherit',
        $PropogationFlags = 'None',
        [Parameter(Mandatory)]
        [ValidateSet('Allow', 'Deny')]
        $Type
    )

    If (Test-Path $Path) {
        $NewAcl = Get-ACL -Path $Path
        $FileSystemAccessRuleArgumentList = $Identity, $FileSystemRights, $InheritanceFlags, $PropogationFlags, $type
        $FileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $FileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($FileSystemAccessRule)
        Set-Acl -Path "$Path" -AclObject $NewAcl
    }
}

function Update-ACLInheritance {
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        [Parameter(Mandatory = $true,
            Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $false,
            Position = 1)]
        [bool]$DisableInheritance = $false,

        [Parameter(Mandatory = $true,
            Position = 2)]
        [bool]$PreserveInheritedACEs = $true
    )

    If (Test-Path $Path) {
        $NewACL = Get-Acl -Path $Path
        $NewACL.SetAccessRuleProtection($DisableInheritance, $PreserveInheritedACEs)
        Set-ACL -Path $Path -AclObject $NewACL
    }

}

Function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $EventLog = $EventLog,
        [Parameter()]
        [string]
        $EventSource = $EventSource,
        [Parameter()]
        [string]
        [ValidateSet('Information', 'Warning', 'Error')]
        $EntryType = 'Information',
        [Parameter()]
        [Int]
        $EventID,
        [Parameter()]
        [string]
        $Message
    )
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType $EntryType -EventId $EventId -Message $Message -ErrorAction SilentlyContinue
}

#endregion Functions

#region Initialization

New-EventLog -LogName $EventLog -Source $EventSource -ErrorAction SilentlyContinue

Write-Log -EntryType Information -EventId 1 -Message "Executing '$Script:FullName'."
Write-Log -EntryType Information -EventId 2 -Message "Running on $($OS.Caption) version $($OS.Version)."

If (Get-PendingReboot) {
    Write-Log -EntryType Error -EventId 0 -Message "There is a reboot pending. This application cannot be installed when a reboot is pending.`nRebooting the computer in 15 seconds."
    Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r /t 15'
    Exit 3010
}

# Copy lgpo to system32 for future use.
Copy-Item -Path "$DirTools\lgpo.exe" -Destination "$env:SystemRoot\System32" -Force

# Enable the Scheduled Task History by enabling the TaskScheduler operational log
$TaskschdLog = Get-WinEvent -ListLog Microsoft-Windows-TaskScheduler/Operational
$TaskschdLog.IsEnabled = $True
$TaskschdLog.SaveChanges()

#endregion Inistiialization

#region Remove Previous Versions

# Run Removal Script first in the event that a previous version is installed or in the event of a failed installation.
Write-Log -EntryType Information -EventId 3 -Message 'Running removal script in case of previous installs or failures.'
& "$Script:Dir\Remove-KioskSettings.ps1" -Reinstall

#endregion Previous Version Removal

#region Remove Apps

# Remove Built-in Windows 10 Apps on non LTSC builds of Windows
If (-not $LTSC) {
    Write-Log -EntryType Information -EventId 25 -Message "Starting Remove Apps Script."
    & "$DirConfigurationScripts\Remove-BuiltinApps.ps1"
}
# Remove OneDrive
If (Test-Path -Path "$env:SystemRoot\Syswow64\onedrivesetup.exe") {
    Write-Log -EntryType Information -EventId 26 -Message "Removing Per-User installation of OneDrive."
    Start-Process -FilePath "$env:SystemRoot\Syswow64\onedrivesetup.exe" -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
}
ElseIf (Test-Path -Path "$env:ProgramFiles\Microsoft OneDrive") {
    Write-Log -EntryType Information -EventId 26 -Message "Removing Per-Machine Installation of OneDrive."
    $OneDriveSetup = Get-ChildItem -Path "$env:ProgramFiles\Microsoft OneDrive" -Filter 'onedrivesetup.exe' -Recurse
    If ($OneDriveSetup) {
        Start-Process -FilePath $OneDriveSetup[0].FullName -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    }
}

#endregion Remove Apps

#region STIGs

If ($ApplySTIGs) {
    Write-Log -EntryType Information -EventId 27 -Message "Running Script to apply the latest STIG group policy settings via LGPO for Windows 10, Internet Explorer, Microsoft Edge, Windows Firewall, and Defender AntiVirus."
    & "$DirConfigurationScripts\Apply-LatestSTIGs.ps1"
    If ($AutoLogon) {
        # Remove Logon Banner
        Write-Log -EntryType Information -EventId 28 -Message "Running Script to remove the logon banner because this is an autologon kiosk."
        & "$DirConfigurationScripts\Apply-STIGAutoLogonExceptions.ps1"
    }
    Else {        
        Write-Log -EntryType Information -EventId 28 -Message "Running Script to allow PKU2U online identities required for AAD logon."
        & "$DirConfigurationScripts\Apply-STIGDirectSignOnExceptions.ps1"
    }
}

#endregion STIGs

#region Install AVD Client

If ($installAVDClient) {
    Write-Log -EntryType Information -EventID 30 -Message "Running Script to install or update Visual C++ Redistributables."
    & "$DirConfigurationScripts\Install-VisualC++Redistributables.ps1"
    Write-Log -EntryType Information -EventId 31 -Message "Running Script to install or update AVD Client."
    & "$DirConfigurationScripts\Install-AVDClient.ps1"
}

#endregion Install AVD Client

#region KioskSettings Directory

#Create the KioskSettings Directory
Write-Log -EntryType Information -EventId 40 -Message "Creating KioskSettings Directory at root of system drive."
If (-not (Test-Path $DirKiosk)) {
    New-Item -Path $DirKiosk -ItemType Directory -Force | Out-Null
}

# Setting ACLs on the Kiosk Settings directory to prevent Non-Administrators from changing files. Defense in Depth.
Write-Log -EntryType Information -EventId 41 -Message "Configuring Kiosk Directory ACLs"
$Group = New-Object System.Security.Principal.NTAccount("Builtin", "Administrators")
$ACL = Get-ACL $DirKiosk
$ACL.SetOwner($Group)
Set-ACL -Path $DirKiosk -AclObject $ACL
Update-ACL -Path $DirKiosk -Identity 'BuiltIn\Administrators' -FileSystemRights 'FullControl' -Type 'Allow'
Update-ACL -Path $DirKiosk -Identity 'BuiltIn\Users' -FileSystemRights 'ReadAndExecute' -Type 'Allow'
Update-ACL -Path $DirKiosk -Identity 'System' -FileSystemRights 'FullControl' -Type 'Allow'
Update-ACLInheritance -Path $DirKiosk -DisableInheritance $true -PreserveInheritedACEs $false

# Copy Client Launch Scripts.
If ($CustomLaunchScript) {
    $LaunchScriptSource = 'Launch AVD Client'
    New-EventLog -LogName $EventLog -Source $LaunchScriptSource -ErrorAction SilentlyContinue
    Write-Log -EntryType Information -EventId 42 -Message "Copying Launch AVD Client Scripts from '$DirConfigurationScripts' to '$DirKiosk'"
    Copy-Item -Path "$DirConfigurationScripts\Launch-AVDClient.ps1" -Destination $DirKiosk -Force
    Copy-Item -Path "$DirConfigurationScripts\Launch-AVDClient.vbs" -Destination $DirKiosk -Force
    # dynamically update parameters of launch script.
    $FileToUpdate = Join-Path -Path $DirKiosk -ChildPath 'Launch-AVDClient.ps1'
    $Content = Get-Content -Path $FileToUpdate
    $Content = $Content.Replace('[string]$EventLog', "[string]`$EventLog = '$EventLog'") 
    $Content = $Content.Replace('[string]$EventSource', "[string]`$EventSource = '$LaunchScriptSource'")
    If ($AutoLogon) {
        $Content = $Content.Replace('[bool]$AutoLogon', '[bool]$AutoLogon = $true')
        $Content = $Content.Replace('[string]$SubscribeUrl', "[string]`$SubscribeUrl = '$SubscribeUrl'")
    }
    If ($SecurityKey) { $Content = $Content.Replace('[string]$DeviceVendorID', "[string]`$DeviceVendorID = '$DeviceVendorID'") }
    If ($SmartCard) { $Content = $Content.Replace('[bool]$SmartCard', '[bool]$SmartCard = $true') }
    If ($Timeout) { $Content = $Content.Replace('[int]$Timeout', "[int]`$Timeout = $Timeout")}
    If ($Triggers) { $Content = $Content.Replace('[string[]]$Triggers', "[string[]]`$Triggers = @(`"$($Triggers -join '`", `"')`")") }
    If ($TriggerAction) { $Content = $Content.Replace('[string]$TriggerAction', "[string]`$TriggerAction = '$TriggerAction'") }
     
    $Content | Set-Content -Path $FileToUpdate
}

$SchedTasksScriptsDir = Join-Path -Path $DirKiosk -ChildPath 'ScheduledTasks'
If (-not (Test-Path $SchedTasksScriptsDir)) {
    $null = New-Item -Path $SchedTasksScriptsDir -ItemType Directory -Force
}
Write-Log -EntryType Information -EventId 43 -Message "Copying Scheduled Task Scripts from '$DirSchedTasksScripts' to '$SchedTasksScriptsDir'"
Get-ChildItem -Path $DirSchedTasksScripts -filter '*.*' | Copy-Item -Destination $SchedTasksScriptsDir -Force
If ($Triggers -contains 'SessionDisconnect') {
    $parentKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services\EventLog", $true)
    $null = $parentKey.CreateSubKey("Microsoft-Windows-TerminalServices-RDPClient/Operational")
}
#endregion KioskSettings Directory

#region Provisioning Packages

$ProvisioningPackages = @()
If ($SharedPC) {
    Write-Log -EntryType Information -EventId 44 -Message "Adding Provisioning Package to enable SharedPC mode"
    $ProvisioningPackages += (Get-ChildItem -Path $DirProvisioningPackages | Where-Object { $_.Name -like '*SharedPC*' }).FullName
}
If (-not $AVDClientShell -and $Windows10) {
    # Installing provisioning packages. Currently only one is included to hide the pinned items on the left of the Start Menu.
    # No GPO settings are available to do this.
    Write-Log -EntryType Information -EventId 45 -Message "Adding Provisioning Package to remove pinned items from Start Menu"
    $ProvisioningPackages += (Get-ChildItem -Path $DirProvisioningPackages | Where-Object { $_.Name -like '*PinnedFolders*' }).FullName
    If (-not $ShowDisplaySettings) {
        $ProvisioningPackages += (Get-ChildItem -Path $DirProvisioningPackages | Where-Object { $_.Name -like '*Settings*' }).FullName
    }
    If ($AutoLogon) {
        $ProvisioningPackages += (Get-ChildItem -Path $DirProvisioningPackages | Where-Object { $_.Name -like '*Autologon*' }).FullName
    }
}
New-Item -Path "$DirKiosk\ProvisioningPackages" -ItemType Directory -Force | Out-Null
ForEach ($Package in $ProvisioningPackages) {
    Copy-Item -Path $Package -Destination "$DirKiosk\ProvisioningPackages" -Force
    Write-Log -EntryType Information -EventID 46 -Message "Installing $($Package)."
    Install-ProvisioningPackage -PackagePath $Package -ForceInstall -QuietInstall
}

#endregion Provisioning Packages

#region Start Menu

If (-not ($AVDClientShell)) {
    # Create custom Remote Desktop Client shortcut and configure custom start menu for Non-Admins
    Write-Log -EntryType Information -EventId 47 -Message "Removing any existing shortcuts from the All Users (Public) Desktop and Default User Desktop."
    Get-ChildItem -Path "$env:Public\Desktop" -Filter '*.lnk' | Remove-Item -Force
    Get-ChildItem -Path "$env:SystemDrive\Users\Default\Desktop" -Filter '*.lnk' | Remove-Item -Force 
    
    [string]$StringVersion = $Version
    $ObjShell = New-Object -ComObject WScript.Shell
    $DirShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $LinkRemoteDesktop = "Remote Desktop.lnk"
    $PathLinkRD = Join-Path $DirShortcut -ChildPath $LinkRemoteDesktop
        
    If ($CustomLaunchScript) {
        Write-Log -EntryType Information -EventId 48 -Message "Creating a custom AVD Shortcut in Start Menu."
        $LinkAVD = "Azure Virtual Desktop.lnk"    
        $ShortcutPath = Join-Path $DirShortcut -ChildPath $LinkAVD
        $Shortcut = $ObjShell.CreateShortcut($ShortcutPath)
        #Set values
        $Shortcut.TargetPath = "wscript.exe"
        $Shortcut.Arguments = "`"$env:SystemDrive\KioskSettings\Launch-AVDClient.vbs`""
        $Shortcut.WindowStyle = 3
        $Shortcut.WorkingDirectory = "$env:ProgramFiles\Remote Desktop"
        $Shortcut.Description = "Launches Remote Desktop Client and logon prompt. Kiosk Configuration Version: $StringVersion"
        $Shortcut.IconLocation = $ObjShell.CreateShortcut($PathLinkRD).IconLocation
        $Shortcut.Save()
    }
    Else {
        # Do not need special Remote Desktop Client shortcut If not using AutoLogon or a Device Other than SmartCards. Updating it to start maximized.
        $ShortcutPath = $PathLinkRD
        $Shortcut = $ObjShell.CreateShortcut($ShortcutPath)
        $Shortcut.WindowStyle = 3
        $Shortcut.Save()
    }  
    
    $dirStartup = "$env:SystemDrive\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    If (-not (Test-Path -Path $dirStartup)) {
        $null = New-Item -Path $dirStartup -ItemType Directory -Force
    }
    Copy-Item -Path "$ShortcutPath" -Destination $dirStartup -Force
    
    If ($AutoLogon) {
        $TaskName = "(AVD Client) - Hide KioskUser0 Start Button Context Menu"
        Write-Log -EntryType Information -EventId 49 -Message "Creating Scheduled Task: '$TaskName'."
        $TaskScriptEventSource = 'Hide Start Button Context Menu'
        $TaskDescription = "Hide Start Button Right Click Menu"
        $TaskScriptName = 'Hide-StartButtonRightClickMenu.ps1'
        $TaskScriptFullName = Join-Path -Path $SchedTasksScriptsDir -ChildPath $TaskScriptName
        New-EventLog -LogName $EventLog -Source $TaskScriptEventSource -ErrorAction SilentlyContinue   
        $TaskTrigger = New-ScheduledTaskTrigger -AtLogOn
        $TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-executionpolicy bypass -file $TaskScriptFullName -TaskName `"$TaskName`" -EventLog `"$EventLog`" -EventSource `"$TaskScriptEventSource`" -AutoLogonUser `"KioskUser0`""
        $TaskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries
        Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $TaskAction -Settings $TaskSettings -Principal $TaskPrincipal -Trigger $TaskTrigger
        If (Get-ScheduledTask | Where-Object { $_.TaskName -eq "$TaskName" }) {
            Write-Log -EntryType Information -EventId 50 -Message "Scheduled Task created successfully."
        }
        Else {
            Write-Log -EntryType Error -EventId 51 -Message "Scheduled Task not created."
            $ScriptExitCode = 1618
        }
    }
    Else {
        Write-Log -EntryType Information -EventId 52 -Message "Disabling the Start Button Right Click Menu for all users."
        # Set Default profile to hide Start Menu Right click
        $Groups = @(
            "Group1",
            "Group2",
            "Group3"
        )
        $WinXRoot = "$env:SystemDrive\Users\Default\Appdata\local\Microsoft\Windows\WinX\{0}"
        foreach ($grp in $Groups) { 
            $HideDir = Get-ItemProperty -Path ($WinXRoot -f $grp )
            $HideDir.Attributes = [System.IO.FileAttributes]::Hidden
        }
    }
    
    If ($Windows10) {
        Write-Log -EntryType Information -EventId 53 -Message "Copying Start Menu Layout file for Non Admins to '$DirKiosk' directory."
        If ($ShowDisplaySettings) {
            If ($CustomLaunchScript) {
                $StartMenuFile = "$DirStartMenu\Win10-LayoutModIficationWithSettings_AVDClient.xml"
            }
            Else {
                $StartMenuFile = "$DirStartMenu\Win10-LayoutModIficationWithSettings.xml"
            }
        }
        Else {
            If ($CustomLaunchScript) {
                $StartMenuFile = "$DirStartMenu\Win10-LayoutModIfication_AVDClient.xml"
            }
            Else {
                $StartMenuFile = "$DirStartMenu\Win10-LayoutModIfication.xml"
            }
        }
        Copy-Item -Path $StartMenuFile -Destination "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModIfication.xml" -Force
    }
}
    
#endregion Start Menu

#region User Logos

$null = cmd /c lgpo.exe /t "$DirGPO\computer-userlogos.txt" '2>&1'
Write-Log -EntryType Information -EventId 55 -Message "Configured User Logos to use default via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
Write-Log -EntryType Information -EventId 56 -Message "Backing up current User Logo files to '$DirKiosk\UserLogos'."
Copy-Item -Path "$env:ProgramData\Microsoft\User Account Pictures" -Destination "$DirKiosk\UserLogos" -Force
Write-Log -EntryType Information -EventId 57 -Message "Copying User Logo files to '$env:ProgramData\Microsoft\User Account Pictures'."
Get-ChildItem -Path $DirUserLogos | Copy-Item -Destination "$env:ProgramData\Microsoft\User Account Pictures" -Force

#endregion User Logos

#region Local GPO Settings

# Apply Non-Admin GPO settings
If ($AVDClientShell) {
    $nonAdminsFile = 'nonadmins-AVDClientShell.txt'
    $null = cmd /c lgpo.exe /t "$DirGPO\$nonAdminsFile" '2>&1'
    Write-Log -EntryType Information -EventId 60 -Message "Configured basic Explorer settings for kiosk user via Non-Administrators Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
}
Else {
    If ($Windows10) {
        $nonAdminsFile = 'nonadmins-ExplorerShell.txt'
        $null = cmd /c lgpo.exe /t "$DirGPO\$nonAdminsFile" '2>&1'
        Write-Log -EntryType Information -EventId 60 -Message "Configured basic Explorer settings for kiosk user via Non-Administrators Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
        $null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-HideSettings.txt" '2>&1'
        Write-Log -EntryType Information -EventId 61 -Message "Hid Settings App and Control Panel for kiosk user via Non-Administrators Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
        If (-not $WIfiAdapter) {
            $null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-noWIfi.txt" '2>&1'
            Write-Log -EntryType Information -EventId 62 -Message "No Wi-Fi Adapter Present. Disabled TaskBar tray area via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"    
        }
    }
    Else {
        $nonAdminsFile = 'nonadmins-MultiAppKiosk.txt'
        $null = cmd /c lgpo.exe /t "$DirGPO\$nonAdminsFile" '2>&1'
        Write-Log -EntryType Information -EventId 60 -Message "Configured basic Explorer settings for kiosk user via Non-Administrators Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"

    }
    If ($ShowDisplaySettings) {
        $null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-ShowDisplaySettings.txt" '2>&1'
        Write-Log -EntryType Information -EventId 63 -Message "Restricted Settings App and Control Panel to allow only Display Settings for kiosk user via Non-Administrators Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
    }
}

# Configure Feed URL for all Users
$outfile = "$env:Temp\Users-AVDURL.txt"
If ($AutoLogon) {
    $sourceFile = Join-Path -Path $DirGPO -ChildPath 'users-DefaultConnectionUrl.txt'
}
Else {
    $sourceFile = Join-Path -Path $DirGPO -ChildPath 'users-AutoSubscribe.txt'
}
(Get-Content -Path $sourceFile).Replace('<url>', $SubscribeUrl) | Out-File $outfile
$null = cmd /c lgpo.exe /t "$outfile" '2>&1'
Write-Log -EntryType Information -EventId 70 -Message "Configured AVD Feed URL for all users via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"

# Disable Cortana, Search, Feeds, Logon Animations, and Edge Shortcuts. These are computer settings only.
$null = cmd /c lgpo.exe /t "$DirGPO\Computer.txt" '2>&1'
Write-Log -EntryType Information -EventId 75 -Message "Disabled Cortana search, feeds, login animations, and Edge desktop shortcuts via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"

If ($AutoLogon) {
    # Disable Password requirement for screen saver lock and wake from sleep.
    $null = cmd /c lgpo.exe /t "$DirGPO\disablePasswordForUnlock.txt" '2>&1'
    Write-Log -EntryType Information -EventId 80 -Message "Disabled password requirement for screen saver lock and wake from sleep via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
    $null = cmd /c lgpo.exe /t "$DirGPO\nonadmins-autologon.txt" '2>&1'
    Write-Log -EntryType Information -EventId 81 -Message "Removed logoff, change password, lock workstation, and fast user switching entry points. `nlgpo.exe Exit Code: [$LastExitCode]"
}
Else {
    If ($Triggers -contains 'DeviceRemoval' -and $SmartCard -and -not $SecurityKey) {
        Write-Log -EntryType Information -EventId 82 -Message "Setting 'Smart Card Policy Service' to start Automatically (Delayed Start)."
        Get-Service -Name 'ScPolicySvc' | Set-Service -StartupType AutomaticDelayedStart
        If ($TriggerAction -eq 'Lock') {
            $null = cmd /c lgpo /s "$DirGPO\SmartCardLockWorkstation.inf" '2>&1'
            Write-Log -EntryType Information -EventId 84 -Message "Set 'Interactive logon: Smart Card Removal behavior' to 'Lock Workstation' via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
        }
        ElseIf ($TriggerAction -eq 'Logoff') {
            $null = cmd /c lgpo /s "$DirGPO\SmartCardLogOffWorkstation.inf" '2>&1'
            Write-Log -EntryType Information -EventId 84 -Message "Set 'Interactive logon: Smart Card Removal behavior' to 'Force Logoff Workstation' via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
        }
    }
    If ($Triggers -contains 'IdleTimeout' -and $TriggerAction -eq 'Lock') {
        # Will lock the system via the inactivity timeout built-in policy which locks the screen after inactivity.
        $sourceFile = Join-Path -Path $DirGPO -ChildPath 'MachineInactivityTimeout.inf'
        $outFile = Join-Path -Path $env:Temp -ChildPath 'MachineInactivityTimeout.inf'
        (Get-Content -Path $SourceFile).Replace('900', $Timeout) | Out-File $outFile
        $null = cmd /c lgpo /s "$outFile" '2>&1'
        Write-Log -EntryType Information -EventId 85 -Message "Set 'Interactive logon: Machine inactivity limit' to '$Timeout seconds' via Local Group Policy Object.`nlgpo.exe Exit Code: [$LastExitCode]"
    }
}

#endregion Local GPO Settings

#region Registry Edits

# update the Default User Hive to Hide the search button and task view icons on the taskbar.
$null = cmd /c REG LOAD "HKLM\Default" "$env:SystemDrive\Users\default\ntuser.dat" '2>&1'
Write-Log -EntryType Information -EventId 95 -Message "Loaded Default User Hive Registry Keys via Reg.exe.`nReg.exe Exit Code: [$LastExitCode]"

# Import registry keys file
Write-Log -EntryType Information -EventId 96 -Message "Loading Registry Keys from CSV file for modIfication of default user hive."
$RegKeys = Import-Csv -Path $FileRegKeys

# create the reg key restore file If it doesn't exist, else load it to compare for appending new rows.
Write-Log -EntryType Information -EventId 97 -Message "Creating a Registry key restore file for Kiosk Mode uninstall."
$FileRestore = "$DirKiosk\RegKeyRestore.csv"
New-Item -Path $FileRestore -ItemType File -Force | Out-Null
Add-Content -Path $FileRestore -Value 'Key,Value,Type,Data,Description'

# Loop through the registry key file and perform actions.
ForEach ($Entry in $RegKeys) {
    #reset from previous values
    $Key = $null
    $Value = $null
    $Type = $null
    $Data = $null
    $Description = $Null
    #set values
    $Key = $Entry.Key
    $Value = $Entry.Value
    $Type = $Entry.Type
    $Data = $Entry.Data
    $Description = $Entry.Description
    Write-Log -EntryType Information -EventId 99 -Message "Processing Registry Value to '$Description'."

    If ($Key -like 'HKCU\*') {
        $Key = $Key.Replace("HKCU\", "HKLM\Default\")
    }
    
    If ($null -ne $Data -and $Data -ne '') {
        # Output the Registry Key and value name to the restore csv so it can be deleted on restore.
        Add-Content -Path $FileRestore -Value "$Key,$Value,,"        
        $null = cmd /c REG ADD "$Key" /v $Value /t $Type /d "$Data" /f '2>&1'
        Write-Log -EntryType Information -EventId 100 -Message "Added '$Type' Value '$Value' with Value '$Data' to '$Key' with reg.exe.`nReg.exe Exit Code: [$LastExitCode]"
    }
    Else {
        # This is a delete action
        # Get the current value so we can restore it later If needed.
        $keyTemp = $Key.Replace("HKLM\", "HKLM:\")
        If (Get-ItemProperty -Path "$keyTemp" -Name "$Value" -ErrorAction SilentlyContinue) {
            $CurrentRegValue = Get-ItemPropertyValue -Path "$keyTemp" -Name $Value
            If ($CurrentRegValue) {
                Add-Content -Path $FileRestore -Value "$Key,$Value,$type,$CurrentRegValue"        
                Write-Log -EntryType Information -EventId 101 -Message "Stored '$Type' Value '$Value' with value '$CurrentRegValue' to '$Key' to Restore CSV file."
                $null = cmd /c REG DELETE "$Key" /v $Value /f '2>&1'
                Write-Log -EntryType Information -EventId 102 -Message "REG command to delete '$Value' from '$Key' exited with exit code: [$LastExitCode]."
            }
        }        
    }
}
Write-Log -EntryType Information -EventId 105 -Message "Unloading default user hive."
$null = cmd /c REG UNLOAD "HKLM\Default" '2>&1'
If ($LastExitCode -ne 0) {
    # sometimes the registry doesn't unload properly so we have to perform powershell garbage collection first.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 5
    $null = cmd /c REG UNLOAD "HKLM\Default" '2>&1'
    If ($LastExitCode -eq 0) {
        Write-Log -EntryType Information -EventId 106 -Message "Hive unloaded successfully."
    }
    Else {
        Write-Log -EntryType Error -EventId 107 -Message "Default User hive unloaded with exit code [$LastExitCode]."
    }
}
Else {
    Write-Log -EntryType Information -EventId 106 -Message "Hive unloaded successfully."
}

#endregion Registry Edits

#region Applocker Policy 

Write-Log -EntryType Information -EventId 110 -Message "Applying AppLocker Policy to disable Microsoft Edge, Internet Explorer, Notepad, Windows Search, and Wordpad for the Kiosk User."
# If there is an existing applocker policy, back it up and store its XML for restore.
# Else, copy a blank policy to the restore location.
# Then apply the new AppLocker Policy
If ($Windows10) {
    $FileAppLockerKiosk = Join-Path -Path $DirAppLocker -ChildPath "AVDClientKioskAppLockerPolicy.xml"
}
Else {
    $FileAppLockerKiosk = Join-Path -Path $DirAppLocker -ChildPath "MultiAppKioskAppLockerPolicy.xml"
}
[xml]$Policy = Get-ApplockerPolicy -Local -XML
If ($Policy.AppLockerPolicy.RuleCollection) {
    Get-ApplockerPolicy -Local -XML | out-file "$DirKiosk\ApplockerPolicy.xml" -force
}
Else {
    Copy-Item "$FileAppLockerClear" -Destination "$DirKiosk\ApplockerPolicy.xml" -Force
}
Set-AppLockerPolicy -XmlPolicy "$FileAppLockerKiosk"
Write-Log -EntryType Information -EventId 111 -Message "Enabling and Starting Application Identity Service"
Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
# Start the service If not already running
If ((Get-Service -Name AppIDSvc).Status -ne 'Running') {
    Start-Service -Name AppIDSvc
}

#endregion Applocker Policy

#region Shell Launcher Configuration

If ($AutoLogon -or $AVDClientShell -or -not $Windows10) {
    Write-Log -EntryType Information -EventId 113 -Message "Starting Assigned Access Configuration Section."
    . "$DirConfigurationScripts\AssignedAccessWmiBridgeHelpers.ps1"
    If ($AVDClientShell) {
        If ($AutoLogon) {
            $configFile = "Launch-AVDClient_AutoLogon.xml"
            Write-Log -EntryType Information -EventId 114 -Message "Enabling Custom AVD Client Launch Script Shell Launcher Settings with Autologon via WMI MDM bridge."
        }
        ElseIf ($CustomLaunchScript) {
            $configFile = "Launch-AVDClient.xml"
            Write-Log -EntryType Information -EventId 114 -Message "Enabling Custom AVD Client Launch Script Shell Launcher Settings for Security Keys via WMI MDM bridge."
        }
        Else {
            $configFile = "msrdcw.xml"
            Write-Log -EntryType Information -EventId 114 -Message "Enabling Remote Desktop Client Shell Launcher Settings via WMI MDM bridge."
        }
    }
    If ($AutoLogon -and $Windows10) {
        $configFile = "Explorer_AutoLogon.xml"
        Write-Log -EntryType Information -EventID 114 -Message "Enabling Explorer Shell Launcher Settings with Autologon via the WMI MDM bridge."
    }    
    If ($configFile) {
        $sourceFile = Join-Path $DirShellLauncherSettings -ChildPath $configFile
        $destFile = Join-Path -Path $DirKiosk -ChildPath "ShellLauncher.xml"
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Set-ShellLauncherConfiguration -FilePath $destFile
        If (Get-ShellLauncherConfiguration) {
            Write-Log -EntryType Information -EventId 115 -Message "Shell Launcher configuration successfully applied."
        }
        Else {
            Write-Log -EntryType Error -EventId 116 -Message "Shell Launcher configuration failed. Computer should be restarted first."
            Exit 1
        }
    }
    ElseIf (-not $Windows10 -and -not $AVDClientShell) {
        If ($AutoLogon) {
            If ($ShowDisplaySettings) {
                Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Custom Launch Script with Settings and Autologon."
                $configFile = "AzureVirtualDesktop_Settings_Autologon.xml"
            }
            Else {
                Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Custom Launch Script and Autologon."
                $configFile = "AzureVirtualDesktop_Autologon.xml"
            }
        }
        Else {
            If ($ShowDisplaySettings) {
                If ($CustomLaunchScript) {
                    Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Custom Launch Script with Settings."
                    $configFile = "AzureVirtualDesktop_Settings.xml"
                }
                Else {
                    Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Remote Desktop Client and Settings."
                    $configFile = "RemoteDesktop_Settings.xml"
                }
            }
            Else {
                If ($CustomLaunchScript) {
                    Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Custom Launch Script."
                    $configFile = "AzureVirtualDesktop.xml"
                }
                Else {
                    Write-Log -EntryType Information -EventId 113 -Message "Configuring MultiApp Kiosk settings for Remote Desktop Client."
                    $configFile = "RemoteDesktop.xml"
                }
            }
        }
        Write-Log -EntryType Information -EventId 114 -Message "Configuration File = $configFile"
        $sourceFile = Join-Path -Path $DirMultiAppSettings -ChildPath $configFile
        $destFile = Join-Path $DirKiosk -ChildPath 'MultiAppKioskConfiguration.xml'
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Set-MultiAppKioskConfiguration -FilePath $destFile
        If (Get-MultiAppKioskConfiguration) {
            Write-Log -EntryType Information -EventId 115 -Message "Multi-App Kiosk configuration successfully applied."
        }
        Else {
            Write-Log -EntryType Error -EventId 116 -Message "Multi-App Kiosk configuration failed. Computer should be restarted first."
            Exit 1        
        }
    }
}

#endregion Assigned Access Launcher

#region Keyboard Filter

Write-Log -EntryType Information -EventID 117 -Message "Enabling Keyboard filter."
Enable-WindowsOptionalFeature -Online -FeatureName Client-KeyboardFilter -All -NoRestart

# Configure Keyboard Filter after reboot
$TaskName = "(AVD Client) - Configure Keyboard Filter"
Write-Log -EntryType Information -EventId 118 -Message "Creating Scheduled Task: '$TaskName'."
$TaskScriptEventSource = 'Keyboard Filter Configuration'
$TaskDescription = "Configures the Keyboard Filter"
$TaskScriptName = 'Set-KeyboardFilterConfiguration.ps1'
$TaskScriptFullName = Join-Path -Path $SchedTasksScriptsDir -ChildPath $TaskScriptName
New-EventLog -LogName $EventLog -Source $TaskScriptEventSource -ErrorAction SilentlyContinue     
$TaskTrigger = New-ScheduledTaskTrigger -AtStartup
$TaskScriptArgs = "-TaskName `"$TaskName`" -EventLog `"$EventLog`" -EventSource `"$TaskScriptEventSource`""
If ($ShowDisplaySettings) {
    $TaskScriptArgs = "$TaskScriptArgs -ShowDisplaySettings"
}
$TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-executionpolicy bypass -file $TaskScriptFullName $TaskScriptArgs"
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $TaskAction -Settings $TaskSettings -Principal $TaskPrincipal -Trigger $TaskTrigger
If (Get-ScheduledTask | Where-Object { $_.TaskName -eq "$TaskName" }) {
    Write-Log -EntryType Information -EventId 119 -Message "Scheduled Task created successfully."
}
Else {
    Write-Log -EntryType Error -EventId 120 -Message "Scheduled Task not created."
    $ScriptExitCode = 1618
}

#endregion Keyboard Filter

#region Prevent Microsoft AAD Broker Timeout

If ($AutoLogon) {
    $TaskName = "(AVD Client) - Restart AAD Sign-in"
    $TaskDescription = 'Restarts the AAD Sign-in process If there are no active connections to prevent a stale sign-in attempt.'
    Write-Log -EntryType Information -EventId 135 -Message "Creating Scheduled Task: '$TaskName'."
    $TaskScriptEventSource = 'AAD Sign-in Restart'
    New-EventLog -LogName $EventLog -Source $TaskScriptEventSource -ErrorAction SilentlyContinue
    $TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -User KioskUser0
    $TaskTrigger.Delay = 'PT30M'
    $TaskTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At "12:00 AM" -RepetitionInterval (New-TimeSpan -Minutes 30)).Repetition
    $TaskAction = New-ScheduledTaskAction -Execute "wscript.exe" `
        -Argument "$SchedTasksScriptsDir\Restart-AADSignIn.vbs"
    # Set up scheduled task to run interactively (only when user is logged in)
    $TaskPrincipal = New-ScheduledTaskPrincipal -UserId KioskUser0 -LogonType Interactive
    $TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -Compatibility Win8 -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Description $TaskDescription -Principal $TaskPrincipal -Settings $TaskSettings -Trigger $TaskTrigger
    If (Get-ScheduledTask | Where-Object { $_.TaskName -eq "$TaskName" }) {
        Write-Log -EntryType Information -EventId 119 -Message "Scheduled Task created successfully."
    }
    Else {
        Write-Log -EntryType Error -EventId 120 -Message "Scheduled Task not created."
        $ScriptExitCode = 1618
    }
}

#endregion Prevent Microsoft AAD Broker Timeout
If ($ScriptExitCode -eq 1618) {
    Write-Log -EntryType Error -EventId 135 -Message "At least one critical failure occurred. Exiting Script and restarting computer."
    Restart-Computer -Force
}
Else {
    $ScriptExitCode -eq 1641
}
    
Write-Log -EntryType Information -EventId 150 -Message "Updating Group Policy"
$gpupdate = Start-Process -FilePath 'GPUpdate' -ArgumentList '/force' -Wait -PassThru
Write-Log -EntryType Information -EventID 151 -Message "GPUpdate Exit Code: [$($GPUpdate.ExitCode)]"
$null = cmd /c reg add 'HKLM\Software\Kiosk' /v Version /d "$($version.ToString())" /t REG_SZ /f
Write-Log -EntryType Information -EventId 199 -Message "Ending Kiosk Mode Configuration version '$($version.ToString())' with Exit Code: $ScriptExitCode"
Exit $ScriptExitCode
