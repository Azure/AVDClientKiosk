# Azure Virtual Desktop Client Kiosk

## Introduction

The source folder contains a script and supporting artifacts to configure a Windows operating system to act as a custom AVD Client kiosk. The custom configuration is built with a varied combination of:

- A Shell Launcher or Multi-App configuration applied via the Assigned Access CSP WMI Bridge. The assigned access configuration varies depending on the 'AutoLogon' and 'AVDClientShell' parameters and the operationg system version as follows:
- a multi-user local group policy object for non-administrative users.
- a local group policy object that affects computer settings.
- an applocker policy that disables Windows Search, Notepad, Internet Explorer, WordPad, and Edge for all Non-Administrators.
- one or more provisioning packages that remove pinned items from the start menu and enable SharedPC mode when that switch is used.

## Prerequisites

1. A currently [supported version of a Windows client operating system](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client) with the choice of editions based on the use of the **AVDClientShell** parameter as follows:
   
   1. The **AVDClientShell** option requires one of the following Windows client editions[^1]:
      * Education
      * Enterprise
      * Enterprise LTSC
      * IoT Enterprise
      * IoT Enterprise LTSC
   
   2. If you <ins>don't</ins> pick the **AVDClientShell** option, then supported Windows client editions include[^2]:
      * Education
      * Enterprise
      * Enterprise LTSC
      * IoT Enterprise
      * IoT Enterprise LTSC
      * Pro
      * Pro Education

2. The ability to run the installation script as SYSTEM. The instructions are provided in the [Installation section](#installation).

[^1]: For more information see [Shell Launcher Windows Edition Requirements](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/shell-launcher/?tabs=intune#windows-edition-requirements).
[^2]: For more information see [Assigned Access Windows Edition Requirements](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/overview?tabs=ps#windows-edition-requirements)

## User Interface and Behavior

### Summary

The user interface experience is determined by several factors and parameters. The parameters are all documented in the [Parameters section](#parameters) below, but the following tables outline the resulting user interface and device removal behavior based on the parameter values and operating system.

**Table 1:** Azure Virtual Desktop User Interface Summary

| AVDClientShell | AutoLogon | Operating System | User Interface |
|:--------------:|:---------:|------------------|----------------|
| True           | True      | Windows 10+ | The default explorer shell will be replaced with the Remote Desktop client for Windows via the Shell Launcher Assigned Access CSP. The Windows 10 (or later) client will automatically logon to the shell with 'KioskUser0' account. The user will be presented with a dialog to logon to Remote Desktop client. |
| True           | False     | Windows 10+ | The default explorer shell will be replaced with the Remote Desktop client for Windows via the Shell Launcher Assigned Access CSP. The user will be required to sign in to the Windows 10 (or later) client and will be automatically signed in to the Remote Desktop client. |
| False          | True      | Windows 10 | The default shell remains explorer.exe; however, it is heavily customized and locked down to allow only the Remote Desktop client to be executed from the customized Start Menu. This configuration allows for easier user interaction with remote sessions, the Remote Desktop client interface, and Display Settings if the option is chosen. The Shell Launcher configuration of the Assigned Access CSP is used to configure the Windows 10 client with autologon to the shell with the 'KioskUser0' account. The user will be presented with a dialog to logon to Remote Desktop client. |
| False          | True      | Windows 11 | A Multi-App Kiosk configuration is applied via the Assigned Access CSP which automatically locks down the explorer interface to only show the Remote Desktop client. This configuration allows for easier user interaction with remote sessions and the Remote Desktop client along with Display Settings if the option is chosen. The Windows 11 22H2+ client will automatically logon to the shell with 'KioskUser0' account. The user will be presented with a dialog to logon to Remote Desktop client. |
| False          | False     | Windows 10 | *This is the default configuration if no parameters are specified when running the script on Windows 10.* The explorer shell is the default shell; however, it is heavily customized and locked down to allow only the Remote Desktop client to be executed from the customized Start Menu. This configuration allows for easier user interaction with remote sessions, the Remote Desktop client interface, and display settings if the option is chosen. The user will be required to sign in to the Windows 10 client and will be automatically signed in to the Remote Desktop client. |
| False          | False     | Windows 11 | *This is the default configuration if no parameters are specified when running the script on Windows 11 22H2+.* A Multi-App Kiosk configuration is applied via the Assigned Access CSP which automatically locks down the explorer interface to only show the Remote Desktop client. This configuration allows for easier user interaction with remote sessions, the Remote Desktop client interface, and the display settings if the option is chosen. The user will be required to sign in to the Windows 11 client and will be automatically signed in to the Remote Desktop client. |

**Table 2:** Azure Virtual Desktop Device Removal Action Summary

| AutoLogon | AuthenticationDeviceRemovalAction | Result of Device Removal |
|:---------:|:---------------------------------:|-------------------------------|
| True      | N/A | If the user removes their YUBIKEY (if option selected) or Smart Card or closes the Remote Desktop client, then the client is closed, reset to remove their user credentials and the feed, and then restarted with the Entra Id logon dialog displayed. |
| False     | Lock | If the user removes their YUBIKEY (if option selected) or Smart Card the local workstation is locked. If they close the Remote Desktop Client, then they are forcefully logged off. |
| False     | Logoff | If the user removes their YUBIKEY (if option selected) or Smart Card they are forcefully logged off the local workstation. If they close the Remote Desktop Client, then they are also forcefully logged off the local workstation. |

### Multi-App Kiosk

When the operating system of the thin client device is Windows 11 22H2 or greater, and the **AVDClientShell** switch parameter is **not** specified, the device is configured using the [Multi-App Kiosk Assigned Access CSP](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/customize/multi-app-kiosk). The user interface experience with the **ShowDisplaySettings** parameter selected is shown in the video and pictures below.

https://github.com/user-attachments/assets/b85689b2-8f15-4177-9f4e-ad012d5dce51

**Picture 1:** Multi-App Showing a client connection

![Multi-App Showing a client connection](docs/media/multi-app-showing-client-and-connection.png)

**Picture 2:** Multi-App Showing Display Settings

![Multi-App Showing a client connection](docs/media/displaySettings.png)

### Shell Launcher

When the **AVDClientShell** parameter is selected on any operating system, the default user shell (explorer.exe) is replaced with the [Remote Desktop client](https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-remote-desktop-client?tabs=windows) using the [Shell Launcher CSP](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/customize/shell-launcher). The user interface experience is shown in the video and picture below. 

https://github.com/user-attachments/assets/5252b15d-a953-4b5a-9e3f-541c493df85e

**Picture 3:** Shell Launcher full screen

![Shell Launcher full Screen](docs/media/shellLauncherInterface.png)

## Installation

This section documents the parameters and the manual installation instructions

### Parameters

**Table 2:** Set-AVDClientKioskSettings.ps1 Parameters

| Parameter Name | Type | Description | Notes/Requirements |
|:---------------|:----:|:------------|:-------------------|
| ApplySTIGs | Switch | Determines if the latest DoD Security Technical Implementation Guide Group Policy Objects are automatically downloaded from [Cyber Command](https://public.cyber.mil/stigs/gpo) and applied via the Local Group Policy Object (LGPO) tool to the system. If they are, then several delta settings are applied to allow the system to communicate with Entra Id and complete autologon (if applicable). | Requires access to https://public.cyber.mil/stigs/gpo |
| AuthenticationDeviceRemovalAction | String | Determines the action to take when a user removes either a smart card or Yubikey (when option chosen). Possible values are 'Lock' or 'Logoff'. | Default is 'Lock'. Only valid in the direct logon mode (Autologon is not specified). | 
| Autologon | Switch | Determines if Autologon is enabled through the Shell Launcher or Multi-App Kiosk configuration. These features will automatically create a new user - 'KioskUser0' - which will not have a password and be configured to automatically logon when Windows starts. ||
| AVDClientShell | Switch | Determines whether the Windows Shell is replaced by the Remote Desktop client for Windows or remains the default 'explorer.exe'. When not specified the default 'explorer' shell is used and on Windows 11 22H2 and later, the Multi-App Kiosk configuration is used along with additional local group policy settings and provisioning packages to lock down the shell. On Windows 10, only local group policy settings and provisioning packages are used to lock down the shell. ||
| EnvironmentAVD | String | Determines the Azure environment to which you are connecting. It ultimately determines the Url of the Remote Desktop Feed which varies by environment by setting the $SubscribeUrl variable and replacing placeholders in several files during installation. The list of Urls can be found at https://learn.microsoft.com/en-us/azure/virtual-desktop/users/connect-microsoft-store?source=recommendations#subscribe-to-a-workspace. | Default is 'AzureUSGovernment' |
| InstallAVDClient | Switch | Determines if the latest Remote Desktop client for Windows and the Visual Studio C++ Redistributables are downloaded from the Internet and installed prior to configuration. | Requires Internet Access to https://go.microsoft.com/fwlink/?linkid=2139369 and https://aka.ms/vs/17/release/vc_redist.x64.exe |
| SharedPC | Switch | Determines if the computer is setup as a shared PC. The account management process is enabled and all user profiles are automatically deleted on logoff. | Only valid for direct logon mode (Autologon is not set). |
| ShowDisplaySettings | Switch | Determines if the Settings App and Control Panel are restricted to only allow access to the Display Settings page. If this value is not set, then the Settings app and Control Panel are not displayed or accessible. | Only valid when 'AVDClientShell' is not selected. |
| Version | Version |  Allows tracking of the installed version using configuration management software such as Microsoft Endpoint Manager or Microsoft Endpoint Configuration Manager by querying the value of the registry value: HKLM\Software\Kiosk\version. ||
| Yubikey | Switch | Determines if the WMI Event Subscription Filter also monitors for Yubikey removal. ||

### Manual Installation

***Important*** You need to run the PowerShell script with system priviledges. The easiest way to do this is to download [PSExec](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec). Then extract the Zip to a folder and open an administrative command prompt.

1. Execute PowerShell as SYSTEM by running the following command:

    ```
    psexec64 -s -i powershell
    ```

2. In the newly opened PowerShell window, execute the following:

    ``` powershell
    set-executionpolicy bypass -scope process
    ```

3. Change directories to the source directory.

4. Then execute the script using the correct parameters as exemplified below:

    * Default parameter values:
  
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1
      ```

    * Apply the latest STIGs
  
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1 -ApplySTIGs
      ```
    * Install the Remote Desktop client, enable SharedPC Mode (Delete User Profiles), and show display settings
    
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1 -SharedPC -ShowDisplaySettings
      ```

    * Enable the AVD Client Shell
    
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1 -AVDClientShell
      ```

    * Enable Autologon with the AVD Client Shell
  
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1 -AutoLogon -AVDClientShell
      ```

    * Enable Autologon with Yubikey option
     
      ``` powershell
      .\Set-AVDClientKioskSettings.ps1 -AutoLogon -Yubikey
      ```

### Microsoft Endpoint Manager (Intune) Deployment

This configuration supports deployment through Intune as a Win32 App. The instructions for creating a Win32 application are available at https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management.

The command line should be similar to:

``` cmd
powershell.exe -executionpolicy bypass -file Set-AVDClientKioskSettings.ps1 -SharedPC -Yubikey -EnvironmentAVD AzureCloud -ShowDisplaySettings
```

You can utilize the DetectionScript.ps1 as a custom detection script in Intune which will automatically look for all the configurations applied by the script. you can also use a Registry detection method to read the value of ```HKEY_LOCAL_MACHINE\Software\Kiosk\version``` which should be equal to the value of the version parameter used in the deployment script. This would be useful for when you do not implement AutoLogon.

### Manual Removal

Remove the configuration from the PowerShell prompt using:

``` powershell
.\Remove-KioskSettings.ps1
```
## Troubleshooting

1. All events from the configuration scripts and scheduled tasks are logged to the **Application and Services Logs | AVD Client Kiosk** event log.
2. You can break autologon of the Kiosk User account during restart by holding down the [LEFT SHIFT] button down and continuously tap [ENTER] during restart all the way to the lock screen appears.
