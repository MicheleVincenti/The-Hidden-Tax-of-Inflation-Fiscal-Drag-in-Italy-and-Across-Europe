/*==============================================================================
00_master.do — Run the complete fiscal drag replication pipeline
==============================================================================
INSTRUCTIONS:

1. Open Stata.
2. Set the working directory to the folder containing this file and the
   required input files:
       - scaglioni_irpef_storico.csv
       - inflazione_istat_nic.csv
   Example:
       cd "path/to/fiscal_drag_analysis"
3. Run:
       do "00_master.do"

The pipeline covers tax years 2020–2024.

The MEF download step retrieves five annual administrative IRPEF datasets.
If an automatic download fails because the MEF URL structure has changed,
the corresponding raw CSV can be obtained from the MEF Open Data portal.
==============================================================================*/

clear all
set more off
set varabbrev off

di as result "=============================================================="
di as result "FISCAL DRAG REPLICATION PIPELINE — START"
di as result "=============================================================="

do "01_download_import_mef.do"
do "02_pulizia_merge.do"
do "03_calcolo_fiscal_drag.do"
do "04_aggregazione_output_tesi.do"
do "05_fiscal_drag_marginale.do"
do "06_simulazione_proposta.do"

di as result "=============================================================="
di as result "FISCAL DRAG REPLICATION PIPELINE — COMPLETED" 
di as result "=============================================================="
