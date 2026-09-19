import 'package:flutter/material.dart';

class StudentDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback? onReEnrollFace;
  final VoidCallback? onToggleReregisterPermission;

  const StudentDetailsDialog({
    super.key,
    required this.student,
    required this.onEdit,
    required this.onToggleStatus,
    this.onReEnrollFace,
    this.onToggleReregisterPermission,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> student,
    required VoidCallback onEdit,
    required VoidCallback onToggleStatus,
    VoidCallback? onReEnrollFace,
    VoidCallback? onToggleReregisterPermission,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650, maxHeight: 720),
          child: StudentDetailsDialog(
            student: student,
            onEdit: onEdit,
            onToggleStatus: onToggleStatus,
            onReEnrollFace: onReEnrollFace,
            onToggleReregisterPermission: onToggleReregisterPermission,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (student['name'] ?? 'Student').toString();
    final regNo = (student['reg_no'] ?? '').toString();
    final isSuspended = (student['suspended'] == true);
    final hasFace = (student['has_face'] == true) || (student['face_samples_count'] ?? 0) > 0;
    final canReregister = (student['can_reregister'] == true);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 0,
          title: const Text('Student Profile Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            if (onReEnrollFace != null)
              IconButton(
                icon: const Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Re-Enroll Biometrics',
                onPressed: () {
                  Navigator.pop(context);
                  onReEnrollFace!();
                },
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Student',
              onPressed: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reg No: $regNo | Roll: ${student['roll_no'] ?? '-'}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSuspended ? Colors.redAccent : const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isSuspended ? 'Suspended Account' : 'Active University Record',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (canReregister) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Re-register Unlocked 🔓',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Academic Information
              _buildSectionTitle('University Academic Information', Icons.school_outlined, isDark),
              _buildInfoContainer(
                isDark: isDark,
                rows: [
                  _buildDataRow('Degree & Program', '${student['degree'] ?? 'B.E.'} ${student['dept']}'),
                  _buildDataRow('Batch / Period', '${student['batch']}'),
                  _buildDataRow('Current Semester', 'Semester ${student['semester']} (Year ${student['year_of_study'] ?? 1})'),
                  _buildDataRow('Class Section', 'Section ${student['section']}'),
                  _buildDataRow('Admission Quota', '${student['quota'] ?? 'Govt'}'),
                  _buildDataRow('Assigned Mentor / Advisor', '${student['mentor_staff_reg_no'] ?? 'Not Assigned'}'),
                ],
              ),
              const SizedBox(height: 16),

              // Biometric Face ID Diagnostics
              _buildSectionTitle('Biometric Face Identification', Icons.face_retouching_natural_rounded, isDark),
              _buildInfoContainer(
                isDark: isDark,
                rows: [
                  _buildDataRow(
                    'Biometric Enrollment Status',
                    hasFace ? 'Active Centroid Prototype ✓' : 'Pending Enrollment ✗',
                    isHighlight: true,
                    highlightColor: hasFace ? const Color(0xFF10B981) : Colors.orange,
                  ),
                  _buildDataRow('Face Samples Count', '${student['face_samples_count'] ?? 0} angles enrolled'),
                  _buildDataRow(
                    'Re-Registration Lock',
                    canReregister ? 'Unlocked (Permission Granted) 🔓' : 'Locked & Protected 🔒',
                    isHighlight: true,
                    highlightColor: canReregister ? const Color(0xFF10B981) : Colors.grey,
                  ),
                  _buildDataRow('ArcFace Vector Spec', '512-Dimensional IEEE-754 Compact Buffer'),
                ],
              ),
              const SizedBox(height: 16),

              // Personal & Contact Info
              _buildSectionTitle('Personal & Guardian Contact', Icons.contact_phone_outlined, isDark),
              _buildInfoContainer(
                isDark: isDark,
                rows: [
                  _buildDataRow('Date of Birth', '${student['dob']}'),
                  _buildDataRow('Gender & Blood Group', '${student['gender']} | ${student['blood_group'] ?? 'Not Specified'}'),
                  _buildDataRow('Student Mobile', '${student['phone_number'] ?? '-'}'),
                  _buildDataRow('Student Email', '${student['email'] ?? '-'}'),
                  _buildDataRow("Father's / Guardian Name", '${student['father_name'] ?? '-'}'),
                  _buildDataRow('Parent Contact Number', '${student['parent_phone'] ?? '-'}'),
                  _buildDataRow('Emergency Contact', '${student['emergency_contact'] ?? '-'}'),
                  _buildDataRow('Permanent Address', '${student['permanent_address'] ?? student['city'] ?? '-'}'),
                ],
              ),
              const SizedBox(height: 20),

              // Footer Actions
              Column(
                children: [
                  if (onReEnrollFace != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onReEnrollFace!();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.face_retouching_natural_rounded, size: 18),
                        label: const Text('Re-Enroll Student Biometrics', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (onToggleReregisterPermission != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onToggleReregisterPermission!();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: canReregister ? Colors.orange : const Color(0xFF2563EB),
                          side: BorderSide(color: canReregister ? Colors.orange : const Color(0xFF2563EB)),
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: Icon(canReregister ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 18),
                        label: Text(canReregister ? 'Revoke Face Re-Registration' : 'Grant Face Re-Registration Permission'),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onToggleStatus();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isSuspended ? const Color(0xFF10B981) : Colors.redAccent,
                            side: BorderSide(color: isSuspended ? const Color(0xFF10B981) : Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: Icon(isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline),
                          label: Text(isSuspended ? 'Activate Record' : 'Suspend Record'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onEdit();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Details'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoContainer({
    required bool isDark,
    required List<Widget> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(children: rows),
    );
  }

  Widget _buildDataRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isHighlight ? highlightColor : null,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
