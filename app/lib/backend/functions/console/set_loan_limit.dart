// POST /api/console/set_loan_limit: Sets how much a line may borrow.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSetLoanLimit(DVContext ctx, String msisdn, String amount) =>
    Console.shared.setLoanLimit(msisdn, amount);
