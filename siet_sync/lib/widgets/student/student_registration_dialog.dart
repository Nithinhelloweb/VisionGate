import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../services/client_face_prefilter.dart';
import 'student_bulk_import_dialog.dart';

class StudentRegistrationDialog extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  final String? initialDept;
  final bool isDeptLocked;
  final Map<String, dynamic>? initialStudent;
  final bool isReEnroll;
  final VoidCallback? onStudentRegistered;

  const StudentRegistrationDialog({
    super.key,
    required this.token,
    required this.user,
    this.initialDept,
    this.isDeptLocked = false,
    this.initialStudent,
    this.isReEnroll = false,
    this.onStudentRegistered,
  });

  static Future<void> show(
    BuildContext context, {
    required String token,
    required Map<String, dynamic> user,
    String? initialDept,
    bool isDeptLocked = false,
    Map<String, dynamic>? initialStudent,
    bool isReEnroll = false,
    VoidCallback? onStudentRegistered,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
          child: StudentRegistrationDialog(
            token: token,
            user: user,
            initialDept: initialDept,
            isDeptLocked: isDeptLocked,
            initialStudent: initialStudent,
            isReEnroll: isReEnroll,
            onStudentRegistered: onStudentRegistered,
          ),
        ),
      ),
    );
  }

  @override
  State<StudentRegistrationDialog> createState() =>
      _StudentRegistrationDialogState();
}

class _StudentRegistrationDialogState extends State<StudentRegistrationDialog> {
  static const Color primaryIndigo = Color(0xFF4F46E5);

  int _currentStep = 0;
  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>();

  // Step 1: Academic Controllers
  final _regNoCtrl = TextEditingController();
  final _rollNoCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _selectedDegree = "B.E.";
  late String _selectedDept;
  String _selectedBatch = "2022-2026";
  int _selectedYear = 3;
  int _selectedSemester = 6;
  String _selectedSection = "A";
  String _selectedQuota = "Govt";
  final _mentorCtrl = TextEditingController();

  // Comprehensive Indian States & Districts mapping (State -> District)
  static const Map<String, List<String>> indianStatesAndDistricts = {
    'Tamil Nadu': [
      'Ariyalur',
      'Chengalpattu',
      'Chennai',
      'Coimbatore',
      'Cuddalore',
      'Dharmapuri',
      'Dindigul',
      'Erode',
      'Kallakurichi',
      'Kanchipuram',
      'Kanyakumari',
      'Karur',
      'Krishnagiri',
      'Madurai',
      'Mayiladuthurai',
      'Nagapattinam',
      'Namakkal',
      'Nilgiris',
      'Perambalur',
      'Pudukkottai',
      'Ramanathapuram',
      'Ranipet',
      'Salem',
      'Sivaganga',
      'Tenkasi',
      'Thanjavur',
      'Theni',
      'Thoothukudi',
      'Tiruchirappalli',
      'Tirunelveli',
      'Tirupathur',
      'Tiruppur',
      'Tiruvallur',
      'Tiruvannamalai',
      'Tiruvarur',
      'Vellore',
      'Viluppuram',
      'Virudhunagar',
    ],
    'Kerala': [
      'Alappuzha',
      'Ernakulam',
      'Idukki',
      'Kannur',
      'Kasaragod',
      'Kollam',
      'Kottayam',
      'Kozhikode',
      'Malappuram',
      'Palakkad',
      'Pathanamthitta',
      'Thiruvananthapuram',
      'Thrissur',
      'Wayanad',
    ],
    'Karnataka': [
      'Bagalkot',
      'Ballari',
      'Belagavi',
      'Bengaluru Rural',
      'Bengaluru Urban',
      'Bidar',
      'Chamarajanagar',
      'Chikkaballapur',
      'Chikkamagaluru',
      'Chitradurga',
      'Dakshina Kannada',
      'Davanagere',
      'Dharwad',
      'Gadag',
      'Hassan',
      'Haveri',
      'Kalaburagi',
      'Kodagu',
      'Kolar',
      'Koppal',
      'Mandya',
      'Mysuru',
      'Raichur',
      'Ramanagara',
      'Shivamogga',
      'Tumakuru',
      'Udupi',
      'Uttara Kannada',
      'Vijayapura',
      'Yadgir',
    ],
    'Andhra Pradesh': [
      'Alluri Sitharama Raju',
      'Anakapalli',
      'Ananthapuramu',
      'Annamayya',
      'Bapatla',
      'Chittoor',
      'Dr. B.R. Ambedkar Konaseema',
      'East Godavari',
      'Eluru',
      'Guntur',
      'Kakinada',
      'Krishna',
      'Kurnool',
      'Nandyal',
      'NTR',
      'Palnadu',
      'Parvathipuram Manyam',
      'Prakasam',
      'SPSR Nellore',
      'Sri Sathya Sai',
      'Srikakulam',
      'Tirupati',
      'Visakhapatnam',
      'Vizianagaram',
      'West Godavari',
      'YSR Kadapa',
    ],
    'Telangana': [
      'Adilabad',
      'Bhadradri Kothagudem',
      'Hyderabad',
      'Jagtial',
      'Jangaon',
      'Jayashankar Bhupalpally',
      'Jogulamba Gadwal',
      'Kamareddy',
      'Karimnagar',
      'Khammam',
      'Kumuram Bheem Asifabad',
      'Mahabubabad',
      'Mahabubnagar',
      'Mancherial',
      'Medak',
      'Medchal-Malkajgiri',
      'Mulugu',
      'Nagarkurnool',
      'Nalgonda',
      'Narayanpet',
      'Nirmal',
      'Nizamabad',
      'Peddapalli',
      'Rajanna Sircilla',
      'Ranga Reddy',
      'Sangareddy',
      'Siddipet',
      'Suryapet',
      'Vikarabad',
      'Wanaparthy',
      'Warangal',
      'Hanamkonda',
      'Yadadri Bhuvanagiri',
    ],
    'Maharashtra': [
      'Ahmednagar',
      'Akola',
      'Amravati',
      'Aurangabad',
      'Beed',
      'Bhandara',
      'Buldhana',
      'Chandrapur',
      'Dhule',
      'Gadchiroli',
      'Gondia',
      'Hingoli',
      'Jalgaon',
      'Jalna',
      'Kolhapur',
      'Latur',
      'Mumbai City',
      'Mumbai Suburban',
      'Nagpur',
      'Nanded',
      'Nandurbar',
      'Nashik',
      'Osmanabad',
      'Palghar',
      'Parbhani',
      'Pune',
      'Raigad',
      'Ratnagiri',
      'Sangli',
      'Satara',
      'Sindhudurg',
      'Solapur',
      'Thane',
      'Wardha',
      'Washim',
      'Yavatmal',
    ],
    'Puducherry': [
      'Karaikal',
      'Mahe',
      'Puducherry',
      'Yanam',
    ],
    'Delhi': [
      'Central Delhi',
      'East Delhi',
      'New Delhi',
      'North Delhi',
      'North East Delhi',
      'North West Delhi',
      'Shahdara',
      'South Delhi',
      'South East Delhi',
      'South West Delhi',
      'West Delhi',
    ],
    'Other States': [
      'Other District',
    ],
  };

  // Step 2: Personal & Guardian Controllers
  DateTime _selectedDob = DateTime(2004, 6, 15);
  String _selectedGender = "Male";
  String _selectedBloodGroup = "O+";
  String _selectedState = "Tamil Nadu";
  String _selectedDistrict = "Coimbatore";
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _fatherNameCtrl = TextEditingController();
  final _motherNameCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: "Coimbatore");
  final _stateCtrl = TextEditingController(text: "Tamil Nadu");
  final _pincodeCtrl = TextEditingController(text: "641001");
  final _customPasswordCtrl = TextEditingController();

  // Step 3: Biometric Face Capture
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  int _activeFaceAngleIndex = 0; // 0: Frontal, 1: Left 30°, 2: Right 30°
  final List<String?> _capturedImagesB64 = [null, null, null];
  final List<String> _angleLabels = [
    "Frontal (Center)",
    "Left Angle (30°)",
    "Right Angle (30°)"
  ];

  bool _isSubmitting = false;
  String? _statusError;
  bool _isLoadingStudentData = false;

  // Faculty pool for Class Advisor selection
  List<Map<String, dynamic>> _facultyPool = [];
  bool _isLoadingFaculty = false;
  bool _showAllDeptsStaff = false;

  final List<String> _departments = [
    'CSE',
    'IT',
    'AI & DS',
    'AI & ML',
    'CYBER',
    'ECE',
    'EEE',
    'MECH',
    'CIVIL',
    'BIOTECH',
    'BME',
    'AGRI',
  ];

  @override
  void initState() {
    super.initState();
    final callerDept = (widget.initialDept ??
            widget.initialStudent?['dept'] ??
            widget.user['dept'] ??
            widget.user['department'] ??
            'CSE')
        .toString()
        .trim();
    _selectedDept = _departments.contains(callerDept.toUpperCase())
        ? callerDept.toUpperCase()
        : 'CSE';

    if (widget.user['role'] == 'staff' || widget.user['role'] == 'faculty') {
      _mentorCtrl.text = (widget.user['reg_no'] ?? widget.user['regNo'] ?? '').toString();
    }

    if (widget.initialStudent != null) {
      _populateFromStudent(widget.initialStudent!);
      final reg = (widget.initialStudent!['reg_no'] ?? '').toString().trim();
      if (reg.isNotEmpty) {
        _fetchFullStudentProfile(reg);
      }
    }

    _fetchFacultyPool();
  }

  void _populateFromStudent(Map<String, dynamic> stu) {
    _regNoCtrl.text = (stu['reg_no'] ?? '').toString();
    _rollNoCtrl.text = (stu['roll_no'] ?? '').toString();
    _nameCtrl.text = (stu['name'] ?? '').toString();

    final deg = (stu['degree'] ?? '').toString();
    if (['B.E.', 'B.Tech', 'M.E.', 'MBA', 'MCA', 'Ph.D'].contains(deg)) {
      _selectedDegree = deg;
    }

    final d = (stu['dept'] ?? '').toString().toUpperCase();
    if (_departments.contains(d)) {
      _selectedDept = d;
    }

    final b = (stu['batch'] ?? '').toString();
    if (b.isNotEmpty) {
      _selectedBatch = b;
    }

    final sem = int.tryParse('${stu['semester']}');
    if (sem != null && sem >= 1 && sem <= 8) {
      _selectedSemester = sem;
      _selectedYear = ((sem + 1) / 2).floor();
    }

    final yr = int.tryParse('${stu['year_of_study']}');
    if (yr != null && yr >= 1 && yr <= 4) {
      _selectedYear = yr;
    }

    final sec = (stu['section'] ?? '').toString().toUpperCase();
    if (['A', 'B', 'C', 'D'].contains(sec)) {
      _selectedSection = sec;
    }

    final q = (stu['quota'] ?? '').toString();
    if (['Govt', 'Management', 'NRI', 'Sports', 'Lateral Entry'].contains(q)) {
      _selectedQuota = q;
    }

    final mentor = (stu['mentor_staff_reg_no'] ?? stu['mentor'] ?? '').toString();
    if (mentor.isNotEmpty) {
      _mentorCtrl.text = mentor;
    }

    if (stu['dob'] != null && stu['dob'].toString().isNotEmpty) {
      try {
        _selectedDob = DateTime.parse(stu['dob'].toString());
      } catch (_) {}
    }

    final g = (stu['gender'] ?? '').toString();
    if (['Male', 'Female', 'Other'].contains(g)) {
      _selectedGender = g;
    }

    final bg = (stu['blood_group'] ?? '').toString();
    if (['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'].contains(bg)) {
      _selectedBloodGroup = bg;
    }

    if ((stu['phone_number'] ?? stu['phone'] ?? '').toString().isNotEmpty) {
      _phoneCtrl.text = (stu['phone_number'] ?? stu['phone']).toString();
    }
    if ((stu['email'] ?? '').toString().isNotEmpty) {
      _emailCtrl.text = stu['email'].toString();
    }
    if ((stu['father_name'] ?? '').toString().isNotEmpty) {
      _fatherNameCtrl.text = stu['father_name'].toString();
    }
    if ((stu['mother_name'] ?? '').toString().isNotEmpty) {
      _motherNameCtrl.text = stu['mother_name'].toString();
    }
    if ((stu['parent_phone'] ?? '').toString().isNotEmpty) {
      _parentPhoneCtrl.text = stu['parent_phone'].toString();
    }
    if ((stu['parent_email'] ?? '').toString().isNotEmpty) {
      _parentEmailCtrl.text = stu['parent_email'].toString();
    }
    if ((stu['emergency_contact'] ?? '').toString().isNotEmpty) {
      _emergencyCtrl.text = stu['emergency_contact'].toString();
    }
    if ((stu['permanent_address'] ?? stu['address'] ?? '').toString().isNotEmpty) {
      _addressCtrl.text = (stu['permanent_address'] ?? stu['address']).toString();
    }
    if ((stu['state'] ?? '').toString().isNotEmpty) {
      final s = stu['state'].toString();
      if (indianStatesAndDistricts.containsKey(s)) {
        _selectedState = s;
      }
      _stateCtrl.text = s;
    }
    if ((stu['district'] ?? stu['city'] ?? '').toString().isNotEmpty) {
      final d = (stu['district'] ?? stu['city']).toString();
      final dists = indianStatesAndDistricts[_selectedState] ?? [];
      if (dists.contains(d)) {
        _selectedDistrict = d;
      } else if (dists.isNotEmpty) {
        _selectedDistrict = dists.first;
      }
    }
    if ((stu['city'] ?? '').toString().isNotEmpty) {
      _cityCtrl.text = stu['city'].toString();
    }
    if ((stu['pincode'] ?? '').toString().isNotEmpty) {
      _pincodeCtrl.text = stu['pincode'].toString();
    }
  }

  Future<void> _fetchFullStudentProfile(String regNo) async {
    setState(() => _isLoadingStudentData = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/$regNo'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fullStudent = data['student'] as Map<String, dynamic>?;
        if (fullStudent != null && mounted) {
          setState(() {
            _populateFromStudent(fullStudent);
            _isLoadingStudentData = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingStudentData = false);
      }
    } catch (e) {
      debugPrint("Error fetching full student profile: $e");
      if (mounted) setState(() => _isLoadingStudentData = false);
    }
  }

  Future<void> _fetchFacultyPool() async {
    setState(() => _isLoadingFaculty = true);
    try {
      final res = await http.get(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/academics/faculty-pool?include_all_depts=true'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['faculty'] ?? []);
        if (mounted) {
          setState(() {
            _facultyPool = list;
            _isLoadingFaculty = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingFaculty = false);
      }
    } catch (e) {
      debugPrint("Error fetching faculty pool: $e");
      if (mounted) setState(() => _isLoadingFaculty = false);
    }
  }

  bool _deptMatches(String staffDept, String selectedDept) {
    final sd = staffDept.toLowerCase().trim();
    final td = selectedDept.toLowerCase().trim();
    if (sd == td) return true;
    if (td == 'cse' && (sd.contains('computer') || sd == 'cse')) return true;
    if (td == 'it' && (sd.contains('information') || sd == 'it')) return true;
    if (td == 'ece' && (sd.contains('electronics') || sd.contains('communication') || sd == 'ece')) return true;
    if (td == 'eee' && (sd.contains('electrical') || sd == 'eee')) return true;
    if (td == 'mech' && (sd.contains('mechanical') || sd == 'mech')) return true;
    if (td == 'civil' && (sd.contains('civil') || sd == 'civil')) return true;
    if ((td == 'ai & ds' || td == 'ai & ml') && (sd.contains('ai') || sd.contains('data') || sd.contains('machine'))) return true;
    return false;
  }

  List<Map<String, dynamic>> _getFilteredFaculty() {
    if (_showAllDeptsStaff) return _facultyPool;
    return _facultyPool.where((f) {
      final fDept = (f['dept'] ?? '').toString();
      return _deptMatches(fDept, _selectedDept);
    }).toList();
  }

  String _getAdvisorDisplayName(String regNo) {
    if (regNo.trim().isEmpty) return 'Not Assigned';
    final found = _facultyPool.firstWhere(
      (f) => (f['reg_no'] ?? '').toString().toLowerCase() == regNo.toLowerCase().trim(),
      orElse: () => <String, dynamic>{},
    );
    if (found.isNotEmpty) {
      final name = found['name'] ?? '';
      final role = (found['role'] ?? '').toString();
      final isHod = found['is_hod'] == true || role.toLowerCase() == 'hod';
      return '$name ($regNo)${isHod ? ' [HOD]' : ''}';
    }
    return regNo;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _regNoCtrl.dispose();
    _rollNoCtrl.dispose();
    _nameCtrl.dispose();
    _mentorCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _fatherNameCtrl.dispose();
    _motherNameCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _parentEmailCtrl.dispose();
    _emergencyCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _customPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) return;

      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      if (_cameraController != null) {
        await _cameraController!.dispose();
      }

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  Future<void> _captureFaceAngle() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final XFile photo = await _cameraController!.takePicture();

      final targetPose = _activeFaceAngleIndex == 0
          ? FaceTargetPose.front
          : (_activeFaceAngleIndex == 1 ? FaceTargetPose.left : FaceTargetPose.right);

      final prefilter = await ClientFacePreFilterService.evaluateImagePath(
        photo.path,
        targetPose: targetPose,
        allowMultipleFaces: false,
      );

      if (!prefilter.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(prefilter.message ?? 'Invalid face alignment.'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return;
      }

      final bytes = await photo.readAsBytes();
      final b64 = base64Encode(bytes);

      setState(() {
        _capturedImagesB64[_activeFaceAngleIndex] = b64;
        if (_activeFaceAngleIndex < 2) {
          _activeFaceAngleIndex++;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture frame: $e')),
        );
      }
    }
  }

  Future<void> _submitRegistration() async {
    setState(() {
      _isSubmitting = true;
      _statusError = null;
    });

    final validImages =
        _capturedImagesB64.where((img) => img != null).cast<String>().toList();

    final dobFormatted =
        "${_selectedDob.year.toString().padLeft(4, '0')}-${_selectedDob.month.toString().padLeft(2, '0')}-${_selectedDob.day.toString().padLeft(2, '0')}";

    final payload = {
      "reg_no": _regNoCtrl.text.trim(),
      "roll_no": _rollNoCtrl.text.trim().isEmpty ? null : _rollNoCtrl.text.trim(),
      "name": _nameCtrl.text.trim(),
      "dob": dobFormatted,
      "gender": _selectedGender,
      "blood_group": _selectedBloodGroup,
      "degree": _selectedDegree,
      "dept": _selectedDept,
      "batch": _selectedBatch,
      "year_of_study": _selectedYear,
      "semester": _selectedSemester,
      "section": _selectedSection,
      "quota": _selectedQuota,
      "mentor_staff_reg_no":
          _mentorCtrl.text.trim().isEmpty ? null : _mentorCtrl.text.trim(),
      "phone_number":
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      "email": _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      "father_name": _fatherNameCtrl.text.trim().isEmpty
          ? null
          : _fatherNameCtrl.text.trim(),
      "mother_name": _motherNameCtrl.text.trim().isEmpty
          ? null
          : _motherNameCtrl.text.trim(),
      "parent_phone": _parentPhoneCtrl.text.trim(),
      "parent_email": _parentEmailCtrl.text.trim().isEmpty
          ? null
          : _parentEmailCtrl.text.trim(),
      "emergency_contact": _emergencyCtrl.text.trim().isEmpty
          ? null
          : _emergencyCtrl.text.trim(),
      "permanent_address": _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      "state": _selectedState,
      "district": _selectedDistrict,
      "city": _cityCtrl.text.trim().isEmpty ? _selectedDistrict : _cityCtrl.text.trim(),
      "pincode":
          _pincodeCtrl.text.trim().isEmpty ? null : _pincodeCtrl.text.trim(),
      "custom_password": _customPasswordCtrl.text.trim().isEmpty
          ? null
          : _customPasswordCtrl.text.trim(),
      "images_base64": validImages,
      "overwrite": true,
    };

    try {
      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/students/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data['message'] ??
                          'Student ${_nameCtrl.text} registered successfully!',
                    ),
                  ),
                ],
              ),
            ),
          );
          widget.onStudentRegistered?.call();
        }
      } else {
        final err = jsonDecode(response.body);
        setState(() {
          _statusError = err['detail'] ?? 'Registration failed. Check details.';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusError = 'Network error: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Icon(
                widget.isReEnroll ? Icons.face_retouching_natural_rounded : Icons.person_add_alt_1_rounded,
                color: primaryIndigo,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                widget.isReEnroll ? 'Re-Enroll Student Biometrics' : 'University Student Registration',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          actions: [
            if (!widget.isReEnroll)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    StudentBulkImportDialog.show(
                      context,
                      token: widget.token,
                      user: widget.user,
                      initialDept: widget.initialDept,
                      onStudentsImported: widget.onStudentRegistered,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: primaryIndigo),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 16, color: primaryIndigo),
                  label: const Text(
                    'Bulk Import (CSV / Excel)',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: primaryIndigo),
                  ),
                ),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: _buildStepIndicator(isDark),
          ),
        ),
        body: Container(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          child: Column(
            children: [
              if (widget.initialStudent != null || widget.isReEnroll)
                _buildStudentSummaryBanner(isDark),
              if (_statusError != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusError!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentStep,
                  children: [
                    _buildStep1Academic(isDark),
                    _buildStep2Personal(isDark),
                    _buildStep3Biometrics(isDark),
                    _buildStep4Review(isDark),
                  ],
                ),
              ),
              _buildBottomControls(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentSummaryBanner(bool isDark) {
    final hasFace = (widget.initialStudent?['has_face'] == true) ||
        ((widget.initialStudent?['face_samples_count'] ?? 0) > 0);
    final faceCount = widget.initialStudent?['face_samples_count'] ?? 0;
    final name = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text
        : (widget.initialStudent?['name'] ?? 'Student');
    final regNo = _regNoCtrl.text.isNotEmpty
        ? _regNoCtrl.text
        : (widget.initialStudent?['reg_no'] ?? '');
    final rollNo = _rollNoCtrl.text.isNotEmpty
        ? _rollNoCtrl.text
        : (widget.initialStudent?['roll_no'] ?? '');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryIndigo.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: primaryIndigo,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryIndigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.isReEnroll ? 'RE-ENROLL MODE' : 'STORED PROFILE',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: primaryIndigo),
                      ),
                    ),
                    if (_isLoadingStudentData) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: primaryIndigo),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$regNo ${rollNo.isNotEmpty ? '• ($rollNo)' : ''} | $_selectedDegree $_selectedDept • Batch $_selectedBatch (Sem $_selectedSemester - Sec $_selectedSection)',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (hasFace ? const Color(0xFF10B981) : Colors.orange).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (hasFace ? const Color(0xFF10B981) : Colors.orange).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasFace ? Icons.check_circle_rounded : Icons.face_retouching_off_rounded,
                  size: 13,
                  color: hasFace ? const Color(0xFF10B981) : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  hasFace ? 'Enrolled ($faceCount)' : 'No Face ID',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasFace ? const Color(0xFF10B981) : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    final steps = ['Academic', 'Personal', 'Biometrics', 'Review'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isDone = i < _currentStep;
          final isCurrent = i == _currentStep;
          final color = isCurrent
              ? primaryIndigo
              : (isDone ? const Color(0xFF10B981) : Colors.grey.shade400);

          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _currentStep = i);
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color.withValues(alpha: 0.2),
                    child: isDone
                        ? const Icon(Icons.check, size: 14, color: Color(0xFF10B981))
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.grey,
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: isDone ? const Color(0xFF10B981) : Colors.grey.shade300,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1Academic(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyStep1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'University Academic Enrollment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (widget.isReEnroll)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryIndigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: primaryIndigo),
                        SizedBox(width: 4),
                        Text(
                          'Pre-filled with stored student records',
                          style: TextStyle(fontSize: 11, color: primaryIndigo, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _regNoCtrl,
                    readOnly: widget.isReEnroll,
                    decoration: InputDecoration(
                      labelText: 'University Reg No *',
                      hintText: 'e.g. 714024104145',
                      prefixIcon: Icon(widget.isReEnroll ? Icons.lock_rounded : Icons.badge_outlined),
                      helperText: widget.isReEnroll ? 'Unique register number locked for re-enrollment' : null,
                      helperStyle: const TextStyle(fontSize: 11, color: primaryIndigo),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Reg No required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _rollNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Roll No',
                      hintText: 'e.g. 22CS101',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Student Full Name *',
                hintText: 'As per University records',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Full Name required' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDegree,
                    decoration: const InputDecoration(
                      labelText: 'Degree',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    items: ['B.E.', 'B.Tech', 'M.E.', 'MBA', 'MCA', 'Ph.D']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedDegree = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDept,
                    decoration: InputDecoration(
                      labelText: 'Department',
                      prefixIcon: const Icon(Icons.domain_outlined),
                      helperText: widget.isDeptLocked ? 'Department locked' : null,
                    ),
                    items: _departments
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: widget.isDeptLocked
                        ? null
                        : (val) {
                            setState(() {
                              _selectedDept = val!;
                              if (!_showAllDeptsStaff) {
                                final filtered = _getFilteredFaculty();
                                if (!filtered.any((f) =>
                                    (f['reg_no'] ?? '').toString().toLowerCase() ==
                                    _mentorCtrl.text.toLowerCase().trim())) {
                                  _mentorCtrl.text = '';
                                }
                              }
                            });
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBatch,
                    decoration: const InputDecoration(
                      labelText: 'Batch',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    items: [
                      '2021-2025',
                      '2022-2026',
                      '2023-2027',
                      '2024-2028',
                      '2025-2029'
                    ]
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedBatch = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedSemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      prefixIcon: Icon(Icons.timeline_outlined),
                    ),
                    items: List.generate(8, (i) => i + 1)
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text('Sem $s')))
                        .toList(),
                    onChanged: (val) => setState(() {
                      _selectedSemester = val!;
                      _selectedYear = ((val + 1) / 2).floor();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSection,
                    decoration: const InputDecoration(
                      labelText: 'Section',
                      prefixIcon: Icon(Icons.group_work_outlined),
                    ),
                    items: ['A', 'B', 'C', 'D']
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text('Sec $s')))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedSection = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedQuota,
                    decoration: const InputDecoration(
                      labelText: 'Admission Quota',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    items: ['Govt', 'Management', 'Sports', 'NRI']
                        .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedQuota = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _mentorCtrl.text.trim().isEmpty
                            ? ''
                            : (_facultyPool.any((f) =>
                                    (f['reg_no'] ?? '').toString() ==
                                    _mentorCtrl.text.trim())
                                ? _mentorCtrl.text.trim()
                                : ''),
                        decoration: InputDecoration(
                          labelText: 'Class Advisor / Mentor',
                          prefixIcon:
                              const Icon(Icons.supervisor_account_outlined),
                          suffixIcon: _isLoadingFaculty
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text(
                              '-- No Advisor Assigned --',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                          ..._getFilteredFaculty().map((f) {
                            final regNo = (f['reg_no'] ?? '').toString();
                            final name = (f['name'] ?? '').toString();
                            final isHod = f['is_hod'] == true ||
                                (f['role'] ?? '').toString().toLowerCase() ==
                                    'hod';
                            final dept = (f['dept'] ?? '').toString();
                            return DropdownMenuItem<String>(
                              value: regNo,
                              child: Text(
                                '$name ($regNo)${isHod ? ' [HOD]' : ''}${_showAllDeptsStaff ? ' - $dept' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isHod
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _mentorCtrl.text = val ?? '';
                          });
                        },
                      ),
                      if (_getFilteredFaculty().isEmpty && !_isLoadingFaculty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'No staff found in $_selectedDept. ',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.orange),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _showAllDeptsStaff = true),
                                child: const Text(
                                  'Show all staff',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: primaryIndigo,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (!_showAllDeptsStaff)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 20),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                setState(() => _showAllDeptsStaff = true),
                            child: const Text('Show all staff',
                                style: TextStyle(
                                    fontSize: 11, color: primaryIndigo)),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 20),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                setState(() => _showAllDeptsStaff = false),
                            child: Text('Filter by $_selectedDept only',
                                style: const TextStyle(
                                    fontSize: 11, color: primaryIndigo)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Personal(bool isDark) {
    final dobStr =
        "${_selectedDob.day.toString().padLeft(2, '0')}-${_selectedDob.month.toString().padLeft(2, '0')}-${_selectedDob.year}";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyStep2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personal & Guardian Information',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDob,
                        firstDate: DateTime(1995),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDob = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date of Birth (DOB) *',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      child: Text(dobStr,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: Icon(Icons.transgender_outlined),
                    ),
                    items: ['Male', 'Female', 'Other']
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedGender = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBloodGroup,
                    decoration: const InputDecoration(
                      labelText: 'Blood Group',
                      prefixIcon: Icon(Icons.water_drop_outlined),
                    ),
                    items: ['A+', 'B+', 'O+', 'AB+', 'A-', 'B-', 'O-', 'AB-']
                        .map((bg) => DropdownMenuItem(value: bg, child: Text(bg)))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedBloodGroup = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Student Mobile',
                      prefixIcon: Icon(Icons.phone_iphone_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Student Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fatherNameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Father's / Guardian Name",
                      prefixIcon: Icon(Icons.person_pin_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _parentPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Parent Contact Number *',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Parent contact required'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Permanent Residential Address',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedState,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'State *',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                    items: indianStatesAndDistricts.keys
                        .map((st) => DropdownMenuItem(
                              value: st,
                              child: Text(st, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedState = val;
                          final dists = indianStatesAndDistricts[val] ?? [];
                          if (!dists.contains(_selectedDistrict)) {
                            _selectedDistrict = dists.isNotEmpty ? dists.first : '';
                          }
                          _stateCtrl.text = val;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: (indianStatesAndDistricts[_selectedState] ?? []).contains(_selectedDistrict)
                        ? _selectedDistrict
                        : ((indianStatesAndDistricts[_selectedState] ?? []).isNotEmpty
                            ? (indianStatesAndDistricts[_selectedState] ?? []).first
                            : null),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'District *',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: (indianStatesAndDistricts[_selectedState] ?? [])
                        .map((dist) => DropdownMenuItem(
                              value: dist,
                              child: Text(dist, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDistrict = val;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'City / Town',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _pincodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Pincode',
                      prefixIcon: Icon(Icons.pin_drop_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3Biometrics(bool isDark) {
    if (!_isCameraReady && _cameraController == null) {
      _initCamera();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 550;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isReEnroll || widget.initialStudent != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: primaryIndigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryIndigo.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.face_retouching_natural_rounded, size: 20, color: primaryIndigo),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Re-enrolling face biometrics for: ${_nameCtrl.text.isNotEmpty ? _nameCtrl.text : (widget.initialStudent?['name'] ?? '')} (${_regNoCtrl.text}) • $_selectedDegree $_selectedDept (Sem $_selectedSemester - Sec $_selectedSection)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: primaryIndigo),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  const Icon(Icons.face_retouching_natural_rounded,
                      color: primaryIndigo),
                  const SizedBox(width: 8),
                  Text(
                    'Multi-Angle Biometric Face Enrollment',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Capture 3 distinct angles for high-precision Centroid Prototype reduction.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildCameraFeedBox(isDark)),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: _buildAngleCardsColumn(isDark)),
                  ],
                )
              else ...[
                _buildCameraFeedBox(isDark),
                const SizedBox(height: 16),
                _buildAngleCardsColumn(isDark),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraFeedBox(bool isDark) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryIndigo.withValues(alpha: 0.4), width: 2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraReady && _cameraController != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CameraPreview(_cameraController!),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: primaryIndigo),
                  const SizedBox(height: 12),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          Center(
            child: Container(
              width: 150,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(80),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _captureFaceAngle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryIndigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(
                    'Capture ${_angleLabels[_activeFaceAngleIndex]}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleCardsColumn(bool isDark) {
    return Column(
      children: List.generate(3, (idx) {
        final b64 = _capturedImagesB64[idx];
        final isCaptured = b64 != null;
        final isActive = idx == _activeFaceAngleIndex;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? primaryIndigo
                  : (isCaptured ? const Color(0xFF10B981) : Colors.grey.shade300),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey.shade200,
                  child: isCaptured
                      ? Image.memory(base64Decode(b64), fit: BoxFit.cover)
                      : Icon(
                          idx == 0
                              ? Icons.face_rounded
                              : (idx == 1
                                  ? Icons.turn_left_rounded
                                  : Icons.turn_right_rounded),
                          color: Colors.grey,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _angleLabels[idx],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      isCaptured ? 'Ready (Captured) ✓' : 'Pending capture',
                      style: TextStyle(
                        fontSize: 11,
                        color: isCaptured
                            ? const Color(0xFF10B981)
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isCaptured ? Icons.refresh_rounded : Icons.camera_alt_outlined,
                  size: 20,
                  color: primaryIndigo,
                ),
                tooltip: 'Capture via camera',
                onPressed: () {
                  setState(() => _activeFaceAngleIndex = idx);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStep4Review(bool isDark) {
    final validSamples =
        _capturedImagesB64.where((img) => img != null).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isReEnroll
                ? 'Biometrics Re-Enrollment Review & Confirmation'
                : 'Registration Summary & Credential Setup',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Full Name', _nameCtrl.text),
                _buildSummaryRow('University Reg No', _regNoCtrl.text),
                _buildSummaryRow('Degree & Dept', '$_selectedDegree $_selectedDept'),
                _buildSummaryRow('Batch / Sem / Sec',
                    '$_selectedBatch | Sem $_selectedSemester | Sec $_selectedSection'),
                _buildSummaryRow('Class Advisor', _getAdvisorDisplayName(_mentorCtrl.text)),
                _buildSummaryRow('State & District', '$_selectedState → $_selectedDistrict'),
                _buildSummaryRow('Parent Contact', _parentPhoneCtrl.text),
                _buildSummaryRow(
                    'Face Samples',
                    '$validSamples of 3 angles captured',
                    isHighlight: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _customPasswordCtrl,
            decoration: InputDecoration(
              labelText: widget.isReEnroll
                  ? 'Reset Password (Optional - leave blank to keep unchanged)'
                  : 'Initial Password (Optional)',
              hintText: widget.isReEnroll
                  ? 'Leave blank to preserve existing password'
                  : 'Default is Date of Birth (DDMMYYYY)',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              helperText: widget.isReEnroll
                  ? 'Only enter a password if you wish to reset it.'
                  : 'Student will be prompted to change password on first login.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value.isEmpty ? '-' : value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isHighlight ? const Color(0xFF10B981) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _currentStep--),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Back'),
            )
          else
            const SizedBox(width: 80),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isReEnroll && _currentStep < 2)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() => _currentStep = 2),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16, color: primaryIndigo),
                    label: const Text(
                      'Skip to Camera',
                      style: TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _handleNextOrSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIndigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(140, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _currentStep == 3
                            ? (widget.isReEnroll
                                ? 'Complete Re-Enrollment'
                                : 'Complete Registration')
                            : 'Next Step',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleNextOrSubmit() {
    if (_currentStep == 0) {
      if (_formKeyStep1.currentState?.validate() ?? false) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_formKeyStep2.currentState?.validate() ?? false) {
        setState(() => _currentStep = 2);
      }
    } else if (_currentStep == 2) {
      setState(() => _currentStep = 3);
    } else if (_currentStep == 3) {
      _submitRegistration();
    }
  }
}
