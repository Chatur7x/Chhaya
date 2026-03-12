import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ShareFileDialog extends StatefulWidget {
  final String fileName;
  const ShareFileDialog({super.key, required this.fileName});

  @override
  State<ShareFileDialog> createState() => _ShareFileDialogState();
}

class _ShareFileDialogState extends State<ShareFileDialog> {
  bool _usePassword = false;
  final _passwordController = TextEditingController();
  int _expiryDays = 7;
  String? _generatedLink;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.share, color: Colors.blueAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share "${widget.fileName}"',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Password Protect', style: TextStyle(color: Colors.white70)),
              value: _usePassword,
              onChanged: (v) => setState(() => _usePassword = v),
              activeColor: Colors.blueAccent,
              contentPadding: EdgeInsets.zero,
            ),
            if (_usePassword)
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter password',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            const SizedBox(height: 16),
            const Text('Expires in (days)', style: TextStyle(color: Colors.white70, fontSize: 14)),
            Slider(
              value: _expiryDays.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_expiryDays days',
              activeColor: Colors.blueAccent,
              onChanged: (v) => setState(() => _expiryDays = v.round()),
            ),
            const SizedBox(height: 24),
            if (_generatedLink != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(child: Text(_generatedLink!, style: const TextStyle(color: Colors.blueAccent), overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white70),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _generatedLink!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!')));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _generatedLink = "https://proj16.io/share/s-58392-x-239"; // Mock result
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Generate Secure Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
