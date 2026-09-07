/*==============================================================================
SCRIPT 2 di 4 — PULIZIA CLASSI DI REDDITO E MERGE CON SCAGLIONI/INFLAZIONE
==============================================================================
Input:  dati_puliti/mef_calcolo_irpef_panel.dta  (creato dallo script 1)
        scaglioni_irpef_storico.csv               (fornito a parte)
        inflazione_istat_nic.csv                   (fornito a parte)

Questo script:
1. Estrae i limiti numerici (min/max) dalla stringa "classe_reddito_str"
   (es. "da 15.000 a 20.000" -> min=15000, max=20000)
2. Calcola il reddito medio osservato in ciascuna cella (= ammontare / frequenza)
   che useremo come "reddito rappresentativo" della classe
3. Importa e fa il merge con la tabella degli scaglioni IRPEF storici
4. Importa e fa il merge con la serie di inflazione ISTAT (NIC)
5. Calcola l'aliquota media effettiva (ETR) realmente osservata nei dati MEF
==============================================================================*/

use "dati_puliti/mef_calcolo_irpef_panel.dta", clear

/*------------------------------------------------------------------------------
PASSO 1: Parsing della stringa "classe_reddito_str"
-------------------------------------------------------------------------------
I valori tipici osservati nel CSV MEF sono del tipo:
  "minore di -1.000"
  "da -1.000 a 0"
  "zero"
  "da 0 a 1.000"
  "da 1.000 a 1.500"
  ...
  "da 100.000 a 120.000"
  "oltre 300.000"

Creiamo due variabili numeriche: classe_min e classe_max (in euro).
Per le code apertе ("minore di", "oltre") usiamo missing su un lato, che poi
gestiamo a parte nelle analisi (tipicamente si escludono dalle elaborazioni
di fiscal drag perché non hanno punto medio ben definito, oppure si fissa
una convenzione, vedi nota sotto).
------------------------------------------------------------------------------*/

gen str100 tmp = lower(classe_reddito_str)
gen tmp2 = subinstr(tmp, ".", "", .)   // rimuove punti delle migliaia nella stringa

gen classe_min = .
gen classe_max = .
gen byte tipo_classe = .   // 1=chiusa, 2=coda sinistra aperta, 3=coda destra aperta, 4=zero

* Caso "zero"
replace classe_min = 0 if tmp2 == "zero"
replace classe_max = 0 if tmp2 == "zero"
replace tipo_classe = 4 if tmp2 == "zero"

* Caso "minore di X"  (coda sinistra aperta) — riconosciuto PRIMA del caso
* generale "da X a Y" perché la stringa "minore di" non contiene " a "
replace classe_max = real(subinstr(tmp2, "minore di ", "", .)) ///
    if strpos(tmp2, "minore di") > 0 & tipo_classe == .
replace tipo_classe = 2 if strpos(tmp2, "minore di") > 0 & tipo_classe == .

* Caso "oltre X" (coda destra aperta)
replace classe_min = real(subinstr(tmp2, "oltre ", "", .)) ///
    if strpos(tmp2, "oltre") > 0 & tipo_classe == .
replace tipo_classe = 3 if strpos(tmp2, "oltre") > 0 & tipo_classe == .

* Caso generale "da X a Y" — applicato SOLO alle righe non ancora classificate
gen str100 tmp3 = tmp2
replace tmp3 = substr(tmp3, 4, .) if strpos(tmp3, "da ") == 1 & tipo_classe == .
gen pos_a = strpos(tmp3, " a ")
replace classe_min = real(substr(tmp3, 1, pos_a - 1)) if pos_a > 0 & tipo_classe == .
replace classe_max = real(substr(tmp3, pos_a + 3, .)) if pos_a > 0 & tipo_classe == .
replace tipo_classe = 1 if pos_a > 0 & tipo_classe == .
* Se pos_a == 0 per qualche riga non ancora classificata, resta missing e
* verrà segnalata dal controllo di qualità subito sotto.

drop tmp tmp2 tmp3 pos_a

label define tipoclasse 1 "Chiusa (da X a Y)" 2 "Aperta a sinistra (minore di X)" ///
    3 "Aperta a destra (oltre X)" 4 "Zero"
label values tipo_classe tipoclasse
label var tipo_classe "Tipo di classe di reddito (per gestione code aperte)"

* Controllo: segnala eventuali righe non riconosciute da nessuna delle
* regole sopra (dovrebbero essere zero; se non lo sono, ispeziona
* manualmente i valori di classe_reddito_str non classificati)
count if tipo_classe == .
if r(N) > 0 {
    di as error "ATTENZIONE: `r(N)' righe con classe di reddito non riconosciuta dal parsing."
    di as error "Valori non riconosciuti:"
    tab classe_reddito_str if tipo_classe == .
}

* Punto medio della classe (rappresentativo) — per le classi chiuse
gen classe_midpoint = (classe_min + classe_max) / 2 if classe_min != . & classe_max != .

label var classe_min "Limite inferiore classe di reddito (euro)"
label var classe_max "Limite superiore classe di reddito (euro)"
label var classe_midpoint "Punto medio della classe di reddito (euro)"

/*------------------------------------------------------------------------------
PASSO 2: Reddito medio OSSERVATO in ciascuna cella
-------------------------------------------------------------------------------
Più robusto del punto medio teorico: dividiamo l'ammontare aggregato del
reddito complessivo per il numero di contribuenti con frequenza positiva.
Questo è il valore che useremo come "reddito rappresentativo" per calcolare
l'aliquota media effettiva e il fiscal drag.
------------------------------------------------------------------------------*/

gen redd_medio_oss = redd_compl_amm / redd_compl_freq if redd_compl_freq > 0
gen redd_imp_medio_oss = redd_imponibile_amm / redd_imponibile_freq if redd_imponibile_freq > 0
label var redd_medio_oss "Reddito complessivo medio osservato nella cella (euro)"
label var redd_imp_medio_oss "Reddito imponibile medio osservato nella cella (euro)"

/*------------------------------------------------------------------------------
PASSO 3: Aliquota media effettiva (ETR) REALMENTE OSSERVATA nei dati MEF
-------------------------------------------------------------------------------
ETR_osservata = Imposta netta aggregata / Reddito complessivo aggregato
(per cella classe_reddito x classe_eta x anno)

Usiamo l'imposta NETTA (dopo le detrazioni) perché è la misura più vicina al
carico fiscale effettivo sostenuto dal contribuente. Se preferisci l'aliquota
sul "prelievo lordo" prima delle detrazioni, usa imposta_lorda_amm al posto
di imposta_netta_amm.
------------------------------------------------------------------------------*/

gen ETR_osservata = imposta_netta_amm / redd_compl_amm if redd_compl_amm > 0
label var ETR_osservata "Aliquota media effettiva osservata (imposta netta / reddito compl.)"

* Aliquota media sul reddito imponibile (alternativa, spesso usata nei paper OCSE)
gen ETR_su_imponibile = imposta_lorda_amm / redd_imponibile_amm if redd_imponibile_amm > 0
label var ETR_su_imponibile "Aliquota media su imponibile (imposta lorda / reddito imponibile)"

/*------------------------------------------------------------------------------
PASSO 4: Import e merge con la tabella degli scaglioni IRPEF storici
-------------------------------------------------------------------------------
Il file scaglioni_irpef_storico.csv ha struttura:
  anno;scaglione_num;soglia_min;soglia_max;aliquota
con una riga per ciascuno scaglione, per ciascun anno (es. 5 righe nel 2020,
4 righe nel 2022, 3 righe nel 2024).

NON facciamo un merge diretto m:1 su anno, perché ogni anno ha piu' scaglioni:
costruiamo invece un PROGRAMMA che calcola l'imposta teorica (vedi script 3),
e qui ci limitiamo a salvare la tabella degli scaglioni in formato Stata
così il programma possa richiamarla.
------------------------------------------------------------------------------*/

preserve
    import delimited "scaglioni_irpef_storico.csv", delimiter(";") clear varnames(1) ///
        encoding("utf-8")
    * La colonna soglia_max contiene "." per lo scaglione piu' alto (no tetto)
    destring soglia_max, replace force
    destring soglia_min, replace force
    destring aliquota, replace force
    rename anno anno_imposta
    label var anno_imposta "Anno d'imposta"
    label var scaglione_num "Numero dello scaglione (1 = piu' basso)"
    label var soglia_min "Soglia minima dello scaglione (euro)"
    label var soglia_max "Soglia massima dello scaglione (euro, mancante = nessun tetto)"
    label var aliquota "Aliquota marginale dello scaglione"
    compress
    save "dati_puliti/scaglioni_irpef.dta", replace
restore

/*------------------------------------------------------------------------------
PASSO 5: Import e merge con la serie di inflazione ISTAT (NIC)
-------------------------------------------------------------------------------
Il file inflazione_istat_nic.csv ha struttura:
  anno;inflazione_pct;indice_nic_base2020
con indice_nic_base2020 = indice NIC a base 100 nel 2020, ottenuto componendo
le variazioni percentuali annue ufficiali ISTAT.
------------------------------------------------------------------------------*/

preserve
    import delimited "inflazione_istat_nic.csv", delimiter(";") clear varnames(1) ///
        encoding("utf-8")
    rename anno anno_imposta
    destring inflazione_pct, replace force
    destring indice_nic_base2020, replace force
    label var anno_imposta "Anno"
    label var inflazione_pct "Inflazione media annua NIC (%, fonte ISTAT)"
    label var indice_nic_base2020 "Indice NIC, base 2020=100"
    compress
    save "dati_puliti/inflazione_nic.dta", replace
restore

* Merge dell'inflazione nel panel principale (m:1 su anno_imposta)
merge m:1 anno_imposta using "dati_puliti/inflazione_nic.dta"
tab _merge
* Tutte le osservazioni del panel devono trovare corrispondenza (_merge==3);
* se vedi _merge==1, significa che mancano anni nel file inflazione_istat_nic.csv
drop _merge

compress
save "dati_puliti/mef_panel_con_inflazione.dta", replace

di as result "=============================================================="
di as result "Panel con inflazione salvato: dati_puliti/mef_panel_con_inflazione.dta"
di as result "Tabella scaglioni salvata:    dati_puliti/scaglioni_irpef.dta"
di as result "=============================================================="

* Controllo rapido di qualita': quante celle hanno reddito medio osservato
* coerente con la classe dichiarata (devono cadere dentro [classe_min, classe_max])
count if redd_medio_oss < classe_min | redd_medio_oss > classe_max
di as text "Celle con reddito medio fuori dal range dichiarato: `r(N)' (controllarle manualmente)"
