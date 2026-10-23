/// Campus complaint category configuration and hierarchy
class ComplaintCategoryModel {
  final String title;
  final String defaultDepartmentCode;
  final List<String> subCategories;

  const ComplaintCategoryModel({
    required this.title,
    required this.defaultDepartmentCode,
    required this.subCategories,
  });

  /// Standard institutional categories configured for campus grievances
  static const List<ComplaintCategoryModel> predefinedCategories = [
    ComplaintCategoryModel(
      title: 'Academic Affairs',
      defaultDepartmentCode: 'ACAD',
      subCategories: [
        'Class Scheduling & Timetable',
        'Examination & Hall Tickets',
        'Evaluation & Grade Sheets',
        'Curriculum & Syllabus Coverage',
        'Faculty Interaction',
      ],
    ),
    ComplaintCategoryModel(
      title: 'Hostel & Residential Life',
      defaultDepartmentCode: 'HOSTEL',
      subCategories: [
        'Room Allotment & Keys',
        'Hostel Hygiene & Cleaning',
        'Mess & Food Quality',
        'Drinking Water Supply',
        'Warden / Staff Behavior',
      ],
    ),
    ComplaintCategoryModel(
      title: 'Campus Infrastructure',
      defaultDepartmentCode: 'INFRA',
      subCategories: [
        'Classroom Projectors & AV',
        'Laboratory Equipment & Power',
        'Restrooms & Sanitation',
        'Campus Lighting & Security',
        'Transport & Parking',
      ],
    ),
    ComplaintCategoryModel(
      title: 'Accounts & Billing',
      defaultDepartmentCode: 'FIN',
      subCategories: [
        'Tuition Fee Receipts',
        'Scholarship Disbursal',
        'Caution Deposit Refund',
        'Hostel Fee Reconciliation',
      ],
    ),
    ComplaintCategoryModel(
      title: 'Library & IT Services',
      defaultDepartmentCode: 'IT',
      subCategories: [
        'Campus Wi-Fi Connectivity',
        'Student Portal Login',
        'Digital Library Access',
        'Lab Computer Systems',
      ],
    ),
  ];
}
