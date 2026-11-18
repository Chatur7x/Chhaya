import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/models/message_attachment.dart';
import '../theme/chhaya_theme.dart';
import 'voice_message_player.dart';
import 'image_preview_screen.dart';

/// Attachment export always requires an explicit action and an OS save dialog.
class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({super.key, required this.attachment, required this.foreground, this.heroTag});
  final MessageAttachment attachment;
  final Color foreground;
  final String? heroTag;

  static Future<void> export(BuildContext context, MessageAttachment attachment) async {
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Save a decrypted copy?'),
      content: const Text('The exported file will be outside Chhaya’s encrypted storage. Disappearing-message timers will not remove it.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Choose location'))],
    ));
    if (approved != true || !context.mounted) return;
    try {
      final path = await FilePicker.platform.saveFile(fileName: attachment.name, bytes: attachment.bytes);
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File saved')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this file. Try another location.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (attachment.isPreviewableImage) Semantics(button:true,label:'Open image ${attachment.name}',
        child:InkWell(onTap:heroTag==null?null:()=>Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>ImagePreviewScreen(attachment:attachment,heroTag:heroTag!))),
          child:Hero(tag:heroTag??attachment,child:ClipRRect(
            borderRadius:BorderRadius.circular(12),
            child:Image.memory(attachment.bytes,width:220,height:160,fit:BoxFit.cover,
              cacheWidth:660,cacheHeight:480,semanticLabel:attachment.name,
              errorBuilder:(_,error,stack)=>Text('Image preview unavailable',style:ChhayaType.of(context).body.copyWith(color:foreground)))))),
      ),
      if (attachment.mimeType == 'audio/aac') VoiceMessagePlayer(attachment: attachment, foreground: foreground),
      Text(attachment.name, maxLines: 3, overflow: TextOverflow.ellipsis,
        style: ChhayaType.of(context).bodyLarge.copyWith(color: foreground)),
      Text('${(attachment.size / 1024).ceil()} KB', style: ChhayaType.of(context).caption.copyWith(color: foreground)),
      TextButton.icon(style: TextButton.styleFrom(foregroundColor: foreground),
        onPressed: () => export(context, attachment), icon: const Icon(Icons.download_rounded),
        label: const Text('Save file')),
    ],
  );
}
