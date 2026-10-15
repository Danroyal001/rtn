// POST /api/console/issue_vouchers: Prints a batch of recharge vouchers.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<VoucherBook>> _consoleIssueVouchers(DVContext ctx, String count, String amount) =>
    Console.shared.issueVouchers(count, amount);
