//+------------------------------------------------------------------+
//| NQ100Tester.mq5                                                   |
//| The MT5 Strategy Tester expert that mirrors our Python branch      |
//| strategy `strategies/agy_intraday_v1.py` so the broker's own      |
//| history can be used for the backtest.                             |
//|                                                                   |
//| Rules (identical to the Python branch):                           |
//|   - timeframe  : 15 minutes (the tester period is set in the ini)|
//|   - trend      : EMA20 vs EMA50                                  |
//|   - momentum   : ROC(20) must agree with the trend               |
//|   - volatility : ATR14/price between 0.10% and 5%                 |
//|   - stop       : 1.5 x ATR14, target 2.25 x ATR14                |
//|   - one position at a time, fixed risk fraction of the balance   |
//|                                                                   |
//| NOTE: written by the manager, NOT yet compiled on the PC -        |
//| Antigravity compiles it (MetaEditor / terminal64.exe /compile:).  |
//+------------------------------------------------------------------+
#property copyright "Nour AI Company"
#property version   "1.00"

#include <Trade\Trade.mqh>

input int      EMA_FAST       = 20;
input int      EMA_SLOW       = 50;
input int      ROC_LEN        = 20;
input int      ATR_LEN        = 14;
input double   MIN_ATR_PCT    = 0.0010;
input double   MAX_ATR_PCT    = 0.0500;
input double   STOP_ATR       = 1.5;
input double   TARGET_ATR     = 2.25;
input double   RISK_PERCENT   = 1.0;      // % of the balance risked per trade
input long     MAGIC          = 20261104;
input ENUM_TIMEFRAMES TF = PERIOD_M15;

CTrade   trade;
datetime lastBar = 0;

bool NewBar()      { datetime t = iTime(_Symbol, TF, 0); if(t == lastBar) return false; lastBar = t; return true; }
bool HasPosition() { for(int i = PositionsTotal()-1; i >= 0; i--) if(PositionGetSymbol(i) == _Symbol) return true; return false; }

double Atr(int len)
{
   int handle = iATR(_Symbol, TF, len);
   if(handle == INVALID_HANDLE) return 0;
   double a[]; ArraySetAsSeries(a, true);
   if(CopyBuffer(handle, 0, 0, len + 2, a) < len + 2) return 0;
   double s = 0; for(int i = 1; i <= len; i++) s += a[i];
   return s / len;
}

double Ema(int span, int shift)
{
   double e[]; ArraySetAsSeries(e, true);
   int n = iMA(_Symbol, TF, span, 0, MODE_EMA, PRICE_CLOSE, shift);
   if(n <= 0 || CopyBuffer(iMA(_Symbol, TF, span, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, e) < 2) return 0;
   return e[1];   // value of the closed bar (shift 1)
}

double Roc(int len)
{
   double c[]; ArraySetAsSeries(c, true);
   if(CopyClose(_Symbol, TF, 0, len + 3, c) < len + 3) return 0;
   double past = c[2 + len];
   if(past <= 0) return 0;
   return (c[2] / past) - 1.0;
}

int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!NewBar()) return;
   if(HasPosition()) return;

   double fast = Ema(EMA_FAST, 1);
   double slow = Ema(EMA_SLOW, 1);
   if(fast <= 0 || slow <= 0) return;
   double roc = Roc(ROC_LEN);
   double atr = Atr(ATR_LEN);
   if(atr <= 0) return;
   double price = iClose(_Symbol, TF, 1);
   if(price <= 0) return;
   double atrPct = atr / price;
   if(atrPct < MIN_ATR_PCT || atrPct > MAX_ATR_PCT) return;

   int dir = 0;
   if(fast > slow && roc > 0)        dir = 1;
   else if(fast < slow && roc < 0)   dir = -1;
   else if(fast > slow && roc > -0.002) dir = 1;
   else if(fast < slow && roc < 0.002)  dir = -1;
   if(dir == 0) return;

   double stopDist   = atr * STOP_ATR;
   double targetDist = atr * TARGET_ATR;
   double sl = (dir == 1) ? price - stopDist : price + stopDist;
   double tp = (dir == 1) ? price + targetDist : price - targetDist;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RISK_PERCENT / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lots = 0;
   if(stopDist > 0 && tickValue > 0)
   {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double lossPerLot = stopDist / tickSize * tickValue;
      if(lossPerLot > 0) lots = riskMoney / lossPerLot;
   }
   lots = MathFloor(lots * 100.0) / 100.0;          // keep it simple and small
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lots < minLot || lots <= 0) return;

   if(dir == 1) trade.Buy(lots, _Symbol, 0.0, sl, tp, "agy entry");
   else         trade.Sell(lots, _Symbol, 0.0, sl, tp, "agy entry");
}
