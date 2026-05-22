import 'package:flutter_test/flutter_test.dart';
import 'package:gtd/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Shows onboarding wizard on first launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GtdApp());
    await tester.pumpAndSettle();
    // First-page hero text from the wizard.
    expect(find.text('Obsidian Agenda'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets(
      'Skips onboarding and shows the empty state if wizard already done',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await tester.pumpWidget(const GtdApp());
    await tester.pumpAndSettle();
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('No vault selected'), findsOneWidget);
  });
}
