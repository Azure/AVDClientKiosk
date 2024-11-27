[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $EventLog,
    [Parameter(Mandatory=$true)]
    [string]
    $EventSource,
    [Parameter(Mandatory=$true)]
    [string]
    $AutoLogonUser,
    [Parameter(Mandatory=$true)]
    [string]
    $TaskName
)
#region Variables
$Script:FullName = $MyInvocation.MyCommand.Path
$WinX = "$env:SystemDrive\Users\$AutoLogonUser\Appdata\local\Microsoft\Windows\WinX"
#endregion Variables

#region Main

Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1000 -Message "Executing '$Script:FullName'."
$DefaultGroupCount = (Get-ChildItem -Path "$env:SystemDrive\Users\Default\Appdata\Local\Microsoft\Windows\Winx").Count
If (Test-Path -Path $WinX) {
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1001 -Message "Found '$WinX'."
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1001 -Message "Listing folders under '$WinX'."
} Else {
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Warning -EventId 1001 -Message "Could not find '$WinX'. Exiting script."
    Exit
}
$HiddenCount = (Get-ChildItem -Path $WinX -Hidden).Count
$FoldersToHide = Get-ChildItem -Path $winX
If ($HiddenCount -lt $DefaultGroupCount -or $FolderstoHide) {
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1002 -Message "Found $($FolderstoHide.Count) folders that are not hidden under '$WinX'. Hiding these folders."
    $counter = 0
    Do {
        $FoldersToHide = Get-ChildItem -Path $WinX
        ForEach ($Folder in $FoldersToHide)  {
            Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1003 -Message "Hiding '$($Folder.FullName)'."
            (Get-ItemProperty -Path $Folder.FullName).Attributes = [System.IO.FileAttributes]::Hidden
        }
        $counter ++
        Start-Sleep -Seconds 1
        $HiddenCount = (Get-ChildItem -Path $WinX -Hidden).Count
    } Until (($HiddenCount -ge $DefaultGroupCount -and (-not(Get-ChildItem -Path $WinX))) -or $Counter -eq 30)
}

If ($counter -le 30) {
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1004 -Message "Successfully applied the hidden attribute to '$HiddenCount' folders. "
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1005 -Message "Deleting Scheduled Task: '$TaskName'."
    Get-ScheduledTask | Where-Object {$_.TaskName -eq "$TaskName"} | Unregister-ScheduledTask -Confirm:$False
} Else {
    Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Warning -EventId 1010 -Message "After $Counter seconds, there are still folders to be hidden. This task will run again."
}

Write-EventLog -LogName $EventLog -Source $EventSource -EntryType Information -EventId 1020 -Message "Ending '$Script:FullName'."
#endregion Main
