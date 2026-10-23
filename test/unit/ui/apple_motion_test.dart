import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chaaya/core/models/message_attachment.dart';
import 'package:chaaya/ui/theme/appearance_provider.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/chhaya_context_menu.dart';
import 'package:chaaya/ui/widgets/message_attachment_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('swipe reply requires a deliberate threshold and settles without dismissing content', (tester) async {
    var replies=0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child:
      SwipeReply(onReply:()=>replies++,child:const SizedBox(width:200,height:80,child:Text('A message')))))));
    await tester.drag(find.text('A message'),const Offset(28,0));
    await tester.pumpAndSettle();
    expect(replies,0);
    await tester.drag(find.text('A message'),const Offset(120,0));
    await tester.pumpAndSettle();
    expect(replies,1);
    expect(find.text('A message'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('contextual reply action works with both preview motion and reduced motion', (tester) async {
    for(final reduced in [false,true]) {
      var replied=false;
      await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
        data:MediaQuery.of(context).copyWith(disableAnimations:reduced),child:child!),
        home:Scaffold(body:Builder(builder:(context)=>Center(child:ChhayaContextMenu(
          onStaticMenu:()=>ChhayaMotion.sheet<void>(context,(ctx)=>TextButton(
            onPressed:(){replied=true;Navigator.pop(ctx);},child:const Text('Reply'))),
          actions:[CupertinoContextMenuAction(onPressed:(){replied=true;Navigator.pop(context);},child:const Text('Reply'))],
          child:const SizedBox(width:180,height:80,child:Text('Hold this message'))))))));
      await tester.longPress(find.text('Hold this message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(replied,isTrue);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('image expands to a zoomable viewer and closes without exporting', (tester) async {
    final image=MessageAttachment.fromBytes(name:'Sample.png',mimeType:'image/png',bytes:base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:MessageAttachmentView(
      attachment:image,foreground:ChhayaColors.ink,heroTag:'sample-image')))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer),findsOneWidget);
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer),findsNothing);
    expect(tester.takeException(),isNull);
  });

  test('appearance survives reload and cannot be overwritten by an earlier preference load', () async {
    SharedPreferences.setMockInitialValues({'chhaya_appearance':'light'});
    final container=ProviderContainer();
    final controller=container.read(appearanceProvider.notifier);
    await controller.select(ThemeMode.dark);
    expect(container.read(appearanceProvider),ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getString('chhaya_appearance'),'dark');
    container.dispose();
    final restored=ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(appearanceProvider);
    await Future<void>.delayed(Duration.zero);
    expect(restored.read(appearanceProvider),ThemeMode.dark);
  });

  test('both appearances retain readable action, message and secondary text contrast', () {
    double contrast(Color a,Color b) {
      final x=a.computeLuminance(),y=b.computeLuminance();
      return (x>y?(x+0.05)/(y+0.05):(y+0.05)/(x+0.05));
    }
    for(final theme in [ChhayaTheme.materialLight,ChhayaTheme.materialDark]) {
      final p=ChhayaPalette(theme.colorScheme);
      for(final pair in [(p.ink,p.primaryBackground),(p.inkMuted,p.primaryBackground),
        (p.onAccent,p.accent),(p.bubbleSentText,p.bubbleSent),
        (p.bubbleReceivedText,p.bubbleReceived),(p.warning,p.primaryBackground),
        (p.success,p.primaryBackground),(p.info,p.primaryBackground)]) {
        expect(contrast(pair.$1,pair.$2),greaterThanOrEqualTo(4.5));
      }
    }
    expect(ChhayaTypography.displaySmall.fontFamily,'DepartureMono');
  });
}
