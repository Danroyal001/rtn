// POST /api/console/vouchers: Recharge vouchers printed so far.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<VoucherBook>> _consoleVouchers(DVContext ctx) => Console.shared.vouchers();
