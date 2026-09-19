import 'package:flutter/material.dart';

class StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onReEnrollFace;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const StudentCard({
    super.key,
    required this.student,
    required this.onTap,
    required this.onEdit,
    required this.onReEnrollFace,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = (student['name'] ?? 'Unnamed Student').toString();
    final regNo = (student['reg_no'] ?? '').toString();
    final rollNo = (student['roll_no'] ?? '').toString();
    final dept = (student['dept'] ?? 'CSE').toString();
    final batch = (student['batch'] ?? '2022-2026').toString();
    final sem = (student['semester'] ?? 1).toString();
    final sec = (student['section'] ?? 'A').toString();
    final degree = (student['degree'] ?? 'B.E.').toString();
    final hasFace = (student['has_face'] == true) || (student['face_samples_count'] ?? 0) > 0;
    final isSuspended = (student['suspended'] == true);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSuspended
                ? Colors.redAccent.withValues(alpha: 0.5)
                : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: isSuspended ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar, Name & Reg No, Status & Menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                          decoration: isSuspended ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$regNo ${rollNo.isNotEmpty ? '• ($rollNo)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (val) {
                    if (val == 'view') onTap();
                    if (val == 'edit') onEdit();
                    if (val == 'reenroll') onReEnrollFace();
                    if (val == 'toggle') onToggleStatus();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'view',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('View Profile'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Details'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'reenroll',
                      child: Row(
                        children: [
                          Icon(Icons.face_retouching_natural_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Re-Enroll Biometrics'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline,
                            size: 18,
                            color: isSuspended ? const Color(0xFF10B981) : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(isSuspended ? 'Activate Student' : 'Suspend Student'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text('Delete Student', style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Badges Row
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildChip('$degree $dept', const Color(0xFF2563EB)),
                () {
                  final semNum = int.tryParse(sem);
                  final isEven = semNum != null && semNum % 2 == 0;
                  final semColor = isEven ? const Color(0xFF8B5CF6) : const Color(0xFF10B981);
                  return _buildChip('Sem $sem ($sec) • ${isEven ? 'Even' : 'Odd'}', semColor);
                }(),
                _buildChip(batch, Colors.grey.shade700),
                if (student['attendance_pct'] != null || student['attendance_percentage'] != null) ...[
                  () {
                    final raw = student['attendance_pct'] ?? student['attendance_percentage'];
                    final val = raw is num ? raw.toDouble() : (double.tryParse(raw.toString()) ?? 0.0);
                    final color = val >= 75.0 ? const Color(0xFF10B981) : (val >= 65.0 ? Colors.amber.shade800 : Colors.redAccent);
                    final label = val >= 75.0 ? '${val.toStringAsFixed(0)}% Eligible' : (val >= 65.0 ? '${val.toStringAsFixed(0)}% Condonation' : '${val.toStringAsFixed(0)}% Detained');
                    return _buildChip(label, color);
                  }(),
                ],
                if (hasFace)
                  _buildChip('Face Enrolled ✓', const Color(0xFF10B981))
                else
                  _buildChip('No Face ID', Colors.orange),
                if (student['can_reregister'] == true)
                  _buildChip('Re-register 🔓', Colors.amber.shade700),
                if (isSuspended)
                  _buildChip('Suspended', Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
