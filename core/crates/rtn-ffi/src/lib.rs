//! A C ABI over one in-process [`Network`].
//!
//! Every call is JSON in and JSON out, through [`rtn_core::rpc`], so a binding needs four
//! functions and no structs:
//!
//! ```c
//! RtnNetwork *net = rtn_network_new();
//! char *answer = rtn_network_call(net, "{\"method\":\"catalog\"}");
//! // {"ok": {...}} or {"error": {"code": "...", "message": "..."}}
//! rtn_string_free(answer);
//! rtn_network_free(net);
//! ```
//!
//! A network is not thread-safe: one caller at a time per handle.
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use rtn_core::{rpc, Network};

/// An opaque handle to one network.
pub struct RtnNetwork(Network);

fn into_c(text: String) -> *mut c_char {
    CString::new(text)
        .unwrap_or_else(|_| CString::new("{\"error\":{\"code\":\"internal\"}}").expect("no NUL"))
        .into_raw()
}

/// A new, empty network with the default catalogue. Free it with [`rtn_network_free`].
#[no_mangle]
pub extern "C" fn rtn_network_new() -> *mut RtnNetwork {
    Box::into_raw(Box::new(RtnNetwork(Network::new())))
}

/// A network restored from a snapshot (`{"method":"snapshot"}` or the API's state file), or null
/// when the JSON is not a snapshot.
///
/// # Safety
/// `json` must be a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn rtn_network_from_json(json: *const c_char) -> *mut RtnNetwork {
    if json.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(text) = CStr::from_ptr(json).to_str() else { return std::ptr::null_mut() };
    match Network::from_json(text) {
        Ok(net) => Box::into_raw(Box::new(RtnNetwork(net))),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Frees a network. Null is ignored.
///
/// # Safety
/// `net` must come from this library and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn rtn_network_free(net: *mut RtnNetwork) {
    if !net.is_null() {
        drop(Box::from_raw(net));
    }
}

/// Runs one JSON call and returns the JSON answer. The answer is never null; free it with
/// [`rtn_string_free`].
///
/// # Safety
/// `net` must be a live handle and `request` a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn rtn_network_call(net: *mut RtnNetwork, request: *const c_char) -> *mut c_char {
    if net.is_null() || request.is_null() {
        return into_c("{\"error\":{\"code\":\"invalid_request\",\"message\":\"null argument\"}}".into());
    }
    let net = &mut (*net).0;
    let Ok(text) = CStr::from_ptr(request).to_str() else {
        return into_c("{\"error\":{\"code\":\"invalid_request\",\"message\":\"not UTF-8\"}}".into());
    };
    match catch_unwind(AssertUnwindSafe(|| rpc::handle_json(net, text))) {
        Ok(answer) => into_c(answer),
        Err(_) => into_c("{\"error\":{\"code\":\"internal\",\"message\":\"the core panicked\"}}".into()),
    }
}

/// Frees a string this library returned. Null is ignored.
///
/// # Safety
/// `text` must come from this library and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn rtn_string_free(text: *mut c_char) {
    if !text.is_null() {
        drop(CString::from_raw(text));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(net: *mut RtnNetwork, request: &str) -> serde_json::Value {
        let request = CString::new(request).unwrap();
        unsafe {
            let answer = rtn_network_call(net, request.as_ptr());
            let text = CStr::from_ptr(answer).to_str().unwrap().to_owned();
            rtn_string_free(answer);
            serde_json::from_str(&text).unwrap()
        }
    }

    #[test]
    fn round_trips_calls_and_snapshots_through_the_c_abi() {
        let net = rtn_network_new();
        let seeded = call(net, r#"{"method":"seed","count":3,"seed":1,"now":1800000000000}"#);
        assert_eq!(seeded["ok"].as_array().unwrap().len(), 3);
        let out = call(
            net,
            r#"{"method":"apply","request_id":"r1","now":1800000000000,
                "op":{"type":"buy_bundle","msisdn":"2349990000001","bundle_id":"daily-100mb"}}"#,
        );
        assert_eq!(out["ok"]["charged"], 10_000);
        let refused = call(net, r#"{"method":"balance","msisdn":"2349990009999","now":0}"#);
        assert_eq!(refused["error"]["code"], "unknown_subscriber");
        let garbage = call(net, "not json");
        assert_eq!(garbage["error"]["code"], "invalid_request");

        let snapshot = call(net, r#"{"method":"snapshot"}"#)["ok"].to_string();
        let snapshot = CString::new(snapshot).unwrap();
        let restored = unsafe { rtn_network_from_json(snapshot.as_ptr()) };
        assert!(!restored.is_null());
        let balance = call(restored, r#"{"method":"balance","msisdn":"2349990000001","now":1800000000000}"#);
        assert_eq!(balance["ok"]["bundles"].as_array().unwrap().len(), 1);
        unsafe {
            rtn_network_free(net);
            rtn_network_free(restored);
        }
    }
}
