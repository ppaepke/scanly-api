# Teknisk leveransrapport

**Uppdrag:** Scanly AB — Fakturaigenkänning som tjänst
**Konsultteam:** Pontus Paepke
**Datum:** 22 september 2026
**Version:** 1.0

---

## Sammanfattning

Jag har levererat en fungerande molnbaserad plattform för automatisk
fakturaigenkänning. Ni kan nu ladda upp fakturor via ett säkert API och
omedelbart få tillbaka strukturerad data — leverantör, belopp och
förfallodatum — utan manuell handpåläggning. Plattformen är driftsatt i
Microsoft Azure och skalas automatiskt vid ökad belastning.

---

## Vad som levereras

### Inkluderat i leveransen

| Komponent | Teknisk lösning | Status |
|-----------|----------------|--------|
| REST API | .NET 8 WebAPI, 4 endpoints | ✅ Levererat |
| Containerisering | Docker, multi-stage build | ✅ Levererat |
| Driftsättning | Azure Container Apps | ✅ Levererat |
| Bildarkiv | Azure Container Registry | ✅ Levererat |
| Fillagring | Azure Blob Storage | ✅ Levererat |
| AI-analys | Azure Document Intelligence | ✅ Levererat |
| Infrastruktur som kod | Bicep | ✅ Levererat |
| Automatiserad driftsättning | Azure DevOps-pipeline | ✅ Levererat |
| API-dokumentation | Swagger UI (`/swagger`) | ✅ Levererat |

### Utanför leveransens scope

| Punkt | Motivering |
|-------|-----------|
| Produktionsgodkänd autentisering för slutanvändare | Kräver Entra ID-integration och definierade användarroller — rekommenderas inför kundlansering |
| Utökade automatiserade tester (t.ex. enhetstester av analyslogiken) | Pipelinen kör ett enkelt test som startar imagen och kontrollerar att tjänsten svarar; djupare tester prioriterades bort i denna sprint |
| Disaster recovery-plan | Utanför tidsscopet för denna leverans — bör definieras innan produktionssättning |
| Strukturerad felhantering mot Document Intelligence | Fel från AI-tjänsten hanteras idag inte med egna, tydliga API-svar — rekommenderas som nästa steg |

---

## Arkitektur

### Systemdiagram

```
[Klient / Användare]
        │
        ▼
[Azure Container Apps — REST API]
        │
        ├──► [Azure Blob Storage — fillagring]
        │
        └──► [Azure Document Intelligence — AI-analys]
                        │
                        ▼
              [Strukturerat svar tillbaka till API]
```

### Motiverade arkitekturval

**Varför Azure Container Apps och inte AKS?**
Lösningen består av en enda applikation, och Container Apps gav allt som
behövdes med mycket lite konfiguration — skalning till flera samtidiga
instanser krävde bara ett par rader kod i infrastrukturbeskrivningen, utan
att ett helt Kubernetes-kluster behövde sättas upp och underhållas. Det
sänker både komplexiteten och den löpande driftskostnaden för ett tidigt
SaaS-bolag som Scanly. Skulle plattformen växa till flera samverkande
tjänster som behöver kommunicera tätt med varandra, är AKS värt att
utvärdera på nytt.

**Varför Bicep och inte manuell konfiguration i portalen?**
Infrastrukturen är beskriven som kod, vilket gör den reproducerbar och
spårbar — varje ändring syns i versionshistoriken, och hela miljön kan
byggas om identiskt om något behöver återskapas. Det minskar risken för
mänskliga misstag som lätt uppstår när resurser sätts upp manuellt.

**Varför Azure Blob Storage för fillagring?**
Blob Storage är låg kostnad, skalar automatiskt med mängden data, och
integrerar direkt med samma identitetsbaserade behörighetssystem som resten
av lösningen använder — ingen extra inloggningslogik behövs.

---

## Säkerhetsarkitektur

### Identitet och åtkomst

| Resurs | Åtkomstkontroll |
|--------|----------------|
| Azure Container Apps | Managed Identity — ingen hårdkodad nyckel |
| Azure Blob Storage | RBAC via Managed Identity (Storage Blob Data Contributor) |
| Azure Container Registry | RBAC via Managed Identity (AcrPull) |
| Azure Document Intelligence | API-nyckel, lagrad krypterat som Container App-secret |
| Pipeline-credentials | Azure DevOps Service Connection (Workload Identity Federation) — scopead till resursgruppen, ingen lagrad nyckel |

### Hemlighetshantering

Inga credentials lagras i källkod eller git-historik. Åtkomst till
lagring och Container Registry sker via Azure Managed Identity, som inte
kräver någon lagrad hemlighet alls. Den enda nyckel som förekommer
(Document Intelligence) hanteras via Azure Container Apps krypterade
secret-funktion och skrivs aldrig i klartext i kod eller kommandon.

### Kvarvarande risker

| Risk | Sannolikhet | Åtgärd |
|------|------------|--------|
| API saknar autentisering för slutanvändare | Hög | Implementera Entra ID Easy Auth i nästa sprint |
| Fel från AI-tjänsten ger generiska felmeddelanden istället för tydlig felhantering | Medel | Lägg till strukturerad felhantering och loggning kring Document Intelligence-anropet |
| Ingen rate limiting på uppladdnings-endpointen | Medel | Lägg till API Management eller throttling-regler |

---

## Kostnadskalkyl

### Månadskostnad vid lansering

| Resurs | SKU | Uppskattad kostnad/mån |
|--------|-----|----------------------|
| Container Apps (2 repliker) | Consumption | ~260 kr |
| Azure Container Registry | Basic | ~50 kr |
| Azure Blob Storage | Standard LRS | ~5 kr |
| Azure Document Intelligence | S0 | ~1 600 kr |
| Log Analytics | PerGB2018 | ~15 kr |
| Azure DevOps | Basic | Gratis |
| **Totalt** | | **~1 930 kr/mån** |

> Beräknat med 30 kunder och ~15 000 analyserade fakturor/månad, enligt
> Azures publicerade prislistor. Det motsvarar ungefär 0,13 kr per analyserad
> faktura, varav ungefär 0,11 kr är själva AI-analysen.

### Skalningspunkt

Document Intelligence är redan idag den klart dominerande kostnadsposten,
eftersom den är den enda resursen som prissätts per analyserad faktura
snarare än som en fast avgift. Tredubblas kundbasen till 90 kunder väntas
totalkostnaden stiga till ungefär 5 100 kr/mån — nästan hela ökningen driven
av just den posten.

Den tekniska flaskhalsen, om trafiken fyrdubblas, ligger dock inte i
kostnaden utan i hur många fakturor som kan analyseras **samtidigt**: varje
analys upptar en instans av tjänsten under tiden den väntar på svar, och
med dagens gräns på fyra samtidiga instanser kan fyra fakturor hanteras
parallellt innan nya får vänta i kö. Vid en kraftig trafiktopp är det den
gränsen som avgör svarstiden, inte kostnaden.

Att höja den gränsen är billigt i sig — ytterligare instanser kostar bara
för den tid de faktiskt är aktiva. Den egentliga kostnadsökningen vid högre
trafik kommer alltid från Document Intelligence, inte från skalningen av
själva applikationen, eftersom det är den enda resursen som växer i
proportion till hur många fakturor som analyseras.

---

## Rekommendationer inför produktionssättning

1. **Autentisering för slutanvändare** — Implementera Entra ID Easy Auth eller API-nyckel per kund innan offentlig lansering.
2. **Felhantering mot Document Intelligence** — Fånga och logga fel från AI-tjänsten, returnera tydliga API-svar istället för generiska serverfel.
3. **Monitoring** — Koppla Application Insights och sätt upp alerts vid förhöjd felfrekvens.
4. **Höj den samtidiga kapaciteten** — Om trafiken väntas öka kraftigt, höj gränsen för samtidiga instanser för att undvika kö vid trafiktoppar.
5. **Kostnadslarm** — Sätt budget-alert i Azure Cost Management, särskilt kopplat till Document Intelligence-användningen som är den snabbast växande kostnaden.

---

## Överlämning

| Leverabel | Plats |
|-----------|-------|
| Källkod | Azure DevOps-repo |
| Bicep-mallar | `/infra/` i repot |
| Pipeline-definition | `azure-pipelines.yml` i repots rot |
| API-dokumentation | `https://scanly-app-b2wli3hdd2336.victoriousdesert-92496089.swedencentral.azurecontainerapps.io/swagger` |
| Denna rapport | `RAPPORT.md` i repots rot |

---

*Rapporten är upprättad som ett avslutande leveransdokument. Frågor hänvisas
till konsulten via Azure DevOps.*
