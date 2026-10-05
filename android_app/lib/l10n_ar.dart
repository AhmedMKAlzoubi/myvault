/// English -> Arabic for the phone app (see l10n.dart). Keep in step with the
/// PC's myvault/ui/ar.json: the same words for the same things.
library;

const arabic = <String, String>{
  // ---- unlock and lock ----
  'Locked after {t0} without use.': 'أُقفل بعد {t0} من عدم الاستخدام.',
  'Enter your master password.': 'أدخل كلمة المرور الرئيسية.',
  'Use at least 8 characters. A short sentence works well.':
      'استخدم 8 أحرف على الأقل. الجملة القصيرة خيار جيد.',
  "The two passwords don't match.": 'كلمتا المرور غير متطابقتين.',
  "That isn't the master password. Try again.":
      'هذه ليست كلمة المرور الرئيسية. حاول مرة أخرى.',
  'Your vault is sealed. Enter your master password to open it.':
      'خزنتك مختومة. أدخل كلمة المرور الرئيسية لفتحها.',
  "Choose the one password that opens your vault. It's the only one you'll need to remember.":
      'اختر كلمة المرور الوحيدة التي تفتح خزنتك. هي الوحيدة التي ستحتاج إلى تذكّرها.',
  'Master password': 'كلمة المرور الرئيسية',
  'Choose a master password': 'اختر كلمة مرور رئيسية',
  'Type it again': 'اكتبها مرة أخرى',
  "There's no reset. If this password is forgotten, nobody can open the vault, not even you. Write it down and keep it somewhere safe.":
      'لا توجد إعادة تعيين. إن نُسيت هذه الكلمة فلن يستطيع أحد فتح الخزنة، ولا أنت. اكتبها واحفظها في مكان آمن.',
  'Opening…': 'جارٍ الفتح…',
  'Creating…': 'جارٍ الإنشاء…',
  'Unlock': 'فتح',
  'Create my vault': 'أنشئ خزنتي',
  'Wrong master password.': 'كلمة المرور الرئيسية خاطئة.',
  'Wrong master password (or the file was altered).':
      'كلمة المرور الرئيسية خاطئة (أو أن الملف عُدّل).',
  'Unrecognized vault file.': 'ملف خزنة غير معروف.',
  'File is not valid MyVault data.': 'الملف لا يحوي بيانات MyVault صالحة.',
  'This is not a MyVault file.': 'هذا ليس ملفًا لـ MyVault.',
  'The vault file is corrupt or unreadable.':
      'ملف الخزنة تالف أو لا يمكن قراءته.',

  // ---- home ----
  'Saved 1 login from other apps.': 'تم حفظ تسجيل دخول واحد من تطبيقات أخرى.',
  'Saved {0} logins from other apps.':
      'تسجيلات الدخول المحفوظة من تطبيقات أخرى: {0}.',
  'What are you adding?': 'ماذا تريد أن تضيف؟',
  'Sync with PC': 'المزامنة مع الكمبيوتر',
  'Lock': 'قفل',
  'Password generator': 'مولّد كلمات المرور',
  'Restore from paper': 'الاستعادة من الورق',
  'Change master password': 'تغيير كلمة المرور الرئيسية',
  'Auto-lock': 'القفل التلقائي',
  'Autofill in other apps': 'التعبئة التلقائية في التطبيقات الأخرى',
  'Updates': 'التحديثات',
  'Language': 'اللغة',
  'About & privacy': 'حول التطبيق والخصوصية',
  'Lock now': 'اقفل الآن',
  'Search': 'بحث',
  'All': 'الكل',
  'New': 'جديد',
  'Your vault is empty': 'خزنتك فارغة',
  'Nothing matches “{0}”': 'لا شيء يطابق «{0}»',
  'Start with the account you use most. Logins, API keys, SSH keys and notes are all encrypted on this phone.':
      'ابدأ بالحساب الذي تستخدمه أكثر. تسجيلات الدخول ومفاتيح API ومفاتيح SSH والملاحظات كلها مشفّرة على هذا الهاتف.',
  'Try a shorter word, or check the type filter.':
      'جرّب كلمة أقصر، أو تحقق من تصفية النوع.',
  'Add your first entry': 'أضف أول عنصر',

  // ---- an entry ----
  'Hidden value': 'قيمة مخفية',
  'Copy {t0}': 'نسخ {t0}',
  'Copy': 'نسخ',
  '{t0} is empty.': '{t0} فارغ.',
  '{t0} copied. It clears from the clipboard in 30 s.':
      'تم نسخ {t0}. سيُمسح من الحافظة بعد 30 ثانية.',
  'Edit': 'تعديل',
  'Extra fields': 'حقول إضافية',
  'Nothing stored here yet. Tap Edit to add details.':
      'لا شيء محفوظ هنا بعد. اضغط «تعديل» لإضافة التفاصيل.',
  'Last changed {0} · Created {1}': 'آخر تعديل {0} · أُنشئ {1}',
  'Hide': 'إخفاء',
  'Show': 'إظهار',
  'Give it a name first.': 'أعطه اسمًا أولًا.',
  'Delete for good?': 'حذف نهائيًا؟',
  '“{0}” will be removed from this phone, and from your PC at the next sync.':
      'سيُحذف «{0}» من هذا الهاتف، ومن الكمبيوتر عند المزامنة القادمة.',
  'Keep it': 'أبقِه',
  'Delete': 'حذف',
  'Replace this password?': 'هل تريد استبدال كلمة المرور هذه؟',
  'Once you save, the old one is gone for good. Change it on the website or app as well, or you could lock yourself out.':
      'بعد الحفظ تختفي القديمة نهائيًا. غيّرها في الموقع أو التطبيق أيضًا، وإلا فقد لا تتمكن من الدخول إلى حسابك.',
  'The password in the box will be replaced.':
      'ستُستبدل كلمة المرور الموجودة في الخانة.',
  'Type a new one': 'اكتب كلمة جديدة',
  'Generate one': 'ولّد كلمة',
  'Paste': 'لصق',
  'The clipboard is empty. Copy the text again, then tap Paste.':
      'الحافظة فارغة. انسخ النص مرة أخرى، ثم اضغط «لصق».',
  'Generate': 'توليد',
  'Change password': 'تغيير كلمة المرور',
  'Keep the old password': 'أبقِ كلمة المرور القديمة',
  'New login': 'تسجيل دخول جديد',
  'New api key': 'مفتاح API جديد',
  'New ssh key': 'مفتاح SSH جديد',
  'New secure note': 'ملاحظة آمنة جديدة',
  'Name': 'الاسم',
  'Profile details': 'تفاصيل الملف الشخصي',
  'App, phone, region, age, gender': 'التطبيق، الهاتف، المنطقة، العمر، الجنس',
  'Notes': 'ملاحظات',
  'Add field': 'إضافة حقل',
  'Label': 'التسمية',
  'Value': 'القيمة',
  'Remove field': 'إزالة الحقل',
  'Save': 'حفظ',

  // ---- kinds and fields (kinds.dart) ----
  'Login': 'تسجيل دخول',
  'Logins': 'تسجيلات الدخول',
  'A website or app sign-in.': 'حساب في موقع أو تطبيق.',
  'Website': 'الموقع',
  'Username': 'اسم المستخدم',
  'Email': 'البريد الإلكتروني',
  'Password': 'كلمة المرور',
  'App name': 'اسم التطبيق',
  'Phone': 'الهاتف',
  'Region / country': 'المنطقة / البلد',
  'Age': 'العمر',
  'Gender': 'الجنس',
  'API key': 'مفتاح API',
  'API keys': 'مفاتيح API',
  'Client IDs, client secrets, API keys and tokens.':
      'معرّفات العملاء وأسرارهم ومفاتيح API والرموز.',
  'Service': 'الخدمة',
  'Endpoint / URL': 'نقطة الوصول / الرابط',
  'Client ID': 'معرّف العميل',
  'Client secret': 'سرّ العميل',
  'Access token': 'رمز الوصول',
  'SSH key': 'مفتاح SSH',
  'SSH keys': 'مفاتيح SSH',
  'A private key, its passphrase and the server it opens.':
      'مفتاح خاص وعبارة مروره والخادم الذي يفتحه.',
  'Host': 'الخادم',
  'Port': 'المنفذ',
  'User': 'المستخدم',
  'Private key': 'المفتاح الخاص',
  'Passphrase': 'عبارة المرور',
  'Public key': 'المفتاح العام',
  'Fingerprint': 'البصمة',
  'Secure note': 'ملاحظة آمنة',
  'Secure notes': 'ملاحظات آمنة',
  'Recovery codes, PINs, anything private.':
      'رموز الاسترداد، أرقام PIN، وأي شيء خاص.',
  'Note': 'ملاحظة',

  // ---- generator ----
  'Weak': 'ضعيفة',
  'Okay': 'مقبولة',
  'Strong': 'قوية',
  'Very strong': 'قوية جدًا',
  'Strength: {t0}': 'القوة: {t0}',
  'Turn on at least one kind of character.':
      'فعّل نوعًا واحدًا من الأحرف على الأقل.',
  'Enable at least one character type.':
      'فعّل نوعًا واحدًا من الأحرف على الأقل.',
  'New password': 'كلمة مرور جديدة',
  'Length': 'الطول',
  'Uppercase letters': 'أحرف كبيرة',
  'Lowercase letters': 'أحرف صغيرة',
  'Numbers': 'أرقام',
  'Symbols': 'رموز',
  'Avoid look-alikes': 'تجنّب الأحرف المتشابهة',
  'No l, 1, O, 0, I': 'بدون l و1 وO و0 وI',
  'Use this password': 'استخدم كلمة المرور هذه',
  "Random, from this phone's secure random source. Nothing is saved unless you copy it.":
      'عشوائية، من مصدر العشوائية الآمن في هذا الهاتف. لا يُحفظ شيء ما لم تنسخها.',

  // ---- sync ----
  'Looking for a code…': 'جارٍ البحث عن رمز…',
  "MyVault can't use the camera ({0}). Allow camera access for MyVault in Android settings › Apps › MyVault › Permissions, then try again.":
      'لا يستطيع MyVault استخدام الكاميرا ({0}). اسمح لـ MyVault بالوصول إلى الكاميرا من إعدادات Android › التطبيقات › MyVault › الأذونات، ثم حاول مرة أخرى.',
  'Synced. 1 entry updated on this phone. Your PC has the rest.':
      'تمت المزامنة. تحدّث عنصر واحد على هذا الهاتف، والباقي على الكمبيوتر.',
  'Synced. 1 entry updated on this phone. Your PC has the rest.{0}':
      'تمت المزامنة. تحدّث عنصر واحد على هذا الهاتف، والباقي على الكمبيوتر.{0}',
  'Synced. {0} entries updated on this phone. Your PC has the rest.':
      'تمت المزامنة. العناصر التي تحدّثت على هذا الهاتف: {0}. والباقي على الكمبيوتر.',
  'Synced. {0} entries updated on this phone. Your PC has the rest.{1}':
      'تمت المزامنة. العناصر التي تحدّثت على هذا الهاتف: {0}. والباقي على الكمبيوتر.{1}',
  'Your PC has MyVault {0} and passed the update to this phone.':
      'على الكمبيوتر MyVault {0}، وقد نقل التحديث إلى هذا الهاتف.',
  'Your PC runs an older MyVault (before 0.5). Update it with the new installer; after that, updates pass between your devices when you sync.':
      'الكمبيوتر يعمل بإصدار أقدم من MyVault (قبل 0.5). حدّثه بالمثبّت الجديد؛ وبعدها تنتقل التحديثات بين أجهزتك عند المزامنة.',
  'Your PC had MyVault {0}, so this phone passed it the {1} update. Install it from the card in the PC app.':
      'كان على الكمبيوتر MyVault {0}، فنقل له هذا الهاتف تحديث {1}. ثبّته من البطاقة في تطبيق الكمبيوتر.',
  'Your PC has MyVault {0} (this phone has {1}).{t2}':
      'على الكمبيوتر MyVault {0} (وعلى هذا الهاتف {1}).{t2}',
  'Update this phone from Updates in the menu.':
      'حدّث هذا الهاتف من «التحديثات» في القائمة.',
  "The update couldn't be passed over: {0}": 'تعذّر نقل التحديث: {0}',
  'Your PC runs MyVault {0} (this phone has {1}). Update the PC when you can.':
      'الكمبيوتر يعمل بـ MyVault {0} (وهذا الهاتف بـ {1}). حدّث الكمبيوتر عندما تستطيع.',
  'Scan the code on your PC': 'امسح الرمز على الكمبيوتر',
  'On your PC, open MyVault → Sync with phone → Show sync code. Hold the phone 15–30 cm from the screen.':
      'على الكمبيوتر افتح MyVault ← المزامنة مع الهاتف ← اعرض رمز المزامنة. أمسك الهاتف على بعد 15–30 سم من الشاشة.',
  "That QR code isn't a MyVault sync code. Point at the code in MyVault's Sync with phone screen.":
      'رمز QR هذا ليس رمز مزامنة لـ MyVault. وجّه الكاميرا إلى الرمز في شاشة «المزامنة مع الهاتف» في MyVault.',
  'Your phone and PC swap changes directly over your WiFi. No cloud is involved.':
      'يتبادل الهاتف والكمبيوتر التغييرات مباشرة عبر شبكة Wi‑Fi لديك. لا توجد أي سحابة.',
  '1. On the PC, open MyVault and choose Sync with phone.\n2. Choose Show sync code.\n3. Tap Scan below and point the camera at it.':
      '1. على الكمبيوتر افتح MyVault واختر «المزامنة مع الهاتف».\n2. اختر «اعرض رمز المزامنة».\n3. اضغط «مسح» أدناه ووجّه الكاميرا إليه.',
  'Syncing with your PC…': 'جارٍ المزامنة مع الكمبيوتر…',
  'Scan sync code': 'امسح رمز المزامنة',
  'Scan again': 'امسح مرة أخرى',
  'The code is the key.': 'الرمز هو المفتاح.',
  'It holds a one-time random key that only travels through the camera, so nobody else on the WiFi can read the sync.':
      'يحمل مفتاحًا عشوائيًا لمرة واحدة لا ينتقل إلا عبر الكاميرا، فلا يستطيع أي أحد آخر على الشبكة قراءة المزامنة.',
  'Same WiFi only.': 'على الشبكة نفسها فقط.',
  'The PC stops listening after one sync, or after 2 minutes.':
      'يتوقف الكمبيوتر عن الاستقبال بعد مزامنة واحدة، أو بعد دقيقتين.',
  "That isn't a MyVault sync code.": 'هذا ليس رمز مزامنة لـ MyVault.',
  'Bad key in sync code.': 'مفتاح غير صالح في رمز المزامنة.',
  "That code doesn't point at a PC on your home network, so MyVault won't sync with it.":
      'هذا الرمز لا يشير إلى كمبيوتر على شبكة منزلك، لذا لن يتزامن MyVault معه.',

  // ---- paper restore ----
  "That code isn't from a MyVault backup.":
      'هذا الرمز ليس من نسخة احتياطية لـ MyVault.',
  'Checking the backup password… (slow on purpose)':
      'جارٍ التحقق من كلمة مرور النسخة الاحتياطية… (بطيء عن قصد)',
  'Read {0}. Keep scanning, or tap Done.':
      'المقروء: {0}. تابع المسح، أو اضغط «تم».',
  "That backup password doesn't open this sheet.":
      'كلمة مرور النسخة الاحتياطية هذه لا تفتح هذه الورقة.',
  "Couldn't read that code. Try holding the phone steadier.":
      'تعذّرت قراءة هذا الرمز. حاول تثبيت الهاتف أكثر.',
  'Read 1 entry. All were already in your vault.':
      'قُرئ عنصر واحد، وهو موجود في خزنتك أصلًا.',
  'Read {0} entries. All were already in your vault.':
      'العناصر المقروءة: {0}، وكلها موجودة في خزنتك أصلًا.',
  'Read 1 entry. {0} restored or updated.':
      'قُرئ عنصر واحد. المستعاد أو المحدَّث: {0}.',
  'Read {0} entries. {1} restored or updated.':
      'العناصر المقروءة: {0}. المستعادة أو المحدَّثة: {1}.',
  'Scanning: {0} read': 'جارٍ المسح: المقروء {0}',
  'Point the camera at each code on the backup sheet, one at a time.':
      'وجّه الكاميرا إلى كل رمز على ورقة النسخة الاحتياطية، واحدًا تلو الآخر.',
  'Done: restore {0}': 'تم: استعادة {0}',
  'Bring back entries from a printed MyVault backup. Each code on the sheet is one encrypted entry; restored entries are merged into this vault, keeping the newer version of anything you already have.':
      'أعِد العناصر من نسخة احتياطية مطبوعة لـ MyVault. كل رمز على الورقة عنصر مشفّر واحد؛ وتُدمج العناصر المستعادة في هذه الخزنة مع الإبقاء على النسخة الأحدث مما لديك أصلًا.',
  'Backup password': 'كلمة مرور النسخة الاحتياطية',
  'Enter the backup password first.': 'أدخل كلمة مرور النسخة الاحتياطية أولًا.',
  'Start scanning': 'ابدأ المسح',

  // ---- master password ----
  'The current master password is wrong.':
      'كلمة المرور الرئيسية الحالية خاطئة.',
  'Use at least 8 characters.': 'استخدم 8 أحرف على الأقل.',
  "The new passwords don't match.": 'كلمتا المرور الجديدتان غير متطابقتين.',
  'Master password changed.': 'تم تغيير كلمة المرور الرئيسية.',
  'Current master password': 'كلمة المرور الرئيسية الحالية',
  'New master password': 'كلمة المرور الرئيسية الجديدة',
  'Your PC keeps its own master password. Sync still works if they differ.':
      'يحتفظ الكمبيوتر بكلمة مروره الرئيسية الخاصة. تعمل المزامنة حتى لو اختلفتا.',

  // ---- auto-lock ----
  '1 minute': 'دقيقة واحدة',
  '2 minutes': 'دقيقتان',
  '5 minutes': '5 دقائق',
  '10 minutes': '10 دقائق',
  '{0} minutes': '{0} دقيقة',
  '1 hour': 'ساعة واحدة',
  'Immediately': 'فورًا',
  'After {0} seconds': 'بعد {0} ثانية',
  'After 1 minute': 'بعد دقيقة واحدة',
  'After 5 minutes': 'بعد 5 دقائق',
  'After {0} minutes': 'بعد {0} دقيقة',
  "Lock when I haven't used MyVault for": 'اقفل عندما لا أستخدم MyVault لمدة',
  'Lock after I switch to another app': 'اقفل بعد انتقالي إلى تطبيق آخر',
  'Shorter is safer. "Immediately" also locks when you briefly switch apps to copy something.':
      'المدة الأقصر أكثر أمانًا. خيار «فورًا» يقفل أيضًا حين تنتقل إلى تطبيق آخر لحظة لنسخ شيء.',

  // ---- language ----
  'Same as this phone': 'مثل لغة هذا الهاتف',

  // ---- updates ----
  'Check for updates online?': 'هل تريد البحث عن التحديثات عبر الإنترنت؟',
  'New versions of MyVault come out every now and then. To find out when, MyVault can look at a small version file on GitHub (at most once a day). Nothing from your vault is sent. You can change this later under Updates.':
      'تصدر نسخ جديدة من MyVault بين حين وآخر. لمعرفة ذلك يستطيع MyVault الاطلاع على ملف إصدار صغير على GitHub (مرة واحدة في اليوم على الأكثر). لا يُرسَل أي شيء من خزنتك. يمكنك تغيير هذا لاحقًا من «التحديثات».',
  'No thanks': 'لا، شكرًا',
  'Yes, let me know': 'نعم، أخبرني',
  'MyVault {0} is available': 'MyVault {0} متاح',
  'MyVault {0} is the newest version.': 'MyVault {0} هو أحدث إصدار.',
  'You have {0}. Updating keeps your vault exactly as it is.\n\nDownloads {1}: the phone update, plus the PC update so you can pass it to your PC the next time you sync. Best on WiFi.':
      'لديك الإصدار {0}. التحديث يُبقي خزنتك كما هي تمامًا.\n\nحجم التنزيل {1}: تحديث الهاتف، وتحديث الكمبيوتر لتنقله إليه في المزامنة القادمة. الأفضل عبر Wi‑Fi.',
  'Later': 'لاحقًا',
  'Update now': 'حدّث الآن',
  "Couldn't check for updates: {0}": 'تعذّر البحث عن التحديثات: {0}',
  'Downloading the update': 'جارٍ تنزيل التحديث',
  'Starting…': 'جارٍ البدء…',
  'The download failed: {0}': 'فشل التنزيل: {0}',
  'Install MyVault {0}?': 'هل تريد تثبيت MyVault {0}؟',
  'You have {0}. Your vault stays exactly as it is. Android will show its install screen; MyVault closes while it updates.':
      'لديك الإصدار {0}. ستبقى خزنتك كما هي تمامًا. سيعرض Android شاشة التثبيت، ويُغلق MyVault أثناء التحديث.',
  '{0}You have {1}. Your vault stays exactly as it is. Android will show its install screen; MyVault closes while it updates.':
      '{0}لديك الإصدار {1}. ستبقى خزنتك كما هي تمامًا. سيعرض Android شاشة التثبيت، ويُغلق MyVault أثناء التحديث.',
  'Install': 'تثبيت',
  'Allow "Install unknown apps" for MyVault, then come back and tap Install again.':
      'اسمح بـ «تثبيت تطبيقات غير معروفة» لـ MyVault، ثم عُد واضغط «تثبيت» مرة أخرى.',
  'This is MyVault {0}.': 'هذا MyVault {0}.',
  'Updates also arrive offline: when you sync, a newer PC hands its phone update over.':
      'تصل التحديثات دون إنترنت أيضًا: عند المزامنة يسلّم الكمبيوتر الأحدث تحديث الهاتف.',
  'Let me know when a new version is out': 'أخبرني عند صدور نسخة جديدة',
  'MyVault looks at a small version file on GitHub, at most once a day. Nothing from your vault is sent.':
      'يطّلع MyVault على ملف إصدار صغير على GitHub مرة واحدة في اليوم على الأكثر. لا يُرسَل أي شيء من خزنتك.',
  'Last checked: {0}': 'آخر فحص: {0}',
  'never': 'أبدًا',
  'Install MyVault {0}': 'ثبّت MyVault {0}',
  'Checking…': 'جارٍ الفحص…',
  'Check now': 'افحص الآن',
  'Go back to the previous version': 'العودة إلى الإصدار السابق',
  "Android doesn't let an app install an older version of itself over a newer one. Going back means removing MyVault, which also removes its copy of your vault, so:\n\n1. Sync with your PC first, so the PC has everything.\n2. Uninstall MyVault on this phone.\n3. Install the older MyVault APK from the releases page.\n4. Create a master password, then sync with your PC again.":
      'لا يسمح Android لتطبيق بتثبيت إصدار أقدم منه فوق إصدار أحدث. العودة تعني إزالة MyVault، وهذا يزيل نسخته من خزنتك أيضًا، لذا:\n\n1. زامِن مع الكمبيوتر أولًا ليكون لديه كل شيء.\n2. أزل تثبيت MyVault من هذا الهاتف.\n3. ثبّت ملف APK الأقدم لـ MyVault من صفحة الإصدارات.\n4. أنشئ كلمة مرور رئيسية، ثم زامِن مع الكمبيوتر مرة أخرى.',
  'Open the releases page': 'افتح صفحة الإصدارات',
  'This update isn\'t signed by MyVault\'s update key.':
      'هذا التحديث غير موقّع بمفتاح تحديثات MyVault.',
  "That isn't a MyVault release manifest.": 'هذا ليس بيان إصدار لـ MyVault.',
  'Bad file entry in the manifest.': 'مُدخل ملف غير صالح في البيان.',
  "The manifest doesn't list that package.": 'البيان لا يذكر هذه الحزمة.',
  "The update file is damaged (its fingerprint doesn't match).":
      'ملف التحديث تالف (بصمته غير مطابقة).',
  'No release has been published yet.': 'لم يُنشر أي إصدار بعد.',
  'GitHub answered {0}.': 'ردّ GitHub بالرمز {0}.',
  'Unexpectedly large download.': 'تنزيل أكبر من المتوقع.',
  "Couldn't reach GitHub. Check your internet connection.":
      'تعذّر الوصول إلى GitHub. تحقق من اتصالك بالإنترنت.',
  'This release has no {0} package.': 'هذا الإصدار لا يحوي حزمة {0}.',
  "That update can't be installed.": 'لا يمكن تثبيت هذا التحديث.',

  // ---- about ----
  'About MyVault': 'حول MyVault',
  'MyVault {0}\n\nMade by Ahmed Mohammed. Free software under the GPL-3.0 licence. Your vault stays on your devices: no account, no cloud, no tracking.':
      'MyVault {0}\n\nمن صنع أحمد محمد. برنامج حر بموجب رخصة GPL-3.0. تبقى خزنتك على أجهزتك: بلا حساب ولا سحابة ولا تتبّع.',
  'Privacy policy': 'سياسة الخصوصية',
  'Terms of use': 'شروط الاستخدام',
  'Security & reporting a problem': 'الأمان والإبلاغ عن مشكلة',
  "What's new": 'ما الجديد',
  'Contact: ahmedmohammedkhear@gmail.com':
      'للتواصل: ahmedmohammedkhear@gmail.com',

  // ---- autofill ----
  'Fill {0}': 'تعبئة {0}',
  'Search your logins': 'ابحث في تسجيلات الدخول',
  'Saved for {0}': 'المحفوظ لـ {0}',
  'Nothing saved for {0} yet. Pick a login:':
      'لا شيء محفوظ لـ {0} بعد. اختر تسجيل دخول:',
  'Other logins': 'تسجيلات دخول أخرى',
  'No logins match that search.': 'لا توجد تسجيلات دخول تطابق هذا البحث.',
  'MyVault is your autofill service.':
      'MyVault هو خدمة التعبئة التلقائية لديك.',
  'MyVault is not your autofill service yet.':
      'MyVault ليس خدمة التعبئة التلقائية لديك بعد.',
  'With this on, MyVault can fill and save logins in other apps and in Chrome:\n\n• Tap a login box, then "Fill with MyVault". MyVault asks for your master password, then you pick the account.\n• When you sign in or sign up somewhere new, Android asks "Save to MyVault?". Saved logins are kept encrypted on this phone and added to your vault the next time you unlock.':
      'عند تفعيل هذا يستطيع MyVault تعبئة بيانات الدخول وحفظها في التطبيقات الأخرى وفي Chrome:\n\n• اضغط خانة الدخول ثم «التعبئة بـ MyVault». يطلب MyVault كلمة المرور الرئيسية، ثم تختار الحساب.\n• عند تسجيل الدخول أو التسجيل في مكان جديد يسألك Android «الحفظ في MyVault؟». تُحفظ بيانات الدخول مشفّرة على هذا الهاتف وتُضاف إلى خزنتك عند الفتح التالي.',
  'Change autofill service': 'تغيير خدمة التعبئة التلقائية',
  'Turn on': 'تفعيل',
  'In Chrome, also open Chrome › Settings › Autofill services and choose "Autofill using another service".':
      'في Chrome افتح أيضًا Chrome › الإعدادات › خدمات الملء التلقائي واختر «الملء التلقائي باستخدام خدمة أخرى».',
  "This phone's Android version doesn't support autofill services.":
      'إصدار Android على هذا الهاتف لا يدعم خدمات التعبئة التلقائية.',
  // ---- documents ----
  'Document': 'مستند',
  'Documents': 'المستندات',
  'New document': 'مستند جديد',
  'Passport, ID, visa, licence or contract, with a reminder before it expires.':
      'جواز سفر أو هوية أو تأشيرة أو رخصة أو عقد، مع تذكير قبل انتهائه.',
  'Type': 'النوع',
  'Name on the document': 'الاسم على المستند',
  'Document number': 'رقم المستند',
  'Issued by': 'جهة الإصدار',
  'Issue date': 'تاريخ الإصدار',
  'Expiry date': 'تاريخ الانتهاء',
  'Clear': 'مسح',
  'Cancel': 'إلغاء',
  'Choose a type': 'اختر النوع',
  'Passport': 'جواز السفر',
  'ID card': 'بطاقة الهوية',
  'Residence permit': 'تصريح الإقامة',
  'Visa': 'التأشيرة',
  'Driving licence': 'رخصة القيادة',
  'Car registration': 'ترخيص المركبة',
  'Rental contract': 'عقد الإيجار',
  'Insurance': 'التأمين',
  '1 day': 'يوم واحد',
  '2 days': 'يومين',
  '3 days': '3 أيام',
  '10 days': '10 أيام',
  '1 week': 'أسبوع واحد',
  '2 weeks': 'أسبوعين',
  '1 month': 'شهر واحد',
  '2 months': 'شهرين',
  '3 months': '3 أشهر',
  '6 months': '6 أشهر',
  '1 year': 'سنة واحدة',
  '{0} days': '{0} يومًا',
  'Expired {0}': 'انتهى في {0}',
  'Expires today': 'ينتهي اليوم',
  'Expires {0}': 'ينتهي في {0}',
  '{0} expires in {t1}.': 'موعد انتهاء {0} بعد {t1}.',
  '{0} expires today.': 'اليوم موعد انتهاء {0}.',
  'Reminders': 'التذكيرات',
  'Add the expiry date to get reminders.':
      'أضف تاريخ الانتهاء لتصلك التذكيرات.',
  'No reminders set. Tap Edit to add some.':
      'لا توجد تذكيرات. اضغط «تعديل» لإضافتها.',
  ',': '،',
  'before it expires, and on the day.': 'قبل انتهائه، وفي يوم الانتهاء نفسه.',
  'A notification will say:': 'سيقول الإشعار:',
  'Files': 'الملفات',
  'Save an unprotected copy?': 'هل تريد حفظ نسخة غير محمية؟',
  'The copy isn\'t encrypted: any app or person that can open where you save it can see it.':
      'النسخة غير مشفّرة: يستطيع رؤيتها أي تطبيق أو شخص يستطيع فتح المكان الذي تحفظها فيه.',
  'Save a copy': 'حفظ نسخة',
  'Saved.': 'تم الحفظ.',
  'Reading the document…': 'جارٍ قراءة المستند…',
  'Couldn\'t find new details in this file. Type them in instead.':
      'لم أجد تفاصيل جديدة في هذا الملف. اكتبها بنفسك.',
  'Read from the machine-readable zone (the <<< lines) and checked.':
      'قُرئت من المنطقة المقروءة آليًا (أسطر <<<) وتم التحقق منها.',
  'Read from the document\'s text.': 'قُرئت من نص المستند.',
  'Filled in: {0}.': 'تمت تعبئة: {0}.',
  'The expiry date is a guess (it wasn\'t labelled).':
      'تاريخ الانتهاء تخمين (لم يكن موسومًا).',
  'Check the details before saving.': 'تحقق من التفاصيل قبل الحفظ.',
  'That file couldn\'t be opened.': 'تعذّر فتح هذا الملف.',
  'That file couldn\'t be read.': 'تعذّرت قراءة هذا الملف.',
  'That PDF couldn\'t be shown.': 'تعذّر عرض ملف PDF هذا.',
  'Your phone has no app for that.': 'لا يوجد على هاتفك تطبيق لذلك.',
  'Photos or PDFs of the document. They\'re encrypted the moment you add them. MyVault can read the details from them, on this phone.':
      'صور المستند أو ملفات PDF له. تُشفَّر لحظة إضافتها. ويستطيع MyVault قراءة التفاصيل منها على هذا الهاتف.',
  'Read details': 'قراءة التفاصيل',
  'Remove file': 'إزالة الملف',
  'Take a photo': 'التقاط صورة',
  'Choose files': 'اختيار ملفات',
  'Remind me before it expires': 'ذكّرني قبل انتهائه',
  'Days': 'أيام',
  'Add days': 'إضافة أيام',
  'Choose as many as you like. You\'re also reminded on the day it expires.':
      'اختر ما تشاء منها. وستُذكَّر أيضًا في يوم الانتهاء.',
  'Name in reminders': 'الاسم في التذكيرات',
  'Keep numbers and private details out: notifications can be seen on a locked screen.':
      'لا تكتب فيه أرقامًا أو تفاصيل خاصة: يمكن رؤية الإشعارات على الشاشة المقفلة.',
  'Expiring soon': 'ينتهي قريبًا',
  'Sync document files with your PC': 'مزامنة ملفات المستندات مع الكمبيوتر',
  'Photos and PDFs travel encrypted over your WiFi when you sync. Turn off to keep them on this phone only; names, numbers and dates always sync.':
      'تنتقل الصور وملفات PDF مشفّرة عبر شبكة Wi‑Fi لديك عند المزامنة. أوقف هذا الخيار لتبقيها على هذا الهاتف فقط؛ أما الأسماء والأرقام والتواريخ فتتزامن دائمًا.',
  'Reminders can notify you.': 'يمكن للتذكيرات أن تُرسل إليك إشعارات.',
  'Notifications are off for MyVault, so reminders can\'t show.':
      'الإشعارات متوقفة لـ MyVault، فلا يمكن عرض التذكيرات.',
  'Each reminder says only the document type, or the name you chose, and the time left.':
      'لا يذكر كل تذكير إلا نوع المستند، أو الاسم الذي اخترته، والوقت المتبقي.',
  'Allow notifications': 'السماح بالإشعارات',
  'Document files received: {0}.': 'ملفات المستندات المستلمة: {0}.',
  'Document files couldn\'t be synced: {0}':
      'تعذّرت مزامنة ملفات المستندات: {0}',
  'That file is over 20 MB.': 'حجم هذا الملف أكبر من 20 ميغابايت.',
  'Only photos (JPG, PNG, WebP) and PDFs can be added.':
      'يمكن إضافة الصور (JPG وPNG وWebP) وملفات PDF فقط.',
  'That file isn\'t on this device yet. Sync with the device that has it.':
      'هذا الملف ليس على هذا الجهاز بعد. زامِن مع الجهاز الذي يحويه.',
  'That file is damaged.': 'هذا الملف تالف.',
  // ---- document fields and scanning ----
  'Date of birth': 'تاريخ الميلاد',
  'Place of birth': 'مكان الولادة',
  'Sex': 'الجنس',
  'Address': 'العنوان',
  'Nationality': 'الجنسية',
  'Licence class': 'فئة الرخصة',
  'Visa type': 'نوع التأشيرة',
  'Sponsor or employer': 'الكفيل أو صاحب العمل',
  'Plate number': 'رقم اللوحة',
  'Make and model': 'الصنع والطراز',
  'Chassis number (VIN)': 'رقم الشاصي (VIN)',
  'Landlord': 'المؤجر',
  'Rent': 'الأجرة',
  'Insurer': 'شركة التأمين',
  'Owner': 'المالك',
  'Registration number': 'رقم التسجيل',
  'Tenant': 'المستأجر',
  'Contract number': 'رقم العقد',
  'Start date': 'تاريخ البدء',
  'End date': 'تاريخ الانتهاء',
  'Insured': 'المؤمَّن عليه',
  'Policy number': 'رقم الوثيقة',
  'Add a photo or PDF of the document first.':
      'أضف صورة أو ملف PDF للمستند أولًا.',
  'Send a test notification': 'إرسال إشعار تجريبي',
  'This is how a document reminder looks.': 'هكذا يبدو تذكير المستند.',
  'Couldn\'t find new details in these files. Type them in instead.':
      'لم أجد تفاصيل جديدة في هذه الملفات. اكتبها بنفسك.',
  'Scan document': 'مسح المستند ضوئيًا',
  'Scan both sides of a card. The scanner finds the edges for you; drag the corners to adjust. Files are encrypted the moment you add them, and MyVault reads the details from all of them together, on this phone.':
      'امسح وجهي البطاقة. يجد الماسح الحواف تلقائيًا، ويمكنك سحب الزوايا لضبطها. تُشفَّر الملفات لحظة إضافتها، ويقرأ MyVault التفاصيل منها كلها معًا على هذا الهاتف.',
  'The document scanner isn\'t available.': 'الماسح الضوئي للمستندات غير متاح.',
  // ---- document checks and choices ----
  'Choose…': 'اختر…',
  'Male': 'ذكر',
  'Female': 'أنثى',
  'Card number': 'رقم البطاقة',
  'ID number': 'الرقم الوطني',
  'Scans can be misread: check every highlighted box against the document before saving.':
      'قد تُقرأ المسوحات بشكل خاطئ: طابق كل خانة مميَّزة مع المستند قبل الحفظ.',
  'From the scan: check it': 'من المسح: تحقّق منها',
  'Use the camera': 'استخدام الكاميرا',
  'Too dark? Tap the scanner\'s flash button. Photo too bright or shiny? Pick “No filter” after scanning, tilt the card away from the light, or use the camera instead.':
      'الصورة معتمة؟ اضغط زر الفلاش في الماسح. الصورة ساطعة أو لامعة؟ اختر «بلا فلتر» بعد المسح، أو أمِل البطاقة بعيدًا عن الضوء، أو استخدم الكاميرا بدلًا منه.',
  // ---- 2FA, password health, fingerprint, chip ----
  '2FA secret': 'مفتاح التحقق بخطوتين',
  '2FA code': 'رمز التحقق بخطوتين',
  'Copy 2FA code': 'نسخ رمز التحقق بخطوتين',
  'Previous passwords ({0})': 'كلمات المرور السابقة ({0})',
  'Until {0}': 'حتى {0}',
  'Only time-based codes (TOTP) are supported.':
      'الرموز المعتمدة على الوقت (TOTP) فقط مدعومة.',
  'That 2FA link isn\'t valid.': 'رابط التحقق بخطوتين هذا غير صالح.',
  'That isn\'t a 2FA secret. Paste the setup key or the otpauth:// link.':
      'هذا ليس مفتاح تحقق بخطوتين. الصق مفتاح الإعداد أو رابط otpauth://.',
  'Once you save, the old one moves to Previous passwords. Change it on the website or app as well, or you can\'t sign in.':
      'بعد الحفظ تنتقل كلمة المرور القديمة إلى «كلمات المرور السابقة». غيّرها في الموقع أو التطبيق أيضًا، وإلا فلن تتمكن من تسجيل الدخول.',
  'Password health': 'صحة كلمات المرور',
  'No logins with a password yet.': 'لا توجد تسجيلات دخول بكلمة مرور بعد.',
  'All {0} passwords look good: none is weak or reused.':
      'كلمات المرور كلها ({0}) جيدة: لا توجد كلمة ضعيفة أو مكررة.',
  '{0} logins checked: {1} weak, {2} reused.':
      'فُحص {0} من تسجيلات الدخول: {1} ضعيفة، {2} مكررة.',
  'Weak passwords': 'كلمات مرور ضعيفة',
  'Short or simple, so they\'re easy to guess. Change each on its site, then here: Edit › Change password › Generate one.':
      'قصيرة أو بسيطة، فيسهل تخمينها. غيّر كل واحدة في موقعها ثم هنا: تعديل › تغيير كلمة المرور › إنشاء واحدة.',
  'Reused passwords': 'كلمات مرور مكررة',
  'If one of these sites leaks its passwords, the same password opens the others. Give each site its own.':
      'إذا سُرّبت كلمات المرور من أحد هذه المواقع، فستفتح كلمة المرور نفسها المواقع الأخرى. اجعل لكل موقع كلمة مرور خاصة به.',
  'Same password, group {0}': 'كلمة المرور نفسها، المجموعة {0}',
  'Leaked passwords': 'كلمات مرور مسرّبة',
  'Check whether any of your passwords appears in known data leaks, using Have I Been Pwned (haveibeenpwned.com).':
      'تحقّق مما إذا كانت أي من كلمات مرورك موجودة في تسريبات بيانات معروفة، باستخدام خدمة Have I Been Pwned ‏(haveibeenpwned.com).',
  'Check for leaked passwords': 'البحث عن كلمات مرور مسرّبة',
  'Found in known leaks: {0} of {1} passwords. Change these first, on the site and then here.':
      'موجودة في تسريبات معروفة: {0} من {1} كلمة مرور. غيّر هذه أولًا، في الموقع ثم هنا.',
  'Checked {0} passwords: none of them is in a known leak.':
      'فُحصت {0} كلمة مرور: لا توجد أي منها في تسريب معروف.',
  'Seen in leaks {0} times': 'ظهرت في التسريبات {0} مرة',
  'Couldn\'t reach the leak check service. Check your internet connection.':
      'تعذّر الوصول إلى خدمة فحص التسريبات. تحقّق من اتصالك بالإنترنت.',
  'Photos or PDFs that belong with this entry. They\'re encrypted the moment you add them.':
      'صور أو ملفات PDF تخص هذا العنصر. تُشفَّر لحظة إضافتها.',
  'Only the first 5 characters of a scrambled copy (SHA-1 hash) of each password are sent, never the password itself, and the match is made on this phone. Nothing is checked until you choose to.':
      'تُرسل أول 5 أحرف فقط من نسخة مُبعثرة (بصمة SHA-1) لكل كلمة مرور، وليس كلمة المرور نفسها أبدًا، وتتم المطابقة على هذا الهاتف. لا يُفحص شيء حتى تختار ذلك.',
  'Scan the QR code': 'مسح رمز QR',
  'Point the camera at the QR code the site shows when you turn on two-factor sign-in.':
      'وجّه الكاميرا إلى رمز QR الذي يعرضه الموقع عند تفعيل تسجيل الدخول بخطوتين.',
  'That QR code isn\'t a 2FA setup code.':
      'رمز QR هذا ليس رمز إعداد للتحقق بخطوتين.',
  '2FA secret added. Save to keep it.':
      'أُضيف مفتاح التحقق بخطوتين. احفظ للاحتفاظ به.',
  'Use the password': 'استخدام كلمة المرور',
  'Turn on fingerprint unlock': 'تفعيل الفتح بالبصمة',
  'Unlock MyVault': 'فتح MyVault',
  'This phone\'s fingerprints changed, so enter your master password once. Then turn fingerprint unlock on again in the menu › Auto-lock.':
      'تغيّرت بصمات هذا الهاتف، فأدخل كلمة مرورك الرئيسية مرة واحدة. ثم فعّل الفتح بالبصمة من جديد من القائمة › القفل التلقائي.',
  'Unlock with your fingerprint?': 'الفتح ببصمتك؟',
  'Next time, open MyVault with your fingerprint or face instead of typing the master password. Your password stays encrypted on this phone, and you can turn this off in the menu › Auto-lock.':
      'في المرة القادمة، افتح MyVault ببصمتك أو وجهك بدلًا من كتابة كلمة المرور الرئيسية. تبقى كلمة مرورك مشفّرة على هذا الهاتف، ويمكنك إيقاف ذلك من القائمة › القفل التلقائي.',
  'Not now': 'ليس الآن',
  'Use fingerprint': 'استخدام البصمة',
  'Unlock with fingerprint or face': 'الفتح بالبصمة أو الوجه',
  'Your master password is kept encrypted on this phone by a key that only your fingerprint or face opens. If fingerprints are added or removed, you\'ll type the password once more.':
      'تُحفظ كلمة مرورك الرئيسية مشفّرة على هذا الهاتف بمفتاح لا تفتحه إلا بصمتك أو وجهك. إذا أُضيفت بصمات أو أُزيلت، فستكتب كلمة المرور مرة أخرى.',
  'Turn on NFC': 'تشغيل NFC',
  'NFC is off. Turn it on in Android\'s settings, then come back.':
      'NFC متوقف. شغّله من إعدادات Android ثم عُد.',
  'Open settings': 'فتح الإعدادات',
  'Read the chip': 'قراءة الشريحة',
  'Passports and many ID cards have a chip with the same details as the <<< lines, exact. It opens only with the document\'s number, date of birth and expiry date, so scan the document or type those first.':
      'في جوازات السفر وكثير من بطاقات الهوية شريحة فيها التفاصيل نفسها الموجودة في أسطر <<<، بدقة تامة. لا تُفتح إلا برقم المستند وتاريخ الميلاد وتاريخ الانتهاء، فامسح المستند أو اكتبها أولًا.',
  'Card access number (optional)': 'رقم الوصول إلى البطاقة (اختياري)',
  'The 6 digits printed on the front of some ID cards.':
      'الأرقام الستة المطبوعة على وجه بعض بطاقات الهوية.',
  'Start': 'ابدأ',
  'First scan the document, or type its number, date of birth and expiry date: the chip only opens with them.':
      'امسح المستند أولًا، أو اكتب رقمه وتاريخ الميلاد وتاريخ الانتهاء: لا تُفتح الشريحة إلا بها.',
  'Hold the phone flat against the document now and keep it still. Passport: the photo page or the cover. ID card: the middle of the card.':
      'ضع الهاتف الآن مسطّحًا على المستند وأبقِه ثابتًا. جواز السفر: صفحة الصورة أو الغلاف. بطاقة الهوية: منتصف البطاقة.',
  'Read from the chip: {0}. These come straight from the document\'s chip, so they\'re exact.':
      'قُرئت من الشريحة: {0}. هذه مأخوذة مباشرة من شريحة المستند، فهي دقيقة.',
  'The chip didn\'t open. Check the document number, date of birth and expiry date (or the card access number) against the document, then try again.':
      'لم تُفتح الشريحة. طابق رقم المستند وتاريخ الميلاد وتاريخ الانتهاء (أو رقم الوصول إلى البطاقة) مع المستند، ثم حاول مرة أخرى.',
  'The phone lost the chip. Hold it still against the document and try again. On a passport, try both the cover and the photo page.':
      'فقد الهاتف الاتصال بالشريحة. أبقِه ثابتًا على المستند وحاول مرة أخرى. في جواز السفر، جرّب الغلاف وصفحة الصورة.',
  'This chip doesn\'t take a card access number. Leave that box empty to use the number and dates.':
      'هذه الشريحة لا تقبل رقم الوصول إلى البطاقة. اترك تلك الخانة فارغة لاستخدام الرقم والتواريخ.',
  'That isn\'t a passport or ID card chip.':
      'هذه ليست شريحة جواز سفر أو بطاقة هوية.',
  'Couldn\'t read the chip. Try again, holding the phone still.':
      'تعذّرت قراءة الشريحة. حاول مرة أخرى مع إبقاء الهاتف ثابتًا.',
  'Stop reading': 'إيقاف القراءة',
  // ---- MyVault's own scanner and NFC ----
  'Crop the document': 'قصّ المستند',
  'Turn': 'تدوير',
  'Drag the corners onto the document\'s corners. MyVault cuts it out and straightens it, which also helps it read the details.': 'اسحب الزوايا إلى زوايا المستند. يقصّه MyVault ويقوّمه، وهذا يساعده أيضًا على قراءة التفاصيل.',
  'Retake': 'إعادة الالتقاط',
  'Use this': 'استخدام هذه',
  'Scan both sides of a card: take the photo with your camera (use its flash if it\'s dark), then drag the corners onto the card\'s. Files are encrypted the moment you add them, and MyVault reads the details from all of them together, on this phone.': 'امسح وجهي البطاقة: التقط الصورة بالكاميرا (استخدم الفلاش إذا كان المكان معتمًا)، ثم اسحب الزوايا إلى زوايا البطاقة. تُشفَّر الملفات لحظة إضافتها، ويقرأ MyVault التفاصيل منها كلها معًا على هذا الهاتف.',
  'Photo too bright or shiny? Tilt the card away from the light, or turn the flash off.': 'الصورة ساطعة أو لامعة؟ أمِل البطاقة بعيدًا عن الضوء، أو أطفئ الفلاش.',
  'Scan with NFC': 'المسح عبر NFC',
  'The chip opens only with the document\'s number, date of birth and expiry date. MyVault reads them from the <<< lines: first take a photo of the passport\'s photo page, or the back of the ID card.': 'لا تُفتح الشريحة إلا برقم المستند وتاريخ الميلاد وتاريخ الانتهاء. يقرؤها MyVault من أسطر <<<: التقط أولًا صورة لصفحة الصورة في جواز السفر، أو لظهر بطاقة الهوية.',
  'Card access number': 'رقم الوصول إلى البطاقة',
  'Take the photo': 'التقاط الصورة',
  'MyVault couldn\'t read the number and dates from the photo. Type them in (or take the photo again, straight and sharp), then tap Scan with NFC.': 'لم يتمكن MyVault من قراءة الرقم والتواريخ من الصورة. اكتبها بنفسك (أو التقط الصورة مجددًا مستقيمة وواضحة)، ثم اضغط «المسح عبر NFC».',
  'The chip didn\'t open. Check the document number, date of birth and expiry date against the document, then tap Scan with NFC again. Some ID cards open only with their card access number: you can choose it then.': 'لم تُفتح الشريحة. طابق رقم المستند وتاريخ الميلاد وتاريخ الانتهاء مع المستند، ثم اضغط «المسح عبر NFC» مرة أخرى. بعض بطاقات الهوية لا تُفتح إلا برقم الوصول إلى البطاقة: يمكنك اختياره حينها.',
  'That photo couldn\'t be used.': 'تعذّر استخدام هذه الصورة.',
  'Allow the camera for MyVault to take a photo (Android settings › Apps › MyVault › Permissions).': 'اسمح لـ MyVault باستخدام الكاميرا لالتقاط صورة (إعدادات Android › التطبيقات › MyVault › الأذونات).',
};

const arabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];
