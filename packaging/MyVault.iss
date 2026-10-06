; Inno Setup script for the MyVault installer. Built by packaging/build_windows.py.
;
; Installs like any normal app: per-user into %LOCALAPPDATA%\Programs\MyVault by
; default (no admin prompt), or into Program Files when "install for all users"
; is picked. Adds a desktop shortcut, a Start menu entry and an uninstaller.
; Your vaults live separately in %LOCALAPPDATA%\MyVault. Installing and updating
; never touch them; uninstalling asks first (keep them, save a copy, or delete).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
ShowLanguageDialog=auto
AppId={{6F1A2C3E-9B4D-4E8A-A7C2-5D3B8E1F0A94}
AppName=MyVault
AppVersion={#AppVersion}
AppVerName=MyVault {#AppVersion}
AppPublisher=Ahmed Mohammed
AppPublisherURL=https://github.com/AhmedMKAlzoubi/myvault
AppSupportURL=https://github.com/AhmedMKAlzoubi/myvault/issues
DefaultDirName={autopf}\MyVault
DefaultGroupName=MyVault
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=MyVault-Setup-{#AppVersion}
SetupIconFile=..\assets\myvault.ico
UninstallDisplayIcon={app}\MyVault.exe
UninstallDisplayName=MyVault
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Languages]
; Setup picks the one matching Windows' display language (no language prompt).
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"

[CustomMessages]
en.StartupTask=Start MyVault when I sign in to Windows (it waits by the clock, locked)
ar.StartupTask=شغّل MyVault عند تسجيل دخولي إلى Windows (ينتظر بجانب الساعة، مقفلًا)
en.CopyTitle=Save a copy of your vaults first?
en.CopyText=MyVault can save a copy of a vault to keep somewhere else: encrypted (it opens only with that vault's master password) or readable (anyone can open it).%n%nTo do that, choose Save a copy: MyVault opens. Unlock a vault, go to Settings › A copy of this vault, then run the uninstaller again.
en.CopyBtn=Save a copy first
en.GoOnBtn=Uninstall now
en.KeepTitle=Keep your vaults on this PC?
en.KeepText=Your vaults are encrypted files in:%n%n%1%n%nKeep them, and reinstalling MyVault opens them again. Nobody can read them without their master passwords.%n%nDelete them, and everything in them is gone from this PC for good. Copies on your phone stay.
en.KeepBtn=Keep my vaults
en.DeleteBtn=Delete my vaults too
en.SureDelete=Delete every vault on this PC for good? This can't be undone.
en.KeptAt=Your vaults stay on this PC, encrypted, in:%n%n%1%n%nWrite this path down and keep it somewhere safe.
ar.CopyTitle=حفظ نسخة من خزائنك أولًا؟
ar.CopyText=يستطيع MyVault حفظ نسخة من خزنة لتحتفظ بها في مكان آخر: مشفّرة (لا تُفتح إلا بكلمة المرور الرئيسية لتلك الخزنة) أو مقروءة (يستطيع أي أحد فتحها).%n%nلفعل ذلك اختر «حفظ نسخة أولًا»: سيُفتح MyVault. افتح خزنة، ثم الإعدادات › نسخة من هذه الخزنة، ثم شغّل أداة الإزالة مرة أخرى.
ar.CopyBtn=حفظ نسخة أولًا
ar.GoOnBtn=الإزالة الآن
ar.KeepTitle=الإبقاء على خزائنك على هذا الكمبيوتر؟
ar.KeepText=خزائنك ملفات مشفّرة في:%n%n%1%n%nأبقِها، وعند إعادة تثبيت MyVault تُفتح من جديد. لا يستطيع أحد قراءتها دون كلمات المرور الرئيسية.%n%nاحذفها، فيزول كل ما فيها من هذا الكمبيوتر نهائيًا. وتبقى النسخ التي على هاتفك.
ar.KeepBtn=الإبقاء على خزائني
ar.DeleteBtn=حذف خزائني أيضًا
ar.SureDelete=حذف كل الخزائن على هذا الكمبيوتر نهائيًا؟ لا يمكن التراجع عن ذلك.
ar.KeptAt=تبقى خزائنك على هذا الكمبيوتر، مشفّرة، في:%n%n%1%n%nاكتب هذا المسار واحفظه في مكان آمن.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartupTask}"; GroupDescription: "{cm:AdditionalIcons}"

[Registry]
; Same per-user Run entry the in-app switch (Settings > Start with Windows) manages.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MyVault"; ValueData: """{app}\MyVault.exe"" --minimized"; Flags: uninsdeletevalue; Tasks: startup

[InstallDelete]
; Phone APKs from earlier versions: keep only the one that matches this PC app.
Type: filesandordirs; Name: "{app}\packages"

[Files]
Source: "..\dist\MyVault\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\MyVault"; Filename: "{app}\MyVault.exe"; AppUserModelID: "MyVault.Desktop"
Name: "{autodesktop}\MyVault"; Filename: "{app}\MyVault.exe"; Tasks: desktopicon; AppUserModelID: "MyVault.Desktop"

[Run]
Filename: "{app}\MyVault.exe"; Description: "{cm:LaunchProgram,MyVault}"; Flags: nowait postinstall skipifsilent
; In-app updates run the installer silently: start MyVault again afterwards.
Filename: "{app}\MyVault.exe"; Flags: nowait; Check: WizardSilent

[UninstallRun]
; Close a running MyVault before its files are removed.
Filename: "{sys}\taskkill.exe"; Parameters: "/IM MyVault.exe /F"; Flags: runhidden; RunOnceId: "StopMyVault"
; Also remove a start-with-Windows entry made from inside the app.
Filename: "{sys}\reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v MyVault /f"; Flags: runhidden; RunOnceId: "RemoveStartup"

[Code]
// Uninstalling asks what happens to the vaults (they aren't in {app}): save a
// copy first, keep them (the path is shown), or delete them too.
var
  DeleteVaults: Boolean;

function VaultsDir: String;
begin
  Result := ExpandConstant('{localappdata}\MyVault');
end;

function InitializeUninstall: Boolean;
var
  Answer, Code: Integer;
begin
  Result := True;
  DeleteVaults := False;
  if UninstallSilent or not DirExists(VaultsDir) then
    Exit;
  Answer := TaskDialogMsgBox(CustomMessage('CopyTitle'), CustomMessage('CopyText'), mbConfirmation,
    MB_YESNOCANCEL, [CustomMessage('CopyBtn'), CustomMessage('GoOnBtn')], 0);
  if Answer = IDYES then
    ShellExec('', ExpandConstant('{app}\MyVault.exe'), '', '', SW_SHOWNORMAL, ewNoWait, Code);
  if Answer <> IDNO then
  begin
    Result := False;         // a copy first, or Cancel: nothing is uninstalled
    Exit;
  end;
  Answer := TaskDialogMsgBox(CustomMessage('KeepTitle'), FmtMessage(CustomMessage('KeepText'), [VaultsDir]),
    mbConfirmation, MB_YESNO, [CustomMessage('KeepBtn'), CustomMessage('DeleteBtn')], 0);
  if Answer = IDNO then
    DeleteVaults := MsgBox(CustomMessage('SureDelete'), mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep <> usPostUninstall) or UninstallSilent or not DirExists(VaultsDir) then
    Exit;
  if DeleteVaults then
    DelTree(VaultsDir, True, True, True)
  else
    MsgBox(FmtMessage(CustomMessage('KeptAt'), [VaultsDir]), mbInformation, MB_OK);
end;
