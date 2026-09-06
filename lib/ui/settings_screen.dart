import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SharedPreferences _prefs;
  bool _isLoaded = false;

  // User Profile
  String _userId = "default_user";
  String _userName = "friend";
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  // Settings
  String _activePersonality = 'Best Friend';
  String _activeEmojis = 'More Emojis';
  bool _activeAdult = false;
  String _activeAccentTheme = 'Neon Lime';
  String _activeAppMode = 'Dark Mode';

  // Memories & Archived Chats
  List<Map<String, dynamic>> _vaultMemories = [];
  List<Map<String, dynamic>> _archivedSessions = [];

  bool get _isLightMode => _activeAppMode == 'Light Mode';
  Color get _bgColor => _isLightMode ? const Color(0xFFF7F8FA) : const Color(0xFF09090B);
  Color get _cardBgColor => _isLightMode ? Colors.white : const Color(0xFF121216);
  Color get _textColor => _isLightMode ? const Color(0xFF0F0F12) : Colors.white;
  Color get _subtextColor => _isLightMode ? const Color(0xFF6E6E77) : const Color(0xFF8E8E9A);

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
      case 'Neon Pink':
        return const Color(0xFFFF00FF);
      case 'Neon Blue':
        return const Color(0xFF00FFFF);
      case 'Neon Lime':
      default:
        return const Color(0xFFCCFF00);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final userId = _prefs.getString('user_id') ?? 'default_user';
      final userName = _prefs.getString('user_name') ?? 'friend';

      final profile = await DatabaseHelper.instance.getProfile(userId);
      final memories = await DatabaseHelper.instance.getVaultFacts(userId);
      final allSessions = await DatabaseHelper.instance.getChatSessions(userId);
      final archived = allSessions.where((s) => s['is_archived'] == 1).toList();

      if (mounted) {
        setState(() {
          _userId = userId;
          _userName = userName;
          _vaultMemories = memories;
          _archivedSessions = archived;

          _nameCtrl.text = profile["name"] == "friend" ? "" : (profile["name"] ?? "");
          _ageCtrl.text = (profile["age"] == 0 || profile["age"] == null) ? "" : profile["age"].toString();
          _genderCtrl.text = profile["gender"] == "unknown" ? "" : (profile["gender"] ?? "");
          _bioCtrl.text = profile["bio"] ?? "";

          _activePersonality = _prefs.getString('echo_personality') ?? 'Best Friend';
          _activeEmojis = _prefs.getString('echo_emojis') ?? 'More Emojis';
          _activeAdult = _prefs.getBool('echo_adult') ?? false;
          _activeAccentTheme = _prefs.getString('echo_accent_theme') ?? 'Neon Lime';
          _activeAppMode = _prefs.getString('echo_app_mode') ?? 'Dark Mode';
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    }
  }

  Future<void> _saveProfileDetails() async {
    HapticFeedback.mediumImpact();
    final parsedAge = int.tryParse(_ageCtrl.text.trim()) ?? 0;
    final nameVal = _nameCtrl.text.trim().isEmpty ? "friend" : _nameCtrl.text.trim();

    final updatedProfile = {
      'user_id': _userId,
      'name': nameVal,
      'age': parsedAge,
      'gender': _genderCtrl.text.trim().isEmpty ? "unknown" : _genderCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    };

    await DatabaseHelper.instance.saveProfile(updatedProfile);
    await _prefs.setString('user_name', nameVal);
    setState(() {
      _userName = nameVal;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _accentColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            'Profile updated ✨',
            style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _saveBehaviorSettings() async {
    HapticFeedback.mediumImpact();
    await _prefs.setString('echo_personality', _activePersonality);
    await _prefs.setString('echo_emojis', _activeEmojis);
    await _prefs.setBool('echo_adult', _activeAdult);
    await _prefs.setString('echo_accent_theme', _activeAccentTheme);
    await _prefs.setString('echo_app_mode', _activeAppMode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _accentColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            'Preferences saved ✨',
            style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  Future<void> _performLogout() async {
    HapticFeedback.mediumImpact();
    await _prefs.remove('user_id');
    await _prefs.remove('user_name');
    await _prefs.remove('user_email');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _deleteMemory(int id) async {
    HapticFeedback.mediumImpact();
    await DatabaseHelper.instance.deleteVaultFact(id);
    final memories = await DatabaseHelper.instance.getVaultFacts(_userId);
    setState(() {
      _vaultMemories = memories;
    });
  }

  Future<void> _eraseAllMemories() async {
    HapticFeedback.heavyImpact();
    await DatabaseHelper.instance.clearAllVaultFacts(_userId);
    setState(() {
      _vaultMemories = [];
    });
  }

  Future<void> _unarchiveChat(String sessionId) async {
    HapticFeedback.mediumImpact();
    await DatabaseHelper.instance.updateSessionArchive(sessionId, false);
    await _loadAllSettings();
  }

  Future<void> _deleteChat(String sessionId) async {
    HapticFeedback.heavyImpact();
    await DatabaseHelper.instance.deleteChatSession(sessionId);
    await _loadAllSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: CircularProgressIndicator(color: _accentColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: _textColor, size: 18),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: _textColor,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header Card
            _buildProfileHeaderCard(),
            const SizedBox(height: 20),

            // Profile Info Section
            _buildSectionLabel('YOUR IDENTITY'),
            const SizedBox(height: 8),
            _buildCardContainer(
              child: Column(
                children: [
                  _buildTextField(controller: _nameCtrl, label: 'Name', icon: Icons.person_outline),
                  const Divider(height: 16, indent: 40),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(controller: _ageCtrl, label: 'Age', icon: Icons.cake_outlined, isNumber: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTextField(controller: _genderCtrl, label: 'Gender', icon: Icons.wc_outlined)),
                    ],
                  ),
                  const Divider(height: 16, indent: 40),
                  _buildTextField(controller: _bioCtrl, label: 'Bio / Personal Notes', icon: Icons.edit_note_outlined, maxLines: 2),
                  const SizedBox(height: 16),
                  _buildActionButton('Save Profile', _saveProfileDetails),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Companion Behavior Section
            _buildSectionLabel('COMPANION & LOOK'),
            const SizedBox(height: 8),
            _buildCardContainer(
              child: Column(
                children: [
                  _buildDropdownRow(
                    title: 'Personality Mode',
                    icon: Icons.psychology_outlined,
                    value: _activePersonality,
                    items: ['Friendly', 'Best Friend', 'Research'],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _activePersonality = val);
                        _saveBehaviorSettings();
                      }
                    },
                  ),
                  const Divider(height: 16, indent: 40),
                  _buildDropdownRow(
                    title: 'Emoji Vibe',
                    icon: Icons.sentiment_satisfied_alt_outlined,
                    value: _activeEmojis,
                    items: ['More Emojis', 'Less Emojis'],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _activeEmojis = val);
                        _saveBehaviorSettings();
                      }
                    },
                  ),
                  const Divider(height: 16, indent: 40),
                  _buildDropdownRow(
                    title: 'Theme Mode',
                    icon: Icons.dark_mode_outlined,
                    value: _activeAppMode,
                    items: ['Dark Mode', 'Light Mode'],
                    onChanged: (val) async {
                      if (val != null) {
                        setState(() => _activeAppMode = val);
                        await _prefs.setString('echo_app_mode', val);
                      }
                    },
                  ),
                  const Divider(height: 16, indent: 40),
                  _buildDropdownRow(
                    title: 'Accent Color',
                    icon: Icons.palette_outlined,
                    value: _activeAccentTheme,
                    items: ['Neon Lime', 'Soft Sage', 'Soft Lavender', 'Soft Peach', 'Soft Rose', 'Soft Sky Blue', 'Neon Pink', 'Neon Blue'],
                    onChanged: (val) async {
                      if (val != null) {
                        setState(() => _activeAccentTheme = val);
                        await _prefs.setString('echo_accent_theme', val);
                      }
                    },
                  ),
                  const Divider(height: 16, indent: 40),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: _accentColor,
                    secondary: Icon(Icons.style_outlined, color: _subtextColor, size: 20),
                    title: Text('Adult & Spicy Mode', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Allows mature, flirtatious conversations freely.', style: GoogleFonts.outfit(color: _subtextColor, fontSize: 12)),
                    value: _activeAdult,
                    onChanged: (val) {
                      setState(() => _activeAdult = val);
                      _saveBehaviorSettings();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Memory Vault Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionLabel('MEMORY VAULT (${_vaultMemories.length})'),
                if (_vaultMemories.isNotEmpty)
                  GestureDetector(
                    onTap: _eraseAllMemories,
                    child: Text(
                      'Clear All',
                      style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCardContainer(
              child: _vaultMemories.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No memories saved yet. Echo remembers facts automatically as you chat.',
                        style: GoogleFonts.outfit(color: _subtextColor, fontSize: 13),
                      ),
                    )
                  : Column(
                      children: _vaultMemories.take(5).map((m) {
                        final id = m['id'] as int?;
                        final content = m['content'] ?? m['text'] ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _textColor.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, color: _accentColor, size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(content, style: GoogleFonts.outfit(color: _textColor, fontSize: 13)),
                              ),
                              if (id != null)
                                GestureDetector(
                                  onTap: () => _deleteMemory(id),
                                  child: Icon(Icons.close, color: _subtextColor, size: 16),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 24),

            // Archived Conversations
            if (_archivedSessions.isNotEmpty) ...[
              _buildSectionLabel('ARCHIVED CHATS (${_archivedSessions.length})'),
              const SizedBox(height: 8),
              _buildCardContainer(
                child: Column(
                  children: _archivedSessions.map((session) {
                    final sessionId = session['session_id'] as String;
                    final lastMsg = session['last_message'] as String? ?? 'Empty conversation';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: _textColor, fontSize: 14)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.unarchive_outlined, color: _accentColor, size: 18),
                            onPressed: () => _unarchiveChat(sessionId),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                            onPressed: () => _deleteChat(sessionId),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // About Section
            _buildSectionLabel('ABOUT ECHO'),
            const SizedBox(height: 8),
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.bubble_chart_outlined, color: _accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Echo AI', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('v1.2.0-beta', style: GoogleFonts.outfit(color: _subtextColor, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Echo is designed to feel like a real friend—conversational, witty, empathetic, and powered by ultra-fast intelligence.',
                    style: GoogleFonts.outfit(color: _subtextColor, fontSize: 13, height: 1.4),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Founder & Owner', style: GoogleFonts.outfit(color: _subtextColor, fontSize: 13)),
                      Text('Tannu Bhukal', style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Log Out Button
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _performLogout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text('Log Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _textColor.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _accentColor,
            child: Text(
              _userName.isNotEmpty ? _userName[0].toUpperCase() : 'F',
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _userName,
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor),
              ),
              Text(
                'Echo Companion User',
                style: GoogleFonts.outfit(fontSize: 12, color: _subtextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: _subtextColor,
        ),
      ),
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _textColor.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      style: GoogleFonts.outfit(color: _textColor, fontSize: 14),
      decoration: InputDecoration(
        icon: Icon(icon, color: _subtextColor, size: 20),
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: _subtextColor, fontSize: 13),
        border: InputBorder.none,
        isDense: true,
      ),
    );
  }

  Widget _buildDropdownRow({
    required String title,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: _subtextColor, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(title, style: GoogleFonts.outfit(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            dropdownColor: _cardBgColor,
            value: value,
            style: GoogleFonts.outfit(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13),
            items: items.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }
}
