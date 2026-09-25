import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_update_helper/force_update_helper.dart';

void main() {
  ForceUpdateClient client(Completer<String> required) => ForceUpdateClient(
        fetchRequiredVersion: () => required.future,
        iosAppStoreId: '123',
        versionCheckMethod: VersionCheckMethod.buildNumberOnly,
        currentVersion: '1.0.0+1',
      );

  Widget app(GlobalKey<NavigatorState> key, ForceUpdateClient c,
          {bool mountNavigator = true}) =>
      MaterialApp(
        navigatorKey: mountNavigator ? key : null,
        builder: (_, child) => ForceUpdateWidget(
          navigatorKey: key,
          forceUpdateClient: c,
          allowCancel: false,
          showForceUpdateAlert: (ctx, _) => showDialog<bool>(
            context: ctx,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(title: Text('Required')),
          ),
          showStoreListing: (_) async {},
          child: child!,
        ),
        home: const SizedBox(),
      );

  testWidgets('resume during a check shows only one alert', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final required = Completer<String>();
    await tester.pumpWidget(app(GlobalKey(), client(required)));
    await tester.pump();
    // Resume while the initial check is still fetching
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    required.complete('1.0.0+2');
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('waits for the navigator instead of throwing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final key = GlobalKey<NavigatorState>();
    final required = Completer<String>()..complete('1.0.0+2');
    await tester.pumpWidget(app(key, client(required), mountNavigator: false));
    // Well past the old 5s cut-off
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
    expect(find.text('Required'), findsNothing);
    await tester.pumpWidget(app(key, client(required)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
