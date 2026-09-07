/* compile-tests.p
   Kompiliert alle Testprozeduren eines Verzeichnisses in ein r-Code
   Verzeichnis. Die erzeugten r-Files werden entweder direkt (lose im
   PROPATH) oder verpackt in einer Procedure Library verwendet.

   Alle Fehler (fehlendes Quellverzeichnis, Compilerfehler, unerwartete
   Laufzeitfehler) werden protokolliert und zusaetzlich in eine Statusdatei
   geschrieben, damit das aufrufende Skript den Fehlerfall sicher erkennt.

   Session-Parameter (-param):
       <Quellverzeichnis>,<r-Code-Verzeichnis>,<Statusdatei>
   Default: src/procedures,build/rcode,<keine Statusdatei>                 */

DEFINE VARIABLE cSrcDir   AS CHARACTER NO-UNDO INITIAL "src/procedures".
DEFINE VARIABLE cOutDir   AS CHARACTER NO-UNDO INITIAL "build/rcode".
DEFINE VARIABLE cStatus   AS CHARACTER NO-UNDO.
DEFINE VARIABLE cParam    AS CHARACTER NO-UNDO.
DEFINE VARIABLE cFileName AS CHARACTER NO-UNDO.
DEFINE VARIABLE cFullName AS CHARACTER NO-UNDO.
DEFINE VARIABLE cAttr     AS CHARACTER NO-UNDO.
DEFINE VARIABLE iFiles    AS INTEGER   NO-UNDO.
DEFINE VARIABLE iErrors   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iMsg      AS INTEGER   NO-UNDO.
DEFINE VARIABLE cError    AS CHARACTER NO-UNDO.

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
    cSrcDir = ENTRY(1, cParam).

IF NUM-ENTRIES(cParam) >= 2 AND ENTRY(2, cParam) <> "" THEN
    cOutDir = ENTRY(2, cParam).

IF NUM-ENTRIES(cParam) >= 3 THEN
    cStatus = ENTRY(3, cParam).

MESSAGE "compile-tests.p: Quelle=" cSrcDir "Ziel=" cOutDir.

MAIN-BLOCK:
DO ON ERROR UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON STOP  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK
   ON QUIT  UNDO MAIN-BLOCK, LEAVE MAIN-BLOCK:

    IF SEARCH(cSrcDir + "/test00001.p") = ? THEN DO:
        cError = "Quellverzeichnis '" + cSrcDir + "' enthaelt keine Testprozeduren.".
        LEAVE MAIN-BLOCK.
    END.

    OS-CREATE-DIR VALUE(cOutDir).
    IF OS-ERROR <> 0 THEN
        MESSAGE "Hinweis: OS-CREATE-DIR" cOutDir "meldet OS-ERROR" OS-ERROR
                "(Verzeichnis existiert vermutlich bereits).".

    INPUT FROM OS-DIR(cSrcDir).
    REPEAT:
        IMPORT cFileName cFullName cAttr.

        IF cAttr <> "F" THEN NEXT.
        IF ENTRY(NUM-ENTRIES(cFileName, "."), cFileName, ".") <> "p" THEN NEXT.

        COMPILE VALUE(cFullName) SAVE INTO VALUE(cOutDir) NO-ERROR.

        IF COMPILER:ERROR THEN DO:
            iErrors = iErrors + 1.
            MESSAGE "FEHLER beim Kompilieren von" cFullName
                    "- Zeile" COMPILER:ERROR-ROW
                    "Spalte" COMPILER:ERROR-COLUMN.
            DO iMsg = 1 TO ERROR-STATUS:NUM-MESSAGES:
                MESSAGE "  " ERROR-STATUS:GET-MESSAGE(iMsg).
            END.
            IF cError = "" THEN
                cError = "Compilerfehler in " + cFullName.
        END.
        ELSE
            iFiles = iFiles + 1.
    END.
    INPUT CLOSE.

    IF iFiles = 0 AND cError = "" THEN
        cError = "Es wurde keine einzige Prozedur kompiliert.".

    CATCH oError AS Progress.Lang.Error:
        cError = "Unerwarteter Fehler: " + oError:GetMessage(1).
        DO iMsg = 1 TO oError:NumMessages:
            MESSAGE "FEHLER:" oError:GetMessage(iMsg).
        END.
    END CATCH.
END.

MESSAGE iFiles "Prozeduren aus" cSrcDir "nach" cOutDir "kompiliert,"
        iErrors "Fehler.".

IF cError <> "" THEN DO:
    MESSAGE "compile-tests.p FEHLGESCHLAGEN:" cError.
    RUN writeStatus ("ERROR: " + cError).
END.
ELSE
    RUN writeStatus ("OK: " + STRING(iFiles) + " Prozeduren kompiliert").
