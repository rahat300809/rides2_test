class Validators {
  Validators._();

  static String? validateStudentId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your DIU Student ID';
    }
    final trimmed = value.trim();
    // Typical DIU ID formats: 201-15-12345, 211-35-987, etc.
    final idRegex = RegExp(r'^\d{3}-\d{2}-\d{3,5}$');
    if (!idRegex.hasMatch(trimmed) && trimmed.length < 8) {
      return 'Valid format: e.g. 201-15-12345';
    }
    return null;
  }

  static String? validateDiuEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your university email';
    }
    final trimmed = value.trim().toLowerCase();
    if (!trimmed.endsWith('@diu.edu.bd')) {
      return 'Email must end with @diu.edu.bd';
    }
    final parts = trimmed.split('@');
    if (parts.length != 2 || parts[0].isEmpty) {
      return 'Please enter a valid DIU student email';
    }
    return null;
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter phone number';
    }
    final trimmed = value.trim().replaceAll(' ', '').replaceAll('-', '');
    final phoneRegex = RegExp(r'^(?:\+88)?01[3-9]\d{8}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Enter a valid 11-digit Bangladeshi mobile number';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String originalPassword) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != originalPassword) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? validateLoginIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your DIU Student ID or Email';
    }
    final trimmed = value.trim();
    if (trimmed.contains('@')) {
      return validateDiuEmail(trimmed);
    }
    return validateStudentId(trimmed);
  }

  static String getDepartmentName(String studentId) {
    final parts = studentId.trim().split('-');
    if (parts.length >= 2) {
      final code = parts[1];
      const deptMap = {
        '15': 'Computer Science & Engineering (CSE)',
        '16': 'Software Engineering (SWE)',
        '11': 'Electrical & Electronic Engineering (EEE)',
        '25': 'Business Administration (BBA)',
        '18': 'Department of Pharmacy',
        '35': 'Department of English',
        '26': 'Civil Engineering (CE)',
        '29': 'Textile Engineering (TE)',
        '34': 'Journalism, Media & Comm (JMC)',
        '41': 'Department of Law',
        '27': 'Architecture',
        '38': 'Environmental Science',
      };
      if (deptMap.containsKey(code)) {
        return deptMap[code]!;
      }
    }
    return 'DIU Department';
  }

  static String getBatchName(String studentId) {
    final parts = studentId.trim().split('-');
    if (parts.isNotEmpty && parts[0].length >= 2) {
      return 'Batch ${parts[0]}';
    }
    return 'DIU Student';
  }

  static String? validateOtp(String? value) {
    if (value == null || value.trim().length < 4 || value.trim().length > 6) {
      return 'Enter valid verification code (4-6 digits)';
    }
    return null;
  }

  static String? validateFare(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please specify fare';
    }
    final amount = double.tryParse(value.trim());
    if (amount == null || amount < 15) {
      return 'Minimum fare is ৳15';
    }
    if (amount > 200) {
      return 'Maximum subsidized peer fare is ৳200';
    }
    return null;
  }

  static String? validateSeats(int? value) {
    if (value == null || value < 1) {
      return 'Must offer at least 1 seat';
    }
    if (value > 12) {
      return 'Cannot exceed 12 seats';
    }
    return null;
  }
}
