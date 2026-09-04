cd "C:\Users\miche\OneDrive\Desktop\UNIVERSITA'\TESI\FONTI\Figure 2

clear all
set more off

/* ============================================================
   DATASET 1: INFLAZIONE
   Fonte: Eurostat
   File: inflazione.csv

   Obiettivo:
   creare un file con due variabili:
   - year
   - inflation_rate
   ============================================================ */

import delimited "prc_hicp_aind_page_linear.csv", clear
br

* Creo la variabile anno.
* Nel file Eurostat la variabile temporale di solito si chiama time_period.
gen year = time_period

* Rinomino il valore dell'inflazione.
* Nel file Eurostat il valore osservato di solito si chiama obs_value.
rename obs_value inflation_rate

keep if year >= 2019
keep year inflation_rate

sort year
save "inflazione.dta", replace

/* ============================================================
   DATASET 2: REDDITO DISPONIBILE
   Fonte: BCE
   File: reddito_disponibile_bce.csv

   Obiettivo:
   trasformare il reddito trimestrale in reddito annuo
   e calcolare la crescita annua del reddito disponibile.
   ============================================================ */

import delimited "reddito_disponibile_bce.csv", clear
br

* Creo la variabile anno partendo dal periodo trimestrale.
* Anche nel file BCE la variabile temporale può chiamarsi time_period.
gen year = real(substr(date, 1, 4))

* Rinomino il valore del reddito disponibile.
* Nel file BCE il valore osservato di solito si chiama obs_value.
rename grossdisposableincomeofhousehold disposable_income

keep if year >= 2019 

* Tengo solo le variabili necessarie
keep year disposable_income

* Sommo i quattro trimestri per ottenere il reddito disponibile annuo.
* Uso sum perché il reddito disponibile è un flusso.
collapse (sum) disposable_income, by(year)
sort year

* Calcolo la crescita percentuale annua del reddito disponibile nominale
gen income_growth = 100 * (disposable_income / disposable_income[_n-1] - 1)

* Salvo il dataset pulito del reddito
save "reddito.dta", replace


/* ============================================================
   MERGE DEI DUE DATASET
   Unisco inflazione e reddito disponibile usando l'anno.
   ============================================================ */

use "inflazione.dta", clear

merge 1:1 year using "reddito.dta"

* Tengo solo gli anni presenti in entrambi i dataset
keep if _merge == 3
drop _merge

sort year


/* ============================================================
   CRESCITA REALE DEL REDDITO DISPONIBILE
   Approssimazione:
   crescita reale = crescita nominale - inflazione
   ============================================================ */

gen real_income_growth = income_growth - inflation_rate
br


/* ============================================================
   GRAFICO PER LA SEZIONE 2.2
   ============================================================ */

set scheme s2color

twoway ///
    (line inflation_rate year, ///
        lwidth(medthick) ///
        lpattern(solid)) ///
    (line income_growth year, ///
        lwidth(medthick) ///
        lpattern(dash)) ///
    (line real_income_growth year, ///
        lwidth(medthick) ///
        lpattern(dot)), ///
    title("Inflation and Household Disposable Income in Italy", size(medsmall)) ///
    subtitle("Annual percentage changes, 2020-2025", size(small)) ///
    xtitle("Year", size(small)) ///
    ytitle("Annual percentage change", size(small)) ///
    xlabel(2020(1)2025, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal)) ///
    legend(order(1 "Inflation rate" ///
                 2 "Nominal disposable income growth" ///
                 3 "Real disposable income growth") ///
           position(6) rows(3) size(small) region(lstyle(none))) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    note("Source: Eurostat dataset prc_hicp_aind (HICP annual data)" ///
         "and ECB Data Portal dataset Gross disposable income of households, Italy, Quarterly.", ///
         size(vsmall))

graph export "graph_2_2_inflation_disposable_income.png", replace width(2400)

save "dataset_finale_2_2.dta", replace