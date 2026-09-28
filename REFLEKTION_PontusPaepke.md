# Individuell reflektion — Pontus Paepke

## 1. Min roll i teamet

Jag gjorde uppgiften själv och hade ansvar för hela lösningen — infrastrukturen i `infra/main.bicep`, CI/CD-flödet i `azure-pipelines.yml`, Docker-bygget och kopplingen mot Document Intelligence. Jag byggde varje del från grunden och testade den innan jag gick vidare till nästa, snarare än att sätta ihop allt och hoppas att det funkade i slutet.

Den debug-session jag äger mest är när Container App-deploymenten gav `Operation expired` upprepade gånger — beskriven i detalj under nästa fråga. Att jag till slut löste den genom att jämföra min konfiguration mot en klasskompis fungerande version är nog det jag är mest nöjd med från hela sprinten.

## 2. Det svåraste momentet

Det jag fastnade på längst var `Operation expired`-felet när Container App skulle deployas. Först trodde jag att portarna inte matchade mellan Bicep-filen och platshållar-imagen, så jag testade att ändra porten — men felet kom tillbaka identiskt. Jag kollade sedan revision-status och Azures aktivitetsloggar utan att hitta en konkret orsak. Det som till slut löste det var att jämföra min Bicep-fil mot en klasskompis fungerande version: skillnaden var att jag använde en SystemAssigned identity kopplad direkt till Container App, vilket skapade ett cirkulärt beroende, medan hen använde en fristående identitet som kunde få sina roller innan appen ens skapades. Den största lärdomen var inte den tekniska lösningen i sig, utan att jämföra mot något som faktiskt fungerar är ett effektivt felsökningsknep när man kört fast.

## 3. Vad jag förstår nu som jag inte förstod innan

Det koncept jag förstår mycket bättre nu är least privilege inom RBAC. Innan idag visste jag att man "ska ge minsta möjliga åtkomst", men inte riktigt varför det spelar roll i praktiken. Nu förstår jag att Azure låter dig scopea en rolltilldelning till en specifik resurs — som `scope: acr` istället för `scope: resourceGroup()` i min Bicep-fil — av två skäl samtidigt: dels begränsas skadan om identiteten någon gång skulle läcka eller missbrukas till bara de resurserna den faktiskt fick tillgång till, dels blir det tydligt och spårbart exakt vem som får röra vad, resurs för resurs, istället för en enda vag "allt eller inget"-rättighet på hela prenumerationen. Det jag faktiskt tar med mig är inte bara ATT man ska scopea smått, utan VARFÖR — att det är en medveten avvägning mellan bekvämlighet och säkerhet, inte bara en regel man följer utan att veta anledningen.

## 4. Vad jag skulle göra annorlunda

Om jag fick göra om sprinten från dag ett hade jag velat förstå hela arkitekturen — hur Container App, identiteten, RBAC-tilldelningarna, ACR och Storage faktiskt hänger ihop — bättre innan jag började skriva Bicep-koden. Jag byggde infrastrukturen bit för bit utan att riktigt ha helhetsbilden klar för mig, vilket gjorde att jag inte förstod varför ordningen mellan resurser spelade roll förrän jag redan fastnat i `Operation expired`-felet. Jag är osäker på om jag hade sluppit felet helt med bättre förståelse från början, men jag hade förmodligen förstått snabbare vad som faktiskt gick fel istället för att testa mig fram. Nästa gång skulle jag lägga mer tid på att förstå helheten innan jag börjar skriva kod.

## 5. Arkitektur och ekonomi

Just nu ligger kostnaden på ungefär 1 930 kronor i månaden, baserat på 30 kunder och runt 15 000 fakturor. Den absolut största posten är själva AI-analysen — den kostar per faktura, medan resten av infrastrukturen har en fast kostnad oavsett hur mycket ni använder tjänsten. Så ju fler kunder ni får, desto mer av notan hamnar just där, inte i servrarna. Var det gäller sårbarhet skulle jag peka på två saker. Det finns i dagsläget ingen inloggning för era slutanvändare — vem som helst med länken kan ladda upp en faktura, vilket är okej i det här läget men behöver lösas innan en riktig lansering. Den andra sårbarheten är att om AI-tjänsten någon gång svarar med ett fel, till exempel om den inte klarar av att tolka en fil, får kunden idag bara ett generiskt felmeddelande istället för något tydligt och användbart. Det är inget som stoppar er från att lansera i liten skala, men det är precis den typen av saker jag skulle vilja täppa till innan ni skalar upp på riktigt.
