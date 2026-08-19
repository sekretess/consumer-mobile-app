import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/di/injection.dart';
import 'core/theme/app_colors.dart';
import 'data/services/api_bridge_service.dart';
import 'data/services/deep_link_service.dart';
import 'presentation/pages/splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (with error handling)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase might not be configured yet, continue without it
    print('Firebase initialization failed: $e');
  }

  // Initialize Hive
  await Hive.initFlutter();

  // Configure dependencies (SharedPreferences will be initialized via module)
  await configureDependencies();
  
  // Initialize API bridge service for native-to-Flutter API calls
  try {
    final apiBridgeService = getIt<ApiBridgeService>();
    await apiBridgeService.initialize();
  } catch (e) {
    print('Failed to initialize ApiBridgeService: $e');
  }

  // Start listening for sekretess:// deep links (email verification callback)
  try {
    await getIt<DeepLinkService>().initialize();
  } catch (e) {
    print('Failed to initialize DeepLinkService: $e');
  }

  runApp(
    const ProviderScope(
      child: SekretessApp(),
    ),
  );
}

class SekretessApp extends StatefulWidget {
  const SekretessApp({super.key});

  @override
  State<SekretessApp> createState() => _SekretessAppState();
}

class _SekretessAppState extends State<SekretessApp> {
  /// App-level messenger, so the verification message survives the route
  /// changes a cold start goes through (Splash → Login/Main).
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<EmailVerificationResult>? _verificationSubscription;

  @override
  void initState() {
    super.initState();
    try {
      final deepLinkService = getIt<DeepLinkService>();
      _verificationSubscription =
          deepLinkService.verificationResults.listen(_showVerificationMessage);

      // A link that cold-started the app is handled before this widget exists.
      final pending = deepLinkService.takePendingResult();
      if (pending != null) {
        _showVerificationMessage(pending);
      }
    } catch (e) {
      print('Failed to listen for email verification results: $e');
    }
  }

  void _showVerificationMessage(EmailVerificationResult result) {
    // The messenger is only usable once the first frame is scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result.isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(result.message)),
              ],
            ),
            backgroundColor:
                result.isSuccess ? AppColors.success : AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
    });
  }

  @override
  void dispose() {
    _verificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sekretess',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SplashPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
