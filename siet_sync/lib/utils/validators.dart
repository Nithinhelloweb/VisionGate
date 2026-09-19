class Validators {
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 50;
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 100;

  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    final trimmed = value.trim();
    if (trimmed.length < minUsernameLength) {
      return 'Username must be at least $minUsernameLength characters';
    }
    if (trimmed.length > maxUsernameLength) {
      return 'Username must be less than $maxUsernameLength characters';
    }
    final usernameRegex = RegExp(r'^[a-zA-Z0-9._-]+$');
    if (!usernameRegex.hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, dots, underscores, and hyphens';
    }
    return null;
  }

  static String? validatePassword(String? value, {bool isRequired = true}) {
    if (value == null || value.isEmpty) {
      return isRequired ? 'Password is required' : null;
    }
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    if (value.length > maxPasswordLength) {
      return 'Password must be less than $maxPasswordLength characters';
    }
    return null;
  }

  static String? validateName(
    String? value, {
    String fieldName = 'Name',
    bool isRequired = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? '$fieldName is required' : null;
    }
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return '$fieldName must be at least 2 characters';
    }
    if (trimmed.length > 100) {
      return '$fieldName must be less than 100 characters';
    }
    return null;
  }

  static String? validateRegNo(String? value, {bool isRequired = true}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Registration number is required' : null;
    }
    final trimmed = value.trim().toUpperCase();
    if (trimmed.length < 5) {
      return 'Registration number seems invalid';
    }
    if (trimmed.length > 20) {
      return 'Registration number is too long';
    }
    return null;
  }
}

class CredentialValidator {
  final String? usernameError;
  final String? passwordError;
  final bool isValid;

  CredentialValidator({this.usernameError, this.passwordError})
    : isValid = usernameError == null && passwordError == null;

  factory CredentialValidator.validate(
    String? username,
    String? password, {
    bool requirePassword = true,
  }) {
    return CredentialValidator(
      usernameError: Validators.validateUsername(username),
      passwordError: Validators.validatePassword(
        password,
        isRequired: requirePassword,
      ),
    );
  }
}
