import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../data/models/business_dto.dart';
import '../../data/services/business_service.dart';

final businessServiceProvider = Provider<IBusinessService>((ref) {
  return getIt<BusinessService>();
});

final businessesProvider = FutureProvider<List<BusinessDto>>((ref) async {
  final businessService = ref.watch(businessServiceProvider);
  final businesses = await businessService.getBusinesses();
  final subscribedBusinesses = await businessService.getSubscribedBusinesses();
  
  // Mark which businesses are subscribed
  final subscribedSet = subscribedBusinesses.toSet();
  final businessesWithSubscription = businesses.map((business) {
    return business.copyWith(
      subscribed: subscribedSet.contains(business.businessId),
    );
  }).toList();
  
  // Sort: subscribed first, then add headers
  businessesWithSubscription.sort((a, b) {
    if (a.subscribed && !b.subscribed) return -1;
    if (!a.subscribed && b.subscribed) return 1;
    return 0;
  });
  
  // Add section headers
  final List<BusinessDto> result = [];
  bool lastWasSubscribed = false;
  bool hasSubscribed = false;
  
  for (final business in businessesWithSubscription) {
    if (business.subscribed && !lastWasSubscribed) {
      result.add(const BusinessDto(
        displayName: 'Subscribed',
        name: '__HEADER_SUBSCRIBED__',
        subscribed: true,
        itemType: ItemType.header,
      ));
      hasSubscribed = true;
      lastWasSubscribed = true;
    } else if (!business.subscribed && lastWasSubscribed && hasSubscribed) {
      result.add(const BusinessDto(
        displayName: 'Other Businesses',
        name: '__HEADER_OTHER__',
        subscribed: false,
        itemType: ItemType.header,
      ));
      lastWasSubscribed = false;
    }
    result.add(business.copyWith(itemType: ItemType.item));
  }
  
  return result;
});

final filteredBusinessesProvider = Provider.family<List<BusinessDto>, String>((ref, query) {
  final businessesAsync = ref.watch(businessesProvider);
  
  return businessesAsync.when(
    data: (businesses) {
      if (query.isEmpty) return businesses;
      
      final lowerQuery = query.toLowerCase();
      return businesses.where((business) {
        // Don't filter out headers
        if (business.itemType == ItemType.header) return true;
        return business.name.toLowerCase().contains(lowerQuery) ||
               business.displayName.toLowerCase().contains(lowerQuery);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
