# ProcedureLibraryVSRCodeDeployment

Vergleich zweier Deployment-Varianten von OpenEdge ABL r-Code: lose r-Files im
PROPATH gegenueber einer Procedure Library (`.pl`).

## Inhalt

| Pfad | Beschreibung |
| --- | --- |
| `src/procedures/test00001.p` … `test10000.p` | 10000 winzige Testprozeduren, die dynamisch je genau einmal aufgerufen werden |
| `src/build/generate-tests.p` | erzeugt die Testprozeduren neu (`-param "<Zielverzeichnis>,<Anzahl>"`) |
| `src/build/compile-tests.p` | kompiliert die Prozeduren nach `build/rcode` (`-param "<Quelle>,<r-Code-Verzeichnis>"`) |
| `src/build/runtests.p` | ruft alle Prozeduren der Reihe nach dynamisch auf und gibt die benoetigte Zeit aus (`-param "<Bezeichnung>,<Anzahl>,<Ergebnisdatei>,<Statusdatei>,<PROPATH-Eintrag>"`) |
| `benchmark.sh` | fuehrt die komplette Messung inklusive Packetierung in die Procedure Library aus und protokolliert alles nach `build/benchmark.log` |

Eine Testprozedur sieht so aus:

```progress
/* test00001.p */
DEFINE VARIABLE i AS INTEGER NO-UNDO.
i = 1.
```

## Messung ausfuehren

Voraussetzung ist eine installierte OpenEdge Runtime. Das Installations-
verzeichnis ist in `benchmark.sh` fest mit `C:\dlc128_x64` hinterlegt; eine
gesetzte Umgebungsvariable `DLC` hat weiterhin Vorrang.

```bash
./benchmark.sh                              # 10000 Prozeduren, 3 Messrunden
COUNT=10000 REPEATS=5 WARMUP=1 ./benchmark.sh
```

| Variable | Bedeutung | Default |
| --- | --- | --- |
| `COUNT` | Anzahl der dynamisch aufgerufenen Prozeduren | `10000` |
| `REPEATS` | Messrunden je Variante | `3` |
| `WARMUP` | Warmlaeufe je Variante (Zeiten werden verworfen) | `1` |

Das Skript

1. kompiliert `src/procedures/test*.p` nach `build/rcode`,
2. packt dieselben r-Files mit `prolib` in `build/lib/testlib.pl` - noch
   bevor gemessen wird, damit beide Varianten unter gleichen Bedingungen
   antreten,
3. faehrt `WARMUP` Warmlaeufe je Variante (Zeiten werden verworfen),
4. misst `REPEATS` Runden, in denen beide Varianten abwechselnd zuerst
   drankommen,
5. gibt je Variante bestes Ergebnis und Mittelwert sowie den Unterschied aus.

Die Rohwerte aller Messrunden landen zusaetzlich als
`Bezeichnung;Anzahl;Millisekunden` in `build/results.csv`.

### Wird wirklich jedes Mal eine frische AVM gestartet?

Ja. Jede Messung ist ein eigener `_progres`-Aufruf, also ein eigener
Betriebssystem-Prozess mit einer neu gestarteten AVM. r-Code, den eine
fruehere Messung geladen hat, kann eine spaetere Session nicht sehen: der
Session-Cache stirbt mit dem Prozess. Zum Nachweis protokolliert
`runtests.p` beim Start `SESSION:UNIQUE-ID` - dieser Wert unterscheidet sich
bei jedem Lauf.

Was sehr wohl "cachen" kann, ist der Datei-Cache des Betriebssystems: die
zuerst gemessene Variante liest von Platte, die zweite womoeglich schon aus
dem RAM. Dagegen wirken

* die Warmlaeufe (`WARMUP`), deren Zeiten verworfen werden und die beide
  Varianten gleichermassen in den Cache holen, und
* die abwechselnde Reihenfolge in den Messrunden (`REPEATS`), sodass keine
  Variante systematisch von der Position profitiert.

Fuer eine Messung mit garantiert kaltem Datei-Cache muss der Cache
ausserhalb des Skripts geleert werden (unter Windows z.B. per Neustart);
das Skript tut das bewusst nicht.

Einzelne Schritte lassen sich auch von Hand starten, z. B.:

```bash
"$DLC/bin/_progres" -b -p src/build/runtests.p \
    -param "Procedure Library,10000,build/results.csv,build/status/run.status,$PWD/build/lib/testlib.pl"
```

Der PROPATH-Eintrag wird bewusst als Parameter uebergeben und in `runtests.p`
per `PROPATH = <Eintrag> + "," + PROPATH` gesetzt: `_progres.exe` uebernimmt
unter Windows die Umgebungsvariable `PROPATH` nicht, sondern verwendet den in
der Registry hinterlegten Standard-PROPATH. Ohne diesen Parameter meldet die
Messung `test00001.r ist ueber den PROPATH nicht erreichbar`.

Neue Testprozeduren erzeugen:

```bash
$DLC/bin/_progres -b -p src/build/generate-tests.p -param "src/procedures,10000"
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
* uebergibt den PROPATH-Eintrag zusaetzlich als Parameter an `runtests.p`,
  weil `_progres.exe` die Umgebungsvariable `PROPATH` unter Windows ignoriert,
* verwendet ohne gesetzte Umgebungsvariable die feste Vorgabe
  `C:\dlc128_x64` und rechnet die Windows-Schreibweise fuer die Datei-
  pruefungen der Shell in `/c/dlc128_x64` um (an die OpenEdge-Programme wird
  weiterhin der Windows-Pfad in `$DLC` uebergeben).

Typischer Aufruf in Git-Bash:

```bash
COUNT=10000 ./benchmark.sh                      # nutzt C:\dlc128_x64
DLC='C:\Progress\OpenEdge' ./benchmark.sh       # andere Installation
```

Auf der ABL-Seite protokollieren `generate-tests.p`, `compile-tests.p` und
`runtests.p` alle Fehler ueber `MESSAGE` (Compilerfehler inklusive Zeile und
Spalte, fehlgeschlagene dynamische Aufrufe inklusive aller Meldungen aus
`ERROR-STATUS`) und fangen unerwartete Fehler in einem `CATCH`-Block ab.
