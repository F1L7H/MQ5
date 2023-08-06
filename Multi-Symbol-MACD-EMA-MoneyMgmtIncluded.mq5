//+------------------------------------------------------------------+
//|                                                      Sandbox.mq5 |
//|                                                    Dylan Gabriel |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Dylan Gabriel"
#property link      "https://www.mql5.com"
#property version   "1.14"



//+------------------------------------------------------------------+
//| Expert Setup                                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>       //Include MQL trade object functions
CTrade   *Trade;                 //Declare Trade as pointer to CTrade class
input int MagicNumber = 14;   //Unique identifier for this expert advisor

//Multi-Symbol EA Variables
enum     MULTISYMBOL {Current, All};
input    MULTISYMBOL InputMultiSymbol = Current;
string   AllTradableSymbols   = "AUDJPY|CADJPY|CHFJPY|EURJPY|GBPJPY|NZDJPY|USDJPY|AUDCHF|CADCHF|EURCHF|GBPCHF|NZDCHF|USDCHF|AUDCAD|EURCAD|GBPCAD|NZDCAD|USDCAD|AUDUSD|EURUSD|GBPUSD|NZDUSD|AUDNZD|EURNZD|GBPNZD|GBPAUD|EURAUD|EURGBP";
int      NumberOfTradableSymbols;
string   SymbolArray[];

//Expert Core Arrays
string          SymbolMetrics[];
int             TicksProcessed[];
static datetime TimeLastTickProcessed[]; 

//Expert Variables
string   ExpertComments = "";
int      TicksReceived  =  0;

//Setup Variables
input string               InpTradeComment   =  __FILE__;      //Optional comment for trades
input ENUM_APPLIED_PRICE   InpAppliedPrice   =  PRICE_CLOSE;   //Applied price for indicators

//Store Position Ticket Number
ulong TicketNumber = 0;

//Risk Metrics
input bool     TslCheck          = true;  //Use Trailing Stop Loss?
input bool     RiskCompounding   = false; //Use Compounded Risk Method?
double         StartingEquity    = 0.0;   //Starting Equity
double         CurrentEquityRisk = 0.0;   //Equity that will be risked per trade
double         CurrentEquity     = 0.0;
input double   MaxLossPrc        = 0.02;  //Percent Risk Per Trade
input double   AtrProfitMulti    = 2.0;   //ATR Profit Multiple
input double   AtrLossMulti      = 1.0;   //ATR Loss Multiple

//Money Management and Variables - ATR
double      MoneyMgmtSignal;
int         AtrHandle[];
int         AtrPeriod = 14;

//Trailing Stop Loss Variables
double      TslSignal;
int         TslHandle[];

//Indicator 1 Variables - MACD
string      IndicatorSignal1;
int         MacdHandle[];
input int   MacdFast    = 12;
input int   MacdSlow    = 26;
input int   MacdSignal  = 9;

//Indicator 2 Variables - EMA
string      IndicatorSignal2;
int         EmaHandle[];
input int   EmaPeriod = 200;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
     // Declare magic number for all trades
     Trade = new CTrade();
     Trade.SetExpertMagicNumber(MagicNumber);
     
     //Set up multi-symbol EA Tradable Symbols
     if(InputMultiSymbol == Current)
     {
         NumberOfTradableSymbols = 1;
         ArrayResize(SymbolArray,NumberOfTradableSymbols);
         SymbolArray[0] = Symbol();
         Print("EA will process ", NumberOfTradableSymbols, " Symbol: ", SymbolArray[0]);
     } else
     {
         NumberOfTradableSymbols = StringSplit(AllTradableSymbols, '|', SymbolArray);
         ArrayResize(SymbolArray,NumberOfTradableSymbols);
         Print("EA will process ", NumberOfTradableSymbols, " Symbols: ", AllTradableSymbols);
     }
     
     //Resize core arrays for Multi-Symbol EA
     ResizeCoreArrays();
     
     //Resize indicator arrays for Multi-Symbol EA
     ResizeIndicatorArrays();
     
     //Resize mmoney management arrays for Multi-Symbol EA
     ResizeMoneyMgmtArrays();
     
     //Set up Multi-Symbol Handles for Indicators
     if(!MacdHandleMultiSymbol() || !EmaHandleMultiSymbol() || !AtrHandleMultiSymbol())
         return(INIT_FAILED);
 
     // Store starting equity oninit
     StartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);    
     
     return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //Release Indicator Arrays
   ReleaseIndicatorArrays();   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //Declare comment variabless
   ExpertComments="";
   TicksReceived++;
   
   //Run multi-symbol loop
      for(int SymbolLoop=0; SymbolLoop < NumberOfTradableSymbols; SymbolLoop++)
      {
         //Store Current Symbol
         string CurrentSymbol = SymbolArray[SymbolLoop];
         
         //Check for new candle based off opening time of bar
         bool IsNewCandle = false;
         if(TimeLastTickProcessed[SymbolLoop] != iTime(CurrentSymbol,Period(),0))
         {
            IsNewCandle    = true;
            TimeLastTickProcessed[SymbolLoop]  = iTime(CurrentSymbol,Period(),0);
         }
         //Process strategy only if is new candle
         if(IsNewCandle == true)
         {
            TicksProcessed[SymbolLoop]++;
            
            //Money Management - ATR
            MoneyMgmtSignal = GetAtrValue(SymbolLoop);
            
            //Indicator 1 - Trigger - MACD
            IndicatorSignal1 = GetMacdOpenSignal(SymbolLoop);
            
            //Indicator 2 - Filter - EMA
            IndicatorSignal2 = GetEmaOpenSignal(SymbolLoop);
            
            //Enter Trades
            if(IndicatorSignal1 == "Long" && IndicatorSignal2 == "Long")
               ProcessTradeOpen(CurrentSymbol, SymbolLoop, ORDER_TYPE_BUY, MoneyMgmtSignal);
            else if(IndicatorSignal1 == "Short" && IndicatorSignal2 == "Short")
               ProcessTradeOpen(CurrentSymbol, SymbolLoop, ORDER_TYPE_SELL, MoneyMgmtSignal);     
            
            //Update Symbol Metrics
            SymbolMetrics[SymbolLoop] = CurrentSymbol +
                                        " | Ticks Processed: " + IntegerToString(TicksProcessed[SymbolLoop])+
                                        " | Last Candle: " + TimeToString(TimeLastTickProcessed[SymbolLoop])+
                                        " | Indicator 1: " + IndicatorSignal1+
                                        " | Indicator 2: " + IndicatorSignal2+
                                        " | Money Mgmt: " + (string)MoneyMgmtSignal;
         }
         
         //Update expert comments for each symbol
         ExpertComments = ExpertComments + SymbolMetrics[SymbolLoop] + "\n\r";
      
      //Comment expert behaviour
      Comment("\n\rExpert: ", MagicNumber, "\n\r",
               "MT5 Server Time: ", TimeCurrent(), "\n\r",
               "Ticks Received: ", TicksReceived,"\n\r\n\r",
               "Symbolss Traded:\n\r",
               ExpertComments
               );
  
      //Counts the number of ticks processed
      TicksProcessed[SymbolLoop]++;
      
      //Check if position is still open.  If not open, return 0.
      if (!PositionSelectByTicket(TicketNumber))
         TicketNumber = 0;
      
      //Adjust Open Positions - Trailing Stop Loss
      if(TslCheck == true)
         AdjustTsl((string)SymbolLoop, TicketNumber, MoneyMgmtSignal, AtrLossMulti);
      }
   }
//+------------------------------------------------------------------+
//| Custom functions                                                 |
//+------------------------------------------------------------------+

//Resize Core Arrays for multi-symbol EA
void ResizeCoreArrays()
   {
      ArrayResize(SymbolMetrics, NumberOfTradableSymbols);
      ArrayResize(TicksProcessed, NumberOfTradableSymbols);
      ArrayResize(TimeLastTickProcessed, NumberOfTradableSymbols);
   }

//Resize Indicator arrays for multi-symbol EA
void ResizeIndicatorArrays()
   {
      //Indicator Handle Arrays
      ArrayResize(MacdHandle, NumberOfTradableSymbols);
      ArrayResize(EmaHandle,  NumberOfTradableSymbols);
   }
   
//Resize Money Management Arrays for multi-symbol EA
void ResizeMoneyMgmtArrays()
   {
      //Money Management Handle Arrays
      ArrayResize(AtrHandle,  NumberOfTradableSymbols);
      ArrayResize(TslHandle,  NumberOfTradableSymbols);
   }

//Release indicator handles from Metatrader cache for multi-symbol EA
void ReleaseIndicatorArrays()
{
   for(int SymbolLoop=0; SymbolLoop < NumberOfTradableSymbols; SymbolLoop++)
   {
      IndicatorRelease(MacdHandle[SymbolLoop]);
      IndicatorRelease(EmaHandle[SymbolLoop]);
      IndicatorRelease(AtrHandle[SymbolLoop]);
      IndicatorRelease(TslHandle[SymbolLoop]);
   }
   Print("Handles released for all symbols");
}


//Set up ATR Handle for Multi-Symbol EA
bool AtrHandleMultiSymbol()
{
   for(int SymbolLoop=0; SymbolLoop < NumberOfTradableSymbols; SymbolLoop++)
      {
         ResetLastError();
         AtrHandle[SymbolLoop] = iATR(SymbolArray[SymbolLoop],Period(),AtrPeriod);
         if(AtrHandle[SymbolLoop] == INVALID_HANDLE)
         {
            string OutputMessage = "";
            if(GetLastError() == 4302)
               OutputMessage = ". Symbol needs to be added to the MArket Watch";
            else
               StringConcatenate(OutputMessage, ". Error Code ", GetLastError());
            MessageBox("Failed to create handle for ATR indicator for " + SymbolArray[SymbolLoop] + OutputMessage);
            return false;
         }
      }
   Print("Handle for ATR for all Symbols successfully created");
   return true;
}
//Custom Function - Get ATR Signals based on indicator
double GetAtrValue(int SymbolLoop)
{
   // Set symbol string and indicator buffers
   const int   StartCandle       = 0;
   const int   RequiredCandles   = 3; //How many candles are required to be stored in Expert
   const int   IndexAtr          = 0; //ATR Value
   double      BufferAtr[];           //[prior,current confirmed,not confirmed]
   
   // Populate buffers for ATR Value; check errors
   bool FillAtr = CopyBuffer(AtrHandle[SymbolLoop],IndexAtr,StartCandle,RequiredCandles,BufferAtr); //Copy buffer uses olds as 0 (reversed)
   if(FillAtr==false)return(0);
   
   // Find ATR Value for Candle '1' Only
   double CurrentAtr = NormalizeDouble(BufferAtr[1],5);
   
   // Return ATR Value
   return(CurrentAtr);
}



//Set up MACD Handle for Multi-Symbol EA
bool MacdHandleMultiSymbol()
{
   for(int SymbolLoop=0; SymbolLoop < NumberOfTradableSymbols; SymbolLoop++)
      {
         ResetLastError();
         MacdHandle[SymbolLoop] = iMACD(SymbolArray[SymbolLoop],Period(),MacdFast,MacdSlow,MacdSignal,PRICE_CLOSE);
         if(MacdHandle[SymbolLoop] == INVALID_HANDLE)
         {
            string OutputMessage = "";
            if(GetLastError() == 4302)
               OutputMessage = ". Symbol needs to be added to the Market Watch";
            else
               StringConcatenate(OutputMessage, ". Error Code ", GetLastError());
            MessageBox("Failed to create handle for MACD indicator for " + SymbolArray[SymbolLoop] + OutputMessage);
            return false;
         }
      }
   Print("Handle for MACD for all Symbols successfully created");
   return true;
}

//Custom Function - Get MACD Open Signals
string GetMacdOpenSignal(int SymbolLoop)
{
   // Set symbol string and indicator buffers
   const int   StartCandle       = 0;
   const int   RequiredCandles   = 3; //How many candles are required to be stored in Expert
   // Indicator Variables and Buffers
   const int   IndexMacd         = 0; //Macd Line
   const int   IndexSignal       = 1; //Signal Line
   double      BufferMacd[];          //[prior,current confirmed,not confirmed]
   double      BufferSignal[];        //[prior,current confirmed,not confirmed]
   
   
   // Define Macd and Signal lines, from not confirmed candle 0, for 3 candles, and store results
   bool        FillMacd    = CopyBuffer(MacdHandle[SymbolLoop],IndexMacd,  StartCandle,RequiredCandles,BufferMacd);
   bool        FillSignal  = CopyBuffer(MacdHandle[SymbolLoop],IndexSignal,StartCandle,RequiredCandles,BufferSignal);
   if(FillMacd==false || FillSignal==false) return "FILL_ERROR"; //If buffers are not completely filled, return to end onTick
   
   // Find required Macd signal lines and normalize to 10 places to prevent rounding errors in crossovers
   double      CurrentMacd    = NormalizeDouble(BufferMacd[1],10);
   double      CurrentSignal  = NormalizeDouble(BufferSignal[1],10);
   double      PriorMacd      = NormalizeDouble(BufferMacd[0],10);
   double      PriorSignal    = NormalizeDouble(BufferSignal[0],10);
   
   
   // Submit Macd Long and Short Trades
   if(PriorMacd <= PriorSignal && CurrentMacd > CurrentSignal && CurrentMacd < 0 && CurrentSignal < 0)
      return "Long";
   else if(PriorMacd >= PriorSignal && CurrentMacd < CurrentSignal && CurrentMacd > 0 && CurrentSignal > 0)
      return "Short";
   else
      return "No Trade";
}


//Set up EMA Handle for Multi-Symbol EA
bool EmaHandleMultiSymbol()
{
   for(int SymbolLoop=0; SymbolLoop < NumberOfTradableSymbols; SymbolLoop++)
   {
      ResetLastError();
      EmaHandle[SymbolLoop] = iMA(SymbolArray[SymbolLoop],Period(),EmaPeriod,0,MODE_EMA,PRICE_CLOSE);
      if(EmaHandle[SymbolLoop] == INVALID_HANDLE)
      {
         string OutputMessage = "";
         if(GetLastError() == 4302)
            OutputMessage = ". Symbol needs to be added to the Market Watch";
         else
            StringConcatenate(OutputMessage, ". Error Code ", GetLastError());
         MessageBox("Failed to create handle for EMA indicator for " + SymbolArray[SymbolLoop] + OutputMessage);
         return false;
      }
   }
   Print("Handle for EMA for all Symbols successfully created");
   return true;
}
//Custom Function - Get EMA Signals based off EMA line and price close - Filter
string GetEmaOpenSignal(int SymbolLoop)
{
   //Set symbol string and indicator buffers
   const int   StartCandle       = 0;
   const int   RequiredCandles   = 2; //How many candles are required to be stored in Expert
   const int   IndexEma          = 0; //EMA Line
   double      BufferEma[];           //[current confirmed,not confirmed]
   
   // Define Ema and Signal lines, from not confirmed candle 0, for 2 candles, and store results
   bool FillEma    = CopyBuffer(EmaHandle[SymbolLoop],IndexEma,StartCandle,RequiredCandles,BufferEma);
   if(FillEma==false)return("FILL_ERROR"); //If buffers are not completely filled, return to end onTick
   
   // Find required EMA signal lines
   double CurrentEma = NormalizeDouble(BufferEma[1],10);
   
   //Get Last confirmed candle price.  NOTE: Use last value as this is when the candle is confirmed.  Ask/bid gives some errors.
   double CurrentClose = NormalizeDouble(iClose(SymbolArray[SymbolLoop],Period(),0), 10);   
   
   //Submit EMA Long and Short Trades
   if(CurrentClose > CurrentEma)
      return "Long";
   else if(CurrentClose < CurrentEma)
      return "Short";
   else
      return "No Trade";
}

// Process trades to enter buy or sell
ulong ProcessTradeOpen(string CurrentSymbol, int SymbolLoop, ENUM_ORDER_TYPE OrderType, double CurrentAtr)
{
   //Set symbol string and variables
   int      SymbolDigits      = (int) SymbolInfoInteger(CurrentSymbol,SYMBOL_DIGITS); //note - typecast required to remove error
   double   Price             = 0.0;
   double   StopLossPrice     = 0.0;
   double   TakeProfitPrice   = 0.0;
   
   // Get price, sl, tp for open and close orders
   if(OrderType == ORDER_TYPE_BUY)
   {
      Price             = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), SymbolDigits);
      StopLossPrice     = NormalizeDouble(Price - MoneyMgmtSignal*AtrLossMulti, SymbolDigits);
      TakeProfitPrice   = NormalizeDouble(Price + MoneyMgmtSignal*AtrProfitMulti, SymbolDigits);
   }
   else if(OrderType == ORDER_TYPE_SELL)
   {
      Price             = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), SymbolDigits);
      StopLossPrice     = NormalizeDouble(Price + MoneyMgmtSignal*AtrLossMulti, SymbolDigits);
      TakeProfitPrice   = NormalizeDouble(Price - MoneyMgmtSignal*AtrProfitMulti, SymbolDigits);
   }
   
   // Get lot size
   double LotSize = OptimalLotSize(CurrentSymbol,Price,StopLossPrice);
   
   // Exit any trades that are currently open; enter new trade
   Trade.PositionClose(CurrentSymbol);
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,TakeProfitPrice,__FILE__);
   
   // Get Position Ticket Number
   ulong  Ticket = PositionGetTicket(0);  
   
   // Add in any error handling
   Print("Trade Processed For ", CurrentSymbol," Order Type ",OrderType, " Lot Size ", LotSize, " Ticket ", Ticket);
   
   //Return the ticket number to onTick
   return(Ticket);
}


// Finds the optimal lot size for the trade
double OptimalLotSize(string CurrentSymbol, double EntryPrice, double StopLoss)
{
   // Set symbol string and calculate point value
   double TickSize      = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_SIZE);
   double TickValue     = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_VALUE);
   if(SymbolInfoInteger(CurrentSymbol,SYMBOL_DIGITS) <= 3)
      TickValue = TickValue/100;
   double PointAmount   = SymbolInfoDouble(CurrentSymbol,SYMBOL_POINT);
   double TicksPerPoint = TickSize/PointAmount;
   double PointValue    = TickValue/TicksPerPoint;
   
   // Calculate risk based off entry and stop loss level by pips
   double RiskPoints = MathAbs((EntryPrice - StopLoss)/TickSize);
   
   // Set risk model - Fixed or Compounding
   if(RiskCompounding == true)
      {
      CurrentEquityRisk = AccountInfoDouble(ACCOUNT_EQUITY);
      CurrentEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   else
      {
      CurrentEquityRisk = StartingEquity;
      CurrentEquity     = AccountInfoDouble(ACCOUNT_EQUITY);     
      }
   
   // Calculate total risk amount in dollars
   double RiskAmount = CurrentEquityRisk * MaxLossPrc;
   
   // Calculate lot size
   double RiskLots   = NormalizeDouble(RiskAmount/(RiskPoints*PointValue),2);
   
   // Print values in Journal to check if operating correctly
   PrintFormat("TickSize=%f,TickValue=%f,PointAmount=%f,TicksPerPoint=%f,PointValue=%f,",
                  TickSize,TickValue,PointAmount,TicksPerPoint,PointValue);
   PrintFormat("EntryPrice=%f,StopLoss=%f,RiskPoints=%f,RiskAmount=%f,RiskLots=%f,",
                  EntryPrice,StopLoss,RiskPoints,RiskAmount,RiskLots);
   
   // Return optimal lot size
   return RiskLots;
}

void AdjustTsl(string CurrentSymbol, ulong Ticket, double CurrentAtr, double AtrMulti)
{
   //Set symbol string and variables
   int    SymbolDigits     = (int) SymbolInfoInteger(CurrentSymbol,SYMBOL_DIGITS);
   double Price            = 0.0;
   double OptimalStopLoss  = 0.0;
   
   //Check correct ticket number is selected for further position data to be stored.  Return if error.
   if (!PositionSelectByTicket(Ticket))
      return;
   
   //Store position data variables
   ulong    PositionDirection = PositionGetInteger(POSITION_TYPE);
   double   CurrentStopLoss   = PositionGetDouble(POSITION_SL);
   double   CurrentTakeProfit = PositionGetDouble(POSITION_TP);
   
   //Check if position direction is long
   if (PositionDirection==POSITION_TYPE_BUY)
   {
      //Set optimal stop loss value
      Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
      OptimalStopLoss = Price - AtrMulti*MoneyMgmtSignal;
      
      //Check if optimal stop loss is greater than current stop loss.  If TRUE, adjust stop loss
      if(OptimalStopLoss > CurrentStopLoss)
      {
         Trade.PositionModify(Ticket,OptimalStopLoss,CurrentTakeProfit);
         Print("Ticket ", Ticket, " for Symbol ", CurrentSymbol," stop loss adjusted to ", OptimalStopLoss);
      }
   
      //Return once complete
      return;
   }
   
   //Check if position direction is short
   if (PositionDirection==POSITION_TYPE_SELL)
   {
      Price = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), SymbolDigits);
      
      //Set optimal stop loss value
      OptimalStopLoss = Price + AtrMulti*MoneyMgmtSignal;
      
      //Check if optimal stop loss is less than current stop loss.  If TRUE, adjust stop loss
      if(OptimalStopLoss < CurrentStopLoss)
      {
         Trade.PositionModify(Ticket,OptimalStopLoss,CurrentTakeProfit);
         Print("Ticket ", Ticket, " for Symbol ", CurrentSymbol," stop loss adjusted to ", OptimalStopLoss);
      }
      
      //Return once complete
      return;
   }
}

//+--------------------------------------------------------------------+