/*==============================================================================
SCRIPT 3 di 4 — CALCOLO IMPOSTA TEORICA E FISCAL DRAG (metodo controfattuale)
==============================================================================
Input:  dati_puliti/mef_panel_con_inflazione.dta
        dati_puliti/scaglioni_irpef.dta

Questo è lo script CENTRALE della tesi: implementa
  (a) un programma Stata che calcola l'imposta teorica multi-scaglione dato
      un reddito e una tabella di scaglioni/aliquote
  (b) lo SCENARIO REALE: applica gli scaglioni effettivamente in vigore
      nell'anno t al reddito osservato nell'anno t
  (c) lo SCENARIO CONTROFATTUALE INDICIZZATO: applica gli scaglioni
      dell'anno BASE (2012), rivalutati per l'inflazione cumulata fino
      all'anno t, al reddito osservato nell'anno t
  (d) il FISCAL DRAG = differenza tra l'aliquota media nello scenario reale
      e quella nello scenario controfattuale indicizzato

Formule implementate (vedi spiegazione testuale fornita separatamente):
  ETR_reale(t)        = T_reale(Y_t) / Y_t
  ETR_indicizzato(t)  = T_indicizzato(Y_t) / Y_t
  FiscalDrag(t)       = ETR_reale(t) - ETR_indicizzato(t)

dove T_indicizzato applica al reddito Y_t gli scaglioni del 2012 moltiplicati
per (indice_NIC_t / indice_NIC_2012), cioè gli scaglioni CHE SAREBBERO STATI
in vigore nel periodo t se fossero stati indicizzati all'inflazione dal 2012
in avanti (anno base = 2012, primo anno disponibile nel panel MEF).
==============================================================================*/

use "dati_puliti/mef_panel_con_inflazione.dta", clear

* Anno base per il controfattuale: 2020 (primo anno del periodo di analisi
* della tesi, 2020-2024). Scegliere come anno base il primo anno della
* finestra di analisi è la scelta standard in letteratura quando si vuole
* misurare "quanto fiscal drag si è accumulato durante il periodo studiato",
* piuttosto che rispetto a un anno arbitrario precedente.
local anno_base = 2020

/*------------------------------------------------------------------------------
PROGRAMMA 1: calcola l'imposta teorica multi-scaglione
-------------------------------------------------------------------------------
Sintassi:  calcola_imposta reddito, scaglioni(nome_matrice)
La matrice scaglioni ha 3 colonne: soglia_min, soglia_max (= . se nessun tetto),
aliquota. Ogni riga = uno scaglione, ordinato dal piu' basso al piu' alto.
Il programma restituisce in r(imposta) l'imposta totale dovuta.
------------------------------------------------------------------------------*/

cap program drop calcola_imposta_scalare
program define calcola_imposta_scalare, rclass
    args reddito mat_scaglioni

    if `reddito' <= 0 {
        return scalar imposta = 0
        exit
    }

    local n_righe = rowsof(`mat_scaglioni')
    local imposta_tot = 0
    local reddito_residuo = `reddito'

    forvalues i = 1/`n_righe' {
        local s_min = el(`mat_scaglioni', `i', 1)
        local s_max = el(`mat_scaglioni', `i', 2)
        local aliq  = el(`mat_scaglioni', `i', 3)

        if `s_max' == . {
            local ampiezza_scaglione = `reddito_residuo'
        }
        else {
            local ampiezza_scaglione = min(`s_max' - `s_min', `reddito_residuo')
        }

        if `ampiezza_scaglione' > 0 {
            local imposta_tot = `imposta_tot' + `ampiezza_scaglione' * `aliq'
            local reddito_residuo = `reddito_residuo' - `ampiezza_scaglione'
        }

        if `reddito_residuo' <= 0 {
            continue, break
        }
    }

    return scalar imposta = `imposta_tot'
end

/*------------------------------------------------------------------------------
PASSO 1: costruzione delle matrici di scaglioni per ciascun anno (scenario
reale) e per il controfattuale indicizzato
------------------------------------------------------------------------------*/

* --- 1a. Carica la tabella scaglioni e trasformala in matrici per anno ---
preserve
    use "dati_puliti/scaglioni_irpef.dta", clear
    levelsof anno_imposta, local(anni_scaglioni)
restore

* Funzione di appoggio: crea una matrice Stata "scagl_AAAA" con le colonne
* (soglia_min, soglia_max, aliquota) per l'anno AAAA, leggendo dal dataset
* scaglioni_irpef.dta

cap program drop crea_matrice_scaglioni
program define crea_matrice_scaglioni
    args anno nome_matrice

    preserve
        use "dati_puliti/scaglioni_irpef.dta", clear
        keep if anno_imposta == `anno'
        sort scaglione_num
        mkmat soglia_min soglia_max aliquota, matrix(`nome_matrice')
    restore
end

* Crea le matrici reali per ogni anno presente nel panel
levelsof anno_imposta, local(anni_panel)
foreach a of local anni_panel {
    crea_matrice_scaglioni `a' scagl_reale_`a'
}

* --- 1b. Matrice degli scaglioni BASE (anno_base = 2012), da usare come
*     punto di partenza per il controfattuale indicizzato ---
mat scagl_base = scagl_reale_`anno_base'

/*------------------------------------------------------------------------------
PASSO 2: per ciascun anno t, costruisci la matrice INDICIZZATA
  scagl_indic_t = scagl_base * (indice_NIC_t / indice_NIC_anno_base)
(le aliquote restano identiche, vengono rivalutate solo le soglie in euro)
------------------------------------------------------------------------------*/

* Recupera l'indice NIC dell'anno base
preserve
    use "dati_puliti/inflazione_nic.dta", clear
    keep if anno_imposta == `anno_base'
    local indice_base = indice_nic_base2020[1]
restore
di as text "Indice NIC dell'anno base (`anno_base'): `indice_base'"

foreach a of local anni_panel {
    preserve
        use "dati_puliti/inflazione_nic.dta", clear
        keep if anno_imposta == `a'
        local indice_t = indice_nic_base2020[1]
    restore

    local fattore_rivalutazione = `indice_t' / `indice_base'

    mat scagl_indic_`a' = scagl_base
    * Rivaluta solo le colonne 1 e 2 (soglie), NON la colonna 3 (aliquote)
    forvalues r = 1/`=rowsof(scagl_base)' {
        mat scagl_indic_`a'[`r',1] = scagl_base[`r',1] * `fattore_rivalutazione'
        if scagl_base[`r',2] != . {
            mat scagl_indic_`a'[`r',2] = scagl_base[`r',2] * `fattore_rivalutazione'
        }
    }
    di as text "Anno `a': fattore di rivalutazione scaglioni = `fattore_rivalutazione'"
}

/*------------------------------------------------------------------------------
PASSO 3: applica le due matrici (reale e indicizzata) al reddito osservato
in ciascuna cella del panel, per calcolare T_reale e T_indicizzato
-------------------------------------------------------------------------------
NOTA: usiamo redd_imp_medio_oss (il reddito imponibile medio osservato nella
cella) come base imponibile su cui applicare gli scaglioni teorici. Questo è
necessario perché il MEF non fornisce il reddito imponibile individuale, solo
l'aggregato per cella; usiamo quindi il valore medio come "reddito
rappresentativo" della cella (approssimazione standard nei lavori che usano
dati aggregati per fascia, vedi Immervoll 2005 per la stessa scelta).
------------------------------------------------------------------------------*/

gen T_reale = .
gen T_indicizzato = .

* NOTA SUI TEMPI DI ESECUZIONE: il loop seguente itera riga per riga
* (forvalues riga = 1/_N) per chiarezza didattica — ogni riga richiama il
* programma calcola_imposta_scalare con la matrice di scaglioni corretta
* per il suo anno. Con un panel di poche migliaia di righe (come quello
* MEF: ~13 anni x ~30 classi di reddito x ~5 classi di età = circa 2.000
* righe) il tempo di esecuzione è di pochi minuti. Se in futuro userai un
* dataset a livello individuale (es. EU-SILC o IBF, con centinaia di
* migliaia di osservazioni), questo approccio andrebbe vettorizzato:
* è possibile farlo creando una variabile per ciascuna soglia/aliquota
* via merge m:1 anno_imposta, e poi calcolando l'imposta con formule gen
* invece che con il programma riga-per-riga. Per il dataset MEF aggregato
* usato qui, l'approccio attuale è sufficientemente efficiente.

quietly levelsof anno_imposta, local(anni_panel)
foreach a of local anni_panel {
    count if anno_imposta == `a' & redd_imp_medio_oss != . & redd_imp_medio_oss > 0
    local n_celle = r(N)
    di as text "Calcolo imposta teorica per l'anno `a': `n_celle' celle valide"

    forvalues riga = 1/`=_N' {
        if anno_imposta[`riga'] == `a' & redd_imp_medio_oss[`riga'] != . & redd_imp_medio_oss[`riga'] > 0 {
            local y = redd_imp_medio_oss[`riga']

            calcola_imposta_scalare `y' scagl_reale_`a'
            replace T_reale = `r(imposta)' in `riga'

            calcola_imposta_scalare `y' scagl_indic_`a'
            replace T_indicizzato = `r(imposta)' in `riga'
        }
    }
}

label var T_reale "Imposta teorica con scaglioni REALI dell'anno t (su redd. imp. medio cella)"
label var T_indicizzato "Imposta teorica con scaglioni INDICIZZATI da `anno_base' (controfattuale)"

/*------------------------------------------------------------------------------
PASSO 4: calcolo delle aliquote medie effettive teoriche e del FISCAL DRAG
------------------------------------------------------------------------------*/

gen ETR_reale_teor = T_reale / redd_imp_medio_oss if redd_imp_medio_oss > 0
gen ETR_indic_teor = T_indicizzato / redd_imp_medio_oss if redd_imp_medio_oss > 0

gen fiscal_drag = ETR_reale_teor - ETR_indic_teor
label var ETR_reale_teor "Aliquota media teorica, scenario REALE"
label var ETR_indic_teor "Aliquota media teorica, scenario INDICIZZATO (controfattuale)"
label var fiscal_drag "Fiscal drag individuale: ETR_reale - ETR_indicizzato (punti percentuali se *100)"

* Versione in punti percentuali, più leggibile nelle tabelle della tesi
gen fiscal_drag_pp = fiscal_drag * 100
label var fiscal_drag_pp "Fiscal drag in punti percentuali"

* Gettito aggiuntivo in euro dovuto al fiscal drag, per cella
gen gettito_aggiuntivo_fd = (T_reale - T_indicizzato) * n_contribuenti
label var gettito_aggiuntivo_fd "Gettito aggiuntivo aggregato dovuto al fiscal drag nella cella (euro)"

compress
save "dati_puliti/mef_panel_fiscal_drag.dta", replace

di as result "=============================================================="
di as result "FISCAL DRAG CALCOLATO E SALVATO: dati_puliti/mef_panel_fiscal_drag.dta"
di as result "=============================================================="

* Anteprima rapida: fiscal drag medio per anno (non pesato)
preserve
    collapse (mean) fiscal_drag_pp (sum) gettito_aggiuntivo_fd n_contribuenti, by(anno_imposta)
    list anno_imposta fiscal_drag_pp gettito_aggiuntivo_fd, sep(0)
restore
