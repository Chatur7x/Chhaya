import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../contacts/domain/models/contact.dart';

class HiddenInboxScreen extends ConsumerStatefulWidget {
  const HiddenInboxScreen({super.key});

  @override
  ConsumerState<HiddenInboxScreen> createState() => _HiddenInboxScreenState();
}

class _HiddenInboxScreenState extends ConsumerState<HiddenInboxScreen> {
  final _pinController = TextEditingController();
  bool _isUnlocked = false;
  List<Contact> _stealthContacts = [];

  @override
  void initState() {
    super.initState();
    // Check if memory cache is already unlocked
    _isUnlocked = ref.read(stealthServiceProvider).isUnlocked;
    if (_isUnlocked) {
      _loadContacts();
    }
  }

  void _loadContacts() {
    setState(() {
      _stealthContacts = ref.read(stealthServiceProvider).getStealthContacts();
    });
  }

  Future<void> _attemptUnlock() async {
    final pin = _pinController.text;
    if (pin.isEmpty) return;
    
    final success = await ref.read(stealthServiceProvider).unlock(pin);
    if (success) {
      setState(() => _isUnlocked = true);
      _loadContacts();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PIN. Decryption failed.'), backgroundColor: ChaayaTheme.sosRed)
        );
      }
    }
  }

  void _lockInbox() {
    ref.read(stealthServiceProvider).lock();
    setState(() {
      _isUnlocked = false;
      _stealthContacts = [];
      _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isUnlocked) {
      return _buildLockScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black, // true black for low-visibility mode
      appBar: AppBar(
        title: const Text('Hidden Inbox', style: TextStyle(color: ChaayaTheme.accent)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: ChaayaTheme.accent),
        actions: [
          IconButton(icon: const Icon(Icons.lock_outline), onPressed: _lockInbox),
        ],
      ),
      body: _stealthContacts.isEmpty
        ? const Center(child: Text('No stealth contacts.', style: TextStyle(color: ChaayaTheme.glassBorder)))
        : ListView.builder(
            itemCount: _stealthContacts.length,
            itemBuilder: (context, index) {
              final contact = _stealthContacts[index];
              return ListTile(
                leading: const CircleAvatar(backgroundColor: ChaayaTheme.surfaceLight, child: Icon(Icons.person_outline, color: ChaayaTheme.textSecondary)),
                title: Text(contact.name, style: const TextStyle(color: ChaayaTheme.textPrimary)),
                subtitle: const Text('Tap to open chat', style: TextStyle(color: ChaayaTheme.glassBorder)),
                onTap: () {
                  // Push to encrypted chat context here
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Opening stealth chat with \${contact.name}...'), backgroundColor: ChaayaTheme.surface)
                  );
                },
              );
            },
          )
    );
  }

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(elevation: 0, backgroundColor: ChaayaTheme.background),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off, size: 64, color: ChaayaTheme.textSecondary),
            const SizedBox(height: 32),
            const Text('Enter Stealth PIN', style: TextStyle(color: ChaayaTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: ChaayaTheme.textPrimary, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ChaayaTheme.glassBorder)),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ChaayaTheme.accent)),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ChaayaTheme.accent,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _attemptUnlock,
              child: const Text('Decrypt & Unlock', style: TextStyle(fontSize: 18, color: ChaayaTheme.background, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
