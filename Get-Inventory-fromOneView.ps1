## -------------------------------------------------------------------------------------------------------------
## 
##
##      Description: Collect information of BladeSystem from OneView
##
## DISCLAIMER
## The sample scripts are not supported under any HPE standard support program or service.
## The sample scripts are provided AS IS without warranty of any kind. 
## HPE further disclaims all implied warranties including, without limitation, any implied 
## warranties of merchantability or of fitness for a particular purpose. 
##
##    
## Scenario
##     	Use HP OneView to collect information about servers
##		
##
## Input parameters:
##         OVApplianceIP      : Address of OneView appliance
##         OVAdminName        : name of OneView administrator
##         OVAdminPassword    : password of OneView administrator
##         Enclosures         : List of enclosures
##         OneViewModule      ; OneView PS modules - Minimum is HPOneView 1.20
##
##
## History: 
##         Dec-2017 v1.0      - Add FW inventory for components of server hardware 
##                            - Add inventory of Spp ( Date applied to server)
##
## Contact: Dung.HoangKhac@hp.com


Param ( [string]$OVApplianceIP  =   "", 
        [string]$OVAdminName    =   "Administrator", 
        [string]$OVAdminPassword=   "",
        [string]$OneViewModule  = "HPOneView.310",  

        [string[]]$Enclosures   = "" 

       )


## -------------------------------------------------------------------------------------------------------------
##
##                     Function New-InventoryFiles
##
## -------------------------------------------------------------------------------------------------------------
Function New-InventoryFiles 
{

Param ([string]$Enclosure)


    # ---------------------------
    #  Generate Output files

    $TimeStamp = get-date -format MMMyyyy 

    $script:Fwfile  = "$Enclosure-FW-$TimeStamp.CSV"
    $script:Sppfile = "$Enclosure-Spp-$TimeStamp.CSV"
    $script:Srvfile = "$Enclosure-Servers-$TimeStamp.CSV"
    $script:SNPFile = "$Enclosure-Parts-$TimeStamp.CSV"
    $script:IPSFile = "$Enclosure-IPs-$TimeStamp.CSV"
    $script:ConFile = "$Enclosure-Connections-$TimeStamp.CSV"
    $script:UplFile = "$Enclosure-UpLinks-$TimeStamp.CSV"

    # ---Create header for Firmware CSV file
    $FirmwareCSV = New-Item $script:FwFile  -type file -force
    Set-content -Path $script:FwFile -Value "Location,Model,FW" 

    # ---Create header for SPP CSV file
    $SppCSV = New-Item $script:SppFile  -type file -force
    Set-content -Path $script:SppFile -Value "Fw Baseline,AppliedTo,InstallDate,InstallState"

    # ---Create header for Srv CSV file
    $SrvCSV = New-Item $script:SrvFile  -type file -force
    Set-content -Path $script:SrvFile -Value "Location,Server Model,CPU Type,CPU Count,CPU Cores,Memory(GB)"
    

    # ---Create header for Parts CSV file
    $SNPCSV = New-Item $script:SNPFile  -type file -force
    Set-content -Path $script:SNPFile -Value "Location,Device,S/N,Part Number,Spare Part Number" 


    # ---Create header for Memory CSV file
    $IPsCSV = New-Item $script:IPsFile  -type file -force
    Set-content -Path $script:IPsFile -Value "Location,Device,IP Address,FQDN"
                    

    # ---Create header for Connections CSV file
    $ConCSV = New-Item $script:ConFile  -type file -force
    Set-content -Path $script:ConFile -Value "Location,Type,Port,MAC,WWPN,WWNN,Network,Device,Model"

    # ---Create header for UpLink CSV file
    $UplCSV = New-Item $script:UplFile  -type file -force
    Set-content -Path $script:UplFile -Value "Location,PortName,RemotePortDescription,RemoteChassisID,RemoteMgmtAddress,RemoteSystemName,RemoteSystemDescription" 
     

}



# -------------------------------------------------------------------------------------------------------------
#
#                  Main Entry
#
#
# -------------------------------------------------------------------------------------------------------------
   
# -----------------------------------
#    Always reload module
   
$LoadedModule = get-module $OneviewModule
if ($LoadedModule -ne $NULL)
{
    remove-module $OneviewModule
}

import-module $OneViewModule

  

# ---------------------------
# Connect to OneView appliance

write-host "`n Connect to the OneView appliance..."
$global:ApplianceConnection = Connect-HPOVMgmt -appliance $OVApplianceIP -user $OVAdminName -password $OVAdminPassword

$SynergyAppliance = $global:ApplianceConnection.ApplianceType -eq 'Composer'

# ----------------------------
# Scan thru enclosures


$ListofEnclosures  = @()

if ($Enclosures)
{
    foreach ($encl in $Enclosures)
    {
        try 
        {
            $ListofEnclosures += get-HPOVEnclosure -name $encl            
        }
        catch 
        {
            write-host -foreground Yellow " Enclosure $encl does not exist. Skip it..."    
        }

    }
}
else 
{
    $ListofEnclosures = get-HPOVEnclosure    
}

Foreach ($ThisEnclosure in $ListofEnclosures)
{    
    # ---- Getting inventory
    #
    $AllSNParts        = @()
    $AllFW             = @()
    $AllSpp            = @()
    
    $AllIPs             = @()
    $AllConnections     = @()
    $AllUpLinks         = @()
    $AllServers         = @()
    $CurrentSpp         = ""

    # ---------------------------------
    # Enclosure


    $EnclName = $ThisEnclosure.Name
    write-host -ForegroundColor CYAN "`n Collecting information for enclosure --> $EnclName" 

    New-InventoryFiles -Enclosure $EnclName

    $Location     = $EnclName + "- "
    $Model        = $ThisEnclosure.EnclosureType
    $SerialNumber = $ThisEnclosure.serialNumber
    $PartNumber   = $ThisEnclosure.PartNumber
    $SparePart    = ""
   

    # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
    $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"


    # ---------------------------------
    # Device Bay

    $DeviceBays = $ThisEnclosure.DeviceBays
    foreach ( $uri in $ThisEnclosure.DeviceBays.deviceUri)
    {
        if (($uri -ne $NULL) -and ($uri.Startswith('/')) -and ($uri -like '*server-hardware*'))
        {
            $ThisBay    = Send-HPOVRequest -uri $Uri -Hostname $global:ApplianceConnection

            $OneViewProfileName = $ThisBay.name
            $BaySlot            = $ThisBay.position
            $spUri              = $ThisBay.ServerProfileUri
            
            if (($spUri -ne $NULL) -and ($spUri.Startswith('/')) )
            {
                $ThisProfile      = send-HPOVRequest -uri $spUri -Hostname $global:ApplianceConnection
                $FwBaselineUri    = $ThisProfile.firmware.firmwarebaselineUri
                $Connections      = $ThisProfile.Connections
                Foreach($ThisConnection in $Connections)
                {
                    $NetworkName = $ICName = $ICModel = ""

                    $netUri = $ThisConnection.networkuri                
                    if (($netUri -ne $NULL) -and ($netUri.Startswith('/')) )
                    {
                        $Thisnetwork = send-hpovRequest -uri $neturi -Hostname $global:ApplianceConnection
                        $NetworkName = $ThisNetwork.name
                    }

                    $IcUri = $ThisConnection.interconnecturi                
                    if (($IcUri -ne $NULL) -and ($IcUri.Startswith('/')) )
                    {
                        $ThisIC  = send-hpovRequest $IcUri
                        $ICName  = $ThisIC.name
                        $ICName  = $ICName.replace(',','-')
                        $ICModel = $ThisIC.Model
                    }
                    $Location       = $Enclname + "- Bay $BaySlot"
                    $Type           = $ThisConnection.FunctionType
                    $Port           = $ThisConnection.PortId
                    $MAC            = $ThisConnection.mac
                    $WWPN           = $ThisConnection.wwpn
                    $WWNN           = $ThisConnection.wwnn
                    $Network        = $NetworkName
                    $ConnectTo      = $ICName
                    $InterConnect   = $ICModel

                    #---------------- "Location,Type,Port,MAC,WWPN,WWNN,Network,Device,Model"
                    $AllConnections +="$Location,$Type,$Port,$MAC,$WWPN,$WWNN,$Network,$ConnectTo,$InterConnect" 
                }
            }

                    
        
            # --------------------------
            #   Collect IPs of iLO

            
            $Location     = $Enclname + "- Bay $BaySlot"
            $Device       = $ThisBay.mpModel
            
            $FQDN         = $ThisBay.mpHostInfo.mpHostName
            $mpaddr       = $ThisBay.mpHostInfo.mpIpAddresses
            if (($SynergyAppliance) -and $mpaddr )
            {
                $IP           = $mpaddr[1].address
            }
            else 
            {
                $IP           = $mpaddr[0].address    
            }
            

            # ---------"Location,Device,IP Address,FQDN"
            $AllIPs += "$Location,$Device,$IP,$FQDN"

            # --------------------------
            #   Collect Firmware: ROM and HW components
                            
            
            $Location = $Enclname+ "- Bay $BaySlot"
            $Model    = $ThisBay.shortModel
            $FW       = $ThisBay.romVersion
            $iLOModel = $ThisBay.mpModel
            $iLOFW    = $ThisBay.mpFirmwareVersion

            # ------- "Location,Model,FW" 
            $AllFW += "$Location,$Model,$FW"

            $Location = ""

            $FWInventoryUri = $ThisBay.serverFirmwareInventoryUri
            if ($FWInventoryUri)
            {
                $fwlist         = send-hpovRequest -uri $FWInventoryUri
                $fwComponents   = $fwlist.Components
                foreach ($fwcomponent in $fwComponents)
                {
                    $Model       = $fwComponent.componentName
                    $FW          = $fwComponent.componentVersion
                    $AllFW      += "$Location,$model,$FW"
                }
            }

            $AllFW   += ",,"    # Add a blank line

            # --------------------------
            #   Collect FW Baseline settings

            if ($FwBaselineUri)                # Get URi from Server profile
            {
                $ThisSpp            = Send-HPOVRequest -uri $FwBaselineUri
                $SppName            = $ThisSpp.baselineShortName
                $sppInstallState    = $ThisBay.serversettings.firmwareAndDriversInstallState
                $t                  = $sppInstallState.installedStateTimestamp
                if ($t)
                {
                    $sppInstallDate = ([DateTime]$t).DateTime -replace "," , "_"
                    $state          = ""
                }
                else 
                {
                    $sppInstallDate  = ""
                    $state           = $sppInstallState.installState
                }
            
                $Location           = $Enclname + "- Bay $BaySlot"
                if ($CurrentSpp -ne $SppName)
                {
                    $CurrentSpp = $SppName
                }
                else 
                {
                    $SppName    = ""   # Don't repeat Spp Name for each line                     
                }

                # "Fw Baseline,AppliedTo,InstallDate,InstallState" 
                $AllSpp             += "$SppName,$Location,$sppInstallDate,$state" 
            }


            # --------------------------
            #   Collect S/N and PArt Numbers of Servers


            $Location     = $Enclname + "- Bay $BaySlot"
            $Model        = $ThisBay.shortModel
            $SerialNumber = $ThisBay.serialNumber
            $PartNumber   = ""
            $SparePart    = ""

            # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
            $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"


            # --------------------------
            #   Collect S/N and PArt Numbers of iLO

            $Location     = $Enclname + "- Bay $BaySlot"
            $Model        = $ThisBay.mpModel
            $SerialNumber = ""
            $PartNumber   = $ThisBay.partNumber
            $SparePart    = ""

            # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
            $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"                
                            

            # --------------------------
            #   Collect Servers config

            
            $Location  = $Enclname + "- Bay $BaySlot";
            $Model     = $ThisBay.shortModel;
            $CPU       = $ThisBay.processorType;
            $CPUCount  = $ThisBay.processorCount;
            $Core      = $ThisBay.processorCoreCount;
            $Memory    = "$([int]($ThisBay.memoryMB) / 1KB) GB"

            # ------------"Location,Server Model,CPU Type,CPU Count,CPU Cores,Memory(GB)"                                                                                 
            $AllServers += "$Location,$Model,$CPU,$CPUCount,$Core,$Memory"                   
        }

    }

    # ---------------------------------------
    # FanBays
            
    foreach( $ThisFan in $ThisEnclosure.FanBays)
    {

            # --------------------------
            #   Collect S/N and PArt Numbers of Fans

            $Location     = $Enclname + "- Fan $($ThisFan.bayNumber)"
            $Model        = $ThisFan.model
            $SerialNumber = ""
            $PartNumber   = $ThisFan.partNumber
            $SparePart    = $ThisFan.sparepartNumber

            # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
            $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"
    }


    # ---------------------------------------
    # PowerSupply
            
    foreach( $ThisPDU in $ThisEnclosure.powerSupplyBays)
    {

            # --------------------------
            #   Collect S/N and PArt Numbers of PDUs

            $Location     = $Enclname + "- PDU $($ThisPDU.bayNumber)";
            $Model        = $ThisPDU.model;
            $SerialNumber = $ThisPDU.serialNumber;
            $PartNumber   = $ThisPDU.partNumber;
            $SparePart    = $ThisPDU.sparepartNumber

            # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
            $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"
    }

    
    # ---------------------------------------
    # Manager Bays ( OA or Composer)
    
    foreach( $ThisManager in $ThisEnclosure.ManagerBays)
    {
        $Bayslot = $ThisManager.bayNumber

        # --------------------------
        #   Collect firmware of Manager

        
        if ($SynergyAppliance)
        {
            $Location = $Enclname + "- Bay $Bayslot"
            $Device   = $ThisManager.Model
        }
        else 
        {
            $Location = $Enclname + "- OA $Bayslot"
            $Device   = "On-board Administrator"            
        }


        $fwbuild  = $ThisManager.fwBuilddate   -replace ',' , '-'
        $FW       = $ThisManager.fwVersion + ' ' + $fwBuild           

        # ------- "Location,Model,FW,iLOModel,iLOFW" 
        $AllFW += "$Location,$Device,$FW,,"

        # --------------------------
        #   Collect Manager IPs


        $IP           = $ThisManager.ipAddress
        $FQDN         = $ThisManager.fqdnHostName

        # ---------"Location,Device,IP Address,FQDN"
        $AllIPs += "$Location,$Device,$IP,$FQDN"

        # --------------------------
        #   Collect S/N and PArt Numbers 

        $SerialNumber = $ThisManager.serialNumber
        $PartNumber   = $ThisManager.partNumber
        $SparePart    = $ThisManager.sparepartNumber

        # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
        $AllSNParts +="$Location,$Device,$SerialNumber,$PartNumber,$SparePart"
    }

        
    # ---------------------------------------
    # Interconnects

    foreach ($uri in $ThisEnclosure.InterConnectBays.interconnecturi)
    {

        if (($uri -ne $NULL) -and ($uri.Startswith('/')) )
        {

            $ThisInterconnect = Send-HPOVRequest -uri $Uri -Hostname $global:ApplianceConnection

            # --------------------------
            #   Collect FW of Interconnect devices
            $ICName = $ThisInterconnect.name
            $ICName = $ICName -replace(',','-')

            $Location = $ICName
            $Model    = $ThisInterconnect.productname
            $FW       = $ThisInterconnect.firmwareVersion

            # ------- "Location,Model,FW,iLOModel,iLOFW" 
            $AllFW += "$Location,$Model,$FW,,"            

            # --------------------------
            #   Collect S/N and PArt Numbers of Interconnect Devices

            $Location     = $ICName
            $Model        = $ThisInterconnect.productname
            $SerialNumber = $ThisInterconnect.serialNumber
            $PartNumber   = "";
            $SparePart    = ""

            # ------------"Location,Device,S/N,Part Number,Spare Part Number" 
            $AllSNParts +="$Location,$Model,$SerialNumber,$PartNumber,$SparePart"

            # --------------------------
            #   Collect IPs of Interconnect Devices

            
            $Location     = $ICname;
            $Device       = $ThisInterconnect.productname;
            $IP           = $ThisInterconnect.interconnectIP;
            $FQDN         = ""
                

            # ---------"Location,Device,IP Address,FQDN"
            $AllIPs += "$Location,$Device,$IP,$FQDN"

            # --------------------------
            #   Collect Uplinks of Interconnect Devices

            #$ListofUpLinks  = $ThisInterconnect.Ports | where PortName -like 'Q*' | where PortStatus -eq 'Linked'
            $ListofUpLinks  = $ThisInterconnect.Ports  | where PortStatus -eq 'Linked'
            foreach ($UpLink in $ListofUplinks)
            {
                $PortName = $UPLink.PortName
                $neighbor = $Uplink.Neighbor

                $RemoteChassisID   = $neighbor.RemoteChassisID
                $RemoteMgmtAddress = $neighbor.RemoteMgmtAddress
                $RemotePortDescription = $neighbor.RemotePortDescription
                $remoteSystemName = $neighbor.remoteSystemName
                $RemoteSystemDescription = $neighbor.RemoteSystemDescription
                if (-not [string]::IsNullOrEmpty($RemoteSystemDescription))
                {
                    $RemoteSystemDescription = $RemoteSystemDescription.replace("`n","/").replace("`r","/").split('/')[0]
                    $RemoteSystemDescription = $RemoteSystemDescription.Replace(', ', '-')
                }

                $AllUpLinks += "$Location,$PortName,$RemotePortDescription,$RemoteChassisID,$RemoteMgmtAddress,$RemoteSystemName,$RemoteSystemDescription" 
            }
                
            
            $Location     = $ICname;
            $Model        = $ThisInterconnect.productname;
            $IP           = $ThisInterconnect.interconnectIP;
            $FQDN         = ""
        }


    }

    


    add-content -path $script:ConFile   -Value $AllConnections
    add-content -path $script:SNPFile   -Value $AllSNParts
    add-content -path $script:FWFile    -Value $AllFW
    add-content -path $script:SppFile    -Value $AllSpp
    add-content -path $script:IPSFile   -Value $AllIPs
    add-content -path $script:SrvFile   -Value $AllServers
    add-content -path $script:UplFile   -Value $AllUpLinks
   

}

Disconnect-HPOVMgmt
