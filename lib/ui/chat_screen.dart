import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_helper.dart';
import '../services/llm_service.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;
  
  final ImagePicker _picker = ImagePicker();
  // ignore: unused_field
  XFile? _selectedImage;
  String? _selectedImageBase64;
  String? _selectedImageMimeType;
  
  // App state
  final List<Map<String, dynamic>> _messages = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _vaultMemories = [];
  List<Map<String, dynamic>> _chatSessions = [];
  
  late SharedPreferences _prefs;
  String _serverAddress = "10.0.2.2:8000"; // Auto-configured default
  String _userId = "default_user";
  String _userName = "friend";
  String _userEmail = "";
  String _currentSessionId = "";

  // Drawer / Interaction state
  // ignore: unused_field
  bool _isServerConnected = false;
  String _currentStage = "idle";
  // ignore: unused_field
  String _stageMessage = "";
  // ignore: unused_field
  int _confidenceScore = 98;
  // ignore: unused_field
  List<dynamic> _recalledMemories = [];
  // ignore: unused_field
  List<dynamic> _searchResults = [];

  Map<String, dynamic> _profile = {"name": "friend", "age": 0, "gender": "unknown", "bio": ""};
  String _activeAccentTheme = 'Neon Lime';
  String _activeAppMode = 'Dark Mode';

  bool get _isLightMode => _activeAppMode == 'Light Mode';
  Color get _bgColor => _isLightMode ? const Color(0xFFF8F9FA) : const Color(0xFF09090D);
  Color get _surfaceColor => _isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF0E0E12);
  Color get _cardBgColor => _isLightMode ? const Color(0xFFEFEFF4) : const Color(0xFF14141A);
  Color get _textColor => _isLightMode ? const Color(0xFF111115) : Colors.white;
  Color get _subtextColor => _isLightMode ? const Color(0xFF666670) : Colors.grey[400]!;

  Color get _accentColor {
    switch (_activeAccentTheme) {
      case 'Soft Sage':
        return const Color(0xFFA8C3A0);
      case 'Soft Lavender':
        return const Color(0xFFD4C1EC);
      case 'Soft Peach':
        return const Color(0xFFF7C59F);
      case 'Soft Rose':
        return const Color(0xFFF2B5D4);
      case 'Soft Sky Blue':
        return const Color(0xFFA0C4FF);
      case 'Neon Lime':
      default:
        return const Color(0xFFCCFF00);
    }
  }

  Color get _secondaryAccentColor {
    switch (_activeAccentTheme) {
      case 'Soft Sage':
        return const Color(0xFF8BAA82);
      case 'Soft Lavender':
        return const Color(0xFFB89FE1);
      case 'Soft Peach':
        return const Color(0xFFEEA876);
      case 'Soft Rose':
        return const Color(0xFFE291BE);
      case 'Soft Sky Blue':
        return const Color(0xFF7CB0FF);
      case 'Neon Lime':
      default:
        return const Color(0xFF99CC00);
    }
  }

  @override
  void initState() {
    super.initState();
    _initLocalSession();
  }

  Future<void> _initLocalSession() async {
    // Auto-detect server host based on active platform using defaultTargetPlatform (safe to call before initState completes)
    final isDesktopOrWeb = kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux;
    _prefs = await SharedPreferences.getInstance();
    
    final defaultHost = isDesktopOrWeb ? '127.0.0.1:8000' : '10.0.2.2:8000';
    
    final userId = _prefs.getString('user_id') ?? 'default_user';
    final userName = _prefs.getString('user_name') ?? 'friend';
    final userEmail = _prefs.getString('user_email') ?? '';
    final activeSessionId = "session_${userId}_${DateTime.now().millisecondsSinceEpoch}";

    setState(() {
      String savedAddress = _prefs.getString('server_address') ?? defaultHost;
      if (savedAddress == '10.74.123.51:8000' || savedAddress == 'localhost:8000' || (isDesktopOrWeb && savedAddress == '10.0.2.2:8000')) {
        savedAddress = defaultHost;
      }
      _serverAddress = savedAddress;
      _userId = userId;
      _userName = userName;
      _userEmail = userEmail;
      _currentSessionId = activeSessionId;
      _activeAccentTheme = _prefs.getString('echo_accent_theme') ?? 'Neon Lime';
      _activeAppMode = _prefs.getString('echo_app_mode') ?? 'Dark Mode';
    });

    _connectWebSocket();
    await _fetchVaultMemories();
    await _fetchUserProfile();
    await _fetchChatSessions();
  }

  void _connectWebSocket() {
    try {
      _channel?.sink.close();
      
      final protocol = _serverAddress.contains('localhost') || _serverAddress.contains('127.0.0.1') || _serverAddress.contains('10.0.2.2') ? 'ws' : 'wss';
      _channel = WebSocketChannel.connect(
        Uri.parse('$protocol://$_serverAddress/chat?user_id=$_userId'),
      );
      
      _channel!.ready.then((_) {
        if (mounted) {
          setState(() {
            _isServerConnected = true;
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() {
            _isServerConnected = false;
          });
        }
      });
      
      _channel!.stream.listen(
        (data) {
          final event = json.decode(data);
          if (mounted) {
            setState(() {
              _isServerConnected = true;
              _currentStage = event["stage"] ?? "idle";
            
            if (event["stage"] == "searching") {
              _stageMessage = "checking memories...";
              _recalledMemories = [];
              _searchResults = [];
            } else if (event["stage"] == "evaluating") {
              _stageMessage = "synthesizing response...";
              _confidenceScore = event["confidence"] ?? 95;
              _recalledMemories = event["recalled"] ?? [];
              _searchResults = event["sources"] ?? [];
            } else if (event["stage"] == "complete") {
              final replyText = event["reply"];
              _confidenceScore = event["confidence"] ?? 95;
              _recalledMemories = event["recalled"] ?? [];
              _searchResults = event["sources"] ?? [];
              
              // Save to local SQLite log
              DatabaseHelper.instance.addMessage({
                'session_id': _currentSessionId,
                'sender': 'echo',
                'text': replyText,
                'timestamp': DateTime.now().toIso8601String(),
              }).catchError((e) => print("DB Error saving AI response: $e"));

              if (event["new_fact_learned"] != null) {
                _fetchVaultMemories(); // Refresh memories list
              }
              _currentStage = "idle";
              _stageMessage = "";
              _fetchChatSessions(); // Refresh sessions
              
              _streamTypewriterResponse(replyText);
            }
          });
        }
      },
      onError: (_) {
          if (mounted) {
            setState(() {
              _isServerConnected = false;
              _currentStage = "idle";
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isServerConnected = false;
              _currentStage = "idle";
            });
          }
        }
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _currentStage = "idle";
        });
      }
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final profile = await DatabaseHelper.instance.getProfile(_userId);
      setState(() {
        _profile = profile;
      });
    } catch (e) {
      print("Failed to fetch profile: $e");
    }
  }

  Future<void> _fetchVaultMemories() async {
    try {
      final memories = await DatabaseHelper.instance.getVaultFacts(_userId);
      setState(() {
        _vaultMemories = memories;
      });
    } catch (e) {
      print("Failed to fetch vault: $e");
    }
  }

  Future<void> _fetchChatSessions() async {
    try {
      final sessions = await DatabaseHelper.instance.getChatSessions(_userId);
      setState(() {
        _chatSessions = sessions;
      });
    } catch (e) {
      print("Failed to fetch sessions: $e");
    }
  }

  Future<void> _loadSessionMessages(String sessionId) async {
    try {
      final loadedMessages = await DatabaseHelper.instance.getSessionMessages(sessionId);
      setState(() {
        _currentSessionId = sessionId;
        _messages.clear();
        for (var msg in loadedMessages) {
          _messages.add({
            "sender": msg["sender"],
            "text": msg["text"],
            "confidence": 98,
          });
        }
      });
      _scrollToBottom();
    } catch (e) {
      print("Failed to load session messages: $e");
    }
  }

  Future<void> _startNewChat() async {
    final activeSessionId = "session_${_userId}_${DateTime.now().millisecondsSinceEpoch}";
    setState(() {
      _currentSessionId = activeSessionId;
      _messages.clear();
      _recalledMemories.clear();
      _searchResults.clear();
      _currentStage = "idle";
      _stageMessage = "";
    });
    await _fetchChatSessions();
    _connectWebSocket();
  }

  // ignore: unused_element
  Future<void> _logout() async {
    await _prefs.remove('user_id');
    await _prefs.remove('user_name');
    await _prefs.remove('user_email');
    _channel?.sink.close();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _shareCurrentChat() async {
    HapticFeedback.lightImpact();
    if (_messages.isEmpty) return;
    final buffer = StringBuffer("--- Echo AI Chat Transcript ---\n\n");
    for (var m in _messages) {
      final sender = m['sender'] == 'user' ? 'You' : 'Echo';
      buffer.writeln("$sender: ${m['text']}\n");
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: _accentColor,
          content: Text(
            'Chat transcript copied to clipboard!',
            style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _deleteCurrentChat() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text('Delete Conversation?', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this conversation history?', style: GoogleFonts.outfit(color: _subtextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _subtextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final targetSessionId = _currentSessionId;
      setState(() {
        _messages.clear();
        _recalledMemories.clear();
        _searchResults.clear();
        _currentStage = "idle";
        _stageMessage = "";
      });
      await DatabaseHelper.instance.deleteChatSession(targetSessionId);
      await _startNewChat();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
            content: Text('Conversation deleted.', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mime = image.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        setState(() {
          _selectedImage = image;
          _selectedImageBase64 = base64Str;
          _selectedImageMimeType = mime;
        });
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBase64 = null;
      _selectedImageMimeType = null;
    });
  }

  Future<void> _sendMessage([String? customPrompt]) async {
    final text = customPrompt ?? _messageController.text.trim();
    final imageBase64 = _selectedImageBase64;
    final imageMimeType = _selectedImageMimeType;
    final String activeSessionId = _currentSessionId;
    
    if (text.isEmpty && imageBase64 == null) return;

    HapticFeedback.lightImpact();

    setState(() {
      _messages.add({
        "sender": "user",
        "text": text,
        "image_base64": imageBase64,
      });
      _messageController.clear();
      _selectedImage = null;
      _selectedImageBase64 = null;
      _selectedImageMimeType = null;
    });
    _scrollToBottom();

    // Save session and user message to SQLite
    try {
      await DatabaseHelper.instance.addChatSession(activeSessionId, _userId);
      await DatabaseHelper.instance.addMessage({
        'session_id': activeSessionId,
        'sender': 'user',
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("Local DB Error saving user message: $e");
    }

    // 1. Scan SQLite memories matching text for contextual RAG injection
    List<Map<String, dynamic>> activeMemories = [];
    try {
      final allFacts = await DatabaseHelper.instance.getVaultFacts(_userId);
      final words = text.toLowerCase().split(' ');
      for (var m in allFacts) {
        final content = (m['content'] as String?)?.toLowerCase() ?? '';
        for (var word in words) {
          if (word.length > 3 && content.contains(word)) {
            activeMemories.add(m);
            break;
          }
        }
      }
    } catch (e) {
      print("Local DB Error scanning memories: $e");
    }

    // 2. Extract conversation history thread
    final historyPayload = _messages.sublist(0, _messages.length - 1).map((m) => {
      'role': m['sender'] == 'user' ? 'user' : 'assistant',
      'content': (m['text'] as String?) ?? '',
    }).toList();

    // Show typing indicator while generating response!
    if (mounted) {
      setState(() {
        _currentStage = "thinking";
        _stageMessage = "";
      });
      _scrollToBottom();
    }

    // 3. Call the client-side LlmService to get a real LLM chat response with full thread history!
    final responseText = await LlmService.generateChatResponse(
      userMessage: text,
      memories: activeMemories,
      profile: _profile,
      history: historyPayload,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );

    // Always persist AI response to SQLite database regardless of UI state
    try {
      await DatabaseHelper.instance.addMessage({
        'session_id': activeSessionId,
        'sender': 'echo',
        'text': responseText,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("Local DB Error saving AI message: $e");
    }

    // Auto-generate AI Title for new session on first message
    if (_messages.length <= 1) {
      LlmService.generateSessionTitle(text.isNotEmpty ? text : "Image analysis").then((aiTitle) async {
        await DatabaseHelper.instance.updateSessionTitle(activeSessionId, aiTitle);
        if (mounted) _fetchChatSessions();
      });
    }

    // Asynchronously extract facts from the message to store in SQLite vault!
    LlmService.extractMemory(
      userMessage: text,
      memories: activeMemories,
    ).then((extracted) async {
      if (extracted != null && extracted['fact_text'] != null && extracted['transition_state'] != 'UNCERTAIN') {
        final extractedFact = extracted['fact_text'] as String;
        final factType = extracted['fact_type'] ?? 'general';
        try {
          await DatabaseHelper.instance.addVaultFact({
            'user_id': _userId,
            'category': factType,
            'content': extractedFact,
            'importance': 3,
            'confidence': 0.95,
            'source': 'chat',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'last_recalled_at': '',
            'status': 'active',
          });
          if (mounted) await _fetchVaultMemories();
        } catch (e) {
          print("Local DB Error saving extracted vault fact: $e");
        }
      }
    });

    if (mounted) {
      _fetchChatSessions();
      if (_currentSessionId == activeSessionId) {
        await _streamTypewriterResponse(responseText);
      }
    }
  }

  Future<void> _streamTypewriterResponse(String fullText) async {
    final messageIndex = _messages.length;
    setState(() {
      _messages.add({
        "sender": "echo",
        "text": "",
        "is_typing": true,
      });
      _currentStage = "idle";
      _stageMessage = "";
    });
    _scrollToBottom();

    final words = fullText.split(' ');
    if (words.isEmpty) return;

    String currentBuffer = "";
    // Reveal 1-3 words per burst tick for ultra-fast, fluid natural word-chunk typing
    int chunkSize = words.length > 50 ? 3 : (words.length > 20 ? 2 : 1);

    for (int i = 0; i < words.length; i += chunkSize) {
      if (!mounted) return;
      int end = (i + chunkSize < words.length) ? i + chunkSize : words.length;
      final burst = words.sublist(i, end).join(" ");
      currentBuffer += (currentBuffer.isEmpty ? "" : " ") + burst;

      setState(() {
        _messages[messageIndex]["text"] = currentBuffer;
      });
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 14));
    }

    if (mounted) {
      setState(() {
        _messages[messageIndex]["text"] = fullText;
        _messages[messageIndex]["is_typing"] = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSidebarDrawer() {
    return Drawer(
      backgroundColor: _surfaceColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            decoration: BoxDecoration(
              color: _bgColor,
              border: Border(bottom: BorderSide(color: _textColor.withValues(alpha: 0.08), width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_accentColor, _secondaryAccentColor],
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: Colors.transparent,
                    radius: 26,
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'F',
                      style: GoogleFonts.outfit(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: _textColor),
                      ),
                      Text(
                        _userEmail,
                        style: GoogleFonts.outfit(color: _subtextColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          // New Chat Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [_accentColor, _secondaryAccentColor],
                ),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _startNewChat();
                },
                icon: const Icon(Icons.add, size: 20, color: Colors.black),
                label: Text('New Chat', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ),
          ),
          Divider(color: _textColor.withValues(alpha: 0.08), height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 12, bottom: 6),
            child: Row(
              children: [
                Icon(Icons.history_outlined, size: 16, color: _subtextColor),
                const SizedBox(width: 6),
                Text(
                  'Chat History',
                  style: GoogleFonts.outfit(color: _subtextColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildSessionsTabContent(),
          ),
          const Divider(color: Colors.white10),
          // Settings Option
          ListTile(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((shouldRefresh) {
                _initLocalSession();
                if (shouldRefresh == true) {
                  _fetchVaultMemories();
                  _fetchUserProfile();
                }
              });
            },
            leading: Icon(Icons.settings_outlined, color: _textColor),
            title: Text(
              'Settings',
              style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSessionsTabContent() {
    // Filter non-archived sessions
    final activeSessions = _chatSessions.where((s) => (s['is_archived'] ?? 0) == 0).toList();
    if (activeSessions.isEmpty) {
      return Center(
        child: Text(
          'No active conversations.',
          style: GoogleFonts.outfit(color: Colors.grey[500]),
        ),
      );
    }

    final pinnedSessions = activeSessions.where((s) => (s['is_pinned'] ?? 0) == 1).toList();
    final recentSessions = activeSessions.where((s) => (s['is_pinned'] ?? 0) == 0).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pinnedSessions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(Icons.push_pin, color: _accentColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'PINNED',
                  style: GoogleFonts.outfit(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
          ),
          ...pinnedSessions.map((s) => _buildSessionTile(s)),
          const SizedBox(height: 12),
        ],
        if (recentSessions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              'RECENT',
              style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
          ...recentSessions.map((s) => _buildSessionTile(s)),
        ],
      ],
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> session) {
    final String sessionId = session["session_id"];
    final bool isCurrent = sessionId == _currentSessionId;
    final bool isPinned = (session["is_pinned"] ?? 0) == 1;

    return Dismissible(
      key: Key("session_$sessionId"),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: _accentColor.withValues(alpha: 0.2),
        child: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: _accentColor),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.amber.withValues(alpha: 0.2),
        child: const Icon(Icons.archive_outlined, color: Colors.amber),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          // Swipe Right -> Toggle Pin
          await _togglePinSession(sessionId, !isPinned);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          // Swipe Left -> Archive
          await _archiveSession(sessionId);
          return true;
        }
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          onTap: () {
            Navigator.pop(context);
            _loadSessionMessages(sessionId);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showSessionOptionsSheet(sessionId, isPinned);
          },
          tileColor: isCurrent ? _accentColor.withValues(alpha: 0.08) : _cardBgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCurrent ? _accentColor.withValues(alpha: 0.4) : _textColor.withValues(alpha: 0.05),
            ),
          ),
          leading: isPinned
              ? Icon(Icons.push_pin, color: _accentColor, size: 18)
              : Icon(Icons.chat_bubble_outline, color: _subtextColor, size: 18),
          title: Text(
            session["title"]?.isNotEmpty == true
                ? session["title"]
                : (session["last_message"]?.isNotEmpty == true ? session["last_message"] : "Empty conversation"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: isCurrent ? _accentColor : _textColor,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            session["created_at"]?.toString().split('T').first ?? "",
            style: GoogleFonts.outfit(fontSize: 11, color: _subtextColor),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePinSession(String sessionId, bool pinState) async {
    await DatabaseHelper.instance.updateSessionPin(sessionId, pinState);
    await _fetchChatSessions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: _accentColor,
          content: Text(
            pinState ? 'Conversation pinned to top!' : 'Conversation unpinned.',
            style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _archiveSession(String sessionId) async {
    await DatabaseHelper.instance.updateSessionArchive(sessionId, true);
    if (sessionId == _currentSessionId) {
      await _startNewChat();
    } else {
      await _fetchChatSessions();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.amber,
          content: Text(
            'Conversation archived.',
            style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  void _showSessionOptionsSheet(String sessionId, bool isPinned) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101014),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: _accentColor),
              title: Text(isPinned ? 'Unpin Chat' : 'Pin to Top', style: GoogleFonts.outfit(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _togglePinSession(sessionId, !isPinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.amber),
              title: Text('Archive Chat', style: GoogleFonts.outfit(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _archiveSession(sessionId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.purpleAccent),
              title: Text('Share Conversation Card', style: GoogleFonts.outfit(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final msgs = await DatabaseHelper.instance.getSessionMessages(sessionId);
                if (msgs.isNotEmpty) {
                  final lastText = msgs.last['text'] ?? '';
                  final isUser = msgs.last['sender'] == 'user';
                  _showShareCardModal(lastText, isUser);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('Delete Chat', style: GoogleFonts.outfit(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await DatabaseHelper.instance.deleteChatSession(sessionId);
                if (sessionId == _currentSessionId) {
                  await _startNewChat();
                } else {
                  await _fetchChatSessions();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showBubbleMenu(BuildContext context, Map<String, dynamic> message, int index) {
    HapticFeedback.mediumImpact();
    final bool isUser = message["sender"] == "user";
    final String text = message["text"] ?? "";

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUser)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: _accentColor),
                  title: Text('Edit & Regenerate', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('Updates message & regenerates AI conversation', style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditMessageDialog(text, index);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: Colors.white),
                title: Text('Copy Text', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      backgroundColor: _accentColor,
                      content: Text('Copied to clipboard!', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: Colors.purpleAccent),
                title: Text('Share as Privacy Card', style: GoogleFonts.outfit(color: Colors.white)),
                subtitle: Text('Creates visual snippet card (no account data exposed)', style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  _showShareCardModal(text, isUser);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditMessageDialog(String currentText, int index) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
          title: Text('Edit Message', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            maxLines: 4,
            style: GoogleFonts.outfit(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Edit your prompt...',
              hintStyle: GoogleFonts.outfit(color: Colors.grey[600]),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _accentColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[400])),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final newText = controller.text.trim();
                if (newText.isNotEmpty && newText != currentText) {
                  Navigator.pop(context);
                  await _executeMessageEditAndRegenerate(index, newText);
                }
              },
              child: Text('Save & Regenerate', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeMessageEditAndRegenerate(int editedIndex, String editedText) async {
    HapticFeedback.heavyImpact();

    // 1. Get messages to purge from local database
    final messages = await DatabaseHelper.instance.getSessionMessages(_currentSessionId);
    if (editedIndex < messages.length) {
      final targetMsg = messages[editedIndex];
      final targetId = targetMsg['id'] as int;

      // Update target message text
      await DatabaseHelper.instance.updateMessage(targetId, editedText);

      // Purge subsequent message IDs in SQLite database
      await DatabaseHelper.instance.deleteMessageAfter(_currentSessionId, targetId);
    }

    // 2. Truncate local state up to edited index
    setState(() {
      _messages.removeRange(editedIndex, _messages.length);
      _messages.add({
        "sender": "user",
        "text": editedText,
      });
      _currentStage = "thinking";
      _stageMessage = "echo is regenerating...";
    });
    _scrollToBottom();

    // 3. Trigger LLM regeneration
    final activeMemories = await DatabaseHelper.instance.getVaultFacts(_userId);
    final responseText = await LlmService.generateChatResponse(
      userMessage: editedText,
      memories: activeMemories,
      profile: _profile,
    );

    // Save regenerated message to SQLite database
    await DatabaseHelper.instance.addMessage({
      'session_id': _currentSessionId,
      'sender': 'echo',
      'text': responseText,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await _fetchChatSessions();
    await _streamTypewriterResponse(responseText);
  }

  void _showShareCardModal(String text, bool isUser) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F14),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(8)),
              ),
              const SizedBox(height: 20),
              Text(
                'Echo Share Card',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Privacy-First Snippet (No personal account data included)',
                style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(height: 24),
              // Card Canvas Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A22), Color(0xFF0B0B0E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: _accentColor.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: _accentColor, shape: BoxShape.circle),
                              child: const Icon(Icons.psychology, color: Colors.black, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Echo Companion',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            isUser ? 'USER MESSAGE' : 'ECHO RESPONSE',
                            style: GoogleFonts.outfit(color: _accentColor, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '"$text"',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 15, height: 1.4, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Shared via Echo AI', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 10)),
                        Text('echo.ai', style: GoogleFonts.outfit(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text('Copy Snippet Text', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '"$text" — Echo AI'));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _accentColor,
                        content: Text('Card text copied! Ready to paste & share.', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      drawer: _buildSidebarDrawer(),
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: _textColor.withValues(alpha: 0.05),
            height: 1.0,
          ),
        ),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(Icons.menu, color: _textColor),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _accentColor.withValues(alpha: 0.7), blurRadius: 6, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Echo',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                Text(
                  'Online Companion',
                  style: GoogleFonts.outfit(fontSize: 10, color: _subtextColor, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_note_outlined, color: _textColor),
            tooltip: 'New Chat',
            onPressed: _startNewChat,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _textColor),
            tooltip: 'Chat Actions',
            color: _surfaceColor,
            onSelected: (value) async {
              if (value == 'pin') {
                final currentSession = _chatSessions.firstWhere(
                  (s) => s['session_id'] == _currentSessionId,
                  orElse: () => {'is_pinned': 0},
                );
                final isPinned = (currentSession['is_pinned'] ?? 0) == 1;
                await _togglePinSession(_currentSessionId, !isPinned);
              } else if (value == 'archive') {
                await _archiveSession(_currentSessionId);
              } else if (value == 'share') {
                _shareCurrentChat();
              } else if (value == 'delete') {
                _deleteCurrentChat();
              }
            },
            itemBuilder: (context) {
              final currentSession = _chatSessions.firstWhere(
                (s) => s['session_id'] == _currentSessionId,
                orElse: () => {'is_pinned': 0},
              );
              final isPinned = (currentSession['is_pinned'] ?? 0) == 1;
              return [
                PopupMenuItem(
                  value: 'pin',
                  child: Row(
                    children: [
                      Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: _textColor, size: 20),
                      const SizedBox(width: 12),
                      Text(isPinned ? 'Unpin Chat' : 'Pin Chat', style: GoogleFonts.outfit(color: _textColor)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, color: _textColor, size: 20),
                      const SizedBox(width: 12),
                      Text('Archive Chat', style: GoogleFonts.outfit(color: _textColor)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: _textColor, size: 20),
                      const SizedBox(width: 12),
                      Text('Share Chat', style: GoogleFonts.outfit(color: _textColor)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Text('Delete Chat', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Builder(
        builder: (innerContext) {
          return GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
                Scaffold.of(innerContext).openDrawer();
              }
            },
            child: Container(
              color: _bgColor,
              child: Column(
          children: [
            // Chat list
            Expanded(
              child: (_messages.isEmpty && _currentStage == "idle")
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 120),
                          // Clean Human Premium Heading & Subtitle
                          Text(
                            "How can I help you today?",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: _textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Ask a question, analyze images, or chat freely.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: _subtextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_currentStage != "idle" ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const TypingIndicator();
                      }
                      
                      final message = _messages[index];
                      final isEcho = message["sender"] == "echo";
                      final imageBase64 = message["image_base64"] as String?;
                      
                      return Align(
                        alignment: isEcho ? Alignment.centerLeft : Alignment.centerRight,
                        child: InkWell(
                          onLongPress: () => _showBubbleMenu(context, message, index),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78,
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: isEcho
                                  ? null
                                  : LinearGradient(
                                      colors: _isLightMode
                                          ? [const Color(0xFF1F1F24), const Color(0xFF141418)]
                                          : [const Color(0xFF22222B), const Color(0xFF17171F)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              color: isEcho
                                  ? (_isLightMode ? const Color(0xFFEFEFF4) : const Color(0xFF14141A))
                                  : null,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(isEcho ? 4 : 20),
                                bottomRight: Radius.circular(isEcho ? 20 : 4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ],
                              border: Border.all(
                                color: isEcho
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : _accentColor.withValues(alpha: 0.3),
                                width: isEcho ? 1.0 : 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (imageBase64 != null && imageBase64.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      base64Decode(imageBase64),
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if ((message["text"] as String?)?.isNotEmpty == true)
                                  Text(
                                    (message["text"] ?? "") + (message["is_typing"] == true ? " ▌" : ""),
                                    style: GoogleFonts.outfit(
                                      fontSize: 15.5,
                                      color: Colors.white,
                                      fontWeight: isEcho ? FontWeight.w400 : FontWeight.w500,
                                      height: 1.38,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Typing / Input field & Attachment preview container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              border: Border(
                top: BorderSide(color: _textColor.withValues(alpha: 0.08), width: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Attached Image Thumbnail Preview Bar
                if (_selectedImageBase64 != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _cardBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accentColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(_selectedImageBase64!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Image attached",
                                style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                "Ready for Echo to analyze",
                                style: GoogleFonts.outfit(color: _subtextColor, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 22),
                          onPressed: _clearSelectedImage,
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    // Media Attachment Button
                    IconButton(
                      icon: Icon(
                        Icons.add_a_photo_outlined,
                        color: _selectedImageBase64 != null ? _accentColor : _subtextColor,
                        size: 24,
                      ),
                      tooltip: 'Attach Image',
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: _surfaceColor,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (ctx) => Wrap(
                            children: [
                              ListTile(
                                leading: Icon(Icons.photo_library_outlined, color: _accentColor),
                                title: Text('Choose from Gallery', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.w600)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _pickImage(ImageSource.gallery);
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.camera_alt_outlined, color: _accentColor),
                                title: Text('Take a Photo', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.w600)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _pickImage(ImageSource.camera);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _cardBgColor,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: _textColor.withValues(alpha: 0.08)),
                        ),
                        child: TextField(
                          controller: _messageController,
                          style: GoogleFonts.outfit(color: _textColor),
                          decoration: InputDecoration(
                            hintText: _selectedImageBase64 != null ? 'Ask about this image...' : 'Message Echo...',
                            hintStyle: GoogleFonts.outfit(color: _subtextColor),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_accentColor, _secondaryAccentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: CircleAvatar(
                        backgroundColor: Colors.transparent,
                        radius: 22,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward, color: Colors.black, size: 20),
                          onPressed: () => _sendMessage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
},
),
);
}
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16161a),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = index * 0.2;
                final value = (_controller.value - delay).clamp(0.0, 1.0);
                final offset = -4.0 * (value < 0.5 ? value : 1.0 - value);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3.0),
                  transform: Matrix4.translationValues(0.0, offset, 0.0),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
