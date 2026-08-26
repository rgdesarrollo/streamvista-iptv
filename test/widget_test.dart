import 'package:flutter_test/flutter_test.dart';

import 'package:streamvista_iptv/main.dart';

void main() {
  testWidgets('app loads the connect screen', (WidgetTester tester) async {
    await tester.pumpWidget(const StreamVistaApp());

    expect(find.text('StreamVista'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
  });
}
