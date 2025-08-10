import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final String threadId;
  late final String otherUid;

  @override
  void initState() {
    super.initState();
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    threadId = args['threadId'] as String;
    otherUid = args['otherUid'] as String;
  }

  Future<void> _send() async {
    final me = _auth.currentUser;
    final text = _ctrl.text.trim();
    if (me == null || text.isEmpty) return;

    final msgRef = _fs.collection('threads').doc(threadId).collection('messages').doc();
    await msgRef.set({
      'sender': me.uid,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _fs.collection('threads').doc(threadId).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
    });
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final me = _auth.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Direct Message')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _fs.collection('threads').doc(threadId)
                .collection('messages')
                .orderBy('createdAt', descending: true)
                .snapshots(),
              builder: (_, snap) {
                final docs = snap.data?.docs ?? [];
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final isMe = m['sender'] == me;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m['text'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _send, child: const Text('Send')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
