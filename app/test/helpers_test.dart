import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/services/rtn.dart';

void main() {
  test('money reads as naira with grouping', () {
    expect(naira(0), '₦0.00');
    expect(naira(5), '₦0.05');
    expect(naira(123450), '₦1,234.50');
    expect(naira(100000000), '₦1,000,000.00');
  });

  test('data sizes read the way people say them', () {
    expect(dataSize(512 * 1024), '512 KB');
    expect(dataSize(100 * 1048576), '100 MB');
    expect(dataSize(1024 * 1048576), '1 GB');
    expect(dataSize(1536 * 1048576), '1.5 GB');
  });

  test('numbers read the local way', () {
    expect(phone('2349990000001'), '0999 000 0001');
    expect(phone('441234567890'), '441234567890');
  });

  test('an answer becomes a result', () {
    final RtnResult ok = RtnResult.from(<String, Object?>{'ok': true, 'data': <String, Object?>{'a': 1}});
    expect(ok.ok, isTrue);
    expect(ok.map['a'], 1);
    final RtnResult refused =
        RtnResult.from(<String, Object?>{'ok': false, 'code': 'barred', 'message': 'this line is barred'});
    expect(refused.ok, isFalse);
    expect(refused.code, 'barred');
    expect(refused.message, 'this line is barred');
  });

  test('a transport failure is a readable refusal', () async {
    final RtnResult result = await rtnCall(() async => throw StateError('socket closed'));
    expect(result.ok, isFalse);
    expect(result.code, 'offline');
  });
}
