import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/chatbot_api.dart';

// Persists chat history across navigation — tidak hilang saat pindah halaman
class ChatState {
  final List<ChatMessage> messages;
  final bool isTyping;

  const ChatState({this.messages = const [], this.isTyping = false});

  ChatState copyWith({List<ChatMessage>? messages, bool? isTyping}) =>
      ChatState(
        messages: messages ?? this.messages,
        isTyping: isTyping ?? this.isTyping,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  void addMessage(ChatMessage msg) =>
      state = state.copyWith(messages: [...state.messages, msg]);

  void setTyping(bool v) => state = state.copyWith(isTyping: v);

  void clearHistory() => state = const ChatState();
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatState>((ref) => ChatNotifier());