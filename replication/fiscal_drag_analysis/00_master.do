/*==============================================================================
00_MASTER.do — Lancia l'intera pipeline di calcolo del fiscal drag
==============================================================================
ISTRUZIONI:
1. Apri Stata
2. Imposta la cartella di lavoro sulla cartella che contiene questo file e
   i due CSV (scaglioni_irpef_storico.csv, inflazione_istat_nic.csv):
       cd "percorso/della/tua/cartella/fiscal_drag"
3. Esegui questo file: do "00_master.do"

Tempo stimato: il download dei 13 file CSV dal MEF può richiedere alcuni
minuti a seconda della connessione. Se un download fallisce, lo script lo
segnala e tu puoi scaricare manualmente quell'anno dal link indicato.
==============================================================================*/

clear all
set more off
set varabbrev off

di as result "=============================================================="
di as result "PIPELINE FISCAL DRAG — Avvio"
di as result "=============================================================="

do "01_download_import_mef.do"
do "02_pulizia_merge.do"
do "03_calcolo_fiscal_drag.do"
do "04_aggregazione_output_tesi.do"
do "05_fiscal_drag_marginale.do"

di as result "=============================================================="
di as result "PIPELINE COMPLETATA"
di as result "=============================================================="
