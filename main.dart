// fastlane_session_manager.dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class FastlaneSessionManager {
  static const String _sessionFileName = 'fastlane_session.json';
  
  // Session bilgilerini tutan model
  static class FastlaneSession {
    final String? appleCookie;
    final String? googleCookie;
    final String? matchPassword;
    final DateTime lastLogin;
    final Map<String, String> environment;

    FastlaneSession({
      this.appleCookie,
      this.googleCookie,
      this.matchPassword,
      required this.lastLogin,
      required this.environment,
    });

    Map<String, dynamic> toJson() => {
      'appleCookie': appleCookie,
      'googleCookie': googleCookie,
      'matchPassword': matchPassword,
      'lastLogin': lastLogin.toIso8601String(),
      'environment': environment,
    };

    factory FastlaneSession.fromJson(Map<String, dynamic> json) {
      return FastlaneSession(
        appleCookie: json['appleCookie'],
        googleCookie: json['googleCookie'],
        matchPassword: json['matchPassword'],
        lastLogin: DateTime.parse(json['lastLogin']),
        environment: Map<String, String>.from(json['environment']),
      );
    }
  }

  // Session bilgilerini kaydet
  static Future<void> saveSession(FastlaneSession session) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_sessionFileName');
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (e) {
      print('Session kaydetme hatası: $e');
    }
  }

  // Session bilgilerini oku
  static Future<FastlaneSession?> loadSession() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_sessionFileName');
      
      if (await file.exists()) {
        final jsonStr = await file.readAsString();
        return FastlaneSession.fromJson(jsonDecode(jsonStr));
      }
    } catch (e) {
      print('Session okuma hatası: $e');
    }
    return null;
  }

  // Fastlane çıktısından çerezleri ayıkla
  static Future<FastlaneSession?> extractSessionFromOutput(String output) async {
    final Map<String, String> environment = {};
    String? appleCookie;
    String? googleCookie;
    String? matchPassword;

    // Apple session cookie'sini bul
    final appleMatch = RegExp(r'fastlane_session:([^\s]+)').firstMatch(output);
    if (appleMatch != null) {
      appleCookie = appleMatch.group(1);
    }

    // Google Play session cookie'sini bul
    final googleMatch = RegExp(r'oauth2_token:([^\s]+)').firstMatch(output);
    if (googleMatch != null) {
      googleCookie = googleMatch.group(1);
    }

    // Match password'ü bul
    final matchMatch = RegExp(r'MATCH_PASSWORD=([^\s]+)').firstMatch(output);
    if (matchMatch != null) {
      matchPassword = matchMatch.group(1);
    }

    // Çevresel değişkenleri topla
    final envVars = [
      'FASTLANE_USER',
      'FASTLANE_PASSWORD',
      'FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD',
      'FASTLANE_SESSION',
      'MATCH_PASSWORD',
      'GOOGLE_PLAY_JSON_KEY',
    ];

    for (var env in envVars) {
      final value = Platform.environment[env];
      if (value != null) {
        environment[env] = value;
      }
    }

    if (appleCookie != null || googleCookie != null || environment.isNotEmpty) {
      final session = FastlaneSession(
        appleCookie: appleCookie,
        googleCookie: googleCookie,
        matchPassword: matchPassword,
        lastLogin: DateTime.now(),
        environment: environment,
      );
      
      await saveSession(session);
      return session;
    }

    return null;
  }
}

// Güncellenmiş FastlaneController
class FastlaneController {
  static Future<FastlaneResult> runFastlaneCommand({
    required String platform,
    required String lane,
    required String workingDirectory,
  }) async {
    try {
      // Mevcut session'ı yükle
      final existingSession = await FastlaneSessionManager.loadSession();
      
      // Çevresel değişkenleri ayarla
      final Map<String, String> environment = Map.from(Platform.environment);
      if (existingSession != null) {
        environment.addAll(existingSession.environment);
        
        if (existingSession.appleCookie != null) {
          environment['FASTLANE_SESSION'] = existingSession.appleCookie!;
        }
        if (existingSession.matchPassword != null) {
          environment['MATCH_PASSWORD'] = existingSession.matchPassword!;
        }
      }

      final result = await Process.run(
        'fastlane',
        [platform, lane],
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: true,
      );

      // Çıktıdan yeni session bilgilerini ayıkla
      final newSession = await FastlaneSessionManager.extractSessionFromOutput(
        result.stdout.toString(),
      );

      return FastlaneResult(
        success: result.exitCode == 0,
        output: result.stdout.toString(),
        error: result.stderr.toString(),
        session: newSession ?? existingSession,
      );
    } catch (e) {
      return FastlaneResult(
        success: false,
        output: '',
        error: e.toString(),
        session: null,
      );
    }
  }
}

// Güncellenmiş FastlaneResult
class FastlaneResult {
  final bool success;
  final String output;
  final String error;
  final FastlaneSessionManager.FastlaneSession? session;

  FastlaneResult({
    required this.success,
    required this.output,
    required this.error,
    this.session,
  });
}

// Fastlane ekranına eklenecek session widget'ı
class FastlaneSessionWidget extends StatelessWidget {
  final FastlaneSessionManager.FastlaneSession? session;

  const FastlaneSessionWidget({this.session});

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Oturum bilgisi bulunamadı'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Oturum Bilgileri',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 8),
            Text('Son Giriş: ${session!.lastLogin.toString()}'),
            if (session!.appleCookie != null) ...[
              SizedBox(height: 8),
              Text('Apple Session: ${session!.appleCookie!.substring(0, 20)}...'),
            ],
            if (session!.googleCookie != null) ...[
              SizedBox(height: 8),
              Text('Google Session: ${session!.googleCookie!.substring(0, 20)}...'),
            ],
            if (session!.environment.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Çevresel Değişkenler:'),
              ...session!.environment.entries.map(
                (e) => Text('${e.key}: ${e.value.substring(0, 10)}...'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
