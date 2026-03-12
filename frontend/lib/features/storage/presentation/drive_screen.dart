import 'package:flutter/material.dart';
import '../../sharing/presentation/share_file_dialog.dart';

class DriveScreen extends StatelessWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('My Drive', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D47A1),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8, // Placeholder
        itemBuilder: (context, index) {
          final fileName = 'Secure_File_$index.pdf';
          return Card(
            color: Colors.white.withOpacity(0.05),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blueAccent, size: 32),
              title: Text(fileName, style: const TextStyle(color: Colors.white)),
              subtitle: const Text('2.4 MB • Encrypted', style: TextStyle(color: Colors.white38)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.blueAccent, size: 20),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => ShareFileDialog(fileName: fileName),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.upload_file, color: Colors.white),
      ),
    );
  }
}
