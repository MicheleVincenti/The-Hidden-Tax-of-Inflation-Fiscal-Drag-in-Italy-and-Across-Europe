*==============================================================================
* 06_simulazione_proposta.do
* Simulazione di tre regole di aggiornamento delle soglie IRPEF, 2020-2024
*
* COME ESEGUIRLO:
*   Lancialo SUBITO DOPO "03_calcolo_fiscal_drag.do", quando in memoria ci sono
*   ancora i dati a livello di cella con le variabili:
*     anno_imposta, n_contribuenti, redd_imp_medio_oss, indice_nic_base2020
*   Se non ci sono, apri prima il dataset pulito a livello di cella, es:
*     use "dati_puliti/dati_cella_completi.dta", clear
*   (adatta il nome del file a quello che usi tu)
*
* COSA FA:
*   Confronta, a parità di struttura 2020 e di distribuzione reale dei redditi,
*   tre regole di indicizzazione delle SOGLIE:
*     (A) nessuna indicizzazione  -> soglie ferme al 2020
*     (B) indicizzazione piena     -> soglie x inflazione cumulata, ogni anno
*     (C) indicizzazione a trigger -> rivaluta solo se l'inflazione cumulata
*                                     dall'ultima rivalutazione supera theta
*   Per ciascuna calcola l'aliquota media effettiva (ETR) aggregata e il
*   fiscal drag residuo rispetto all'indicizzazione piena (benchmark).
*==============================================================================

* --- parametro della regola: soglia di attivazione del trigger ---
local theta = 0.03      // 3% di inflazione cumulata. Cambia qui per sensibilita'

* --- controllo che le variabili necessarie siano in memoria ---
capture confirm variable anno_imposta n_contribuenti redd_imp_medio_oss indice_nic_base2020
if _rc {
    display as error "Mancano variabili a livello di cella. Apri prima il dataset pulito (vedi intestazione)."
    exit 111
}

*------------------------------------------------------------------------------
* 1) Costruisco i fattori di rivalutazione anno per anno
*------------------------------------------------------------------------------
preserve
    collapse (mean) indice_nic_base2020, by(anno_imposta)
    sort anno_imposta

    * fattore indicizzazione PIENA = indice_t / indice_2020
    gen double f_full = indice_nic_base2020 / indice_nic_base2020[1]

    * fattore indicizzazione NESSUNA = 1 sempre
    gen double f_none = 1

    * fattore indicizzazione a TRIGGER
    gen double f_trig = 1 in 1
    scalar base_idx = indice_nic_base2020[1]      // indice all'ultima rivalutazione
    forvalues i = 2/`=_N' {
        local cum = indice_nic_base2020[`i']/base_idx - 1     // infl. cumulata dall'ultima reval.
        if `cum' >= `theta' {
            replace f_trig = indice_nic_base2020[`i']/indice_nic_base2020[1] in `i'
            scalar base_idx = indice_nic_base2020[`i']
        }
        else {
            replace f_trig = f_trig[`i'-1] in `i'
        }
    }

    list anno_imposta f_none f_full f_trig, sep(0) noobs
    tempfile fattori
    save `fattori'
restore

* --- aggancio i fattori alle celle ---
merge m:1 anno_imposta using `fattori', nogenerate

*------------------------------------------------------------------------------
* 2) Funzione imposta: struttura 2020 con soglie scalate da un fattore f
*    Scaglioni 2020: 15000(23%) 28000(27%) 55000(38%) 75000(41%) oltre(43%)
*------------------------------------------------------------------------------
capture program drop genera_imposta
program define genera_imposta
    * args: nome_nuova_var  var_reddito  var_fattore
    args nome y f
    gen double s1 = 15000*`f'
    gen double s2 = 28000*`f'
    gen double s3 = 55000*`f'
    gen double s4 = 75000*`f'
    gen double `nome' = cond(`y'<=s1, `y'*0.23, ///
        cond(`y'<=s2, s1*0.23 + (`y'-s1)*0.27, ///
        cond(`y'<=s3, s1*0.23 + (s2-s1)*0.27 + (`y'-s2)*0.38, ///
        cond(`y'<=s4, s1*0.23 + (s2-s1)*0.27 + (s3-s2)*0.38 + (`y'-s3)*0.41, ///
                      s1*0.23 + (s2-s1)*0.27 + (s3-s2)*0.38 + (s4-s3)*0.41 + (`y'-s4)*0.43))))
    drop s1 s2 s3 s4
end

* imposta per cella sotto le tre regole
genera_imposta imp_none redd_imp_medio_oss f_none
genera_imposta imp_full redd_imp_medio_oss f_full
genera_imposta imp_trig redd_imp_medio_oss f_trig

*------------------------------------------------------------------------------
* 3) Aggrego a ETR media effettiva per anno (ponderata per n. contribuenti)
*------------------------------------------------------------------------------
gen double imp_none_tot = imp_none * n_contribuenti
gen double imp_full_tot = imp_full * n_contribuenti
gen double imp_trig_tot = imp_trig * n_contribuenti
gen double redd_tot     = redd_imp_medio_oss * n_contribuenti

collapse (sum) imp_none_tot imp_full_tot imp_trig_tot redd_tot, by(anno_imposta)

gen double ETR_none = imp_none_tot / redd_tot * 100
gen double ETR_full = imp_full_tot / redd_tot * 100
gen double ETR_trig = imp_trig_tot / redd_tot * 100

* fiscal drag residuo rispetto all'indicizzazione PIENA (benchmark = 0)
gen double drag_none = ETR_none - ETR_full     // bracket creep puro (il problema)
gen double drag_trig = ETR_trig - ETR_full     // residuo sotto la regola a trigger

format ETR_* drag_* %9.3f
list anno_imposta ETR_none ETR_full ETR_trig drag_none drag_trig, sep(0) noobs

* --- costo erariale: gettito in piu' che lo Stato incassa per la NON indicizzazione ---
* (= quanto la regola restituirebbe ai contribuenti). Lo ricavi dal tuo
*  dataset principale come somma di (imposta_reale - imposta_indicizzata).

export excel anno_imposta ETR_none ETR_full ETR_trig drag_none drag_trig ///
    using "dati_puliti/tabella_simulazione_proposta.xlsx", firstrow(variables) replace

*------------------------------------------------------------------------------
* 4) Grafico: fiscal drag residuo sotto le due regole, per anno
*------------------------------------------------------------------------------
twoway (connected drag_none anno_imposta, lcolor("200 60 60") mcolor("200 60 60") lpattern(solid)) ///
       (connected drag_trig anno_imposta, lcolor("31 119 180") mcolor("31 119 180") lpattern(dash)), ///
    yline(0, lcolor(gray) lpattern(dot)) ///
    title("Residual fiscal drag under alternative indexation rules", size(medium)) ///
    ytitle("Residual fiscal drag vs full indexation (p.p.)", size(small)) ///
    xtitle("Tax year") ///
    legend(order(1 "No indexation (bracket creep)" 2 "Triggered rule ({&theta}=3%)") position(6) rows(1)) ///
    graphregion(color(white)) scheme(s1color) ///
    note("Same 2020 bracket structure and actual income distribution under each rule; only the threshold-updating rule changes." ///
         "Source: own elaboration on MEF - Dipartimento delle Finanze; ISTAT.", size(vsmall))
graph export "dati_puliti/grafico_simulazione_proposta.png", width(1800) replace

display as result "=== Simulazione completata. Output in dati_puliti/ ==="
