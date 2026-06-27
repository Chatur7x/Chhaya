import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/chaaya_theme.dart';
import '../data/group_channel_service.dart';
import '../data/poll_service.dart';
import '../domain/models/poll.dart';
import '../widgets/poll_widget.dart';
import '../widgets/create_poll_sheet.dart';

/// Group Chat Screen — create and manage group chats + public channels.
class GroupChatScreen extends ConsumerStatefulWidget {
  final MeshGroup? group;
  final MeshChannel? channel;
  final String myId;
  final String myName;

  const GroupChatScreen({
    super.key,
    this.group,
    this.channel,
    required this.myId,
    required this.myName,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Poll> _polls = [];
  bool _showPolls = false;

  String get _title => widget.group?.name ?? widget.channel?.name ?? 'Group';
  int get _memberCount =>
      widget.group?.members.length ?? widget.channel?.members.length ?? 0;
  String get _conversationId => widget.group?.id ?? widget.channel?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadPolls();
  }

  void _loadPolls() {
    final pollService = ref.read(pollServiceProvider);
    setState(() {
      _polls = pollService.getActivePolls();
    });
  }

  void _showCreatePollSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => CreatePollSheet(
          creatorId: widget.myId,
          conversationId: _conversationId,
          onPollCreated: (data) {
            _loadPolls();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Poll created successfully')),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChaayaTheme.background,
      appBar: AppBar(
        backgroundColor: ChaayaTheme.surface,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.channel != null
                      ? [ChaayaTheme.bleColor, ChaayaTheme.accent]
                      : [ChaayaTheme.accent, ChaayaTheme.accentLight],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.channel != null ? Icons.tag : Icons.group,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
                Text(
                  '$_memberCount members',
                  style: const TextStyle(
                      fontSize: 11, color: ChaayaTheme.textMuted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (widget.channel != null) ChaayaTheme.channelBadge('ble'),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _showPolls ? Icons.poll : Icons.poll_outlined,
              color:
                  _showPolls ? ChaayaTheme.accent : ChaayaTheme.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _showPolls = !_showPolls;
                if (_showPolls) _loadPolls();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_chart, color: ChaayaTheme.textSecondary),
            onPressed: _showCreatePollSheet,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline,
                color: ChaayaTheme.textSecondary),
            onPressed: () => _showGroupInfo(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Encryption banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: ChaayaTheme.accent.withOpacity(0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 12, color: ChaayaTheme.accent),
                const SizedBox(width: 6),
                Text(
                  widget.channel != null
                      ? 'Public channel • Messages visible to all members'
                      : 'Group encrypted with sender keys',
                  style: TextStyle(
                      fontSize: 11, color: ChaayaTheme.accent.withOpacity(0.8)),
                ),
              ],
            ),
          ),

          // Messages area (placeholder — will populate from service)
          Expanded(
            child: _showPolls ? _buildPollsList() : _buildWelcomeView(),
          ),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: ChaayaTheme.surface,
        border:
            Border(top: BorderSide(color: ChaayaTheme.glassBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: ChaayaTheme.glassDecoration(borderRadius: 24),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(
                      color: ChaayaTheme.textPrimary, fontSize: 15),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText:
                        'Message ${widget.channel?.name ?? widget.group?.name ?? "group"}',
                    hintStyle: const TextStyle(color: ChaayaTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: ChaayaTheme.accent,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, size: 20, color: Colors.white),
                onPressed: () async {
                  final text = _messageController.text.trim();
                  if (text.isEmpty) return;

                  final svc = ref.read(groupChannelServiceProvider);
                  if (widget.channel != null) {
                    await svc.sendChannelMessage(
                        widget.channel!.id, text, widget.myId);
                  } else if (widget.group != null) {
                    await svc.sendGroupMessage(
                        widget.group!.id, text, widget.myId);
                  }

                  _messageController.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Message sent to $_title')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ChaayaTheme.accent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.channel != null ? Icons.tag : Icons.group,
              size: 32,
              color: ChaayaTheme.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text('Welcome to $_title', style: ChaayaTheme.heading3),
          const SizedBox(height: 6),
          Text(
            widget.channel != null
                ? 'Public channel — anyone on the mesh can join'
                : 'Group chat — messages are encrypted',
            style: ChaayaTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPollsList() {
    if (_polls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ChaayaTheme.accent.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.poll_outlined,
                size: 32,
                color: ChaayaTheme.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text('No polls yet', style: ChaayaTheme.heading3),
            const SizedBox(height: 6),
            Text(
              'Create a poll to ask your group',
              style: ChaayaTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showCreatePollSheet,
              icon: const Icon(Icons.add),
              label: const Text('Create Poll'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _polls.length,
      itemBuilder: (context, index) {
        final poll = _polls[index];
        return PollWidget(
          poll: poll,
          currentUserId: widget.myId,
          onPollUpdated: (updatedPoll) {
            _loadPolls();
          },
        );
      },
    );
  }

  void _showGroupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChaayaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: ChaayaTheme.heading2),
            const SizedBox(height: 8),
            Text('$_memberCount members', style: ChaayaTheme.bodyMedium),
            const SizedBox(height: 16),
            if (widget.channel != null) ...[
              Row(
                children: [
                  Icon(
                      widget.channel!.hasPassword
                          ? Icons.lock
                          : Icons.lock_open,
                      size: 16,
                      color: ChaayaTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    widget.channel!.hasPassword
                        ? 'Password protected'
                        : 'Open channel',
                    style: ChaayaTheme.bodyMedium,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create Group/Channel Dialog
class CreateGroupDialog extends StatefulWidget {
  final bool isChannel;
  const CreateGroupDialog({super.key, this.isChannel = false});

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasPassword = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ChaayaTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.isChannel ? 'Create Channel' : 'Create Group',
        style: ChaayaTheme.heading3,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: ChaayaTheme.textPrimary),
            decoration: InputDecoration(
              hintText: widget.isChannel ? '#channel-name' : 'Group name',
              prefixIcon: Icon(
                widget.isChannel ? Icons.tag : Icons.group_add,
                color: ChaayaTheme.accent,
              ),
            ),
          ),
          if (widget.isChannel) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Password protected',
                  style:
                      TextStyle(color: ChaayaTheme.textPrimary, fontSize: 14)),
              value: _hasPassword,
              activeColor: ChaayaTheme.accent,
              onChanged: (v) => setState(() => _hasPassword = v),
            ),
            if (_hasPassword)
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: ChaayaTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Channel password',
                  prefixIcon:
                      Icon(Icons.lock_outline, color: ChaayaTheme.accent),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: ChaayaTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'name': name,
              'password': _hasPassword ? _passwordController.text : null,
            });
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
