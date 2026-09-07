#!/usr/bin/env bash
#
# benchmark.sh
#
# 1. kompiliert die Testprozeduren src/procedures/test*.p nach build/rcode
# 2. ruft alle Prozeduren dynamisch genau einmal auf (lose r-Files im PROPATH)
#    und misst die dafuer benoetigte Zeit
# 3. packt dieselben r-Files in eine Procedure Library build/lib/testlib.pl
# 4. wiederholt die Messung mit der Library im PROPATH
# 5. gibt den Unterschied der beiden Messungen aus
#
# Voraussetzung: installierte OpenEdge Runtime, $DLC gesetzt (oder /usr/dlc).
#
# Umgebungsvariablen:
#   DLC       Installationsverzeichnis der OpenEdge Runtime
#   COUNT     Anzahl der aufzurufenden Prozeduren (Default 1000)
#   LOG_FILE  Pfad der Logdatei (Default build/benchmark.log)
#   DEBUG=1   zusaetzliche Ablaufverfolgung (set -x) in die Logdatei
#
# Saemtliche Schritte werden protokolliert; jeder Fehler - auch ein Abbruch
# durch ein Signal - wird mit Zeile, Kommando und Exit-Code geloggt, damit
# das Skript (z.B. unter Git-Bash) nicht kommentarlos abbrechen kann.

set -uo pipefail

# ---------------------------------------------------------------------------
# Grundeinstellungen
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "FEHLER: Skriptverzeichnis nicht ermittelbar." >&2
    exit 1
}
cd "$ROOT" || {
    echo "FEHLER: Wechsel nach '$ROOT' nicht moeglich." >&2
    exit 1
}

COUNT="${COUNT:-1000}"

SRC_DIR="src/procedures"
BUILD_DIR="build"
RCODE_DIR="$BUILD_DIR/rcode"
LIB_DIR="$BUILD_DIR/lib"
LIB="$LIB_DIR/testlib.pl"
RESULT="$BUILD_DIR/results.csv"
STATUS_DIR="$BUILD_DIR/status"
LOG_FILE="${LOG_FILE:-$BUILD_DIR/benchmark.log}"

CURRENT_STEP="Initialisierung"
FAILED=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if ! : >> "$LOG_FILE" 2>/dev/null; then
    echo "WARNUNG: Logdatei '$LOG_FILE' nicht beschreibbar - es wird nur auf" \
         "die Konsole geloggt." >&2
    LOG_FILE="/dev/null"
fi

timestamp() {
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "----------- --------"
}

log() {
    # $1 = Level, Rest = Meldung
    local level="$1"
    shift
    local line
    line="$(timestamp) [$level] $*"
    if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
        printf '%s\n' "$line" >&2
    else
        printf '%s\n' "$line"
    fi
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

# Fehler, der den Ablauf beendet
die() {
    FAILED=1
    log_error "$@"
    log_error "Abbruch im Schritt: $CURRENT_STEP"
    exit 1
}

# ---------------------------------------------------------------------------
# Fehler- und Signal-Behandlung
# ---------------------------------------------------------------------------

on_error() {
    local exit_code="$1" line="$2" command="$3"
    FAILED=1
    log_error "Unerwarteter Fehler in Zeile $line: '$command' (Exit-Code $exit_code)"
    log_error "Schritt: $CURRENT_STEP"
}

on_signal() {
    local signal="$1"
    FAILED=1
    log_error "Signal $signal empfangen - Abbruch im Schritt: $CURRENT_STEP"
    exit $((128 + ${2:-0}))
}

on_exit() {
    local exit_code="$?"
    if [ "$exit_code" -ne 0 ] || [ "$FAILED" -ne 0 ]; then
        log_error "benchmark.sh mit Exit-Code $exit_code beendet" \
                  "(letzter Schritt: $CURRENT_STEP)."
        log_error "Details siehe Logdatei: $LOG_FILE"
        [ "$exit_code" -eq 0 ] && exit_code=1
    else
        log_info "benchmark.sh erfolgreich beendet. Logdatei: $LOG_FILE"
    fi
    exit "$exit_code"
}

set -E
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap 'on_signal INT 2' INT
trap 'on_signal TERM 15' TERM
trap 'on_signal HUP 1' HUP
trap on_exit EXIT

if [ "${DEBUG:-0}" = "1" ]; then
    export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
    set -x
fi

# Startet ein Kommando, protokolliert Ausgabe und Exit-Code vollstaendig.
run_cmd() {
    local description="$1"
    shift
    local exit_code=0

    CURRENT_STEP="$description"
    log_info "Starte: $description"
    log_info "Kommando: $*"

    # Ausgabe geht gleichzeitig auf die Konsole und in die Logdatei.
    # Der ERR-Trap wird kurz deaktiviert, damit der Fehler nur einmal - mit
    # dem sprechenden Text von 'die' - protokolliert wird.
    trap - ERR
    "$@" 2>&1 | tee -a "$LOG_FILE"
    exit_code="${PIPESTATUS[0]}"
    trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

    if [ "$exit_code" -ne 0 ]; then
        die "Schritt '$description' fehlgeschlagen (Exit-Code $exit_code)."
    fi

    log_info "Fertig: $description"
    return 0
}

# Prueft die von den ABL-Programmen geschriebene Statusdatei.
check_status_file() {
    local description="$1" status_file="$2" status_line=""

    if [ ! -f "$status_file" ]; then
        die "Schritt '$description': Statusdatei '$status_file' fehlt - das" \
            "ABL-Programm wurde vermutlich vorzeitig beendet."
    fi

    status_line="$(tr -d '\r' < "$status_file" | head -n 1)"
    log_info "Status '$description': $status_line"

    case "$status_line" in
        OK*) return 0 ;;
        *)   die "Schritt '$description' meldet Fehler: $status_line" ;;
    esac
}

log_info "===== benchmark.sh gestartet ====="
log_info "Arbeitsverzeichnis: $ROOT"
log_info "Shell: ${BASH_VERSION:-unbekannt} auf $(uname -s 2>/dev/null || echo unbekannt)"
log_info "Logdatei: $LOG_FILE"

# ---------------------------------------------------------------------------
# Plattform (Git-Bash/MSYS/Cygwin vs. Unix)
# ---------------------------------------------------------------------------

CURRENT_STEP="Plattformerkennung"
UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
IS_WINDOWS=0
EXE=""
PROPATH_SEP=":"

case "$UNAME_S" in
    MINGW*|MSYS*|CYGWIN*)
        IS_WINDOWS=1
        EXE=".exe"
        PROPATH_SEP=";"
        log_info "Windows-Umgebung erkannt ($UNAME_S) - verwende '*$EXE' und" \
                 "'$PROPATH_SEP' als PROPATH-Trenner."
        ;;
    *)
        log_info "Unix-Umgebung erkannt ($UNAME_S)."
        ;;
esac

# Wandelt einen Pfad fuer die OpenEdge-Programme um (unter Git-Bash noetig,
# da _progres keine MSYS-Pfade wie /c/dlc versteht).
native_path() {
    local path="$1"
    if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$path" 2>/dev/null || printf '%s' "$path"
    else
        printf '%s' "$path"
    fi
}

# ---------------------------------------------------------------------------
# OpenEdge Runtime suchen
# ---------------------------------------------------------------------------

CURRENT_STEP="Pruefung der OpenEdge-Installation"

if [ -z "${DLC:-}" ]; then
    if [ "$IS_WINDOWS" -eq 1 ]; then
        log_warn "DLC ist nicht gesetzt - probiere Standardpfade."
        for candidate in "/c/Progress/OpenEdge" "/c/dlc" "/d/Progress/OpenEdge"; do
            if [ -d "$candidate" ]; then
                DLC="$candidate"
                break
            fi
        done
    else
        DLC="/usr/dlc"
    fi
fi

DLC="${DLC:-}"
export DLC

if [ -z "$DLC" ] || [ ! -d "$DLC" ]; then
    die "OpenEdge-Installationsverzeichnis nicht gefunden (DLC='${DLC:-<leer>}')." \
        "Bitte DLC setzen, z.B.: DLC=/c/Progress/OpenEdge ./benchmark.sh"
fi

PROGRES="$DLC/bin/_progres$EXE"
PROLIB="$DLC/bin/prolib$EXE"

for tool in "$PROGRES" "$PROLIB"; do
    if [ ! -f "$tool" ]; then
        die "Benoetigtes Programm nicht gefunden: $tool (DLC='$DLC')."
    fi
    if [ ! -x "$tool" ]; then
        log_warn "Programm '$tool' ist nicht als ausfuehrbar markiert -" \
                 "Aufruf wird trotzdem versucht."
    fi
done

log_info "DLC=$DLC"
log_info "_progres=$PROGRES"
log_info "prolib=$PROLIB"

CURRENT_STEP="Pruefung der Parameter und Quelldateien"

case "$COUNT" in
    ''|*[!0-9]*) die "COUNT muss eine positive ganze Zahl sein (aktuell: '$COUNT')." ;;
esac
[ "$COUNT" -gt 0 ] || die "COUNT muss groesser als 0 sein (aktuell: '$COUNT')."
log_info "Anzahl Prozeduren: $COUNT"

if [ ! -d "$SRC_DIR" ]; then
    die "Quellverzeichnis '$SRC_DIR' fehlt."
fi

available="$(find "$SRC_DIR" -maxdepth 1 -name 'test*.p' 2>/dev/null | wc -l | tr -d ' ')"
log_info "Gefundene Testprozeduren: $available"
if [ "$available" -lt "$COUNT" ]; then
    die "Es sind nur $available Testprozeduren vorhanden, benoetigt werden" \
        "$COUNT. Neu erzeugen mit: \"$PROGRES\" -b -p src/build/generate-tests.p" \
        "-param \"$SRC_DIR,$COUNT\""
fi

# ---------------------------------------------------------------------------
# Build-Verzeichnis vorbereiten
# ---------------------------------------------------------------------------

CURRENT_STEP="Build-Verzeichnis vorbereiten"
log_info "Leere Build-Verzeichnis '$BUILD_DIR' (Logdatei bleibt erhalten)."

for stale in "$RCODE_DIR" "$LIB_DIR" "$STATUS_DIR" "$RESULT"; do
    rm -rf "$stale" || die "'$stale' konnte nicht geloescht werden."
done

mkdir -p "$RCODE_DIR" "$LIB_DIR" "$STATUS_DIR" \
    || die "Build-Verzeichnisse konnten nicht angelegt werden."

# ---------------------------------------------------------------------------
# 1. Kompilieren
# ---------------------------------------------------------------------------

COMPILE_STATUS="$STATUS_DIR/compile.status"

run_cmd "Kompilieren von $SRC_DIR nach $RCODE_DIR" \
    "$PROGRES" -b -p src/build/compile-tests.p \
    -param "$SRC_DIR,$RCODE_DIR,$COMPILE_STATUS"
check_status_file "Kompilieren" "$COMPILE_STATUS"

rcount="$(find "$RCODE_DIR" -maxdepth 1 -name '*.r' 2>/dev/null | wc -l | tr -d ' ')"
log_info "Erzeugte r-Files: $rcount"
[ "$rcount" -ge "$COUNT" ] \
    || die "Es wurden nur $rcount r-Files erzeugt, benoetigt werden $COUNT."

# ---------------------------------------------------------------------------
# 2. Messung mit losen r-Files
# ---------------------------------------------------------------------------

RUN1_STATUS="$STATUS_DIR/run-rcode.status"

CURRENT_STEP="Messung 1: lose r-Files"
PROPATH="$(native_path "$ROOT/$RCODE_DIR")"
export PROPATH
log_info "PROPATH=$PROPATH"

run_cmd "Messung 1 (lose r-Files)" \
    "$PROGRES" -b -p src/build/runtests.p \
    -param "r-Files,$COUNT,$RESULT,$RUN1_STATUS"
check_status_file "Messung 1 (lose r-Files)" "$RUN1_STATUS"

# ---------------------------------------------------------------------------
# 3. Procedure Library erzeugen
# ---------------------------------------------------------------------------

CURRENT_STEP="Procedure Library erzeugen"
LIB_NATIVE="$(native_path "$ROOT/$LIB")"

run_cmd "Procedure Library $LIB anlegen" "$PROLIB" "$LIB_NATIVE" -create

CURRENT_STEP="r-Files in Procedure Library aufnehmen"
log_info "Nehme r-Files aus '$RCODE_DIR' in die Library auf."

add_rcode_to_library() (
    cd "$RCODE_DIR" || exit 1
    # In Bloecken hinzufuegen, damit die Kommandozeile nicht zu lang wird.
    find . -maxdepth 1 -name '*.r' \
        | xargs -n 100 "$PROLIB" "$LIB_NATIVE" -add
)

run_cmd "r-Files in Procedure Library aufnehmen" add_rcode_to_library

if [ ! -f "$LIB" ]; then
    die "Procedure Library '$LIB' wurde nicht erzeugt."
fi

run_cmd "Inhalt der Procedure Library pruefen" "$PROLIB" "$LIB_NATIVE" -list

# ---------------------------------------------------------------------------
# 4. Messung mit Procedure Library
# ---------------------------------------------------------------------------

RUN2_STATUS="$STATUS_DIR/run-library.status"

CURRENT_STEP="Messung 2: Procedure Library"
PROPATH="$LIB_NATIVE"
export PROPATH
log_info "PROPATH=$PROPATH"

run_cmd "Messung 2 (Procedure Library)" \
    "$PROGRES" -b -p src/build/runtests.p \
    -param "Procedure Library,$COUNT,$RESULT,$RUN2_STATUS"
check_status_file "Messung 2 (Procedure Library)" "$RUN2_STATUS"

# ---------------------------------------------------------------------------
# 5. Auswertung
# ---------------------------------------------------------------------------

CURRENT_STEP="Auswertung"

if [ ! -s "$RESULT" ]; then
    die "Ergebnisdatei '$RESULT' fehlt oder ist leer."
fi

log_info "===== Ergebnis ====="
awk -F';' '
    { ms[NR] = $3
      printf "%-20s %6d Prozeduren %8d ms\n", $1, $2, $3 }
    END {
      if (NR < 2) {
          print "Es liegen weniger als zwei Messungen vor." > "/dev/stderr"
          exit 1
      }
      if (ms[1] > 0)
          printf "Unterschied: %d ms (%.1f %%)\n", ms[1] - ms[2],
                 (ms[1] - ms[2]) * 100 / ms[1]
    }' "$RESULT" 2>&1 | tee -a "$LOG_FILE"

awk_status="${PIPESTATUS[0]}"
[ "$awk_status" -eq 0 ] || die "Auswertung fehlgeschlagen (Exit-Code $awk_status)."

CURRENT_STEP="Abschluss"
log_info "Rohdaten: $RESULT"
