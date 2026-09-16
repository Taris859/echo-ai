import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../services/database_helper.dart';
import 'chat_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Configure Google Sign-In (clientId only needed explicitly on Web)
      final GoogleSignIn googleSignIn = kIsWeb
          ? GoogleSignIn(clientId: '649382462716-bm2bfkd2mgnugqc9d1s4u89asej58jne.apps.googleusercontent.com')
          : GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return; // User cancelled
      }

      String name = googleUser.displayName ?? 'friend';
      String email = googleUser.email;
      String userId = googleUser.id;

      // Try Firebase authentication if Firebase options exist, otherwise use direct Google Account
      try {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        if (googleAuth.idToken != null || googleAuth.accessToken != null) {
          final AuthCredential credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
          if (userCredential.user != null) {
            name = userCredential.user!.displayName ?? name;
            email = userCredential.user!.email ?? email;
            userId = userCredential.user!.uid;
          }
        }
      } catch (_) {
        // Firebase optional; proceed with direct Google Account credentials
      }

      // Store session details locally for app state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setString('user_name', name);
      await prefs.setString('user_email', email);

      // Save user model in local SQLite
      await DatabaseHelper.instance.saveUser({
        'id': userId,
        'name': name,
        'email': email,
        'google_id': userId,
      });

      // Try syncing session securely to FastAPI backend (if reachable)
      final serverAddress = prefs.getString('server_address') ?? '10.0.2.2:8000';
      final protocol = serverAddress.contains('localhost') || serverAddress.contains('10.0.2.2') ? 'http' : 'https';
      
      try {
        await http.post(
          Uri.parse('$protocol://$serverAddress/auth/verify-token'),
          headers: {"Content-Type": "application/json"},
          body: json.encode({"user_id": userId, "email": email, "name": name}),
        ).timeout(const Duration(seconds: 2));
      } catch (_) {
        // Backend sync deferred; offline mode active
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) => const ChatScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      debugPrint("Google Auth Flow Exception (Auto-proceeding to local companion profile): $e");
      if (mounted) {
        await _proceedWithLocalProfile();
      }
    }
  }

  Future<void> _proceedWithLocalProfile() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final String localId = "local_${DateTime.now().millisecondsSinceEpoch}";
      final name = 'Companion Friend';
      final email = 'companion@echo.ai';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', localId);
      await prefs.setString('user_name', name);
      await prefs.setString('user_email', email);

      await DatabaseHelper.instance.saveUser({
        'id': localId,
        'name': name,
        'email': email,
        'google_id': '',
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) => const ChatScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      debugPrint("Local Profile Fallback Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to create local profile: $e")),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 50.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              children: [
                Image.asset(
                  'assests/logo/logo.png',
                  width: 42,
                  height: 42,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                Text(
                  'echo',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              'you talk.\necho\nremembers.',
              style: GoogleFonts.outfit(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'echo is an AI that actually pays attention to your memories, preferences, and relationships.',
              style: GoogleFonts.outfit(
                fontSize: 18,
                color: Colors.grey[400],
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                icon: const Icon(Icons.login, color: Colors.black),
                label: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Connecting Google...',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'sign in with google',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[800]!, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: _isLoading ? null : _proceedWithLocalProfile,
                child: Text(
                  'continue as guest (instant access)',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[300],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
