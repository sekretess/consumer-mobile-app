import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/business_dto.dart';
import '../../data/services/business_service.dart';
import '../../core/di/injection.dart';

class BusinessInfoBottomSheet extends StatefulWidget {
  final BusinessDto business;
  final VoidCallback onSubscriptionChanged;

  const BusinessInfoBottomSheet({
    super.key,
    required this.business,
    required this.onSubscriptionChanged,
  });

  @override
  State<BusinessInfoBottomSheet> createState() => _BusinessInfoBottomSheetState();
}

class _BusinessInfoBottomSheetState extends State<BusinessInfoBottomSheet> {
  late bool _isSubscribed;
  late bool _vibrationEnabled;
  late bool _soundAlertsEnabled;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isSubscribed = widget.business.subscribed;
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final vibrationKey = 'vibration_${widget.business.name}';
    final soundKey = 'sound_alerts_${widget.business.name}';
    
    setState(() {
      _vibrationEnabled = prefs.getBool(vibrationKey) ?? true;
      _soundAlertsEnabled = prefs.getBool(soundKey) ?? true;
    });
  }

  Future<void> _toggleSubscription(bool value) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    final businessId = widget.business.businessId;
    if (businessId == null) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing business id')),
        );
      }
      return;
    }

    try {
      final businessService = getIt<BusinessService>();
      bool success;

      if (value) {
        success = await businessService.subscribeToBusiness(businessId);
      } else {
        success = await businessService.unsubscribeFromBusiness(businessId);
      }

      if (success && mounted) {
        setState(() {
          _isSubscribed = value;
          _isLoading = false;
        });
        widget.onSubscriptionChanged();
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to ${value ? "subscribe" : "unsubscribe"}')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleVibration(bool value) async {
    setState(() {
      _vibrationEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_${widget.business.name}', value);
  }

  Future<void> _toggleSoundAlerts(bool value) async {
    setState(() {
      _soundAlertsEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_alerts_${widget.business.name}', value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Business Icon and Name
          Row(
            children: [
              _buildBusinessIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.business.displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Subscription Toggle
          _buildSwitchTile(
            title: 'Subscription',
            subtitle: _isSubscribed ? 'Subscribed to this business' : 'Not subscribed',
            value: _isSubscribed,
            onChanged: _isLoading ? null : _toggleSubscription,
          ),
          
          const Divider(),
          
          // Vibration Toggle
          _buildSwitchTile(
            title: 'Vibration',
            subtitle: 'Vibrate when receiving messages',
            value: _vibrationEnabled,
            onChanged: _toggleVibration,
          ),
          
          const Divider(),
          
          // Sound Alerts Toggle
          _buildSwitchTile(
            title: 'Sound Alerts',
            subtitle: 'Play sound when receiving messages',
            value: _soundAlertsEnabled,
            onChanged: _toggleSoundAlerts,
          ),
          
          // Reserve space for the keyboard (viewInsets) AND the system
          // navigation bar (viewPadding.bottom) so the last row isn't hidden
          // behind the system toolbar on gesture/3-button-nav devices.
          SizedBox(
            height: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).viewPadding.bottom,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildBusinessIcon() {
    if (widget.business.icon != null && widget.business.icon!.isNotEmpty) {
      try {
        final imageBytes = base64Decode(widget.business.icon!);
        return ClipOval(
          child: Image.memory(
            imageBytes,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildPlaceholder();
            },
          ),
        );
      } catch (e) {
        // If decoding fails, show placeholder
      }
    }
    
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: Icon(
        Icons.business,
        color: Colors.grey[600],
        size: 35,
      ),
    );
  }
}
