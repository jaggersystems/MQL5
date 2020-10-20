//+------------------------------------------------------------------+
//|     						 	   			           	   RSI MA EA.mq5  |
//|                                 Developed by : Rumman Chowdhury  |
//|                                          rc@rummanchowdhury.xyz  |
//+------------------------------------------------------------------+

#include <MT4Orders.mqh>

#property copyright "Copyright © 2020, Stefan Andrew J."
#property version "1.06"
#property description "Automated Trading EA for RSI MA Strategy"

#property strict

/*
Change Log
from v1.00 : Fix entry candle handling. Allow max#trades=0 handling.
from v1.01 : Add timeframe option
from v1.02 : Add reentry bool option
from v1.03 : Change openTrades array size
from v1.04 : Change Pending order expiry & entry shift to dynamic TF
from v1.05 : Change SL and TP to have MathMax functions
*/

enum lotTypes
{
	fixedLots,		// Fixed
	balanceRisk		// Dynamic Balance Risk
};

enum tradeDirs
{
	buySell,		// Long & Short
	buyOnly,		// Long Only
	sellOnly		// Short Only
};

input string   TRADE_SETTINGS = "--------------- TRADE SETTINGS ---------------";
input int eaMagic = 12345 ;						// EA Magic Number
input int maxNumTrades = 2 ;					// Maximum # Trades [0=Unlimited]
input tradeDirs tradeDir = buySell ;			// Trade Direction
input lotTypes lotMethod = balanceRisk ;		// Position Size Method
input double lotSize = 0.20 ;					// Lot Size (Fixed)
input double lotRisk = 1.0 ;					// Balance Risk % (Dynamic)
input double slFixed = 0 ;						// Fixed SL (Pips) [0=SL Delta]
input double slDelta = 3.0 ;					// PA SL Delta (Pips) [-1=Spread]
input double slDeltaMA = 3.0 ;					// MA SL Delta (Pips) [-1=Spread]
input double beDelta = -1.0 ;					// BE Delta (Pips) [-1=Spread, -2=False]
input double tpFixed = 0 ;						// Fixed TP (Pips) [0=R:R TP]
input double rrRatioTP1 = 1.0 ;					// TP1 Risk:Reward Ratio [0=False]
input double rrRatioTP2 = 2.0 ;					// TP2 Risk:Reward Ratio [0=False]
input int partialPerc = 50 ;					// Partial Close % [0=False]
input int orderExp = 0 ;						// Order Expiry (# Candles)
input int dailyTPTarget = 0 ;					// Daily TP Count [0=Unlimited]
input int dailySLTarget = 0 ;					// Daily SL Count [0=Unlimited]
input int maxSpreadPoints = 3.0 ;				// Max. Spread (Pips)
input int maxSlippage = 3 ;						// Max. Slippage (Points)
input bool mobileNotif = true ;					// Receive Notifications (Mobile)
input string   ENTRY_EXIT_SETTINGS = "--------------- ENTRY/EXIT SETTINGS ---------------";
input int maLookback = 4 ;						// MA Cross Lookback (# Candles)
input double entryDelta = 1.0 ;					// Entry Delta (Pips) [-1=Spread]
input bool useReEntry1 = true ;					// Use ReEntry 1
input bool useReEntry2 = true ;					// Use ReEntry 2
input int reEntryLookback = 5 ;					// ReEntry Lookback (# Candles)
input double rsiLevel = 50.0 ;					// RSI Level
input double maDelta = -2 ;						// MA Trail Delta (Pips) [-1=Spread, -2=False]
input string   PANEL_SETTINGS = "--------------- INFO PANEL SETTINGS ---------------";
input bool drawProfit = true ;					// Notify Profit
input bool drawMagic = true ;					// Notify Magic Number
input string   INDICATOR_SETTINGS = "--------------- INDICATOR SETTINGS ---------------";
input ENUM_TIMEFRAMES indTF = PERIOD_CURRENT ;			// Selected Timeframe
input int maFastPeriod = 8 ;							// Fast MA Period
input ENUM_MA_METHOD maFastMethod = MODE_EMA ;			// Fast MA Method
input ENUM_APPLIED_PRICE maFastPrice = PRICE_CLOSE ;	// Fast MA Applied Price
input int maSlowPeriod = 20 ;							// Slow MA Period
input ENUM_MA_METHOD maSlowMethod = MODE_SMA ;			// Slow MA Method
input ENUM_APPLIED_PRICE maSlowPrice = PRICE_CLOSE ;	// Slow MA Applied Price
input int rsiPeriod = 14 ;								// RSI Period
input ENUM_APPLIED_PRICE rsiPrice = PRICE_CLOSE ;		// RSI Applied Price
input int maPeriod = 20 ;								// Trail MA Period
input ENUM_MA_METHOD maMethod = MODE_SMA ;				// Trail MA Method
input ENUM_APPLIED_PRICE maPrice = PRICE_CLOSE ;		// Trail MA Applied Price



long buyTicket, sellTicket , currentSpread;
long openTrades[][4] ;
double tradeDetails[][3];
int tradeCounter = 0 ;
double stopLossDelta = 0 ;
double newStopLoss, newTakeProfit, SLpips, newSL , entryPrice, tp1 , posSL , bePrice;
bool closeStatus , exitBuy , exitSell;
datetime lastSignal = TimeCurrent()-PeriodSeconds();

double newLot, minLot, maxLot, lotStep, partialLot ;
int lossCounter = 0 ;
double custPoint, pipAmount, nextLot, closedProfit, openProfit, tradeProfit ;
long chartID = ChartID() ;
color openProfColor = clrSeaGreen ;
color closedProfColor = clrSeaGreen ;
int curMinute, curHour, curDay ;
bool weekendShut = false ;
string timeFrameString ;
bool entryRestriction = false ;


double fastMaVals[] , slowMaVals[], maVals[] , rsiVals[];
int rsiHandle , maFastHandle , maSlowHandle , maHandle;
int updateSanity, tradeIndex, barShift , slCount , tpCount;
bool lotUpdated = false ;
double lastBuy , lastSell, positionDelta, cumProfit , pipValue;
long posId ;
ulong modifyAttempt; 
int maxLookBack , entryIndexLong , entryIndexShort;
datetime lastDayUpdate = D'1990.01.01 00:00';
datetime lastEntryTime = D'1990.01.01 00:00' ;

//+------------------------------------------------------------------+
//| Expert Initialisaton function                                   |
//+------------------------------------------------------------------+

int OnInit()
{
	//TesterHideIndicators(true);

	ArrayResize(openTrades, ((maxNumTrades==0)? 9999 : maxNumTrades)) ;
	ArrayResize(tradeDetails, ((maxNumTrades==0)? 9999 : maxNumTrades)) ;
	ArrayFill(openTrades, 0, ArraySize(openTrades),(long) EMPTY_VALUE);
	ArrayFill(tradeDetails, 0, ArraySize(tradeDetails),EMPTY_VALUE);
	lotStep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP) ;
	minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) ;
	maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX) ;
		
	custPoint=_Point ;
	if((_Digits==3) || (_Digits==5))
		custPoint*=10;
	pipAmount = (((SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)*custPoint)/SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE))*1);
	pipValue = getPipValue() ;
	
	
	if(ObjectCreate(0,"panelBack", OBJ_RECTANGLE_LABEL , 0 , 0 , 0))
	{
		ObjectSetInteger(0,"panelBack",OBJPROP_XDISTANCE,5);
		ObjectSetInteger(0,"panelBack",OBJPROP_YDISTANCE,5);
		ObjectSetInteger(0,"panelBack",OBJPROP_XSIZE,160);
		ObjectSetInteger(0,"panelBack",OBJPROP_YSIZE,85);
		ObjectSetInteger(0,"panelBack",OBJPROP_BGCOLOR,clrAliceBlue);
		ObjectSetInteger(0,"panelBack",OBJPROP_COLOR,clrAliceBlue);
		ObjectSetInteger(0,"panelBack",OBJPROP_STYLE,STYLE_SOLID);
		ObjectSetInteger(0,"panelBack",OBJPROP_CORNER,CORNER_LEFT_UPPER);
		ObjectSetInteger(0,"panelBack",OBJPROP_SELECTABLE,false);
		ObjectSetInteger(0,"panelBack",OBJPROP_HIDDEN,true);
		ObjectSetInteger(0,"panelBack",OBJPROP_BACK,false);
	}
	
	ObjectCreate(chartID, "eaLabel", OBJ_LABEL, 0, 0, 0);
	if(ObjectFind(chartID, "eaLabel")>=0)
	{
		ObjectSetString(chartID,"eaLabel",OBJPROP_FONT,"Berlin Sans FB");
		ObjectSetInteger(chartID,"eaLabel",OBJPROP_FONTSIZE, 13);
		ObjectSetInteger(chartID,"eaLabel", OBJPROP_COLOR, clrBlack);
		ObjectSetInteger(chartID,"eaLabel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
		ObjectSetInteger(chartID,"eaLabel", OBJPROP_XDISTANCE, 15);
		ObjectSetInteger(chartID,"eaLabel", OBJPROP_YDISTANCE, 15);
		ObjectSetString(chartID,"eaLabel",OBJPROP_TEXT, "RSI MA EA");
	}
	
	if(drawMagic)
	{
		ObjectCreate(chartID, "Magic Number", OBJ_LABEL, 0, 0, 0);
		if(ObjectFind(chartID, "Magic Number")>=0)
		{
			ObjectSetString(chartID,"Magic Number",OBJPROP_FONT,"Berlin Sans FB");
			ObjectSetInteger(chartID,"Magic Number",OBJPROP_FONTSIZE, 11);
			ObjectSetInteger(chartID,"Magic Number", OBJPROP_COLOR, clrDeepSkyBlue);
			ObjectSetInteger(chartID,"Magic Number", OBJPROP_CORNER, CORNER_LEFT_UPPER);
			ObjectSetInteger(chartID,"Magic Number", OBJPROP_XDISTANCE, 15);
			ObjectSetInteger(chartID,"Magic Number", OBJPROP_YDISTANCE, 35);
			ObjectSetString(chartID,"Magic Number",OBJPROP_TEXT, StringFormat("Magic Number :%d", eaMagic));
		}
	}
	
	if(drawProfit)
	{
		ObjectCreate(chartID, "Open Profit", OBJ_LABEL, 0, 0, 0);
		ObjectSetString(chartID,"Open Profit",OBJPROP_FONT,"Berlin Sans FB");
		ObjectSetInteger(chartID,"Open Profit",OBJPROP_FONTSIZE, 11);
		ObjectSetInteger(chartID,"Open Profit", OBJPROP_CORNER, CORNER_LEFT_UPPER);
		ObjectSetInteger(chartID,"Open Profit", OBJPROP_XDISTANCE, 15);
		ObjectSetInteger(chartID,"Open Profit", OBJPROP_YDISTANCE, 50);
		ObjectSetInteger(chartID,"Open Profit", OBJPROP_COLOR, openProfColor);
		if(ObjectFind(chartID, "Open Profit")>=0)
			ObjectSetString(chartID,"Open Profit",OBJPROP_TEXT, "Open P&L: "+DoubleToString(0.00, 2));
		
		ObjectCreate(chartID, "Realised Profit", OBJ_LABEL, 0, 0, 0);
		ObjectSetString(chartID,"Realised Profit",OBJPROP_FONT,"Berlin Sans FB");
		ObjectSetInteger(chartID,"Realised Profit",OBJPROP_FONTSIZE, 11);
		ObjectSetInteger(chartID,"Realised Profit", OBJPROP_CORNER, CORNER_LEFT_UPPER);
		ObjectSetInteger(chartID,"Realised Profit", OBJPROP_XDISTANCE, 15);
		ObjectSetInteger(chartID,"Realised Profit", OBJPROP_YDISTANCE, 65);
		ObjectSetInteger(chartID,"Realised Profit", OBJPROP_COLOR, closedProfColor);
		if(ObjectFind(chartID, "Realised Profit")>=0)
			ObjectSetString(chartID,"Realised Profit",OBJPROP_TEXT,"Realised P&L: "+DoubleToString(0.00, 2));
	}

	rsiHandle = iRSI(NULL , indTF , rsiPeriod, rsiPrice);
	maFastHandle = iMA(NULL , indTF , maFastPeriod, 0, maFastMethod, maFastPrice);
	maSlowHandle = iMA(NULL , indTF , maSlowPeriod, 0, maSlowMethod, maSlowPrice);
	maHandle = iMA(NULL , indTF , maPeriod, 0, maMethod, maPrice);

	if(handleCheck(rsiHandle, "RSI Handle")==-1)
		return INIT_FAILED;
	
	if(handleCheck(maFastHandle, "Fast MA Handle")==-1)
		return INIT_FAILED;
		
	if(handleCheck(maSlowHandle, "Slow MA Handle")==-1)
		return INIT_FAILED;
		
	if(handleCheck(maHandle, "Trail MA Handle")==-1)
		return INIT_FAILED;
	
	timeFrameString = tfString(indTF);
	maxLookBack = (int) MathMax(maLookback , reEntryLookback)+5 ;
	return INIT_SUCCEEDED ;
}

void OnDeInit()
{
	ObjectsDeleteAll(chartID);
	return ;
}


//+------------------------------------------------------------------+
//| Expert Tick function                                   |
//+------------------------------------------------------------------+

void OnTick() 
{
	if(tradeCounter>0)
	{
		cumProfit = 0.0 ;
		// Handle Order/Position & Profit Tracking
		for(int i=0; i<ArrayRange(openTrades, 0); i++)
		{
			if(openTrades[i][0]!= (long) EMPTY_VALUE)
			{
				if(!OrderSelect(openTrades[i][0]))
				{
					if(!PositionSelectByTicket(openTrades[i][0]))
					{			
						if(!updateProfit(openTrades[i][2]))
							Print("Profit Update Error");

						tradeCloseSanity();						
						openTrades[i][0]= (long) EMPTY_VALUE;
						openTrades[i][1]= (long) EMPTY_VALUE;
						openTrades[i][2]= (long) EMPTY_VALUE;
						openTrades[i][3]= (long) EMPTY_VALUE;
						tradeDetails[i][0] = EMPTY_VALUE;
						tradeDetails[i][1] = EMPTY_VALUE;
						tradeDetails[i][2] = EMPTY_VALUE;
						return ;
					}
					else
					{
					   if(openTrades[i][2] == (long) EMPTY_VALUE)
						   openTrades[i][2] = PositionGetInteger(POSITION_IDENTIFIER) ;
						cumProfit += getPositionProfit(openTrades[i][0]) ;
					}
				}

				if(cumProfit<0)
					openProfColor = clrCrimson ;
				else
					openProfColor = clrSeaGreen ;
				if(ObjectFind(chartID, "Open Profit")>=0)
				{
					ObjectSetString(chartID,"Open Profit",OBJPROP_TEXT, "Open P&L: "+DoubleToString(cumProfit, 2));
					ObjectSetInteger(chartID,"Open Profit", OBJPROP_COLOR, openProfColor);
				}
			}
		}
		
		currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
		updateSanity = updateBuffers();
		if(updateSanity<0)
			PrintFormat("Buffer Update Error: %d", updateSanity);
		
		
		for(int i=0; i<ArrayRange(openTrades, 0); i++)
		{
			if(openTrades[i][0]!= (long) EMPTY_VALUE)
			{
				if(OrderSelect(openTrades[i][0]))
				{
					if((openTrades[i][1]==POSITION_TYPE_BUY && fastMaVals[1]<slowMaVals[1]) || (openTrades[i][1]==POSITION_TYPE_SELL && fastMaVals[1]>slowMaVals[1]))
					{
						if(OrderDelete(openTrades[i][0], clrYellow))
						{
							Alert(StringFormat("RSI MA Pending Order Cancelled: %s %s", Symbol(), timeFrameString));
							tradeCounter--;						
							openTrades[i][0]= (long) EMPTY_VALUE;
							openTrades[i][1]= (long) EMPTY_VALUE;
							openTrades[i][2]= (long) EMPTY_VALUE;
							openTrades[i][3]= (long) EMPTY_VALUE;
							tradeDetails[i][0] = EMPTY_VALUE;
							tradeDetails[i][1] = EMPTY_VALUE;
							tradeDetails[i][2] = EMPTY_VALUE;
							return ;
						}
						else
							Print("Pending Order Cancel Error: %d", GetLastError());
					}
				}
				else if(PositionSelectByTicket(openTrades[i][0]))
				{
					if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
					{
						// Partial Close
						if(tradeDetails[i][2]==0 && partialPerc!=0 && tradeDetails[i][0]!= EMPTY_VALUE && SymbolInfoDouble(_Symbol,SYMBOL_BID)>=tradeDetails[i][0])
						{
							partialLot = normalizeLot(PositionGetDouble(POSITION_VOLUME)*partialPerc/100);
							if(PositionGetDouble(POSITION_VOLUME)-partialLot>=minLot)
							{
								closeStatus = OrderClose(openTrades[i][0], partialLot, SymbolInfoDouble(_Symbol,SYMBOL_BID), maxSlippage, clrDodgerBlue);
								if(closeStatus)
								{
									Alert("RSI MA Buy Partial Exit , Order ", openTrades[i][0]);
									tradeDetails[i][1] = 1 ;
									tradeDetails[i][2] = 1 ;
									if(!updateProfit(openTrades[i][2]))
											Print("Profit Update Error");
								}
								else
									Print("RSI MA Buy Partial Close Error:", GetLastError());
							}
							else
							{
								closeStatus = OrderClose(openTrades[i][0], PositionGetDouble(POSITION_VOLUME), SymbolInfoDouble(_Symbol,SYMBOL_BID), maxSlippage, clrDodgerBlue);
								if(closeStatus)
								{
									Alert("RSI MA Buy Full Close (Partial Force) Exit , Order ", openTrades[i][0]);
									
									if(!updateProfit(openTrades[i][2]))
										Print("Profit Update Error");

									tradeCloseSanity();						
									openTrades[i][0]= (long) EMPTY_VALUE;
									openTrades[i][1]= (long) EMPTY_VALUE;
									openTrades[i][2]= (long) EMPTY_VALUE;
									openTrades[i][3]= (long) EMPTY_VALUE;
									tradeDetails[i][0] = EMPTY_VALUE;
									tradeDetails[i][1] = EMPTY_VALUE;
									tradeDetails[i][2] = EMPTY_VALUE;
									return ;										
								}
								else
									Print("RSI MA Buy Full Close (Partial Force) Error:", GetLastError());
							}
						}
						
						// Check for BE / Trail, once TP1 utilised
						if(tradeDetails[i][1] == 1)
						{
							// Check BE
							posSL = PositionGetDouble(POSITION_SL) ;
							bePrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN)+((beDelta==-1)? (currentSpread*_Point): (beDelta*pipValue)),_Digits);
							if(beDelta!=-2 && SymbolInfoDouble(_Symbol,SYMBOL_BID)>=tradeDetails[i][0] && posSL<bePrice)
							{
								modifyAttempt = modifySL(openTrades[i][0] , bePrice, PositionGetDouble(POSITION_TP)) ;
								if(modifyAttempt!=-1)
									Print("RSI MA Buy SL Modified (BE), Order ", openTrades[i][0]);
								else
									Alert(StringFormat("RSI MA Buy SL (BE) Modify Error: %d", GetLastError()));
							}
							
							// Check MA Trail
							if(maDelta!=-2)
							{
								if(iLow(NULL , indTF , 1)<maVals[1])
								{
									newSL = NormalizeDouble(iLow(NULL , indTF , 1)-((maDelta==-1)? (currentSpread*_Point): (maDelta*pipValue)),_Digits);
									if(newSL>PositionGetDouble(POSITION_SL))
									{
										modifyAttempt = modifySL(openTrades[i][0] , newSL, PositionGetDouble(POSITION_TP)) ;
										if(modifyAttempt!=-1)
											Print("RSI MA Buy SL Modified (MA Trail), Order ", openTrades[i][0]);
										else
											Alert(StringFormat("RSI MA Buy SL (MA Trail) Modify Error: %d", GetLastError()));
									}
								}
							}
						}
					}
					else
					{
						// Partial Close
						if(tradeDetails[i][2]==0 && partialPerc!=0 && tradeDetails[i][0]!= EMPTY_VALUE && SymbolInfoDouble(_Symbol,SYMBOL_ASK)<=tradeDetails[i][0])
						{
							partialLot = normalizeLot(PositionGetDouble(POSITION_VOLUME)*partialPerc/100);
							if(PositionGetDouble(POSITION_VOLUME)-partialLot>=minLot)
							{
								closeStatus = OrderClose(openTrades[i][0], partialLot, SymbolInfoDouble(_Symbol,SYMBOL_ASK), maxSlippage, clrDodgerBlue);
								if(closeStatus)
								{
									Alert("RSI MA Sell Partial Exit , Order ", openTrades[i][0]);
									tradeDetails[i][1] = 1 ;
									tradeDetails[i][2] = 1 ;
									if(!updateProfit(openTrades[i][2]))
											Print("Profit Update Error");
								}
								else
									Print("RSI MA Sell Partial Close Error:", GetLastError());
							}
							else
							{
								closeStatus = OrderClose(openTrades[i][0], PositionGetDouble(POSITION_VOLUME), SymbolInfoDouble(_Symbol,SYMBOL_ASK), maxSlippage, clrDodgerBlue);
								if(closeStatus)
								{
									Alert("RSI MA Sell Full Close (Partial Force) Exit , Order ", openTrades[i][0]);
									if(!updateProfit(openTrades[i][2]))
											Print("Profit Update Error");
									tradeCloseSanity();						
									openTrades[i][0]= (long) EMPTY_VALUE;
									openTrades[i][1]= (long) EMPTY_VALUE;
									openTrades[i][2]= (long) EMPTY_VALUE;
									openTrades[i][3]= (long) EMPTY_VALUE;
									tradeDetails[i][0] = EMPTY_VALUE;
									tradeDetails[i][1] = EMPTY_VALUE;
									tradeDetails[i][2] = EMPTY_VALUE;
									return ;
								}
								else
									Print("RSI MA Sell Full Close (Partial Force) Error:", GetLastError());
							}
						}
						
						// Check for BE / Trail, once TP1 utilised
						if(tradeDetails[i][1] == 1)
						{
							// Check BE
							posSL = PositionGetDouble(POSITION_SL) ;
							bePrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN)-((beDelta==-1)? (currentSpread*_Point): (beDelta*pipValue)),_Digits);
							if(beDelta!=-2 && SymbolInfoDouble(_Symbol,SYMBOL_ASK)<=tradeDetails[i][0] && posSL>bePrice)
							{
								modifyAttempt = modifySL(openTrades[i][0] , bePrice, PositionGetDouble(POSITION_TP)) ;
								if(modifyAttempt!=-1)
									Print("RSI MA Sell SL Modified (BE), Order ", openTrades[i][0]);
								else
									Alert(StringFormat("RSI MA Sell SL (BE) Modify Error: %d", GetLastError()));
							}
							
							// Check MA Trail
							if(maDelta!=-2)
							{
								if(iHigh(NULL , indTF , 1)>maVals[1])
								{
									newSL = NormalizeDouble(iHigh(NULL , indTF , 1)+((maDelta==-1)? (currentSpread*_Point): (maDelta*pipValue)),_Digits);
									if(newSL<PositionGetDouble(POSITION_SL))
									{
										modifyAttempt = modifySL(openTrades[i][0] , newSL, PositionGetDouble(POSITION_TP)) ;
										if(modifyAttempt!=-1)
											Print("RSI MA Sell SL Modified (MA Trail), Order ", openTrades[i][0]);
										else
											Alert(StringFormat("RSI MA Sell SL (MA Trail) Modify Error: %d", GetLastError()));
									}
								}
							}
						}
					}
				}
			}
		}
	}

	// If number of open trades less than maximum allowed, check conditions for entry
	if(maxNumTrades==0 || tradeCounter<maxNumTrades)
	{
		updateSanity = updateBuffers();
		if(updateSanity<0)
			PrintFormat("Buffer Update Error: %d", updateSanity);
			
		if((tradeDir==0 || tradeDir==1) &&  entryCheck(POSITION_TYPE_BUY) && (lastSignal <= (TimeCurrent()-PeriodSeconds(indTF))))
		{
			currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
			if(currentSpread*_Point<=maxSpreadPoints*pipValue)
			{
				updateSLTP(POSITION_TYPE_BUY);
				
				tradeIndex = getIndex() ;
				if(tradeIndex==-1)
				{
					Print("Trade Index Error. Trade Rejected");
					return ;
				}
				
				if(!lotUpdated)
				{
					updateLotSize();
					lotUpdated = true ;
				}
				
				buyTicket=OrderSend(Symbol(),((entryPrice>SymbolInfoDouble(_Symbol, SYMBOL_ASK))? OP_BUYSTOP : OP_BUYLIMIT) ,newLot, entryPrice ,maxSlippage,newStopLoss,newTakeProfit,
										StringFormat("RSI MA Buy %s", timeFrameString),eaMagic,((orderExp==0)? 0 : (TimeCurrent()+orderExp*PeriodSeconds(indTF))),clrGreen);
				if(buyTicket!=-1)
				{
					Alert("RSI MA Buy Opened, ", Symbol(), ", ",timeFrameString);
					if(mobileNotif)
						SendNotification(StringFormat("RSI MA Buy Opened: %s ; %s " , Symbol() , timeFrameString));
					lastSignal = TimeCurrent();
					openTrades[tradeIndex][0] = buyTicket;
					openTrades[tradeIndex][1] = POSITION_TYPE_BUY;
					openTrades[tradeIndex][3] = 0 ;
					tradeDetails[tradeIndex][0] = tp1 ;
					PrintFormat("TP1: %s", DoubleToString(tradeDetails[tradeIndex][0], _Digits));
					tradeDetails[tradeIndex][1] = 0 ;
					tradeDetails[tradeIndex][2] = 0 ;
					tradeCounter++;
					lotUpdated = false ;
					return ;
				}
				else
					Alert("RSI MA Buy failed, ", Symbol(),", Error:", GetLastError());
				
			}
		}
		if((tradeDir==0 || tradeDir==2) && entryCheck(POSITION_TYPE_SELL) && (lastSignal <= (TimeCurrent()-PeriodSeconds(indTF))))	// 
		{
			currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
			if(currentSpread*_Point<=maxSpreadPoints*pipValue)
			{
				updateSLTP(POSITION_TYPE_SELL);
				
				tradeIndex = getIndex() ;
				if(tradeIndex==-1)
				{
					Print("Trade Index Error. Trade Rejected");
					return ;
				}
				
				if(!lotUpdated)
				{
					updateLotSize();
					lotUpdated = true ;
				}
				
				sellTicket=OrderSend(Symbol(),((entryPrice<SymbolInfoDouble(_Symbol, SYMBOL_BID))? OP_SELLSTOP : OP_SELLLIMIT),newLot, entryPrice ,maxSlippage,newStopLoss,newTakeProfit,
										StringFormat("RSI MA Sell %s", timeFrameString),eaMagic,((orderExp==0)? 0 : (TimeCurrent()+orderExp*PeriodSeconds(indTF))),clrGreen);
				if(sellTicket!=-1)
				{
					Alert("RSI MA Sell Opened, ", Symbol(), ", ", timeFrameString);
					if(mobileNotif)
						SendNotification(StringFormat("RSI MA Sell Opened: %s ; %s " , Symbol() , timeFrameString));
					lastSignal = TimeCurrent();
					openTrades[tradeIndex][0] = sellTicket;
					openTrades[tradeIndex][1] = POSITION_TYPE_SELL;
					openTrades[tradeIndex][3] = 0 ;
					tradeDetails[tradeIndex][0] = tp1 ;
					PrintFormat("TP1: %s", DoubleToString(tradeDetails[tradeIndex][0], _Digits));
					tradeDetails[tradeIndex][1] = 0 ;
					tradeDetails[tradeIndex][2] = 0 ;
					tradeCounter++;
					return ;
				}
				else
					Alert("RSI MA Sell failed, ", Symbol(),", Error:", GetLastError());
			}
		}
	}

	return ;
}

int getIndex()
{
	if(openTrades[tradeCounter][0]==(long)EMPTY_VALUE)
		return tradeCounter ;
	else
	{
		for(int i=0 ; i<ArrayRange(openTrades,0) ; i++)
		{
			if(openTrades[i][0]==(long)EMPTY_VALUE)
				return i ;
		}
	}
	return -1 ;
}

void updateLotSize()
{
	updateBaseLot() ;
	newLot = MathFloor(newLot/lotStep)*lotStep ;
	
	if(newLot<minLot)
		newLot = minLot ;
	else if(newLot>maxLot)
		newLot = maxLot ;
	
	return ;
}

double normalizeLot(double baseLot)
{
	double tempLot = MathFloor(baseLot/lotStep)*lotStep ;
	
	if(tempLot<minLot)
		tempLot = minLot ;
	
	return tempLot ;
}

void updateBaseLot()
{
	if(lotMethod==0)
		newLot = lotSize ;
	else
	{
		if(stopLossDelta!=0)
			newLot = (AccountInfoDouble(ACCOUNT_BALANCE)*(lotRisk/100)) / (stopLossDelta * pipAmount) ;
		else
			newLot = (AccountInfoDouble(ACCOUNT_BALANCE)*(lotRisk/100)) / (10 * pipAmount) ;		// If no stop loss set, use 10 default default SL
	}
	
	return ;
}

void updateSLTP(ENUM_POSITION_TYPE type)
{
	double maSL , paSL ;
	if(type==POSITION_TYPE_BUY)
		entryPrice = iHigh(NULL , indTF , entryIndexLong) + ((entryDelta==-1)? (currentSpread*_Point) : (entryDelta*pipValue));
	else
		entryPrice = iLow(NULL , indTF , entryIndexShort) - ((entryDelta==-1)? (currentSpread*_Point) : (entryDelta*pipValue));
			
	if(slFixed==0)
	{	
		if(type==POSITION_TYPE_BUY)
		{
			maSL = MathMin(fastMaVals[entryIndexLong] , slowMaVals[entryIndexLong]);
			paSL = iLow(NULL , indTF , entryIndexLong);
			newStopLoss = (maSL<paSL)? (maSL-((slDeltaMA==-1)? (currentSpread*_Point) : (slDeltaMA*pipValue))) :  (paSL-((slDelta==-1)? (currentSpread*_Point) : (slDelta*pipValue)));
			stopLossDelta = (entryPrice - newStopLoss)/pipValue ;
		}
		else
		{
			maSL = MathMax(fastMaVals[entryIndexShort] , slowMaVals[entryIndexShort]);
			paSL = iHigh(NULL , indTF , entryIndexShort);
			newStopLoss = (maSL>paSL)? (maSL+((slDeltaMA==-1)? (currentSpread*_Point) : (slDeltaMA*pipValue))) :  (paSL+((slDelta==-1)? (currentSpread*_Point) : (slDelta*pipValue)));
			stopLossDelta = (newStopLoss - entryPrice)/pipValue ;
		}
	}
	else
	{
		stopLossDelta = slFixed ;
		if(type==POSITION_TYPE_BUY)
			newStopLoss = entryPrice - stopLossDelta*pipValue;
		else
			newStopLoss = entryPrice + stopLossDelta*pipValue ;
	}

	if(tpFixed!=0)
	{
		if(type==POSITION_TYPE_BUY)
			newTakeProfit = entryPrice + tpFixed*pipValue;
		else
			newTakeProfit = entryPrice - tpFixed*pipValue ;
	}
	else if(rrRatioTP2!=0)
	{
		if(type==POSITION_TYPE_BUY)
			newTakeProfit = entryPrice+(stopLossDelta*pipValue*rrRatioTP2);
		else
			newTakeProfit = entryPrice-(stopLossDelta*pipValue*rrRatioTP2);
		
	}
	else if(rrRatioTP1!=0)
	{
		if(type==POSITION_TYPE_BUY)
			newTakeProfit = entryPrice+(stopLossDelta*pipValue*rrRatioTP1);
		else
			newTakeProfit = entryPrice-(stopLossDelta*pipValue*rrRatioTP1);
	}	
	else
		newTakeProfit = 0 ;
	
	if(rrRatioTP1!=0 && tpFixed==0)
	{
		if(type==POSITION_TYPE_BUY)
			tp1 = entryPrice+(stopLossDelta*pipValue*rrRatioTP1);
		else
			tp1 = entryPrice-(stopLossDelta*pipValue*rrRatioTP1);
		
		tp1 = NormalizeDouble(tp1, _Digits);
	}
	else
		tp1 = EMPTY_VALUE ;
	
	newStopLoss = NormalizeDouble(MathMax(0, newStopLoss), _Digits);
	newTakeProfit = NormalizeDouble(MathMax(0,newTakeProfit), _Digits);
	
	
	return ;
}

void tradeCloseSanity()
{
	closedProfit += tradeProfit ;
	if(tradeProfit<0)
	{
		lossCounter++;
		Alert("RSI MA Loss Realised, ", Symbol(), ", ", timeFrameString);
		slCount++;
	}
	else
	{
		lossCounter = 0 ;
		Alert("RSI MA Profit Realised, ", Symbol(), ", ", timeFrameString);
		tpCount++;
	}
	
	if(mobileNotif)
		SendNotification(StringFormat("RSI MA Trade Closed: %s ; %s ; (%s)" , Symbol() , timeFrameString , DoubleToString(tradeProfit, 2) ));
										
	if(closedProfit<0)
		closedProfColor = clrCrimson ;
	else
		closedProfColor = clrSeaGreen ;
	
	if(ObjectFind(chartID, "Realised Profit")>=0)
	{
		ObjectSetString(chartID, "Realised Profit",OBJPROP_TEXT, "Realised P&L: "+DoubleToString(closedProfit, 2));
		ObjectSetInteger(chartID, "Realised Profit", OBJPROP_COLOR , closedProfColor);
	}
	if(ObjectFind(chartID, "Open Profit")>=0)
	{
		ObjectSetString(chartID,"Open Profit",OBJPROP_TEXT, "Open P&L: "+DoubleToString(0.00, 2));
		ObjectSetInteger(chartID, "Open Profit", OBJPROP_COLOR , clrSeaGreen);
	}
	
	tradeCounter--;
	return ;
}

bool entryCheck(ENUM_POSITION_TYPE type)
{
	if(!dayStatCheck())
		return false ;

	if(tradeCounter==0 && rsiCheck(type) && maCheck(type))
		return true ;
	else if(reEntryCheck(type) && ((useReEntry1 && activeCheck(type)) ||  (useReEntry2 && tradeCounter==0)) )
		return true ;
	
	return false ;
}

bool activeCheck(ENUM_POSITION_TYPE type)
{
	if(tradeCounter>0)
	{
		for(int i=0 ; i<ArrayRange(openTrades, 0) ; i++)
		{
			if(PositionSelectByTicket(openTrades[i][0]))
			{
				if(PositionGetInteger(POSITION_TYPE)==type)
					return true ;
			}
		}
	}
	return false ;
}

bool dayStatCheck()
{
	if(lastDayUpdate!=iTime(NULL,PERIOD_D1,1))
	{
		lastDayUpdate = iTime(NULL,PERIOD_D1,1) ;
		tpCount = 0 ;
		slCount = 0 ;
	}
	else
	{
		if(dailyTPTarget!=0 && tpCount>=dailyTPTarget)
			return false ;
		
		if(dailySLTarget!=0 && slCount>=dailySLTarget)
			return false ;
	}
	
	return true ;
}

bool rsiCheck(ENUM_POSITION_TYPE type)
{
	if((type==POSITION_TYPE_BUY && rsiVals[1]>rsiLevel) || (type==POSITION_TYPE_SELL && rsiVals[1]<rsiLevel))
		return true ;
	return false ;
}

bool maCheck(ENUM_POSITION_TYPE type)
{
	for(int i=1 ; i<=MathMax(1, maLookback) ; i++)
	{
		if(type==POSITION_TYPE_BUY)
		{
			if(fastMaVals[0]>slowMaVals[0] && fastMaVals[i]>slowMaVals[i] && fastMaVals[i+1]<=slowMaVals[i+1])
			{
				if(iTime(NULL , indTF , i)>lastEntryTime)
				{
					lastEntryTime = iTime(NULL , indTF , i) ;
					entryIndexLong = i ;
					return true ;
				}
			}
		}
		else
		{
			if(fastMaVals[0]<slowMaVals[0] && fastMaVals[i]<slowMaVals[i] && fastMaVals[i+1]>=slowMaVals[i+1])
			{
				if(iTime(NULL , indTF , i)>lastEntryTime)
				{
					lastEntryTime = iTime(NULL , indTF , i) ;
					entryIndexShort = i ;
					return true ;
				}
			}
		}
	}
	return false ;
}

bool reEntryCheck(ENUM_POSITION_TYPE type)
{
	if(iTime(NULL , indTF , 1)>lastEntryTime)
	{
		if(type==POSITION_TYPE_BUY && rsiVals[1]>rsiLevel && rsiVals[2]<=rsiLevel && fastMaVals[1]>slowMaVals[1])
		{
			if(reEntryLookback==0)
			{
				entryIndexLong = 1 ;
				lastEntryTime = iTime(NULL , indTF , 1) ;
				return true ;
			}
			else
			{
				for(int i=2 ; i<=2+reEntryLookback ; i++)
				{
					if(fastMaVals[i]>=slowMaVals[i] && fastMaVals[i+1]<slowMaVals[i+1])
					{
						entryIndexLong = 1 ;
						lastEntryTime = iTime(NULL , indTF , 1) ;
						return true ;
					}
				}
			}
		}
		else if(type==POSITION_TYPE_SELL && rsiVals[1]<rsiLevel && rsiVals[2]>=rsiLevel && fastMaVals[1]<slowMaVals[1])
		{
			if(reEntryLookback==0)
			{
				entryIndexShort = 1 ;
				return true ;
			}
			else
			{
				for(int i=2 ; i<=2+reEntryLookback ; i++)
				{
					if(fastMaVals[i]<=slowMaVals[i] && fastMaVals[i+1]>slowMaVals[i+1])
					{
						entryIndexShort = 1 ;
						return true ;
					}
				}
			}
		}
	}
	return false ;
}


double getPipValue()
{
   if(_Digits<=3){
      return(0.01);
   }
   else if(_Digits>=4){
      return(0.0001);
   }
   else return(0);
}


string tfString(int tfC)
{
	switch(tfC)
	{
		case PERIOD_CURRENT:
			return tfString(_Period);
		case PERIOD_M1:
			return "M1";
		case PERIOD_M2:
			return "M2";
		case PERIOD_M3:
			return "M3";
		case PERIOD_M4:
			return "M4";
		case PERIOD_M5:
			return "M5";
		case PERIOD_M6:
			return "M6";
		case PERIOD_M10:
			return "M10";
		case PERIOD_M12:
			return "M12";
		case PERIOD_M15:
			return "M15";
		case PERIOD_M20:
			return "M20";
		case PERIOD_M30:
			return "M30";
		case PERIOD_H1:
			return "H1";
		case PERIOD_H2:
			return "H2";
		case PERIOD_H3:
			return "H3";
		case PERIOD_H4:
			return "H4";
		case PERIOD_H6:
			return "H6";
		case PERIOD_H8:
			return "H8";
		case PERIOD_H12:
			return "H12";
		case PERIOD_D1:
			return "D1";
		case PERIOD_W1:
			return "W1";
		case PERIOD_MN1:
			return "MN1";
		default:
			return "INVALID TF";
			break;
	}
}

int handleCheck(int handleReturn, string handleName)
{
	if(handleReturn<0)
	{
		PrintFormat("The creation of %s has failed.", handleName);
		Print("Runtime error = ",GetLastError());
		return(-1);
	}
	else 
		return 0 ;
}

bool CopyBufferAsSeries(int handle,int buffer,int start, int number,bool asSeries,double &M[])
{
	if(CopyBuffer(handle,buffer,start,number,M)<=0) 
		return(false);
	ArraySetAsSeries(M,asSeries);
	return(true);
}


bool getIndicatorBuffers(int handleA, int handleB, int handleC, int handleD , int start, int number, double &arr1[], double &arr2[], double &arr3[] , double &arr4[], bool asSeries=true)
{
	// RSI
	if(!CopyBufferAsSeries(handleA,0,start,number,asSeries,arr1)) 
		return(false);
		
	// MA Fast
	if(!CopyBufferAsSeries(handleB,0,start,number,asSeries,arr2)) 
		return(false);
	
	// MA Slow
	if(!CopyBufferAsSeries(handleC,0,start,number,asSeries,arr3)) 
		return(false);
	
	// MA Trail
	if(!CopyBufferAsSeries(handleD,0,start,number,asSeries,arr4)) 
		return(false);
	
	return(true);
}

int updateBuffers()
{
	if(!getIndicatorBuffers(rsiHandle, maFastHandle , maSlowHandle , maHandle,  0 , maxLookBack , rsiVals, fastMaVals , slowMaVals, maVals,  true)) 
		return -1;

	return 0 ;
}

bool updateProfit(long pID)
{
	tradeProfit = 0 ;
	if(HistorySelectByPosition(pID))
	{
		for(int i= HistoryDealsTotal()-1 ; i>=0 ; i--)
		{
			ulong dealTicket = HistoryDealGetTicket(i);
			if(HistoryDealGetDouble(dealTicket,DEAL_PROFIT)!=0)
				tradeProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
			if(HistoryDealGetDouble(dealTicket,DEAL_COMMISSION)!=0)
				tradeProfit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
			if(HistoryDealGetDouble(dealTicket,DEAL_SWAP)!=0)
				tradeProfit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
		}
	}
	
	if(tradeProfit!=0)
		return true ;

	return false ;
}

double getPositionProfit(long ticketNumber)
{
	if(PositionSelectByTicket(ticketNumber))
		return PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
	return -1;
}

ulong modifySL(long ticketNumber, double SL, double TP)
{
	MqlTradeRequest request;
	MqlTradeResult  result;
	ZeroMemory(request);
	ZeroMemory(result);
	request.action  =TRADE_ACTION_SLTP;
	request.position=ticketNumber;
	request.symbol= _Symbol;
	request.sl      =SL;
	request.tp      =TP;
	if(!OrderSend(request,result))
	{
		PrintFormat("OrderSend error %d",GetLastError());
		return -1 ;
	}
	else
		return result.deal ;
}


double OnTester()
{
	double ret=0.0;
	double array[];
	double trades_volume;
	GetTradeResultsToArray(array,trades_volume);
	int trades=ArraySize(array);
	if(trades<15)
		return (0);
	double average_pl=0;
	for(int i=0;i<ArraySize(array);i++)
		average_pl+=array[i];
	average_pl/=trades;

	if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
		PrintFormat("%s: Trades=%d, Average profit=%.2f",__FUNCTION__,trades,average_pl);

	double a,b,std_error;
	double chart[];
	if(!CalculateLinearRegression(array,chart,a,b))
		return (0);

	if(!CalculateStdError(chart,a,b,std_error))
		return (0);

	ret=a*trades/std_error;

	return ret ;
}

bool GetTradeResultsToArray(double &pl_results[],double &volume)
{
	if(!HistorySelect(0,TimeCurrent()))
		return (false);
	uint total_deals=HistoryDealsTotal();
	volume=0;
	ArrayResize(pl_results,total_deals);
	int counter=0;
	ulong ticket_history_deal=0;
	for(uint i=0;i<total_deals;i++)
	{
		if((ticket_history_deal=HistoryDealGetTicket(i))>0)
		{
			ENUM_DEAL_ENTRY deal_entry  =(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket_history_deal,DEAL_ENTRY);
			long            deal_type   =HistoryDealGetInteger(ticket_history_deal,DEAL_TYPE);
			double          deal_profit =HistoryDealGetDouble(ticket_history_deal,DEAL_PROFIT);
			double          deal_volume =HistoryDealGetDouble(ticket_history_deal,DEAL_VOLUME);
			if((deal_type!=DEAL_TYPE_BUY) && (deal_type!=DEAL_TYPE_SELL))
				continue;
			if(deal_entry!=DEAL_ENTRY_IN)
			{
				pl_results[counter]=deal_profit;
				volume+=deal_volume;
				counter++;
			}
		}
	}
	ArrayResize(pl_results,counter);
	return true ;
}

bool CalculateLinearRegression(double  &change[],double &chartline[],
                               double  &a_coef,double  &b_coef)
{
	if(ArraySize(change)<3)
		return (false);
	int N=ArraySize(change);
	ArrayResize(chartline,N);
	chartline[0]=change[0];
	for(int i=1;i<N;i++)
		chartline[i]=chartline[i-1]+change[i];

	double x=0,y=0,x2=0,xy=0;
	for(int i=0;i<N;i++)
	{
		x=x+i;
		y=y+chartline[i];
		xy=xy+i*chartline[i];
		x2=x2+i*i;
	}
	a_coef=(N*xy-x*y)/(N*x2-x*x);
	b_coef=(y-a_coef*x)/N;

	return true ;
}

bool  CalculateStdError(double  &data[],double  a_coef,double  b_coef,double &std_err)
{
	double error=0;
	int N=ArraySize(data);
	if(N==0)
		return (false);
	for(int i=0;i<N;i++)
		error=MathPow(a_coef*i+b_coef-data[i],2);
	std_err=MathSqrt(error/(N-2));

	return true ;
}
