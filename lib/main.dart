import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/api.dart';
import 'core/app_state.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/google_auth.dart';
import 'features/shell/home_shell.dart';
import 'features/splash/splash_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// True once the splash screen has handed over (until then the splash decides the first screen).
final appStarted = ValueNotifier<bool>(false);

/// Google sign-in problems for the sign-in screen to show.
final googleAuthError = ValueNotifier<String?>(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts load from Google once, then come from the device cache (fallback: system font).
  GoogleFonts.config.allowRuntimeFetching = true;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Session expired for good (refresh refused / banned): back to sign-in from anywhere.
  ApiClient.instance.onSignedOut = () {
    AppState.instance.reset();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  };

  // Google sign-in returns to the app as a deep link (dazzlingwins://auth?code=…).
  GoogleAuth.onResult = (error) async {
    if (error != null) {
      googleAuthError.value = error;
      return;
    }
    googleAuthError.value = null;
    if (!appStarted.value) return; // the splash sees the new session and opens the app itself
    await AppState.instance.refreshAll().timeout(const Duration(seconds: 6), onTimeout: () {});
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  };
  GoogleAuth.listen();

  runApp(const DazzlingWinsApp());
}

class DazzlingWinsApp extends StatelessWidget {
  const DazzlingWinsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DazzlingWins',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.build(),
      // Keep text readable but never let a huge system font size break layouts.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.2);
        return MediaQuery(data: media.copyWith(textScaler: scale), child: child!);
      },
      home: SplashScreen(
        onReady: (context) async {
          await Session.instance.load();
          final next = Session.instance.isSignedIn ? const HomeShell() : const AuthScreen();
          if (Session.instance.isSignedIn) {
            // Warm the cache while the splash is still on screen.
            await AppState.instance.refreshAll().timeout(const Duration(seconds: 6), onTimeout: () {});
          }
          return next;
        },
      ),
    );
  }
}
