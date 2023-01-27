use cocoa::base::{id, nil, BOOL, NO, YES};
use cocoa::foundation::NSString;
use objc::declare::ClassDecl;
use objc::runtime::{Object, Sel};
use log::info;

use std::collections::HashMap;
use std::{slice, str};

#[link(name = "InputMethodKit", kind = "framework")]
extern "C" {}

// NSUTF8StringEncoding
const UTF8_ENCODING: libc::c_uint = 4;

pub unsafe fn connect_imkserver(name: id /* NSString */, identifer: id /* NSString */) {
  let server_alloc: id = msg_send![class!(IMKServer), alloc];
  let _server: id = msg_send![server_alloc, initWithName:name bundleIdentifier:identifer];
}

pub fn register_controller() {
    info!("register controller!");
  let super_class = class!(IMKInputController);
  let mut decl = ClassDecl::new("AkazaInputController", super_class).unwrap();

  unsafe {
    /*
    decl.add_method(
      sel!(inputText:client:),
      input_text as extern "C" fn(&Object, Sel, id, id) -> BOOL,
    );
    */
    // https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.5.sdk/System/Library/Frameworks/InputMethodKit.framework/Versions/A/Headers/IMKInputController.h#L73
    decl.add_method(
      sel!(handleEvent:client:),
      handle_event as extern "C" fn(&Object, Sel, id, id) -> BOOL,
    );
  }
  decl.register();
}

extern "C" fn input_text(_this: &Object, _cmd: Sel, text: id, sender: id) -> BOOL {
  if let Some(desc_str) = to_s(text) {
    if let Some(insert_text) = convert(desc_str) {
      // TODO: 英数キーを押すとなぜか半角スペースが入力されるバグがある
      // to_s(text) == " " になってる
      unsafe {
        let _: () = msg_send![sender, insertText: NSString::alloc(nil).init_str(&insert_text)];
      }
      return YES;
    }
  }
  return NO;
}

// GyalM は handle_event を利用している。
extern "C" fn handle_event(_this: &Object, _cmd: Sel, event: id, _sender: id) -> BOOL {
    // https://developer.apple.com/documentation/appkit/nsevent?language=objc
  info!("Got handle_event");
  unsafe {
      // [2023-01-27][21:44:41][mac_akaza::imk][INFO] Object description: NSEvent: type=KeyDown
      // loc=(0,0) time=16312.6 flags=0 win=0x0 winNum=0 ctxt=0x0 chars="o" unmodchars="o" repeat=0
      // keyCode=31
  // u64 固定でいいのかは謎
  let type_: u64 = msg_send![event, type];
  info!("Got handle_event: type={}", type_);
  describe(event);
  /*
  let key_code: u16 = msg_send![event, keyCode];
  info!("Got handle_event: key_code={}", key_code);
  */
  }
  return NO;
}

fn convert(text: &str) -> Option<String> {
  info!("convert: {}", text);
  let mut outs = HashMap::new();
  outs.insert(" ", vec![" "]);

  if let Some(list) = outs.get(text) {
    let i: usize = 0_usize;
    return Some(list[i as usize].to_string());
  }
  return None;
}

/// Get and print an objects description
pub unsafe fn describe(obj: *mut Object) {
  let description: *mut Object = msg_send![obj, description];
  if let Some(desc_str) = to_s(description) {
    info!("Object description: {}", desc_str);
  }
}

/// Convert an NSString to a String
fn to_s<'a>(nsstring_obj: *mut Object) -> Option<&'a str> {
  let bytes = unsafe {
    let length = msg_send![nsstring_obj, lengthOfBytesUsingEncoding: UTF8_ENCODING];
    let utf8_str: *const u8 = msg_send![nsstring_obj, UTF8String];
    slice::from_raw_parts(utf8_str, length)
  };
  str::from_utf8(bytes).ok()
}
