/* generate-tests.p
   Erzeugt die Testprozeduren test0001.p .. testNNNN.p, die spaeter dynamisch
   genau einmal aufgerufen werden.

   Fehler beim Anlegen des Verzeichnisses oder beim Schreiben der Dateien
   werden protokolliert und in eine Statusdatei geschrieben.

   Session-Parameter (-param): <Zielverzeichnis>,<Anzahl>,<Statusdatei>
   Default: src/procedures,1000,<keine Statusdatei>                        */

DEFINE VARIABLE cTargetDir AS CHARACTER NO-UNDO INITIAL "src/procedures".
DEFINE VARIABLE iCount     AS INTEGER   NO-UNDO INITIAL 1000.
DEFINE VARIABLE cStatus    AS CHARACTER NO-UNDO.
DEFINE VARIABLE cParam     AS CHARACTER NO-UNDO.
DEFINE VARIABLE cName      AS CHARACTER NO-UNDO.
DEFINE VARIABLE cError     AS CHARACTER NO-UNDO.
DEFINE VARIABLE iCreated   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iMsg       AS INTEGER   NO-UNDO.
DEFINE VARIABLE i          AS INTEGER   NO-UNDO.

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
    cTargetDir = ENTRY(1, cParam).

IF NUM-ENTRIES(cParam) >= 2 AND ENTRY(2, cParam) <> "" THEN
    iCount = INTEGER(ENTRY(2, cParam)) NO-ERROR.

IF NUM-ENTRIES(cParam) >= 3 THEN
    cStatus = ENTRY(3, cParam).

MESSAGE "generate-tests.p: Ziel=" cTargetDir "Anzahl=" iCount.

MAIN-BLOCK:
DO ON ERROR UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON STOP  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON QUIT  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK:

    IF iCount = ? OR iCount <= 0 THEN DO:
        cError = "Ungueltige Anzahl: " + ENTRY(2, cParam).
        LEAVE MAIN-BLOCK.
    END.

    OS-CREATE-DIR VALUE(cTargetDir).
    IF OS-ERROR <> 0 THEN
        MESSAGE "Hinweis: OS-CREATE-DIR" cTargetDir "meldet OS-ERROR" OS-ERROR
                "(Verzeichnis existiert vermutlich bereits).".

    DO i = 1 TO iCount:
        cName = "test" + STRING(i, "9999").

        OUTPUT TO VALUE(cTargetDir + "/" + cName + ".p").
        PUT UNFORMATTED
            "/* " + cName + ".p */"                 SKIP
            "DEFINE VARIABLE i AS INTEGER NO-UNDO." SKIP
            "i = " + STRING(i) + "."                SKIP.
        OUTPUT CLOSE.

        iCreated = iCreated + 1.
    END.

    FILE-INFO:FILE-NAME = cTargetDir + "/test0001.p".
    IF FILE-INFO:FULL-PATHNAME = ? THEN
        cError = "Die Testprozeduren wurden nicht geschrieben ('" + cTargetDir + "').".

    CATCH oError AS Progress.Lang.Error:
        cError = "Unerwarteter Fehler: " + oError:GetMessage(1).
        DO iMsg = 1 TO oError:NumMessages:
            MESSAGE "FEHLER:" oError:GetMessage(iMsg).
        END.
    END CATCH.
END.

MESSAGE iCreated "Testprozeduren in" cTargetDir "erzeugt.".

IF cError <> "" THEN DO:
    MESSAGE "generate-tests.p FEHLGESCHLAGEN:" cError.
    RUN writeStatus ("ERROR: " + cError).
END.
ELSE
    RUN writeStatus ("OK: " + STRING(iCreated) + " Prozeduren erzeugt").
