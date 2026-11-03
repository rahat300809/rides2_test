import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/features/auth/data/repositories/mock_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DIU Ride - Auth Validators Tests', () {
    test('validateLoginIdentifier accepts both DIU Student ID and DIU Email', () {
      expect(Validators.validateLoginIdentifier('201-15-14285'), isNull);
      expect(Validators.validateLoginIdentifier('student@diu.edu.bd'), isNull);
      expect(Validators.validateLoginIdentifier('211-16-0987'), isNull);
      expect(Validators.validateLoginIdentifier('shakib15-14285@diu.edu.bd'), isNull);

      // Invalid inputs
      expect(Validators.validateLoginIdentifier(''), isNotNull);
      expect(Validators.validateLoginIdentifier('student@gmail.com'), isNotNull);
      expect(Validators.validateLoginIdentifier('123'), isNotNull);
    });

    test('validatePassword enforces minimum 6 characters', () {
      expect(Validators.validatePassword('password123'), isNull);
      expect(Validators.validatePassword('diu123'), isNull);
      expect(Validators.validatePassword('12345'), isNotNull);
      expect(Validators.validatePassword(''), isNotNull);
      expect(Validators.validatePassword(null), isNotNull);
    });

    test('validateConfirmPassword ensures matching passwords', () {
      expect(Validators.validateConfirmPassword('password123', 'password123'), isNull);
      expect(Validators.validateConfirmPassword('mismatch', 'password123'), isNotNull);
      expect(Validators.validateConfirmPassword('', 'password123'), isNotNull);
    });

    test('getDepartmentName and getBatchName extract correct DIU info from ID', () {
      expect(Validators.getDepartmentName('201-15-14285'), contains('CSE'));
      expect(Validators.getDepartmentName('211-16-9999'), contains('SWE'));
      expect(Validators.getDepartmentName('221-11-5555'), contains('EEE'));
      expect(Validators.getDepartmentName('231-25-1111'), contains('BBA'));

      expect(Validators.getBatchName('201-15-14285'), equals('Batch 201'));
      expect(Validators.getBatchName('223-16-1234'), equals('Batch 223'));
    });
  });

  group('DIU Ride - Account Creation & Password Login Flow', () {
    late PreferencesService preferences;
    late MockAuthRepository authRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await PreferencesService.init();
      final secureStorage = SecureStorageService();
      authRepo = MockAuthRepository(
        secureStorage: secureStorage,
        preferences: preferences,
      );
      await preferences.seedDefaultAccounts();
    });

    test('Default demo student account can log in with ID and password', () async {
      final user = await authRepo.loginWithIdAndPassword(
        identifier: '201-15-14285',
        password: 'password123',
      );

      expect(user.studentId, equals('201-15-14285'));
      expect(user.email, equals('student@diu.edu.bd'));
      expect(user.isDiuVerified, isTrue);
    });

    test('Default demo student account can also log in using DIU email and password', () async {
      final user = await authRepo.loginWithIdAndPassword(
        identifier: 'student@diu.edu.bd',
        password: 'password123',
      );

      expect(user.studentId, equals('201-15-14285'));
      expect(user.isDiuVerified, isTrue);
    });

    test('Login throws exception on wrong password', () async {
      expect(
        () => authRepo.loginWithIdAndPassword(
          identifier: '201-15-14285',
          password: 'wrong_password',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('New student registration with DIU email verification flow works end-to-end', () async {
      // 1. Submit Registration Form
      final otp = await authRepo.registerWithDiuEmail(
        name: 'Tanvir Hossain',
        studentId: '221-16-77889',
        email: 'tanvir16-77889@diu.edu.bd',
        phone: '01812345678',
        password: 'securePass123',
      );

      expect(otp, isNotEmpty);
      expect(otp.length, equals(6));

      // 2. Verify with the OTP dispatched to DIU email
      final verifiedUser = await authRepo.verifyAndCompleteRegistration(otp: otp);
      expect(verifiedUser.studentId, equals('221-16-77889'));
      expect(verifiedUser.name, equals('Tanvir Hossain'));
      expect(verifiedUser.department, contains('SWE'));
      expect(verifiedUser.isDiuVerified, isTrue);

      // 3. User can now sign in with their new password
      final loggedInUser = await authRepo.loginWithIdAndPassword(
        identifier: '221-16-77889',
        password: 'securePass123',
      );
      expect(loggedInUser.id, equals(verifiedUser.id));
      expect(loggedInUser.name, equals('Tanvir Hossain'));
    });

    test('Forgot Password flow resets password via DIU email verification code', () async {
      // 1. Request reset code for student
      final resetCode = await authRepo.requestPasswordReset(identifier: '201-15-14285');
      expect(resetCode.length, equals(6));
      expect(preferences.getResolvedResetEmail(), equals('student@diu.edu.bd'));

      // 2. Verify code and update password
      final success = await authRepo.verifyAndResetPassword(
        identifier: '201-15-14285',
        otp: resetCode,
        newPassword: 'myBrandNewPassword99',
      );
      expect(success, isTrue);

      // 3. Log in with the new password
      final user = await authRepo.loginWithIdAndPassword(
        identifier: '201-15-14285',
        password: 'myBrandNewPassword99',
      );
      expect(user.studentId, equals('201-15-14285'));
    });

    test('Forgot Password resolves registered email when given student ID', () async {
      final resetCode = await authRepo.requestPasswordReset(identifier: '201-15-14285');
      expect(resetCode.length, equals(6));
      final resolved = preferences.getResolvedResetEmail();
      expect(resolved, equals('student@diu.edu.bd'));
    });
  });
}
