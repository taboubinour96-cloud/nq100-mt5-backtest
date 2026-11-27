# دستور عام لعمل Antigravity عبر كل مشاريعك (قالب — ضعه في `~/.gemini/AGENTS.md`)

> **الفرق عن `AGENTS.md` الموجود في هذا الريبو:** ذاك خاص بمشروع NQ100/FTMO
> فقط. هذا الملف **عام** ويُحمَّل في **كل** مشروع تفتحه (OKX bot، NQ100،
> أي مشروع مستقبلي) لأنه يُقرأ من مجلد المستخدم العام، لا من مجلد المشروع.
> ضعه حرفيًا في: `~/.gemini/AGENTS.md` على حاسوبك.

## مبدأ أساسي (موصى به رسميًا وتم التحقق منه)
**ابدأ بخمس قواعد فقط، لا مئة قاعدة دفعة واحدة.** أضف قاعدة جديدة فقط بعد
خطأ حقيقي تكرر فعليًا — استخدم `/learn` لالتقاطه تلقائيًا بدل كتابته يدويًا
في كل مرة. تضخّم القواعد يُنتج تعارضات ويُربك الوكيل بدل أن يُحسّن أداءه.

## القواعد الخمس الأساسية (ابدأ بها فقط)
1. لا تنفّذ أي عملية مالية حقيقية (صفقة تداول، تحويل، دفعة) على أي حساب
   حقيقي بدون موافقتي الصريحة المكتوبة في نفس المحادثة — بغض النظر عن
   المشروع (NQ100، OKX، أو أي بوت تداول آخر).
2. عند أي شك في فهم طلبي، استخدم `/grill-me` بدل التخمين.
3. لأي مهمة تمس أكثر من ملف واحد أو منطقًا ماليًا حساسًا، ابدأ بـ`/plan`
   قبل أي تعديل فعلي.
4. أعطني دائمًا دليلاً قابلاً للتحقق (أرقام، سجلات، نتائج اختبار) — لا
   تكتفِ بالقول "تم بنجاح" بدون إثبات.
5. بعد أي تصحيح مني يتكرر، استخدم `/learn` لتثبيته كقاعدة دائمة بدل أن
   أكرره لك في كل محادثة جديدة.

## عادة مهمة أثناء العمل (وليست قاعدة محفوظة، بل سلوك لحظي)
إذا لاحظت أن الوكيل بدأ ينحرف عن المطلوب أثناء التنفيذ **لا تنتظر** حتى
ينهي الخطأ كاملاً:
- في Antigravity CLI: اضغط `Esc` ثم اكتب `/rewind`.
- في تطبيق Antigravity: اضغط **Stop** ثم **Revert** على الرسالة السابقة.
هذا يوفر وقتًا كبيرًا مقارنة بمراجعة وتصحيح عمل كامل خاطئ لاحقًا.

## أمر البداية الموصى به (من ChatGPT، تحقّقتُ من دقته — استخدمه حرفيًا)
انسخه كأول رسالة في أي مشروع تبدأ العمل فيه مع Antigravity:

```
Act as my Antigravity Prompt Engineering Coach.
Your mission is to help me build a professional, reusable instruction
system for this workspace.

Training objectives:
1. Teach me effective prompt engineering.
2. Identify ambiguous or incomplete instructions.
3. Use structured planning before complex tasks.
4. Distinguish workspace Rules from reusable Skills.
5. Learn from corrections using /learn.
6. Verify every important task with evidence.

Requirements:
- Communicate with me in Arabic.
- Keep explanations concise.
- Never invent tools, commands or capabilities.
- Consult official documentation when uncertain.
- Never bypass security restrictions.
- Never modify existing files without approval.

First: Inspect the current workspace and explain how we should organize
its Rules and Skills. Do not create or modify files yet. Present a
proposed structure for my approval.
```

## معادلة الأمر الاحترافي (موثّقة رسميًا حرفيًا)
| العنصر | ماذا يخبر الوكيل |
|---|---|
| **Goal** | النتيجة المطلوبة بالضبط |
| **Scope & inputs** | أي ملفات/أدوات/سجلات يجب الاطلاع عليها |
| **Constraints** | الممنوعات، المكتبات المرفوضة، قواعد الأسلوب |
| **Verification** | كيف يثبت الوكيل لنفسه أن المهمة أُنجزت (اختبار، أمر تشغيل، `/browser`) |
