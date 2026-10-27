/// Shared test doubles for the Flutter client tests.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_task_manager/core/storage/token_store.dart';

/// In-memory token store that records saved tokens.
class FakeTokenStore extends TokenStore {
  /// Creates a fake store seeded with an optional token pair.
  FakeTokenStore({String? accessToken, String? refreshToken})
      : _access = accessToken,
        _refresh = refreshToken,
        super(const FlutterSecureStorage());

  String? _access;
  String? _refresh;

  /// Last access token passed to [saveTokens].
  String? savedAccessToken;

  /// Last refresh token passed to [saveTokens].
  String? savedRefreshToken;

  /// Whether [clear] was called.
  bool cleared = false;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _access = savedAccessToken = accessToken;
    _refresh = savedRefreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    cleared = true;
  }
}
