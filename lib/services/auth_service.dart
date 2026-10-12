import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signUp(String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await cred.user?.updateDisplayName(displayName);
    await _db.collection('users').doc(cred.user!.uid).set({'displayName': displayName});
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();

  Future<Map<String, String>> displayNames(Iterable<String> uids) async {
    final out = <String, String>{};
    for (final uid in uids) {
      final doc = await _db.collection('users').doc(uid).get();
      var name = (doc.data()?['displayName'] as String?)?.trim();
      // Self-heal: if your own profile document is missing a name, fall back to the name on your
      // login account and save it, so everyone else sees it too.
      final me = _auth.currentUser;
      if ((name == null || name.isEmpty) && me != null && me.uid == uid) {
        final authName = me.displayName?.trim();
        if (authName != null && authName.isNotEmpty) {
          name = authName;
          try {
            await _db.collection('users').doc(uid).set({'displayName': authName}, SetOptions(merge: true));
          } catch (_) {}
        }
      }
      out[uid] = (name == null || name.isEmpty) ? 'Player' : name;
    }
    return out;
  }
}