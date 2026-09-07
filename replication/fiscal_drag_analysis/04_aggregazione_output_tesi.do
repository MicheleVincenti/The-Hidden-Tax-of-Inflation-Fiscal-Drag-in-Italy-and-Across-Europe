/*==============================================================================
SCRIPT 4 di 4 — AGGREGAZIONE, SCOMPOSIZIONE E OUTPUT PER LA TESI
==============================================================================
Input: dati_puliti/mef_panel_fiscal_drag.dta

Questo script produce:
1. Il fiscal drag AGGREGATO per anno (formula ponderata per numero contribuenti)
2. La scomposizione per classe di reddito (dove si concentra il fiscal drag)
3. La scomposizione per classe di età (utile per capire chi è più colpito)
4. Un grafico dell'andamento del fiscal drag nel tempo
5. Un grafico della scomposizione per scaglione di reddito
6. Una tabella riassuntiva esportabile in Excel/LaTeX per la tesi
==============================================================================*/

use "dati_puliti/mef_panel_fiscal_drag.dta", clear

/*------------------------------------------------------------------------------
PASSO 1: FISCAL DRAG AGGREGATO PER ANNO (ponderato)
-------------------------------------------------------------------------------
Formula (vedi nota metodologica):
  FD_agg(t) = [ Sum_i T_reale_i * n_i  -  Sum_i T_indicizzato_i * n_i ]
              -------------------------------------------------------
                          Sum_i Y_i * n_i

dove i = celle (classe di reddito x classe di età), n_i = numero contribuenti
nella cella, Y_i = reddito imponibile medio della cella.
------------------------------------------------------------------------------*/

preserve
    gen T_reale_tot = T_reale * n_contribuenti
    gen T_indic_tot = T_indicizzato * n_contribuenti
    gen Y_tot = redd_imp_medio_oss * n_contribuenti

    collapse (sum) T_reale_tot T_indic_tot Y_tot gettito_aggiuntivo_fd n_contribuenti, ///
        by(anno_imposta)

    gen ETR_reale_agg = T_reale_tot / Y_tot
    gen ETR_indic_agg = T_indic_tot / Y_tot
    gen fiscal_drag_agg_pp = (ETR_reale_agg - ETR_indic_agg) * 100
    gen gettito_aggiuntivo_mld = gettito_aggiuntivo_fd / 1000000000

    label var fiscal_drag_agg_pp "Fiscal drag aggregato (punti percentuali), ponderato per n. contribuenti"
    label var gettito_aggiuntivo_mld "Gettito aggiuntivo aggregato dovuto al fiscal drag (miliardi di euro)"

    * Formattazione leggibile: fiscal drag a 3 decimali, ETR a 4 decimali,
    * gettito a 3 decimali (in miliardi). Senza questa formattazione i valori
    * piccoli apparirebbero come "0" in Excel.
    format fiscal_drag_agg_pp %9.3f
    format ETR_reale_agg ETR_indic_agg %9.4f
    format gettito_aggiuntivo_mld %9.3f

    order anno_imposta n_contribuenti ETR_reale_agg ETR_indic_agg fiscal_drag_agg_pp gettito_aggiuntivo_mld

    list anno_imposta fiscal_drag_agg_pp gettito_aggiuntivo_mld, sep(0)

    save "dati_puliti/fiscal_drag_aggregato_per_anno.dta", replace
    export excel "dati_puliti/tabella_fiscal_drag_per_anno.xlsx", firstrow(variables) replace

    * --- Grafico 1: andamento del fiscal drag aggregato nel tempo ---
    twoway (line fiscal_drag_agg_pp anno_imposta, lwidth(medthick) lcolor("0 90 150")) ///
        (scatter fiscal_drag_agg_pp anno_imposta, mcolor("0 90 150") msymbol(circle)), ///
        title("Aggregate fiscal drag in Italy, 2020-2024") ///
        ytitle("Fiscal drag (percentage points)") xtitle("Tax year") ///
        legend(off) graphregion(color(white)) scheme(s1color) ///
        note("Difference between actual effective average tax rate and inflation-indexed bracket scenario (base year 2020)." ///
             "Source: MEF - Dipartimento delle Finanze; ISTAT.", size(vsmall))
    graph export "dati_puliti/grafico_fiscal_drag_tempo.png", width(1600) replace
restore

/*------------------------------------------------------------------------------
PASSO 2: SCOMPOSIZIONE DEL FISCAL DRAG PER CLASSE DI REDDITO
-------------------------------------------------------------------------------
Risponde alla domanda: quali fasce di reddito sono più colpite dal fiscal
drag? Tipicamente (letteratura OCSE) sono i redditi medi che attraversano
una soglia di scaglione, non i redditi più bassi (sotto no-tax area) né i
più alti (già nello scaglione massimo, dove l'indicizzazione conta meno in
termini relativi).
------------------------------------------------------------------------------*/

preserve
    gen T_reale_tot = T_reale * n_contribuenti
    gen T_indic_tot = T_indicizzato * n_contribuenti
    gen Y_tot = redd_imp_medio_oss * n_contribuenti

    collapse (sum) T_reale_tot T_indic_tot Y_tot n_contribuenti, ///
        by(classe_reddito_str classe_min classe_max anno_imposta)

    gen fiscal_drag_classe_pp = (T_reale_tot - T_indic_tot) / Y_tot * 100

    * Mostra solo l'ultimo anno disponibile come istantanea, ordinato per
    * classe di reddito crescente
    summarize anno_imposta
    local ultimo_anno = r(max)

    save "dati_puliti/fiscal_drag_per_classe_reddito_anno.dta", replace

    keep if anno_imposta == `ultimo_anno' & classe_min != . & classe_min < 200000
    sort classe_min
    list classe_reddito_str fiscal_drag_classe_pp n_contribuenti, sep(0)

    * Creo un indice progressivo ordinato e etichette leggibili delle classi
    * (in euro, abbreviate in "k"), così l'asse mostra categorie uniformi e
    * non valori continui: questo elimina i "buchi" dovuti alle classi di
    * ampiezza diversa e rende il grafico molto più leggibile.
    gen ordine = _n
    gen str20 etichetta_classe = ""
    replace etichetta_classe = string(classe_min/1000, "%9.0f") + "-" + ///
        string(classe_max/1000, "%9.0f") + "k" if classe_max != .
    replace etichetta_classe = string(classe_min/1000, "%9.0f") + "k+" if classe_max == .

    * Applico le etichette all'indice "ordine" con metodo nativo Stata
    * (senza dipendere dal comando esterno labmask)
    cap label drop classlbl
    forvalues i = 1/`=_N' {
        local lab_`i' = etichetta_classe[`i']
        label define classlbl `i' "`lab_`i''", add
    }
    label values ordine classlbl

    graph hbar (asis) fiscal_drag_classe_pp, over(ordine, sort(ordine) ///
        label(labsize(vsmall))) ///
        title("Fiscal drag by income class, tax year `ultimo_anno'", size(medium)) ///
        ytitle("Fiscal drag (percentage points)", size(small)) ///
        bar(1, color("31 119 180%85")) ///
        graphregion(color(white)) scheme(s1color) ///
        ylabel(, labsize(small) grid) ///
        note("Income classes in thousands of euro (e.g. 28-50k). Cumulative fiscal drag relative to 2020 brackets indexed to inflation." ///
             "Source: MEF - Dipartimento delle Finanze; ISTAT.", size(vsmall))
    graph export "dati_puliti/grafico_fiscal_drag_per_classe_reddito.png", width(1600) replace
restore

/*------------------------------------------------------------------------------
PASSO 3: SCOMPOSIZIONE PER CLASSE DI ETÀ
-------------------------------------------------------------------------------
Utile per capire se il fiscal drag colpisce più i lavoratori giovani (con
redditi crescenti nel tempo per carriera) o quelli più anziani/pensionati.
------------------------------------------------------------------------------*/

preserve
    gen T_reale_tot = T_reale * n_contribuenti
    gen T_indic_tot = T_indicizzato * n_contribuenti
    gen Y_tot = redd_imp_medio_oss * n_contribuenti

    collapse (sum) T_reale_tot T_indic_tot Y_tot n_contribuenti, ///
        by(classe_eta_str anno_imposta)

    gen fiscal_drag_eta_pp = (T_reale_tot - T_indic_tot) / Y_tot * 100

    list classe_eta_str anno_imposta fiscal_drag_eta_pp, sep(0)
    save "dati_puliti/fiscal_drag_per_classe_eta_anno.dta", replace
restore

/*------------------------------------------------------------------------------
PASSO 4: CONFRONTO TRA ALIQUOTA MEDIA "REALE OSSERVATA" (dal dato MEF grezzo)
E ALIQUOTA TEORICA RICOSTRUITA (validazione del modello)
-------------------------------------------------------------------------------
Questo passo è un controllo di qualità da inserire nella tesi: confronta
ETR_osservata (calcolata sui dati MEF effettivi, script 2) con ETR_reale_teor
(calcolata applicando gli scaglioni teorici al reddito medio, script 3).
Se i due valori sono vicini, il modello di micro-simulazione è validato.
Le differenze residue sono dovute a: detrazioni/deduzioni specifiche non
modellate, eterogeneità di reddito all'interno della cella, ecc.
------------------------------------------------------------------------------*/

preserve
    gen scostamento_validazione = ETR_osservata - ETR_reale_teor
    summarize scostamento_validazione, detail
    di as result "Scostamento medio tra ETR osservata (dati MEF) e ETR teorica (modello): " r(mean)
    di as result "Deviazione standard dello scostamento: " r(sd)

    histogram scostamento_validazione, ///
        title("Model validation: observed ETR - theoretical ETR") ///
        xtitle("Deviation (percentage points if multiplied by 100)") ///
        ytitle("Density") ///
        graphregion(color(white)) scheme(s1color) ///
        note("Comparison between observed effective average tax rate and the one reconstructed by the bracket model." ///
             "Source: MEF - Dipartimento delle Finanze; ISTAT.", size(vsmall))
    graph export "dati_puliti/grafico_validazione_modello.png", width(1600) replace
restore

di as result "=============================================================="
di as result "ANALISI COMPLETA. File prodotti in dati_puliti/:"
di as result "  - fiscal_drag_aggregato_per_anno.dta / .xlsx"
di as result "  - fiscal_drag_per_classe_reddito_anno.dta"
di as result "  - fiscal_drag_per_classe_eta_anno.dta"
di as result "  - grafico_fiscal_drag_tempo.png"
di as result "  - grafico_fiscal_drag_per_classe_reddito.png"
di as result "  - grafico_validazione_modello.png"
di as result "=============================================================="
