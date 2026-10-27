/// Tracks whether the user is signed in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Authentication status of the application.
enum AuthStatus {
  /// Stored credentials are still being checked.
  unknown,

  /// No valid session; the login screen is shown.
  signedOut,

  /// A session exists; the task screen is shown.
  signedIn,
}

/// Signs users in and out and reacts to session expiration.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    Future.microtask(_restore);
    return AuthStatus.unknown;
  }

  Future<void> _restore() async {
    final hasSession = await ref.read(authRepositoryProvider).hasSession();
    state = hasSession ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  /// Logs in with [email] and [password]; throws on failure.
  Future<void> login(String email, String password) async {
    await ref.read(authRepositoryProvider).login(email, password);
    state = AuthStatus.signedIn;
  }

  /// Registers with [email] and [password]; throws on failure.
  Future<void> register(String email, String password) async {
    await ref.read(authRepositoryProvider).register(email, password);
    state = AuthStatus.signedIn;
  }

  /// Revokes the session on the server and clears local tokens.
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = AuthStatus.signedOut;
  }

  /// Called by the API client when a refresh fails.
  void sessionExpired() => state = AuthStatus.signedOut;
}

/// Global authentication state.
final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
