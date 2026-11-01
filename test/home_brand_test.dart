import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamvista_iptv/main.dart';

void main() {
  testWidgets('authenticated home displays the approved logo asset',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: HomePage(
      config: PortalConfig(
          type: SourceType.m3u, server: 'https://example.com/list.m3u'),
      api: IptvApi(),
      settings: const AppSettings(),
      onSettingsChanged: (_) {},
      onDisconnect: () async {},
    )));
    await tester.pump();
    final logo = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == 'Logo de Steamvista');
    expect(logo, findsOneWidget);
    expect(
        (tester.widget<Image>(logo).image as AssetImage).assetName, 'icon.png');
    await tester.pumpWidget(const SizedBox());
  });
}
