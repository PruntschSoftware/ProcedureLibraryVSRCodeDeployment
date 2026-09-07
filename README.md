# ProcedureLibraryVSRCodeDeployment

Vergleich zweier Deployment-Varianten von OpenEdge ABL r-Code: lose r-Files im
PROPATH gegenueber einer Procedure Library (`.pl`).

## Inhalt

| Pfad | Beschreibung |
| --- | --- |
| `src/procedures/test0001.p` … `test1000.p` | 1000 winzige Testprozeduren, die dynamisch je genau einmal aufgerufen werden |
| `src/build/generate-tests.p` | erzeugt die Testprozeduren neu (`-param "<Zielverzeichnis>,<Anzahl>"`) |
| `src/build/compile-tests.p` | kompiliert die Prozeduren nach `build/rcode` (`-param "<Quelle>,<r-Code-Verzeichnis>"`) |
| `src/build/runtests.p` | ruft alle Prozeduren der Reihe nach dynamisch auf und gibt die benoetigte Zeit aus (`-param "<Bezeichnung>,<Anzahl>,<Ergebnisdatei>"`) |
| `benchmark.sh` | fuehrt die komplette Messung inklusive Packetierung in die Procedure Library aus und protokolliert alles nach `build/benchmark.log` |

Eine Testprozedur sieht so aus:

```progress
/* test0001.p */
DEFINE VARIABLE i AS INTEGER NO-UNDO.
i = 1.
```

## Messung ausfuehren

Voraussetzung ist eine installierte OpenEdge Runtime. Das Installations-
verzeichnis ist in `benchmark.sh` fest mit `C:\dlc128_x64` hinterlegt; eine
gesetzte Umgebungsvariable `DLC` hat weiterhin Vorrang.

```bash
./benchmark.sh          # 1000 Prozeduren
COUNT=1000 ./benchmark.sh
```

Das Skript

1. kompiliert `src/procedures/test*.p` nach `build/rcode`,
2. ruft alle Prozeduren dynamisch genau einmal auf (PROPATH zeigt auf
   `build/rcode`) und misst die Laufzeit,
3. packt dieselben r-Files mit `prolib` in `build/lib/testlib.pl`,
4. wiederholt die Messung mit der Library im PROPATH,
5. gibt beide Zeiten und deren Unterschied aus.

Die Rohwerte landen zusaetzlich als `Bezeichnung;Anzahl;Millisekunden` in
`build/results.csv`.

Einzelne Schritte lassen sich auch von Hand starten, z. B.:

```bash
PROPATH=$PWD/build/lib/testlib.pl $DLC/bin/_progres -b -p src/build/runtests.p \
    -param "Procedure Library,1000,build/results.csv"
```

Neue Testprozeduren erzeugen:

```bash
$DLC/bin/_progres -b -p src/build/generate-tests.p -param "src/procedures,1000"
```

## Logging und Fehlersuche

`benchmark.sh` protokolliert jeden Schritt mit Zeitstempel auf der Konsole und
zusaetzlich in `build/benchmark.log` (ueber `LOG_FILE` aenderbar). Es gibt
keinen stillen Abbruch mehr:

* jeder Schritt wird mit Kommando, kompletter Ausgabe und Exit-Code geloggt,
* ein `ERR`-Trap protokolliert unerwartete Fehler mit Zeilennummer und
  Kommando, Traps fuer `INT`/`TERM`/`HUP` melden Abbrueche durch Signale,
* ein `EXIT`-Trap gibt am Ende immer den Exit-Code und den zuletzt
  ausgefuehrten Schritt aus,
* fehlende Voraussetzungen (DLC-Verzeichnis nicht vorhanden, kein
  `_progres`/`prolib`, ungueltiges
  `COUNT`, zu wenige Testprozeduren) werden vor dem ersten Aufruf gemeldet,
* die ABL-Programme schreiben ihr Ergebnis nach `build/status/*.status`
  (`OK: …` oder `ERROR: …`). Das Skript prueft diese Dateien; fehlt eine
  Statusdatei, gilt der Lauf als vorzeitig beendet und wird als Fehler
  gemeldet. Damit werden auch Faelle erkannt, in denen `_progres` mit
  Exit-Code 0 zurueckkommt.

Ausfuehrliche Ablaufverfolgung (`set -x`) einschalten:

```bash
DEBUG=1 ./benchmark.sh
```

### Git-Bash unter Windows

Das Skript erkennt MSYS/MinGW/Cygwin automatisch und

* verwendet `_progres.exe` bzw. `prolib.exe`,
* wandelt Pfade fuer den PROPATH mit `cygpath -w` in Windows-Pfade um
  (OpenEdge kann mit Pfaden wie `/c/dlc` nichts anfangen),
* verwendet ohne gesetzte Umgebungsvariable die feste Vorgabe
  `C:\dlc128_x64` und rechnet die Windows-Schreibweise fuer die Datei-
  pruefungen der Shell in `/c/dlc128_x64` um (an die OpenEdge-Programme wird
  weiterhin der Windows-Pfad in `$DLC` uebergeben).

Typischer Aufruf in Git-Bash:

```bash
COUNT=1000 ./benchmark.sh                       # nutzt C:\dlc128_x64
DLC='C:\Progress\OpenEdge' ./benchmark.sh       # andere Installation
```

Auf der ABL-Seite protokollieren `generate-tests.p`, `compile-tests.p` und
`runtests.p` alle Fehler ueber `MESSAGE` (Compilerfehler inklusive Zeile und
Spalte, fehlgeschlagene dynamische Aufrufe inklusive aller Meldungen aus
`ERROR-STATUS`) und fangen unerwartete Fehler in einem `CATCH`-Block ab.
