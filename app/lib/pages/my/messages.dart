import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Messages', description: 'Send and read SMS on your RTN line.')
@pragma('vm:entry-point')
Widget _messagesPage(BuildContext context) => const MessagesScreen();
