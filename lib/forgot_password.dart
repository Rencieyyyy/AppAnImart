import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';
import 'widgets/top_message.dart';

/// Password reset in two steps, all inside the app:
///
///  1. The user enters their email → Supabase emails them a 6-digit
///     recovery code (`resetPasswordForEmail`).
///  2. They type the code + a new password → `verifyOTP` (type: recovery)
///     proves ownership, `updateUser` sets the password, and the temporary
///     session is signed out so they log in normally.
///
/// NOTE: the Supabase "Reset Password" email template must include the
/// `{{ .Token }}` placeholder so the email actually contains the code
/// (Dashboard → Authentication → Email Templates).
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _retypeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureRetype = true;

  // Simple resend cooldown so the button can't be hammered.
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _retypeController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showTopMessage(context, 'Please enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startResendCooldown();
      showTopMessage(
        context,
        'Reset code sent! Check your email (including spam).',
        isError: false,
      );
    } on AuthException catch (e) {
      if (mounted) showTopMessage(context, e.message);
    } catch (_) {
      if (mounted) {
        showTopMessage(context, 'Could not send the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;

    if (code.isEmpty) {
      showTopMessage(context, 'Please enter the code from your email.');
      return;
    }
    if (password.length < 8) {
      showTopMessage(context, 'Password must be at least 8 characters.');
      return;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      showTopMessage(
          context, 'Password must contain at least one letter and one number.');
      return;
    }
    if (password != _retypeController.text) {
      showTopMessage(context, 'Passwords do not match.');
      return;
    }

    setState(() => _busy = true);
    try {
      // The code proves the user owns the email; verifying it opens a
      // temporary session that lets us set the new password.
      await supabase.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: code,
      );
      await supabase.auth.updateUser(UserAttributes(password: password));
      // Sign out the temporary recovery session — the user logs in normally
      // (which also re-runs the admin-approval gate).
      await supabase.auth.signOut();
      if (!mounted) return;
      showTopMessage(
        context,
        'Password updated! You can now log in with your new password.',
        isError: false,
        duration: const Duration(seconds: 4),
      );
      Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) showTopMessage(context, e.message);
    } catch (_) {
      if (mounted) {
        showTopMessage(
            context, 'Could not reset your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black45, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFA8DFC8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      suffixIcon: suffix,
    );
  }

  Widget _toggleEye(bool obscure, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: Colors.black45,
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'Forgot Password',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                _codeSent ? Icons.mark_email_read_outlined : Icons.lock_reset,
                size: 72,
                color: const Color(0xFF4CAF7D),
              ),
              const SizedBox(height: 20),
              Text(
                _codeSent
                    ? 'Enter the 6-digit code we emailed to\n${_emailController.text.trim()}'
                    : 'Enter your account email and we\'ll send you a code to reset your password.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 28),

              if (!_codeSent) ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoration('Email'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _sendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6DBF99),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'SEND RESET CODE',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2),
                          ),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8),
                  decoration: _decoration('Code').copyWith(counterText: ''),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _decoration(
                    'New Password',
                    suffix: _toggleEye(_obscurePassword,
                        () => setState(() => _obscurePassword = !_obscurePassword)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _retypeController,
                  obscureText: _obscureRetype,
                  decoration: _decoration(
                    'Retype New Password',
                    suffix: _toggleEye(_obscureRetype,
                        () => setState(() => _obscureRetype = !_obscureRetype)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6DBF99),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'RESET PASSWORD',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _resendSeconds > 0
                      ? Text(
                          'Resend code in ${_resendSeconds}s',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black45),
                        )
                      : GestureDetector(
                          onTap: _busy ? null : _sendCode,
                          child: const Text(
                            'Resend code',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4CAF7D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
