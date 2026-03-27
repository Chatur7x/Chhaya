import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../contacts/domain/models/contact.dart';
import '../../../core/theme/chaaya_theme.dart';

class SafetyNumbersScreen extends StatelessWidget {
  final String myPublicKeyBase64;
  final Contact peerContact;

  const SafetyNumbersScreen({
    super.key,
    required this.myPublicKeyBase64,
    required this.peerContact,
  });

  String _computeSafetyNumber() {
    // Standard approach: SHA-256 of sorted public keys
    final keys = [myPublicKeyBase64, peerContact.publicKey]..sort();
    final combinedRaw = keys.join('|');
    
    final hashObj = sha256.convert(utf8.encode(combinedRaw));
    final hashHex = hashObj.toString().substring(0, 60); // 60 chars

    // Convert hex string into numbers to display as 5-digit chunks
    String numbersOnly = "";
    for (var char in hashHex.runes) {
        numbersOnly += (char % 10).toString();
    }
    
    // Chunk into 5s
    final chunks = <String>[];
    for (int i = 0; i < numbersOnly.length; i += 5) {
      if (i + 5 <= numbersOnly.length) {
        chunks.add(numbersOnly.substring(i, i + 5));
      }
    }
    return chunks.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    final safetyNumber = _computeSafetyNumber();

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Verify Safety Number'),
        backgroundColor: ChaayaTheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.verified_user, size: 80, color: ChaayaTheme.accentLight),
            const SizedBox(height: 32),
            Text(
              'Verify with \${peerContact.name}',
              style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'To verify that your offline communications are end-to-end encrypted and immune to interception, compare these numbers with \${peerContact.name}.',
              style: TextStyle(color: ChaayaTheme.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ChaayaTheme.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ChaayaTheme.glassBorder),
              ),
              child: Text(
                safetyNumber,
                style: const TextStyle(
                  color: ChaayaTheme.textPrimary,
                  fontSize: 26,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ChaayaTheme.safeGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                peerContact.isTrusted = true;
                peerContact.save(); // hive
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact Marked as Verified'), backgroundColor: ChaayaTheme.safeGreen)
                );
              },
              child: const Text('Mark as Verified', style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
