// POST /api/sign_in/verify_code: Checks a sign-in code and starts a subscriber session.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/sessions.dart';

@DVBackendFunction()
Future<Response> _verifySignInCode(Request request, String msisdn, String code) async =>
    sessionResponse(request, await SelfCare.shared.verifyCode(msisdn, code));
