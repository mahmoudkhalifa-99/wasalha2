import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

class _Message {
  final String id;
  final String senderId;
  final String text;
  final int createdAt;
  const _Message(
      {required this.id,
      required this.senderId,
      required this.text,
      required this.createdAt});
}

/// نسخة Flutter من components/ChatView.tsx
class ChatView extends StatefulWidget {
  final AppUser user;
  final Order order;
  final VoidCallback onBack;
  const ChatView(
      {super.key, required this.user, required this.order, required this.onBack});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  List<_Message> _messages = [];
  bool _loading = true;
  final _newMessageCtrl = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = db
        .collection('messages')
        .where('orderId', isEqualTo: widget.order.id)
        .limit(100)
        .snapshots()
        .listen((snap) {
      final docs = snap.docs.map((d) {
        final m = stripFirestore(d.data()) as Map<String, dynamic>;
        return _Message(
          id: d.id,
          senderId: m['senderId'] as String? ?? '',
          text: m['text'] as String? ?? '',
          createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        );
      }).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;
      setState(() {
        _messages = docs;
        _loading = false;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    }, onError: (e) => handleFirestoreError(e, OperationType.list, 'messages'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _newMessageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage() async {
    final text = _newMessageCtrl.text.trim();
    if (text.isEmpty) return;
    _newMessageCtrl.clear();
    try {
      await db.collection('messages').add({
        'orderId': widget.order.id,
        'senderId': widget.user.id,
        'text': text,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      final recipientId = widget.user.id == widget.order.customerId
          ? widget.order.driverId
          : widget.order.customerId;
      if (recipientId != null) {
        await NotificationService.notifyUser(
          userId: recipientId,
          title: 'رسالة من ${widget.user.name}',
          body: text,
          type: 'INFO',
          key: 'chat_${widget.order.id}_${DateTime.now().millisecondsSinceEpoch}',
          orderId: widget.order.id,
        );
      }
    } catch (err) {
      debugPrint('send message error: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final user = widget.user;
    final isDriver = user.role == UserRole.driver;
    final headerName = isDriver
        ? 'العميل'
        : 'الكابتن ${order.driverName ?? ""}';
    final avatarText = isDriver
        ? (order.customerPhone.length >= 2
            ? order.customerPhone.substring(order.customerPhone.length - 2)
            : order.customerPhone)
        : ((order.driverName?.isNotEmpty ?? false)
            ? order.driverName!.substring(0, 1)
            : 'ك');

    return Material(
      color: C.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            color: C.slate900,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(LucideIcons.chevronRight,
                        size: 24, color: C.white),
                  ),
                ),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(headerName, style: T.s(14, T.w900, C.white)),
                        Text('مشوار نشط • المنوفية',
                            style: T.s(10, T.w700, C.emerald400,
                                letterSpacing: 0.6)),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.emerald500,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(avatarText,
                          style: T.s(18, T.w900, C.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: C.slate50,
              child: _loading
                  ? const Center(child: Spinner(color: C.slate900))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(24),
                      itemCount: _messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, i) {
                        final msg = _messages[i];
                        final isMe = msg.senderId == user.id;
                        return Align(
                          alignment: isMe
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.8),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isMe ? C.slate900 : C.white,
                                border: isMe
                                    ? null
                                    : Border.all(color: C.slate100),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(29),
                                  topRight: const Radius.circular(29),
                                  bottomRight: Radius.circular(isMe ? 29 : 0),
                                  bottomLeft: Radius.circular(isMe ? 0 : 29),
                                ),
                                boxShadow: Sh.sm(),
                              ),
                              child: Text(msg.text,
                                  style: T.s(13, T.w700,
                                      isMe ? C.white : C.slate800)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            decoration: BoxDecoration(
              color: C.white,
              border: Border(top: BorderSide(color: C.slate100)),
            ),
            child: Row(
              children: [
                PressScale(
                  scale: 0.9,
                  onTap: _handleSendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: C.emerald600,
                      shape: BoxShape.circle,
                      boxShadow: Sh.lg(),
                    ),
                    child: const Icon(LucideIcons.send,
                        size: 24, color: C.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: C.slate50,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: C.slate100),
                    ),
                    child: TextField(
                      controller: _newMessageCtrl,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: T.s(13, T.w700, C.slate900),
                      onSubmitted: (_) => _handleSendMessage(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'اكتب رسالتك...',
                        hintStyle: T.s(13, T.w700, C.gray400),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
