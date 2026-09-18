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