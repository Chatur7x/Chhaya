import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chaaya/services/messaging/poll_payload.dart';
import 'package:chaaya/ui/theme/chhaya_theme.dart';
import 'package:chaaya/ui/widgets/poll_card.dart';

void main() {
  testWidgets(
    'poll selection submits the chosen option and shows aggregate results',
    (tester) async {
      final poll = PollPayload.create(
        question: 'Where to meet?',
        labels: ['Cafe', 'Park'],
        allowMultiple: false,
      );
      List<String>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          theme: ChhayaTheme.materialLight,
          home: Scaffold(
            body: Center(
              child: PollCard(
                poll: poll,
                totals: {poll.options.first.id: 2, poll.options.last.id: 1},
                totalVotes: 3,
                selectedOptions: const [],
                canVote: true,
                onVote: (values) => submitted = values,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cafe'));
      await tester.pump();
      await tester.tap(find.text('Vote'));
      expect(submitted, [poll.options.first.id]);
      expect(find.text('67%  2'), findsOneWidget);
    },
  );

  testWidgets('closed poll renders results without voting controls', (
    tester,
  ) async {
    final poll = PollPayload.create(
      question: 'Closed poll',
      labels: ['Yes', 'No'],
      allowMultiple: false,
      endsAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ChhayaTheme.materialLight,
        home: Scaffold(
          body: PollCard(
            poll: poll,
            totals: {poll.options.first.id: 1, poll.options.last.id: 0},
            totalVotes: 1,
            selectedOptions: const [],
            canVote: false,
            onVote: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Poll closed'), findsOneWidget);
    expect(find.text('Vote'), findsNothing);
    expect(find.text('100%  1'), findsOneWidget);
  });
}
