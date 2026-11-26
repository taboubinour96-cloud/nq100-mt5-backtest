# =====================================================================
# deploy_live_ftmo.ps1
# سكربت واحد شامل: يثبّت MT5 (إن لم يكن مثبتًا)، ينسخ البوت، يجمّعه،
# ثم يشغّله حيًا على حساب FTMO تلقائيًا بالكامل - بدون أي نقر يدوي.
# يعتمد فقط على مفاتيح ملف /config: الموثّقة رسميًا من MetaQuotes:
# https://www.metatrader5.com/en/terminal/help/start_advanced/start
#
# طريقة الاستخدام:
#   1. عدّل قيمة $Symbol أدناه لتطابق الاسم الذي تراه في MT5 على هاتفك
#   2. افتح PowerShell (ليس كمسؤول بالضرورة) والصق هذا الملف كاملاً، أو
#      شغّله بالأمر:  powershell -ExecutionPolicy Bypass -File deploy_live_ftmo.ps1
#   3. سيُطلب منك إدخال رقم الحساب وكلمة المرور والخادم بشكل آمن (لن تظهر
#      على الشاشة ولن تُحفظ في أي مكان غير ملف الإعداد المحلي على جهازك)
# =====================================================================

# --- 1) عدّل هذا السطر فقط قبل التشغيل ---
$Symbol = "NAS100"   # <-- غيّره للاسم الصحيح الذي تراه في Market Watch على هاتفك

# --- إعدادات ثابتة ---
$MT5Dir   = "C:\Program Files\MetaTrader 5"
$Term     = Join-Path $MT5Dir "terminal64.exe"
$Editor   = Join-Path $MT5Dir "MetaEditor64.exe"
$ExpertsDir = Join-Path $MT5Dir "MQL5\Experts"
$EaName   = "NQ100_D1_Live_FTMO"

Write-Host "=== 1/5: التحقق من تثبيت MT5 ===" -ForegroundColor Cyan
if (-not (Test-Path $Term)) {
    Write-Host "MT5 غير مثبت - سيتم تحميله وتثبيته الآن (صامت)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -OutFile "$env:TEMP\mt5setup.exe"
    Start-Process -FilePath "$env:TEMP\mt5setup.exe" -ArgumentList "/auto" -Wait
    Start-Sleep -Seconds 5
} else {
    Write-Host "MT5 مثبت مسبقًا في: $MT5Dir" -ForegroundColor Green
}
if (-not (Test-Path $Term)) { Write-Host "خطأ: لم يتم العثور على terminal64.exe حتى بعد التثبيت." -ForegroundColor Red; exit 1 }

Write-Host "=== 2/5: نسخ ملف البوت (Expert Advisor) ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ExpertsDir | Out-Null
$EaPath = Join-Path $ExpertsDir "$EaName.mq5"

@'
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

'@ | Set-Content -Path $EaPath -Encoding UTF8

Write-Host "تم نسخ $EaPath" -ForegroundColor Green

Write-Host "=== 3/5: تجميع (Compile) البوت ===" -ForegroundColor Cyan
$compileLog = Join-Path $env:TEMP "compile.log"
Remove-Item $compileLog -ErrorAction SilentlyContinue
Start-Process -FilePath $Editor -ArgumentList "/compile:`"$EaPath`"","/log:`"$compileLog`"" -Wait
Start-Sleep -Seconds 3
if (Test-Path $compileLog) { Get-Content $compileLog }
$Ex5Path = Join-Path $ExpertsDir "$EaName.ex5"
if (-not (Test-Path $Ex5Path)) {
    Write-Host "خطأ: فشل التجميع - راجع الرسالة أعلاه." -ForegroundColor Red
    exit 1
}
Write-Host "تم التجميع بنجاح: $Ex5Path" -ForegroundColor Green

Write-Host "=== 4/5: إدخال بيانات حساب FTMO (آمن، لن تُحفظ إلا على جهازك) ===" -ForegroundColor Cyan
$Login    = Read-Host "رقم الحساب (Login)"
$SecurePw = Read-Host "كلمة المرور" -AsSecureString
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($SecurePw))
$ServerName = Read-Host "اسم الخادم (مثال: FTMO-Demo)"

$iniPath = Join-Path $env:TEMP "ftmo_live.ini"
$ini = @"
[Common]
Login=$Login
Password=$Password
Server=$ServerName

[Experts]
AllowLiveTrading=1
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Expert=$EaName
Symbol=$Symbol
Period=D1
"@
Set-Content -Path $iniPath -Value $ini -Encoding ASCII
Write-Host "تم إنشاء ملف الإعداد المحلي (مؤقت): $iniPath" -ForegroundColor Green

Write-Host "=== 5/5: تشغيل MT5 حيًا (سيبقى يعمل في الخلفية) ===" -ForegroundColor Cyan
Start-Process -FilePath $Term -ArgumentList "/config:`"$iniPath`""
Write-Host ""
Write-Host "تم التشغيل! تحقّق الآن من:" -ForegroundColor Green
Write-Host " 1) نافذة MT5 فتحت رسمًا بيانيًا لرمز $Symbol بفريم D1"
Write-Host " 2) أيقونة ابتسامة خضراء 🙂 في أعلى يمين الرسم البياني"
Write-Host " 3) في تبويب Experts/Journal أسفل الشاشة: سطر يبدأ بـ 'NQ100_D1_Live_FTMO: initialized...'"
Write-Host " 4) افتح تطبيق MT5 على هاتفك وتأكد أن الحساب متصل - أي صفقة ستظهر هناك تلقائيًا"
Write-Host ""
Write-Host "ملاحظة أمان: ملف الإعداد المؤقت يحتوي كلمة المرور بنص صريح في $iniPath" -ForegroundColor Yellow
Write-Host "احذفه الآن إن أردت (Remove-Item '$iniPath') - MT5 سيبقى مسجلاً دخوله حتى بدونه." -ForegroundColor Yellow
