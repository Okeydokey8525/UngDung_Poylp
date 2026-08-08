import 'package:app_polyp/features/auth/auth_models.dart';

enum AuthStatus {
  checking,
  unauthenticated,
  authenticating,
  authenticated,
  failure,
}

class AuthState {
  const AuthState._({
    required this.status,
    this.user,
    this.message,
    this.fieldErrors = const {},
    this.requestId,
    this.emailHint,
    this.bootstrapFailure = false,
  });

  const AuthState.checking() : this._(status: AuthStatus.checking);

  const AuthState.unauthenticated({String? message, String? emailHint})
    : this._(
        status: AuthStatus.unauthenticated,
        message: message,
        emailHint: emailHint,
      );

  const AuthState.authenticating({String? emailHint})
    : this._(status: AuthStatus.authenticating, emailHint: emailHint);

  const AuthState.authenticated(AuthUser user)
    : this._(status: AuthStatus.authenticated, user: user);

  const AuthState.failure({
    required String message,
    Map<String, String> fieldErrors = const {},
    String? requestId,
    String? emailHint,
    bool bootstrapFailure = false,
  }) : this._(
         status: AuthStatus.failure,
         message: message,
         fieldErrors: fieldErrors,
         requestId: requestId,
         emailHint: emailHint,
         bootstrapFailure: bootstrapFailure,
       );

  final AuthStatus status;
  final AuthUser? user;
  final String? message;
  final Map<String, String> fieldErrors;
  final String? requestId;
  final String? emailHint;
  final bool bootstrapFailure;

  bool get isBusy =>
      status == AuthStatus.checking || status == AuthStatus.authenticating;
}
