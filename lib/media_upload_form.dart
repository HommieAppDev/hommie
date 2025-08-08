// media_upload_form.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MediaUploadForm extends StatefulWidget {
  final String listingId;
  const MediaUploadForm({required this.listingId, super.key});

  @override
  State<MediaUploadForm> createState() => _MediaUploadFormState();
}

class _MediaUploadFormState extends State<MediaUploadForm> {
  final List<XFile> _mediaFiles = [];
  bool _isUploading = false;

  Future<void> _pickMedia() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> files = await picker.pickMultiImage();
    setState(() {
      _mediaFiles.addAll(files);
    });
  }

  Future<void> _uploadMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isUploading = true;
    });

    final storage = FirebaseStorage.instance;
    final firestore = FirebaseFirestore.instance;

    for (final file in _mediaFiles) {
      final fileRef = storage
          .ref()
          .child('user_media')
          .child(widget.listingId)
          .child('${DateTime.now().millisecondsSinceEpoch}_${file.name}');

      final uploadTask = await fileRef.putFile(File(file.path));
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await firestore.collection('userMedia').add({
        'listingId': widget.listingId,
        'userId': user.uid,
        'mediaUrl': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    setState(() {
      _mediaFiles.clear();
      _isUploading = false;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload successful!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Media')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _pickMedia,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Pick Photos'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _mediaFiles.length,
                itemBuilder: (context, index) {
                  return Image.file(File(_mediaFiles[index].path), fit: BoxFit.cover);
                },
              ),
            ),
            const SizedBox(height: 16),
            _isUploading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _uploadMedia,
                    child: const Text('Upload Media'),
                  ),
          ],
        ),
      ),
    );
  }
}
