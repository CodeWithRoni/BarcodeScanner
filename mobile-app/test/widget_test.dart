import 'package:barcodesync/src/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GradientButton renders its label and handles taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: GradientButton(label: 'Start scanning', icon: Icons.qr_code_scanner_rounded, onPressed: () => taps++)),
        ),
      ),
    );
    expect(find.text('Start scanning'), findsOneWidget);
    await tester.tap(find.text('Start scanning'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
  });

  testWidgets('StatusPill shows its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: StatusPill(color: Colors.green, label: 'Live', pulse: false)))),
    );
    expect(find.text('Live'), findsOneWidget);
  });
}
