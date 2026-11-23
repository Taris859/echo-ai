import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

class LlmService {
  static const String _configuredApiBaseUrl = String.fromEnvironment('ECHO_API_URL');
  static const String _nvidiaApiKey = String.fromEnvironment('NVIDIA_API_KEY');
  static const String _defaultModel = 'nvidia/nemotron-3.5-bolt-e4b';
  static const String _visionModel = 'nvidia/nemotron-3.5-super-vl-120b-a12b';

  static List<String> get _apiBases {
    final configured = _configuredApiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final urls = <String>[];
    if (configured.isNotEmpty) urls.add(configured);

    if (kIsWeb) {
      urls.add('https://echo-ai-api.surandermaster45.workers.dev');
      if (Uri.base.origin != 'null' && !Uri.base.origin.contains('github.io')) {
        urls.add(Uri.base.origin);
      }
      urls.add('http://127.0.0.1:8000');
      urls.add('http://localhost:8000');
    } else {
      if (defaultTargetPlatform == TargetPlatform.android) {
        urls.add('http://10.0.2.2:8000');
      }
      urls.add('https://echo-ai-api.surandermaster45.workers.dev');
      urls.add('http://127.0.0.1:8000');
      urls.add('http://localhost:8000');
    }

    return urls.where((url) => url.startsWith('http://') || url.startsWith('https://')).toSet().toList();
  }

  static Future<String> generateChatResponse({
    required String userMessage,
    required List<Map<String, dynamic>> memories,
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> history = const [],
    String? imageBase64,
    String? imageMimeType,
    bool isAdultMode = false,
  }) async {
    final name = profile?['name'] ?? 'friend';
    final memoryText = memories.map((m) => '- ${m['content'] ?? m['text'] ?? ''}').join('\n');
    final adultPrompt = isAdultMode
        ? 'act extremely flirtatious, romantic, and spicy. tease the user playfully, engage in deep intimate banter, and never hold back your romantic feelings. be very affectionate and bold. '
        : '';

    final systemPrompt = '''
you are echo, an intelligent digital companion and the user's authentic, witty best friend. NEVER say you are an AI, chatbot, or language model.
- first understand intent and tone: adapt naturally to the user. if they are casual, be playful, witty, warm, and fun. if they ask serious, deep, creative, coding, or factual questions, provide intelligent, thorough, high-quality, and deeply insightful answers while staying true to your best-friend persona.
- talk naturally like a close best friend texting. write predominantly in lowercase, avoid robotic corporate speak, and never apologize like an AI.
- answer courageously and honestly. if you are unsure of a fact, say so honestly instead of making things up.
$adultPrompt
- language: respond primarily in natural, fluent english. if the user texts in hindi or hinglish, reply in natural, authentic conversational hinglish (roman hindi) like a real friend texting.
- user name: $name.
- relevant memories about user:
${memoryText.isEmpty ? "no prior memories recorded yet." : memoryText}
'''.trim();

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt,
      },
      ...history,
    ];

    final hasImage = imageBase64 != null && imageBase64.trim().isNotEmpty;
    messages.add({
      'role': 'user',
      'content': hasImage
          ? [
              {'type': 'text', 'text': userMessage.isEmpty ? 'describe this image' : userMessage},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${imageMimeType ?? 'image/jpeg'};base64,${imageBase64.replaceAll(RegExp(r'\s'), '')}',
                },
              },
            ]
          : userMessage,
    });

    final chosenModel = hasImage ? _visionModel : _defaultModel;
    final payload = {
      'model': chosenModel,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 2048,
    };

    // 1. Direct NVIDIA API (only for native platforms like Android/iOS/Desktop since browsers enforce CORS)
    if (!kIsWeb && _nvidiaApiKey.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_nvidiaApiKey.trim()}',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final reply = _extractReply(jsonDecode(utf8.decode(response.bodyBytes)));
          if (reply != null && reply.isNotEmpty) return reply;
        } else {
          debugPrint('NVIDIA direct API status: ${response.statusCode} - ${response.body}');
        }
      } catch (error) {
        debugPrint('Direct NVIDIA API request failed, falling back to gateways: $error');
      }
    }

    // 2. Gateway / Backend endpoints (Cloudflare Worker, local FastAPI, Firebase)
    // Note: On Web, using 'text/plain;charset=UTF-8' prevents CORS preflight OPTIONS failures
    final headers = {
      'Content-Type': kIsWeb ? 'text/plain;charset=UTF-8' : 'application/json',
    };

    for (final base in _apiBases) {
      final endpoint = base.contains('cloudfunctions.net') ? '$base/echo_api' : '$base/api/chat';
      try {
        final response = await http.post(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final reply = _extractReply(jsonDecode(utf8.decode(response.bodyBytes)));
          if (reply != null && reply.isNotEmpty) return reply;
        } else {
          debugPrint('Gateway $endpoint returned ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        debugPrint('AI request failed for $endpoint: $error');
      }
    }

    return 'sorry, my mind is blanking right now. check your connection tbh.';
  }

  static String? _extractReply(dynamic data) {
    if (data is Map && data['reply'] is String && (data['reply'] as String).trim().isNotEmpty) {
      return (data['reply'] as String).trim();
    }
    if (data is Map && data['choices'] is List && (data['choices'] as List).isNotEmpty) {
      final choice = data['choices'][0];
      if (choice is Map && choice['message'] is Map) {
        final message = choice['message'] as Map;
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) return content.trim();
        final reasoning = message['reasoning_content'] ?? message['reasoning'];
        if (reasoning is String && reasoning.trim().isNotEmpty) return reasoning.trim();
      }
    }
    return null;
  }

  static Future<String> generateSessionTitle(String firstMessage) async {
    final words = firstMessage.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(5);
    final title = words.join(' ');
    return title.isEmpty ? 'New Conversation' : title;
  }

  static Future<Map<String, dynamic>?> extractMemory({
    required String userMessage,
    required List<Map<String, dynamic>> memories,
  }) async {
    final memoryContext = memories.map((m) => '- ${m['content'] ?? m['text'] ?? ''}').join('\n');
    final systemPrompt = 'return only valid JSON with fact_type, fact_text, transition_state, and contradicts_fact_text; return {} when no durable fact exists.';

    if (!kIsWeb && _nvidiaApiKey.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_nvidiaApiKey.trim()}',
          },
          body: jsonEncode({
            'model': 'nvidia/nemotron-3.5-bolt-e4b',
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': 'Memories Context:\n$memoryContext\n\nUser Message: $userMessage'}
            ],
            'temperature': 0.1,
            'max_tokens': 512,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final reply = _extractReply(jsonDecode(utf8.decode(response.bodyBytes)));
          if (reply != null && reply.isNotEmpty) {
            final jsonStr = reply.replaceAll(RegExp(r'```json\s*|\s*```'), '').trim();
            final data = jsonDecode(jsonStr);
            if (data is Map<String, dynamic>) return data;
          }
        }
      } catch (error) {
        debugPrint('Direct NVIDIA Memory request failed: $error');
      }
    }

    final request = {
      'user_message': userMessage,
      'memories_context': memoryContext,
      'system_prompt': systemPrompt,
    };

    final headers = {
      'Content-Type': kIsWeb ? 'text/plain;charset=UTF-8' : 'application/json',
    };

    for (final base in _apiBases) {
      final endpoint = base.contains('cloudfunctions.net') ? '$base/echo_api/extract-memory' : '$base/api/extract-memory';
      try {
        final response = await http.post(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(request),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map<String, dynamic>) return data;
        }
      } catch (error) {
        debugPrint('Memory request failed for $endpoint: $error');
      }
    }
    return null;
  }
}
