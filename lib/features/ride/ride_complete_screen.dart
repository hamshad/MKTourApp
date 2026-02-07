import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/widgets/custom_snackbar.dart';

class RideCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;

  const RideCompleteScreen({super.key, required this.rideData});

  @override
  State<RideCompleteScreen> createState() => _RideCompleteScreenState();
}

class _RideCompleteScreenState extends State<RideCompleteScreen> {
  final ApiService _apiService = ApiService();
  int _rating = 0;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;


  // Get actual fare from ride data
  double get _fare => (widget.rideData['fare'] ?? 0.0).toDouble();
  double get _distance => (widget.rideData['distance'] ?? widget.rideData['actualDistance'] ?? 0.0).toDouble();
  double get _originalFare => (widget.rideData['originalFare'] ?? 0.0).toDouble();
  bool get _isEarlyCompletion => 
      widget.rideData['status'] == 'early_completed' || 
      widget.rideData['earlyCompleted'] == true;
  String get _reason => widget.rideData['reason'] ?? '';
  bool get _isAirportTransfer => widget.rideData['isAirportTransfer'] == true; // Check if it's an airport transfer
  String get _rideId =>
      widget.rideData['bookingId'] ??
      widget.rideData['_id'] ??
      widget.rideData['rideId'] ??
      '';

  final SocketService _socketService = SocketService();
  bool _isCashConfirmed = false;

  @override
  void initState() {
    super.initState();
    _checkInitialPaymentStatus();
    _listenForPaymentUpdates();
  }

  void _checkInitialPaymentStatus() {
     // If it's card, it's already paid. If cash, check if already confirmed (logic could vary)
     if (widget.rideData['paymentMethod'] != 'cash') {
       _isCashConfirmed = true;
     } else if (widget.rideData['paymentStatus'] == 'completed') {
       _isCashConfirmed = true;
     }
  }

  void _listenForPaymentUpdates() {
    if (_isCashConfirmed) return;

    _socketService.on('payment:cashCollected', (data) {
      if (mounted) {
         // Verify rideId if needed
         setState(() {
           _isCashConfirmed = true;
         });
         CustomSnackbar.show(
            context,
            message: 'Cash payment confirmed!',
            type: SnackbarType.success,
         );
      }
    });
  }

  @override
  void dispose() {
    _socketService.off('payment:cashCollected');
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_rating == 0) {
      CustomSnackbar.show(
        context,
        message: 'Please select a rating',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    debugPrint(
      '🔵 ------------------------------------------------------------------',
    );
    debugPrint('🔵 [RideCompleteScreen] Submitting rating...');
    debugPrint('🔵 [RideCompleteScreen] RideId: $_rideId');
    debugPrint('🔵 [RideCompleteScreen] Rating: $_rating');
    debugPrint('🔵 [RideCompleteScreen] Feedback: ${_feedbackController.text}');

    try {
      final response = await _apiService.rateRide(
        bookingId: _rideId,
        rating: _rating,
        feedback: _feedbackController.text,
      );

      debugPrint('🟣 [RideCompleteScreen] API Response: $response');

      if (mounted) {
        if (response['success'] == true || response['status'] == 'success') {
          debugPrint('🟢 [RideCompleteScreen] Rating submitted successfully');

          CustomSnackbar.show(
            context,
            message: 'Thank you for your feedback!',
            type: SnackbarType.success,
          );

          await Future.delayed(const Duration(seconds: 1));

          if (mounted) {
            debugPrint('⭐ [RideCompleteScreen] Navigating to /home');
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            );
          }
        } else {
          debugPrint(
            '🔴 [RideCompleteScreen] Rating submission failed: ${response['message']}',
          );
          CustomSnackbar.show(
            context,
            message: response['message'] ?? 'Failed to submit rating',
            type: SnackbarType.error,
          );
        }
      }
    } catch (e) {
      debugPrint('🔴 [RideCompleteScreen] Exception caught: $e');
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Failed to submit rating. Please try again.',
          type: SnackbarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _skipRating() {
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.rideData['driver'] ?? {};

    debugPrint('⭐ RIDE COMPLETE: Screen loaded');
    debugPrint('⭐ RIDE COMPLETE: Driver = ${driver['name']}');
    debugPrint('⭐ RIDE COMPLETE: Fare = $_fare');

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

                    // Payment Method Section
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: const Icon(Icons.credit_card, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Payment Method',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.rideData['paymentMethod'] ?? 'Cash',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

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
                          Row(
                            children: [
                              Text(
                                'Trip fare',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (_isAirportTransfer) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.flight, color: Colors.blue, size: 16),
                                      SizedBox(width: 4),
                                      Text(
                                        'Airport Transfer',
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),
                           if (_isEarlyCompletion && _reason.isNotEmpty) ...[
                            _buildFareRow(
                              'Reason',
                              _reason.replaceAll('_', ' ').toUpperCase(),
                            ),
                          ],
                          if (_distance > 0) ...[
                            _buildFareRow(
                              _isEarlyCompletion ? 'Actual Distance' : 'Total Distance',
                              '${_distance.toStringAsFixed(2)} mi',
                            ),
                          ],
                          if (_isEarlyCompletion && _originalFare > 0) ...[
                            _buildFareRow(
                              'Original Fare',
                              '£${_originalFare.toStringAsFixed(2)}',
                            ),
                          ],

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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '£${_fare.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        _isCashConfirmed ? Icons.check_circle : Icons.pending,
                                        size: 14,
                                        color: _isCashConfirmed ? Colors.green[600] : Colors.orange[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isCashConfirmed ? 'Paid' : 'Pay Cash to Driver',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _isCashConfirmed ? Colors.green[600] : Colors.orange[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
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
                            onPressed: () =>
                                setState(() => _rating = index + 1),
                            icon: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              size: 44,
                              color: index < _rating
                                  ? (_rating == 1
                                        ? Colors.red
                                        : (_rating == 5
                                              ? Colors.green
                                              : Colors.amber))
                                  : AppTheme.textSecondary,
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
                          borderSide: BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Done button with skip option
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
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_rating > 0 && !_isSubmitting)
                            ? _submitRating
                            : null,
                        child: _isSubmitting
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _rating > 0 ? 'Submit Rating' : 'Select a Rating',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
                      child: TextButton(
                        onPressed: _isSubmitting ? null : _skipRating,
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildFareRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }




}
