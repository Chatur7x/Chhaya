import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../data/contact_service.dart';
import 'qr_pairing_screen.dart';

/// Contacts screen — shows all paired contacts with status dots.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactListProvider);

    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        title: const Text('Contacts'),
        backgroundColor: ChaayaTheme.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: ChaayaTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: contacts.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                if (contact.isStealth) return const SizedBox.shrink();
                return _ContactTile(contact: contact);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QRPairingScreen()),
          );
        },
        backgroundColor: ChaayaTheme.accent,
        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: ChaayaTheme.accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline,
              size: 40,
              color: ChaayaTheme.accent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No contacts yet',
            style: ChaayaTheme.heading3,
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan a QR code to pair with\na nearby Chaaya device',
            textAlign: TextAlign.center,
            style: ChaayaTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QRPairingScreen()),
              );
            },
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: const Text('Scan QR Code'),
          ),
        ],
      ),
    );
  }
}

/// Individual contact tile
class _ContactTile extends StatelessWidget {
  final MeshContact contact;
  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: ChaayaTheme.glassDecoration(borderRadius: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: ChaayaTheme.accent.withOpacity(0.2),
              child: Text(
                contact.username[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: ChaayaTheme.accent,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: ChaayaTheme.statusDot(contact.status.name),
            ),
          ],
        ),
        title: Text(
          contact.username,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: ChaayaTheme.textPrimary,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              contact.lastSeenText,
              style: const TextStyle(
                fontSize: 12,
                color: ChaayaTheme.textMuted,
              ),
            ),
            if (contact.isTrustedRing) ...[
              const SizedBox(width: 8),
              const Icon(Icons.shield, size: 12, color: ChaayaTheme.safeGreen),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              color: ChaayaTheme.accent,
              onPressed: () {
                // Navigate to chat
              },
            ),
            IconButton(
              icon: const Icon(Icons.call_outlined, size: 20),
              color: ChaayaTheme.safeGreen,
              onPressed: () {
                // Initiate call
              },
            ),
          ],
        ),
      ),
    );
  }
}

