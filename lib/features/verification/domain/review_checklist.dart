/// قائمة الفحص اللي لازم المراجع يأكدها واحدة واحدة قبل اعتماد الكابتن.
/// الأمر ده بيخلّي "المقارنة" خطوات صريحة ومحفوظة في سجل القرار (review.checklist)
/// بدل خانة واحدة عامة. الفحص الآلي مساعد فقط والقرار للمراجع.
class ChecklistItem {
  final String key;
  final String label;
  const ChecklistItem(this.key, this.label);
}

const kChecklistIdentity =
    ChecklistItem('identity_match', 'الاسم والرقم القومي المُدخلين مطابقين للبطاقة (الوجه والخلف)');
const kChecklistFace =
    ChecklistItem('face_match', 'وجه صاحب البطاقة هو نفسه وجه السيلفي والوضعيات');
const kChecklistVehicle = ChecklistItem(
    'vehicle_match', 'رخصة القيادة ورخصة المركبة سارية، وأرقامها ورقم اللوحة مطابقة للمُدخل وصورة المركبة');
const kChecklistNoDuplicates =
    ChecklistItem('no_duplicates', 'راجعت تحذيرات التكرار (رقم قومي/هاتف/رخصة/لوحة/صورة) ولا يوجد ما يمنع');

/// عناصر الفحص حسب نوع المركبة. بند المركبة بيظهر لو فيه مستندات مركبة مطلوبة.
List<ChecklistItem> checklistFor({required bool needsVehicleDocs}) => [
      kChecklistIdentity,
      kChecklistFace,
      if (needsVehicleDocs) kChecklistVehicle,
      kChecklistNoDuplicates,
    ];

/// الاعتماد مسموح فقط لما كل العناصر تتأكد.
bool checklistComplete(List<ChecklistItem> items, Set<String> checked) =>
    items.every((i) => checked.contains(i.key));
