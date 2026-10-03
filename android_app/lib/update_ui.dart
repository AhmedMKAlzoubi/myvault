/// The phone's update screens: the one-time "check online?" question, the
/// "update available / ready" prompts, and Settings › Updates.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'theme.dart';
import 'update.dart' as upd;
import 'version.dart';

void _snack(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(tr(msg))));

bool isNewerVersion(String a, String b) => upd.isNewer(a, b);

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

/// Runs once after unlocking: ask the question the first time, offer a waiting
/// update, then (if allowed, and at most once a day) look on GitHub.
Future<void> startupUpdateFlow(BuildContext context) async {
  final ready = await upd.readyApk();
  if (ready != null && context.mounted) return offerInstall(context, ready);
  final prefs = await upd.loadPrefs();
  if (!context.mounted) return;
  if (prefs['update_check'] == null) {
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(tr('Check for updates online?')),
        content: Text(
          tr(
            'New versions of MyVault come out every now and then. To find out when, '
            'MyVault can look at a small version file on GitHub (at most once a day). '
            'Nothing from your vault is sent. You can change this later under Updates.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('No thanks')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Yes, let me know')),
          ),
        ],
      ),
    );
    prefs['update_check'] = yes == true;
    await upd.savePrefs(prefs);
  }
  final last = (prefs['last_check'] ?? 0) as num;
  final dayOld =
      DateTime.now().millisecondsSinceEpoch / 1000 - last > 24 * 3600;
  if (prefs['update_check'] == true && dayOld && context.mounted) {
    await checkNow(context, quiet: true);
  }
}

/// Ask GitHub; if there's something newer, offer it. [quiet] hides "up to date".
Future<void> checkNow(BuildContext context, {bool quiet = false}) async {
  try {
    final r = await upd.checkOnline();
    final prefs = await upd.loadPrefs();
    prefs['last_check'] = DateTime.now().millisecondsSinceEpoch / 1000;
    await upd.savePrefs(prefs);
    if (!context.mounted) return;
    if (!upd.isNewer(r.version, appVersion)) {
      if (!quiet) _snack(context, 'MyVault $appVersion is the newest version.');
      return;
    }
    final size = r.sizeOf(upd.platformName) + r.sizeOf('windows');
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('MyVault ${r.version} is available')),
        content: Text(
          tr(
            'You have $appVersion. Updating keeps your vault exactly as it is.\n\n'
            'Downloads ${_mb(size)}: the phone update, plus the PC update so you can '
            'pass it to your PC the next time you sync. Best on WiFi.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Later')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Update now')),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) await _download(context, r);
  } on upd.UpdateException catch (e) {
    if (!quiet && context.mounted) _snack(context, e.message);
  } catch (e) {
    if (!quiet && context.mounted) {
      _snack(context, tr("Couldn't check for updates: $e"));
    }
  }
}

Future<void> _download(BuildContext context, upd.Release r) async {
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(tr('Downloading the update')),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: v == 0 ? null : v),
            const SizedBox(height: 10),
            Text(v == 0 ? tr('Starting…') : '${(v * 100).round()}%'),
          ],
        ),
      ),
    ),
  );
  try {
    final apk = await upd.download(
      r,
      upd.platformName,
      progress: (v) => progress.value = v,
    );
    if (r.sizeOf('windows') > 0) {
      try {
        await upd.download(r, 'windows', progress: (v) => progress.value = v);
      } catch (_) {
        // The phone update matters most; the PC copy is a convenience.
      }
    }
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) await offerInstall(context, apk);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      _snack(
        context,
        e is upd.UpdateException ? e.message : tr('The download failed: $e'),
      );
    }
  }
}

/// A verified APK is on the phone: ask, then hand it to Android's installer.
Future<void> offerInstall(
  BuildContext context,
  upd.Package p, {
  String from = '',
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Install MyVault ${p.version}?')),
      content: Text(
        tr(
          '${from.isEmpty ? '' : '$from\n\n'}You have $appVersion. Your vault stays exactly as it is. '
          "Android will show its install screen; MyVault closes while it updates.",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('Later')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('Install')),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final bool started;
  try {
    started = await upd.installApk(p);
  } on upd.UpdateException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return;
  }
  if (!started && context.mounted) {
    _snack(
      context,
      tr(
        'Allow "Install unknown apps" for MyVault, then come back and tap Install again.',
      ),
    );
  }
}

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  Map<String, dynamic> _prefs = {};
  upd.Package? _ready;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await upd.loadPrefs();
    final r = await upd.readyApk();
    if (mounted) {
      setState(() {
        _prefs = p;
        _ready = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    final on = _prefs['update_check'] == true;
    final last = (_prefs['last_check'] ?? 0) as num;
    final when = last == 0
        ? 'never'
        : DateTime.fromMillisecondsSinceEpoch(
            (last * 1000).round(),
          ).toString().substring(0, 16);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Updates'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            tr('This is MyVault $appVersion.'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Updates also arrive offline: when you sync, a newer PC hands its phone update over.',
            ),
            style: TextStyle(color: e.ink2, height: 1.4),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Let me know when a new version is out')),
            subtitle: Text(
              tr(
                'MyVault looks at a small version file on GitHub, at most once a day. Nothing from your vault is sent.',
              ),
            ),
            value: on,
            onChanged: (v) async {
              _prefs['update_check'] = v;
              await upd.savePrefs(_prefs);
              setState(() {});
            },
          ),
          Text(
            tr('Last checked: $when'),
            style: TextStyle(color: e.ink3, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          if (_ready != null)
            FilledButton.icon(
              onPressed: () => offerInstall(context, _ready!),
              icon: const Icon(Icons.system_update),
              label: Text(tr('Install MyVault ${_ready!.version}')),
            )
          else
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await checkNow(context);
                      if (mounted) setState(() => _busy = false);
                      _load();
                    },
              icon: const Icon(Icons.refresh),
              label: Text(tr(_busy ? 'Checking…' : 'Check now')),
            ),
          const SizedBox(height: 26),
          Text(
            tr('Go back to the previous version'),
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              "Android doesn't let an app install an older version of itself over a newer one. "
              'Going back means removing MyVault, which also removes its copy of your vault, so:\n\n'
              '1. Sync with your PC first, so the PC has everything.\n'
              '2. Uninstall MyVault on this phone.\n'
              '3. Install the older MyVault APK from the releases page.\n'
              '4. Create a master password, then sync with your PC again.',
            ),
            style: TextStyle(color: e.ink2, height: 1.45),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => const MethodChannel(
                'myvault/update',
              ).invokeMethod('openDoc', 'RELEASES'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr('Open the releases page')),
            ),
          ),
        ],
      ),
    );
  }
}

/// About MyVault: version, and the privacy policy, terms and security policy
/// (opened in the browser from GitHub).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final e = Envelope.of(context);
    Widget doc(String title, String file) => ListTile(
      title: Text(tr(title)),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () =>
          const MethodChannel('myvault/update').invokeMethod('openDoc', file),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('About MyVault'))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              tr(
                'MyVault $appVersion\n\nMade by Ahmed Mohammed. Free software under the GPL-3.0 licence. Your vault stays on your '
                'devices: no account, no cloud, no tracking.',
              ),
              style: TextStyle(color: e.ink2, height: 1.45),
            ),
          ),
          doc(tr('Privacy policy'), 'PRIVACY.md'),
          doc(tr('Terms of use'), 'TERMS.md'),
          doc(tr('Security & reporting a problem'), 'SECURITY.md'),
          doc(tr("What's new"), 'CHANGELOG.md'),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              tr('Contact: ahmedmohammedkhear@gmail.com'),
              style: TextStyle(color: e.ink3, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
