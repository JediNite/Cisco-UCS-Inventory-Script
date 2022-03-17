#
#	Cisco IMC Inventory Script (IIS) - v1.3 (17-04-2016)
#	 Martijn Smit <martijn@lostdomain.org>
#
#	- Grab all information from an IMC and output it to a file.
#	- Useful for post-implementation info dumps and scheduled checks
#
#	Usage: .\IMC-Inventory-Script.ps1 -IMC <IP or hostname IMC> [-OutFile <report.html>] [[-Password <passwd>] [-Username <user>]]
#
#   - If Username or Password parameter are omitted, the script will prompt for manual credentials
#
# v1.3 - 17-04-2016 - Added multiple IMC support via a CSV file and logging to a file.
# v1.2 - 30-06-2014 - Added a recommendations tab for configuration and health recommendations,
#                     taken from experience in the field.
# v1.1 - 30-12-2013 - Add arguments for the require input data, allow it to run as a scheduled task.
# v1.0 - 25-11-2013 - First version; capture every bit of information from IMC I could think of.
#
param(	[string]$IMC = $null,
		[string]$OutFile = $null,
		[string]$Password = $null,
		[string]$Username = $null,
		[switch]$GeneratePassword,
		[string]$CSVFile = $null,
		[switch]$SendEmail = $null,
		[string]$LogFile = $null)

# Configure Mail Variables
$smtpServer = "smtpserver" 
$mailFrom = "Cisco IMC Inventory Script <imchcheck@domain.com>"
$mailTo = "user@domain.com"

###############################################################################################
# DO NOT UPDATE BELOW THIS LINE                                                               #
###############################################################################################

# Import the Cisco IMC PowerTool module, search for version 1 and version 2 and load which one we find
if(!(Get-Module -ListAvailable -Name Cisco.IMC))
{
	# Version 2 not found, look for version 1
	if(!(Get-Module -ListAvailable -Name CiscoImcPS))
	{
		Write-Host "Cisco IMC PowerTool version 1 or 2 not found!" -ForegroundColor "red"
		Exit
	}
	else {
		# Load PowerTool 1.x
		Import-Module CiscoImcPS
		Write-Host "Cisco IMC PowerTool version 1.x loaded" -ForegroundColor "yellow"
	}
}
else {
	# Load PowerTool 2.x
	Import-Module Cisco.IMC
	Write-Host "Cisco IMC PowerTool version 2.x or higher loaded" -ForegroundColor "yellow"
}

# Generate an encrypted password from input
if($GeneratePassword.IsPresent)
{
#	$PlainPassword = Read-Host "Please enter your password"
	Write-Host -NoNewline "Please enter your password: "
	$PlainPassword = Read-Host
	$SecurePassword = $PlainPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
	Write-Host "Done! Here's your encrypted password, save this in the CSV:"
	Write-Host $SecurePassword
	exit;
}

### START FUNCTION ###
function WriteLog
{
	param ([string]$logstring)

	if($LogFile -ne "") {
		Add-Content $Logfile -value "[$([DateTime]::Now)] - $logstring"
	}
	Write-Host "[$([DateTime]::Now)] - $logstring"
}
### END FUNCTION ###

### START FUNCTION ###
function GenerateReport()
{
	Param([Parameter(Mandatory=$true)][string]$IMC,
				[Parameter(Mandatory=$true)][string]$OutFile,
				[Parameter(Mandatory=$false)][string]$Username,
				[Parameter(Mandatory=$false)][string]$Password,
				[Parameter(Mandatory=$true)][string]$ManualGeneration)

	# Generate credentials
	if($Username -eq "" -or $Password -eq "") {
		$IMCCredentials = $Host.UI.PromptForCredential("IMC Authentication", "Enter IMC Login", "", "")
	}
	else
	{
		if($ManualGeneration -eq "manual") {
			$IMCCredentials = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $Username, ($Password | ConvertTo-SecureString -AsPlainText -Force)
		}
		else {
			$IMCCredentials = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $Username, ($Password | ConvertTo-SecureString)
		}
	}

	# Create or empty file
	$OutFileObj = New-Item -ItemType file $OutFile -Force

	# Get current date and time
	$date = Get-Date -Format g

	$Global:TMP_OUTPUT  = ""
	Function AddToOutput($txt)
	{
		$Global:TMP_OUTPUT += $txt, "`n"
	}

	# Connect to the IMC
	$imcc = Connect-Imc -Name $IMC -Credential $IMCCredentials
	$IMCName = $imcc.Imc

	# Test connection
	$connected = Get-UcsPSSession
	if ($connected -eq $null) {
		WriteLog "Error connecting to IMC!"
		Return
	}

	WriteLog "Connected to: $IMC, starting inventory collection and outputting to: $OutFile"

	# Output HTML headers and CSS
	AddToOutput -txt "<html>"
	AddToOutput -txt "<html>"
	AddToOutput -txt "<head>"
	AddToOutput -txt "<meta http-equiv='Content-Type' content='text/html; charset=utf-8' />"
	AddToOutput -txt "<title>Cisco IMC Inventory Script - $IMCName</title>"
	AddToOutput -txt "<style type='text/css'>"
	AddToOutput -txt "body { font-family: 'Calibri', serif; font-size:14px; }"
	AddToOutput -txt "div.content { border-top: #e3e3e3 solid 3px; clear: left; width: 100%; }"
	AddToOutput -txt "div.content.inactive { display: none; }"
	AddToOutput -text "div.content-sub.inactive { display: none; } "
	AddToOutput -txt "ul { height: 2em; list-style: none; margin: 0; padding: 0; }"
	AddToOutput -txt "ul a { background: #e3e3e3; color: #000000; display: block; float: left; height: 2em; padding-left: 10px; text-decoration: none; font-weight: bold; }"
	AddToOutput -txt "ul a:hover { background-color: #e85a05; background-position: 0 -120px; color: #ffffff; }"
	AddToOutput -txt "ul a:hover span { background-position: 100% -120px; }"
	AddToOutput -txt "ul li { float: left; margin: 0 1px 0 0; }"
	AddToOutput -txt "ul li.ui-tabs-active a { background-color: #e85a05; background-position: 0 -60px; color: #fff; font-weight: bold; }"
	AddToOutput -txt "ul li.ui-tabs-active a span { background-position: 100% -60px; }"
	AddToOutput -txt "ul span { display: block; line-height: 2em; padding-right: 10px; }"
	AddToOutput -txt "table { border: #e3e3e3 2px solid; border-collapse: collapse; min-width: 800px; }"
	AddToOutput -txt "th { padding: 2px; border: #e3e3e3 2px solid; background-color:#e3e3e3; }"
	AddToOutput -txt "td { padding: 2px; border: #e3e3e3 2px solid; }"
	AddToOutput -txt ".ui-tabs-vertical .ui-tabs-nav {  float: left; width: 250px; padding-top: 25px; }"
	AddToOutput -txt ".ui-tabs-vertical .ui-tabs-nav li { height: 30px; }"
	AddToOutput -txt ".ui-tabs-vertical .ui-tabs-nav li a { padding-top: 7px; width: 200px; }"
	AddToOutput -txt ".ui-tabs-vertical .ui-tabs-panel { float: left; width: 1100px; }"
	AddToOutput -txt "</style>"
	# Include jQuery and jQueryUI and define the tabs
	AddToOutput -txt "<script src='http://code.jquery.com/jquery-1.9.1.js'></script>"
	AddToOutput -txt "<script src='http://code.jquery.com/ui/1.10.3/jquery-ui.js'></script>"
	AddToOutput -txt "<script> jQuery(function() {"
	AddToOutput -txt "jQuery('#tabs').tabs();  "
	AddToOutput -txt "jQuery('#equipment-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#equipment-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#server-config-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#server-config-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#lan-config-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#lan-config-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#san-config-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#san-config-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#admin-config-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#admin-config-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#stats-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix');"
	AddToOutput -txt "jQuery('#stats-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "jQuery('#recommendations-tabs').tabs().addClass('ui-tabs-vertical ui-helper-clearfix'); "
	AddToOutput -txt "jQuery('#recommendations-tabs li').removeClass('ui-corner-top').addClass('ui-corner-left'); "
	AddToOutput -txt "});</script>"
	AddToOutput -txt "</head>"
	AddToOutput -txt "<body>"
	AddToOutput -txt "<h1>Cisco IMC Inventory Script - $IMCName</h1>"
	AddToOutput -txt "Generated: "
	$Global:TMP_OUTPUT += $date
	AddToOutput -txt "<div id='tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#equipment'><span>Hardware Inventory</span></a></li>"
	AddToOutput -txt "<li><a href='#server-config'><span>Service Configuration</span></a></li>"
	AddToOutput -txt "<li><a href='#lan-config'><span>LAN Configuration</span></a></li>"
	AddToOutput -txt "<li><a href='#san-config'><span>SAN Configuration</span></a></li>"
	AddToOutput -txt "<li><a href='#admin-config'><span>Admin Configuration</span></a></li>"
	AddToOutput -txt "<li><a href='#stats'><span>Statistics &amp; Faults</span></a></li>"
	AddToOutput -txt "<li><a href='#recommendations'><span>Recommendations</span></a></li>"
	AddToOutput -txt "</ul>"


	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################    EQUIPMENT OVERVIEW   ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='equipment'>"
	AddToOutput -txt "<div id='equipment-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#equipment-tab-fi'>Fabric Interconnect</a></li>"
	AddToOutput -txt "<li><a href='#equipment-tab-chassis'>Chassis</a></li>"
	AddToOutput -txt "<li><a href='#equipment-tab-servers'>Servers</a></li>"
	AddToOutput -txt "<li><a href='#equipment-tab-firmware'>Firmware</a></li>"
	AddToOutput -txt "</ul>"
	AddToOutput -txt "<div class='content-sub' id='equipment-tab-fi'>"

	# Get Fabric Interconnects
	AddToOutput -txt "<h2>Fabric Interconnects</h2>"
	$Global:TMP_OUTPUT += Get-ImcNetworkElement | Select-Object Imc,Rn,OobIfIp,OobIfMask,OobIfGw,Operability,Model,Serial | ConvertTo-Html -Fragment

	# Get Fabric Interconnect inventory
	AddToOutput -txt "<h2>Fabric Interconnect Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcFiModule | Sort-Object -Property Dn | Select-Object Dn,Model,Descr,OperState,State,Serial | ConvertTo-Html -Fragment

	# Get Cluster State
	AddToOutput -txt "<h2>Cluster Status</h2>"
	$Global:TMP_OUTPUT += Get-ImcStatus | Select-Object Name,VirtualIpv4Address,HaConfiguration,HaReadiness,HaReady,EthernetState | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcStatus | Select-Object FiALeadership,FiAOobIpv4Address,FiAManagementServicesState | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcStatus | Select-Object FiBLeadership,FiBOobIpv4Address,FiBManagementServicesState | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>"
	AddToOutput -txt "<div class='content-sub' id='equipment-tab-chassis'>"

	# Get Chassis info
	AddToOutput -txt "<h2>Chassis Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcChassis | Sort-Object -Property Rn | Select-Object Rn,AdminState,Model,OperState,LicState,Power,Thermal,Serial | ConvertTo-Html -Fragment

	# Get chassis IOM info
	AddToOutput -txt "<h2>IOM Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcIom | Sort-Object -Property Dn | Select-Object ChassisId,Rn,Model,Discovery,ConfigState,OperState,Side,Thermal,Serial | ConvertTo-Html -Fragment

	# Get Fabric Interconnect to Chassis port mapping
	AddToOutput -txt "<h2>Fabric Interconnect to IOM Connections</h2>"
	$Global:TMP_OUTPUT += Get-ImcEtherSwitchIntFIo | Select-Object ChassisId,Discovery,Model,OperState,SwitchId,PeerSlotId,PeerPortId,SlotId,PortId,XcvrType | ConvertTo-Html -Fragment

	# Get Global chassis discovery policy
	$chassisDiscoveryPolicy = Get-ImcChassisDiscoveryPolicy | Select-Object Rn,LinkAggregationPref,Action
	AddToOutput -txt "<h2>Chassis Discovery Policy</h2>"
	$Global:TMP_OUTPUT += $chassisDiscoveryPolicy | ConvertTo-Html -Fragment

	# Get Global chassis power redundancy policy
	$chassisPowerRedPolicy = Get-ImcPowerControlPolicy
	AddToOutput -txt "<h2>Chassis Power Redundancy Policy</h2>"
	$Global:TMP_OUTPUT += $chassisPowerRedPolicy | Select-Object Rn,Redundancy | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='equipment-tab-servers'>"

	# Get all IMC servers and server info

	# Does the system have blade servers? return those
	if (Get-ImcBlade) {
		AddToOutput -txt "<h2>Server Inventory - Blades</h2>"
		$Global:TMP_OUTPUT += Get-ImcBlade | Select-Object ServerId,Model,AvailableMemory,@{N='CPUs';E={$_.NumOfCpus}},@{N='Cores';E={$_.NumOfCores}},@{N='Adaptors';E={$_.NumOfAdaptors}},@{N='eNICs';E={$_.NumOfEthHostIfs}},@{N='fNICs';E={$_.NumOfFcHostIfs}},AssignedToDn,OperPower,Serial | Sort-Object -Property ChassisID,SlotID | ConvertTo-Html -Fragment
	}
	# Does the system have rack servers? return those
	if (Get-ImcRackUnit) {
		AddToOutput -txt "<h2>Server Inventory - Rack-mounts</h2>"
		$Global:TMP_OUTPUT += Get-ImcRackUnit | Select-Object Dn,ServerId,Model,AvailableMemory,@{N='CPUs';E={$_.NumOfCpus}},@{N='Cores';E={$_.NumOfCores}},@{N='Adaptors';E={$_.NumOfAdaptors}},@{N='eNICs';E={$_.NumOfEthHostIfs}},@{N='fNICs';E={$_.NumOfFcHostIfs}},AssignedToDn,OperPower,Serial | Sort-Object { [int]$_.ServerId } | ConvertTo-Html -Fragment
	}

	# Get server adaptor (mezzanine card) info
	AddToOutput -txt "<h2>Server Adaptor Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorUnit | Sort-Object -Property Dn | Select-Object Dn,ChassisId,BladeId,Rn,Model | ConvertTo-Html -Fragment

	# Get server adaptor port expander info
	AddToOutput -txt "<h2>Servers with Adaptor Port Expanders</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorUnitExtn | Sort-Object -Property Dn | Select-Object Dn,Model,Presence | ConvertTo-Html -Fragment

	# Get server processor info
	AddToOutput -txt "<h2>Server CPU Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcProcessorUnit | Sort-Object -Property Dn | Select-Object Dn,SocketDesignation,Cores,CoresEnabled,Threads,Speed,OperState,Thermal,Model | Where-Object {$_.OperState -ne "removed"} | ConvertTo-Html -Fragment

	# Get server memory info
	AddToOutput -txt "<h2>Server Memory Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcMemoryUnit | Sort-Object -Property Dn,Location | Where-Object {$_.Capacity -ne "unspecified"} | Select-Object -Property Dn,Location,Capacity,Clock,OperState,Model | ConvertTo-Html -Fragment

	# Get server storage controller info
	AddToOutput -txt "<h2>Server Storage Controller Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcStorageController | Sort-Object -Property Dn | Select-Object Dn,Vendor,Model | ConvertTo-Html -Fragment

	# Get server local disk info
	AddToOutput -txt "<h2>Server Local Disk Inventory</h2>"
	$Global:TMP_OUTPUT += Get-ImcStorageLocalDisk | Sort-Object -Property Dn | Select-Object Dn,Model,Size,Serial,DeviceVersion | Where-Object {$_.Size -ne "unknown"}  | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='equipment-tab-firmware'>"

	# Get IMC firmware version
	AddToOutput -txt "<h2>IMC</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "system"} | ConvertTo-Html -Fragment

	# Get Fabric Interconnect firmware
	AddToOutput -txt "<h2>Fabric Interconnect</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "switch-kernel" -OR $_.Type -eq "switch-software"} | ConvertTo-Html -Fragment

	# Get IOM firmware
	AddToOutput -txt "<h2>IOM</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "iocard"} | Where-Object -FilterScript {$_.Deployment -notlike "boot-loader"} | ConvertTo-Html -Fragment

	# Get Server CIMC firmware
	AddToOutput -txt "<h2>Server CIMC</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "blade-controller"} | Where-Object -FilterScript {$_.Deployment -notlike "boot-loader"} | ConvertTo-Html -Fragment
	
	# Get Server BIOS versions
	AddToOutput -txt "<h2>Server BIOS</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "blade-bios" -Or $_.Type -eq "rack-bios"} | ConvertTo-Html -Fragment

	# Get Server Board Controller firmware
	AddToOutput -txt "<h2>Server Board</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "board-controller"} | Where-Object -FilterScript {$_.Deployment -notlike "boot-loader"} | ConvertTo-Html -Fragment

	# Get Server Adapter firmware
	AddToOutput -txt "<h2>Server Adapters</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "adaptor"} | Where-Object -FilterScript {$_.Deployment -notlike "boot-loader"} | ConvertTo-Html -Fragment
	
	# Get FlexFlash Controller firmware
	AddToOutput -txt "<h2>FlexFlash Controllers</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "flexflash-controller"} | Where-Object -FilterScript {$_.Deployment -notlike "boot-loader"} | ConvertTo-Html -Fragment	
	
	# Get Server Disk firmware
	AddToOutput -txt "<h2>Server Local Disks</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "local-disk"} | ConvertTo-Html -Fragment	

	# Get SAS Expander firmware
	AddToOutput -txt "<h2>SAS Adapters</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareRunning | Select-Object Deployment,Dn,Type,Version,PackageVersion | Sort-Object -Property Dn | Where-Object {$_.Type -eq "sas-exp"} | ConvertTo-Html -Fragment	

	# Get Host Firmware Packages
	AddToOutput -txt "<h2>Host Firmware Packages</h2>"
	$Global:TMP_OUTPUT += Get-ImcFirmwareComputeHostPack | Select-Object Dn,Name,BladeBundleVersion,RackBundleVersion | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs container
	AddToOutput -txt "</div>" # end tab

	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################  SERVICE CONFIGURATION  ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='server-config'>"
	AddToOutput -txt "<div id='server-config-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#server-config-tab-sp'>Service Profiles</a></li>"
	AddToOutput -txt "<li><a href='#server-config-tab-policies'>Policies</a></li>"
	AddToOutput -txt "<li><a href='#server-config-tab-pools'>Pools</a></li>"
	AddToOutput -txt "</ul>"
	AddToOutput -txt "<div class='content-sub' id='server-config-tab-sp'>"

	# Get Service Profile Templates
	AddToOutput -txt "<h2>Service Profile Templates</h2>"
	$Global:TMP_OUTPUT += Get-ImcServiceProfile | Where-object {$_.Type -ne "instance"}  | Sort-object -Property Name | Select-Object Dn,Name,BiosProfileName,BootPolicyName,HostFwPolicyName,LocalDiskPolicyName,MaintPolicyName,VconProfileName | ConvertTo-Html -Fragment

	# Get Service Profiles
	AddToOutput -txt "<h2>Service Profiles</h2>"
	$Global:TMP_OUTPUT += Get-ImcServiceProfile | Where-object {$_.Type -eq "instance"}  | Sort-object -Property Name | Select-Object Dn,Name,OperSrcTemplName,AssocState,PnDn,BiosProfileName,IdentPoolName,Uuid,BootPolicyName,HostFwPolicyName,LocalDiskPolicyName,MaintPolicyName,VconProfileName,OperState | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='server-config-tab-policies'>"

	# Get Maintenance Policies
	AddToOutput -txt "<h2>Maintenance Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcMaintenancePolicy | Select-Object Name,Dn,UptimeDisr,Descr | ConvertTo-Html -Fragment

	# Get Boot Policies
	AddToOutput -txt "<h2>Boot Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcBootPolicy | sort-object -Property Dn | Select-Object Dn,Name,Purpose,RebootOnUpdate | ConvertTo-Html -Fragment

	# Get SAN Boot Policies
	AddToOutput -txt "<h2>SAN Boot Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcLsbootSanImagePath | sort-object -Property Dn | Select-Object Dn,Type,Vnicname,Lun,Wwn | Where-Object -FilterScript {$_.Dn -notlike "sys/chassis*"} | ConvertTo-Html -Fragment

	# Get Local Disk Policies
	AddToOutput -txt "<h2>Local Disk Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcLocalDiskConfigPolicy | Select-Object Dn,Name,Mode,Descr | ConvertTo-Html -Fragment

	# Get Scrub Policies
	AddToOutput -txt "<h2>Scrub Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcScrubPolicy | Select-Object Dn,Name,BiosSettingsScrub,DiskScrub | Where-Object {$_.Name -ne "policy"} | ConvertTo-Html -Fragment

	# Get BIOS Policies
	AddToOutput -txt "<h2>BIOS Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"} | Select-Object Dn,Name | ConvertTo-Html -Fragment

	# Get BIOS Policy Settings
	AddToOutput -txt "<h2>BIOS Policy Settings</h2>"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfQuietBoot | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfPOSTErrorPause | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfResumeOnACPowerLoss | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfFrontPanelLockout | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosTurboBoost | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosEnhancedIntelSpeedStep | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosHyperThreading | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfCoreMultiProcessing | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosExecuteDisabledBit | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfIntelVirtualizationTechnology | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfDirectCacheAccess | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfProcessorCState | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfProcessorC1E | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfProcessorC3Report | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfProcessorC6Report | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfProcessorC7Report | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfCPUPerformance | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfMaxVariableMTRRSetting | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosIntelDirectedIO | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfSelectMemoryRASConfiguration | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosNUMA | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosLvDdrMode | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfUSBBootConfig | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfUSBFrontPanelAccessLock | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfUSBSystemIdlePowerOptimizingSetting | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfMaximumMemoryBelow4GB | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfMemoryMappedIOAbove4GB | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfBootOptionRetry | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfIntelEntrySASRAIDModule | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"
	$Global:TMP_OUTPUT += Get-ImcBiosPolicy | Where-Object {$_.Name -ne "SRIOV"}  | Get-ImcBiosVfOSBootWatchdogTimer | Sort-Object Dn | Select-Object Dn,Vp* | ConvertTo-Html -Fragment
	AddToOutput -txt "<br />"

	# Get Service Profiles vNIC/vHBA Assignments
	AddToOutput -txt "<h2>Service Profile vNIC Placements</h2>"
	$Global:TMP_OUTPUT += Get-ImcLsVConAssign -Transport ethernet | Select-Object Dn,Vnicname,Adminvcon,Order | Sort-Object Dn | ConvertTo-Html -Fragment

	# Get Ethernet VLAN to vNIC Mappings #
	AddToOutput -txt "<h2>Ethernet VLAN to vNIC Mappings</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorVlan | sort-object Dn |Select-Object Dn,Name,Id,SwitchId | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='server-config-tab-pools'>"

	# Get UUID Suffix Pools
	AddToOutput -txt "<h2>UUID Pools</h2>"
	$Global:TMP_OUTPUT += Get-ImcUuidSuffixPool | Select-Object Dn,Name,AssignmentOrder,Prefix,Size,Assigned | ConvertTo-Html -Fragment

	# Get UUID Suffix Pool Blocks
	AddToOutput -txt "<h2>UUID Pool Blocks</h2>"
	$Global:TMP_OUTPUT += Get-ImcUuidSuffixBlock | Select-Object Dn,From,To | ConvertTo-Html -Fragment

	# Get UUID UUID Pool Assignments
	AddToOutput -txt "<h2>UUID Pool Assignments</h2>"
	$Global:TMP_OUTPUT += Get-ImcUuidpoolAddr | Where-Object {$_.Assigned -ne "no"} | select-object AssignedToDn,Id | sort-object -property AssignedToDn | ConvertTo-Html -Fragment

	# Get Server Pools
	AddToOutput -txt "<h2>Server Pools</h2>"
	$Global:TMP_OUTPUT += Get-ImcServerPool | Select-Object Dn,Name,Assigned | ConvertTo-Html -Fragment

	# Get Server Pool Assignments
	AddToOutput -txt "<h2>Server Pool Assignments</h2>"
	$Global:TMP_OUTPUT += Get-ImcComputePooledSlot | Select-Object Dn,Rn | ConvertTo-Html -Fragment
	$Global:TMP_OUTPUT += "<br />"
	$Global:TMP_OUTPUT += Get-ImcComputePooledRackUnit | Select-Object Dn,PoolableDn | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs container
	AddToOutput -txt "</div>" # end tab service configuration

	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################    LAN CONFIGURATION    ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='lan-config'>"

	AddToOutput -txt "<div id='lan-config-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#lan-config-tab-lan'>LAN</a></li>"
	AddToOutput -txt "<li><a href='#lan-config-tab-policies'>Policies</a></li>"
	AddToOutput -txt "<li><a href='#lan-config-tab-pools'>Pools</a></li>"
	AddToOutput -txt "</ul>"

	AddToOutput -txt "<div class='content-sub' id='lan-config-tab-lan'>"

	# Get LAN Switching Mode
	AddToOutput -txt "<h2>Fabric Interconnect Ethernet Switching Mode</h2>"
	$Global:TMP_OUTPUT += Get-ImcLanCloud | Select-Object Rn,Mode | ConvertTo-Html -Fragment

	# Get Fabric Interconnect Ethernet port usage and role info
	AddToOutput -txt "<h2>Fabric Interconnect Ethernet Port Configuration</h2>"
	$Global:TMP_OUTPUT += Get-ImcFabricPort | Select-Object Dn,IfRole,LicState,Mode,OperState,OperSpeed,XcvrType | Where-Object {$_.OperState -eq "up"} | ConvertTo-Html -Fragment

	# Get Ethernet LAN Uplink Port Channel info
	AddToOutput -txt "<h2>Fabric Interconnect Ethernet Uplink Port Channels</h2>"
	$Global:TMP_OUTPUT += Get-ImcUplinkPortChannel | Sort-Object -Property Name | Select-Object Dn,Name,OperSpeed,OperState,Transport | ConvertTo-Html -Fragment

	# Get Ethernet LAN Uplink Port Channel port membership info
	AddToOutput -txt "<h2>Fabric Interconnect Ethernet Uplink Port Channel Members</h2>"
	$Global:TMP_OUTPUT += Get-ImcUplinkPortChannelMember | Sort-Object -Property Dn |Select-Object Dn,Membership | ConvertTo-Html -Fragment

	# Get QoS Class Configuration
	AddToOutput -txt "<h2>QoS System Class Configuration</h2>"
	$Global:TMP_OUTPUT += Get-ImcQosClass | Select-Object Priority,AdminState,Cos,Weight,Drop,Mtu | ConvertTo-Html -Fragment

	# Get QoS Policies
	AddToOutput -txt "<h2>QoS Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcQosPolicy | Select-Object Dn,Name | ConvertTo-Html -Fragment

	# Get QoS vNIC Policy Map
	AddToOutput -txt "<h2>QoS vNIC Policy Map</h2>"
	$Global:TMP_OUTPUT += Get-ImcVnicEgressPolicy | Sort-Object -Property Prio | Select-Object Dn,Prio | ConvertTo-Html -Fragment

	# Get Ethernet VLANs
	AddToOutput -txt "<h2>Ethernet VLANs</h2>"
	$Global:TMP_OUTPUT += Get-ImcVlan | Where-Object {$_.IfRole -eq "network"} | Sort-Object -Property Id | Select-Object Id,Name,SwitchId | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='lan-config-tab-policies'>"

	# Get Network Control Policies
	AddToOutput -txt "<h2>Network Control Policies</h2>"
	$Global:TMP_OUTPUT += Get-ImcNetworkControlPolicy | Select-Object Dn,Name,Cdp,UplinkFailAction | ConvertTo-Html -Fragment

	# Get vNIC Templates
	$vnicTemplates = Get-ImcVnicTemplate | Select-Object Dn,Name,Descr,SwitchId,TemplType,IdentPoolName,Mtu,NwCtrlPolicyName,QosPolicyName
	AddToOutput -txt "<h2>vNIC Templates</h2>"
	$Global:TMP_OUTPUT += $vnicTemplates | ConvertTo-Html -Fragment

	# Get Ethernet VLAN to vNIC Mappings #
	AddToOutput -txt "<h2>Ethernet VLAN to vNIC Mappings</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorVlan | sort-object Dn |Select-Object Dn,Name,Id,SwitchId | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='lan-config-tab-pools'>"

	# Get IP Pools
	AddToOutput -txt "<h2>IP Pools</h2>"
	$Global:TMP_OUTPUT += Get-ImcIpPool | Select-Object Dn,Name,AssignmentOrder,Size | ConvertTo-Html -Fragment

	# Get IP Pool Blocks
	AddToOutput -txt "<h2>IP Pool Blocks</h2>"
	$Global:TMP_OUTPUT += Get-ImcIpPoolBlock | Select-Object Dn,From,To,Subnet,DefGw | ConvertTo-Html -Fragment

	# Get IP CIMC MGMT Pool Assignments
	AddToOutput -txt "<h2>CIMC IP Pool Assignments</h2>"
	$Global:TMP_OUTPUT += Get-ImcIpPoolAddr | Sort-Object -Property AssignedToDn | Where-Object {$_.Assigned -eq "yes"} | Select-Object AssignedToDn,Id | ConvertTo-Html -Fragment

	# Get MAC Address Pools
	AddToOutput -txt "<h2>MAC Address Pools</h2>"
	$Global:TMP_OUTPUT += Get-ImcMacPool | Select-Object Dn,Name,AssignmentOrder,Size,Assigned | ConvertTo-Html -Fragment

	# Get MAC Address Pool Blocks
	AddToOutput -txt "<h2>MAC Address Pool Blocks</h2>"
	$Global:TMP_OUTPUT += Get-ImcMacMemberBlock | Select-Object Dn,From,To | ConvertTo-Html -Fragment

	# Get MAC Pool Assignments
	AddToOutput -txt "<h2>MAC Address Pool Assignments</h2>"
	$Global:TMP_OUTPUT += Get-ImcVnic | Sort-Object -Property Dn | Select-Object Dn,IdentPoolName,Addr | Where-Object {$_.Addr -ne "derived"} | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs containers
	AddToOutput -txt "</div>" # end tab LAN configuration

	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################    SAN CONFIGURATION    ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='san-config'>"

	AddToOutput -txt "<div id='san-config-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#san-config-tab-san'>SAN</a></li>"
	AddToOutput -txt "<li><a href='#san-config-tab-policies'>Policies</a></li>"
	AddToOutput -txt "<li><a href='#san-config-tab-pools'>Pools</a></li>"
	AddToOutput -txt "</ul>"

	AddToOutput -txt "<div class='content-sub' id='san-config-tab-san'>"

	# Get SAN Switching Mode
	AddToOutput -txt "<h2>Fabric Interconnect Fibre Channel Switching Mode</h2>"
	$Global:TMP_OUTPUT += Get-ImcSanCloud | Select-Object Rn,Mode | ConvertTo-Html -Fragment

	# Get Fabric Interconnect FC Uplink Ports
	AddToOutput -txt "<h2>Fabric Interconnect FC Uplink Ports</h2>"
	$Global:TMP_OUTPUT += Get-ImcFiFcPort | Select-Object EpDn,SwitchId,SlotId,PortId,LicState,Mode,OperSpeed,OperState,wwn | sort-object -descending  | where-object {$_.OperState -ne "sfp-not-present"} | ConvertTo-Html -Fragment

	# Get SAN Fiber Channel Uplink Port Channel info
	AddToOutput -txt "<h2>Fabric Interconnect FC Uplink Port Channels</h2>"
	$Global:TMP_OUTPUT += Get-ImcFcUplinkPortChannel | Select-Object Dn,Name,OperSpeed,OperState,Transport | ConvertTo-Html -Fragment

	# Get Fabric Interconnect FCoE Uplink Ports
	AddToOutput -txt "<h2>Fabric Interconnect FCoE Uplink Ports</h2>"
	$Global:TMP_OUTPUT += Get-ImcFabricPort | Where-Object {$_.IfRole -eq "fcoe-uplink"} | Select-Object IfRole,EpDn,LicState,OperState,OperSpeed | ConvertTo-Html -Fragment

	# Get SAN FCoE Uplink Port Channel info
	AddToOutput -txt "<h2>Fabric Interconnect FCoE Uplink Port Channels</h2>"
	$Global:TMP_OUTPUT += Get-ImcFabricFcoeSanPc | Select-Object Dn,Name,FcoeState,OperState,Transport,Type | ConvertTo-Html -Fragment

	# Get SAN FCoE Uplink Port Channel Members
	AddToOutput -txt "<h2>Fabric Interconnect FCoE Uplink Port Channel Members</h2>"
	$Global:TMP_OUTPUT += Get-ImcFabricFcoeSanPcEp | Select-Object Dn,IfRole,LicState,Membership,OperState,SwitchId,PortId,Type | ConvertTo-Html -Fragment

	# Get FC VSAN info
	AddToOutput -txt "<h2>FC VSANs</h2>"
	$Global:TMP_OUTPUT += Get-ImcVsan | Select-Object Dn,Id,FcoeVlan,DefaultZoning | ConvertTo-Html -Fragment

	# Get FC Port Channel VSAN Mapping
	AddToOutput -txt "<h2>FC VSAN to FC Port Mappings</h2>"
	$Global:TMP_OUTPUT += Get-ImcVsanMemberFcPortChannel | Select-Object EpDn,IfType | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='san-config-tab-policies'>"

	# Get vHBA Templates
	$vhbaTemplates = Get-ImcVhbaTemplate | Select-Object Dn,Name,Descr,SwitchId,TemplType,QosPolicyName
	AddToOutput -txt "<h2>vHBA Templates</h2>"
	$Global:TMP_OUTPUT += $vhbaTemplates | ConvertTo-Html -Fragment

	# Get Service Profiles vNIC/vHBA Assignments
	AddToOutput -txt "<h2>Service Profile vHBA Placements</h2>"
	$Global:TMP_OUTPUT += Get-ImcLsVConAssign -Transport fc | Select-Object Dn,Vnicname,Adminvcon,Order | Sort-Object dn | ConvertTo-Html -Fragment

	# Get vHBA to VSAN Mappings
	AddToOutput -txt "<h2>vHBA to VSAN Mappings</h2>"
	$Global:TMP_OUTPUT += Get-ImcVhbaInterface | Select-Object Dn,OperVnetName,Initiator | Where-Object {$_.Initiator -ne "00:00:00:00:00:00:00:00"} | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='san-config-tab-pools'>"

	# Get WWNN Pools
	AddToOutput -txt "<h2>WWN Pools</h2>"
	$Global:TMP_OUTPUT += Get-ImcWwnPool | Select-Object Dn,Name,AssignmentOrder,Purpose,Size,Assigned | ConvertTo-Html -Fragment

	# Get WWNN/WWPN Pool Assignments
	AddToOutput -txt "<h2>WWN Pool Assignments</h2>"
	$Global:TMP_OUTPUT += Get-ImcVhba | Sort-Object -Property Addr | Select-Object Dn,IdentPoolName,NodeAddr,Addr | Where-Object {$_.NodeAddr -ne "vnic-derived"} | ConvertTo-Html -Fragment

	# Get WWNN/WWPN vHBA and adaptor Assignments
	AddToOutput -txt "<h2>vHBA Details</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorHostFcIf | sort-object -Property VnicDn -Descending | Select-Object VnicDn,Vendor,Model,LinkState,SwitchId,NodeWwn,Wwn | Where-Object {$_.NodeWwn -ne "00:00:00:00:00:00:00:00"} | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs containers
	AddToOutput -txt "</div>" # end tab SAN configuration


	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################   ADMIN CONFIGURATION   ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################


	AddToOutput -txt "<div class='content' id='admin-config'>"

	AddToOutput -txt "<div id='admin-config-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#admin-config-tab-general'>General Settings</a></li>"
	AddToOutput -txt "<li><a href='#admin-config-tab-user'>User Management</a></li>"
	AddToOutput -txt "<li><a href='#admin-config-tab-comm'>Communication Management</a></li>"
	AddToOutput -txt "<li><a href='#admin-config-tab-license'>Licensing</a></li>"
	AddToOutput -txt "</ul>"

	AddToOutput -txt "<div class='content-sub' id='admin-config-tab-general'>"

	# Get Organizations
	AddToOutput -txt "<h2>Organizations</h2>"
	$Global:TMP_OUTPUT += Get-ImcOrg | Select-Object Name,Dn | ConvertTo-Html -Fragment

	# Get Fault Policy
	AddToOutput -txt "<h2>Fault Policy</h2>"
	$Global:TMP_OUTPUT += Get-ImcFaultPolicy | Select-Object Rn,AckAction,ClearAction,ClearInterval,FlapInterval,RetentionInterval | ConvertTo-Html -Fragment

	# Get Syslog Remote Destinations
	AddToOutput -txt "<h2>Remote Syslog</h2>"
	$Global:TMP_OUTPUT += Get-ImcSyslogClient | Where-Object {$_.AdminState -ne "disabled"} | Select-Object Rn,Severity,Hostname,ForwardingFacility | ConvertTo-Html -Fragment

	# Get Syslog Sources
	AddToOutput -txt "<h2>Syslog Sources</h2>"
	$Global:TMP_OUTPUT += Get-ImcSyslogSource | Select-Object Rn,Audits,Events,Faults | ConvertTo-Html -Fragment

	# Get Syslog Local File
	AddToOutput -txt "<h2>Syslog Local File</h2>"
	$Global:TMP_OUTPUT += Get-ImcSyslogFile | Select-Object Rn,Name,AdminState,Severity,Size | ConvertTo-Html -Fragment

	# Get Full State Backup Policy
	AddToOutput -txt "<h2>Full State Backup Policy</h2>"
	$Global:TMP_OUTPUT += Get-ImcMgmtBackupPolicy | Select-Object Descr,Host,LastBackup,Proto,Schedule,AdminState | ConvertTo-Html -Fragment

	# Get All Config Backup Policy
	AddToOutput -txt "<h2>All Configuration Backup Policy</h2>"
	$Global:TMP_OUTPUT += Get-ImcMgmtCfgExportPolicy | Select-Object Descr,Host,LastBackup,Proto,Schedule,AdminState | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>"
	AddToOutput -txt "<div class='content-sub' id='admin-config-tab-user'>"

	# Get Native Authentication Source
	AddToOutput -txt "<h2>Native Authentication</h2>"
	$Global:TMP_OUTPUT += Get-ImcNativeAuth | Select-Object Rn,DefLogin,ConLogin,DefRolePolicy | ConvertTo-Html -Fragment

	# Get local users
	AddToOutput -txt "<h2>Local users</h2>"
	$Global:TMP_OUTPUT += Get-ImcLocalUser | Sort-Object Name | Select-Object Name,Email,AccountStatus,Expiration,Expires,PwdLifeTime | ConvertTo-Html -Fragment

	# Get LDAP server info
	AddToOutput -txt "<h2>LDAP Providers</h2>"
	$Global:TMP_OUTPUT += Get-ImcLdapProvider | Select-Object Name,Rootdn,Basedn,Attribute | ConvertTo-Html -Fragment

	# Get LDAP group mappings
	AddToOutput -txt "<h2>LDAP Group Mappings</h2>"
	$Global:TMP_OUTPUT += Get-ImcLdapGroupMap | Select-Object Name | ConvertTo-Html -Fragment

	# Get user and LDAP group roles
	AddToOutput -txt "<h2>LDAP User Roles</h2>"
	$Global:TMP_OUTPUT += Get-ImcUserRole | Select-Object Name,Dn | Where-Object {$_.Dn -like "sys/ldap-ext*"} | ConvertTo-Html -Fragment

	# Get tacacs providers
	AddToOutput -txt "<h2>TACACS+ Providers</h2>"
	$Global:TMP_OUTPUT += Get-ImcTacacsProvider | Sort-Object -Property Order,Name | Select-Object Order,Name,Port,KeySet,Retries,Timeout | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>"
	AddToOutput -txt "<div class='content-sub' id='admin-config-tab-comm'>"

	# Get Call Home config
	$callHome = Get-ImcCallhome
	AddToOutput -txt "<h2>Call Home Configuration</h2>"
	$Global:TMP_OUTPUT += $callHome | Sort-Object -Property Imc | Select-Object AdminState | ConvertTo-Html -Fragment

	# Get Call Home SMTP Server
	AddToOutput -txt "<h2>Call Home SMTP Server</h2>"
	$Global:TMP_OUTPUT += Get-ImcCallhomeSmtp | Sort-Object -Property Imc | Select-Object Host | ConvertTo-Html -Fragment

	# Get Call Home Recipients
	AddToOutput -txt "<h2>Call Home Recipients</h2>"
	$Global:TMP_OUTPUT += Get-ImcCallhomeRecipient | Sort-Object -Property Imc | Select-Object Dn,Email | ConvertTo-Html -Fragment

	# Get SNMP Configuration
	AddToOutput -txt "<h2>SNMP Configuration</h2>"
	$Global:TMP_OUTPUT += Get-ImcSnmp | Sort-Object -Property Imc | Select-Object AdminState,Community,SysContact,SysLocation | ConvertTo-Html -Fragment

	# Get DNS Servers
	$dnsServers = Get-ImcDnsServer | Select-Object Name
	AddToOutput -txt "<h2>DNS Servers</h2>"
	$Global:TMP_OUTPUT += $dnsServers | ConvertTo-Html -Fragment

	# Get Timezone
	AddToOutput -txt "<h2>Timezone</h2>"
	$Global:TMP_OUTPUT += Get-ImcTimezone | Select-Object Timezone | ConvertTo-Html -Fragment

	# Get NTP Servers
	$ntpServers = Get-ImcNtpServer | Select-Object Name
	AddToOutput -txt "<h2>NTP Servers</h2>"
	$Global:TMP_OUTPUT += $ntpServers | ConvertTo-Html -Fragment

	# Get Cluster Configuration and State
	AddToOutput -txt "<h2>Cluster Configuration</h2>"
	$Global:TMP_OUTPUT += Get-ImcStatus | Select-Object Name,VirtualIpv4Address,HaConfiguration,HaReadiness,HaReady,FiALeadership,FiAOobIpv4Address,FiAOobIpv4DefaultGateway,FiAManagementServicesState,FiBLeadership,FiBOobIpv4Address,FiBOobIpv4DefaultGateway,FiBManagementServicesState | ConvertTo-Html -Fragment

	# Get Management Interface Monitoring Policy
	AddToOutput -txt "<h2>Management Interface Monitoring Policy</h2>"
	$Global:TMP_OUTPUT += Get-ImcMgmtInterfaceMonitorPolicy | Select-Object AdminState,EnableHAFailover,MonitorMechanism | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>"
	AddToOutput -txt "<div class='content-sub' id='admin-config-tab-license'>"

	# Get host-id information
	AddToOutput -txt "<h2>Fabric Interconnect HostIDs</h2>"
	$Global:TMP_OUTPUT += Get-ImcLicenseServerHostId | Sort-Object -Property Scope | Select-Object Scope,HostId | ConvertTo-Html -Fragment

	# Get installed license information
	$ImcLicenses = Get-ImcLicense
	AddToOutput -txt "<h2>Installed Licenses</h2>"
	$Global:TMP_OUTPUT += $ImcLicenses | Sort-Object -Property Scope,Feature | Select-Object Scope,Feature,Sku,AbsQuant,UsedQuant,GracePeriodUsed,OperState,PeerStatus | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs containers
	AddToOutput -txt "</div>" # end tab SAN configuration

	##########################################################################################################################################################
	##########################################################################################################################################################
	###################################################        STATISTICS       ##############################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='stats'>"
	AddToOutput -txt "<div id='stats-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#stats-tab-faults'>Faults</a></li>"
	AddToOutput -txt "<li><a href='#stats-tab-equip'>Equipment</a></li>"
	AddToOutput -txt "<li><a href='#stats-tab-eth'>Ethernet</a></li>"
	AddToOutput -txt "<li><a href='#stats-tab-fc'>Fiberchannel</a></li>"
	AddToOutput -txt "</ul>"
	AddToOutput -txt "<div class='content-sub' id='stats-tab-faults'>"

	# Get all Imc Faults sorted by severity
	AddToOutput -txt "<h2>Faults</h2>"
	$Global:TMP_OUTPUT += Get-ImcFault | Sort-Object -Property @{Expression = {$_.Severity}; Ascending = $true}, Created -Descending | Select-Object Severity,Created,Descr,dn | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='stats-tab-equip'>"

	# Get chassis power usage stats
	AddToOutput -txt "<br /><small>* Temperatures are in Celcius</small>"
	AddToOutput -txt "<h2>Chassis Power</h2>"
	$Global:TMP_OUTPUT += Get-ImcChassisStats | Select-Object Dn,InputPower,InputPowerAvg,InputPowerMax,InputPowerMin,OutputPower,OutputPowerAvg,OutputPowerMax,OutputPowerMin,Suspect | ConvertTo-Html -Fragment

	# Get chassis and FI power status
	AddToOutput -txt "<h2>Chassis and Fabric Interconnect Power Supply Status</h2>"
	$Global:TMP_OUTPUT += Get-ImcPsu | Sort-Object -Property Dn | Select-Object Dn,OperState,Perf,Power,Thermal,Voltage | ConvertTo-Html -Fragment

	# Get chassis PSU stats
	AddToOutput -txt "<h2>Chassis Power Supplies</h2>"
	$Global:TMP_OUTPUT += Get-ImcPsuStats | Sort-Object -Property Dn | Select-Object Dn,AmbientTemp,AmbientTempAvg,Input210v,Input210vAvg,Output12v,Output12vAvg,OutputCurrentAvg,OutputPowerAvg,Suspect | ConvertTo-Html -Fragment

	# Get chassis and FI fan stats
	AddToOutput -txt "<h2>Chassis and Fabric Interconnect Fan</h2>"
	$Global:TMP_OUTPUT += Get-ImcFan | Sort-Object -Property Dn | Select-Object Dn,Module,Id,Perf,Power,OperState,Thermal | ConvertTo-Html -Fragment

	# Get chassis IOM temp stats
	AddToOutput -txt "<h2>Chassis IOM Temperatures</h2>"
	$Global:TMP_OUTPUT += Get-ImcEquipmentIOCardStats | Sort-Object -Property Dn | Select-Object Dn,AmbientTemp,AmbientTempAvg,Temp,TempAvg,Suspect | ConvertTo-Html -Fragment

	# Get server power usage
	AddToOutput -txt "<h2>Server Power</h2>"
	$Global:TMP_OUTPUT += Get-ImcComputeMbPowerStats | Sort-Object -Property Dn | Select-Object Dn,ConsumedPower,ConsumedPowerAvg,ConsumedPowerMax,InputCurrent,InputCurrentAvg,InputVoltage,InputVoltageAvg,Suspect | ConvertTo-Html -Fragment

	# Get server temperatures
	AddToOutput -txt "<h2>Server Temperatures</h2>"
	$Global:TMP_OUTPUT += Get-ImcComputeMbTempStats | Sort-Object -Property Dn | Select-Object Dn,FmTempSenIo,FmTempSenIoAvg,FmTempSenIoMax,FmTempSenRear,FmTempSenRearAvg,FmTempSenRearMax,Suspect | ConvertTo-Html -Fragment

	# Get Memory temperatures
	AddToOutput -txt "<h2>Memory Temperatures</h2>"
	$Global:TMP_OUTPUT += Get-ImcMemoryUnitEnvStats | Sort-Object -Property Dn | Select-Object Dn,Temperature,TemperatureAvg,TemperatureMax,Suspect | ConvertTo-Html -Fragment

	# Get CPU power and temperatures
	AddToOutput -txt "<h2>CPU Power and Temperatures</h2>"
	$Global:TMP_OUTPUT += Get-ImcProcessorEnvStats | Sort-Object -Property Dn | Select-Object Dn,InputCurrent,InputCurrentAvg,InputCurrentMax,Temperature,TemperatureAvg,TemperatureMax,Suspect | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='stats-tab-eth'>"

	# Get LAN Uplink Port Channel Loss Stats
	AddToOutput -txt "<h2>LAN Uplink Port Channel Loss</h2>"
	$Global:TMP_OUTPUT += Get-ImcUplinkPortChannel | Get-ImcEtherLossStats | Sort-Object -Property Dn | Select-Object Dn,ExcessCollision,ExcessCollisionDeltaAvg,LateCollision,LateCollisionDeltaAvg,MultiCollision,MultiCollisionDeltaAvg,SingleCollision,SingleCollisionDeltaAvg | ConvertTo-Html -Fragment

	# Get LAN Uplink Port Channel Receive Stats
	AddToOutput -txt "<h2>LAN Uplink Port Channel Receive</h2>"
	$Global:TMP_OUTPUT += Get-ImcUplinkPortChannel | Get-ImcEtherRxStats | Sort-Object -Property Dn | Select-Object Dn,BroadcastPackets,BroadcastPacketsDeltaAvg,JumboPackets,JumboPacketsDeltaAvg,MulticastPackets,MulticastPacketsDeltaAvg,TotalBytes,TotalBytesDeltaAvg,TotalPackets,TotalPacketsDeltaAvg,Suspect | ConvertTo-Html -Fragment

	# Get LAN Uplink Port Channel Transmit Stats
	AddToOutput -txt "<h2>LAN Uplink Port Channel Transmit</h2>"
	$Global:TMP_OUTPUT += Get-ImcUplinkPortChannel | Get-ImcEtherTxStats | Sort-Object -Property Dn | Select-Object Dn,BroadcastPackets,BroadcastPacketsDeltaAvg,JumboPackets,JumboPacketsDeltaAvg,MulticastPackets,MulticastPacketsDeltaAvg,TotalBytes,TotalBytesDeltaAvg,TotalPackets,TotalPacketsDeltaAvg,Suspect | ConvertTo-Html -Fragment

	# Get vNIC Stats
	AddToOutput -txt "<h2>vNICs</h2>"
	$Global:TMP_OUTPUT += Get-ImcAdaptorVnicStats | Sort-Object -Property Dn | Select-Object Dn,BytesRx,BytesRxDeltaAvg,BytesTx,BytesTxDeltaAvg,PacketsRx,PacketsRxDeltaAvg,PacketsTx,PacketsTxDeltaAvg,DroppedRx,DroppedRxDeltaAvg,DroppedTx,DroppedTxDeltaAvg,ErrorsTx,ErrorsTxDeltaAvg,Suspect | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "<div class='content-sub' id='stats-tab-fc'>"

	# Get FC Uplink Port Channel Loss Stats
	AddToOutput -txt "<h2>FC Uplink Ports</h2>"
	$Global:TMP_OUTPUT += Get-ImcFcErrStats | Sort-Object -Property Dn | Select-Object Dn,CrcRx,CrcRxDeltaAvg,DiscardRx,DiscardRxDeltaAvg,DiscardTx,DiscardTxDeltaAvg,LinkFailures,SignalLosses,Suspect | ConvertTo-Html -Fragment

	# Get FCoE Uplink Port Channel Stats
	AddToOutput -txt "<h2>FCoE Uplink Port Channels</h2>"
	$Global:TMP_OUTPUT += Get-ImcEtherFcoeInterfaceStats | Select-Object DN,BytesRx,BytesTx,DroppedRx,DroppedTx,ErrorsRx,ErrorsTx | ConvertTo-Html -Fragment

	AddToOutput -txt "</div>" # end subtab
	AddToOutput -txt "</div>" # end subtabs containers
	AddToOutput -txt "</div>" # end tab SAN configuration


	##########################################################################################################################################################
	##########################################################################################################################################################
	#################################################        RECOMMENDATIONS       ###########################################################################
	##########################################################################################################################################################
	##########################################################################################################################################################

	AddToOutput -txt "<div class='content' id='recommendations'>"
	AddToOutput -txt "<div id='recommendations-tabs'>"
	AddToOutput -txt "<ul>"
	AddToOutput -txt "<li><a href='#recommendations-tab'>Recommendations</a></li>"
	AddToOutput -txt "</ul>"
	AddToOutput -txt "<div class='content-sub' id='recommendations-tab'>"

	AddToOutput -txt "<h2>Recommendations</h2>"

	AddToOutput -txt "<table>"
	AddToOutput -txt "<tr><th>Recommendation</th><th>Status</th></tr>"



	# DNS servers defined?
	$recommendationText = "Are there DNS server(s) configured?"
	if($dnsServers.count -eq 0) {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}

	# NTP servers defined?
	$recommendationText = "Are there NTP server(s) configured?"
	if($ntpServers.count -eq 0) {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}

	# Telnet disabled?
	$recommendationText = "Is telnet disabled?"
	$telnet = Get-ImcTelnet
	if($telnet.AdminState -eq "enabled") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}

	# call home configured?
	$recommendationText = "Call Home configured?"
	if($callHome.AdminState -eq "off") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}

	# License check
	$licenseFabricA_Abs  = 0
	$licenseFabricB_Abs  = 0
	$licenseFabricA_Used = 0
	$licenseFabricB_Used = 0

	foreach ($lic in $ImcLicenses) {
		if($lic.Scope -eq "A") {
			$licenseFabricA_Abs += $lic.AbsQuant
			$licenseFabricA_Used += $lic.UsedQuant
		}
		if($lic.Scope -eq "B") {
			$licenseFabricB_Abs += $lic.AbsQuant
			$licenseFabricB_Used += $lic.UsedQuant
		}
	}

	$recommendationText = "Port licenses on Fabric A are sufficient?"
	if($licenseFabricA_Abs -ge $licenseFabricA_Used) {
		$licenseFabricA_Abs -= $licenseFabricA_Used
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes ($licenseFabricA_Abs left)</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}

	$recommendationText = "Port licenses on Fabric B are sufficient?"
	if($licenseFabricB_Abs -ge $licenseFabricB_Used) {
		$licenseFabricB_Abs -= $licenseFabricB_Used
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes ($licenseFabricB_Abs left)</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}

	# Discovery policy = port-channel?
	$recommendationText = "Configure server (fabric) links as port-channels"
	if($chassisDiscoveryPolicy.LinkAggregationPref -eq "port-channel") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}

	# Uplink port-channels present?
	$portchannelFabricA = "false"
	$portchannelFabricB = "false"
	$uplinkPortChannels = Get-ImcUplinkPortChannel
	foreach($pc in $uplinkPortChannels)
	{
		if($pc.SwitchId -eq "A") {
			$portchannelFabricA = "true"
		}
		if($pc.SwitchId -eq "B") {
			$portchannelFabricB = "true"
		}
	}

	$recommendationText = "Configure network uplinks as port-channels (Fabric A)"
	if($portchannelFabricA -eq "false") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}
	$recommendationText = "Configure network uplinks as port-channels (Fabric B)"
	if($portchannelFabricB -eq "false") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}

	# chassis redundancy policy
	$recommendationText = "Chassis power redundancy?"
	$chred = $chassisPowerRedPolicy.Redundancy
	if($chassisPowerRedPolicy.Redundancy -eq "non-redundant") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes ($chred)</td></tr>"
	}

	# Maintenance policy check
	$maintProfilesImmediate = [System.Collections.ArrayList]@()
	$maintProfiles = Get-ImcMaintenancePolicy | Where-Object {$_.UptimeDisr -eq "immediate"} | Select-Object Name
	foreach($prof in $maintProfiles) {
		$maintProfilesImmediate += $prof.Name
	}

	$totalSPsImmediate = 0
	$totalSPsImmediateProfiles = [System.Collections.ArrayList]@()
	$maintServiceProfiles = Get-ImcServiceProfile | Where-Object {$_.AssocState -eq "associated"} | Select-Object Rn, MaintPolicyName
	foreach($profile in $maintServiceProfiles)
	{
		if($maintProfilesImmediate -contains $profile.MaintPolicyName) {
			$totalSPsImmediate++
			$totalSPsImmediateProfiles += $profile.Rn
		}
	}
	$recommendationText = "Configure the maintenance policies to 'User Acknowledge'"
	if($totalSPsImmediate -eq 0) {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No ($totalSPsImmediateProfiles)</td></tr>"
	}

	# Check for vNIC Templates which are not updating templates
	$nonUpdatingvNICs = [System.Collections.ArrayList]@()
	$nonUpdatingFound = "false"
	foreach($vnictmpl in $vnicTemplates)
	{
		if($vnictmpl.TemplType -ne "updating-template") {
			$nonUpdatingFound = "true"
			$nonUpdatingvNICs += $vnictmpl.Name
		}
	}
	$recommendationText = "Configure vNIC templates as 'Updating'"
	if($nonUpdatingFound -eq "false") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No ($nonUpdatingvNICs)</td></tr>"
	}

	# Check for vHBA Templates which are not updating templates
	$nonUpdatingvHBAs = [System.Collections.ArrayList]@()
	$nonUpdatingFound = "false"
	foreach($vhbatmpl in $vhbaTemplates)
	{
		if($vhbatmpl.TemplType -ne "updating-template") {
			$nonUpdatingFound = "true"
			$nonUpdatingvHBAs += $vhbatmpl.Name
		}
	}
	$recommendationText = "Configure vHBA templates as 'Updating'"
	if($nonUpdatingFound -eq "false") {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: green'>Yes</td></tr>"
	}
	else {
		AddToOutput -txt "<tr><td>$recommendationText</td><td style='background-color: red'>No ($nonUpdatingvHBAs)</td></tr>"
	}


	AddToOutput -txt "</table>" # end recommendations table

	AddToOutput -txt "</div>" # end subtabs
	AddToOutput -txt "</div>" # end subtabs container
	AddToOutput -txt "</div>" # end recommendations tab


	AddToOutput -txt "</body>"
	AddToOutput -txt "</html>"

	$Global:TMP_OUTPUT | Out-File $OutFile

	# Open html file
	Invoke-Item $OutFile

	# Disconnect
	Disconnect-Imc

	# Send Email if required
	if ( $SendEmail ) 
	{ 
		$message = New-Object Net.Mail.MailMessage
		$attachment = New-Object Net.Mail.Attachment($OutFileObj)
		$smtp = New-Object Net.Mail.SmtpClient($smtpServer) 
		$message.From = $mailFrom
		$message.To.Add($mailTo) 
		$message.Subject = "Cisco IMC Inventory Script - $IMCName"
		$message.Body = "Cisco IMC Inventory Script, open the attached HTML file to view the report"
		$message.Attachments.Add($attachment) 
		$smtp.Send($message)
	}

	WriteLog "Done generating report for $IMC"
}
### END FUNCTION ###

WriteLog "Starting Cisco IMC Inventory Script (IIS).."

# If there's no CSVFile input, check for manual input parameters
if ($CSVFile -eq "")
{
	# Prompt for IMC IP and credentials
	if ($IMC -eq "") {
		$IMC = Read-Host "Hostname or IP address IMC"
	}
	# IMC is required
	if ($IMC -eq "") {
		WriteLog "Please specify the hostname or IP address of a IMC!"
		Exit
	}

	# Prompt for HTML report file output name and path
	if ($OutFile -eq "") {
		$OutFile = Read-Host "Enter file name for the HTML output file"
	}
	if ($OutFile -eq "") {
		WriteLog "Please specify output file!"
		Exit
	}

	GenerateReport $IMC $OutFile $Username $Password "manual"
}
else
{
	# Check if the CSVFile exists
	if (Test-Path $CSVFile)
	{
		# Run through the CSV file line for line and generate the report for each one
		$line = 0;
		Import-Csv $CSVFile | Foreach {
			$line++
			$IMC = $_."IMC IP"
			$OutFile = $_."Outfile"
			$Username = $_."Username"
			$Password = $_."Encrypted Password"

			# Check input values
			if ($IMC -eq "") {
				WriteLog "Line $line - IMC is empty!"
			}
			elseif ($Username -eq "") {
				WriteLog "Line $line - Username is empty!"
			}
			elseif ($Password -eq "") {
				WriteLog "Line $line - Password is empty!"
			}
			elseif ($OutFile -eq "") {
				WriteLog "Line $line - OutFile is empty!"
			}
			else
			{
				GenerateReport $IMC $OutFile $Username $Password "csv"
			}
		}
	}
	else
	{
		WriteLog "CSV File '$CSVFile' does not exist!"
		Exit
	}
}
