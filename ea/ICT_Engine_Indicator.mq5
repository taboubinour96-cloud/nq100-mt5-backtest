//+------------------------------------------------------------------+
//| ICT_Engine_Indicator.mq5                                         |
//| Deterministic MQL5 implementation of ICT_SPEC.md / ict_engine.py |
//| Logs entry signals via SignalLogger.mqh for MBT headless backtest|
//+------------------------------------------------------------------+
#property copyright "Nour AI Company"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "ICT Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "ICT Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

#include <SignalLogger.mqh>

//--- Fixed constants matching ICT_SPEC.md / ict_engine.py
input double InpDispAtrMult     = 1.5;
input double InpFvgMinAtrMult   = 0.10;
input double InpSlBufferAtrMult = 0.10;
input double InpMinRR           = 2.0;
input double InpMaxRR           = 5.0;
input int    InpSwingLR         = 2;
input int    InpChochMaxBars    = 3;   // Max closed bars after sweep for CHoCH confirmation
input int    InpAtrPeriod       = 14;
input int    InpDailyEmaFast    = 50;
input int    InpDailyEmaSlow    = 200;

double BuyBuf[];
double SellBuf[];

struct ZoneState
{
   bool   active;
   bool   burned;
   int    dir;
   double lo;
   double hi;
   int    idx;
};

//--- Persistent incremental state across closed bars
int       g_last_bar = -1;
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

double    g_last_swing_high = 0.0;
bool      g_has_swing_high = false;
bool      g_swing_high_burned = false;
int       g_recent_high_idx = -1;

double    g_last_swing_low = 0.0;
bool      g_has_swing_low = false;
bool      g_swing_low_burned = false;
int       g_recent_low_idx = -1;

int       g_trend_state = 0;   // 1 bull, -1 bear, 0 unknown
int       g_sweep_kind = 0;    // 1 bull_judas, -1 bear_judas, 0 none
int       g_sweep_idx = -1;

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

void ResetEngineState()
{
   g_last_bar = -1;
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

   g_last_swing_high = 0.0;
   g_has_swing_high = false;
   g_swing_high_burned = false;
   g_recent_high_idx = -1;

   g_last_swing_low = 0.0;
   g_has_swing_low = false;
   g_swing_low_burned = false;
   g_recent_low_idx = -1;

   g_trend_state = 0;
   g_sweep_kind = 0;
   g_sweep_idx = -1;

   ResetZone(g_ob);
   ResetZone(g_fvg);
}

//--- Date helpers (pure Gregorian, DST-accurate for EU server & US NY)
int DaysInMonth(int y, int m)
{
   static int md[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
   if(m == 2 && ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)))
      return 29;
   return md[m - 1];
}

int DayOfWeekDate(int y, int m, int d)
{
   // Sakamoto: 0=Sun..6=Sat
   static int t[12] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
   int yy = y;
   if(m < 3) yy -= 1;
   return (yy + yy/4 - yy/100 + yy/400 + t[m - 1] + d) % 7;
}

int LastSunday(int y, int m)
{
   int dim = DaysInMonth(y, m);
   int dow = DayOfWeekDate(y, m, dim);
   return dim - dow;
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
      return (dt.hour >= 3); // 01:00 UTC = 03:00 EET
   }
   int ls10 = LastSunday(dt.year, 10);
   if(dt.day < ls10) return true;
   if(dt.day > ls10) return false;
   return (dt.hour < 4); // 01:00 UTC = 04:00 EEST
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
      return (dt.hour >= 7); // 02:00 EST = 07:00 UTC
   }
   int s1 = NthSunday(dt.year, 11, 1);
   if(dt.day < s1) return true;
   if(dt.day > s1) return false;
   return (dt.hour < 6); // 02:00 EDT = 06:00 UTC
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
   if(mins >= 120 && mins <= 300) return true; // 02:00 - 05:00
   if(mins >= 420 && mins <= 600) return true; // 07:00 - 10:00
   if(mins >= 810 && mins <= 960) return true; // 13:30 - 16:00
   return false;
}

int OnInit()
{
   SetIndexBuffer(0, BuyBuf, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ResetEngineState();
   ResetSignalLog();
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpSwingLR * 2 + 2)
      return(0);

   ArraySetAsSeries(time, false);
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);
   ArraySetAsSeries(BuyBuf, false);
   ArraySetAsSeries(SellBuf, false);

   if(prev_calculated == 0)
   {
      ResetEngineState();
      ResetSignalLog();
      for(int k = 0; k < rates_total; k++)
      {
         BuyBuf[k]  = EMPTY_VALUE;
         SellBuf[k] = EMPTY_VALUE;
      }
   }
   else
   {
      for(int k = prev_calculated; k < rates_total; k++)
      {
         BuyBuf[k]  = EMPTY_VALUE;
         SellBuf[k] = EMPTY_VALUE;
      }
   }

   int closed_end = rates_total - 2; // bar rates_total-1 is still forming
   int start_i = g_last_bar + 1;
   if(start_i < 0) start_i = 0;

   double alpha_atr = 1.0 / InpAtrPeriod;
   double alpha_50  = 2.0 / (InpDailyEmaFast + 1.0);
   double alpha_200 = 2.0 / (InpDailyEmaSlow + 1.0);

   for(int i = start_i; i <= closed_end; i++)
   {
      //--- 1. ATR(14) Wilder RMA (matches pandas ewm(alpha=1/14, adjust=False))
      double tr = high[i] - low[i];
      if(g_has_prev_close)
      {
         double hc = MathAbs(high[i] - g_prev_close);
         double lc = MathAbs(low[i]  - g_prev_close);
         if(hc > tr) tr = hc;
         if(lc > tr) tr = lc;
         g_atr = alpha_atr * tr + (1.0 - alpha_atr) * g_atr;
      }
      else
      {
         g_atr = tr;
      }
      g_prev_close = close[i];
      g_has_prev_close = true;

      //--- 2. Daily EMA50/EMA200 Bias (no lookahead: prior completed NY day's close)
      datetime ny_t = ServerToNY(time[i]);
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
      g_last_day_close = close[i];
      g_has_day_close = true;

      //--- 3. Confirmed fractal swings at orig = i - InpSwingLR (visible only at bar i)
      if(i >= 2 * InpSwingLR)
      {
         int orig = i - InpSwingLR;
         double wh_max = high[orig - InpSwingLR];
         int    wh_arg = orig - InpSwingLR;
         double wl_min = low[orig - InpSwingLR];
         int    wl_arg = orig - InpSwingLR;
         for(int w = orig - InpSwingLR + 1; w <= orig + InpSwingLR; w++)
         {
            if(high[w] > wh_max) { wh_max = high[w]; wh_arg = w; }
            if(low[w]  < wl_min) { wl_min = low[w];  wl_arg = w; }
         }
         if(high[orig] == wh_max && wh_arg == orig)
         {
            g_last_swing_high = high[orig];
            g_has_swing_high = true;
            g_swing_high_burned = false;
            g_recent_high_idx = orig;
         }
         if(low[orig] == wl_min && wl_arg == orig)
         {
            g_last_swing_low = low[orig];
            g_has_swing_low = true;
            g_swing_low_burned = false;
            g_recent_low_idx = orig;
         }
      }

      if(i < InpSwingLR || g_atr <= 0.0)
      {
         g_last_bar = i;
         continue;
      }

      double c = close[i], h = high[i], l = low[i], o = open[i];

      //--- 4. Structure break (BOS/CHoCH) via Close only
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

      //--- 5. Liquidity sweep (strict same-bar rejection)
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

      //--- 6. CHoCH after sweep (must occur within 1..InpChochMaxBars bars) -> build OB / FVG
      if(g_sweep_kind != 0)
      {
         if((i - g_sweep_idx) > InpChochMaxBars)
         {
            g_sweep_kind = 0;
         }
         else if(g_sweep_kind == 1 && g_bias == 1 && broke_up && i > g_sweep_idx)
         {
            int ob_idx = -1;
            for(int k = i - 1; k >= g_sweep_idx; k--)
            {
               if(close[k] < open[k]) { ob_idx = k; break; }
            }
            if(ob_idx >= 0 && (h - l) >= InpDispAtrMult * g_atr)
            {
               g_ob.active = true; g_ob.burned = false; g_ob.dir = 1;
               g_ob.lo = low[ob_idx]; g_ob.hi = high[ob_idx]; g_ob.idx = ob_idx;
            }
            if(i >= 2 && low[i] > high[i - 2])
            {
               double gap = low[i] - high[i - 2];
               if(gap >= InpFvgMinAtrMult * g_atr)
               {
                  g_fvg.active = true; g_fvg.burned = false; g_fvg.dir = 1;
                  g_fvg.lo = high[i - 2]; g_fvg.hi = low[i]; g_fvg.idx = i;
               }
            }
            g_sweep_kind = 0;
         }
         else if(g_sweep_kind == -1 && g_bias == -1 && broke_down && i > g_sweep_idx)
         {
            int ob_idx = -1;
            for(int k = i - 1; k >= g_sweep_idx; k--)
            {
               if(close[k] > open[k]) { ob_idx = k; break; }
            }
            if(ob_idx >= 0 && (h - l) >= InpDispAtrMult * g_atr)
            {
               g_ob.active = true; g_ob.burned = false; g_ob.dir = -1;
               g_ob.lo = low[ob_idx]; g_ob.hi = high[ob_idx]; g_ob.idx = ob_idx;
            }
            if(i >= 2 && high[i] < low[i - 2])
            {
               double gap = low[i - 2] - high[i];
               if(gap >= InpFvgMinAtrMult * g_atr)
               {
                  g_fvg.active = true; g_fvg.burned = false; g_fvg.dir = -1;
                  g_fvg.lo = high[i]; g_fvg.hi = low[i - 2]; g_fvg.idx = i;
               }
            }
            g_sweep_kind = 0;
         }
      }

      //--- 7. Entry check on active zone (OB priority, else FVG)
      bool use_ob = (g_ob.active && !g_ob.burned);
      bool use_fvg = (!use_ob && g_fvg.active && !g_fvg.burned);

      if((use_ob || use_fvg) && g_recent_high_idx >= 0 && g_recent_low_idx >= 0)
      {
         ZoneState z = use_ob ? g_ob : g_fvg;
         bool fvg_also_touched = (use_ob && g_fvg.active && !g_fvg.burned && g_fvg.dir == z.dir && l <= g_fvg.hi && h >= g_fvg.lo);
         string regime = use_ob ? (fvg_also_touched ? "OB_AND_FVG" : "ORDER_BLOCK") : "FVG_FILL";

         double swing_hi = high[g_recent_high_idx];
         double swing_lo = low[g_recent_low_idx];
         double rng = swing_hi - swing_lo;
         if(rng > 0.0)
         {
            double midpoint = swing_lo + 0.5 * rng;
            bool in_discount = (c <= midpoint);
            bool in_premium  = (c >= midpoint);
            bool in_kz       = InKillZoneNY(ny_t);
            bool touched     = (l <= z.hi && h >= z.lo);
            int  shift       = (rates_total - 1) - i;

            if(z.dir == 1 && touched && in_discount && c > o && in_kz)
            {
               double sl = z.lo - InpSlBufferAtrMult * g_atr;
               double risk = c - sl;
               double reward = swing_hi - c;
               if(risk > 0.0 && (reward / risk) >= InpMinRR)
               {
                  double tp = c + MathMin(reward, InpMaxRR * risk);
                  BuyBuf[i] = l;
                  LogSignal(shift, true, c, sl, tp, regime);
                  if(use_ob) g_ob.burned = true; else g_fvg.burned = true;
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
                  SellBuf[i] = h;
                  LogSignal(shift, false, c, sl, tp, regime);
                  if(use_ob) g_ob.burned = true; else g_fvg.burned = true;
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

      g_last_bar = i;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
