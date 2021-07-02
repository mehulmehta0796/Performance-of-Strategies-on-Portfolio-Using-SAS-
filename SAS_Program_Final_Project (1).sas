*********************************************************************************
 Program: Value.sas                                               
 Author : Group_1                                                 
 Date   : 5/3/21                                                          
 Description: Takes the crspm_small dataset which is the full set of monthly
 returns from CRSP and examines the value anomaly with sorts and graphs using
 the Subroutine_ Form Portfolios and Test Anomaly
                         
*********************************************************************************;



*******************************************************;
***Clean Slate: Clear Log and Empty Work Directory;
*******************************************************;

/* 	dm 'log;clear;'; *NOT NECESSARY FOR SAS STUDIO*/
	proc datasets library = work kill memtype=data nolist;
	  quit;



*******************************************************;
**Libraries and Paths;
*******************************************************;
**Define your paths;

%let data_path=/courses/d0f4cb55ba27fe300/Anomalies;
%let program_path=/courses/d0f4cb55ba27fe300/Anomalies/programs;
%let output_path=/home/u58195306/sasuser.v94/Final_Project;
%put &output_path;


*Define Data library;
libname my "&data_path";

*******************************************************;
*Get Stock Data Ready
*******************************************************;


*Make temporary version of full stock universe and create any extra variables you want to add to the mix;
data stock;
set my.crspm_small;
by permno;


*Create/change any variables
***********************************************************************;
*fix price variable because it is sometimes negative to reflect average of bid-ask spread;
price=abs(prc);
*get beginning of period price;
lag_price=lag(price);
if first.permno then lag_price=.;
***********************************************************************;

*require all stocks to have beginning of period market equity.;
if LME=. then delete; 

*pick only the primary security as of that date (only applies to multiple share class stocks);
if primary_security=1; 

keep date permno ME ret LME lag_price;

*remove return label to make programming easier;
label ret=' ';

run;  

*************************************************************;
*do any extra stuff to get your formation data ready;
*************************************************************;


***********************Compustat Book equity Fama French Style
Compustat XpressFeed Variables:                                     
AT      = Total Assets                                              
PSTKL   = Preferred Stock Liquidating Value                                     
PSTKRV  = Preferred Stock Redemption Value       
PSTK	= Preferred Stock Par Value
TXDITC  = Deferred Taxes and Investment Tax Credit       
SEQ		= Shareholder's Equity
CEQ     = Common/Ordinary Equity - Total  
LT 		= Total Liabilities 
datadate = Date of fiscal year end

**********************************************************************
 ;

*Get Compustat Data ready; 
data account;
set my.comp_big;

*data is already sorted on WRDS so we can use by groups right away;
  by gvkey datadate;

*Checking the revenue and total assets;
 if revt=. then delete; 
*delete at<=0 to avoid division by 0;
 if at=0 then delete;
 
*set cogs<0 to missing;
if cogs<0 then cogs=. ;  
   
*set Gross Profit as ;
  GP = revt - cogs;
  
label  
  GP="Gross Profit"
 ;

*require the stock to have a PERMNO (a match to CRSP);
if permno=. then delete;
*only keep the variables we need for later;
keep datadate permno cogs at GP ;

*keep datadate permno BE seq ceq pstk at lt TXDITC PS se;
run;


*Merge stock returns data from CRSP with book equity accounting data from Compustat.
For each month t in the stock returns set, merge with the latest fiscal year end that is also at least 6 months old so we can 
assume you would have access to the accounting data. Remember that firms report accounting data with a lag, annual data in year t
won't be reported until annual reports come out in April of t+1. This sorts by datadate_dist so that closest dates come first;

proc sql;
create table formation as
select a.*, b.* , intck('month',b.datadate,a.date) as datadate_dist "Months from last datadate"

from stock a, account b
where a.permno=b.permno and 6 <= intck('month',b.datadate,a.date) <=18
order by a.permno,date,datadate_dist;
quit;

*select the closest accounting observation for each permno and date combo;
data formation;
set formation;
by permno date;
if first.date;

*Define gross-profit to Total-Asssets ratio! 
-Use beginning of period market equity and GP from 6 to 18 months old)
-Unlike Fama French, We use the division of Grossprofit by the Asset Total to Find the Gross Profit Ratio ;

GPR = GP/at;

run;

*Get SIC industry code from header file in order to
remove stocks that are classified as financials because they have weird ratios (avoid sic between 6000-6999);
proc sql;
create table formation as
select a.*, b.siccd
from formation a ,my.msenames b
where a.permno=b.permno and (b.NAMEDT <= a.date <=b.NAMEENDT)
and not (6000<= b.siccd <=6999);
quit;

*******************************************************;
*Define your Anomaly (User Input required here)
*******************************************************;

*Define a Master Title that will correspond to Anomaly definition throughout output;
title1 "Gross Profit Effect";

*Start Output file;
ods pdf file="&output_path/Gross Profit Effect.pdf"; 

*
We are using portfolios every July since 1985 every six months until December 31st 2016
;
data formation;
set formation;
by permno date;

***********************************************************************;
*Define the stock characteristics you want to sort on (SORTVAR);
***********************************************************************;
*Gross Profit to Asset Total Ratio;
SORTVAR=GPR; 
format SORTVAR 10.2;
label SORTVAR="Sort Variable: Gross Profit to Total Asset Ratio";

***********************************************************************;
*Define Rebalance Frequency;
***********************************************************************;
*Rebalance Annually in July;
if month(date)=7; 


***********************************************************************;
*Define subsample criteria
***********************************************************************;
if SORTVAR = . then delete; *must have non missing SORTVAR;
*if year(date)>=1963 and year(date)<=2016; *Select Time period;
if year(date)>=1985 and year(date)<=2016; *Select Time period;
if lme>1; *market cap of at least 1 million to start from;
if lag_price<1 or lag_price=. then delete; *Remove penny stocks or stocks missing price;

***********************************************************************;
*Define portfolio_weighting technique;
***********************************************************************;
portfolio_weight=LME; *Portfolio weights: set=1 for equal weight, or set =LME for value weighted portfolio;

run;


*******************************************************;
*Define holding period, bin Order and Format
*******************************************************;
*Define Holding Period (number of months in between rebalancing dates (i.e., 1 year = 12 months);
%let holding_period = 12;

*Define number of bins;
%let bins=5;

*Define the bin ordering:;
*%let rankorder= ; 
%let rankorder=descending;

*What stocks are you going long vs. what are you going Short?
leave blank for ascending rank (bin 1 is smallest value), set to descending 
if you want bin 1 to have largest value;

*Define a bin format for what the bin portfolios will correspond to for output;
proc format;
value bin_format 1="1. High Gross Profit to Asset Total"

5="5. Low Gross Profit to Asset Total"
99="Long_Short: High_Low"
;
run;


**********************************************************Forming Portfolios and Testing Begins Here**************************************;
%include "&program_path/Subroutine_ Form Portfolios and Test Anomaly.sas";

ods pdf close;


****Part-III;

data abhi;
set work.portfolio_graph;
*keep dateff mktrf hml smb umd value_momentum;
if bin = 99;
value_momentum=sum(hml,umd);
label value_momentum="Value plus momentum" ;

GPR_Value = sum(sortvar , hml);
label GPR_Value="Gross plus Value" ;

Market_Portfolio = mktrf;
label Market_Portfolio ="Investing_MKTRF" ;
run;
 
PROC SORT data=abhi;
    BY DATE;
RUN;
 
*1;
proc transpose data=abhi out=long;
by date;
var mktrf hml smb umd GPR_Value value_momentum Market_Portfolio;
run;

data port_L;
set long;
rename dateff=date col1=exret _label_=bin;
run;

proc sql;
create table port_L as
select a.*, b.*,a.exret + b.rf as ret
from port_L as a, my.factors_monthly as b
where a.date=b.dateff
order by bin,a.date;
quit;

**1.Create a table containing summmary stats of return for each strategy**;
proc means data=abhi n mean median std min max p1 skew; 
class bin;
var value_momentum GPR_Value Market_Portfolio;
title "Summary stats of monthly returns for all 3 strategies";
run;


**2.Create a graph and table of cummulative returns of all 3 strategies**;
data P_graphs;
set port_L;
by bin;
if first.bin then cumret1=10000;
if ret ne . then cumret1=cumret1*(1+ret);
else cumret1=cumret1;
cumret=cumret1-10000;
retain cumret1;
format cumret1 dollar15.2 ; 
label cumret1="Value of Dollar Invested In the Portfolio";
run;


footnote " ";
proc sgplot data=P_graphs;
where bin in("Gross plus Value","Value plus momentum","Investing_MKTRF");
	series x=date y=cumret / group=bin lineattrs=(thickness=2);
	xaxis type = time;
  xaxis display=(noline);
  yaxis display=(noline) grid; 
title "Cummulative performance of all 3 strategies";
title2 "Cumulative Performance";
run;

data P_table;
set P_graphs;
where bin in("Gross plus Value","Value plus momentum","Investing_MKTRF");
by bin;
if year = 2016;
if month = 12;
keep bin year month cumret;
format cumret 10.3;
run;
proc print data=P_table label;
label Year = "Year";
label month = "Month (December)";
label bin = "Strategies";
label cumret= "Cummulative Returns($)";
title "End of the sample period- Portfolio values: Strategy wise";
run;


**3.Create a table containing the mean excess return, standard deviation and Sharpe Ratio for each strategy**;
proc means data=port_L noprint;
where bin in("Gross plus Value","Value plus momentum","Investing_MKTRF");
by bin;
var ret ;
output out=mean_std mean= std= /autoname autolabel;
run;  

data sharpe;
set mean_std;
sharpe_ratio=ret_mean/ret_StdDev;
drop _TYPE_ _FREQ_;
label 
ret_mean="Mean Excess Return"
ret_StdDev="Standard Deviation of Excess Returns"
sharpe_ratio="Sharpe Ratio"
;

format ret_mean ret_StdDev percentn10.3 sharpe_ratio 10.3;
run;

proc print noobs label;
title "Mean excess return, standard deviation and Sharpe Ratio: Strategy wise ";
run;


**4.Factior analysis **;
* CAPM regression;
proc reg data = port_L outest = CAPM_out edf noprint tableout;
where bin in("Gross plus Value","Value plus momentum","Investing_MKTRF");
by bin;
model ret = mktrf; * Since ret is exret + rf;
quit;

*CAPM clean up regression output;
data CAPM_out label;
set CAPM_out;
where  _TYPE_ in ('PARMS','T'); *just keep Coefficients (Parms) and T-statistics (T);

*rescale intercept to percentage but only the PARMS, not T (Cant use percentage format because it would change T-stat also);
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: CAPM"
mktrf="Market Beta: CAPM"
;

format intercept mktrf 10.3;

keep bin _type_ intercept mktrf;

rename
intercept=alpha_capm
mktrf=mktrf_capm
;
run;


*Fama French 3 Factor;
proc reg data = port_L outest = FF3_out_P edf noprint tableout;
where bin in("Gross plus Value","Value plus momentum","Investing_MKTRF");
by bin;
model ret = mktrf smb hml;
quit;


*FAMA FRENCH ALPHA AND BETAS*;
data FF3_out_P label;
set FF3_out_P;
where  _TYPE_ in ('PARMS','T');

*rescale intercept to percentage but only the PARMS, not T;
IF _TYPE_ ='PARMS' THEN intercept=intercept*100;

label 
intercept="Alpha: FF3"
mktrf="Market Beta: FF3"
smb="SMB Beta"
hml="HML Beta"
;

format intercept mktrf smb hml 10.3;

keep bin _type_ intercept mktrf smb hml;

rename 
intercept=alpha_ff3
mktrf=mktrf_ff3
;

run;

*MERGE TOGETHER: TABLE;
data Combine_table ;
retain bin;
merge CAPM_out FF3_out_P;
by bin _type_;

format bin bin_format.;
run;

proc print;
title "Factor Regression Results";
run;


**5. Annualized reutrn****;

data annual_returns;
set abhi;
by year;
retain cumret_GPR;
if first.year or month(date)=1 then cumret_GPR=1+GPR_Value;
else cumret_GPR=cumret_GPR*(1+GPR_Value);
if month(date)=12 then cumret_GPR=cumret_GPR-1;;
format cumret_GPR percentn10.3 ; 
label cumret_GPR="Returns: Gross plus value";

retain cumret_ValMom;
if first.year or month(date)=1 then cumret_ValMom=1+value_momentum;
else cumret_ValMom=cumret_ValMom*(1+value_momentum);
if month(date)=12 then cumret_ValMom=cumret_ValMom-1;;
format cumret_ValMom percentn10.3 ; 
label cumret_ValMom="Returns: Value plus momentum";

retain cumret_mktrf;
if first.year or month(date)=1 then cumret_mktrf=1+Market_Portfolio;
else cumret_mktrf=cumret_mktrf*(1+Market_Portfolio);
if month(date)=12 then cumret_mktrf=cumret_mktrf-1;;
format cumret_mktrf percentn10.3 ; 
label cumret_mktrf="Returns: Investing_mktrf";

if month = 12;
keep year cumret_GPR cumret_ValMom cumret_mktrf; 
run;

proc print label noobs;
title "Annual Returns: Strategy wise";
run;


*5(II).;

proc rank data=annual_returns out=rank_order descending ties=low;
   var cumret_GPR cumret_ValMom cumret_mktrf;
   ranks ranking_GPR ranking_ValMom ranking_mktrf ;
run;
*proc print data=rank_order;
*   title "Rankings of strategies";
*run;

*** Best 5 annual returns ranking***;
data ranking_performance_GPR;
set rank_order;
where ranking_GPR in (1,2,3,4,5); 
keep Ranking_GPR cumret_GPR ;
run;

data ranking_performance_ValMom;
set rank_order;
where  ranking_ValMom  in (1,2,3,4,5) ;
keep Ranking_ValMom cumret_ValMom ;
run;

data ranking_performance_mktrf;
set rank_order;
where ranking_mktrf in (1,2,3,4,5) ;
keep ranking_mktrf cumret_mktrf  ;
run;

data merge_strategy_ranking_best;
merge ranking_performance_GPR ranking_performance_ValMom ranking_performance_mktrf;
RUN;

PROC PRINT DATA=merge_strategy_ranking_best label;
title "5 best annual returns for each strategy";
label cumret_GPR = "Gross plus value";
label cumret_ValMom = "Value plus Momentum";
label cumret_mktrf = "Investing_mktrf";
label ranking_GPR = "Ranking_Gross plus value";
label ranking_ValMom = "Ranking_Value plus Momentum";
label ranking_mktrf = "Ranking_Investing_mktrf";
RUN ;

*** Worst five***;
data ranking_performance_GPR;
set rank_order;
where ranking_GPR in (28,29,30,31,32); 
keep Ranking_GPR cumret_GPR ;
run;

data ranking_performance_ValMom;
set rank_order;
where  ranking_ValMom  in (28,29,30,31,32) ;
keep Ranking_ValMom cumret_ValMom ;
run;

data ranking_performance_mktrf;
set rank_order;
where ranking_mktrf in (28,29,30,31,32) ;
keep ranking_mktrf cumret_mktrf  ;
run;

data merge_strategy_ranking_worst;
merge ranking_performance_GPR ranking_performance_ValMom ranking_performance_mktrf;
RUN;

PROC PRINT DATA=merge_strategy_ranking_worst label;
title "5 worst annual returns for each strategy";
label cumret_GPR = "Gross plus value";
label cumret_ValMom = "Value plus Momentum";
label cumret_mktrf = "Investing_mktrf";
label ranking_GPR = "Ranking_Gross plus value";
label ranking_ValMom = "Ranking_Value plus Momentum";
label ranking_mktrf = "Ranking_Investing_mktrf";
RUN ;


proc sgplot data=merge_strategy_ranking_best;
vbar ranking_GPR / response=cumret_GPR datalabel
            barwidth=0.6 fillattrs=(color=CornFlowerBlue);
            xaxis display=(noline);
  yaxis display=(noline) grid;
  title "Best 5 Annual returns for Gross plus Value Strategy";
run;


proc sgplot data=merge_strategy_ranking_worst;
vbar ranking_GPR / response=cumret_GPR datalabel
            barwidth=0.6 fillattrs=(color=green);
            xaxis display=(noline);
  yaxis display=(noline) grid;
  title "Worst 5 Annual returns for Gross plus Value Strategy";
run;


** 5 (III).***;
*Creating a table with positive monthly returns and % of years with positive annual returns for each of the 3 strategies.;
data positive_years_months;
set abhi;
if GPR_Value>0 then Variable_GPR=1;
else Variable_GPR=0;

if value_momentum>0 then Variable_ValMom=1;
else Variable_ValMom=0;

if Market_Portfolio>0 then Variable_MrktPortf=1;
else Variable_MrktPortf=0;
run;

proc summary data=positive_years_months;
var Variable_GPR Variable_ValMom Variable_MrktPortf;
output out=totals sum=;
run;

data final_months;
set totals;
Variable_GPR=Variable_GPR/384;
Variable_ValMom=Variable_ValMom/384;
Variable_MrktPortf=Variable_MrktPortf/384;
KEEP Variable_GPR Variable_ValMom Variable_MrktPortf;
format Variable_GPR Variable_ValMom Variable_MrktPortf percentn10.2; 
run;

*proc print data=final_months;
*label Variable_GPR="Positive Months for Gross plus Value Strategy";
*label Variable_ValMom="Positive Months for Value plus Momentum Strategy";
*label Variable_MrktPortf="Positive Months for Investing_Market Strategy";
*run;

** Annual returns % **;
data positive_years;
set annual_returns;
if cumret_GPR>0 then Variable_GPR=1;
else Variable_GPR=0;

if cumret_ValMom>0 then Variable_ValMom=1;
else Variable_ValMom=0;

if cumret_mktrf>0 then Variable_MrktPortf=1;
else Variable_MrktPortf=0;
run;

proc summary data=positive_years;
var Variable_GPR Variable_ValMom Variable_MrktPortf;
output out=totals_years sum=;
run;

data final_years;
set totals_years;
Variable_GPR=Variable_GPR/32;
Variable_ValMom=Variable_ValMom/32;
Variable_MrktPortf=Variable_MrktPortf/32;
KEEP Variable_GPR Variable_ValMom Variable_MrktPortf;
format Variable_GPR Variable_ValMom Variable_MrktPortf percentn10.2; 
run;

*proc print data=final_years label;
*label Variable_GPR="Positive Months for Gross plus Value Strategy";
*label Variable_ValMom="Positive Months for Value plus Momentum Strategy";
*label Variable_MrktPortf="Positive Months for Investing_mktrf Strategy";
*run;

data merge_strategy_percentage;
merge final_months final_years ;
by  Variable_GPR Variable_ValMom Variable_MrktPortf;
RUN;

proc transpose data=merge_strategy_percentage out=transposed_percentage;
var Variable_GPR Variable_ValMom Variable_MrktPortf;
run;
proc print data = transposed_percentage label noobs;
label _name_ = "Strategy";
label col1 = "% of positive months";
label col2 = "% of positive years";
title "% of Months and years with positive returns (>0)";
run;

