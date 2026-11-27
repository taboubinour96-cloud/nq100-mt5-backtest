# حزمة تهيئة احترافية لـGoogle Antigravity — دليل التثبيت والاستخدام (Windows)

> بُنيت بالاعتماد الحصري على التوثيق الرسمي في `antigravity.google/docs`
> (المصادر مذكورة أسفل كل قسم). لا توجد أوامر أو خصائص مُختلَقة.

## خريطة الحزمة

| المجلد/الملف | يذهب إلى | يعمل على |
|---|---|---|
| `global-personal-config/AGENTS.md` | انسخه إلى `C:\Users\<اسمك>\.gemini\AGENTS.md` | **كل** مشاريعك |
| `global-personal-config/config/` | انسخ محتواه إلى `C:\Users\<اسمك>\.gemini\config\` | **كل** مشاريعك |
| `prompts-library/` | مرجع تنسخ منه عند الحاجة، لا يُثبَّت | أي مشروع، يدويًا |
| `permissions-security-guide.md` | مرجع قراءة لإعداد Settings يدويًا | التطبيق/الـCLI عمومًا |
| `ROADMAP_ADVANCED_LAYER.md` | مرجع للمستقبل فقط | — |
| (في جذر هذا الريبو) `AGENTS.md` + `.agents/` | يعملان تلقائيًا بمجرد فتح هذا الريبو في Antigravity | مشروع NQ100/FTMO فقط |

## خطوات التثبيت على Windows (خطوة بخطوة)

### أ) الجزء العام (يُفعَّل مرة واحدة فقط، يخدم كل مشاريعك المستقبلية)
1. افتح **PowerShell** عاديًا (ليس بصلاحية مدير بالضرورة).
2. أنشئ المجلدات إن لم تكن موجودة:
   ```powershell
   mkdir "$env:USERPROFILE\.gemini\config\rules" -Force
   mkdir "$env:USERPROFILE\.gemini\config\skills\session-recap" -Force
   ```
3. انسخ `global-personal-config/AGENTS.md` من هذه الحزمة إلى:
   `C:\Users\<اسمك>\.gemini\AGENTS.md`
4. انسخ محتوى `global-personal-config/config/rules/*.md` إلى:
   `C:\Users\<اسمك>\.gemini\config\rules\`
5. انسخ `global-personal-config/config/skills/session-recap/SKILL.md` إلى:
   `C:\Users\<اسمك>\.gemini\config\skills\session-recap\SKILL.md`
6. أعد تشغيل Antigravity App أو الـCLI (`agy`) إن كان مفتوحًا — القواعد
   الجديدة تُحمَّل عند بدء الجلسة.

**كيف تتحقق أنها فعلاً حُمِّلت؟** افتح أي مشروع، اكتب `@ru` في صندوق
الرسائل (App) — يجب أن تظهر قواعدك الثلاث ضمن قائمة **Rules**. (مصدر
الآلية: `/docs/at-mentions`، `/docs/customization-discovery`).

### ب) الجزء الخاص بمشروع NQ100/FTMO (جاهز بالفعل، لا تثبيت يدوي مطلوب)
ببساطة استنسخ (`clone`) هذا الريبو على جهازك وافتحه كمشروع في Antigravity
— سيقرأ تلقائيًا `AGENTS.md` و`.agents/skills/` الموجودين في جذره، لأن
Antigravity يفحص جذر المستودع (حيث يوجد `.git`) تلقائيًا:
```powershell
git clone https://github.com/taboubinour96-cloud/nq100-mt5-backtest.git
```

### ج) مكتبة البرومبتات (استخدام يدوي حسب الحاجة)
لا تُثبَّت — افتح `prompts-library/onboarding-coach-prompt.md` أو
`planning-prompts.md` وانسخ منها البرومبت المناسب للصقه مباشرة في
Antigravity وقت الحاجة.

### د) دليل الصلاحيات
اقرأه مرة واحدة الآن (`permissions-security-guide.md`)، ثم اضبط
**Settings → General → Global Permissions** في التطبيق على **Default**
(الموصى به يوميًا)، وارجع إليه لاحقًا عند أي قرار متعلق بالأمان.

## لماذا هذا التنظيم تحديدًا؟
مبني حرفيًا على الفرق الرسمي بين نطاقين (`/docs/customization-discovery`):
- **Personal** (`~/.gemini/...`) = يُحمَّل في كل مشروع.
- **Workspace** (`.agents/` + `AGENTS.md` داخل مستودع معيّن) = خاص بذلك
  المستودع فقط، ويمكن مشاركته مع فريقك عبر Git.

هذه الحزمة تفصل الاثنين بوضوح حتى لا تُكرّر نفس القواعد في كل مشروع
جديد تبدأه.

## المصادر الرسمية المستخدمة في بناء هذه الحزمة
- https://antigravity.google/docs/customization-discovery
- https://antigravity.google/docs/rules
- https://antigravity.google/docs/skills
- https://antigravity.google/docs/permissions
- https://antigravity.google/docs/agent-settings
- https://antigravity.google/docs/sandbox
- https://antigravity.google/docs/at-mentions
- https://antigravity.google/docs/slash-commands
- https://antigravity.google/docs/learn/prompting
- https://antigravity.google/docs/commands/learn
- https://antigravity.google/docs/getting-started
- https://antigravity.google/docs/marketplace
