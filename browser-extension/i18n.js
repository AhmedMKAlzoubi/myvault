// Interface language for the extension (popup, settings page and the cards it
// shows on web pages). English is written in the code; when the browser's
// language is Arabic, mvT() looks each string up in AR below. Keys with {0}, {1}
// match strings built from templates. Saved data is never passed through mvT().
(() => {
  const AR = {
    "Checking…": "جارٍ الفحص…",
    "Save this page's login": "احفظ بيانات الدخول في هذه الصفحة",
    "Password generator": "مولّد كلمات المرور",
    "New password": "كلمة مرور جديدة",
    "Copy": "نسخ",
    "Copied": "تم النسخ",
    "Length": "الطول",
    "Uppercase A–Z": "أحرف كبيرة A–Z",
    "Lowercase a–z": "أحرف صغيرة a–z",
    "Numbers 0–9": "أرقام 0–9",
    "Symbols !@#": "رموز !@#",
    "Avoid look-alikes": "تجنّب الأحرف المتشابهة",
    "Settings and pairing token": "الإعدادات ورمز الاقتران",
    "Not paired yet. Open Settings below and paste the token.": "لم يتم الاقتران بعد. افتح الإعدادات أدناه والصق الرمز.",
    "The pairing token is wrong. Copy it again from the app.": "رمز الاقتران خاطئ. انسخه مرة أخرى من التطبيق.",
    "Can't reach MyVault. Is the app open?": "تعذّر الوصول إلى MyVault. هل التطبيق مفتوح؟",
    "MyVault is locked. Unlock the app to fill.": "MyVault مقفل. افتح التطبيق للتعبئة.",
    "Connected to MyVault {0}": "متصل بـ MyVault {0}",
    "Connected to MyVault": "متصل بـ MyVault",
    "No saved logins for {0}.": "لا توجد بيانات دخول محفوظة لـ {0}.",
    "No saved logins for this page.": "لا توجد بيانات دخول محفوظة لهذه الصفحة.",
    "Fill": "تعبئة",
    "(no username)": "(بلا اسم مستخدم)",
    "Password suggested on this site, not saved yet": "كلمة مرور مقترحة في هذا الموقع، لم تُحفظ بعد",
    "Turn on at least one kind.": "فعّل نوعًا واحدًا على الأقل.",
    "Open MyVault to generate.": "افتح MyVault للتوليد.",
    "Reload the page first, then try again": "أعد تحميل الصفحة أولًا، ثم حاول مرة أخرى",
    "MyVault settings": "إعدادات MyVault",
    "Pair with the MyVault app": "الاقتران مع تطبيق MyVault",
    "In the MyVault desktop app, open": "في تطبيق MyVault على الكمبيوتر افتح",
    "Browser auto-fill": "التعبئة التلقائية في المتصفح",
    "(bottom left), copy the": "(أسفل القائمة الجانبية)، وانسخ",
    "pairing token": "رمز الاقتران",
    "and paste it here. The token lets this extension talk to the app on this computer only (": "والصقه هنا. يتيح الرمز لهذه الإضافة التحدث إلى التطبيق على هذا الكمبيوتر فقط (",
    "). Keep it private.": "). أبقِه سرًّا.",
    "Pairing token": "رمز الاقتران",
    "Paste the token from the app": "الصق الرمز من التطبيق",
    "Port (keep 8787 unless you changed it)": "المنفذ (أبقِه 8787 ما لم تغيّره)",
    "Save & test": "حفظ واختبار",
    "Test connection": "اختبار الاتصال",
    "Connected. MyVault {0} is unlocked and ready.": "متصل. MyVault {0} مفتوح وجاهز.",
    "Connected, but the vault is locked. Unlock the app to fill logins.": "متصل، لكن الخزنة مقفلة. افتح التطبيق لتعبئة بيانات الدخول.",
    "Reached the app, but the token is wrong. Copy it again from the app.": "تم الوصول إلى التطبيق، لكن الرمز خاطئ. انسخه مرة أخرى من التطبيق.",
    "Enter the pairing token first.": "أدخل رمز الاقتران أولًا.",
    "Couldn't reach MyVault. Make sure the app is open, then check the port.": "تعذّر الوصول إلى MyVault. تأكد أن التطبيق مفتوح، ثم تحقق من المنفذ.",
    "Saved. Testing…": "تم الحفظ. جارٍ الاختبار…",
    "MyVault: choose an account": "MyVault: اختر حسابًا",
    "MyVault: suggested password": "MyVault: كلمة مرور مقترحة",
    "Strong and random. MyVault offers to save it when you submit the form.": "قوية وعشوائية. سيعرض MyVault حفظها عند إرسال النموذج.",
    "Use this password": "استخدم كلمة المرور هذه",
    "Not now": "ليس الآن",
    "Save your new account": "هل تريد حفظ حسابك الجديد",
    "Save": "حفظ",
    "for {0} to MyVault?": "الخاص بـ {0} في MyVault؟",
    "Close": "إغلاق",
    "this login": "بيانات الدخول هذه",
    "Saved to MyVault.": "تم الحفظ في MyVault.",
    "Couldn't save. Is MyVault open and unlocked?": "تعذّر الحفظ. هل MyVault مفتوح وغير مقفل؟",
    "There's no filled-in password on this page to save.": "لا توجد كلمة مرور مكتوبة في هذه الصفحة لحفظها.",
    "Saved your new {0} account to MyVault.": "تم حفظ حسابك الجديد في {0} إلى MyVault.",
    "Saved.": "تم الحفظ.",
  };
  const on = String((globalThis.chrome && chrome.i18n && chrome.i18n.getUILanguage && chrome.i18n.getUILanguage()) || navigator.language || "")
    .toLowerCase().startsWith("ar");
  const norm = (x) => x.trim().replace(/\s+/g, " ");      // HTML text keeps its line breaks
  const patterns = Object.keys(AR).filter((k) => /\{\d\}/.test(k)).sort((a, b) => b.length - a.length).map((k) => [
    new RegExp("^" + k.split(/(\{\d\})/).map((p) => /^\{\d\}$/.test(p) ? "([\\s\\S]+?)" : p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("") + "$"),
    AR[k]]);
  function mvT(s) {
    if (!on || typeof s !== "string") return s;
    const core = norm(s);
    if (!core) return s;
    const wrap = (x) => s.match(/^\s*/)[0] + x + s.match(/\s*$/)[0];
    if (Object.hasOwn(AR, core)) return wrap(AR[core]);
    for (const [rx, out] of patterns) {
      const m = rx.exec(core);
      if (m) return wrap(out.replace(/\{(\d)\}/g, (_, n) => m[+n + 1]));
    }
    return s;
  }
  // Translate a static page (popup, settings): its text and labels, and set the direction.
  function mvPage() {
    if (!on) return;
    document.documentElement.lang = "ar";
    document.documentElement.dir = "rtl";
    document.title = mvT(document.title);
    const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n; (n = walk.nextNode());) n.textContent = mvT(n.textContent);
    for (const e of document.querySelectorAll("[title],[aria-label],[placeholder]")) {
      for (const a of ["title", "aria-label", "placeholder"]) if (e.hasAttribute(a)) e.setAttribute(a, mvT(e.getAttribute(a)));
    }
  }
  Object.assign(globalThis, { mvT, mvPage, mvRTL: on });
})();
