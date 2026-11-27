//+------------------------------------------------------------------+
//| ICT_Engine_EA.mq5                                                |
//| Full Expert Advisor for Strategy Tester implementing ICT_SPEC.md |
//| Mirrors ICT_Engine_Indicator.mq5 + executes via CTrade           |
//| Risk Management Enhancements (Round 4):                          |
//|   1) Anti-Martingale Sizing:                                     |
//|      - After every 2 consecutive losing trades:                  |
//|        reduce next lot multiplier by 20% (floor = 0.25x base).   |
//|      - After every 2 consecutive winning trades:                 |
//|        increase next lot multiplier by +25% (cap = 2.0x base).   |
//|   2) Daily Max Loss Breaker (default 3.0% of day start balance): |
//|      - Tracks daily starting balance at server day rollover.     |
//|      - If (day_start_balance - min(equity, balance)) >= 3.0%,    |
//|        halts opening any new trades until the next server day.   |
//+------------------------------------------------------------------+
#property copyright "Nour AI Company"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <SignalLogger.mqh>

//--- Fixed constants matching ICT_SPEC.md / ict_engine.py
input double InpDispAtrMult        = 1.5;
input double InpFvgMinAtrMult      = 0.10;
input double InpSlBufferAtrMult    = 0.10;
input double InpMinRR              = 2.0;
input double InpMaxRR              = 5.0;
input int    InpSwingLR            = 2;
input int    InpAtrPeriod          = 14;
input int    InpDailyEmaFast       = 50;
input int    InpDailyEmaSlow       = 200;
input long   InpMagic              = 20261127;

//--- Risk management parameters (Anti-Martingale + Daily Max Loss Breaker)
input double InpRiskPercent        = 1.0;   // Base risk % of balance per trade
input double InpLossStepReducePct  = 20.0;  // Lot reduction % after 2 consecutive losses
input double InpWinStepIncreasePct = 25.0;  // Lot increase % after 2 consecutive wins
input double InpMinLotMult         = 0.25;  // Minimum lot multiplier (safety floor)
input double InpMaxLotMult         = 2.00;  // Maximum lot multiplier (2x base size cap)
input double InpDailyMaxLossPct    = 3.0;   // Daily max loss breaker (% of day start balance)

CTrade trade;

struct ZoneState
{
   bool   active;
   bool   burned;
   int    dir;
   double lo;
   double hi;
   int    idx;
};

//--- Risk management runtime state
double    g_lot_mult = 1.0;
int       g_consec_losses = 0;
int       g_consec_wins = 0;
int       g_trade_day = -1;
double    g_day_start_balance = 0.0;
bool      g_daily_halted = false;

//--- Incremental state across closed H1 bars
datetime  g_last_bar_time = 0;
datetime  g_last_closed_bar_time = 0;
int       g_bar_idx = -1;

double    g_atr = 0.0;
double    g_prev_close = 0.0;
bool      g_has_prev_close = false;

int       g_cur_ny_day = -1;
double    g_last_day_close = 0.0;
bool      g_has_day_close = false;
double    g_ema50 = 0.0;
double    g_ema200 = 0.0;
bool      g_ema_init = false;
int       g_bias = 0;

// Store swing highs/lows by chronological bar index using ring buffer
#define MAX_SWING_HIST 512
double    g_hist_high[MAX_SWING_HIST];
double    g_hist_low[MAX_SWING_HIST];
int       g_hist_count = 0;

double    g_last_swing_high = 0.0;
bool      g_has_swing_high = false;
bool      g_swing_high_burned = false;
double    g_recent_swing_high_val = 0.0;
bool      g_has_recent_high = false;

double    g_last_swing_low = 0.0;
bool      g_has_swing_low = false;
bool      g_swing_low_burned = false;
double    g_recent_swing_low_val = 0.0;
bool      g_has_recent_low = false;

int       g_trend_state = 0;
int       g_sweep_kind = 0;
int       g_sweep_idx = -1;

// Recent candles for OB/FVG lookback (last 128 closed bars)
#define BAR_BUF 128
double    g_b_open[BAR_BUF];
double    g_b_high[BAR_BUF];
double    g_b_low[BAR_BUF];
double    g_b_close[BAR_BUF];
int       g_b_idx[BAR_BUF];
int       g_b_count = 0;

ZoneState g_ob;
ZoneState g_fvg;

void ResetZone(ZoneState &z)
{
   z.active = false;
   z.burned = false;
   z.dir    = 0;
   z.lo     = 0.0;
   z.hi     = 0.0;
   z.idx    = -1;
}

void ResetAllState()
{
   g_lot_mult = 1.0;
   g_consec_losses = 0;
   g_consec_wins = 0;
   g_trade_day = -1;
   g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_daily_halted = false;

   g_last_bar_time = 0;
   g_last_closed_bar_time = 0;
   g_bar_idx = -1;
   g_atr = 0.0;
   g_prev_close = 0.0;
   g_has_prev_close = false;
   g_cur_ny_day = -1;
   g_last_day_close = 0.0;
   g_has_day_close = false;
   g_ema50 = 0.0;
   g_ema200 = 0.0;
   g_ema_init = false;
   g_bias = 0;
   g_hist_count = 0;
   g_last_swing_high = 0.0;
   g_has_swing_high = false;
   g_swing_high_burned = false;
   g_recent_swing_high_val = 0.0;
   g_has_recent_high = false;
   g_last_swing_low = 0.0;
   g_has_swing_low = false;
   g_swing_low_burned = false;
   g_recent_swing_low_val = 0.0;
   g_has_recent_low = false;
   g_trend_state = 0;
   g_sweep_kind = 0;
   g_sweep_idx = -1;
   g_b_count = 0;
   ResetZone(g_ob);
   ResetZone(g_fvg);
}

//--- Daily max loss breaker (resets at broker server midnight, blocks entries if drawdown >= InpDailyMaxLossPct)
bool IsDailyLossHalted()
{
   datetime now_t = TimeCurrent();
   if(now_t <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(now_t, dt);
   int cur_day = dt.year * 10000 + dt.mon * 100 + dt.day;

   if(cur_day != g_trade_day)
   {
      g_trade_day = cur_day;
      g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily_halted = false;
   }

   if(g_daily_halted)
      return true;

   if(g_day_start_balance > 0.0 && InpDailyMaxLossPct > 0.0)
   {
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double worst_val = MathMin(eq, bal);
      double dd_pct = ((g_day_start_balance - worst_val) / g_day_start_balance) * 100.0;
      if(dd_pct >= InpDailyMaxLossPct)
      {
         g_daily_halted = true;
         PrintFormat("DAILY_LOSS_BREAKER: halted new entries for %d (loss=%.2f%% >= %.2f%%)",
                     cur_day, dd_pct, InpDailyMaxLossPct);
      }
   }
   return g_daily_halted;
}

//--- Date helpers (EU server EET/EEST <-> UTC <-> NY EST/EDT)
int DaysInMonth(int y, int m)
{
   static int md[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
   if(m == 2 && ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)))
      return 29;
   return md[m - 1];
}

int DayOfWeekDate(int y, int m, int d)
{
   static int t[12] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
   int yy = y;
   if(m < 3) yy -= 1;
   return (yy + yy/4 - yy/100 + yy/400 + t[m - 1] + d) % 7;
}

int LastSunday(int y, int m)
{
   int dim = DaysInMonth(y, m);
   return dim - DayOfWeekDate(y, m, dim);
}

int NthSunday(int y, int m, int nth)
{
   int dow1 = DayOfWeekDate(y, m, 1);
   int first_sun = 1 + ((7 - dow1) % 7);
   return first_sun + (nth - 1) * 7;
}

bool IsEuDstFromServer(datetime srv_t)
{
   MqlDateTime dt;
   TimeToStruct(srv_t, dt);
   if(dt.mon > 3 && dt.mon < 10) return true;
   if(dt.mon < 3 || dt.mon > 10) return false;
   if(dt.mon == 3)
   {
      int ls = LastSunday(dt.year, 3);
      if(dt.day > ls) return true;
      if(dt.day < ls) return false;
      return (dt.hour >= 3);
   }
   int ls10 = LastSunday(dt.year, 10);
   if(dt.day < ls10) return true;
   if(dt.day > ls10) return false;
   return (dt.hour < 4);
}

bool IsUsDstFromUtc(datetime utc_t)
{
   MqlDateTime dt;
   TimeToStruct(utc_t, dt);
   if(dt.mon > 3 && dt.mon < 11) return true;
   if(dt.mon < 3 || dt.mon > 11) return false;
   if(dt.mon == 3)
   {
      int s2 = NthSunday(dt.year, 3, 2);
      if(dt.day > s2) return true;
      if(dt.day < s2) return false;
      return (dt.hour >= 7);
   }
   int s1 = NthSunday(dt.year, 11, 1);
   if(dt.day < s1) return true;
   if(dt.day > s1) return false;
   return (dt.hour < 6);
}

datetime ServerToNY(datetime srv_t)
{
   datetime utc_t = srv_t - (IsEuDstFromServer(srv_t) ? 3 * 3600 : 2 * 3600);
   return utc_t + (IsUsDstFromUtc(utc_t) ? -4 * 3600 : -5 * 3600);
}

bool InKillZoneNY(datetime ny_t)
{
   MqlDateTime dt;
   TimeToStruct(ny_t, dt);
   int mins = dt.hour * 60 + dt.min;
   if(mins >= 120 && mins <= 300) return true;
   if(mins >= 420 && mins <= 600) return true;
   if(mins >= 810 && mins <= 960) return true;
   return false;
}

bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

//--- Position sizing with Anti-Martingale multiplier applied
double CalcLots(double risk_price)
{
   if(risk_price <= 0.0) return 0.0;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (InpRiskPercent / 100.0) * g_lot_mult;
   double tick_val   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val <= 0.0 || tick_size <= 0.0) return 0.0;

   double loss_per_lot = (risk_price / tick_size) * tick_val;
   if(loss_per_lot <= 0.0) return 0.0;

   double raw_lots = risk_money / loss_per_lot;
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   double lots = MathFloor(raw_lots / step) * step;
   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;
   return NormalizeDouble(lots, 2);
}

void PushBar(int idx, double o, double h, double l, double c)
{
   if(g_b_count < BAR_BUF)
   {
      g_b_open[g_b_count]  = o;
      g_b_high[g_b_count]  = h;
      g_b_low[g_b_count]   = l;
      g_b_close[g_b_count] = c;
      g_b_idx[g_b_count]   = idx;
      g_b_count++;
   }
   else
   {
      for(int k = 1; k < BAR_BUF; k++)
      {
         g_b_open[k - 1]  = g_b_open[k];
         g_b_high[k - 1]  = g_b_high[k];
         g_b_low[k - 1]   = g_b_low[k];
         g_b_close[k - 1] = g_b_close[k];
         g_b_idx[k - 1]   = g_b_idx[k];
      }
      g_b_open[BAR_BUF - 1]  = o;
      g_b_high[BAR_BUF - 1]  = h;
      g_b_low[BAR_BUF - 1]   = l;
      g_b_close[BAR_BUF - 1] = c;
      g_b_idx[BAR_BUF - 1]   = idx;
   }

   if(g_hist_count < MAX_SWING_HIST)
   {
      g_hist_high[g_hist_count] = h;
      g_hist_low[g_hist_count]  = l;
      g_hist_count++;
   }
   else
   {
      for(int k = 1; k < MAX_SWING_HIST; k++)
      {
         g_hist_high[k - 1] = g_hist_high[k];
         g_hist_low[k - 1]  = g_hist_low[k];
      }
      g_hist_high[MAX_SWING_HIST - 1] = h;
      g_hist_low[MAX_SWING_HIST - 1]  = l;
   }
}

void ProcessClosedBar(datetime bar_time, double o, double h, double l, double c, bool allow_trade)
{
   g_bar_idx++;
   int i = g_bar_idx;
   PushBar(i, o, h, l, c);

   double alpha_atr = 1.0 / InpAtrPeriod;
   double alpha_50  = 2.0 / (InpDailyEmaFast + 1.0);
   double alpha_200 = 2.0 / (InpDailyEmaSlow + 1.0);

   //--- 1. ATR(14) Wilder RMA
   double tr = h - l;
   if(g_has_prev_close)
   {
      double hc = MathAbs(h - g_prev_close);
      double lc = MathAbs(l - g_prev_close);
      if(hc > tr) tr = hc;
      if(lc > tr) tr = lc;
      g_atr = alpha_atr * tr + (1.0 - alpha_atr) * g_atr;
   }
   else
   {
      g_atr = tr;
   }
   g_prev_close = c;
   g_has_prev_close = true;

   //--- 2. Daily EMA50/EMA200 Bias
   datetime ny_t = ServerToNY(bar_time);
   MqlDateTime ny_dt;
   TimeToStruct(ny_t, ny_dt);
   int ny_day = ny_dt.year * 10000 + ny_dt.mon * 100 + ny_dt.day;
   if(g_cur_ny_day != -1 && ny_day != g_cur_ny_day && g_has_day_close)
   {
      if(!g_ema_init)
      {
         g_ema50  = g_last_day_close;
         g_ema200 = g_last_day_close;
         g_ema_init = true;
      }
      else
      {
         g_ema50  = alpha_50  * g_last_day_close + (1.0 - alpha_50)  * g_ema50;
         g_ema200 = alpha_200 * g_last_day_close + (1.0 - alpha_200) * g_ema200;
      }
      g_bias = (g_ema50 > g_ema200) ? 1 : -1;
   }
   g_cur_ny_day = ny_day;
   g_last_day_close = c;
   g_has_day_close = true;

   //--- 3. Confirmed fractal swings at orig = i - InpSwingLR
   int win = InpSwingLR * 2 + 1;
   if(g_hist_count >= win)
   {
      int center = g_hist_count - 1 - InpSwingLR;
      double wh_max = g_hist_high[center - InpSwingLR];
      int    wh_arg = center - InpSwingLR;
      double wl_min = g_hist_low[center - InpSwingLR];
      int    wl_arg = center - InpSwingLR;
      for(int w = center - InpSwingLR + 1; w <= center + InpSwingLR; w++)
      {
         if(g_hist_high[w] > wh_max) { wh_max = g_hist_high[w]; wh_arg = w; }
         if(g_hist_low[w]  < wl_min) { wl_min = g_hist_low[w];  wl_arg = w; }
      }
      if(g_hist_high[center] == wh_max && wh_arg == center)
      {
         g_last_swing_high = g_hist_high[center];
         g_has_swing_high = true;
         g_swing_high_burned = false;
         g_recent_swing_high_val = g_last_swing_high;
         g_has_recent_high = true;
      }
      if(g_hist_low[center] == wl_min && wl_arg == center)
      {
         g_last_swing_low = g_hist_low[center];
         g_has_swing_low = true;
         g_swing_low_burned = false;
         g_recent_swing_low_val = g_last_swing_low;
         g_has_recent_low = true;
      }
   }

   if(i < InpSwingLR || g_atr <= 0.0)
      return;

   //--- 4. Structure break (BOS/CHoCH)
   bool broke_up   = (g_has_swing_high && !g_swing_high_burned && c > g_last_swing_high);
   bool broke_down = (g_has_swing_low  && !g_swing_low_burned  && c < g_last_swing_low);

   if(broke_up)
   {
      if(g_trend_state <= 0) g_trend_state = 1;
      g_swing_high_burned = true;
   }
   if(broke_down)
   {
      if(g_trend_state >= 0) g_trend_state = -1;
      g_swing_low_burned = true;
   }

   //--- 5. Liquidity sweep
   if(g_bias != 0)
   {
      if(g_bias == 1 && g_has_swing_low && !g_swing_low_burned)
      {
         if(l < g_last_swing_low && c > g_last_swing_low)
         {
            g_sweep_kind = 1;
            g_sweep_idx  = i;
         }
      }
      if(g_bias == -1 && g_has_swing_high && !g_swing_high_burned)
      {
         if(h > g_last_swing_high && c < g_last_swing_high)
         {
            g_sweep_kind = -1;
            g_sweep_idx  = i;
         }
      }
   }

   //--- 6. CHoCH after sweep -> build OB / FVG
   if(g_sweep_kind != 0)
   {
      if(g_sweep_kind == 1 && g_bias == 1 && broke_up && i > g_sweep_idx)
      {
         int ob_pos = -1;
         for(int k = g_b_count - 2; k >= 0; k--)
         {
            if(g_b_idx[k] < g_sweep_idx) break;
            if(g_b_close[k] < g_b_open[k]) { ob_pos = k; break; }
         }
         if(ob_pos >= 0 && (h - l) >= InpDispAtrMult * g_atr)
         {
            g_ob.active = true; g_ob.burned = false; g_ob.dir = 1;
            g_ob.lo = g_b_low[ob_pos]; g_ob.hi = g_b_high[ob_pos]; g_ob.idx = g_b_idx[ob_pos];
         }
         if(g_b_count >= 3)
         {
            double h2 = g_b_high[g_b_count - 3];
            if(l > h2 && (l - h2) >= InpFvgMinAtrMult * g_atr)
            {
               g_fvg.active = true; g_fvg.burned = false; g_fvg.dir = 1;
               g_fvg.lo = h2; g_fvg.hi = l; g_fvg.idx = i;
            }
         }
         g_sweep_kind = 0;
      }
      else if(g_sweep_kind == -1 && g_bias == -1 && broke_down && i > g_sweep_idx)
      {
         int ob_pos = -1;
         for(int k = g_b_count - 2; k >= 0; k--)
         {
            if(g_b_idx[k] < g_sweep_idx) break;
            if(g_b_close[k] > g_b_open[k]) { ob_pos = k; break; }
         }
         if(ob_pos >= 0 && (h - l) >= InpDispAtrMult * g_atr)
         {
            g_ob.active = true; g_ob.burned = false; g_ob.dir = -1;
            g_ob.lo = g_b_low[ob_pos]; g_ob.hi = g_b_high[ob_pos]; g_ob.idx = g_b_idx[ob_pos];
         }
         if(g_b_count >= 3)
         {
            double l2 = g_b_low[g_b_count - 3];
            if(h < l2 && (l2 - h) >= InpFvgMinAtrMult * g_atr)
            {
               g_fvg.active = true; g_fvg.burned = false; g_fvg.dir = -1;
               g_fvg.lo = h; g_fvg.hi = l2; g_fvg.idx = i;
            }
         }
         g_sweep_kind = 0;
      }
   }

   //--- 7. Entry check
   bool use_ob  = (g_ob.active && !g_ob.burned);
   bool use_fvg = (!use_ob && g_fvg.active && !g_fvg.burned);

   if((use_ob || use_fvg) && g_has_recent_high && g_has_recent_low)
   {
      ZoneState z = use_ob ? g_ob : g_fvg;
      bool fvg_also_touched = (use_ob && g_fvg.active && !g_fvg.burned && g_fvg.dir == z.dir && l <= g_fvg.hi && h >= g_fvg.lo);
      string regime = use_ob ? (fvg_also_touched ? "OB_AND_FVG" : "ORDER_BLOCK") : "FVG_FILL";

      double swing_hi = g_recent_swing_high_val;
      double swing_lo = g_recent_swing_low_val;
      double rng = swing_hi - swing_lo;
      if(rng > 0.0)
      {
         double midpoint = swing_lo + 0.5 * rng;
         bool in_discount = (c <= midpoint);
         bool in_premium  = (c >= midpoint);
         bool in_kz       = InKillZoneNY(ny_t);
         bool touched     = (l <= z.hi && h >= z.lo);

         if(z.dir == 1 && touched && in_discount && c > o && in_kz)
         {
            double sl = z.lo - InpSlBufferAtrMult * g_atr;
            double risk = c - sl;
            double reward = swing_hi - c;
            if(risk > 0.0 && (reward / risk) >= InpMinRR)
            {
               double tp = c + MathMin(reward, InpMaxRR * risk);
               if(use_ob) g_ob.burned = true; else g_fvg.burned = true;

               if(allow_trade)
               {
                  LogSignal(1, true, c, sl, tp, regime);
                  if(!HasPosition() && !IsDailyLossHalted())
                  {
                     double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                     double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                     int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                     double sl_n = NormalizeDouble(sl, digits);
                     double tp_n = NormalizeDouble(tp, digits);
                     double lots = CalcLots(MathAbs(ask - sl_n));
                     if(lots > 0.0 && sl_n < bid && tp_n > ask)
                        trade.Buy(lots, _Symbol, 0.0, sl_n, tp_n, regime);
                  }
               }
            }
         }
         else if(z.dir == -1 && touched && in_premium && c < o && in_kz)
         {
            double sl = z.hi + InpSlBufferAtrMult * g_atr;
            double risk = sl - c;
            double reward = c - swing_lo;
            if(risk > 0.0 && (reward / risk) >= InpMinRR)
            {
               double tp = c - MathMin(reward, InpMaxRR * risk);
               if(use_ob) g_ob.burned = true; else g_fvg.burned = true;

               if(allow_trade)
               {
                  LogSignal(1, false, c, sl, tp, regime);
                  if(!HasPosition() && !IsDailyLossHalted())
                  {
                     double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                     double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                     int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                     double sl_n = NormalizeDouble(sl, digits);
                     double tp_n = NormalizeDouble(tp, digits);
                     double lots = CalcLots(MathAbs(sl_n - bid));
                     if(lots > 0.0 && sl_n > ask && tp_n < bid)
                        trade.Sell(lots, _Symbol, 0.0, sl_n, tp_n, regime);
                  }
               }
            }
         }
         else
         {
            if(z.dir == 1 && c < z.lo)
            {
               if(use_ob) g_ob.burned = true; else g_fvg.burned = true;
            }
            if(z.dir == -1 && c > z.hi)
            {
               if(use_ob) g_ob.burned = true; else g_fvg.burned = true;
            }
         }
      }
   }
}

//--- Track closed deals for Anti-Martingale streak sizing
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(pnl < 0.0)
   {
      g_consec_losses++;
      g_consec_wins = 0;
      if(g_consec_losses >= 2 && (g_consec_losses % 2) == 0)
      {
         g_lot_mult = MathMax(InpMinLotMult, g_lot_mult * (1.0 - InpLossStepReducePct / 100.0));
         PrintFormat("ANTI_MARTINGALE: %d consecutive losses -> lot_mult=%.3f", g_consec_losses, g_lot_mult);
      }
   }
   else if(pnl > 0.0)
   {
      g_consec_wins++;
      g_consec_losses = 0;
      if(g_consec_wins >= 2 && (g_consec_wins % 2) == 0)
      {
         g_lot_mult = MathMin(InpMaxLotMult, g_lot_mult * (1.0 + InpWinStepIncreasePct / 100.0));
         PrintFormat("ANTI_MARTINGALE: %d consecutive wins -> lot_mult=%.3f", g_consec_wins, g_lot_mult);
      }
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   ResetAllState();
   ResetSignalLog();

   // Warm up on pre-start historical bars loaded in tester (no trading during warmup)
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, _Period, 0, Bars(_Symbol, _Period), rates);
   if(copied > 1)
   {
      for(int idx = 0; idx < copied - 1; idx++)
      {
         ProcessClosedBar(rates[idx].time, rates[idx].open, rates[idx].high,
                          rates[idx].low, rates[idx].close, false);
         g_last_closed_bar_time = rates[idx].time;
      }
      g_last_bar_time = rates[copied - 1].time;
   }
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // Check daily max loss breaker continuously (protects against intraday floating drawdown)
   IsDailyLossHalted();

   datetime cur_bar = iTime(_Symbol, _Period, 0);
   if(cur_bar == 0 || cur_bar == g_last_bar_time)
      return;

   int total = Bars(_Symbol, _Period);
   if(total < 2) return;
   datetime prev_closed = iTime(_Symbol, _Period, 1);
   if(prev_closed > g_last_closed_bar_time)
   {
      ProcessClosedBar(prev_closed,
                       iOpen(_Symbol, _Period, 1),
                       iHigh(_Symbol, _Period, 1),
                       iLow(_Symbol, _Period, 1),
                       iClose(_Symbol, _Period, 1),
                       true);
      g_last_closed_bar_time = prev_closed;
   }
   g_last_bar_time = cur_bar;
}
//+------------------------------------------------------------------+
