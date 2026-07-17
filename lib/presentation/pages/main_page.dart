import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/network/websocket_service.dart';
import '../../core/enums/sekretess_event.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/cryptographic_service.dart';
import '../../data/services/message_service.dart';
import '../providers/message_provider.dart';
import '../../core/theme/app_colors.dart';
import 'home_page.dart';
import 'businesses_page.dart';
import 'login_page.dart';
import 'profile_page.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _currentIndex = 0;
  late final WebSocketService _webSocketService;
  late final AuthRepository _authRepository;
  late final CryptographicService _cryptographicService;
  StreamSubscription<SekretessEvent>? _eventSubscription;
  StreamSubscription<bool>? _logoutSubscription;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _snackBarController;
  Timer? _connectionLostTimer;
  String? _username;

  // Only surface the "Network lost" message if the connection stays down this
  // long — brief, self-healing drops shouldn't annoy the user.
  static const Duration _connectionLostGracePeriod = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _webSocketService = getIt<WebSocketService>();
    _authRepository = getIt<AuthRepository>();
    _cryptographicService = getIt<CryptographicService>();

    _loadUsername();

    // Delay Signal Protocol initialization to ensure ApiBridgeService handler is registered
    Future.delayed(const Duration(milliseconds: 500), () {
      _initializeSignalProtocol();
    });
    _connectWebSocket();
    _listenToWebSocketEvents();
    _listenToLogoutEvents();
  }

  Future<void> _loadUsername() async {
    final username = await _authRepository.getUsername();
    if (mounted) {
      setState(() {
        _username = username;
      });
    }
  }

  Future<void> _initializeSignalProtocol() async {
    try {
      final success = await _cryptographicService.init();
      if (!success && mounted) {
        // Encryption key setup failed (e.g. keystore upload rejected by the
        // server). init() has already wiped the local keys, so continuing would
        // leave the user in a broken, undecryptable state. Log out and send them
        // back to login so a fresh, consistent key bundle is registered on the
        // next sign-in.
        await _logoutToLogin('Could not set up encryption keys. Please log in again.');
      }
    } catch (e) {
      if (mounted) {
        await _logoutToLogin('Error initializing encryption. Please log in again.');
      }
    }
  }

  /// Shows [message], then logs the user out. The resulting logout event is
  /// picked up by [_listenToLogoutEvents], which navigates back to the login
  /// screen.
  Future<void> _logoutToLogin(String message) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    await _authRepository.logout();
  }

  Future<void> _connectWebSocket() async {
    try {
      await _webSocketService.connect();
    } catch (e) {
      // Connection will be handled by event stream
    }
  }

  void _listenToWebSocketEvents() {
    _eventSubscription = _webSocketService.eventStream.listen((event) {
      if (mounted) {
        switch (event) {
          case SekretessEvent.websocketConnectionEstablished:
            // Connection recovered — cancel any pending "network lost" warning
            // and dismiss it if already shown.
            _connectionLostTimer?.cancel();
            _connectionLostTimer = null;
            _hideConnectionSnackbar();
            break;
          case SekretessEvent.websocketConnectionLost:
            // Debounce: wait out a grace period before warning. If a timer is
            // already pending or the snackbar is already up, don't reset it.
            if (_connectionLostTimer == null && _snackBarController == null) {
              _connectionLostTimer = Timer(_connectionLostGracePeriod, () {
                _connectionLostTimer = null;
                if (mounted) {
                  _showConnectionSnackbar();
                }
              });
            }
            break;
          case SekretessEvent.authFailed:
            _webSocketService.disconnect();
            _navigateToLogin();
            break;
        }
      }
    });
  }

  void _listenToLogoutEvents() {
    _logoutSubscription = _authRepository.logoutStream.listen((_) {
      if (mounted) {
        // CRITICAL: Invalidate providers to clear cached data for the new user session.
        ref.invalidate(messageBriefsProvider);
        ref.invalidate(topSendersProvider);
        ref.invalidate(messageEventStreamProvider);

        _webSocketService.disconnect();
        _navigateToLogin();
      }
    });
  }

  void _navigateToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false, // Remove all previous routes
    );
  }

  void _showConnectionSnackbar() {
    if (_snackBarController != null) return;

    _snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text('Network lost...'),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(days: 1), // Show indefinitely until dismissed
        action: SnackBarAction(
          label: 'Reconnect',
          textColor: Colors.white,
          onPressed: () {
            _hideConnectionSnackbar();
            _webSocketService.connect();
          },
        ),
      ),
    );

    _snackBarController?.closed.then((_) {
      _snackBarController = null;
    });
  }

  void _hideConnectionSnackbar() {
    _snackBarController?.close();
    _snackBarController = null;
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _logoutSubscription?.cancel();
    _connectionLostTimer?.cancel();
    _hideConnectionSnackbar();
    super.dispose();
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Home';
      case 1:
        return 'Businesses';
      case 2:
        return 'Profile';
      default:
        return 'Sekretess';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create the pages list directly in the build method.
    // This ensures the HomePage gets a new ValueKey whenever the username changes.
    final pages = [
      HomePage(key: ValueKey<String?>(_username)),
      const BusinessesPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        elevation: 0,
        backgroundColor: AppColors.primaryBackground,
        foregroundColor: AppColors.white,
      ),
      body: _username == null
          ? const Center(child: CircularProgressIndicator())
          : pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: AppColors.primaryBackground,
        selectedItemColor: AppColors.sekretessBlue,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business),
            label: 'Businesses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
