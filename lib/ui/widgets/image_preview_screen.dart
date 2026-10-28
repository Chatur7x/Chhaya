import 'package:flutter/material.dart';
import '../../core/models/message_attachment.dart';
import '../theme/chhaya_theme.dart';
import 'message_attachment_view.dart';

class ImagePreviewScreen extends StatelessWidget {
  const ImagePreviewScreen({super.key, required this.attachment, required this.heroTag});
  final MessageAttachment attachment;
  final String heroTag;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ChhayaPalette.of(context).primaryBackground,
    appBar: AppBar(title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: IconButton(tooltip: 'Close image', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
      actions: [IconButton(tooltip: 'Save image', icon: const Icon(Icons.download_rounded),
        onPressed: () => MessageAttachmentView.export(context, attachment))]),
    body: SafeArea(child: Center(child: InteractiveViewer(minScale: 1, maxScale: 4,
      child: Hero(tag: heroTag, child: Image.memory(attachment.bytes, fit: BoxFit.contain,
        cacheWidth: 1920, semanticLabel: attachment.name,
        errorBuilder: (_, error, stack) => const Text('This image cannot be displayed.')))))),
  );
}
