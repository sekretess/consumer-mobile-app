import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart' show AuthRepository;
import '../../core/di/injection.dart';
import '../../core/network/api_exceptions.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/version_service.dart';
import 'main_page.dart';
import 'signup_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _infoMessage;
  /// Set when the last login was refused because this account's email is
  /// unverified; drives the "resend verification email" affordance.
  String? _unverifiedUsername;
  bool _isResendingEmail = false;
  String? _versionName;
  int? _versionCode;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final versionService = VersionService();
    final versionInfo = await versionService.getAppVersion();
    if (mounted) {
      setState(() {
        _versionName = versionInfo['versionName'];
        _versionCode = versionInfo['versionCode'];
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
      _unverifiedUsername = null;
    });

    try {
      final authRepository = getIt<AuthRepository>();
      await authRepository.authorize(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainPage()),
      );
    } on EmailNotVerifiedException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _unverifiedUsername = e.username;
        _errorMessage =
            'Your email address is not verified yet. Check your inbox for the '
            'verification link.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed. Please check your credentials.';
      });
    }
  }

  Future<void> _handleResendVerificationEmail() async {
    final username = _unverifiedUsername;
    if (username == null || _isResendingEmail) return;

    setState(() {
      _isResendingEmail = true;
      _infoMessage = null;
    });

    try {
      final message =
          await getIt<AuthRepository>().resendVerificationEmail(username);
      if (!mounted) return;
      setState(() {
        _isResendingEmail = false;
        _errorMessage = null;
        _unverifiedUsername = null;
        _infoMessage = message;
      });
    } on ResendVerificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _isResendingEmail = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResendingEmail = false;
        _errorMessage =
            'Could not resend the verification email. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      // Sekretess Logo
                      _buildLogo(),
                      const SizedBox(height: 60),
                      // Username Field
                      TextFormField(
                        controller: _usernameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Username',
                          labelStyle: const TextStyle(color: AppColors.sekretessBlue),
                          hintText: 'Enter your username',
                          hintStyle: const TextStyle(color: AppColors.textTertiary),
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: AppColors.sekretessBlue,
                          ),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.dividerColor,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.sekretessBlue,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.error,
                              width: 1,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.error,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your username';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: AppColors.white),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: AppColors.sekretessBlue),
                          hintText: 'Enter your password',
                          hintStyle: const TextStyle(color: AppColors.textTertiary),
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: AppColors.sekretessBlue,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppColors.textTertiary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.dividerColor,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.sekretessBlue,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.error,
                              width: 1,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: const BorderSide(
                              color: AppColors.error,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildMessageBox(_errorMessage!, AppColors.error),
                      ],
                      if (_infoMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildMessageBox(
                          _infoMessage!,
                          AppColors.sekretessBlue,
                        ),
                      ],
                      // Offered only after a login refused for an unverified
                      // email, so the username is known to exist.
                      if (_unverifiedUsername != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _isResendingEmail
                              ? null
                              : _handleResendVerificationEmail,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.sekretessBlue,
                          ),
                          icon: _isResendingEmail
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.sekretessBlue,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.mail_outline, size: 18),
                          label: Text(
                            _isResendingEmail
                                ? 'Sending...'
                                : 'Resend verification email',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Login Button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.sekretessBlue,
                            foregroundColor: AppColors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 29),
                      // Signup Link
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SignupPage()),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.white,
                        ),
                        child: const Text(
                          'Don\'t have an account? Sign up',
                          style: TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Hide the version label while the keyboard is open, otherwise the
          // bottom-anchored label rises with the shrinking layout and overlaps
          // the username/password fields.
          if (_versionName != null &&
              _versionCode != null &&
              MediaQuery.of(context).viewInsets.bottom == 0)
            Positioned(
              bottom: 16,
              right: 16,
              child: Text(
                'v$_versionName ($_versionCode)',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBox(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.1).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color,
          width: 1,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Sekretess Logo Image
        Image.asset(
          'assets/images/sekretess_logo.jpg',
          width: 255,
          height: 288,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback if image fails to load
            return Container(
              width: 255,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.sekretessBlue,
                    AppColors.lightBlue600,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: AppColors.white,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
