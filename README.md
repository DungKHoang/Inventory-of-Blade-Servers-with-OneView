*This script collects information of BL Servers using HPE OneView PowerShell library

Prerequisites:
- Windows PowerShell 5.0
- The script requires the OneView PowerShell library 3.1 : https://github.com/HewlettPackard/POSH-HPOneView/releases



Process
 - Open a Windows PowerShell in administrator mode from your desktop
 


Run the script
 .\Get-SystemInventory-OneView.ps1 -OVApplianceIP <OV-IP-Address> -OVAdminName <Admin-name> -OVAdminPassword <password> 


Result:
 - List of CSV files 