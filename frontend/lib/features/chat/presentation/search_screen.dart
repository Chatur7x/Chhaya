import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../features/chat/data/search_service.dart';
import '../../../core/mesh/mesh_message.dart';

/// Search Screen (Req 16)
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  List<SearchResult> _results = [];
  String _selectedType = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _searching = false;

  void _doSearch() {
    final q = _queryController.text.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _searching = true);

    final searchService = ref.read(searchServiceProvider);
    final type = _selectedType == 'text' ? MeshMessageType.text
        : _selectedType == 'voice' ? MeshMessageType.audio
        : null;

    final results = searchService.search(
      q,
      from: _fromDate,
      to: _toDate,
      type: type,
    );

    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.surface,
        title: TextField(
          controller: _queryController,
          autofocus: true,
          style: const TextStyle(color: ChaayaTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Search messages...',
            hintStyle: TextStyle(color: ChaayaTheme.textMuted),
            border: InputBorder.none,
          ),
          onChanged: (_) => _doSearch(),
          onSubmitted: (_) => _doSearch(),
        ),
        leading: const BackButton(color: ChaayaTheme.accent),
        actions: [
          if (_queryController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: ChaayaTheme.textMuted),
              onPressed: () {
                _queryController.clear();
                setState(() => _results = []);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: ChaayaTheme.accent))
                : _results.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) => _SearchResultTile(
                          result: _results[i],
                          onTap: () {/* Navigate to message */},
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: ChaayaTheme.surface,
    child: Row(
      children: [
        const Icon(Icons.filter_list, size: 18, color: ChaayaTheme.textMuted),
        const SizedBox(width: 8),
        for (final type in ['all', 'text', 'voice'])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedType = type;
                _doSearch();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedType == type ? ChaayaTheme.accent.withOpacity(0.2) : ChaayaTheme.glassWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedType == type ? ChaayaTheme.accent : ChaayaTheme.glassBorder,
                  ),
                ),
                child: Text(
                  type[0].toUpperCase() + type.substring(1),
                  style: TextStyle(
                    color: _selectedType == type ? ChaayaTheme.accent : ChaayaTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildEmptyState() {
    final hasQuery = _queryController.text.trim().isNotEmpty;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.search, size: 64, color: ChaayaTheme.textMuted),
        const SizedBox(height: 16),
        Text(
          hasQuery ? 'No messages found' : 'Search your messages',
          style: ChaayaTheme.heading3,
        ),
        const SizedBox(height: 8),
        Text(
          hasQuery ? 'Try different keywords' : 'Enter keywords to search all chats',
          style: const TextStyle(color: ChaayaTheme.textMuted),
        ),
      ]),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final msg = result.message;
    return ListTile(
      onTap: onTap,
      tileColor: ChaayaTheme.background,
      leading: CircleAvatar(
        backgroundColor: ChaayaTheme.accent.withOpacity(0.15),
        child: Text(
          msg.senderId.isNotEmpty ? msg.senderId[0].toUpperCase() : '?',
          style: const TextStyle(color: ChaayaTheme.accent),
        ),
      ),
      title: Row(children: [
        Text(
          _truncate(msg.senderId.length > 8 ? msg.senderId.substring(0, 8) : msg.senderId, 20),
          style: const TextStyle(color: ChaayaTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const Spacer(),
        Text(
          _formatDate(msg.timestamp),
          style: const TextStyle(color: ChaayaTheme.textMuted, fontSize: 11),
        ),
      ]),
      subtitle: _buildHighlightedText(result.highlightedText),
    );
  }

  Widget _buildHighlightedText(String highlighted) {
    // Parse **bold** markers
    final spans = <TextSpan>[];
    final parts = highlighted.split(RegExp(r'\*\*'));
    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(
            color: ChaayaTheme.accent,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x1A7C3AED),
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(color: ChaayaTheme.textSecondary, fontSize: 13),
        ));
      }
    }
    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _searchableName(SearchableMessage msg) => msg.senderId.substring(0, 8);

  String _truncate(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
