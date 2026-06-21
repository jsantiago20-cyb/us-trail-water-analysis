import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:us_trail_water_analysis/main.dart';

void main() {
  testWidgets('Home page renders title and actions', (tester) async {
    await tester.pumpWidget(const WaterApp());
    expect(find.text('US Trail Water Analysis'), findsOneWidget);
    expect(find.text('Choose GPX file'), findsOneWidget);
    expect(find.text('Analyze water sources'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}
