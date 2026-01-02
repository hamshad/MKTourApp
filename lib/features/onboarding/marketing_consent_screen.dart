import 'package:flutter/material.dart';
import '../../core/theme.dart';

class MarketingConsentScreen extends StatefulWidget {
  const MarketingConsentScreen({super.key});

  @override
  State<MarketingConsentScreen> createState() => _MarketingConsentScreenState();
}

class _MarketingConsentScreenState extends State<MarketingConsentScreen> {
  bool? _accepted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay in the loop',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'I would like to receive discounts and exclusive offers by email or SMS.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              RadioListTile<bool>(
                title: const Text('Yes, please'),
                value: true,
                groupValue: _accepted,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (value) {
                  setState(() {
                    _accepted = value;
                  });
                },
              ),
              RadioListTile<bool>(
                title: const Text('No, thanks'),
                value: false,
                groupValue: _accepted,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (value) {
                  setState(() {
                    _accepted = value;
                  });
                },
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _accepted != null
                      ? () {
                          // Store choice locally (mock)
                          Navigator.pushNamed(context, '/payment-method');
                        }
                      : null,
                  child: const Text('Continue'),
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
