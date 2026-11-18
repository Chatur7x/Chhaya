import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/providers/app_providers.dart';
import '../../theme/chhaya_theme.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});
  @override
  ConsumerState<VerificationScreen> createState()=>_VerificationScreenState();
}
class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _id=TextEditingController();
  String? _status;
  @override
  void dispose(){ _id.dispose(); super.dispose(); }

  Future<void> _verify(String raw) async {
    final value=raw.trim().replaceFirst('chhaya://identity/','').toLowerCase();
    final contacts=ref.read(contactsProvider);
    final contact=contacts.where((c)=>c.chhayaId.publicKey==value).firstOrNull;
    if(contact==null) { setState(()=>_status='No matching contact. Add this identity first.'); return; }
    try {
      final verified=contact.copyWith(isVerified:true,verificationLevel:3);
      await ref.read(localDatabaseProvider).updateContact(verified);
      ref.read(contactsProvider.notifier).updateContact(verified);
      if(mounted) setState(()=>_status='Identity verified for ${contact.displayName}');
    } catch (_) { if(mounted) setState(()=>_status='Could not save verification. Try again.'); }
  }
  Future<void> _scan() async {
    final value=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>const _IdentityScanner()));
    if(value!=null&&mounted) { await _verify(value); }
  }
  @override
  Widget build(BuildContext context) {
    final id=ref.watch(currentUserProvider)?.chhayaId.publicKey;
    return Scaffold(appBar:AppBar(title:const Text('Verify identity')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(ChhayaSpacing.space4),children:[
        const Text('Your identity'),
        if(id!=null) ...[
          Center(child:QrImageView(data:'chhaya://identity/$id',size:220,
            backgroundColor:ChhayaColors.white,padding:const EdgeInsets.all(16))),
          SelectableText(id),
          TextButton.icon(onPressed:()=>Clipboard.setData(ClipboardData(text:id)),icon:const Icon(Icons.copy),label:const Text('Copy identity')),
        ],
        const SizedBox(height:ChhayaSpacing.space4),
        const Text("Scan your contact's code in person, or compare their full identity using a trusted channel. A name alone does not verify a contact."),
        FilledButton.icon(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:const Text('Scan contact QR')),
        TextField(controller:_id,maxLength:66,decoration:const InputDecoration(labelText:'Contact identity')),
        OutlinedButton(onPressed:()=>_verify(_id.text),child:const Text('I compared the full identity')),
        if(_status!=null) Text(_status!,semanticsLabel:_status),
      ])));
  }
}
class _IdentityScanner extends StatefulWidget {
  const _IdentityScanner();
  @override
  State<_IdentityScanner> createState()=>_IdentityScannerState();
}
class _IdentityScannerState extends State<_IdentityScanner> {
  final _controller=MobileScannerController();
  bool _done=false;
  @override
  void dispose(){ _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Scan contact identity')),
    body:MobileScanner(controller:_controller,onDetect:(capture){
      if(_done) { return; }
      final code=capture.barcodes.map((b)=>b.rawValue).whereType<String>().firstOrNull;
      if(code==null) { return; }
      _done=true;
      Navigator.of(context).pop(code);
    }));
}
