import 'package:example/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app title', (tester) async {
    await tester.pumpWidget(const ShellyExampleApp());

    expect(find.text('Shelly Energy Demo'), findsWidgets);
  });
}
