import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DriverActivityScreen extends StatelessWidget {
  const DriverActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildDateHeader('Today'),
          _buildRideCard(
            context,
            'Heathrow Terminal 5',
            '10:30 AM',
            '£24.50',
            'Completed',
            Colors.green,
          ),
          _buildRideCard(
            context,
            'The Shard',
            '09:15 AM',
            '£18.20',
            'Completed',
            Colors.green,
          ),
          _buildRideCard(
            context,
            'Oxford Street',
            '08:45 AM',
            '£12.50',
            'Completed',
            Colors.green,
          ),
          
          const SizedBox(height: 24),
          _buildDateHeader('Yesterday'),
          _buildRideCard(
            context,
            'King\'s Cross Station',
            '05:30 PM',
            '£15.00',
            'Completed',
            Colors.green,
          ),
          _buildRideCard(
            context,
            'Hyde Park',
            '02:15 PM',
            '£0.00',
            'Cancelled',
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        date,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildRideCard(
    BuildContext context,
    String destination,
    String time,
    String amount,
    String status,
    Color statusColor,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context, 
          '/driver-ride-detail',
          arguments: {
            'destination': destination,
            'time': time,
            'amount': amount,
            'status': status,
          },
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
