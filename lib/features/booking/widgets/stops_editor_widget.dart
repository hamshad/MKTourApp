import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/config/api_config.dart';
import '../../../core/services/places_service.dart';
import '../../../core/theme.dart';

/// One intermediate stop being composed at booking time.
class BookingStop {
  final TextEditingController controller;
  String? address;
  double? lat;
  double? lng;
  String? placeId;

  BookingStop({String? initialText})
      : controller = TextEditingController(text: initialText ?? '');

  bool get isComplete =>
      address != null && address!.isNotEmpty && lat != null && lng != null;

  Map<String, dynamic> toApiMap(int order) => {
        'stopOrder': order,
        'address': address ?? controller.text,
        'coordinates': [lng ?? 0.0, lat ?? 0.0],
      };

  void dispose() => controller.dispose();
}

/// Intermediate-stops editor for booking (max 3 stops).
///
/// Each row shows an order badge (1..n), an address field with autocomplete
/// (reusing the [PlacesService] search + place-details pattern from
/// destination search), and a remove button. Completed stops are emitted via
/// [onChanged] as API-shaped maps (`stopOrder`, `address`, `coordinates`)
/// ready for fare-estimate and createRide.
class StopsEditorWidget extends StatefulWidget {
  final List<Map<String, dynamic>>? initialStops;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final int maxStops;

  const StopsEditorWidget({
    super.key,
    this.initialStops,
    required this.onChanged,
    this.maxStops = 3,
  });

  @override
  State<StopsEditorWidget> createState() => _StopsEditorWidgetState();
}

class _StopsEditorWidgetState extends State<StopsEditorWidget> {
  final PlacesService _placesService = PlacesService();
  final List<BookingStop> _stops = [];
  final Map<int, List<Map<String, dynamic>>> _suggestions = {};
  final Map<int, bool> _searching = {};
  final Map<int, Timer?> _debounce = {};
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStops ?? [];
    for (final raw in initial.take(widget.maxStops)) {
      final stop = BookingStop(initialText: raw['address']?.toString() ?? '');
      stop.address = raw['address']?.toString();
      final coords = raw['coordinates'];
      if (coords is List && coords.length >= 2) {
        stop.lng = (coords[0] as num?)?.toDouble();
        stop.lat = (coords[1] as num?)?.toDouble();
      }
      _stops.add(stop);
    }
  }

  @override
  void dispose() {
    for (final stop in _stops) {
      stop.dispose();
    }
    for (final timer in _debounce.values) {
      timer?.cancel();
    }
    super.dispose();
  }

  void _emitChanged() {
    final apiStops = <Map<String, dynamic>>[];
    for (var i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      if (stop.isComplete) {
        apiStops.add(stop.toApiMap(i + 1));
      }
    }
    widget.onChanged(apiStops);
  }

  void _addStop() {
    if (_stops.length >= widget.maxStops) return;
    setState(() => _stops.add(BookingStop()));
  }

  void _removeStop(int index) {
    setState(() {
      _stops[index].dispose();
      _stops.removeAt(index);
      _suggestions.remove(index);
      _searching.remove(index);
      _debounce[index]?.cancel();
      _debounce.remove(index);
    });
    _emitChanged();
  }

  void _onSearchChanged(int index, String query) {
    _debounce[index]?.cancel();
    if (query.isEmpty) {
      setState(() {
        _suggestions[index] = [];
        _searching[index] = false;
      });
      return;
    }
    _sessionToken ??= ApiConfig.generateSessionToken();
    _debounce[index] = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching[index] = true);
      final results = await _placesService.searchPlaces(
        query,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      setState(() {
        _suggestions[index] = results;
        _searching[index] = false;
      });
    });
  }

  Future<void> _selectSuggestion(
    int index,
    Map<String, dynamic> suggestion,
  ) async {
    final placeId = suggestion['place_id']?.toString() ?? '';
    final fallbackName = suggestion['description']?.toString() ?? '';
    setState(() => _searching[index] = true);
    final details = await _placesService.getPlaceDetails(
      placeId,
      sessionToken: _sessionToken,
    );
    _sessionToken = null;
    if (!mounted) return;
    setState(() {
      _searching[index] = false;
      _suggestions[index] = [];
      final stop = _stops[index];
      if (details != null) {
        stop.address =
            details['formatted_address']?.toString().isNotEmpty == true
                ? details['formatted_address'].toString()
                : fallbackName;
        stop.controller.text = stop.address ?? fallbackName;
        stop.lat = (details['lat'] as num?)?.toDouble();
        stop.lng = (details['lng'] as num?)?.toDouble();
        stop.placeId = details['place_id']?.toString();
      } else {
        stop.address = fallbackName;
        stop.controller.text = fallbackName;
      }
    });
    _emitChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.add_location_alt_outlined,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Add stops',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(up to ${widget.maxStops})',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const Spacer(),
            if (_stops.length < widget.maxStops)
              TextButton.icon(
                onPressed: _addStop,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add stop'),
              ),
          ],
        ),
        if (_stops.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'No stops — direct trip. Add up to 3 intermediate stops.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
        ..._stops.asMap().entries.map((entry) {
          final index = entry.key;
          final stop = entry.value;
          return _buildStopRow(index, stop);
        }),
      ],
    );
  }

  Widget _buildStopRow(int index, BookingStop stop) {
    final suggestions = _suggestions[index] ?? [];
    final searching = _searching[index] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              // Order badge 1..n
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: stop.controller,
                  onChanged: (value) {
                    stop.address = null;
                    stop.lat = null;
                    stop.lng = null;
                    _onSearchChanged(index, value);
                    _emitChanged();
                  },
                  decoration: InputDecoration(
                    hintText: 'Stop ${index + 1} address',
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : stop.isComplete
                            ? const Icon(
                                Icons.check_circle,
                                color: AppTheme.successColor,
                                size: 20,
                              )
                            : null,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _removeStop(index),
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: AppTheme.errorColor,
                ),
                tooltip: 'Remove stop',
              ),
            ],
          ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 36, top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppTheme.borderColor),
                itemBuilder: (context, i) {
                  final s = suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    title: Text(
                      s['main_text']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      s['secondary_text']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectSuggestion(index, s),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
