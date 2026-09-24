# ARCHITECTURE.md — Scanly API

Teknisk reflektion. Svaren är skrivna utifrån hur jag faktiskt byggde, felsökte
och driftsatte lösningen.

---

## 1. Container Apps — varför inte AKS?

Jag valde Container Apps istället för AKS för att det bara är en enda app, och
Container Apps gav mig allt jag behövde med väldigt lite konfiguration —
skalning till 2–4 repliker tog tre rader i Bicep-filen, utan att jag behövde
sätta upp ett kluster, hantera noder eller skriva egna Deployment- och
Service-objekt som AKS kräver. Nackdelen är att jag tappar en del finkornig
kontroll: jag kan inte styra exakt vilken hårdvara containrarna kör på, och om
flera tjänster hade behövt prata privat med varandra hade AKS gett mycket mer
kraftfulla verktyg för det (Network Policies, interna Services). Jag hade valt
AKS istället om lösningen bestått av flera samverkande mikrotjänster med
komplexa beroenden, eller om jag behövt exakt kontroll över hur och var varje
container körs — för en enda app som den här är den extra komplexiteten bara
onödigt arbete.

---

## 2. CI/CD — pipeline-flödet

Pipelinen är definierad i `azure-pipelines.yml` och startar automatiskt vid
varje `git push` till main. Den kör på en tillfällig Ubuntu-agent i Azure
DevOps och gör fyra saker i ordning: loggar in mot ACR via en Service
Connection, bygger en ny Docker-image med en unik tagg baserad på Azure
DevOps eget byggnummer (`Build.BuildId`), pushar imagen till ACR, och
uppdaterar sist Container App till att köra den nya imagen. Att varje build
får en egen unik tagg istället för att skriva över samma version betyder att
jag kan rulla tillbaka till en gammal, fungerande image om något går fel,
bara genom att peka Container App mot ett äldre byggnummer. Om ett steg
misslyckas, till exempel om Docker-bygget failar på ett kompileringsfel, så
stoppas pipelinen där och resten av stegen körs aldrig — det bör betyda att
den redan driftsatta appen fortsätter köra som vanligt, eftersom Container
App bara uppdateras i sista steget.

---

## 3. IaC och idempotens

Jag valde Bicep för att det går att köra om — man sätter upp infrastrukturen
en gång i kod istället för att klicka runt i portalen, och slipper risken att
råka sätta upp samma sak flera gånger av misstag. Idempotens betyder att en
operation ger samma resultat oavsett hur många gånger man kör den — skickar
man samma kommando igen ändras inte slutresultatet, förutsatt att första
körningen redan lyckats. Jag märkte det här konkret under felsökning, när jag
körde `az deployment group create` flera gånger i rad: det som redan fanns
(ACR, Storage, Log Analytics, environment) skapades inte om och kraschade
inte för att det redan fanns, Bicep försökte bara med det som fortfarande
saknades eller behövde ändras.

---

## 4. Säkerhet — hemligheter och credentials

Jag hanterar hemligheter på två sätt. För ACR och Storage använder jag
Managed Identity, så ingen hemlighet behöver sparas alls — appen får
rättigheter via RBAC istället för lösenord. Nyckeln till Document
Intelligence går inte att göra så med, den måste vara en riktig nyckel, så
den ligger som en secret i Container App via `az containerapp secret set`
och refereras med `secretref:` i koden, aldrig i klartext. Om en sån nyckel
av misstag hade legat hårdkodad i `Program.cs` och blivit committad hade
appen i sig inte blivit åtkomlig för andra, men vem som helst med tillgång
till repot hade kunnat använda nyckeln själv, vilket hade kunnat kosta pengar
eller gå över kvoten. Det räcker inte att bara ta bort raden och committa
igen heller — nyckeln finns kvar i de gamla commitsen i historiken. Man måste
byta ut den helt (rotera den), det vill säga skapa en ny hos tjänsten och
uppdatera secreten, och se den gamla som förbrukad för alltid.

---

## 5. Ekonomi

Utgår från scenariots siffror: lansering med 30 kunder, ~15 000
fakturor/månad.

| Resurs | Kostnad/mån | Varför |
|---|---|---|
| Container Apps (2 replicas) | ~260 kr | Fast kostnad, betalar för kapacitet oavsett trafik |
| ACR (Basic) | ~50 kr | Fast månadsavgift |
| Storage | ~5 kr | Försumbar, filerna är väldigt små |
| Document Intelligence | ~1 600 kr | Enda posten som kostar per faktura |
| **Totalt** | **~1 930 kr/mån** | |

Document Intelligence är klart den dyraste resursen redan från start, för
att den kostar per analyserad sida — de andra kostar ungefär samma oavsett
hur mycket appen används.

Om kundbasen tredubblas till 90 kunder (~45 000 fakturor/mån) väntar jag mig
en totalkostnad på ungefär 5 100 kr/mån. Kostnaden tredubblas inte riktigt
fullt ut, eftersom Container Apps och ACR knappt rör sig — det är
Document Intelligence som driver nästan hela ökningen.

Flaskhalsen om trafiken fyrdubblas är inte i första hand pengar, utan
teknik: varje analys väntar synkront på Document Intelligence
(`WaitUntil.Completed`), vilket håller en replika upptagen under tiden. Med
`maxReplicas: 4` kan jag bara hantera fyra samtidiga uppladdningar — vid en
trafiktopp är det den gränsen, inte kostnaden, som sätter taket.

*Siffrorna är uppskattningar från Azures publicerade priser, inte exakta
belopp från Pricing Calculator.*
