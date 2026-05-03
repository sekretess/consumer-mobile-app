// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:consumer_flutter_app/core/di/app_module.dart' as _i349;
import 'package:consumer_flutter_app/core/network/api_client.dart' as _i838;
import 'package:consumer_flutter_app/core/network/websocket_service.dart'
    as _i30;
import 'package:consumer_flutter_app/data/repositories/auth_repository.dart'
    as _i549;
import 'package:consumer_flutter_app/data/repositories/message_repository.dart'
    as _i45;
import 'package:consumer_flutter_app/data/services/api_bridge_service.dart'
    as _i498;
import 'package:consumer_flutter_app/data/services/business_service.dart'
    as _i347;
import 'package:consumer_flutter_app/data/services/cryptographic_service.dart'
    as _i629;
import 'package:consumer_flutter_app/data/services/file_service.dart' as _i724;
import 'package:consumer_flutter_app/data/services/message_service.dart'
    as _i951;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final appModule = _$AppModule();
    await gh.singletonAsync<_i460.SharedPreferences>(
      () => appModule.sharedPreferences,
      preResolve: true,
    );
    gh.lazySingleton<_i838.ApiClient>(() => _i838.ApiClient());
    gh.lazySingleton<_i45.MessageRepository>(() => _i45.MessageRepository());
    gh.lazySingleton<_i629.CryptographicService>(
        () => _i629.CryptographicService());
    gh.lazySingleton<_i498.ApiBridgeService>(
        () => _i498.ApiBridgeService(gh<_i838.ApiClient>()));
    gh.lazySingleton<_i724.FileService>(
        () => _i724.FileService(gh<_i838.ApiClient>()));
    gh.lazySingleton<_i347.BusinessService>(
        () => _i347.BusinessService(gh<_i838.ApiClient>()));
    gh.lazySingleton<_i549.AuthRepository>(() => _i549.AuthRepository(
          gh<_i838.ApiClient>(),
          gh<_i460.SharedPreferences>(),
          gh<_i629.ICryptographicService>(),
        ));
    gh.lazySingleton<_i951.MessageService>(() => _i951.MessageService(
          gh<_i45.MessageRepository>(),
          gh<_i549.AuthRepository>(),
          gh<_i629.CryptographicService>(),
          gh<_i724.FileService>(),
        ));
    gh.lazySingleton<_i30.WebSocketService>(() => _i30.WebSocketService(
          gh<_i549.AuthRepository>(),
          gh<_i951.MessageService>(),
        ));
    return this;
  }
}

class _$AppModule extends _i349.AppModule {}
