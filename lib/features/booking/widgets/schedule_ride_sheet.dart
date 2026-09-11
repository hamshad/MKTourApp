import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';

/// Structured payload returned when a scheduled ride is confirmed.
class SchedulePayload {
  /// ISO 8601 pickup time in UTC.
  final String pickupTime;

  /// Selected payment method slug (payment_link, cash).
  final String paymentMethod;

  /// Optional pre-booking note for the driver.
  final String? note;

  /// Intermediate stops (max 3), each with coordinates and address.
  final List<Map<String, dynamic>> stops;

  const SchedulePayload({
    required this.pickupTime,
    required this.paymentMethod,
    this.note,
    this.stops = const [],
  });
}

/// Bottom sheet for selecting a scheduled ride date/time and optional note.
///
/// Enforces a minimum lead time (5 minutes in dev, 2 hours in prod)
/// and maximum of 30 days from now.
/// Returns a [SchedulePayload] via [onSchedule] callback.
class ScheduleRideSheet extends StatefulWidget {
  final DateTime initialDateTime;
  final List<Map<String, dynamic>> stops;
  final String paymentMethod;
  final void Function(SchedulePayload payload) onSchedule;

  const ScheduleRideSheet({
    super.key,
    required this.initialDateTime,
    this.stops = const [],
    this.paymentMethod = 'cash',
    required this.onSchedule,
  });

  @override
  State<ScheduleRideSheet> createState() => _ScheduleRideSheetState();
}

class _ScheduleRideSheetState extends State<ScheduleRideSheet> {
  late DateTime _selectedDateTime;
  final TextEditingController _notesController = TextEditingController();
  late String _selectedPaymentMethod;

  /// Minimum pickup time: 5 minutes in dev (testing), 2 hours in prod
  /// (backend constraint).
  DateTime get _minimumScheduleTime => DateTime.now().add(
        AppConstants.isDev
            ? const Duration(minutes: 5)
            : const Duration(hours: 2),
      );

  /// Human-readable minimum lead time for hint/error copy.
  String get _minLeadLabel =>
      AppConstants.isDev ? '5 minutes' : '2 hours';

  /// Maximum pickup time: 30 days from now (backend constraint).
  DateTime get _maximumScheduleTime =>
      DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _selectedDateTime = widget.initialDateTime;
    _selectedPaymentMethod = widget.paymentMethod;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _showNativePicker({
    required CupertinoDatePickerMode mode,
    required DateTime initialDateTime,
    required Function(DateTime) onChanged,
    DateTime? minimumDate,
    DateTime? maximumDate,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 320,
        padding: const EdgeInsets.only(top: 6.0),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            // Header with Cancel/Done
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
                border: Border(
                  bottom: BorderSide(
                    color: CupertinoColors.separator.resolveFrom(context),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Cancel', style: TextStyle(color: CupertinoColors.systemRed)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    mode == CupertinoDatePickerMode.date ? 'Select Date' : 'Select Time',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: CupertinoColors.label,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text('Done', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Picker
            Expanded(
              child: CupertinoDatePicker(
                mode: mode,
                initialDateTime: initialDateTime,
                minimumDate: minimumDate,
                maximumDate: maximumDate,
                use24hFormat: false,
                onDateTimeChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    _showNativePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _selectedDateTime,
      minimumDate: now,
      maximumDate: _maximumScheduleTime,
      onChanged: (picked) {
        setState(() {
          _selectedDateTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _selectedDateTime.hour,
            _selectedDateTime.minute,
          );
        });
      },
    );
  }

  Future<void> _pickTime() async {
    _showNativePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: _selectedDateTime,
      onChanged: (picked) {
        setState(() {
          _selectedDateTime = DateTime(
            _selectedDateTime.year,
            _selectedDateTime.month,
            _selectedDateTime.day,
            picked.hour,
            picked.minute,
          );
        });
      },
    );
  }

  bool get _isValid {
    return !_selectedDateTime.isBefore(_minimumScheduleTime);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Schedule for Later',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pickup must be $_minLeadLabel to 30 days from now',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // Date picker row
          _buildPickerTile(
            icon: Icons.calendar_today,
            label: DateFormat('EEE, MMM dd yyyy').format(_selectedDateTime),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),

          // Time picker row
          _buildPickerTile(
            icon: Icons.access_time,
            label: DateFormat('h:mm a').format(_selectedDateTime),
            onTap: _pickTime,
          ),
          const SizedBox(height: 20),

          // Note field
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a note for your driver (optional)',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),

          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Pickup must be between $_minLeadLabel and 30 days from now',
                style: TextStyle(fontSize: 12, color: Colors.red[600]),
              ),
            ),

          // Payment method selector
          Text(
            'Payment Method',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPaymentOption(
                  icon: Icons.link,
                  label: 'Payment Link',
                  value: 'payment_link',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPaymentOption(
                  icon: Icons.money,
                  label: 'Cash',
                  value: 'cash',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isValid
                  ? () {
                      Navigator.pop(context);
                      widget.onSchedule(
                        SchedulePayload(
                          pickupTime: _selectedDateTime.toUtc().toIso8601String(),
                          paymentMethod: _selectedPaymentMethod,
                          note: _notesController.text.isNotEmpty
                              ? _notesController.text
                              : null,
                          stops: widget.stops,
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _selectedPaymentMethod == 'cash'
                    ? 'Confirm Booking'
                    : 'Pay & Confirm Booking',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.primaryColor : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
