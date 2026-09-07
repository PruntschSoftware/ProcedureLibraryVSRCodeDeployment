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
| `benchmark.sh` | fuehrt die komplette Messung inklusive Packetierung in die Procedure Library aus |

Eine Testprozedur sieht so aus:

```progress
/* test0001.p */
DEFINE VARIABLE i AS INTEGER NO-UNDO.
i = 1.
```

## Messung ausfuehren

Voraussetzung ist eine installierte OpenEdge Runtime; `DLC` muss gesetzt sein
(Default `/usr/dlc`).

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
