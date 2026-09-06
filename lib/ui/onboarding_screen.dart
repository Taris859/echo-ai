import 'dart:convert';
import 'package:flutter/material.dart';
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
      // 1. Configure and trigger Google Sign-In with Web Client ID to support Web builds
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: '1002423283701-kvjmood1mu8bbu7kc64e11535rvhmll7.apps.googleusercontent.com',
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return; // User cancelled
      }

      // 2. Fetch Native Auth Credentials
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. Authenticate against Firebase Auth instance
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Firebase user is null after authentication");
      }

      // 4. Retrieve secure ID Token to verify on backend
      final String? idToken = await firebaseUser.getIdToken();
      if (idToken == null) {
        throw Exception("Failed to retrieve ID Token from Firebase");
      }

      final name = firebaseUser.displayName ?? 'friend';
      final email = firebaseUser.email ?? '';
      final String userId = firebaseUser.uid;

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
          body: json.encode({"id_token": idToken}),
        ).timeout(const Duration(seconds: 2));
      } catch (e) {
        print("Backend sync deferred. Local offline setup bootstrap: $e");
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
      print("Google Auth Flow Error: $e");
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F0F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.white10),
              ),
              title: Text(
                "Sign-In Options",
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                "Google Sign-In is currently unavailable on this device.\n\nWould you like to proceed with a local companion profile instead?",
                style: GoogleFonts.outfit(color: Colors.grey[300]),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isLoading = false;
                    });
                  },
                  child: Text(
                    "Cancel",
                    style: GoogleFonts.outfit(color: Colors.grey[400]),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCCFF00),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _proceedWithLocalProfile();
                  },
                  child: Text(
                    "Use Local Profile",
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
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
      print("Local Profile Fallback Error: $e");
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
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                child: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Connecting Google Sign-In...',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'let\'s go',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
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
