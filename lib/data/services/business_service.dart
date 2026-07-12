import 'package:injectable/injectable.dart';

import '../models/business_dto.dart';
import '../../core/network/api_client.dart';

abstract class IBusinessService {
  Future<List<BusinessDto>> getBusinesses();
  Future<List<String>> getSubscribedBusinesses();
  Future<bool> subscribeToBusiness(String businessId);
  Future<bool> unsubscribeFromBusiness(String businessId);
}

@lazySingleton
class BusinessService implements IBusinessService {
  final ApiClient _apiClient;

  BusinessService(this._apiClient);

  @override
  Future<List<BusinessDto>> getBusinesses() async {
    return await _apiClient.getBusinesses();
  }

  @override
  Future<List<String>> getSubscribedBusinesses() async {
    return await _apiClient.getSubscribedBusinesses();
  }

  @override
  Future<bool> subscribeToBusiness(String businessId) async {
    return await _apiClient.subscribeToBusiness(businessId);
  }

  @override
  Future<bool> unsubscribeFromBusiness(String businessId) async {
    return await _apiClient.unsubscribeFromBusiness(businessId);
  }
}
