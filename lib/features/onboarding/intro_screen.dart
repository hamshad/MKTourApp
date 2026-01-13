import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Image.file(
                File('/Users/mokshassd/.gemini/antigravity/brain/21bdd7cf-e750-443f-a619-eae979b78097/onboarding_taxi_illustration_1768307016254.png'),
                height: 300,
                width: 300,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 40),
              Text(
                'Ride with ease across the city.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Let us get you where you need to be.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/marketing-consent');
                  },
                  child: const Text('Next'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
