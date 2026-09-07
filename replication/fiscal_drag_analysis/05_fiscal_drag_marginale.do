/*==============================================================================
SCRIPT 5 di 5 — FISCAL DRAG MARGINALE (ANNO SU ANNO) — confronto con il
                FISCAL DRAG CUMULATO calcolato dallo script 03
==============================================================================
Input: dati_puliti/mef_panel_con_inflazione.dta
       dati_puliti/scaglioni_irpef.dta

PERCHE' QUESTO SCRIPT
----------------------
Lo script 03 calcola il fiscal drag CUMULATO: confronta sempre lo scenario
reale dell'anno t con un controfattuale che parte dagli scaglioni del 2020
e li indicizza fino a t. Abbiamo visto che nel 2022 e nel 2024 questo dà un
valore NEGATIVO, perché le riforme strutturali (riduzione aliquote nel 2022,
passaggio a 3 scaglioni nel 2024) "vincono" sul fiscal drag puro accumulato.

Questo script calcola invece il fiscal drag MARGINALE: per ogni coppia di
anni consecutivi (t-1, t), confronta:
  - lo scenario REALE dell'anno t (scaglioni reali di t)
  - lo scenario INDICIZZATO DI UN SOLO ANNO: gli scaglioni REALI dell'anno
    t-1 (non quelli del 2020), rivalutati per la sola inflazione tra t-1 e t

In questo modo, isoliamo l'effetto della mancata indicizzazione nell'ULTIMO
anno, a prescindere da cosa sia successo negli anni precedenti. Se nell'anno
t c'è stata anche una riforma degli scaglioni (rispetto a t-1), quella
riforma viene ESCLUSA dal controfattuale (che riparte sempre dagli scaglioni
REALI di t-1, non da quelli teorici/indicizzati) — quindi qui isoliamo
"quanto fiscal drag puro si è accumulato in un anno", al netto di eventuali
riforme che intervengono nello stesso anno.

NOTA IMPORTANTE: la riforma stessa (es. 2022 vs 2021, 2024 vs 2023) NON
genera fiscal drag marginale per definizione di questo metodo, perché la
riforma È lo scenario reale di t, e lo confrontiamo con "t-1 indicizzato",
non con "t-1 invariato". Quindi negli anni di riforma il fiscal drag
marginale misura SOLO l'inflazione dell'ultimo anno applicata alla struttura
energicamente nuova, il che è leggermente diverso da "quanto la riforma ha
tolto o aggiunto rispetto al fiscal drag". Per la tesi, l'interpretazione
corretta è:
  - Fiscal drag CUMULATO (script 03/04): "quanto si è allontanata l'ETR
    reale da uno scenario puramente indicizzato dal 2020, riforme incluse
    come parte dello scenario reale"
  - Fiscal drag MARGINALE (questo script): "quanto fiscal drag puro si
    genera ogni anno, isolando l'effetto dell'inflazione dell'anno corrente
    dalla struttura di scaglioni in vigore l'anno precedente"
Mostrarli ENTRAMBI in tesi, con questa distinzione esplicitata, è la lettura
più completa e rigorosa.
==============================================================================*/

use "dati_puliti/mef_panel_con_inflazione.dta", clear

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

/*------------------------------------------------------------------------------
PASSO 1: matrici di scaglioni REALI per ogni anno (identico allo script 03)
------------------------------------------------------------------------------*/
levelsof anno_imposta, local(anni_panel)
foreach a of local anni_panel {
    crea_matrice_scaglioni `a' scagl_reale_`a'
}

/*------------------------------------------------------------------------------
PASSO 2: per ogni coppia di anni consecutivi (t-1, t), costruisci la matrice
"scagl_reale_(t-1) indicizzata di un anno" usando il rapporto tra indice NIC
di t e di t-1.
------------------------------------------------------------------------------*/
local anni_ordinati : list sort anni_panel
local n_anni : list sizeof anni_ordinati

forvalues idx = 2/`n_anni' {
    local a_prec : word `=`idx'-1' of `anni_ordinati'
    local a_corr : word `idx' of `anni_ordinati'

    preserve
        use "dati_puliti/inflazione_nic.dta", clear
        keep if anno_imposta == `a_prec'
        local indice_prec = indice_nic_base2020[1]
    restore
    preserve
        use "dati_puliti/inflazione_nic.dta", clear
        keep if anno_imposta == `a_corr'
        local indice_corr = indice_nic_base2020[1]
    restore

    local fattore_1anno = `indice_corr' / `indice_prec'

    mat scagl_indic1_`a_corr' = scagl_reale_`a_prec'
    forvalues r = 1/`=rowsof(scagl_reale_`a_prec')' {
        mat scagl_indic1_`a_corr'[`r',1] = scagl_reale_`a_prec'[`r',1] * `fattore_1anno'
        if scagl_reale_`a_prec'[`r',2] != . {
            mat scagl_indic1_`a_corr'[`r',2] = scagl_reale_`a_prec'[`r',2] * `fattore_1anno'
        }
    }
    di as text "Anno `a_corr' vs `a_prec': fattore di rivalutazione di un anno = `fattore_1anno'"
}

/*------------------------------------------------------------------------------
PASSO 3: applica le matrici al reddito imponibile medio osservato in ogni
cella, per ogni anno t >= secondo anno del panel (il primo anno non ha un
t-1 disponibile e viene escluso, fiscal drag marginale = non definito)
------------------------------------------------------------------------------*/
gen T_reale_marg = .
gen T_indic_marg1anno = .

forvalues idx = 2/`n_anni' {
    local a_corr : word `idx' of `anni_ordinati'

    forvalues riga = 1/`=_N' {
        if anno_imposta[`riga'] == `a_corr' & redd_imp_medio_oss[`riga'] != . & redd_imp_medio_oss[`riga'] > 0 {
            local y = redd_imp_medio_oss[`riga']

            calcola_imposta_scalare `y' scagl_reale_`a_corr'
            replace T_reale_marg = `r(imposta)' in `riga'

            calcola_imposta_scalare `y' scagl_indic1_`a_corr'
            replace T_indic_marg1anno = `r(imposta)' in `riga'
        }
    }
    di as text "Fiscal drag marginale calcolato per l'anno `a_corr'"
}

gen fiscal_drag_marginale = (T_reale_marg - T_indic_marg1anno) / redd_imp_medio_oss * 100 ///
    if redd_imp_medio_oss > 0
label var fiscal_drag_marginale "Fiscal drag marginale anno su anno (punti percentuali)"
label var T_reale_marg "Imposta teorica scenario reale (per calcolo marginale)"
label var T_indic_marg1anno "Imposta teorica con scaglioni anno precedente indicizzati di 1 anno"

compress
save "dati_puliti/mef_panel_fiscal_drag_marginale.dta", replace

/*------------------------------------------------------------------------------
PASSO 4: aggregazione per anno (ponderata per numero di contribuenti) e
confronto fianco a fianco con il fiscal drag CUMULATO calcolato dallo
script 03/04
------------------------------------------------------------------------------*/
preserve
    gen T_reale_tot = T_reale_marg * n_contribuenti
    gen T_indic_tot = T_indic_marg1anno * n_contribuenti
    gen Y_tot = redd_imp_medio_oss * n_contribuenti

    collapse (sum) T_reale_tot T_indic_tot Y_tot n_contribuenti, by(anno_imposta)

    gen fiscal_drag_marginale_agg_pp = (T_reale_tot - T_indic_tot) / Y_tot * 100
    label var fiscal_drag_marginale_agg_pp "Fiscal drag marginale aggregato (p.p.), anno su anno"

    keep anno_imposta fiscal_drag_marginale_agg_pp n_contribuenti
    save "dati_puliti/fiscal_drag_marginale_per_anno.dta", replace
restore

* --- Merge con il fiscal drag cumulato (prodotto dallo script 04) per la
*     tabella di confronto finale ---
preserve
    use "dati_puliti/fiscal_drag_aggregato_per_anno.dta", clear
    keep anno_imposta fiscal_drag_agg_pp gettito_aggiuntivo_mld
    tempfile cumulato
    save `cumulato'
restore

use "dati_puliti/fiscal_drag_marginale_per_anno.dta", clear
merge 1:1 anno_imposta using `cumulato'
drop _merge

rename fiscal_drag_agg_pp fiscal_drag_CUMULATO_pp
rename fiscal_drag_marginale_agg_pp fiscal_drag_MARGINALE_pp

* Arrotonda a 3 decimali per una visualizzazione leggibile in Excel
* (i valori sono in punti percentuali e tipicamente compresi tra -0.5 e +0.5,
*  quindi senza decimali apparirebbero erroneamente come "0")
replace fiscal_drag_CUMULATO_pp = round(fiscal_drag_CUMULATO_pp, 0.001)
replace fiscal_drag_MARGINALE_pp = round(fiscal_drag_MARGINALE_pp, 0.001)
format fiscal_drag_CUMULATO_pp fiscal_drag_MARGINALE_pp %9.3f

label var fiscal_drag_CUMULATO_pp "Fiscal drag cumulato dal 2020 (p.p.) - script 03/04"
label var fiscal_drag_MARGINALE_pp "Fiscal drag marginale anno su anno (p.p.) - script 05"

order anno_imposta fiscal_drag_MARGINALE_pp fiscal_drag_CUMULATO_pp gettito_aggiuntivo_mld n_contribuenti

di as result "=============================================================="
di as result "CONFRONTO FISCAL DRAG MARGINALE vs CUMULATO"
di as result "=============================================================="
list anno_imposta fiscal_drag_MARGINALE_pp fiscal_drag_CUMULATO_pp, sep(0)

save "dati_puliti/confronto_marginale_cumulato.dta", replace
export excel "dati_puliti/tabella_confronto_fiscal_drag.xlsx", firstrow(variables) replace

/*------------------------------------------------------------------------------
PASSO 5: grafico di confronto — le due serie sullo stesso piano
------------------------------------------------------------------------------*/
twoway ///
    (line fiscal_drag_MARGINALE_pp anno_imposta, lwidth(medthick) lcolor("0 90 150") lpattern(solid)) ///
    (scatter fiscal_drag_MARGINALE_pp anno_imposta, mcolor("0 90 150") msymbol(circle)) ///
    (line fiscal_drag_CUMULATO_pp anno_imposta, lwidth(medthick) lcolor("200 60 60") lpattern(dash)) ///
    (scatter fiscal_drag_CUMULATO_pp anno_imposta, mcolor("200 60 60") msymbol(triangle)), ///
    title("Fiscal drag in Italy: marginal vs cumulative, 2020-2024") ///
    ytitle("Fiscal drag (percentage points)") xtitle("Tax year") ///
    legend(order(1 "Marginal (year-on-year)" 3 "Cumulative (base year 2020)") position(6) rows(1)) ///
    graphregion(color(white)) scheme(s1color) ///
    yline(0, lcolor(gray) lpattern(dot)) ///
    note("Marginal: effect of current-year inflation only. Cumulative: total difference vs 2020 brackets indexed to inflation (reforms included)." ///
         "Source: MEF - Dipartimento delle Finanze; ISTAT.", size(vsmall))
graph export "dati_puliti/grafico_confronto_marginale_cumulato.png", width(1800) replace

di as result "=============================================================="
di as result "File prodotti da questo script:"
di as result "  - dati_puliti/mef_panel_fiscal_drag_marginale.dta"
di as result "  - dati_puliti/fiscal_drag_marginale_per_anno.dta"
di as result "  - dati_puliti/confronto_marginale_cumulato.dta"
di as result "  - dati_puliti/tabella_confronto_fiscal_drag.xlsx   <- TABELLA PER LA TESI"
di as result "  - dati_puliti/grafico_confronto_marginale_cumulato.png   <- GRAFICO PER LA TESI"
di as result "=============================================================="
