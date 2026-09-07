/* runtests.p
   Ruft die Testprozeduren test0001.p .. testNNNN.p der Reihe nach dynamisch
   auf - jede genau einmal - und gibt am Schluss die dafuer benoetigte Zeit
   aus. Welche r-Files verwendet werden (lose im Verzeichnis oder in einer
   Procedure Library) entscheidet der uebergebene PROPATH-Eintrag.

   Jeder Fehlerfall (Prozedur nicht im PROPATH, Laufzeitfehler beim Aufruf,
   nicht schreibbare Ergebnisdatei) wird protokolliert und in eine
   Statusdatei geschrieben, damit ein Abbruch nicht unbemerkt bleibt.

   Der PROPATH-Eintrag wird als Parameter uebergeben und hier gesetzt, weil
   _progres.exe unter Windows die Umgebungsvariable PROPATH ignoriert.

   Session-Parameter (-param):
       <Bezeichnung>,<Anzahl>,<Ergebnisdatei>,<Statusdatei>,<PROPATH-Eintrag>
   Default: r-Code,1000,<keine Datei>,<keine Statusdatei>,<PROPATH unveraendert>

   Der PROPATH-Eintrag darf selbst Kommas enthalten; alle weiteren Eintraege
   ab Position 5 werden wieder zusammengefuegt.                            */

DEFINE VARIABLE cLabel     AS CHARACTER NO-UNDO INITIAL "r-Code".
DEFINE VARIABLE iCount     AS INTEGER   NO-UNDO INITIAL 1000.
DEFINE VARIABLE cResult    AS CHARACTER NO-UNDO.
DEFINE VARIABLE cStatus    AS CHARACTER NO-UNDO.
DEFINE VARIABLE cPropath   AS CHARACTER NO-UNDO.
DEFINE VARIABLE cParam     AS CHARACTER NO-UNDO.
DEFINE VARIABLE cProcedure AS CHARACTER NO-UNDO.
DEFINE VARIABLE iElapsed   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iCalled    AS INTEGER   NO-UNDO.
DEFINE VARIABLE iFailed    AS INTEGER   NO-UNDO.
DEFINE VARIABLE iMsg       AS INTEGER   NO-UNDO.
DEFINE VARIABLE i          AS INTEGER   NO-UNDO.
DEFINE VARIABLE cError     AS CHARACTER NO-UNDO.

/* Schreibt das Ergebnis fuer das aufrufende Skript weg. */
PROCEDURE writeStatus:
    DEFINE INPUT PARAMETER pcStatus AS CHARACTER NO-UNDO.

    IF cStatus = "" OR cStatus = ? THEN RETURN.

    OUTPUT TO VALUE(cStatus).
    PUT UNFORMATTED pcStatus SKIP.
    OUTPUT CLOSE.
END PROCEDURE.

cParam = SESSION:PARAMETER.

IF NUM-ENTRIES(cParam) >= 1 AND ENTRY(1, cParam) <> "" THEN
    cLabel = ENTRY(1, cParam).

IF NUM-ENTRIES(cParam) >= 2 AND ENTRY(2, cParam) <> "" THEN
    iCount = INTEGER(ENTRY(2, cParam)) NO-ERROR.

IF NUM-ENTRIES(cParam) >= 3 THEN
    cResult = ENTRY(3, cParam).

IF NUM-ENTRIES(cParam) >= 4 THEN
    cStatus = ENTRY(4, cParam).

/* Ab Eintrag 5 folgt der PROPATH-Eintrag - eventuell enthaltene Kommas
   werden wieder zusammengesetzt. */
DO i = 5 TO NUM-ENTRIES(cParam):
    cPropath = cPropath + (IF cPropath = "" THEN "" ELSE ",") + ENTRY(i, cParam).
END.

MESSAGE "runtests.p:" cLabel "- Anzahl" iCount.

/* _progres.exe uebernimmt die Umgebungsvariable PROPATH unter Windows nicht,
   deshalb wird der benoetigte Eintrag hier explizit vorangestellt. */
IF cPropath <> "" AND cPropath <> ? THEN DO:
    MESSAGE "Setze PROPATH-Eintrag:" cPropath.
    PROPATH = cPropath + "," + PROPATH.
END.

MESSAGE "PROPATH:" PROPATH.

MAIN-BLOCK:
DO ON ERROR UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON STOP  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON QUIT  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK:

    IF iCount = ? OR iCount <= 0 THEN DO:
        cError = "Ungueltige Anzahl: " + ENTRY(2, cParam).
        LEAVE MAIN-BLOCK.
    END.

    /* Vorab pruefen, ob der r-Code ueberhaupt gefunden wird - sonst
       laeuft die Messung ins Leere. */
    IF SEARCH("test0001.r") = ? AND SEARCH("test0001.p") = ? THEN DO:
        cError = "test0001.r ist ueber den PROPATH nicht erreichbar"
                 + (IF cPropath = "" THEN " (kein PROPATH-Eintrag uebergeben)"
                    ELSE " (Eintrag '" + cPropath + "')") + ".".
        LEAVE MAIN-BLOCK.
    END.

    ETIME(YES).

    DO i = 1 TO iCount:
        cProcedure = "test" + STRING(i, "9999") + ".p".

        RUN VALUE(cProcedure) NO-ERROR.

        IF ERROR-STATUS:ERROR THEN DO:
            iFailed = iFailed + 1.
            MESSAGE "FEHLER beim Aufruf von" cProcedure.
            DO iMsg = 1 TO ERROR-STATUS:NUM-MESSAGES:
                MESSAGE "  " ERROR-STATUS:GET-MESSAGE(iMsg).
            END.
            IF cError = "" THEN
                cError = "Aufruf von " + cProcedure + " fehlgeschlagen: "
                         + ERROR-STATUS:GET-MESSAGE(1).
            /* Nach dem ersten Fehler abbrechen - die Messung waere
               ohnehin nicht mehr aussagekraeftig. */
            LEAVE.
        END.

        iCalled = iCalled + 1.
    END.

    iElapsed = ETIME.

    CATCH oError AS Progress.Lang.Error:
        cError = "Unerwarteter Fehler: " + oError:GetMessage(1).
        DO iMsg = 1 TO oError:NumMessages:
            MESSAGE "FEHLER:" oError:GetMessage(iMsg).
        END.
    END CATCH.
END.

MESSAGE cLabel ":" iCalled "von" iCount "Prozeduren dynamisch aufgerufen in"
        iElapsed "ms ("
        (IF iCalled > 0 THEN iElapsed / iCalled ELSE 0) "ms pro Aufruf),"
        iFailed "Fehler.".

IF cError = "" AND iCalled <> iCount THEN
    cError = "Es wurden nur " + STRING(iCalled) + " von " + STRING(iCount)
             + " Prozeduren aufgerufen.".

IF cError = "" THEN DO:
    IF cResult <> "" AND cResult <> ? THEN DO:
        OUTPUT TO VALUE(cResult) APPEND.
        PUT UNFORMATTED cLabel ";" iCount ";" iElapsed SKIP.
        OUTPUT CLOSE.

        FILE-INFO:FILE-NAME = cResult.
        IF FILE-INFO:FULL-PATHNAME = ? THEN
            cError = "Ergebnisdatei '" + cResult + "' konnte nicht geschrieben werden.".
    END.
END.

IF cError <> "" THEN DO:
    MESSAGE "runtests.p FEHLGESCHLAGEN:" cError.
    RUN writeStatus ("ERROR: " + cError).
END.
ELSE
    RUN writeStatus ("OK: " + STRING(iCalled) + " Aufrufe in "
                     + STRING(iElapsed) + " ms").
