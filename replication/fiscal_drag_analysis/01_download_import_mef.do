/*==============================================================================
SCRIPT 1 di 4 — DOWNLOAD E IMPORT DATI MEF (Dipartimento delle Finanze)
==============================================================================
Tesi: Calcolo del Fiscal Drag in Italia (2020 - 2024)
Fonte: MEF - Dipartimento delle Finanze, Open Data Dichiarazioni IRPEF
       https://www1.finanze.gov.it/finanze/analisi_stat/public/index.php?opendata=yes
       Classificazione: "Classi di reddito e Classi di Età"
       Tematica: "Calcolo dell'IRPEF"

Questo script:
1. Scarica i CSV MEF per ogni anno d'imposta (2020-2024) -- file
   "cla_anno_calcolo_irpef_AAAA.csv"
2. Pulisce la formattazione numerica italiana (punto = separatore migliaia)
3. Rinomina le variabili in modo analitico
4. Appende tutti gli anni in un unico panel
5. Salva il dataset pulito: mef_calcolo_irpef_panel.dta

NOTA IMPORTANTE: gli URL sotto sono stati verificati e sono validi al
20/06/2026. Il MEF aggiorna ogni anno la sezione Open Data, ma la struttura
del parametro "?d=" potrebbe cambiare nel tempo: se un link non funziona,
vai su https://www1.finanze.gov.it/finanze/analisi_stat/public/index.php?opendata=yes
filtra per "Classi di reddito" + "Classi di età" e per l'anno desiderato,
e copia il nuovo link "Scarica CSV".
==============================================================================*/

clear all
set more off
cap mkdir "mef_raw"
cap mkdir "dati_puliti"

* ---------------------------------------------------------------------------
* PASSO 1: lista degli URL diretti per ciascun anno d'imposta
* PERIODO ANALISI TESI: 2020-2024 (5 anni d'imposta).
* Nota: l'anno d'imposta 2025 non è ancora disponibile a giugno 2026 perché
* il MEF pubblica le statistiche con un anno di ritardo (le dichiarazioni
* per i redditi 2025 si presentano nel 2026 e vengono elaborate dal MEF
* nel 2027). 2024 è quindi l'anno più recente disponibile.
* ---------------------------------------------------------------------------

local anni "2020 2021 2022 2023 2024"

* Base URL comune (verificata dal sito MEF)
local base_url "https://www1.finanze.gov.it/finanze/analisi_stat/public/v_4_0_0/contenuti"

tempname memhold
postfile `memhold' str4 anno_imposta str200 esito using "dati_puliti/log_download.dta", replace

foreach a of local anni {
    local url "`base_url'/cla_anno_calcolo_irpef_`a'.csv?d=1615465800"
    local out "mef_raw/calcolo_irpef_`a'.csv"

    di as text "Scaricando anno d'imposta `a' ..."
    cap copy "`url'" "`out'", replace

    if _rc == 0 {
        post `memhold' ("`a'") ("OK")
        di as result "  -> OK: `out'"
    }
    else {
        post `memhold' ("`a'") ("FALLITO - rc=`=_rc'")
        di as error "  -> FALLITO per l'anno `a' (rc=`=_rc'). Scarica manualmente da:"
        di as error "     `url'"
    }
}
postclose `memhold'

use "dati_puliti/log_download.dta", clear
list, sep(0)

/*==============================================================================
PASSO 2: import e pulizia di ciascun file CSV
==============================================================================
Struttura reale del CSV MEF (verificata sul file 2024, identica per tutti
gli anni 2012-2024):

Colonna 1:  "Classi di reddito complessivo in euro"   (stringa, es. "da 15.000 a 20.000")
Colonna 2:  "Classi di eta'"                            (stringa, es. "25 - 44")
Colonna 3:  Numero contribuenti
Colonne successive: per ciascuna voce IRPEF, una coppia
            [Voce - Frequenza] e [Voce - Ammontare in euro]
Le voci, nell'ordine esatto in cui appaiono nel CSV "calcolo_irpef":
  - Reddito complessivo
  - Reddito complessivo al netto della cedolare secca
  - Deduzione per abitazione principale
  - Oneri deducibili
  - Reddito imponibile
  - Imposta lorda
  - Detrazioni d'imposta
  - Imposta netta
  - Crediti d'imposta e ritenute
  - Differenza
  - Eccedenza d'imposta risultante dalla precedente dichiarazione
  - Acconti versati
  - Irpef a credito
  - Irpef a debito

I numeri nel CSV usano il formato italiano: punto come separatore delle
migliaia, nessun separatore decimale (i valori sono interi, in euro).
Esempio: "11.644.090" = 11644090 euro.
==============================================================================*/

foreach a of local anni {
    local f "mef_raw/calcolo_irpef_`a'.csv"
    capture confirm file "`f'"
    if _rc != 0 {
        di as error "File mancante per l'anno `a' - salto. Scaricalo manualmente."
        continue
    }

    di as text "Importazione e pulizia anno `a' ..."

    import delimited "`f'", delimiter(";") encoding("utf-8") clear varnames(nonames) ///
        stringcols(_all)

    * La prima riga del file è l'intestazione testuale (nomi di colonna del
    * MEF) ed è stata importata come prima osservazione: va eliminata.
    drop in 1

    * Le prime due colonne sono testuali (classe di reddito, classe di eta')
    rename v1 classe_reddito_str
    rename v2 classe_eta_str

    * Le colonne numeriche dalla 3 in poi vanno pulite dal formato italiano
    * (rimuovere i punti delle migliaia) e convertite in numerico.
    * NB: usiamo destring con la sintassi "ignore" per rimuovere il punto,
    * poi convertiamo a double.

    * Conta quante colonne totali ha il file (variano leggermente se in
    * qualche anno manca/si aggiunge una voce) e pulisce tutte le colonne
    * numeriche dalla v3 in poi
    quietly describe
    local n_vars = r(k)

    forvalues j = 3/`n_vars' {
        cap confirm string variable v`j'
        if _rc == 0 {
            replace v`j' = subinstr(v`j', ".", "", .)
            replace v`j' = "" if v`j' == ""
            destring v`j', replace force
        }
    }

    * Rinomina analitica delle variabili numeriche, in base all'ordine
    * dichiarato dal MEF (vedi intestazione del CSV originale).
    * I rename sono protetti con "cap" perché alcuni anni storici potrebbero
    * avere un numero di colonne leggermente diverso (es. assenza della
    * cedolare secca prima della sua introduzione nel 2011): se una colonna
    * non esiste, il rename viene semplicemente saltato e non interrompe lo
    * script, ma va controllato manualmente con "describe" per quell'anno.
    cap rename v3  n_contribuenti
    cap rename v4  redd_compl_freq
    cap rename v5  redd_compl_amm
    cap rename v6  redd_compl_netcedsecca_freq
    cap rename v7  redd_compl_netcedsecca_amm
    cap rename v8  ded_abitprinc_freq
    cap rename v9  ded_abitprinc_amm
    cap rename v10 oneri_deducibili_freq
    cap rename v11 oneri_deducibili_amm
    cap rename v12 redd_imponibile_freq
    cap rename v13 redd_imponibile_amm
    cap rename v14 imposta_lorda_freq
    cap rename v15 imposta_lorda_amm
    cap rename v16 detrazioni_freq
    cap rename v17 detrazioni_amm
    cap rename v18 imposta_netta_freq
    cap rename v19 imposta_netta_amm
    cap rename v20 crediti_ritenute_freq
    cap rename v21 crediti_ritenute_amm
    cap rename v22 differenza_freq
    cap rename v23 differenza_amm
    cap rename v24 eccedenza_prec_freq
    cap rename v25 eccedenza_prec_amm
    cap rename v26 acconti_versati_freq
    cap rename v27 acconti_versati_amm
    cap rename v28 irpef_credito_freq
    cap rename v29 irpef_credito_amm
    cap rename v30 irpef_debito_freq
    cap rename v31 irpef_debito_amm

    * Controllo esplicito: le variabili essenziali per il calcolo del
    * fiscal drag DEVONO esistere, altrimenti lo script si ferma con un
    * messaggio chiaro invece di proseguire con dati mancanti silenziosi
    foreach v in n_contribuenti redd_compl_amm redd_imponibile_amm imposta_lorda_amm imposta_netta_amm {
        cap confirm variable `v'
        if _rc != 0 {
            di as error "ERRORE: la variabile essenziale `v' non e' stata creata per l'anno `a'."
            di as error "Controlla con 'describe' la struttura del file mef_raw/calcolo_irpef_`a'.csv"
            error 9
        }
    }

    gen anno_imposta = `a'
    label var anno_imposta "Anno d'imposta (reddito percepito in questo anno)"

    * Le righe di intestazione duplicate (se presenti per via di righe vuote
    * nel CSV) e le righe totalmente vuote vanno scartate
    drop if classe_reddito_str == "" | n_contribuenti == .

    compress
    save "dati_puliti/calcolo_irpef_`a'_clean.dta", replace
    di as result "  -> Salvato: dati_puliti/calcolo_irpef_`a'_clean.dta (`=_N' righe)"
}

/*==============================================================================
PASSO 3: append di tutti gli anni in un unico panel
==============================================================================*/

clear
tempfile panel
local primo = 1
foreach a of local anni {
    capture confirm file "dati_puliti/calcolo_irpef_`a'_clean.dta"
    if _rc == 0 {
        if `primo' == 1 {
            use "dati_puliti/calcolo_irpef_`a'_clean.dta", clear
            local primo = 0
        }
        else {
            append using "dati_puliti/calcolo_irpef_`a'_clean.dta"
        }
    }
}

order anno_imposta classe_reddito_str classe_eta_str n_contribuenti
sort anno_imposta classe_reddito_str classe_eta_str

compress
save "dati_puliti/mef_calcolo_irpef_panel.dta", replace

di as result "=============================================================="
di as result "PANEL COMPLETO SALVATO: dati_puliti/mef_calcolo_irpef_panel.dta"
di as result "Osservazioni totali: `=_N'"
di as result "Anni presenti:"
tab anno_imposta
di as result "=============================================================="
