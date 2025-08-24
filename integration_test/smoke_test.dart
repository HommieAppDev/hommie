import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hommie/main.dart' as app; // adjust to your package name

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(Object), findsWidgets); // cheap “it rendered” check
  });
}
