# دليل شامل: ربط Google Antigravity بـ MetaTrader 5 (تحكم كامل)

> **لماذا هذا التحول؟** بعد محاولات متعددة لجلب بيانات تاريخية حقيقية من هذا
> الـsandbox (Yahoo محدود بسنتين H1، Dukascopy محظور بـCloudflare ثم محدود
> بـrate-limit صارم بعد تجاوز الحجب)، تبيّن أن **حاسوب المستخدم نفسه، متصل
> مباشرة بـMT5 عند FTMO، هو المصدر الأدق والأسرع والأكثر موثوقية** — بيانات
> حقيقية 100% لنفس الرمز `US100.cash`، بدون أي حظر أو rate-limit (لأنه عميل
> شرعي عند البروكر)، وبإمكانية اختبار حي (Forward Test) وهو أمر مستحيل من
> أي sandbox معزول عن الشبكة الحية.

## 1. ما هو Google Antigravity؟

Antigravity هو منصة تطوير "Agent-first" من Google (أُطلقت نوفمبر 2025 مع
Gemini 3)، مبنية على VS Code، تسمح لوكلاء AI مستقلين (Agents) بالتخطيط،
كتابة الكود، تشغيله، واختباره داخل بيئتك مباشرة — عبر المحرر، الطرفية
(Terminal)، وحتى متصفح مدمج. الفرق الجوهري عن أي chatbot عادي: Antigravity
يُنفّذ الأوامر فعليًا على جهازك (ملفات، أوامر shell، واتصالات شبكة) وليس
فقط يقترح نصًا.

- تحميل: `antigravity.google` (مجاني، Windows/macOS/Linux)
- يدعم بروتوكول **MCP** (Model Context Protocol) لربط أي أداة خارجية —
  وهذا بالضبط ما يفتح الباب للتحكم في MT5.
- مصدر: [layer3labs.io](https://www.layer3labs.io/guides/google-antigravity-explained),
  [aicodingtools.im](https://aicodingtools.im/blog/what-is-google-antigravity-complete-guide)

## 2. كيف يتحكم Antigravity في MT5؟ (عبر MCP Server)

MCP Server هو "جسر" صغير يعمل على حاسوبك، يتصل بـMT5 عبر مكتبة
`MetaTrader5` الرسمية بايثون (Windows فقط)، ويعرض كل إمكانياته كأدوات
(tools) يستطيع أي Agent (Antigravity/Claude/Cursor) استدعاءها مباشرة بلغة
طبيعية.

**الأداة المُوصى بها:** [`metatrader-mcp-server`](https://github.com/ariadng/metatrader-mcp-server)
(32 أداة MCP: بيانات حية، شموع تاريخية بكل الفريمات، تنفيذ أوامر، تعديل
SL/TP، معلومات الحساب، Strategy Tester headless، ...) — تدعم Antigravity
صراحة في توثيقها.

بديل آخر كامل الميزات مع طبقة أمان للصفقات الحقيقية:
[`mt5-trading-mcp`](https://github.com/vincentwongso/mt5-trading-mcp) (يدعم
Windows وLinux/Docker عبر Wine، مع "consent/audit policy layer" يطلب تأكيدك
قبل أي صفقة حقيقية — مناسب إذا أردت حماية إضافية لاحقًا).

## 3. خطوات التثبيت (على حاسوبك، Windows، حيث MT5/FTMO مثبت أصلاً)

### الخطوة 1 — تثبيت Antigravity
1. اذهب إلى `https://antigravity.google/download` ونزّل النسخة لـWindows.
2. ثبّته، سجّل دخول بحساب Google، اختر "Agent-assisted development"
   (الموصى به) أو "Agent-driven" (Autopilot — تحكم أكبر للـAgent، أقل تدخل
   منك).

### الخطوة 2 — تفعيل التداول الآلي في MT5 (شرط أساسي)
في منصة MT5 نفسها (نفس المنصة من Task 51):
`Tools → Options → Expert Advisors → ✅ Allow algorithmic trading`

### الخطوة 3 — تثبيت Python (إذا لم يكن مثبتًا)
نزّل Python 3.10+ من `python.org`، تأكد من تفعيل "Add to PATH" أثناء التثبيت.

### الخطوة 4 — تثبيت MCP Server
افتح CMD أو PowerShell:
```powershell
pip install metatrader-mcp-server
```

### الخطوة 5 — ربطه بـAntigravity
أنشئ/عدّل الملف التالي (المسار العام):
`%USERPROFILE%\.gemini\config\mcp_config.json`

أو خاص بالمشروع فقط:
`.agents\mcp_config.json` (داخل مجلد مشروعك)

بالمحتوى التالي (عدّل القيم بين `<>`):
```json
{
  "mcpServers": {
    "metatrader": {
      "command": "metatrader-mcp-server",
      "args": [
        "--login",     "<رقم حسابك عند FTMO>",
        "--password",  "<كلمة مرور MT5>",
        "--server",    "<اسم سيرفر FTMO، مثال: FTMO-Server>",
        "--transport", "stdio"
      ]
    }
  }
}
```

> إذا كان مسار MT5 غير الافتراضي، أضف:
> `"--path", "C:\\Program Files\\MetaTrader 5\\terminal64.exe"`

### الخطوة 6 — إعادة تشغيل Antigravity والتحقق
أعد تشغيل Antigravity بالكامل، افتح محادثة جديدة، واسأل:
```
ما هو رصيد حسابي الحالي في MT5؟
```
إذا أجاب برصيدك الحقيقي → الاتصال نجح. إذا فشل، راجع قسم "استكشاف الأخطاء"
أسفل الدليل.

## 4. استكشاف الأخطاء الشائعة
| المشكلة | الحل |
|---|---|
| Connection failed | تأكد MT5 شغّال ومسجّل دخول فعليًا، وAlgo Trading مفعّل |
| Module not found | أعد `pip install metatrader-mcp-server`، تحقق من إصدار Python ≥ 3.10 |
| Order execution failed | تأكد الرمز `US100.cash` موجود في Market Watch عندك (أضفه إن لم يظهر) |

## 5. ملاحظة أمان مهمة
الإعدادات أعلاه تعطي Antigravity **قدرة كاملة** على القراءة والتنفيذ على
حسابك (بما فيها فتح/إغلاق صفقات حقيقية إن طُلب منه ذلك). لا يوجد قيد
افتراضي يمنعه. **القرار لك بخصوص متى تسمح له بتنفيذ صفقات فعلية** مقابل
الاكتفاء بالبيانات/الباكتست/Strategy Tester (التي لا تحمل أي خطر مالي).
راجع قسم "أوامر جاهزة" أسفل — صُمّمت لتفصل بوضوح بين المرحلتين.
