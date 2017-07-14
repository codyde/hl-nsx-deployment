$TransitLsName = 'TransitLS'
$WebLsName = 'Web'
$AppLsName = 'Application'
$DbLsName = 'Database'
$MgmtLsName = 'Management'
$TransitLsName = "Transit"
$WebLsName = "Web"
$AppLsName = "App"
$DbLsName = "Db"
$MgmtLsName = "Mgmt"
$EdgeName = "Edge01"
$LdrName = "Dlr01"
$EdgeDatastoreName = "hl-block-ds01"
$EdgeClusterName = "Management"
$EdgeUplinkPrimaryAddress = "172.24.11.3"
$EdgeDefaultGW = "172.24.11.1"
$EdgeUplinkNetworkName = "NEI Uplink"
$EdgeInternalPrimaryAddress = "172.25.1.1"
$LdrUplinkPrimaryAddress = "172.25.1.2"
$LdrUplinkProtocolAddress = "172.25.1.3"
$LdrWebPrimaryAddress = "10.0.1.1"
$LdrAppPrimaryAddress = "10.0.2.1"
$LdrDbPrimaryAddress = "10.0.3.1"
$EdgeCluster = get-cluster $EdgeClusterName -errorAction Stop
$EdgeDatastore = get-datastore $EdgeDatastoreName -errorAction Stop
$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
$DefaultSubnetBits = "28"
$DefaultSubnetMask = "255.255.255.240"
$AppliancePassword = "VMware123!VMware123!"
$ESGOspfAreaId = "22"
$LDROspfAreaId = "23"


$TransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TransitLsName

$WebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $WebLsName
$AppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $AppLsName
$DbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $DbLsName
$MgmtLs = Get-NsxTransportZone | New-NsxLogicalSwitch $MgmtLsName

######################################
# EDGE

## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits
$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $EdgeInternalPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits 

## Deploy appliance with the defined uplinks
write-host -foregroundcolor "Green" "Creating Edge"
$Edge1 = New-NsxEdge -name $EdgeName -cluster $EdgeCluster -datastore $EdgeDataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwDefaultPolicyAllow

##Configure Edge DGW
Get-NSXEdge $EdgeName | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $EdgeDefaultGW -confirm:$false | out-null

Get-NsxEdge $EdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -DefaultGatewayVnic 0 -confirm:$false | out-null
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null
Get-NsxEdge $EdgeName | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 0 -confirm:$false | out-null
Get-NsxEdge $EdgeName | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution -confirm:$false | out-null
Get-NsxEdge $EdgeName | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner ospf -FromConnected -Action permit -confirm:$false

######################################

# DLR 

$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits
$Ldr = New-NsxLogicalRouter -name $LdrName -ManagementPortGroup $MgmtLs -interface $LdrvNic0 -cluster $EdgeCluster -datastore $EdgeDataStore
## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
write-host -foregroundcolor Green "Adding Web LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $WebLsName  -ConnectedTo $WebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding App LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $AppLsName  -ConnectedTo $AppLs -PrimaryAddress $LdrAppPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding DB LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $DbLsName  -ConnectedTo $DbLs -PrimaryAddress $LdrDbPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $LdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null

# OSPF 

Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LdrUplinkPrimaryAddress -ProtocolAddress $LdrUplinkProtocolAddress -ForwardingAddress $LdrUplinkPrimaryAddress  -confirm:$false | out-null
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 0 | Remove-NsxLogicalRouterOspfArea -confirm:$false
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $LDROspfAreaId -Type normal -confirm:$false | out-null
$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $LDROspfAreaId -vNic $LdrTransitInt.index -confirm:$false | out-null

Get-NsxEdge $LdrName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $LDROspfAreaId -vNic 1 -confirm:$false | out-null
