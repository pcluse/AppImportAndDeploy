# PLS AppImporter and Deploy

Programmet är ett tillägg till Config Manager som automatiserar två olika moment. Dels att importera applikationer (framförallt skrivna i PSADT) och sen att deploya applikationer till olika samlingar.

## PLS AppImport

![AppImport](images/app-list.png)

## Använding

När programmet startar så söker den igenom mappen \\src\file$\Applicationer och hittar alla applicationer som inte är importerade till SCCM. Strukturen på en application skall vara en mapp som är programmets namn och en undermapp som är aktuell version. Ex \\src\file$\Applicationer\MinFinaTestApp och undermappen \\src\file$\Applicationer\MinFinaTestApp\1.4. När sökningen är klar så kan man markera de applikationer som man vill installera.

Här finns en gotcha. När du kryssar en applikation så är det inte den som blir markerad utan du måste även trycka på namnet för att se import-inställningarna för denna. 


För importen så finns det följande alternativ

* Install commandline -
Vilket kommando skall köras vid installation. Behöver inte ändras om du använder PSADT
* Uninstall commandline -
Vilket kommando skall köras vid avinstallation. Behöver inte ändras om du använder PSADT
* Skip creating detectionmethod -
Programmet försöker inte skapa detection från tidigare versioner eller från MSI-filer utan skapar bara en platshållar-regel
* Uninstall previous version (just not replace) - 
Om importen hittar en äldre version så skapas en superseedence-regel. Om man vill att vid installation av denna version så skall avinstallationen på den gamla versionen köras först. Många program kan installeras över en äldre version men om inte så kryssa i denna.
* Should Deploy to 'Applicationstest' - 
Vid importen så deployas applikationen till 'Applikationstest' som är en samling där man kan lägga in sina test-datorer.
** Automatically update superseded -
Om en tidigare version av applikationen är installerad på en dator i Applikationstest så kommer den automatisk uppdateras. Annars måste användaren uppdatera via Software Center

Om du kryssar i en application och trycker på knappen "Import selected applications" så startar importen och programmet växla till...

### Fliken - App List

![AppImport](images/log.png)

Här visas det information i två fält "Log" som visar vad programmet gör och "Todo" som är saker som måste kollas upp i efterhand. För varje importerad applikation så utförs följande steg

1. Letar efter tidigare eller nyare versioner av applikationen. Om den hittar en **nyare** version så får man en varning i "Todo"
1. Skapar applikationen. Importerar ikon om det finns en fil som heter icon.jpg, icon.png eller icon.ico i programmets mapp. Om ikonen är större än 250x250 så varnar den
1. Skapar en Skriptinstallation
1. Skapar detection rules (se nedan)
1. Om det finns en tidigare version så kopierar den dependencies från denna
1. Om det finns en tidigare version så skapas en supersede mot denna
1. Distrubierar applikationen till alla distributionspunkterna
1. Deployar den till Applikationstest om man valt detta

### Detection-rules

* Om mappen files i programmappen (ex: \\src\file$\Applicationer\MinFinaTestApp\1.4\files) innehåller MSI-filer så skapas en regel för varje där Produkt-nyckel och version testas. Om installationen innehåller MSP-filer så kan denna ändras och man kan behöva ändra version.
* Om DeployApplication.ps1 innehåller Add-SCCMDetection så skapas en regel för det registervärdet som den skriver
* Om versionen av programmet är i formen x.x.x och tidigare version innehåller en regel för fil med version mellan x.x.x.0 och x.x.x.99999 så kopieras den regeln men ersätts med det nya programmets version. Praktiskt då versionen som ett program har är x.x.x (ex 2.1.4) men sen har exe-filen en version som även innehåller ett byggnummer (ex 2.1.4.6778)
* Om version av programmet är i formen x.x.x.x och tidigare version har en regel för fil med version så kopieras den regeln men den aktuella versionen sätts.
* Övriga regler för register, filer och mappar kopieras och om de innehåller x.x där x är ett nummer så skrivs en varning ut i Todo att det kan vara en sökväg med ett versionnummer i så man skall dubbelkolla detta.


## PLS Deploy

![AppImport](images/deploy-menu.png)

Om du högerklickar på en applikation i listan så kommer du längst ner i menyn
se ett val PLS Deploy med en undermeny med fyra val

* Alla tillgängliga
* Alla tillgängliga (automatisk uppgradering)
* Tvingande
* Applikationstest

### Alla tillgängliga
Applikationen kommer att finnas för installation i Software Center

### Alla tillgängliga (automatisk uppgradering)
Applikationen kommer finnas i Software Center och på de datorer som har den tidigare version installerad så kommer den uppgradera.

### Tvingande
Applikationen kommer att installeras på alla datorer som finns med i samlingen Tvingad/Programnamn (ex om Applikationen heter MinFinaApp v1.4 så kommer alla samlingar i Tvingad / MinFinaApp att få programmet installerat). Om samlingen inte finns så skapas den.

Krav för att kunna köra skriptet är:
    Minst Windows 10 1607 (det kan fungera på andra versioner)
    System Center Configuration Manager Console 1611



Versioner

1.0.0.4 - 2018-08-28 Nu klarar programmet av att kopiera alla möjliga detection rules från tidigare version (Om det finns två regler med OR emellan så kan den inte göra kopieringen)