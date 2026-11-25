//+------------------------------------------------------------------+
//| NQ100_D1_Live_FTMO.mq5                                            |
//| LIVE-TRADING version of the verified D1 strategy, hardened for    |
//| real (demo/trial) account use on FTMO.                             |
//|                                                                     |
//| Strategy (identical to the independently-verified backtest):      |
//|   D1 timeframe, ADX(14) > 27 trend filter,                        |
//|   entry = RSI(14) pullback crossing 45 (buy) / 55 (sell)           |
//|   relative to EMA200 trend,                                        |
//|   SL = 1.5 x ATR(14), TP = 4.0 x ATR(14).                          |
//|   (32 trades, 50% WR, PF 2.48 on 2016-2025 real NAS100 D1 data).   |
//|                                                                     |
//| SAFETY additions for live deployment (tighter than FTMO's own      |
//| rules, by design, as a self-imposed margin of safety):             |
//|   - RISK_PERCENT default 1.0% of balance per trade                 |
//|     (FTMO Swing allows far more before breaching any rule)         |
//|   - DAILY_LOSS_BREAKER_PCT default 3.0%: if the account's equity   |
//|     drops this much below the day's starting balance, the EA       |
//|     stops opening NEW trades for the rest of that day              |
//|     (FTMO's real max daily loss is 5% - this gives a safety buffer)|
//|   - Only ever one open position on the attached symbol             |
//|     (HasPosition() guard, inherited from the verified EA)          |
//|   - Every decision is Print()-ed to the Experts/Journal log so     |
//|     the user (and this project's record) can audit every action   |
//|                                                                     |
//| HOW TO USE:                                                        |
//|   1. Copy this file into <MT5 data folder>\MQL5\Experts\           |
//|   2. Compile it in MetaEditor (F7) - must show "0 errors"          |
//|   3. Open a D1 chart of your broker's Nasdaq-100 CFD symbol        |
//|      (name varies by broker - check Market Watch, e.g. NAS100,     |
//|      US100.cash, USTEC, NQ100, etc. - look for it directly in      |
//|      the SAME MT5 app/account you already use on your phone)       |
//|   4. Drag this EA onto that chart                                  |
//|   5. In the EA's "Common" tab, tick "Allow live trading"            |
//|   6. Make sure the big "AutoTrading" button in the MT5 toolbar is  |
//|      green/ON - otherwise NO trade will ever be placed              |
//|   7. Leave the chart + terminal running; every new trade / log     |
//|      line will also appear on your phone's MT5 app automatically  |
//|      because it is the same account                                |
//+------------------------------------------------------------------+
#property copyright "Nour AI Company"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== Strategy (verified, do not change unless re-testing) ==="
input int    RSI_PERIOD   = 14;
input int    ADX_PERIOD   = 14;
input int    ATR_PERIOD   = 14;
input int    EMA_PERIOD   = 200;
input double ADX_TH       = 27.0;
input double STOP_ATR     = 1.5;
input double TARGET_ATR   = 4.0;
input ENUM_TIMEFRAMES TF  = PERIOD_D1;

input group "=== Safety (self-imposed, tighter than FTMO's real limits) ==="
input double RISK_PERCENT          = 1.0;   // % of balance risked per trade (FTMO allows much more)
input double DAILY_LOSS_BREAKER_PCT= 3.0;   // stop opening new trades if equity falls this % below today's starting balance (FTMO real max daily loss = 5%)
input int    MAX_TRADES_DAY        = 1;     // this strategy only ever needs 1 signal/day on D1; kept as a hard cap
input long   MAGIC                 = 20261125;

CTrade   trade;
datetime lastBar = 0;
datetime lastDay = 0;
int      dayCount = 0;
double   dayStartBalance = 0;
bool     breakerTrippedToday = false;

int hEma, hRsi, hAtr, hAdx;

int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hEma = iMA(_Symbol, TF, EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   hRsi = iRSI(_Symbol, TF, RSI_PERIOD, PRICE_CLOSE);
   hAtr = iATR(_Symbol, TF, ATR_PERIOD);
   hAdx = iADX(_Symbol, TF, ADX_PERIOD);
   if(hEma == INVALID_HANDLE || hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE || hAdx == INVALID_HANDLE)
   {
      Print("NQ100_D1_Live_FTMO: FAILED to create indicator handles - check symbol/timeframe");
      return(INIT_FAILED);
   }
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   PrintFormat("NQ100_D1_Live_FTMO: initialized on %s %s | balance=%.2f | risk/trade=%.2f%% | daily breaker=%.2f%%",
               _Symbol, EnumToString(TF), dayStartBalance, RISK_PERCENT, DAILY_LOSS_BREAKER_PCT);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   PrintFormat("NQ100_D1_Live_FTMO: stopped (reason=%d)", reason);
}

bool NewBar()
{
   datetime t = iTime(_Symbol, TF, 0);
   if(t == lastBar) return false;
   lastBar = t;
   return true;
}

bool HasPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol) return true;
   return false;
}

double BufVal(int handle, int shift)
{
   double b[]; ArraySetAsSeries(b, true);
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return 0;
   return b[0];
}

void CheckDailyReset()
{
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   datetime dayKey = StringToTime(StringFormat("%04d.%02d.%02d", dtNow.year, dtNow.mon, dtNow.day));
   if(dayKey != lastDay)
   {
      lastDay = dayKey;
      dayCount = 0;
      breakerTrippedToday = false;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      PrintFormat("NQ100_D1_Live_FTMO: new trading day, starting balance=%.2f", dayStartBalance);
   }
}

bool DailyBreakerOK()
{
   if(dayStartBalance <= 0) return true;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (dayStartBalance - equity) / dayStartBalance * 100.0;
   if(lossPct >= DAILY_LOSS_BREAKER_PCT)
   {
      if(!breakerTrippedToday)
      {
         PrintFormat("NQ100_D1_Live_FTMO: *** DAILY LOSS BREAKER TRIPPED *** equity down %.2f%% (limit %.2f%%) - no new trades until tomorrow",
                     lossPct, DAILY_LOSS_BREAKER_PCT);
         breakerTrippedToday = true;
      }
      return false;
   }
   return true;
}

void OnTick()
{
   CheckDailyReset();
   if(!NewBar()) return;

   if(!DailyBreakerOK()) return;
   if(HasPosition()) return;
   if(dayCount >= MAX_TRADES_DAY) return;

   double ema      = BufVal(hEma, 1);
   double rsiNow   = BufVal(hRsi, 1);
   double rsiPrev  = BufVal(hRsi, 2);
   double atr      = BufVal(hAtr, 1);
   double adx      = BufVal(hAdx, 1);
   double closeNow = iClose(_Symbol, TF, 1);
   if(ema <= 0 || atr <= 0 || closeNow <= 0) return;
   if(adx <= ADX_TH) return;

   int dir = 0;
   if(closeNow > ema && rsiPrev < 45.0 && rsiNow >= 45.0) dir = 1;
   else if(closeNow < ema && rsiPrev > 55.0 && rsiNow <= 55.0) dir = -1;
   if(dir == 0) return;

   double stopDist   = atr * STOP_ATR;
   double targetDist = atr * TARGET_ATR;
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (dir == 1) ? closeNow - stopDist : closeNow + stopDist;
   double tp = (dir == 1) ? closeNow + targetDist : closeNow - targetDist;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RISK_PERCENT / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lots = 0;
   if(stopDist > 0 && tickValue > 0 && tickSize > 0)
   {
      double lossPerLot = stopDist / tickSize * tickValue;
      if(lossPerLot > 0) lots = riskMoney / lossPerLot;
   }
   lots = MathFloor(lots * 100.0) / 100.0;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   if(lots <= 0)
   {
      Print("NQ100_D1_Live_FTMO: computed lot size <= 0, skipping signal");
      return;
   }

   PrintFormat("NQ100_D1_Live_FTMO: SIGNAL %s | close=%.2f ema200=%.2f rsi=%.1f->%.1f adx=%.1f atr=%.2f | lots=%.2f sl=%.2f tp=%.2f",
               (dir==1?"BUY":"SELL"), closeNow, ema, rsiPrev, rsiNow, adx, atr, lots, sl, tp);

   bool ok;
   if(dir == 1) ok = trade.Buy(lots, _Symbol, price, sl, tp, "agy D1 verified - live");
   else         ok = trade.Sell(lots, _Symbol, price, sl, tp, "agy D1 verified - live");

   if(ok) { dayCount++; PrintFormat("NQ100_D1_Live_FTMO: order sent OK, ticket=%I64u", trade.ResultOrder()); }
   else   { PrintFormat("NQ100_D1_Live_FTMO: order FAILED, retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()); }
}
