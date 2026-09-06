import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // Web Fallback In-Memory Storage
  static final Map<String, Map<String, dynamic>> _webUsers = {};
  static final Map<String, Map<String, dynamic>> _webProfiles = {};
  static final List<Map<String, dynamic>> _webVault = [];
  static final List<Map<String, dynamic>> _webSessions = [];
  static final List<Map<String, dynamic>> _webMessages = [];
  static int _webVaultIdCounter = 1;
  static int _webMessageIdCounter = 1;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite database is not supported on web.');
    }
    if (_database != null) return _database!;
    _database = await _initDB('echo_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE,
        name TEXT,
        google_id TEXT
      )
    ''');

    // Profiles table
    await db.execute('''
      CREATE TABLE profiles (
        user_id TEXT PRIMARY KEY,
        age INTEGER,
        gender TEXT,
        bio TEXT
      )
    ''');

    // Memory Vault table with lifecycle metadata
    await db.execute('''
      CREATE TABLE memory_vault (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        content TEXT,
        category TEXT,
        importance INTEGER,
        confidence REAL,
        source TEXT,
        created_at TEXT,
        updated_at TEXT,
        last_recalled_at TEXT,
        status TEXT
      )
    ''');

    // Chat Sessions table (with is_pinned, is_archived, and title migrations)
    await db.execute('''
      CREATE TABLE chat_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        created_at TEXT,
        title TEXT,
        is_pinned INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        sender TEXT,
        text TEXT,
        timestamp TEXT
      )
    ''');

    // Preferences table
    await db.execute('''
      CREATE TABLE preferences (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS memory_vault');
      await db.execute('''
        CREATE TABLE memory_vault (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT,
          content TEXT,
          category TEXT,
          importance INTEGER,
          confidence REAL,
          source TEXT,
          created_at TEXT,
          updated_at TEXT,
          last_recalled_at TEXT,
          status TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE chat_sessions ADD COLUMN is_pinned INTEGER DEFAULT 0');
      } catch (e) {
        print("Column is_pinned already exists or failed to add: $e");
      }
      try {
        await db.execute('ALTER TABLE chat_sessions ADD COLUMN is_archived INTEGER DEFAULT 0');
      } catch (e) {
        print("Column is_archived already exists or failed to add: $e");
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE chat_sessions ADD COLUMN title TEXT');
      } catch (e) {
        print("Column title already exists or failed to add: $e");
      }
    }
  }

  // --- Auth / User Operations ---
  Future<Map<String, dynamic>?> getUser(String id) async {
    if (kIsWeb) {
      return _webUsers[id];
    }
    final db = await instance.database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    if (kIsWeb) {
      final id = user['id'] as String;
      _webUsers[id] = Map<String, dynamic>.from(user);
      _webProfiles[id] = {
        'user_id': id,
        'age': 0,
        'gender': 'unknown',
        'bio': '',
      };
      return;
    }
    final db = await instance.database;
    await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Auto-create empty profile
    await db.insert(
      'profiles',
      {
        'user_id': user['id'],
        'age': 0,
        'gender': 'unknown',
        'bio': '',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // --- Profile Operations ---
  Future<Map<String, dynamic>> getProfile(String userId) async {
    if (kIsWeb) {
      final webProf = _webProfiles[userId] ?? {'user_id': userId, 'age': 0, 'gender': 'unknown', 'bio': ''};
      final webUser = _webUsers[userId];
      return {
        ...webProf,
        'name': webUser != null ? webUser['name'] : (webProf['name'] ?? 'friend'),
      };
    }
    final db = await instance.database;
    final maps = await db.query('profiles', where: 'user_id = ?', whereArgs: [userId]);
    final userMaps = await db.query('users', columns: ['name'], where: 'id = ?', whereArgs: [userId]);
    final name = userMaps.isNotEmpty ? userMaps.first['name'] : 'friend';
    
    if (maps.isNotEmpty) {
      final prof = Map<String, dynamic>.from(maps.first);
      prof['name'] = name;
      return prof;
    }
    return {'user_id': userId, 'name': name, 'age': 0, 'gender': 'unknown', 'bio': ''};
  }

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final userId = profile['user_id'] as String;
    final name = profile['name'] as String? ?? 'friend';
    
    if (kIsWeb) {
      _webProfiles[userId] = Map<String, dynamic>.from(profile);
      if (_webUsers[userId] != null) {
        _webUsers[userId]!['name'] = name;
      }
      return;
    }
    
    final db = await instance.database;
    // 1. Update name in users table
    await db.update('users', {'name': name}, where: 'id = ?', whereArgs: [userId]);
    
    // 2. Insert/replace profile in profiles table (excluding name)
    final profMap = Map<String, dynamic>.from(profile)..remove('name');
    await db.insert('profiles', profMap, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllVaultFacts(String userId) async {
    if (kIsWeb) {
      _webVault.removeWhere((element) => element['user_id'] == userId);
      return;
    }
    final db = await instance.database;
    await db.delete('memory_vault', where: 'user_id = ?', whereArgs: [userId]);
  }

  // --- Memory Vault Operations ---
  Future<List<Map<String, dynamic>>> getVaultFacts(String userId) async {
    if (kIsWeb) {
      return _webVault.where((element) => element['user_id'] == userId).toList().reversed.toList();
    }
    final db = await instance.database;
    return await db.query('memory_vault', where: 'user_id = ?', whereArgs: [userId], orderBy: 'id DESC');
  }

  Future<int> addVaultFact(Map<String, dynamic> fact) async {
    if (kIsWeb) {
      final mutableFact = Map<String, dynamic>.from(fact);
      final int id = mutableFact['id'] ?? _webVaultIdCounter++;
      mutableFact['id'] = id;
      _webVault.removeWhere((element) => element['id'] == id);
      _webVault.add(mutableFact);
      return id;
    }
    final db = await instance.database;
    return await db.insert('memory_vault', fact, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVaultFact(int id) async {
    if (kIsWeb) {
      _webVault.removeWhere((element) => element['id'] == id);
      return;
    }
    final db = await instance.database;
    await db.delete('memory_vault', where: 'id = ?', whereArgs: [id]);
  }

  // --- Chat Sessions Operations ---
  Future<List<Map<String, dynamic>>> getChatSessions(String userId) async {
    if (kIsWeb) {
      final List<Map<String, dynamic>> userSessions = _webSessions
          .where((s) => s['user_id'] == userId)
          .toList();
      
      final List<Map<String, dynamic>> result = [];
      for (var s in userSessions) {
        final sessionId = s['id'];
        final messages = _webMessages.where((m) => m['session_id'] == sessionId).toList();
        if (messages.isEmpty) continue; // Skip empty sessions
        final lastMessage = messages.last['text'];
        result.add({
          'session_id': sessionId,
          'created_at': s['created_at'],
          'title': s['title'],
          'last_message': lastMessage,
          'is_pinned': s['is_pinned'] ?? 0,
          'is_archived': s['is_archived'] ?? 0,
        });
      }
      result.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      return result;
    }
    final db = await instance.database;
    
    // Auto-purge orphaned empty sessions
    try {
      await db.delete('chat_sessions', where: 'id NOT IN (SELECT DISTINCT session_id FROM messages)');
    } catch (_) {}

    try {
      final result = await db.rawQuery('''
        SELECT s.id as session_id, s.created_at, s.is_pinned, s.is_archived, s.title,
          m.text as last_message
        FROM chat_sessions s
        INNER JOIN messages m ON m.id = (
          SELECT id FROM messages WHERE session_id = s.id ORDER BY id DESC LIMIT 1
        )
        WHERE s.user_id = ?
        ORDER BY s.is_pinned DESC, s.created_at DESC
      ''', [userId]);
      return result;
    } catch (e) {
      print("Error in getChatSessions, executing fallback: $e");
      try {
        final result = await db.rawQuery('''
          SELECT s.id as session_id, s.created_at, s.is_pinned, s.is_archived,
            m.text as last_message
          FROM chat_sessions s
          INNER JOIN messages m ON m.id = (
            SELECT id FROM messages WHERE session_id = s.id ORDER BY id DESC LIMIT 1
          )
          WHERE s.user_id = ?
          ORDER BY s.is_pinned DESC, s.created_at DESC
        ''', [userId]);
        return result;
      } catch (err) {
        print("Fallback getChatSessions error: $err");
        return [];
      }
    }
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    if (kIsWeb) {
      final index = _webSessions.indexWhere((s) => s['id'] == sessionId);
      if (index != -1) {
        _webSessions[index]['title'] = title;
      }
      return;
    }
    final db = await instance.database;
    await db.update(
      'chat_sessions',
      {'title': title},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> addChatSession(String sessionId, String userId) async {
    if (kIsWeb) {
      _webSessions.removeWhere((element) => element['id'] == sessionId);
      _webSessions.add({
        'id': sessionId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
        'is_pinned': 0,
        'is_archived': 0,
      });
      return;
    }
    final db = await instance.database;
    await db.insert(
      'chat_sessions',
      {
        'id': sessionId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
        'is_pinned': 0,
        'is_archived': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSessionPin(String sessionId, bool isPinned) async {
    if (kIsWeb) {
      final index = _webSessions.indexWhere((s) => s['id'] == sessionId);
      if (index != -1) {
        _webSessions[index]['is_pinned'] = isPinned ? 1 : 0;
      }
      return;
    }
    final db = await instance.database;
    await db.update(
      'chat_sessions',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> updateSessionArchive(String sessionId, bool isArchived) async {
    if (kIsWeb) {
      final index = _webSessions.indexWhere((s) => s['id'] == sessionId);
      if (index != -1) {
        _webSessions[index]['is_archived'] = isArchived ? 1 : 0;
      }
      return;
    }
    final db = await instance.database;
    await db.update(
      'chat_sessions',
      {'is_archived': isArchived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteChatSession(String sessionId) async {
    if (kIsWeb) {
      _webSessions.removeWhere((s) => s['id'] == sessionId);
      _webMessages.removeWhere((m) => m['session_id'] == sessionId);
      return;
    }
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);
      await txn.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    });
  }

  Future<void> deleteMessageAfter(String sessionId, int messageId) async {
    if (kIsWeb) {
      _webMessages.removeWhere((m) => m['session_id'] == sessionId && (m['id'] as int) > messageId);
      return;
    }
    final db = await instance.database;
    await db.delete(
      'messages',
      where: 'session_id = ? AND id > ?',
      whereArgs: [sessionId, messageId],
    );
  }

  Future<void> updateMessage(int messageId, String newText) async {
    if (kIsWeb) {
      final index = _webMessages.indexWhere((m) => m['id'] == messageId);
      if (index != -1) {
        _webMessages[index]['text'] = newText;
      }
      return;
    }
    final db = await instance.database;
    await db.update(
      'messages',
      {'text': newText},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // --- Message Operations ---
  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
    if (kIsWeb) {
      return _webMessages.where((element) => element['session_id'] == sessionId).toList();
    }
    final db = await instance.database;
    return await db.query('messages', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id ASC');
  }

  Future<void> addMessage(Map<String, dynamic> msg) async {
    if (kIsWeb) {
      final mutableMsg = Map<String, dynamic>.from(msg);
      mutableMsg['id'] = _webMessageIdCounter++;
      _webMessages.add(mutableMsg);
      return;
    }
    final db = await instance.database;
    await db.insert('messages', msg, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
