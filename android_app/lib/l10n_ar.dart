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
