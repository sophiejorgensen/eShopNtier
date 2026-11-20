targetScope = 'subscription'

param location string
param resourceGroupName string
param vmName string
param dnsLabel string
param adminUsername string
@secure()
param adminPassword string
param sourceAddress string
param vmSize string = 'Standard_D2as_v7'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    application: 'eShop'
    environment: 'poc'
  }
}

module sqlVm 'sqlserver-vm.bicep' = {
  name: '${vmName}-resources'
  scope: resourceGroup
  params: {
    location: location
    vmName: vmName
    dnsLabel: dnsLabel
    adminUsername: adminUsername
    adminPassword: adminPassword
    sourceAddress: sourceAddress
    vmSize: vmSize
  }
}

output vmName string = vmName
output sqlFqdn string = sqlVm.outputs.sqlFqdn
output publicIp string = sqlVm.outputs.publicIp
