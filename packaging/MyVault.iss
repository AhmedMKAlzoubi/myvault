; Inno Setup script for the MyVault installer. Built by packaging/build_windows.py.
;
; Installs like any normal app: per-user into %LOCALAPPDATA%\Programs\MyVault by
; default (no admin prompt), or into Program Files when "install for all users"
; is picked. Adds a desktop shortcut, a Start menu entry and an uninstaller.
; Your vault lives separately in %LOCALAPPDATA%\MyVault and is never touched by
; installing, updating or uninstalling.

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
