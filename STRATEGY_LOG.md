# سجل تطوير الاستراتيجية (مصدر الحقيقة الوحيد بين الجولات)

> كل جولة: Antigravity ينفّذ، يُلحق قسمًا هنا بالنتائج الرقمية الخام
> (ليس رأيًا، أرقامًا فقط)، يرفع لـGitHub. الجلسة التالية من Arena تقرأ
> هذا الملف أولًا قبل أي شيء آخر لمعرفة أين توقفنا بالضبط.

## الحالة قبل الجولة 1 (خط الأساس المعروف)
- استراتيجية D1 بسيطة (EMA20/50 + ATR) منشورة حاليًا حية على FTMO Demo:
  32 صفقة فقط (2016-2025)، win rate 50%، profit factor 2.48 — **عينة
  صغيرة جدًا للثقة الإحصائية**.
- محرك ICT الكامل (`ict_engine/ict_engine.py` + `ICT_SPEC.md`): لم يُختبر
  على بيانات حقيقية بعد. `results/` فارغ.

## الجولة 1 — (بانتظار تنفيذ Antigravity)
- الهدف: تشغيل محرك ICT الكامل على بيانات H1 حقيقية من FTMO (أطول مدى
  متاح)، وتسجيل كل الأرقام هنا دون أي تدخل بشري في التنفيذ.
- (سيُملأ هذا القسم تلقائيًا من Antigravity بعد التنفيذ)

## ملاحظة جلسة: تفعيل حساب FTMO-Demo جديد + برومبت اتصال V2
المستخدم فعّل حساب FTMO-Demo حقيقيًا (Login معروف محليًا فقط، غير مُسجَّل
هنا لأسباب أمنية). بُني برومبت اتصال جديد `ANTIGRAVITY_MT5_SETUP_PROMPT_V2.md`
بأعلى معيار متوفر من مكتبة `promptat` (89/100) — يفرض استخدام كلمة
المرور الاستثمارية (Read-Only) لا الرئيسية في مرحلة الاتصال/الفحص بأكملها
(مبدأ أقل امتياز). **لم يُنفَّذ الاتصال الفعلي بعد من Antigravity وقت
كتابة هذا السطر** — الجلسة القادمة (Arena أو مراجعة لاحقة) يجب أن تتحقق
من التقرير النهائي (5 أسطر) الذي سينتجه Antigravity بعد تنفيذ هذا
البرومبت، وتُحدِّث هذا القسم بالنتيجة الفعلية بدل تركه فارغًا.

## الجولة 1 — محرك ICT الكامل على بيانات US100.cash H1 من FTMO-Demo (2026-11-27)
- السيرفر: `FTMO-Demo` | الحساب: `Demo` | الرصيد: `50000.0 USD` | الرافعة: `1:30` | السبريد اللحظي المسجّل: `145` نقطة (`1.45` بـ`point=0.01`).
- البيانات المحمّلة (`data/US100_H1_2017-12-29_2026-11-27.csv`): `35374` شمعة (`2017-12-29 00:00:00+00:00` إلى `2026-11-27 17:00:00+00:00`)، صفوف تالفة/NaN: `0`، فجوات >72 ساعة: `14` (عطلات/أعياد)، شموع H1 حقيقية بتدرّج ساعة واحدة تبدأ من `2021-01-22 01:00:00+00:00` (`34597` شمعة في نطاق `2021-01-01`–`2026-11-27`؛ `2018`=`258`، `2019`=`259`، `2020`=`259`).
- قمع الإشارات (`ict_engine.run_structure_and_signals`): `sweeps=1499`، `choch_after_sweep=723`، `ob_or_fvg_built=351`، `touched_zone=1661`، `pd_zone_ok=253`، `killzone_ok=108`، `rr_ok=36`.
- نتائج `ict_engine.backtest(spread_pts=1.66, slippage_pts=0.5)`:
  - `n_trades`: `36`
  - `win_rate`: `25.0%` (`CI95`: `[11.1%, 38.9%]`)
  - `profit_factor`: `1.05` (`CI95`: `[0.38, 2.27]`)
  - `total_pnl_pts`: `84.2`
  - `max_drawdown_pts`: `-417.3`
  - `avg_r_multiple`: `0.03`
- مخرجات محفوظة: `results/ict_US100_H1_2017-12-29_2026-11-27_2026-11-27.csv` و`results/ict_US100_H1_2017-12-29_2026-11-27_2026-11-27_summary.json` (تنفيذ بايثون مرجعي على بيانات FTMO الحقيقية؛ لا يوجد EA لـICT بصيغة `.mq5` في `ea/` لتشغيله داخل Strategy Tester).

## الجولة 2 — تحويل ICT إلى MQL5 + MBT Headless + Strategy Tester (2026-11-27)
### المرحلة 3 — مؤشر MQL5 (`ICT_Engine_Indicator.mq5`) + `run_indicator` (`every_tick`) + `backtest` بوحدة R
- التجميع (`compile_ea`): `0 errors, 0 warnings` لكل من `MBT_IndicatorHost.mq5` و`ICT_Engine_Indicator.mq5`.
- المدى المختبر: `2018.01.01` إلى `2026.11.27` على `US100.cash` `1h` (أول إشارة `2021.03.10 22:00`، آخر إشارة `2026.09.16 22:00`، زمن التشغيل `152.5s`).
- `validate_signals`: `total=31`، `valid=31`، `problems=0`.
- نتائج `backtest` (`ambiguous_bar=loss`، `slippage_points=50.0`، `risk_per_trade=1.0%`، `years=5.52`):
  - `trades_taken`: `31` (`wins=12`, `losses=19`, `open=0`, `signals_skipped=0`)
  - `win_rate_pct`: `38.7%`
  - `profit_factor`: `1.89`
  - `expectancy_r`: `+0.576R`
  - `net_r`: `+17.85R`
  - `avg_win_r`: `+3.16R` | `avg_loss_r`: `-1.06R`
  - `max_win_streak`: `2` | `max_loss_streak`: `6`
  - `max_drawdown_r`: `6.66R` (`max_drawdown_pct`: `6.7%`)
  - `annual_return_pct`: `+3.2%` | `monthly_return_pct`: `+0.27%`
  - تفصيل `by_regime`:
    - `ORDER_BLOCK`: `trades=22`, `win_rate=40.9%`, `profit_factor=1.98`, `net_r=+13.35R`
    - `FVG_FILL`: `trades=6`, `win_rate=33.3%`, `profit_factor=2.04`, `net_r=+4.42R`
    - `OB_AND_FVG`: `trades=3`, `win_rate=33.3%`, `profit_factor=1.03`, `net_r=+0.07R`
- تقارير المرحلة 3 المحفوظة: `results/ict_indicator_signals_20261127.csv` و`results/backtest_US100.cash_1h_20261127_210839.html`.

### المرحلة 4 — Expert Advisor (`ICT_Engine_EA.mq5`) + Strategy Tester الأصلي (`every_tick`, `deposit=50000`)
- التجميع (`compile_ea`): `0 errors, 0 warnings`.
- `signal_parity` بين إشارات المؤشر وإشارات الـEA: `reference_count=31`, `candidate_count=31`, `matched=31`, `mismatched=0`, `verdict=identical`.
- المدى المختبر: `2018.01.01`–`2026.11.27` على `US100.cash` `1h` (`every_tick`, `deposit=50000.00 USD`, `Ticks=292348956`, `Bars=35256`, `History Quality=57%`, زمن التشغيل `145.8s`).
- مقاييس Strategy Tester بعملة الحساب (USD):
  - `Total Trades`: `30` (`Profit Trades=12 (40.00%)`, `Loss Trades=18 (60.00%)`; `Long=18 (33.33%)`, `Short=12 (50.00%)`)
  - `Total Net Profit`: `+17178.33 USD` (`Gross Profit=28589.14`, `Gross Loss=-11410.81`)
  - `Profit Factor`: `2.51`
  - `Expected Payoff`: `572.61 USD`
  - `Recovery Factor`: `3.43`
  - `Sharpe Ratio`: `8.84`
  - `Balance Drawdown Maximal`: `4456.01 USD (6.75%)`
  - `Equity Drawdown Maximal`: `5007.82 USD (7.54%)` | `Equity Drawdown Relative`: `8.3%`
- تقارير المرحلة 4 المحفوظة: `results/ICT_Engine_EA_20261127_211028_mbt.html`، `results/ICT_Engine_EA_20261127_211028.htm`، و`results/ict_ea_signals_20261127.csv`.

## الجولة 3 — فحص الثبات الزمني (نصفان منفصلان عبر Strategy Tester، 2026-11-27)
> نفس إعدادات المرحلة 4 (`ICT_Engine_EA`, `US100.cash`, `1h`, `every_tick`, `deposit=50000.00 USD`, `leverage=30`).

### النصف الأول (`2018.01.01` – `2022.01.01`)
- جودة البيانات: `History Quality=6%`, `Bars=6297`, `Ticks=19965414` (بيانات FTMO قبل `2021-01-22` بفاصل يومي لا H1 حقيقي)، زمن التشغيل `11.0s`.
- `Total Trades`: `4` (`Profit Trades=1 (25.00%)`, `Loss Trades=3 (75.00%)`; `Long=4 (25.00%)`, `Short=0 (0.00%)`).
- `Total Net Profit`: `+962.12 USD` (`Gross Profit=2477.64`, `Gross Loss=-1515.52`).
- `Profit Factor`: `1.63` | `Expected Payoff`: `240.53 USD` | `Recovery Factor`: `0.76` | `Sharpe Ratio`: `0.30`.
- `Balance Drawdown Maximal`: `998.79 USD (2.00%)` | `Equity Drawdown Maximal`: `1270.15 USD (2.54%)`.
- التقارير: `results/ICT_Engine_EA_split1_2018_2022_mbt.html` و`results/ICT_Engine_EA_split1_2018_2022.htm`.

### النصف الثاني (`2022.01.01` – `2026.11.27`)
- جودة البيانات: `History Quality=99%`, `Bars=28959`, `Ticks=272383542`، زمن التشغيل `44.1s`.
- `Total Trades`: `26` (`Profit Trades=11 (42.31%)`, `Loss Trades=15 (57.69%)`; `Long=14 (35.71%)`, `Short=12 (50.00%)`).
- `Total Net Profit`: `+15909.72 USD` (`Gross Profit=25615.82`, `Gross Loss=-9706.10`).
- `Profit Factor`: `2.64` | `Expected Payoff`: `611.91 USD` | `Recovery Factor`: `3.24` | `Sharpe Ratio`: `8.71`.
- `Balance Drawdown Maximal`: `4370.62 USD (6.75%)` | `Equity Drawdown Maximal`: `4911.99 USD (7.54%)` | `Equity Drawdown Relative`: `8.3%`.
- التقارير: `results/ICT_Engine_EA_split2_2022_2026_mbt.html` و`results/ICT_Engine_EA_split2_2022_2026.htm`.

### ملاحظات رقمية صريحة (لا تمثل حكمًا نهائيًا)
- جودة بيانات ما قبل 2022: `History Quality=6%` في النصف الأول (`2018.01.01`–`2022.01.01`، `4` صفقات فقط) ناتجة عن بيانات تيك اصطناعية وفواصل يومية قبل `2021-01-22`؛ لذلك **الفترة قبل 2022 غير قابلة للحكم إحصائيًا بسبب جودة البيانات فقط، وليست دليلاً على تراجع أو ضعف الاستراتيجية**.
- وتيرة التداول: `30` صفقة خلال ~`9` سنوات (`2018`–`2026`) — وتيرة منخفضة جدًا مقارنة بمتطلبات أي تحدي تقييم بوقت محدود (مثل FTMO).

## الجولة 4 — فحص تعميم مؤشر ICT عبر رموز مؤشرات FTMO-Demo (2026-11-27)
> نفس المؤشر `ICT_Engine_Indicator.mq5` على فريم `1h` عبر `run_indicator` (`every_tick`) ثم `validate_signals` ثم `backtest` (بوحدة R، `ambiguous_bar=loss`، `slippage_points=50.0`، `risk_per_trade=1.0%`).

### 1) `US30.cash` (`2021-01-01` – `2026-11-27`)
- جودة البيانات: `History Quality=99%` (`Bars=34883`, `Ticks=397402003`; بيانات `copy_rates` متصلة من `2019-02-08 15:00+00:00`, `bad=0`).
- `validate_signals`: `total=44`, `valid=44`, `problems=0` (`first=2020.01.24 21:00`, `last=2026.11.12 23:00`).
- نتائج `backtest` (`years=6.8`):
  - `trades_taken`: `44` (`wins=11`, `losses=33`, `open=0`, `signals_skipped=0`)
  - `win_rate_pct`: `25.0%` | `profit_factor`: `1.21` | `expectancy_r`: `+0.164R` | `net_r`: `+7.24R`
  - `avg_win_r`: `+3.81R` | `avg_loss_r`: `-1.05R` | `max_win_streak`: `2` | `max_loss_streak`: `8` | `max_drawdown_r`: `10.45R` (`10.4%`)
  - `by_regime`: `FVG_FILL` (`trades=14`, `WR=28.6%`, `PF=1.56`, `net_r=+5.80R`), `ORDER_BLOCK` (`trades=30`, `WR=23.3%`, `PF=1.06`, `net_r=+1.44R`).
- الملفات: `results/ict_US30.cash_signals_20261127.csv`, `results/backtest_US30.cash_1h_20261127.html`.

### 2) `US500.cash` (`2021-01-01` – `2026-11-27`)
- جودة البيانات: `History Quality=87%` (`Bars=34580`, `Ticks=81817377`; بيانات `copy_rates` متصلة من `2021-01-21 22:00+00:00`, `bad=0`).
- `validate_signals`: `total=45`, `valid=45`, `problems=0` (`first=2021.03.18 14:00`, `last=2026.10.22 12:00`).
- نتائج `backtest` (`years=5.59`):
  - `trades_taken`: `44` (`wins=7`, `losses=37`, `open=0`, `signals_skipped=1`)
  - `win_rate_pct`: `15.9%` | `profit_factor`: `0.54` | `expectancy_r`: `-0.433R` | `net_r`: `-19.05R`
  - `avg_win_r`: `+3.24R` | `avg_loss_r`: `-1.13R` | `max_win_streak`: `2` | `max_loss_streak`: `9` | `max_drawdown_r`: `21.14R` (`21.1%`)
  - `by_regime`: `ORDER_BLOCK` (`trades=34`, `WR=17.6%`, `PF=0.66`, `net_r=-10.56R`), `FVG_FILL` (`trades=8`, `WR=12.5%`, `PF=0.22`, `net_r=-6.39R`), `OB_AND_FVG` (`trades=2`, `WR=0.0%`, `PF=0.00`, `net_r=-2.10R`).
- الملفات: `results/ict_US500.cash_signals_20261127.csv`, `results/backtest_US500.cash_1h_20261127.html`.

### 3) `GER40.cash` (`2021-05-19` – `2026-11-27`)
- جودة البيانات: `History Quality=86%` (`Bars=32201`, `Ticks=74517504`; بيانات `copy_rates` متصلة من `2021-05-18 12:00+00:00`, `bad=0`).
- `validate_signals`: `total=49`, `valid=49`, `problems=0` (`first=2021.08.25 23:00`, `last=2026.10.23 11:00`).
- نتائج `backtest` (`years=5.16`):
  - `trades_taken`: `46` (`wins=7`, `losses=39`, `open=0`, `signals_skipped=3`)
  - `win_rate_pct`: `15.2%` | `profit_factor`: `0.49` | `expectancy_r`: `-0.465R` | `net_r`: `-21.37R`
  - `avg_win_r`: `+2.91R` | `avg_loss_r`: `-1.07R` | `max_win_streak`: `1` | `max_loss_streak`: `14` | `max_drawdown_r`: `24.99R` (`25.0%`)
  - `by_regime`: `ORDER_BLOCK` (`trades=25`, `WR=12.0%`, `PF=0.42`, `net_r=-13.57R`), `FVG_FILL` (`trades=12`, `WR=16.7%`, `PF=0.58`, `net_r=-4.56R`), `OB_AND_FVG` (`trades=9`, `WR=22.2%`, `PF=0.56`, `net_r=-3.24R`).
- الملفات: `results/ict_GER40.cash_signals_20261127.csv`, `results/backtest_GER40.cash_1h_20261127.html`.

- **ملاحظة مقارنة صريحة**: أداء محرك ICT **غير متسق عبر الرموز المختلفة** — مربح على `US100.cash` (`31` صفقة, `WR=38.7%`, `PF=1.89`) وضعيف على `US30.cash` (`44` صفقة, `WR=25.0%`, `PF=1.21`) وخاسر بوضوح على `US500.cash` (`44` صفقة, `WR=15.9%`, `PF=0.54`) و`GER40.cash` (`46` صفقة, `WR=15.2%`, `PF=0.49`).

## الجولة 5 — تحسين إدارة المخاطر في `ICT_Engine_EA.mq5` على `US100.cash` (2026-11-27)
> الإضافات في `ICT_Engine_EA.mq5` (`v1.10`, `0 errors, 0 warnings`): (أ) Anti-Martingale (`-20%` بعد كل خسارتين متتاليتين بحد أدنى `0.25x`، و`+25%` بعد كل ربحين متتاليين بحد أقصى `2.00x`)، (ب) حد خسارة يومي أقصى `3.0%` من رصيد بداية اليوم يوقف الصفقات الجديدة حتى اليوم التالي.

- مقارنة المدى الكامل (`2018.01.01` – `2026.11.27`، `every_tick`, `deposit=50000.00 USD`, `HQ=57%`):
  - قبل التحسين (`v1.00`): `Total Trades=30` (`WR=40.00%`), `Net Profit=+17178.33 USD`, `PF=2.51`, `Balance DD Max=4456.01 USD (6.75%)`, `Equity DD Max=5007.82 USD (7.54%)`, `Sharpe=8.84`.
  - بعد التحسين (`v1.10`): `Total Trades=30` (`WR=40.00%`), `Net Profit=+11356.56 USD` (`GP=19932.68`, `GL=-8576.12`), `PF=2.32`, `Expected Payoff=378.55 USD`, `Recovery Factor=3.06`, `Sharpe=7.78`, `Balance DD Max=3037.50 USD (4.89%)`, `Equity DD Max=3717.21 USD (Relative 6.77%)`.
- مقارنة النافذة الموثوقة (`2022.01.01` – `2026.11.27`، `HQ=99%`):
  - قبل التحسين (`v1.00`): `Total Trades=26` (`WR=42.31%`), `Net Profit=+15909.72 USD`, `PF=2.64`, `Balance DD Max=4370.62 USD (6.75%)`, `Equity DD Max=4911.99 USD (7.54%)`.
  - بعد التحسين (`v1.10`): `Total Trades=26` (`WR=42.31%`), `Net Profit=+13478.26 USD` (`GP=22701.82`, `GL=-9223.56`), `PF=2.46`, `Expected Payoff=518.39 USD`, `Recovery Factor=2.93`, `Sharpe=7.74`, `Balance DD Max=3927.07 USD (6.10%)`, `Equity DD Max=4593.09 USD (Relative 8.3%)`.
- تقارير الجولة 5 المحفوظة: `results/ICT_Engine_EA_v2_full_2018_2026_mbt.html`, `results/ICT_Engine_EA_v2_full_2018_2026.htm`, `results/ICT_Engine_EA_v2_hq99_2022_2026_mbt.html`, `results/ICT_Engine_EA_v2_hq99_2022_2026.htm`.

## الجولة 6 — التحقيق في التخصيص الزائد (Overfitting) وتطبيع العتبات (2026-11-27)
- **فحص العتبات الحرفية في `ICT_SPEC.md` و`ict_engine/ict_engine.py` و`ea/ICT_Engine_Indicator.mq5`**:
  - جميع عتبات محرك ICT مُعرَّفة **مسبقًا** كنِسَب لـ`ATR(14)` على H1 أو نسب R:R لا أرقام نقاط مطلقة:
    - `DISPLACEMENT_ATR_MULT = 1.5` / `InpDispAtrMult = 1.5` (`(High - Low) >= 1.5 * ATR`)
    - `FVG_MIN_ATR_MULT = 0.10` / `InpFvgMinAtrMult = 0.10` (`gap >= 0.10 * ATR`)
    - `OB_SL_BUFFER_ATR_MULT = 0.10` / `InpSlBufferAtrMult = 0.10` (`0.10 * ATR`)
    - `MIN_RR = 2.0` / `InpMinRR = 2.0` و`MAX_RR = 5.0` / `InpMaxRR = 5.0`
    - `SWING_LEFT_RIGHT = 2` / `InpSwingLR = 2` و`KILL_ZONES_NY = [("02:00","05:00"), ("07:00","10:00"), ("13:30","16:00")]`
  - القيمة الثابتة الوحيدة بالنقاط كانت `slippage_points: 50.0` في `MBT/config.yaml` (و`spread_pts=1.66, slippage_pts=0.5` في `ict_engine.py`).
- **فحص استبعاد التكلفة الثابتة (`cost_price=0.0` في MBT `backtest`)**:
  - `US100.cash`: `31` صفقة, `WR=38.7%`, `PF=2.01`, `NetR=+19.28R` (مع التكلفة: `PF=1.89`, `+17.85R`)
  - `US30.cash`: `44` صفقة, `WR=25.0%`, `PF=1.29`, `NetR=+9.54R` (مع التكلفة: `PF=1.21`, `+7.24R`)
  - `US500.cash`: `44` صفقة, `WR=15.9%`, `PF=0.63`, `NetR=-13.63R` (مع التكلفة: `PF=0.54`, `-19.05R`)
  - `GER40.cash`: `46` صفقة, `WR=15.2%`, `PF=0.53`, `NetR=-18.25R` (مع التكلفة: `PF=0.49`, `-21.37R`)
- **تشخيص إضافي (`LONG` مقابل `SHORT` و`ambiguous_bar`)**:
  - `US100.cash`: `LONG=6/19 (31.6%)`, `SHORT=6/12 (50.0%)`, `ambig_bars=1`, `PF(win)=2.12`
  - `US30.cash`: `LONG=9/30 (30.0%)`, `SHORT=2/14 (14.3%)`, `ambig_bars=1`, `PF(win)=1.31`
  - `US500.cash`: `LONG=6/31 (19.4%)`, `SHORT=1/13 (7.7%)`, `ambig_bars=1`, `PF(win)=0.68`
  - `GER40.cash`: `LONG=6/36 (16.7%)`, `SHORT=1/10 (10.0%)`, `ambig_bars=0`, `PF(win)=0.49`
- **الاستنتاج الصريح**: لأن عتبات المحرك مُطبَّعة أصلًا على `ATR(14)` H1 (ولم تكن نقاطًا مطلقة)، واستمر التباين الحاد حتى مع إزالة كل التكاليف (`PF=2.01` على `US100.cash` مقابل `PF=0.63` على `US500.cash` و`PF=0.53` على `GER40.cash`)، فإن ربحية `US100.cash` الأصلية في عينة صغيرة (`31` صفقة فقط) يُرجَّح بقوة أنها **صدفة إحصائية / تخصيص مفرط لأداة واحدة وفترات Kill Zones الخاصة بناسداك** وليست أفضلية ICT متّسقة عابرة للأسواق.
