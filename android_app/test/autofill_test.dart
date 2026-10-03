import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/autofill.dart';
import 'package:myvault/vault.dart';

void main() {
  test('autofill matches web logins by host and app logins by package', () {
    expect(hostsMatch('accounts.google.com', 'https://google.com/x'), isTrue);
    expect(hostsMatch('www.github.com', 'github.com'), isTrue);
    expect(hostsMatch('evilgithub.com', 'github.com'), isFalse);
    expect(hostsMatch('', 'github.com'), isFalse);

    final web = AutofillRequest('github.com', 'github.com', true, true);
    final app = AutofillRequest('com.spotify.music', 'Spotify', false, true);
    final gh = Entry(title: 'GitHub', website: 'https://github.com');
    final sp = Entry(title: 'Spotify', app: 'com.spotify.music');
    final note = Entry(kind: 'note', website: 'github.com');
    expect(entryMatches(gh, web), isTrue);
    expect(entryMatches(sp, web), isFalse);
    expect(entryMatches(sp, app), isTrue);
    expect(entryMatches(gh, app), isFalse); // an app can't claim a website
    expect(entryMatches(note, web), isFalse);
  });
}
