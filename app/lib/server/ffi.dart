// The RTN core's C ABI (core/crates/rtn-ffi/include/rtn.h), bound with
// dart:ffi. Five functions, JSON in and JSON out, so the binding is written
// by hand rather than generated: there are no structs for ffigen to read.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _RtnNetwork extends Opaque {}

typedef _OpenC = Pointer<_RtnNetwork> Function(Pointer<Utf8> dir);
typedef _CallC = Pointer<Utf8> Function(Pointer<_RtnNetwork> net, Pointer<Utf8> request);
typedef _FreeNetC = Void Function(Pointer<_RtnNetwork> net);
typedef _FreeNetDart = void Function(Pointer<_RtnNetwork> net);
typedef _FreeStringC = Void Function(Pointer<Utf8> text);
typedef _FreeStringDart = void Function(Pointer<Utf8> text);
typedef _CompactC = Bool Function(Pointer<_RtnNetwork> net);
typedef _CompactDart = bool Function(Pointer<_RtnNetwork> net);

/// One network held in this process by `librtn_ffi`, kept in a directory.
final class RtnLibraryNetwork {
  RtnLibraryNetwork._(this._handle, this._call, this._freeString, this._free, this._compact);

  /// Loads the library at [library] and opens the network kept in [dir],
  /// creating it when it does not exist. Throws when either cannot be done.
  factory RtnLibraryNetwork.open(String library, String dir) {
    final DynamicLibrary lib = DynamicLibrary.open(library);
    final _OpenC open = lib.lookupFunction<_OpenC, _OpenC>('rtn_network_open');
    final Pointer<Utf8> path = dir.toNativeUtf8();
    try {
      final Pointer<_RtnNetwork> handle = open(path);
      if (handle == nullptr) {
        throw StateError('The RTN core could not open the network in $dir.');
      }
      return RtnLibraryNetwork._(
        handle,
        lib.lookupFunction<_CallC, _CallC>('rtn_network_call'),
        lib.lookupFunction<_FreeStringC, _FreeStringDart>('rtn_string_free'),
        lib.lookupFunction<_FreeNetC, _FreeNetDart>('rtn_network_free'),
        lib.lookupFunction<_CompactC, _CompactDart>('rtn_network_compact'),
      );
    } finally {
      malloc.free(path);
    }
  }

  Pointer<_RtnNetwork> _handle;
  final _CallC _call;
  final _FreeStringDart _freeString;
  final _FreeNetDart _free;
  final _CompactDart _compact;

  /// Runs one call: `{"method": ...}` in, `{"ok": ...}` or `{"error": ...}` out.
  String call(String request) {
    if (_handle == nullptr) throw StateError('This network was closed.');
    final Pointer<Utf8> text = request.toNativeUtf8();
    try {
      final Pointer<Utf8> answer = _call(_handle, text);
      try {
        return answer.toDartString();
      } finally {
        _freeString(answer);
      }
    } finally {
      malloc.free(text);
    }
  }

  /// Writes a snapshot and empties the journal.
  bool compact() => _handle != nullptr && _compact(_handle);

  /// Flushes the journal and lets the network go.
  void close() {
    if (_handle == nullptr) return;
    _free(_handle);
    _handle = nullptr;
  }
}
