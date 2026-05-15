import '../errors/failure.dart';

/// Centralized validation utilities for authentication
class AuthValidators {
  AuthValidators._();

  /// Email validation regex pattern
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Password strength regex patterns
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasNumbers = RegExp(r'\d');
  static final RegExp _hasSpecialCharacters = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

  /// Name validation regex (allows letters, spaces, hyphens, and apostrophes)
  static final RegExp _nameRegex = RegExp(r"^[a-zA-Z\s\-']+$");

  /// Phone number validation regex (E.164: optional '+' followed by 7-15 digits)
  static final RegExp _phoneRegex = RegExp(r'^\+?[1-9]\d{6,14}$');

  /// Validates email format
  static ValidationFailure? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return ValidationFailure.requiredField.copyWith(
        message: 'Email is required',
        details: 'Please enter your email address.',
      );
    }

    final trimmedEmail = email.trim();
    
    if (!_emailRegex.hasMatch(trimmedEmail)) {
      return ValidationFailure.invalidEmail;
    }

    if (trimmedEmail.length > 254) {
      return ValidationFailure(
        message: 'Email address is too long',
        details: 'Email address should not exceed 254 characters.',
        timestamp: DateTime.now(),
      );
    }

    return null;
  }

  /// Validates password strength
  static ValidationFailure? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return ValidationFailure.requiredField.copyWith(
        message: 'Password is required',
        details: 'Please enter your password.',
      );
    }

    if (password.length < 8) {
      return ValidationFailure.invalidPassword;
    }

    if (password.length > 128) {
      return ValidationFailure(
        message: 'Password is too long',
        details: 'Password should not exceed 128 characters.',
        timestamp: DateTime.now(),
      );
    }

    // Check for common weak passwords
    final commonPasswords = [
      '12345678', 'password', '123456789', 'qwerty123',
      'abc123456', 'password123', '11111111', '00000000',
    ];

    if (commonPasswords.contains(password.toLowerCase())) {
      return ValidationFailure.weakPassword.copyWith(
        details: 'This password is too common. Please use a unique password.',
      );
    }

    return null;
  }

  /// Validates password strength (stricter requirements)
  static ValidationFailure? validatePasswordStrength(String? password) {
    final basicValidation = validatePassword(password);
    if (basicValidation != null) return basicValidation;

    if (password!.length < 12) {
      return ValidationFailure(
        message: 'Password should be at least 12 characters long',
        details: 'For better security, use a password with 12 or more characters.',
        timestamp: DateTime.now(),
      );
    }

    if (!_hasUppercase.hasMatch(password)) {
      return ValidationFailure.weakPassword.copyWith(
        details: 'Password should contain at least one uppercase letter.',
      );
    }

    if (!_hasLowercase.hasMatch(password)) {
      return ValidationFailure.weakPassword.copyWith(
        details: 'Password should contain at least one lowercase letter.',
      );
    }

    if (!_hasNumbers.hasMatch(password)) {
      return ValidationFailure.weakPassword.copyWith(
        details: 'Password should contain at least one number.',
      );
    }

    if (!_hasSpecialCharacters.hasMatch(password)) {
      return ValidationFailure.weakPassword.copyWith(
        details: 'Password should contain at least one special character.',
      );
    }

    return null;
  }

  /// Validates password confirmation
  static ValidationFailure? validatePasswordConfirmation(
    String? password,
    String? confirmPassword,
  ) {
    if (confirmPassword == null || confirmPassword.isEmpty) {
      return ValidationFailure.requiredField.copyWith(
        message: 'Password confirmation is required',
        details: 'Please confirm your password.',
      );
    }

    if (password != confirmPassword) {
      return ValidationFailure.passwordMismatch;
    }

    return null;
  }

  /// Validates user's name
  static ValidationFailure? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return ValidationFailure.requiredField.copyWith(
        message: 'Name is required',
        details: 'Please enter your name.',
      );
    }

    final trimmedName = name.trim();

    if (trimmedName.length < 2) {
      return ValidationFailure.invalidName.copyWith(
        details: 'Name should be at least 2 characters long.',
      );
    }

    if (trimmedName.length > 50) {
      return ValidationFailure(
        message: 'Name is too long',
        details: 'Name should not exceed 50 characters.',
        timestamp: DateTime.now(),
      );
    }

    if (!_nameRegex.hasMatch(trimmedName)) {
      return ValidationFailure(
        message: 'Name contains invalid characters',
        details: 'Name should only contain letters, spaces, hyphens, and apostrophes.',
        timestamp: DateTime.now(),
      );
    }

    // Check for consecutive special characters
    if (trimmedName.contains('--') || 
        trimmedName.contains("''") || 
        trimmedName.contains('  ')) {
      return ValidationFailure(
        message: 'Invalid name format',
        details: 'Name should not contain consecutive special characters or spaces.',
        timestamp: DateTime.now(),
      );
    }

    // Check if name starts or ends with special characters
    if (trimmedName.startsWith(' ') || 
        trimmedName.endsWith(' ') ||
        trimmedName.startsWith('-') || 
        trimmedName.endsWith('-') ||
        trimmedName.startsWith("'") || 
        trimmedName.endsWith("'")) {
      return ValidationFailure(
        message: 'Invalid name format',
        details: 'Name should not start or end with spaces or special characters.',
        timestamp: DateTime.now(),
      );
    }

    return null;
  }

  /// Validates a phone number in E.164 format.
  ///
  /// Strips spaces, hyphens, and parentheses before checking, so common
  /// human-entered formats like `+1 (555) 123-4567` are accepted.
  static ValidationFailure? validatePhoneNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return ValidationFailure.requiredField.copyWith(
        message: 'Phone number is required',
        details: 'Please enter your phone number.',
      );
    }

    final normalized = phone.replaceAll(RegExp(r'[\s\-()]'), '');

    if (!_phoneRegex.hasMatch(normalized)) {
      return ValidationFailure(
        message: 'Invalid phone number',
        details: 'Please enter a valid phone number in international format.',
        timestamp: DateTime.now(),
      );
    }

    return null;
  }

  /// Validates complete sign up form
  static Map<String, ValidationFailure> validateSignUpForm({
    required String? email,
    required String? password,
    required String? confirmPassword,
    required String? name,
    bool enforceStrongPassword = false,
  }) {
    final errors = <String, ValidationFailure>{};

    final emailError = validateEmail(email);
    if (emailError != null) errors['email'] = emailError;

    final passwordError = enforceStrongPassword
        ? validatePasswordStrength(password)
        : validatePassword(password);
    if (passwordError != null) errors['password'] = passwordError;

    final confirmPasswordError = validatePasswordConfirmation(password, confirmPassword);
    if (confirmPasswordError != null) errors['confirmPassword'] = confirmPasswordError;

    final nameError = validateName(name);
    if (nameError != null) errors['name'] = nameError;

    return errors;
  }

  /// Validates sign in form
  static Map<String, ValidationFailure> validateSignInForm({
    required String? email,
    required String? password,
  }) {
    final errors = <String, ValidationFailure>{};

    final emailError = validateEmail(email);
    if (emailError != null) errors['email'] = emailError;

    if (password == null || password.isEmpty) {
      errors['password'] = ValidationFailure.requiredField.copyWith(
        message: 'Password is required',
        details: 'Please enter your password.',
      );
    }

    return errors;
  }

  /// Validates reset password form
  static Map<String, ValidationFailure> validateResetPasswordForm({
    required String? email,
  }) {
    final errors = <String, ValidationFailure>{};

    final emailError = validateEmail(email);
    if (emailError != null) errors['email'] = emailError;

    return errors;
  }

  /// Validates new password form (for password reset)
  static Map<String, ValidationFailure> validateNewPasswordForm({
    required String? newPassword,
    required String? confirmPassword,
    bool enforceStrongPassword = true,
  }) {
    final errors = <String, ValidationFailure>{};

    final passwordError = enforceStrongPassword
        ? validatePasswordStrength(newPassword)
        : validatePassword(newPassword);
    if (passwordError != null) errors['newPassword'] = passwordError;

    final confirmPasswordError = validatePasswordConfirmation(newPassword, confirmPassword);
    if (confirmPasswordError != null) errors['confirmPassword'] = confirmPasswordError;

    return errors;
  }

  /// Calculates password strength score (0-100)
  static int calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0;

    int score = 0;

    // Length points
    if (password.length >= 8) score += 20;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;

    // Character diversity points
    if (_hasLowercase.hasMatch(password)) score += 15;
    if (_hasUppercase.hasMatch(password)) score += 15;
    if (_hasNumbers.hasMatch(password)) score += 15;
    if (_hasSpecialCharacters.hasMatch(password)) score += 15;

    // Avoid common patterns
    if (!password.contains('123') && !password.contains('abc')) score += 5;
    if (!password.toLowerCase().contains('password')) score += 5;

    return score.clamp(0, 100);
  }

  /// Gets password strength label
  static String getPasswordStrengthLabel(int score) {
    if (score < 30) return 'Weak';
    if (score < 60) return 'Fair';
    if (score < 80) return 'Good';
    return 'Strong';
  }

  /// Sanitizes input by trimming and removing potentially harmful characters
  static String sanitizeInput(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[<>"`;]'), '') // Remove potentially harmful characters
        .replaceAll(RegExp(r'\s+'), ' '); // Replace multiple spaces with single space
  }

  /// Validates that required fields are not empty
  static Map<String, ValidationFailure> validateRequiredFields(
    Map<String, String?> fields,
  ) {
    final errors = <String, ValidationFailure>{};

    for (final entry in fields.entries) {
      if (entry.value == null || entry.value!.trim().isEmpty) {
        errors[entry.key] = ValidationFailure.requiredField.copyWith(
          message: '${_capitalizeFirst(entry.key)} is required',
          details: 'Please enter your ${entry.key}.',
        );
      }
    }

    return errors;
  }

  /// Helper method to capitalize first letter
  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}