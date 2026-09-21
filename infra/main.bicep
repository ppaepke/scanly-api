// ─────────────────────────────────────────────────────────────
// main.bicep — Infrastruktur för Scanly API
// Deployas in i befintlig delad resursgrupp (inga nya RG:er tillåtna)
// ─────────────────────────────────────────────────────────────

// PARAMETRAR — värden som matas in utifrån vid deployment.
// Här: hämtar automatiskt regionen från resursgruppen, så vi
// slipper hårdkoda "swedencentral" i filen.
param location string = resourceGroup().location

// Genererar en unik men deterministisk sträng baserad på
// resursgruppens ID. Samma RG → alltid samma sträng.
// Olika studenters RG → olika sträng → inga namnkrockar.
param uniqueSuffix string = uniqueString(resourceGroup().id)

// VARIABLER — beräknas internt i filen, matas inte in utifrån.
// Bygger ihop ett bas-namn + det unika suffixet till fulla resursnamn.
var acrName = 'scanlyacr${uniqueSuffix}'
var storageName = 'scanlystg${uniqueSuffix}'
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param targetPort int = 8080

// ─────────────────────────────────────────────────────────────
// RESURS 1: Azure Container Registry (ACR)
// Här lagras Docker-imagen som pipelinen bygger och Container App hämtar.
// ─────────────────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName                // Faktiska namnet i Azure
  location: location
  sku: {
    name: 'Basic'               // Billigaste nivån
  }
  properties: {
    adminUserEnabled: false     // Säkerhetsval: ingen delad admin-nyckel,
                                 // endast Managed Identity ska få åtkomst
  }
}

// ─────────────────────────────────────────────────────────────
// RESURS 2: Storage Account
// Här sparas ett JSON-dokument per analyserad faktura (blob storage).
// ─────────────────────────────────────────────────────────────
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName             // OBS: bara gemener/siffror, max 24 tecken
  location: location
  sku: {
    name: 'Standard_LRS'        // Billigaste redundans-nivån (lokalt replikerad)
  }
  kind: 'StorageV2'              // Standardvalet idag, stödjer blob/fil/kö
  properties: {
    minimumTlsVersion: 'TLS1_2'      // Säkerhetsval: blockera gamla, osäkra TLS-versioner
    allowBlobPublicAccess: false     // Säkerhetsval: ingen publik läsning,
                                      // åtkomst enbart via Managed Identity
  }
}


// ─────────────────────────────────────────────────────────────
// RESURS 2b: Blob-container "invoices" (nästlad under Storage Account)
// Program.cs sparar ett JSON-dokument per faktura hit.
// ─────────────────────────────────────────────────────────────
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage               // "hänger under" storage-resursen ovan
  name: 'default'                // Azure kräver alltid namnet 'default' här
}

resource invoicesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService            // hänger i sin tur under blobService
  name: 'invoices'                // matchar exakt "invoices" i Program.cs
  properties: {
    publicAccess: 'None'         // ingen publik läsning, samma säkerhetslinje som förut
  }
}


// ─────────────────────────────────────────────────────────────
// RESURS 3: Log Analytics Workspace
// Container Apps Environment kräver denna för loggning/metrics.
// ─────────────────────────────────────────────────────────────
var logAnalyticsName = 'scanly-logs-${uniqueSuffix}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ─────────────────────────────────────────────────────────────
// RESURS 4: Container Apps Environment
// "Huset" som Container App (rummet) placeras inuti.
// ─────────────────────────────────────────────────────────────
var envName = 'scanly-env-${uniqueSuffix}'

resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}


// ─────────────────────────────────────────────────────────────
// RESURS 5: Container App
// "Rummet" — själva Scanly-appen, körs inuti environment ovan.
// Pekar initialt på en platshållar-image; pipelinen uppdaterar senare.
// ─────────────────────────────────────────────────────────────
var containerAppName = 'scanly-app-${uniqueSuffix}'

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'        // Ger appen en egen Managed Identity i Entra ID
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true             // Publikt nåbar (kravet: "svarar på publik URL")
        targetPort: targetPort           // Matchar EXPOSE 8080 i er Dockerfile
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'       // Autentiserar mot ACR via Managed Identity, ingen nyckel
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'scanlyapi'
          image: placeholderImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 2             // Kravet: minst 2 replicas
        maxReplicas: 4
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// RBAC: ger Container Appens Managed Identity rätt att
// 1) hämta images från ACR, 2) läsa/skriva blobs i Storage.
// Utan dessa startar appen men får 403 vid varje Azure-anrop.
// ─────────────────────────────────────────────────────────────

// Inbyggda roll-GUID:n — fasta i hela Azure, samma för alla prenumerationer
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerApp.id, acrPullRoleId)   // deterministiskt unikt namn
  scope: acr                                            // "på ACR:et"
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: containerApp.identity.principalId       // VEM som får rollen
    principalType: 'ServicePrincipal'
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, containerApp.id, storageBlobDataContributorRoleId)
  scope: storage                                        // "på Storage Account"
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}