import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/college_ip_config.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_design_system.dart';

class StudentBatchPromotionCard extends StatefulWidget {
  final String token;
  final List<dynamic> batches;
  final Map<String, dynamic> batchConfigs;
  final ValueChanged<Map<String, dynamic>> onBatchConfigsChanged;
  final VoidCallback onRefreshBatches;

  const StudentBatchPromotionCard({
    super.key,
    required this.token,
    required this.batches,
    required this.batchConfigs,
    required this.onBatchConfigsChanged,
    required this.onRefreshBatches,
  });

  @override
  State<StudentBatchPromotionCard> createState() => _StudentBatchPromotionCardState();
}

class _StudentBatchPromotionCardState extends State<StudentBatchPromotionCard> {
  bool _isPromoting = false;

  void _openEditBatchDialog(Map<String, dynamic> batchItem) {
    final String batch = batchItem['batch'] ?? '';
    int currentYear = batchItem['year_of_study'] ?? 1;
    int currentSem = batchItem['semester'] ?? 1;
    String status = batchItem['status'] ?? 'active';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AdminColors.getCard(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdminColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_calendar_rounded, color: AdminColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Edit Batch: $batch', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: currentYear,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Year of Study',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.school_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Year I (First Year)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 2, child: Text('Year II (Second Year)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 3, child: Text('Year III (Third Year)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 4, child: Text('Year IV (Final Year)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDlgState(() {
                        currentYear = v;
                        currentSem = (v * 2) - 1; // Auto set to odd sem of that year
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: currentSem,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Semester',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timeline_rounded),
                  ),
                  items: List.generate(8, (i) => i + 1).map((s) {
                    return DropdownMenuItem(value: s, child: Text('Semester $s', overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => currentSem = v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.verified_user_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active (In-Course)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'graduated', child: Text('Graduated (Alumni)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => status = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AdminColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final updatedConfigs = Map<String, dynamic>.from(widget.batchConfigs);
                updatedConfigs[batch] = {
                  'year': currentYear,
                  'semester': currentSem,
                  'status': status,
                };
                widget.onBatchConfigsChanged(updatedConfigs);
                Navigator.pop(ctx);
              },
              child: const Text('Save Batch Config'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPromotionWizard(String? defaultBatch) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String selectedBatch = defaultBatch ?? (widget.batches.isNotEmpty ? widget.batches.first['batch'] : '2023-2027');

    final curBatchInfo = widget.batches.firstWhere(
      (b) => b['batch'] == selectedBatch,
      orElse: () => {'year_of_study': 1, 'semester': 1},
    );

    int curYear = curBatchInfo['year_of_study'] ?? 1;
    int curSem = curBatchInfo['semester'] ?? 1;
    int targetYear = curSem % 2 == 0 ? (curYear + 1).clamp(1, 4) : curYear;
    int targetSem = (curSem + 1).clamp(1, 8);

    String selectedDept = 'ALL';
    String selectedSection = 'ALL';

    int? previewCount;
    List<dynamic> previewSample = [];
    bool isCheckingPreview = false;
    String? previewError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setWizardState) {
          Future<void> fetchDryRun() async {
            setWizardState(() {
              isCheckingPreview = true;
              previewError = null;
            });
            try {
              final response = await http.post(
                Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/admin/student-academics/batches/promote'),
                headers: {
                  'Authorization': 'Bearer ${widget.token}',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'batch': selectedBatch,
                  'target_year': targetYear,
                  'target_semester': targetSem,
                  'dept': selectedDept,
                  'section': selectedSection,
                  'dry_run': true,
                }),
              );
              if (response.statusCode == 200) {
                final res = jsonDecode(response.body);
                setWizardState(() {
                  previewCount = res['eligible_students_count'] ?? 0;
                  previewSample = res['preview_sample'] ?? [];
                  isCheckingPreview = false;
                });
              } else {
                setWizardState(() {
                  previewError = 'Failed to fetch preview';
                  isCheckingPreview = false;
                });
              }
            } catch (e) {
              setWizardState(() {
                previewError = 'Network error: $e';
                isCheckingPreview = false;
              });
            }
          }

          return AlertDialog(
            backgroundColor: AdminColors.getCard(isDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.upgrade_rounded, color: AdminColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Bulk Semester Promotion Wizard', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Promote all students of a batch to the next academic semester / year. Includes audit trail logging.',
                      style: AdminTextStyles.labelSm(isDark),
                    ),
                    const SizedBox(height: 16),

                    // Batch Selector
                    DropdownButtonFormField<String>(
                      initialValue: selectedBatch,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select Batch to Promote',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                      items: widget.batches.map<DropdownMenuItem<String>>((b) {
                        final String bName = b['batch'] ?? '';
                        final int count = b['student_count'] ?? 0;
                        return DropdownMenuItem(value: bName, child: Text('$bName ($count students)', overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setWizardState(() {
                            selectedBatch = v;
                            final bInfo = widget.batches.firstWhere((b) => b['batch'] == v, orElse: () => {});
                            curYear = bInfo['year_of_study'] ?? 1;
                            curSem = bInfo['semester'] ?? 1;
                            targetYear = curSem % 2 == 0 ? (curYear + 1).clamp(1, 4) : curYear;
                            targetSem = (curSem + 1).clamp(1, 8);
                            previewCount = null;
                            previewSample.clear();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Current vs Target Flow Pill
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Current State', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text('Year $curYear • Sem $curSem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.primary)),
                            ],
                          ),
                          const Icon(Icons.arrow_forward_rounded, color: AdminColors.primary),
                          Column(
                            children: [
                              const Text('Promoting To', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text('Year $targetYear • Sem $targetSem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.success)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Target Year & Semester Selectors
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: targetYear,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Target Year of Study',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('Year I', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 2, child: Text('Year II', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 3, child: Text('Year III', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 4, child: Text('Year IV', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) setWizardState(() => targetYear = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: targetSem,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Target Semester',
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(8, (i) => i + 1).map((s) {
                              return DropdownMenuItem(value: s, child: Text('Semester $s', overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setWizardState(() => targetSem = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Department and Section Filters
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDept,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Department Filter',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('ALL Departments', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'CSE', child: Text('CSE', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'IT', child: Text('IT', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'AI & DS', child: Text('AI & DS', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'ECE', child: Text('ECE', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'EEE', child: Text('EEE', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'MECH', child: Text('MECH', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'CIVIL', child: Text('CIVIL', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) setWizardState(() => selectedDept = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedSection,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Section Filter',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('ALL Sections', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'A', child: Text('Section A', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'B', child: Text('Section B', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'C', child: Text('Section C', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) setWizardState(() => selectedSection = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dry Run Preview Button & Box
                    OutlinedButton.icon(
                      onPressed: isCheckingPreview ? null : fetchDryRun,
                      icon: isCheckingPreview
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.remove_red_eye_rounded, size: 16),
                      label: const Text('Run Dry-Run Preview (Verify Count)'),
                    ),
                    const SizedBox(height: 10),

                    if (previewCount != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminColors.successSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdminColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AdminColors.success, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '$previewCount Students will be promoted',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AdminColors.success, fontSize: 13),
                                ),
                              ],
                            ),
                            if (previewSample.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Sample: ${previewSample.take(4).map((s) => '${s['name']} (${s['reg_no']})').join(', ')}...',
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (previewError != null)
                      Text(previewError!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _executePromotion(
                    selectedBatch,
                    targetYear,
                    targetSem,
                    selectedDept,
                    selectedSection,
                  );
                },
                child: const Text('Execute Promotion'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executePromotion(String batch, int year, int sem, String dept, String section) async {
    setState(() => _isPromoting = true);
    try {
      final response = await http.post(
        Uri.parse('${CollegeIPConfig.defaultURL}/api/v1/admin/student-academics/batches/promote'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'batch': batch,
          'target_year': year,
          'target_semester': sem,
          'dept': dept,
          'section': section,
          'dry_run': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final count = data['promoted_count'] ?? 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully promoted $count students of batch $batch to Year $year, Sem $sem!'),
              backgroundColor: AdminColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          widget.onRefreshBatches();
        }
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Promotion failed: $e'),
            backgroundColor: AdminColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPromoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AdminCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;

              final titleSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batch Lifecycle & Student Promotion Engine', style: AdminTextStyles.titleMd(isDark)),
                  const SizedBox(height: 2),
                  Text(
                    'Manage batch progression, active semester mapping, and execute bulk student promotion',
                    style: AdminTextStyles.labelSm(isDark),
                  ),
                ],
              );

              final wizardBtn = FilledButton.icon(
                onPressed: _isPromoting ? null : () => _openPromotionWizard(null),
                icon: _isPromoting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upgrade_rounded, size: 18),
                label: const Text('Bulk Promotion Wizard'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 12),
                    wizardBtn,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: titleSection),
                  const SizedBox(width: 12),
                  wizardBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          if (widget.batches.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text('No student batches found.', style: AdminTextStyles.bodySm(isDark)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.batches.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final b = widget.batches[i];
                final String bName = b['batch'] ?? '';
                final int count = b['student_count'] ?? 0;
                final int year = b['year_of_study'] ?? 1;
                final int sem = b['semester'] ?? 1;
                final String status = b['status'] ?? 'active';
                final bool isActive = status == 'active';

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;

                    final batchInfo = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (isActive ? AdminColors.primary : Colors.grey).withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.groups_rounded,
                            color: isActive ? AdminColors.primary : Colors.grey,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Batch $bName',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AdminColors.getTextPrimary(isDark),
                                    ),
                                  ),
                                  AdminBadge(
                                    label: status.toUpperCase(),
                                    color: isActive ? AdminColors.success : Colors.grey,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Year $year of Study • Current Semester $sem • $count Enrolled Students',
                                style: AdminTextStyles.bodySm(isDark),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    final actionButtons = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openPromotionWizard(bName),
                          icon: const Icon(Icons.upgrade_rounded, size: 16),
                          label: const Text('Promote Batch'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminColors.primary,
                            side: const BorderSide(color: AdminColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.settings_rounded, size: 20),
                          tooltip: 'Configure Batch',
                          onPressed: () => _openEditBatchDialog(b),
                        ),
                      ],
                    );

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AdminColors.getCardTinted(isDark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.getBorder(isDark)),
                      ),
                      child: isNarrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                batchInfo,
                                const SizedBox(height: 12),
                                actionButtons,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: batchInfo),
                                const SizedBox(width: 12),
                                actionButtons,
                              ],
                            ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
