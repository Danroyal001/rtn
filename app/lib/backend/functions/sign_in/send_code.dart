// POST /api/sign_in/send_code: Sends a sign-in code by SMS to a number.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../services/wire.dart';

@DVBackendFunction()
Future<Reply<CodeSent>> _sendSignInCode(String msisdn) =>
    SelfCare.shared.sendCode(msisdn);
