import 'package:flutter/material.dart';
import 'package:mktours/features/auth/role_selection_screen.dart';
import 'package:mktours/features/auth/widgets/app_update_screen.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/models/app_version.dart';
import '../../core/services/app_version_service.dart';
import 'dart:async';

import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AppVersionService _versionService = AppVersionService();
  AppVersionResult? _blockingResult;
  bool _maintenanceRetrying = false;
  late final AnimationController _mainController;
  late final AnimationController _pulseController;

  late final Animation<double> _lottieFade;
  late final Animation<double> _lottieScale;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _lottieFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _lottieScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.45, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _textFade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    _mainController.forward();
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mainController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-run version check when user resumes from the store (spec §4.1.2).
    if (state == AppLifecycleState.resumed && _blockingResult != null) {
      _recheckVersion();
    }
  }

  Future<void> _recheckVersion() async {
    final result = await _versionService.checkForUpdate();
    if (!mounted) return;
    if (result.isBlocking || !result.canContinue) {
      setState(() {
        _blockingResult = result;
        _maintenanceRetrying = false;
      });
      return;
    }
    setState(() => _blockingResult = null);
    if (result.updateType == AppUpdateType.soft) {
      await showSoftUpdateDialog(context, result);
      if (!mounted) return;
    }
    await _proceedToAuth();
  }

  Future<void> _retryMaintenance() async {
    setState(() => _maintenanceRetrying = true);
    await _recheckVersion();
  }

  Future<void> _checkAuth() async {
    // Minimum splash duration
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    // Version gate runs before tokens / navigation (spec §4.1.1).
    // Fail-open: offline or server error proceeds to normal auth flow.
    final versionResult = await _versionService.checkForUpdate();
    if (!mounted) return;

    if (versionResult.isBlocking || !versionResult.canContinue) {
      setState(() => _blockingResult = versionResult);
      return;
    }

    if (versionResult.updateType == AppUpdateType.soft) {
      await showSoftUpdateDialog(context, versionResult);
      if (!mounted) return;
    }

    await _proceedToAuth();
  }

  Future<void> _proceedToAuth() async {

    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = await authProvider.tryAutoLogin();

    if (!mounted) return;

    if (isLoggedIn) {
      if (authProvider.isDriver) {
        final status = authProvider.driverProfileStatus;
        final verificationStatus = status?['verificationStatus']?.toString();
        final targetRoute =
            (verificationStatus == 'pending' ||
                verificationStatus == 'rejected')
            ? '/driver-profile'
            : '/driver-home';

        Navigator.pushReplacementNamed(context, targetRoute);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _blockingResult;
    if (blocking != null) {
      if (blocking.updateType == AppUpdateType.maintenance) {
        return MaintenanceScreen(
          result: blocking,
          isRetrying: _maintenanceRetrying,
          onRetry: _retryMaintenance,
        );
      }
      return ForceUpdateScreen(result: blocking);
    }

    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFEFF5FF).withOpacity(
                        0.7 + (_pulseController.value * 0.2),
                      ),
                      const Color(0xFFFFF2E5).withOpacity(
                        0.62 + (_pulseController.value * 0.18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _lottieFade,
                  child: ScaleTransition(
                    scale: _lottieScale,
                    child: Lottie.asset(
                      'lib/assets/lottie/splash.json',
                      repeat: false,
                      width: width * 0.8,
                      height: width * 0.8,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: _taglineFade,
                  child: SlideTransition(
                    position: _taglineSlide,
                    child: Text(
                      'Your Journey, Simplified',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: const Color(0xFF1F2A44),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _logoFade,
                  child: SlideTransition(
                    position: _logoSlide,
                    child: Image.asset(
                      'lib/assets/images/Logo-01.png',
                      width: 200,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    'MK-Tours',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    'Proud to Serve',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      letterSpacing: 0.25,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
