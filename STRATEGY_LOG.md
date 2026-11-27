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
