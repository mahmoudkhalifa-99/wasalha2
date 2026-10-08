import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

enum BroadcastAudience {
  all('كل المستخدمين (عملاء + كباتن)', ['CUSTOMER', 'DRIVER']),
  customers('العملاء فقط', ['CUSTOMER']),
  drivers('الكباتن فقط', ['DRIVER']);

  final String label;
  final List<String> roles;
  const BroadcastAudience(this.label, this.roles);
}

/// يفتح نافذة إرسال رسالة جماعية (للمدير والمشغّل).
/// بتتكتب نسخة إشعار لكل مستخدم مستهدف (عشان حالة "مقروء" تبقى لكل واحد لوحده)،
/// والـ Cloud Function الموجودة بتبعتها Push تلقائياً لو متفعّلة.
Future<void> showBroadcastDialog(BuildContext context,
    {required AppUser sender}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BroadcastDialog(sender: sender),
  );
}

class _BroadcastDialog extends StatefulWidget {
  final AppUser sender;
  const _BroadcastDialog({required this.sender});

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  static const _maxTitle = 60;
  static const _maxBody = 500;
  static const _parallel = 25;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  BroadcastAudience _audience = BroadcastAudience.all;
  bool _sending = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<List<String>> _recipients() async {
    final snap = await db
        .collection('users')
        .where('role', whereIn: _audience.roles)
        .get();
    return snap.docs
        .where((d) =>
            d.id != widget.sender.id && d.data()['status'] != 'SUSPENDED')
        .map((d) => d.id)
        .toList();
  }

  Future<bool> _confirm(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الإرسال', style: T.s(16, T.w900, C.slate900)),
          content: Text(
              'هتتبعت الرسالة دي إلى $count مستخدم (${_audience.label}). متأكد؟',
              style: T.s(12, T.w700, C.slate500)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رجوع')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إرسال')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _send() async {
    if (_sending) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'اكتب عنوان ونص الرسالة');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ids = await _recipients();
      if (ids.isEmpty) {
        if (mounted) setState(() => _error = 'مفيش مستخدمين في الفئة دي');
        return;
      }
      if (!mounted) return;
      if (!await _confirm(ids.length)) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final key = 'bc_$now';
      // كتابات منفصلة (مش batch) عشان كل كتابة تتفحص لوحدها في قواعد Firestore،
      // وبنبعتها على دفعات متوازية صغيرة.
      var failed = 0;
      for (var i = 0; i < ids.length; i += _parallel) {
        final chunk = ids.skip(i).take(_parallel);
        final results = await Future.wait(chunk.map((uid) async {
          try {
            await db.collection('notifications').add({
              'userId': uid,
              'title': title,
              'body': body,
              'type': 'ADMIN_MESSAGE',
              'key': key,
              'senderId': widget.sender.id,
              'senderName': widget.sender.name,
              'createdAt': now,
              'read': false,
            });
            return true;
          } catch (e) {
            debugPrint('broadcast item failed: $e');
            return false;
          }
        }));
        failed += results.where((ok) => !ok).length;
      }
      if (failed == ids.length) {
        throw Exception('فشل الإرسال بالكامل، راجع قواعد Firestore');
      }
      // Push حقيقي (والتطبيق مقفول) مرة واحدة للفئة كلها عن طريق الـ relay
      unawaited(NotificationService.broadcastPush(
        roles: _audience.roles,
        title: title,
        body: body,
        key: key,
      ));
      if (mounted) {
        setState(() => _done = failed == 0
            ? 'تم إرسال الرسالة إلى ${ids.length} مستخدم ✅'
            : 'تم الإرسال إلى ${ids.length - failed} من ${ids.length} (فشل $failed)');
      }
    } catch (e) {
      debugPrint('broadcast failed: $e');
      if (mounted) setState(() => _error = 'تعذر الإرسال: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: C.white,
        title: Text('رسالة للمستخدمين', style: T.s(18, T.w900, C.slate900)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: _done != null
                ? Text(_done!, style: T.s(14, T.w900, C.emerald600))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('الفئة المستهدفة',
                          style: T.s(11, T.w900, C.slate400)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final a in BroadcastAudience.values)
                            ChoiceChip(
                              label: Text(a.label,
                                  style: T.s(11, T.w800,
                                      _audience == a ? C.white : C.slate700)),
                              selected: _audience == a,
                              selectedColor: C.emerald600,
                              onSelected: _sending
                                  ? null
                                  : (_) => setState(() => _audience = a),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _titleCtrl,
                        enabled: !_sending,
                        maxLength: _maxTitle,
                        decoration: const InputDecoration(
                            labelText: 'العنوان', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _bodyCtrl,
                        enabled: !_sending,
                        maxLength: _maxBody,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: 'نص الرسالة',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder()),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_error!,
                              style: T.s(11, T.w800, C.rose500)),
                        ),
                    ],
                  ),
          ),
        ),
        actions: _done != null
            ? [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('تمام'))
              ]
            : [
                TextButton(
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(backgroundColor: C.emerald600),
                    child: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال')),
              ],
      ),
    );
  }
}
