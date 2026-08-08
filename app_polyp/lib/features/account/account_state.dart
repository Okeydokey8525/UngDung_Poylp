enum AccountOperationStatus { idle, submitting, success, failure }

class AccountOperationState {
  const AccountOperationState({
    this.status = AccountOperationStatus.idle,
    this.message,
    this.fieldErrors = const {},
    this.requestId,
  });

  final AccountOperationStatus status;
  final String? message;
  final Map<String, String> fieldErrors;
  final String? requestId;

  bool get isSubmitting => status == AccountOperationStatus.submitting;
}
