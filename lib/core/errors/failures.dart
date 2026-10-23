/// Base class for strongly typed application failures
abstract class Failure {
  final String message;
  final String? code;

  const Failure(this.message, {this.code});

  @override
  String toString() => '$runtimeType: $message';
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code});
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

class AuthorizationFailure extends Failure {
  const AuthorizationFailure(super.message, {super.code});
}

class StorageUploadFailure extends Failure {
  const StorageUploadFailure(super.message, {super.code});
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.code});
}

class DuplicateSubmissionFailure extends Failure {
  const DuplicateSubmissionFailure(super.message, {super.code});
}
