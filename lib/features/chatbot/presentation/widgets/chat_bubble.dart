import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/chatbot_api.dart';
import '../../../../core/theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  bool get isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [Flexible(child: _bubble(context))],
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFormattedText(message.content),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: AppColors.textHint,
              ),
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
      spans.add(
        TextSpan(
          text: parts[i],
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.normal,
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );
    _animations = _controllers
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: 6,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _loopController(_controllers[i]);
      });
    }
  }

  void _loopController(AnimationController c) {
    c.forward().then(
      (_) => c.reverse().then((_) {
        if (mounted) _loopController(c);
      }),
    );
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
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) => AnimatedBuilder(
                animation: _animations[i],
                builder: (_, __) => Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Color.fromARGB(
                      255,
                      (100 + _animations[i].value * 10).toInt(),
                      (100 + _animations[i].value * 10).toInt(),
                      (100 + _animations[i].value * 10).toInt(),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  transform: Matrix4.translationValues(
                    0,
                    -_animations[i].value,
                    0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
