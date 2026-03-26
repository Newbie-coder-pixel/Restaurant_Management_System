import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/chatbot_api.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  bool get isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) _botAvatar(),
          if (!isUser) const SizedBox(width: 8),
          Flexible(child: _bubble(context)),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _userAvatar(),
        ],
      ),
    );
  }

  Widget _botAvatar() => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1A2E), Color(0xFFE94560)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16)),
    child: const Icon(Icons.restaurant, color: Colors.white, size: 16),
  );

  Widget _userAvatar() => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      color: const Color(0xFF0F3460),
      borderRadius: BorderRadius.circular(16)),
    child: const Icon(Icons.person, color: Colors.white, size: 16),
  );

  Widget _bubble(BuildContext context) {
    final isBookingConfirmed = !isUser &&
        message.content.contains('Reservasi berhasil') ||
        message.content.contains('Kode konfirmasi:');

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesan disalin'),
            duration: Duration(seconds: 1)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF1A1A2E)
              : isBookingConfirmed
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isBookingConfirmed
              ? Border.all(color: const Color(0xFF4CAF50), width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBookingConfirmed)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                  SizedBox(width: 4),
                  Text('Booking Confirmed',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Color(0xFF4CAF50))),
                ]),
              ),
            _buildFormattedText(message.content),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                color: isUser
                    ? Colors.white38
                    : const Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  // Simple markdown-like bold (**text**) renderer
  Widget _buildFormattedText(String text) {
    final parts = text.split('**');
    final spans = <TextSpan>[];
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.normal,
          fontSize: 14,
          color: isUser ? Colors.white : const Color(0xFF1F2937),
          height: 1.5,
        ),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }

  String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
}

// Typing indicator bubble
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400)));
    _animations = _controllers.map((c) =>
      Tween<double>(begin: 0, end: 6).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _loopController(_controllers[i]);
      });
    }
  }

  void _loopController(AnimationController c) {
    c.forward().then((_) => c.reverse().then((_) {
      if (mounted) _loopController(c);
    }));
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFFE94560)]),
          borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.restaurant, color: Colors.white, size: 16),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => AnimatedBuilder(
            animation: _animations[i],
            builder: (_, __) => Container(
              width: 7, height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Color.fromARGB(
                  255,
                  (100 + _animations[i].value * 10).toInt(),
                  (100 + _animations[i].value * 10).toInt(),
                  (100 + _animations[i].value * 10).toInt(),
                ),
                borderRadius: BorderRadius.circular(4)),
              transform: Matrix4.translationValues(
                0, -_animations[i].value, 0),
            ),
          )),
        ),
      ),
    ]),
  );
}