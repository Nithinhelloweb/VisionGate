import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import '../services/session_service.dart';
import '../utils/validators.dart';
import '../utils/vpn_check.dart';
import '../utils/api_response_utils.dart';
import 'admin_panel.dart';
import 'hod_panel.dart';
import 'staff_panel.dart';
import 'other_staff_login.dart';
import 'student_panel.dart';
import '../widgets/face_registration_widget.dart';

String get API_URL => CollegeIPConfig.defaultURL;

class AppColors {
  static const Color orange = Color(0xFF6366F1); // Modernized Indigo
  static const Color orangePaleDark = Color(0xFF1E1B4B); // Deep Indigo
  static const Color orangeLight = Color(0xFF818CF8);
  static const Color orangePale = Color(0xFFEEF2F6);
  static const Color yellow = Color(0xFFEC4899); // Modernized Pink/Magenta
  static const Color yellowPaleDark = Color(0xFF3B0764); // Deep Purple
  static const Color yellowLight = Color(0xFFF472B6);
  static const Color yellowPale = Color(0xFFFDF2F8);
  static const Color green = Color(0xFF10B981); // Emerald Green
  static const Color greenLight = Color(0xFF34D399);
  static const Color greenPale = Color(0xFFECFDF5);
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMedium = Color(0xFF475569);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textDarkGrey = Color(0xFF94A3B8);
}

class FloatingParticle {
  double x;
  double y;
  double size;
  double speedX;
  double speedY;
  Color color;

  FloatingParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.color,
  });
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool isLoading = true;
  String errorMsg = '';
  bool rememberMe = false;
  bool _obscurePassword = true;
  late AnimationController _fadeController;
  late AnimationController _particleController;
  late Animation<double> _fadeAnimation;
  List<FloatingParticle> _particles = [];
  final Random _random = Random();

  List<Map<String, String>> get servers =>
      CollegeIPConfig.getServersForDropdown();

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkExistingSession();
    _checkVpnStatus();
  }

  Future<void> _checkVpnStatus() async {
    final vpnError = await VpnChecker.validateVpnStatus();
    if (vpnError != null && mounted) {
      setState(() => errorMsg = vpnError);
    }
  }

  Future<void> _checkExistingSession() async {
    final session = await sessionService.getSession();
    if (session != null) {
      _navigateToDashboard(session.token, session.user, session.role);
    } else {
      setState(() => isLoading = false);
    }
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();

    _particleController = AnimationController(
      duration: const Duration(seconds: 28),
      vsync: this,
    )..addListener(_updateParticles);

    _initParticles();
    _particleController.repeat();
  }

  void _initParticles() {
    _particles = List.generate(25, (index) {
      final colorChoice = _random.nextInt(3);
      Color particleColor;
      switch (colorChoice) {
        case 0:
          particleColor = AppColors.orange;
          break;
        case 1:
          particleColor = const Color.fromARGB(255, 200, 182, 19);
          break;
        default:
          particleColor = AppColors.green;
      }

      return FloatingParticle(
        x: _random.nextDouble() * 500,
        y: _random.nextDouble() * 800,
        size: _random.nextDouble() * 8 + 4,
        speedX: (_random.nextDouble() - 0.5) * 1.5,
        speedY: (_random.nextDouble() - 0.5) * 1.5,
        color: particleColor.withOpacity(_random.nextDouble() * 0.3 + 0.15),
      );
    });
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      for (var particle in _particles) {
        particle.x += particle.speedX;
        particle.y += particle.speedY;
        if (particle.x < 0 || particle.x > 500) particle.speedX *= -1;
        if (particle.y < 0 || particle.y > 800) particle.speedY *= -1;
      }
    });
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    _fadeController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final usernameError = Validators.validateUsername(usernameCtrl.text);
    if (usernameError != null) {
      setState(() => errorMsg = usernameError);
      return;
    }

    final passwordError = Validators.validatePassword(passwordCtrl.text);
    if (passwordError != null) {
      setState(() => errorMsg = passwordError);
      return;
    }

    // Check for VPN
    final vpnError = await VpnChecker.validateVpnStatus();
    if (vpnError != null) {
      setState(() => errorMsg = vpnError);
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
    });

    try {
      final deviceSessionId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      final response = await http.post(
        Uri.parse('$API_URL/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameCtrl.text,
          'password': passwordCtrl.text,
          'device_id': deviceSessionId,
        }),
      );

      if (response.statusCode == 200) {
        final data = ApiResponseUtils.tryParseJson(response.body);
        if (data == null) {
          setState(
            () => errorMsg =
                'Login failed: invalid server response. Please verify backend URL/server status.',
          );
          return;
        }
        final user = data['user'];
        final role = user['role']?.toString().toLowerCase() ?? '';

        await sessionService.saveSession(
          SessionData(
            token: data['token'],
            user: user,
            role: role,
            loginTime: DateTime.now(),
            deviceSessionId: deviceSessionId,
          ),
        );

        _navigateToDashboard(data['token'], user, role);
      } else {
        final parsed = ApiResponseUtils.tryParseJson(response.body);
        final serverMessage =
            parsed?['detail'] ??
            parsed?['message'] ??
            parsed?['error'] ??
            ApiResponseUtils.nonJsonErrorMessage(
              response.statusCode,
              response.body,
            );
        setState(() => errorMsg = serverMessage ?? 'Login failed');
      }
    } catch (e) {
      setState(() => errorMsg = ApiResponseUtils.sanitize(e));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _navigateToDashboard(
    String token,
    Map<String, dynamic> user,
    String role,
  ) {
    if (role == 'student') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StudentDashboardPage(token: token, user: user),
        ),
      );
    } else if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminDashboardPage(token: token, user: user),
        ),
      );
    } else if (role == 'hod') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HODDashboardPage(token: token, user: user),
        ),
      );
    } else if (role == 'staff') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StaffDashboardPage(token: token, user: user),
        ),
      );
    } else if ([
      'principal',
      'placement_staff',
      'placement',
      'lab_technician',
      'lab_tech',
      'labtech',
      'system_admin',
      'systemadmin',
      'office_staff',
      'vice_chancellor',
      'director',
      'dean',
    ].contains(role)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              OtherStaffDashboardPage(token: token, user: user),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              GeneralUserDashboardPage(token: token, user: user),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 850;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;

    return Scaffold(
      body: Stack(
        children: [
          // Moving Animated Background
          Positioned.fill(
            child: Container(
              color: bgColor,
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _AnimatedBackgroundPainter(
                      animationValue: _particleController.value,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
          ),
          // Main Login Content
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: isDesktop
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Container(
                          width: size.width * 0.90, // 90% width on Desktop
                          height: (size.height * 0.88).clamp(580, 780),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFE2E8F0),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.25 : 0.08),
                                blurRadius: 40,
                                spreadRadius: -4,
                                offset: const Offset(0, 20),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildLeftHeroPanel(isDark),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    color: cardColor,
                                    child: Center(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 460),
                                          child: _buildRightFormPanel(isDark, false),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: cardColor,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMobileTopHeroHeader(isDark),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 440),
                                  child: _buildRightFormPanel(isDark, true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftHeroPanel(bool isDark) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3730A3),
            Color(0xFF4F46E5),
            Color(0xFF6366F1),
            Color(0xFF7C3AED),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 32,
            left: 32,
            child: SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(
                painter: _DotGridPainter(
                  color: Colors.white.withValues(alpha: 0.35),
                  rows: 4,
                  cols: 4,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 36,
            right: 36,
            child: SizedBox(
              width: 80,
              height: 80,
              child: CustomPaint(
                painter: _DotGridPainter(
                  color: Colors.white.withValues(alpha: 0.35),
                  rows: 5,
                  cols: 5,
                ),
              ),
            ),
          ),
          Positioned(
            right: -70,
            top: 30,
            bottom: 30,
            child: Container(
              width: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Attendance\nfor a Smarter Future',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    letterSpacing: -0.6,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'VisionGate helps institutions automate attendance with speed, precision, and ease.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopHeroHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFFEEF2FF),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFFF1F5F9), const Color(0xFFFFFFFF)]
              : [const Color(0xFFEEF2FF), Colors.white],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 8,
            child: SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(
                painter: _DotGridPainter(
                  color: isDark
                      ? const Color(0xFF4F46E5).withValues(alpha: 0.2)
                      : const Color(0xFF6366F1).withValues(alpha: 0.35),
                  rows: 4,
                  cols: 4,
                ),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              height: 180, // BIG LOGO FOR MOBILE VIEW
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.school_rounded,
                  size: 110,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightFormPanel(bool isDark, bool isMobile) {
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final textSecondaryColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final fieldBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final fieldBorder = isDark ? Colors.white12 : Colors.grey.withValues(alpha: 0.25);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!isMobile) ...[
          Container(
            padding: isDark
                ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                : EdgeInsets.zero,
            decoration: isDark
                ? BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  )
                : null,
            child: SizedBox(
              height: 220, // MUCH LARGER LOGO FOR DESKTOP RIGHT PANEL
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.school_rounded,
                  size: 130,
                  color: Color(0xFF6366F1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

          Text(
            'Welcome Back',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to continue to VisionGate',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 30),

          TextFormField(
            controller: usernameCtrl,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(Validators.maxUsernameLength),
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
            onChanged: (value) {
              final trimmed = value.trimRight();
              if (value != trimmed) {
                usernameCtrl.text = trimmed;
                usernameCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: trimmed.length),
                );
              }
            },
            decoration: InputDecoration(
              labelText: 'Username / Reg No',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 22, color: Color(0xFF6366F1)),
              filled: true,
              fillColor: fieldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
              labelStyle: TextStyle(color: textSecondaryColor, fontSize: 16),
              floatingLabelStyle: const TextStyle(color: Color(0xFF6366F1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: passwordCtrl,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(Validators.maxPasswordLength),
            ],
            onChanged: (value) {
              final trimmed = value.trimRight();
              if (value != trimmed) {
                passwordCtrl.text = trimmed;
                passwordCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: trimmed.length),
                );
              }
            },
            onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22, color: Color(0xFF6366F1)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 22,
                  color: Colors.grey[500],
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: fieldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
              labelStyle: TextStyle(color: textSecondaryColor, fontSize: 16),
              floatingLabelStyle: const TextStyle(color: Color(0xFF6366F1), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),

          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _showForgotPasswordDialog,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (errorMsg.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMsg,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(
            width: double.infinity,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: isLoading
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)],
                      ),
                boxShadow: isLoading
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
          ),
        ],
      );
    }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 10),
            Text('Forgot Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Please contact your institution administrator or HOD to reset your password or recover your account.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  final int rows;
  final int cols;
  _DotGridPainter({required this.color, this.rows = 4, this.cols = 4});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    double spacingX = cols > 1 ? size.width / (cols - 1) : 0;
    double spacingY = rows > 1 ? size.height / (rows - 1) : 0;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawCircle(Offset(c * spacingX, r * spacingY), 2.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rows != rows || oldDelegate.cols != cols;
}

class GeneralUserDashboardPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const GeneralUserDashboardPage({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<GeneralUserDashboardPage> createState() =>
      _GeneralUserDashboardPageState();
}

class _GeneralUserDashboardPageState extends State<GeneralUserDashboardPage> {
  int _selectedIndex = 0;
  bool _isRegistered = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFaceStatus();
  }

  Future<void> _checkFaceStatus() async {
    final role = widget.user['role']?.toString() ?? '';
    final isOtherStaff = [
      'principal',
      'placement_staff',
      'lab_technician',
      'system_admin',
      'office_staff',
    ].contains(role.toLowerCase());

    try {
      final url = isOtherStaff
          ? "$API_URL/other_staff/face/status"
          : "$API_URL/face/status/${widget.user['regNo']}";
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isRegistered = data['face_registered'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _logout() {
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user['role']?.toString() ?? 'User';
    final displayRole = role
        .replaceAll('custom_', '')
        .replaceAll('_', ' ')
        .toUpperCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userAccent = Colors.teal;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$displayRole Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7),
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
        leading: Builder(
          builder: (context) => Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                Icons.menu,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                Icons.logout,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _logout,
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: userAccent))
          : _selectedIndex == 0
          ? _buildDashboard()
          : _buildFaceRegistration(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        indicatorColor: userAccent.withValues(alpha: 0.2),
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.dashboard_outlined,
              color: isDark ? Colors.white : Colors.black,
            ),
            selectedIcon: Icon(Icons.dashboard, color: userAccent),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.face_outlined,
              color: isDark ? Colors.white : Colors.black,
            ),
            selectedIcon: Icon(Icons.face, color: userAccent),
            label: 'My Face',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = widget.user['role']?.toString() ?? 'User';
    final displayRole = role
        .replaceAll('custom_', '')
        .replaceAll('_', ' ')
        .toUpperCase();

    return Drawer(
      child: Container(
        color: isDark ? const Color(0xFF000000) : Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)]
                      : [Colors.teal, const Color(0xFF26A69A)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.school,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayRole,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user['name'] ?? 'User',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dashboard,
                  color: Colors.teal,
                  size: 22,
                ),
              ),
              title: Text(
                'Dashboard',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.grey.shade700,
                ),
              ),
              selected: _selectedIndex == 0,
              selectedTileColor: Colors.teal.withValues(alpha: 0.1),
              onTap: () {
                setState(() => _selectedIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_isRegistered ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isRegistered ? Icons.check_circle : Icons.face,
                  color: _isRegistered ? Colors.green : Colors.orange,
                  size: 22,
                ),
              ),
              title: Text(
                _isRegistered ? 'Face Registered' : 'Register Face',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.grey.shade700,
                ),
              ),
              selected: _selectedIndex == 1,
              selectedTileColor: Colors.teal.withValues(alpha: 0.1),
              onTap: () {
                setState(() => _selectedIndex = 1);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3D1A1A)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.logout,
                    color: Colors.red.shade400,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _logout,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = widget.user['role']?.toString() ?? 'User';
    final displayRole = role
        .replaceAll('custom_', '')
        .replaceAll('_', ' ')
        .toUpperCase();
    final userAccent = Colors.teal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)]
                    : [userAccent, const Color(0xFF26A69A)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: userAccent.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.waving_hand,
                        color: Colors.white,
                        size: isSmallScreen ? 24 : 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back,',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          Text(
                            widget.user['name'] ?? 'User',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 18 : 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.badge,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: isSmallScreen ? 16 : 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          displayRole,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: isSmallScreen ? 11 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                decoration: BoxDecoration(
                  color: userAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: userAccent,
                  size: isSmallScreen ? 18 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxGridWidth = isSmallScreen ? double.infinity : 520.0;
              return Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: min(constraints.maxWidth, maxGridWidth),
                  ),
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: isSmallScreen ? 1.15 : 1.1,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildActionCard(
                        icon: _isRegistered ? Icons.check_circle : Icons.face,
                        title: _isRegistered
                            ? 'Face Registered'
                            : 'Register Face',
                        color: _isRegistered ? Colors.green : Colors.orange,
                        onTap: () => setState(() => _selectedIndex = 1),
                      ),
                      _buildActionCard(
                        icon: Icons.logout,
                        title: 'Logout',
                        color: Colors.red,
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: userAccent.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: userAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: userAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.info,
                        color: userAccent,
                        size: isSmallScreen ? 18 : 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Important Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: userAccent,
                          fontSize: isSmallScreen ? 13 : 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '• Register your face to mark attendance\n• Make sure you are in good lighting\n• Look at the camera when marking attendance',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[700],
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w500, color: color),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceRegistration() {
    final role = widget.user['role']?.toString() ?? '';
    final isOtherStaff = [
      'principal',
      'placement_staff',
      'lab_technician',
      'system_admin',
      'office_staff',
    ].contains(role.toLowerCase());
    final registerEndpoint = isOtherStaff
        ? '/other_staff/face/register'
        : '/admin/face/register';

    return SingleChildScrollView(
      child: FaceRegistrationWidget(
        token: widget.token,
        role: widget.user['role'] ?? 'staff',
        initialRegNo: widget.user['regNo'],
        initialName: widget.user['name'],
        initialDept: widget.user['dept'],
        registerEndpoint: registerEndpoint,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Face registered successfully!')),
          );
          _checkFaceStatus();
        },
      ),
    );
  }
}

class _AnimatedBackgroundPainter extends CustomPainter {
  final double animationValue;
  final bool isDark;

  _AnimatedBackgroundPainter({
    required this.animationValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double t = animationValue * 2 * pi;
    final double maxDimension = max(size.width, size.height);

    // Aura 1: Bold Royal Indigo Glow (Top-Left to Top-Border)
    final double g1X = size.width * 0.15 + sin(t) * (size.width * 0.28);
    final double g1Y = size.height * 0.15 + cos(t * 0.7) * (size.height * 0.22);
    final double r1 = maxDimension * 0.58 + sin(t * 1.3) * 70;
    final Paint p1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.58 : 0.40),
          const Color(0xFF6366F1).withValues(alpha: isDark ? 0.32 : 0.20),
          const Color(0xFF312E81).withValues(alpha: isDark ? 0.12 : 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(g1X, g1Y), radius: r1));
    canvas.drawCircle(Offset(g1X, g1Y), r1, p1);

    // Aura 2: Vibrant Electric Violet & Magenta (Bottom-Right to Right-Border)
    final double g2X = size.width * 0.85 + cos(t * 0.8) * (size.width * 0.25);
    final double g2Y = size.height * 0.85 + sin(t * 1.1) * (size.height * 0.25);
    final double r2 = maxDimension * 0.62 + cos(t * 1.2) * 75;
    final Paint p2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF9333EA).withValues(alpha: isDark ? 0.52 : 0.36),
          const Color(0xFFA855F7).withValues(alpha: isDark ? 0.28 : 0.18),
          const Color(0xFFC084FC).withValues(alpha: isDark ? 0.10 : 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.42, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(g2X, g2Y), radius: r2));
    canvas.drawCircle(Offset(g2X, g2Y), r2, p2);

    // Aura 3: Bright Electric Cyan & Sky Blue (Top-Right to Upper-Border)
    final double g3X = size.width * 0.85 + sin(t * 1.2) * (size.width * 0.22);
    final double g3Y = size.height * 0.15 + cos(t * 0.9) * (size.height * 0.22);
    final double r3 = maxDimension * 0.52 + sin(t * 0.8) * 55;
    final Paint p3 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: isDark ? 0.48 : 0.32),
          const Color(0xFF38BDF8).withValues(alpha: isDark ? 0.22 : 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(g3X, g3Y), radius: r3));
    canvas.drawCircle(Offset(g3X, g3Y), r3, p3);

    // Aura 4: Vivid Neon Rose & Deep Purple (Bottom-Left to Left-Border)
    final double g4X = size.width * 0.15 + cos(t * 0.6) * (size.width * 0.22);
    final double g4Y = size.height * 0.85 + sin(t * 0.7) * (size.height * 0.22);
    final double r4 = maxDimension * 0.54 + sin(t * 1.4) * 50;
    final Paint p4 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD946EF).withValues(alpha: isDark ? 0.45 : 0.28),
          const Color(0xFF7E22CE).withValues(alpha: isDark ? 0.20 : 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(g4X, g4Y), radius: r4));
    canvas.drawCircle(Offset(g4X, g4Y), r4, p4);
  }

  @override
  bool shouldRepaint(covariant _AnimatedBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.isDark != isDark;
  }
}

