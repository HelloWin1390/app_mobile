import 'package:drone_controller/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows login screen without a saved session', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const BpnaApp());
    await tester.pumpAndSettle();

    expect(find.text('Вход оператора'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}
