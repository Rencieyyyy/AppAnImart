import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloudinary_function.dart';
import 'friendly_error.dart';
import 'legal.dart';
import 'liveness_check.dart';
import 'login.dart';
import 'main.dart';
import 'services/location_service.dart';
import 'widgets/city_picker.dart';
import 'widgets/top_message.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // Step 1 - Personal
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Step 2 - Address. The city/municipality comes from the searchable PH
  // gazetteer picker (with coordinates), not a free-text box.
  PhCity? _selectedCity;
  final TextEditingController _houseController = TextEditingController();

  // Step 3 - Security & ID
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _retypePasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureRetypePassword = true;
  bool _agreedToTerms = false;

  // ID upload state. Stored as in-memory bytes (not a dart:io File) so it
  // works on every platform including Flutter Web.
  Uint8List? _validIdBytes;
  String? _validIdName;
  String? _selectedIdType;

  // Face verification state — captured right after ID upload, instead of
  // at final submit. Holds the 4 pose photos (center/right/left/down).
  LivenessResult? _livenessResult;

  static const List<String> _idTypes = [
    'Philippine Passport',
    'Driver\'s License',
    'SSS ID',
    'PhilHealth ID',
    'Postal ID',
    'Voter\'s ID',
    'PRC ID',
    'Senior Citizen ID',
    'UMID',
    'National ID (PhilSys)',
    'Barangay ID',
    'School ID',
  ];

  final ImagePicker _picker = ImagePicker();

  int _currentStep = 1;
  bool _isSubmitting = false;

  static const Color mint = Color(0xFF91E6C1);
  static const Color dark = Color(0xFF1F2937);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _houseController.dispose();
    _passwordController.dispose();
    _retypePasswordController.dispose();
    super.dispose();
  }

  // ── Image Picker ──────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _validIdBytes = bytes;
          _validIdName = picked.name;
        });
      }
    } catch (e) {
      if (mounted) {
        showTopMessage(
          context,
          'Could not access ${source == ImageSource.camera ? 'camera' : 'gallery'}. Please check permissions.',
        );
      }
    }
  }

  void _showIdSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Upload Valid ID',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose how you want to provide your ID photo.',
                style: TextStyle(fontSize: 13, color: Colors.black45),
              ),
              const SizedBox(height: 20),
              // Camera option
              _SourceTile(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                subtitle: 'Use your camera to capture your ID',
                color: mint,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 12),
              // Gallery option
              _SourceTile(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                subtitle: 'Select an existing photo of your ID',
                color: const Color(0xFFB8E8FF),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_validIdBytes != null) ...[
                const SizedBox(height: 12),
                _SourceTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove Photo',
                  subtitle: 'Clear the current ID image',
                  color: const Color(0xFFFFD6D6),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _validIdBytes = null;
                      _validIdName = null;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showIdTypePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select ID Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  itemCount: _idTypes.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.black.withOpacity(0.08)),
                  itemBuilder: (_, i) {
                    final idType = _idTypes[i];
                    final isSelected = _selectedIdType == idType;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(
                        idType,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? const Color(0xFF2D7A57) : Colors.black87,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: mint, size: 22)
                          : null,
                      onTap: () {
                        setState(() => _selectedIdType = idType);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Face Verification ─────────────────────────────────────
  /// Launches the face-liveness screen (center → right → left → down,
  /// GCash-style) so we can confirm the person signing up is actually
  /// present. Triggered right after the ID upload, not at final submit.
  Future<void> _verifyFace() async {
    final result = await Navigator.push<LivenessResult?>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessCheckPage()),
    );

    if (result == null) {
      if (mounted) {
        _showSnack('Face verification was not completed. Please try again.');
      }
      return;
    }

    if (mounted) {
      setState(() => _livenessResult = result);
      _showSnack('Face verified!', color: const Color(0xFF4CAF7D));
    }
  }

  // ── Validation per step ───────────────────────────────────

  static final RegExp _emailRe =
      RegExp(r'^[\w.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

  /// Accepts Philippine mobile numbers: 09XXXXXXXXX or +639XXXXXXXXX
  /// (spaces and dashes are ignored).
  static bool _isValidPhPhone(String input) {
    final digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(digits);
  }

  String? _validateCurrentStep() {
    switch (_currentStep) {
      case 1:
        if (_nameController.text.trim().isEmpty) return 'Please enter your name.';
        final email = _emailController.text.trim();
        if (email.isEmpty) return 'Please enter your email.';
        if (!_emailRe.hasMatch(email)) return 'Please enter a valid email address.';
        final phone = _phoneController.text.trim();
        if (phone.isEmpty) return 'Please enter your phone number.';
        if (!_isValidPhPhone(phone)) {
          return 'Please enter a valid PH mobile number (09XXXXXXXXX).';
        }
        return null;
      case 2:
        if (_selectedCity == null) return 'Please select your city/municipality.';
        if (_houseController.text.trim().isEmpty) return 'Please enter your house/street/unit/lot number.';
        return null;
      case 3:
        final password = _passwordController.text;
        if (password.isEmpty) return 'Please enter a password.';
        if (password.length < 8) return 'Password must be at least 8 characters.';
        if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
            !RegExp(r'[0-9]').hasMatch(password)) {
          return 'Password must contain at least one letter and one number.';
        }
        if (_retypePasswordController.text.isEmpty) return 'Please retype your password.';
        if (password != _retypePasswordController.text) return 'Passwords do not match.';
        if (_selectedIdType == null) return 'Please select the type of your valid ID.';
        if (_validIdBytes == null) return 'Please upload a photo of your valid ID.';
        if (_livenessResult == null) return 'Please complete face verification.';
        if (!_agreedToTerms) return 'Please agree to the Terms and Conditions.';
        return null;
    }
    return null;
  }

  void _showSnack(String message, {Color color = Colors.redAccent}) {
    showTopMessage(
      context,
      message,
      isError: color == Colors.redAccent,
      backgroundColor: color,
    );
  }

  Future<void> _onContinue() async {
    final error = _validateCurrentStep();
    if (error != null) {
      _showSnack(error);
      return;
    }
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      // Face verification already happened earlier in step 3 (right after
      // ID upload) — just submit using the stored result.
      await _submitRegistration(_livenessResult!);
    }
  }

  Future<void> _submitRegistration(LivenessResult liveness) async {
    setState(() => _isSubmitting = true);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final city = _selectedCity;
    final address = city?.label ?? '';
    final houseNumber = _houseController.text.trim();
    try {
      // 1) Upload the valid-ID photo, main selfie, and all pose photos to
      //    their own Cloudinary folders first (no auth needed), so their
      //    URLs can travel in the sign-up metadata below.
      String? validIdUrl;
      if (_validIdBytes != null) {
        try {
          validIdUrl = await uploadToCloudinary(
            _validIdBytes!,
            _validIdName ?? 'valid_id_${DateTime.now().millisecondsSinceEpoch}.jpg',
            folder: 'sign ups(animart)',
          );
        } catch (e) {
          debugPrint('Valid ID upload failed: $e');
        }
      }

      // Main selfie (final "down" pose) — kept for backward compatibility.
      String? selfieUrl;
      try {
        selfieUrl = await uploadToCloudinary(
          liveness.selfie,
          'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'sign ups(animart)/selfies',
        );
      } catch (e) {
        debugPrint('Selfie upload failed: $e');
      }

      // All 4 pose photos (center/right/left/down) for stronger verification.
      final Map<String, String> verificationUrls = {};
      for (final entry in liveness.poseImages.entries) {
        try {
          final url = await uploadToCloudinary(
            entry.value,
            '${entry.key}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            folder: 'liveness',
          );
          if (url != null) {
            verificationUrls[entry.key] = url; // only assign non-null
          }
        } catch (e) {
          debugPrint('${entry.key} pose upload failed: $e');
        }
      }

      // 2) Create the Auth user. A database trigger creates the matching row
      //    in `users` from this metadata (which bypasses RLS and works even
      //    when email confirmation is on, so there's no client write here).
      //    `valid_id_url` / `id_type` / `selfie_url` / `verification_photos`
      //    are backfilled into that row on the user's first login, when a
      //    session is guaranteed to exist.
      final res = await supabase.auth.signUp(
        email: email,
        password: _passwordController.text,
        data: {
          'name': name,
          'phone': phone,
          'address': address,
          'house_number': houseNumber,
          'id_type': _selectedIdType,
          'valid_id_url': validIdUrl,
          'selfie_url': selfieUrl,
          'verification_photos': verificationUrls, // {center,right,left,down}
          // Coordinates for "Explore near you" — backfilled into the users
          // row on first login (see backfillLocationFromMetadata).
          'location_name': city?.label,
          'latitude': city?.lat,
          'longitude': city?.lng,
        },
      );

      if (res.user == null) {
        if (mounted) _showSnack('Could not create your account. Please try again.');
        return;
      }

      if (!mounted) return;

      if (res.session != null) {
        // Email confirmation is disabled — user is signed in immediately.
        _showSnack('Account created!', color: const Color(0xFF4CAF7D));
      } else {
        // Email confirmation is enabled — prompt the user to verify.
        _showSnack(
          'Account created! Please check your email to confirm, then log in.',
          color: const Color(0xFF4CAF7D),
        );
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    } on AuthException catch (e) {
      if (mounted) {
        _showSnack(friendlyAuthError(e,
            action: 'signup',
            fallback: 'Could not create your account. Please try again.'));
      }
    } catch (e) {
      if (mounted) _showSnack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Logo Box ──────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  'images/animartLOGO.png',
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    size: 60,
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _StepIndicator(currentStep: _currentStep),
              ),

              const SizedBox(height: 28),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _buildStepContent(),
              ),

              const SizedBox(height: 28),

              // ── Buttons ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          if (_currentStep > 1) {
                            setState(() => _currentStep--);
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: Colors.black26),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mint,
                          foregroundColor: dark,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: dark,
                                ),
                              )
                            : Text(
                                _currentStep < 3 ? 'Continue' : 'Create Account',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4CAF7D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return Column(
          children: [
            _buildField(controller: _nameController, hint: 'Name', keyboardType: TextInputType.name),
            const SizedBox(height: 14),
            _buildField(controller: _emailController, hint: 'Email', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _buildField(
              controller: _phoneController,
              hint: 'Phone (09XXXXXXXXX)',
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
            ),
          ],
        );

      case 2:
        return Column(
          children: [
            // Searchable city/municipality dropdown (all PH locations).
            GestureDetector(
              onTap: () async {
                final city = await showCityPicker(
                  context,
                  selectedLabel: _selectedCity?.label,
                  title: 'Your Address',
                  subtitle: 'Search and select your city or municipality.',
                );
                if (city != null && mounted) {
                  setState(() => _selectedCity = city);
                }
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFA8DFC8),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Colors.black45, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedCity?.label ?? 'Select City / Municipality',
                        style: TextStyle(
                          color: _selectedCity != null
                              ? Colors.black87
                              : Colors.black45,
                          fontSize: 14,
                          fontWeight: _selectedCity != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.black45, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildField(controller: _houseController, hint: 'House No./Street/Unit/Lot No.'),
          ],
        );

      case 3:
        return Column(
          children: [
            _buildPasswordField(
              controller: _passwordController,
              hint: 'Password',
              obscure: _obscurePassword,
              onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            const SizedBox(height: 14),
            _buildPasswordField(
              controller: _retypePasswordController,
              hint: 'Retype Password',
              obscure: _obscureRetypePassword,
              onToggle: () => setState(() => _obscureRetypePassword = !_obscureRetypePassword),
            ),

            const SizedBox(height: 14),

            // ── ID Type Selector ──────────────────────────
            GestureDetector(
              onTap: _showIdTypePicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFA8DFC8),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined, color: Colors.black45, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedIdType ?? 'Select ID Type',
                        style: TextStyle(
                          color: _selectedIdType != null ? Colors.black87 : Colors.black45,
                          fontSize: 14,
                          fontWeight: _selectedIdType != null ? FontWeight.w600 : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45, size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── ID Photo Upload ───────────────────────────
            GestureDetector(
              onTap: _showIdSourcePicker,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFA8DFC8),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: _validIdBytes != null
                    ? Stack(
                        children: [
                          // Preview image
                          Image.memory(
                            _validIdBytes!,
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                          ),
                          // Overlay badge
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Change Photo',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.camera_alt_outlined, color: Colors.black45, size: 20),
                            const SizedBox(width: 12),
                            const Text(
                              'Upload Valid ID Photo',
                              style: TextStyle(color: Colors.black45, fontSize: 14),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Required',
                                style: TextStyle(fontSize: 11, color: Colors.black45),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Face Verification (right after ID upload) ────
            GestureDetector(
              onTap: _verifyFace,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _livenessResult != null
                      ? const Color(0xFFD4F5E4)
                      : const Color(0xFFA8DFC8),
                  borderRadius: BorderRadius.circular(20),
                  border: _livenessResult != null
                      ? Border.all(color: const Color(0xFF4CAF7D), width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _livenessResult != null
                          ? Icons.check_circle_rounded
                          : Icons.face_retouching_natural_rounded,
                      color: _livenessResult != null
                          ? const Color(0xFF4CAF7D)
                          : Colors.black45,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _livenessResult != null
                                ? 'Face Verified'
                                : 'Verify Your Face',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _livenessResult != null
                                  ? const Color(0xFF2D7A57)
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            _livenessResult != null
                                ? 'Tap to redo the scan'
                                : 'Quick face scan to confirm it\'s really you',
                            style: const TextStyle(fontSize: 11, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                    if (_livenessResult == null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Required',
                          style: TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Terms Checkbox ────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                  activeColor: mint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'I agree to the ',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TermsAndPrivacyPage()),
                          );
                        },
                        child: const Text(
                          'Terms and Conditions & Privacy Policy',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4CAF7D),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF4CAF7D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black45, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFA8DFC8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black45, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFA8DFC8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.black45,
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}

// ── Source Tile (reusable bottom sheet option) ────────────
class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF1F2937), size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepCircle(number: 1, label: 'Personal', isActive: currentStep >= 1, isDone: currentStep > 1),
        _StepLine(isActive: currentStep >= 2),
        _StepCircle(number: 2, label: 'Address', isActive: currentStep >= 2, isDone: currentStep > 2),
        _StepLine(isActive: currentStep >= 3),
        _StepCircle(number: 3, label: 'Security & ID', isActive: currentStep >= 3, isDone: false),
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int number;
  final String label;
  final bool isActive;
  final bool isDone;

  const _StepCircle({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFF91E6C1) : const Color(0xFFD1D5DB),
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, size: 16, color: Color(0xFF1F2937))
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isActive ? const Color(0xFF1F2937) : Colors.white,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool isActive;
  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 18),
        color: isActive ? const Color(0xFF91E6C1) : const Color(0xFFD1D5DB),
      ),
    );
  }
}