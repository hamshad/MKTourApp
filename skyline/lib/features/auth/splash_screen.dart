import 'package:flutter/material.dart';
import 'package:mktours/features/auth/role_selection_screen.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import 'dart:async';

import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }



  Future<void> _checkAuth() async {
    // Minimum splash duration
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = await authProvider.tryAutoLogin();

    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'lib/assets/lottie/splash.json',
              repeat: false,
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.width * 0.8,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            
            Image.asset(
              'lib/assets/images/Logo-01.png',
              width: 200,
              height: 100,
              fit: BoxFit.contain,
            ),
            
            const SizedBox(height: 12),

            Text(
              'MK-Tours',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 12),
            
            Text(
              'Your journey, simplified',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
