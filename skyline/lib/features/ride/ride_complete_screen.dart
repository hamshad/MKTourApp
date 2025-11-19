import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api_service.dart';

class RideCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;
  
  const RideCompleteScreen({super.key, required this.rideData});

  @override
  State<RideCompleteScreen> createState() => _RideCompleteScreenState();
}

class _RideCompleteScreenState extends State<RideCompleteScreen> {
  int _rating = 0;
  double _selectedTip = 0;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  final List<double> _tipOptions = [2, 3, 5];

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);
    
    try {
      await ApiService.completeRide(
        bookingId: widget.rideData['bookingId'] ?? '',
        rating: _rating,
        tip: _selectedTip,
        feedback: _feedbackController.text,
      );
      
      if (mounted) {
        print('⭐ RIDE COMPLETE: Rating submitted successfully');
        print('⭐ RIDE COMPLETE: Rating = $_rating stars, Tip = £$_selectedTip');
        print('⭐ RIDE COMPLETE: Navigating to /home');
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to submit rating'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.rideData['driver'] ?? {};
    
    print('⭐ RIDE COMPLETE: Screen loaded');
    print('⭐ RIDE COMPLETE: Driver = ${driver['name']}');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Success icon
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: 64,
                          color: AppTheme.successColor,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Center(
                      child: Text(
                        'Trip completed!',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Fare Breakdown Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip fare',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),
                          
                          _buildFareRow('Base fare', '£2.50'),
                          const SizedBox(height: 12),
                          _buildFareRow('Distance (5.2 mi)', '£8.20'),
                          const SizedBox(height: 12),
                          _buildFareRow('Time (12 min)', '£2.30'),
                          
                          if (_selectedTip > 0) ...[
                            const SizedBox(height: 12),
                            _buildFareRow('Tip', '£${_selectedTip.toStringAsFixed(2)}'),
                          ],
                          
                          const SizedBox(height: 16),
                          Divider(color: AppTheme.borderColor),
                          const SizedBox(height: 16),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                '£${(13.00 + _selectedTip).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Tip Selection
                    Text(
                      'Add a tip',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        ..._tipOptions.map((tip) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _buildTipButton(tip),
                        )),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              // Show custom tip dialog
                              _showCustomTipDialog();
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _selectedTip > 0 && !_tipOptions.contains(_selectedTip)
                                    ? AppTheme.accentColor
                                    : AppTheme.borderColor,
                                width: _selectedTip > 0 && !_tipOptions.contains(_selectedTip) ? 2 : 1,
                              ),
                            ),
                            child: const Text('Custom'),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Rating
                    Text(
                      'How was your ride with ${driver['name'] ?? 'your driver'}?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return IconButton(
                            onPressed: () => setState(() => _rating = index + 1),
                            icon: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              size: 44,
                              color: index < _rating ? Colors.amber[700] : AppTheme.textSecondary,
                            ),
                          );
                        }),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Feedback
                    TextField(
                      controller: _feedbackController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Add a compliment or feedback (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Done button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_rating > 0 && !_isSubmitting) ? _submitRating : null,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFareRow(String label, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTipButton(double amount) {
    final isSelected = _selectedTip == amount;
    
    return OutlinedButton(
      onPressed: () => setState(() => _selectedTip = amount),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        side: BorderSide(
          color: isSelected ? AppTheme.accentColor : AppTheme.borderColor,
          width: isSelected ? 2 : 1,
        ),
        backgroundColor: isSelected ? AppTheme.accentColor.withValues(alpha: 0.05) : null,
      ),
      child: Text(
        '£${amount.toStringAsFixed(0)}',
        style: TextStyle(
          color: isSelected ? AppTheme.accentColor : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        ),
      ),
    );
  }
  
  void _showCustomTipDialog() {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom tip'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '£',
            hintText: 'Enter amount',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                setState(() => _selectedTip = amount);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
