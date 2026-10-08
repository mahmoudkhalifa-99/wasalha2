import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart' as intl;

import '../../../models/models.dart' show AppUser, UserRole;
import '../../../services/firebase_service.dart' show friendlyError;
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../data/captain_accounts_repository.dart';
import '../domain/captain_accounts.dart';

class _Data {
  final List<DriverInfo> drivers;
  final OrdersSlice slice;
  final List<CaptainStats> stats;
  final DateRange range;
  const _Data(this.drivers, this.slice, this.stats, this.range);
}

/// حسابات الكباتن (للأدمن): كل كابتن عمل كام مشوار في الفترة، وإجمالي الأجرة،
/// والنسبة المستحقة عليه (النسبة قابلة للتعديل والحفظ لكل كابتن).
class CaptainAccountsView extends StatefulWidget {
  final AppUser user;
  const CaptainAccountsView({super.key, required this.user});

  @override
  State<CaptainAccountsView> createState() => _CaptainAccountsViewState();
}

class _CaptainAccountsViewState extends State<CaptainAccountsView> {
  final _repo = CaptainAccountsRepository();
  PeriodPreset _preset = PeriodPreset.thisMonth;
  DateTime? _customFirst;
  DateTime? _customLast;
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  DateRange _range() => rangeFor(_preset, DateTime.now(),
      customFirstDay: _customFirst, customLastDay: _customLast);

  Future<_Data> _load() async {
    final range = _range();
    final drivers = await _repo.loadDrivers();
    final slice = await _repo.loadOrders(range);
    return _Data(drivers, slice, buildCaptainStats(slice.rows, range), range);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _customFirst != null && _customLast != null
          ? DateTimeRange(start: _customFirst!, end: _customLast!)
          : null,
    );
    if (r == null) return;
    setState(() {
      _preset = PeriodPreset.custom;
      _customFirst = r.start;
      _customLast = r.end;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user.role != UserRole.admin) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text('غير مصرح', style: T.s(14, T.w900, C.rose500))),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _periodBar(),
          const SizedBox(height: 14),
          FutureBuilder<_Data>(
            future: _future,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (s.hasError) return _error(s.error!);
              return _content(s.data!);
            },
          ),
        ],
      ),
    );
  }

  Widget _periodBar() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in PeriodPreset.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(p == PeriodPreset.custom && _customFirst != null
                          ? _customLabel()
                          : p.label),
                      selected: _preset == p,
                      onSelected: (_) {
                        if (p == PeriodPreset.custom) {
                          _pickCustom();
                        } else {
                          setState(() {
                            _preset = p;
                            _future = _load();
                          });
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'تحديث',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  String _customLabel() {
    final f = intl.DateFormat('MM/dd');
    return '${f.format(_customFirst!)} - ${f.format(_customLast!)}';
  }

  Widget _error(Object e) {
    final msg = friendlyError(e);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('تعذر تحميل الحسابات', style: T.s(14, T.w900, C.rose500)),
          const SizedBox(height: 6),
          Text(msg, textAlign: TextAlign.center, style: T.s(11, T.w700, C.slate500)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _content(_Data d) {
    final byId = {for (final s in d.stats) s.driverId: s};
    final cards = <_CardModel>[];
    final known = <String>{};
    for (final dr in d.drivers) {
      known.add(dr.id);
      cards.add(_CardModel(dr.id, dr, byId[dr.id] ?? CaptainStats(driverId: dr.id)));
    }
    for (final s in d.stats) {
      if (!known.contains(s.driverId)) {
        cards.add(_CardModel(s.driverId, null, s)); // حساب كابتن اتحذف
      }
    }
    cards.sort((a, b) {
      final c = b.stats.deliveredCount.compareTo(a.stats.deliveredCount);
      return c != 0 ? c : (a.driver?.name ?? '').compareTo(b.driver?.name ?? '');
    });

    var trips = 0;
    var fares = 0.0;
    var due = 0.0;
    for (final c in cards) {
      trips += c.stats.deliveredCount;
      fares += c.stats.totalFares;
      due += feeDue(
          c.stats.deliveredCount, c.driver?.feePerTrip ?? kDefaultFeePerTrip);
    }

    final df = intl.DateFormat('yyyy/MM/dd');
    final lastDay = d.range.end.subtract(const Duration(days: 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${df.format(d.range.start)}  →  ${df.format(lastDay)}',
                  style: T.s(12, T.w900, C.slate500)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _stat('المشاوير المكتملة', '$trips'),
                  _stat('مكسبي (رسوم المشاوير)', '${formatMoney(due)} ج.م'),
                  _stat('إجمالي الأجرة', '${formatMoney(fares)} ج.م'),
                ],
              ),
              const SizedBox(height: 6),
              Text('مكسبك = عدد المشاوير المكتملة × رسوم المشوار (الافتراضي ${formatMoney(kDefaultFeePerTrip)} ج.م لكل مشوار، وممكن تعدّلها لكل كابتن).',
                  style: T.s(10, T.w700, C.slate400)),
            ],
          ),
        ),
        if (d.slice.capped)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'تنبيه: الفترة فيها طلبات أكتر من ${CaptainAccountsRepository.maxOrders}، فالأرقام ممكن تكون ناقصة. اختار فترة أقصر.',
                style: T.s(12, T.w900, C.amber500)),
          ),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(child: Text('لا يوجد كباتن', style: T.s(14, T.w900, C.slate400))),
          )
        else
          for (final c in cards)
            _CaptainCard(
              key: ValueKey('${c.id}_${d.range.startMs}_${d.range.endMs}'),
              model: c,
              range: d.range,
              repo: _repo,
            ),
        const SizedBox(height: 8),
        Text(
            'طريقة الحساب: المشوار المكتمل = طلب حالته "تم التسليم" ومعيّن عليه الكابتن، ووقت التسليم داخل الفترة. مكسبك = عدد المشاوير المكتملة × رسوم المشوار (ثابتة، مش نسبة من الأجرة). الأجرة (للمتابعة فقط) = سعر العرض اللي وافق عليه العميل. الإلغاء بعد التعيين بيظهر للمتابعة فقط ومش داخل في الحساب.',
            style: T.s(10, T.w700, C.slate400, height: 1.6)),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: T.s(15, T.w900, C.slate900)),
            const SizedBox(height: 2),
            Text(label, style: T.s(10, T.w700, C.slate500)),
          ],
        ),
      );
}

class _CardModel {
  final String id;
  final DriverInfo? driver;
  final CaptainStats stats;
  const _CardModel(this.id, this.driver, this.stats);
}

class _CaptainCard extends StatefulWidget {
  final _CardModel model;
  final DateRange range;
  final CaptainAccountsRepository repo;
  const _CaptainCard({super.key, required this.model, required this.range, required this.repo});

  @override
  State<_CaptainCard> createState() => _CaptainCardState();
}

class _CaptainCardState extends State<_CaptainCard> {
  late final TextEditingController _rate;
  late double? _saved; // رسوم المشوار المحفوظة (null = الافتراضية)
  bool _open = false;
  bool _saving = false;

  DriverInfo? get _driver => widget.model.driver;
  CaptainStats get _stats => widget.model.stats;

  @override
  void initState() {
    super.initState();
    _saved = _driver?.feePerTrip;
    _rate = TextEditingController(text: formatMoney(_saved ?? kDefaultFeePerTrip));
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  double? get _typed => parseFee(_rate.text);

  bool get _canSave {
    final t = _typed;
    if (t == null || _driver == null) return false;
    return t != (_saved ?? kDefaultFeePerTrip);
  }

  Future<void> _save() async {
    final t = _typed;
    if (t == null) return;
    setState(() => _saving = true);
    try {
      // لو الرسوم = الافتراضية نشيل الحقل بدل ما نثبّتها.
      final value = t == kDefaultFeePerTrip ? null : t;
      await widget.repo.saveFee(widget.model.id, value);
      if (mounted) {
        setState(() => _saved = value);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حفظ الرسوم')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر الحفظ: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _summaryText(double fee) {
    final df = intl.DateFormat('yyyy/MM/dd');
    final last = widget.range.end.subtract(const Duration(days: 1));
    return 'حساب الكابتن: ${_driver?.name ?? widget.model.id}\n'
        'الفترة: ${df.format(widget.range.start)} - ${df.format(last)}\n'
        'المشاوير المكتملة: ${_stats.deliveredCount}\n'
        'إجمالي الأجرة: ${formatMoney(_stats.totalFares)} ج.م\n'
        'رسوم المشوار: ${formatMoney(fee)} ج.م\n'
        'المستحق: ${formatMoney(feeDue(_stats.deliveredCount, fee))} ج.م';
  }

  @override
  Widget build(BuildContext context) {
    final typed = _typed;
    final fee = typed ?? (_saved ?? kDefaultFeePerTrip);
    final due = feeDue(_stats.deliveredCount, fee);
    final name = _driver?.name.isNotEmpty == true ? _driver!.name : 'كابتن غير معروف';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: T.s(15, T.w900, C.slate900)),
                      if ((_driver?.phone ?? '').isNotEmpty)
                        Text(_driver!.phone, style: T.s(11, T.w700, C.slate500)),
                      if (_driver == null)
                        Text('الحساب محذوف أو غير موجود', style: T.s(11, T.w900, C.amber500)),
                      if (_driver?.suspended == true)
                        Text('الحساب معلّق', style: T.s(11, T.w900, C.rose500)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'نسخ ملخص الحساب',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _summaryText(fee)));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('تم نسخ الملخص')));
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _cell('المشاوير', '${_stats.deliveredCount}', big: true),
                _cell('إجمالي الأجرة', '${formatMoney(_stats.totalFares)} ج.م'),
                _cell('متوسط المشوار', '${formatMoney(_stats.averageFare)} ج.م'),
              ],
            ),
            if (_stats.cancelledAfterAssign > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('ألغى/اتلغى بعد التعيين: ${_stats.cancelledAfterAssign}',
                    style: T.s(11, T.w700, C.slate500)),
              ),
            const Divider(height: 22),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'رسوم المشوار (ج.م)',
                      isDense: true,
                      errorText: typed == null ? 'من 0 إلى 1000' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مكسبك من الكابتن (${_stats.deliveredCount} × ${formatMoney(fee)})', style: T.s(10, T.w700, C.slate500)),
                      Text('${formatMoney(due)} ج.م', style: T.s(16, T.w900, C.emerald700)),
                    ],
                  ),
                ),
                if (_driver != null)
                  FilledButton(
                    onPressed: (_canSave && !_saving) ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('حفظ الرسوم'),
                  ),
              ],
            ),
            if (_stats.deliveredCount > 0)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'إخفاء المشاوير' : 'عرض المشاوير (${_stats.deliveredCount})'),
                ),
              ),
            if (_open) ..._tripRows(),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, String value, {bool big = false}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: T.s(big ? 20 : 13, T.w900, C.slate900)),
            const SizedBox(height: 2),
            Text(label, style: T.s(10, T.w700, C.slate500)),
          ],
        ),
      );

  List<Widget> _tripRows() {
    final f = intl.DateFormat('MM/dd HH:mm');
    final shown = _stats.delivered.take(100).toList();
    return [
      for (final t in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                  width: 92,
                  child: Text(f.format(DateTime.fromMillisecondsSinceEpoch(t.atMs)),
                      style: T.s(11, T.w700, C.slate500))),
              Expanded(
                child: Text(
                    [t.from, t.to].where((e) => e.isNotEmpty).join(' ← '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(11, T.w700, C.slate800)),
              ),
              Text('${formatMoney(t.price)} ج.م', style: T.s(12, T.w900, C.slate900)),
            ],
          ),
        ),
      if (_stats.delivered.length > shown.length)
        Text('عرض أحدث ${shown.length} مشوار من ${_stats.delivered.length}',
            style: T.s(10, T.w700, C.slate400)),
    ];
  }
}
