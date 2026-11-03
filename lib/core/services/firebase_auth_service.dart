import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// Firebase Auth Service for DIU Rides
/// Provides Firebase email code sending, verification, and authentication.
class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check current Firebase user
  static User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Send verification email code / link to student email
  static Future<bool> sendEmailVerification({required String email}) async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('[Firebase Auth] Verification email dispatched to $email');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Firebase Auth] sendEmailVerification error: $e');
      return false;
    }
  }

  /// Check if student email has been verified via Firebase link/code
  static Future<bool> isEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      await user.reload();
      final updated = _auth.currentUser;
      return updated?.emailVerified ?? false;
    } catch (e) {
      debugPrint('[Firebase Auth] isEmailVerified check error: $e');
      return false;
    }
  }

  /// Sign up or sign in with student email, then dispatch Firebase verification email
  static Future<bool> dispatchVerificationEmail({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential? cred;
      try {
        cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          debugPrint('[Firebase Auth] Account already exists in Firebase, signing in to send verification email');
          try {
            cred = await _auth.signInWithEmailAndPassword(
              email: email.trim(),
              password: password.trim(),
            );
          } catch (siErr) {
            debugPrint('[Firebase Auth] Sign in note: $siErr');
          }
        } else {
          debugPrint('[Firebase Auth] Create user code: ${authErr.code} - ${authErr.message}');
        }
      } catch (e) {
        debugPrint('[Firebase Auth] Non-firebase note during create: $e');
      }

      final user = cred?.user ?? _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('[Firebase Auth] Student verification email sent to $email');
        return true;
      }
      return user?.emailVerified ?? false;
    } catch (e) {
      debugPrint('[Firebase Auth] dispatchVerificationEmail note: $e');
      return false;
    }
  }

  /// Sign in with student email and password via Firebase Auth
  static Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      debugPrint('[Firebase Auth] Successfully verified credentials for $email');
      return cred;
    } catch (e) {
      debugPrint('[Firebase Auth] signInWithEmailAndPassword note: $e');
      return null;
    }
  }

  /// Send Firebase password reset email to Gmail
  static Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      debugPrint('[Firebase Auth] Password reset email dispatched to $email');
      return true;
    } catch (e) {
      debugPrint('[Firebase Auth] sendPasswordResetEmail error: $e');
      return false;
    }
  }

  /// Launch Gmail inbox or DIU webmail in browser or app
  static Future<bool> openGmailInbox({String? email}) async {
    try {
      final gmailUrl = email != null && email.endsWith('@diu.edu.bd')
          ? 'https://mail.google.com/a/diu.edu.bd'
          : 'https://mail.google.com';
      final uri = Uri.parse(gmailUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('[Firebase Auth] openGmailInbox error: $e');
      return false;
    }
  }

  /// Sign out
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[Firebase Auth] signOut error: $e');
    }
  }
}
