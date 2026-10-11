@echo off
rem RECUIRE LE VAL — apres chaque export depuis MB (World > "Export the world..." dans D:\TheStoryOfKnil\mondes).
rem Double-clic. Ferme le jeu avant (pas l'editeur Godot) : la cuisson reecrit cuit\monde_knil.
rem 1. importe ce que MB a exporte  2. cuit la carte (~8 min)  3. verifie la collision  4. dit si tout va bien.
chcp 65001 >nul
setlocal
set GODOT=C:\Users\jorda\Desktop\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
set MONDE=res://mondes/monde_knil.mbworld/world.json
set JOURNAL=D:\TheStoryOfKnil\cuit\derniere_cuisson.txt
cd /d D:\TheStoryOfKnil
if not exist "D:\TheStoryOfKnil\mondes\monde_knil.mbworld\world.json" (
	echo.
	echo   Pas d'export trouve : dans MB, World ^> "Export the world..." et choisis le dossier D:\TheStoryOfKnil\mondes
	echo.
	pause
	exit /b 1
)
rem L'export range DANS le dossier du monde (on a choisi mondes\monde_knil.mbworld au lieu de mondes) : on recuirait
rem l'ANCIEN monde sans le voir (vu le 11 octobre 2026).
if exist "D:\TheStoryOfKnil\mondes\monde_knil.mbworld\monde_knil.mbworld\world.json" (
	echo.
	echo   L'export de MB est DANS l'ancien : mondes\monde_knil.mbworld\monde_knil.mbworld
	echo   Dans MB, World ^> "Export the world..." : choisis le dossier D:\TheStoryOfKnil\mondes ^(pas monde_knil.mbworld^).
	echo   Ou remplace mondes\monde_knil.mbworld par le dossier qui est dedans, puis relance.
	echo.
	pause
	exit /b 1
)
if not exist "D:\TheStoryOfKnil\cuit" mkdir "D:\TheStoryOfKnil\cuit"
echo.
echo   1/3  Import de l'export de MB...
"%GODOT%" --headless --path D:\TheStoryOfKnil --import > "%JOURNAL%" 2>&1
echo   2/3  Cuisson de la carte (environ 8 minutes)...
"%GODOT%" --headless --path D:\TheStoryOfKnil res://tools/cuisson/cuire.tscn -- --monde=%MONDE% >> "%JOURNAL%" 2>&1
if errorlevel 1 (
	echo.
	echo   ECHEC DE LA CUISSON — le detail est dans %JOURNAL%
	findstr /C:"REFUS" /C:"ERROR" "%JOURNAL%"
	echo.
	pause
	exit /b 1
)
echo   3/3  Verification de la collision...
"%GODOT%" --headless --path D:\TheStoryOfKnil res://tests/sonde_collision.tscn -- --monde=res://cuit/monde_knil --points=auto >> "%JOURNAL%" 2>&1
if errorlevel 1 (
	echo.
	echo   ATTENTION : la collision cuite s'ecarte du rendu par endroits — detail dans %JOURNAL%
	echo.
	pause
	exit /b 1
)
echo.
echo   C'EST PRET. Lance le jeu : la nouvelle carte y est.
findstr /C:"avertissement" /C:"warning" /C:"tiles_missing" "%JOURNAL%"
echo.
pause
