import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

/// Every page, inside MyRTN's frame (or the console's).
class const Layout({super.key, required super.child}) extends DartvelLayout {
  @override
  Widget build(BuildContext context) => AppFrame(child);
}
