# مكتبة هندسة البرومبتات الاحترافية

مكتبة دائمة تُستعمل في كل مشاريعنا — وليست مجموعة برومبتات مؤقتة. تعمل
جنبًا إلى جنب مع مهارتي `prompt-engineering-expert` و
`prompt-injection-defense` في `.agents/skills/`.

## الفرق عن `antigravity-pro-package/prompts-library/`
تلك مكتبة ضيقة مخصصة فقط لبرومبتات مشروع MT5 الجاهزة للصق المباشر —
لا تُكرَّر هنا. هذه المكتبة عامة: قوالب وأطر عمل تصلح لأي مهمة مستقبلية
(برمجة، بحث، تداول، أتمتة، وكلاء متعددون)، وليست برومبتات جاهزة بذاتها.

## الملفات
| الملف | الاستخدام |
|---|---|
| `PROMPT_QUALITY_RUBRIC.md` | معيار تقييم 100 نقطة/10 معايير، مُختبر فعليًا على برومبت حقيقي من هذا المشروع |
| `system-prompt-template.md` | قالب System Prompt عام، بفروق لكل نموذج (Gemini/Claude/GPT) |
| `coding-agent-template.md` | قالب وكيل برمجي |
| `research-agent-template.md` | قالب وكيل بحث (يطبّق "قاعدة Reddit" المسجَّلة هذه الجلسة) |
| `mcp-agent-template.md` | قالب وكيل متصل بأدوات MCP تنفيذية حقيقية |
| `multi-agent-template.md` | قوالب Orchestrator-Workers وEvaluator-Optimizer |
| `data-analysis-trading-template.md` | قالب تحليل بيانات/باكتست، مبني على دروس فعلية من مشروع MT5 |
| `injection-test-cases.md` | 5 حالات اختبار دفاعية حميدة لفحص أي برومبت جديد |

## المصادر الأساسية (رسمية فقط، تاريخ الفحص: جلسة بناء هذه المكتبة)
1. OpenAI — [Prompt engineering guide](https://developers.openai.com/api/docs/guides/prompt-engineering)
2. OpenAI — [Safety in building agents](https://developers.openai.com/api/docs/guides/agent-builder-safety)
3. OWASP GenAI Security — [LLM01:2026 Prompt Injection](https://genai.owasp.org/llm2026/llm012026-prompt-injection/)
4. Anthropic — [Prompt engineering overview](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/overview)
5. Anthropic — [Building effective agents](https://www.anthropic.com/research/building-effective-agents)
6. Anthropic — Writing effective tools for agents / Advanced tool use
7. Google — [Gemini prompt design strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies)
8. Google — Gemini 3 developer guide (مبادئ الدقة والإيجاز لنماذج الاستدلال)

## كيف تُستخدم هذه المكتبة عمليًا
عندما يُطلب مني "أنشئ أقوى برومبت ممكن لـ...": أفتح المهارة
`prompt-engineering-expert`، أختار القالب الأقرب من هذه المكتبة كنقطة
بداية (لا أعيد الاختراع)، أملؤه بتفاصيل المهمة الفعلية، ثم أُقيّمه عبر
`PROMPT_QUALITY_RUBRIC.md` رقميًا قبل التسليم.
