use cocoa::appkit::NSEventType;
use cocoa::appkit::NSKeyDown;
use cocoa::base::{id, BOOL, NO, nil, YES};
use cocoa::foundation::NSString;
use cocoa::foundation::NSNotFound;
use cocoa::foundation::NSRange;

use log::info;
use objc::declare::ClassDecl;
use objc::runtime::{Object, Sel};
// use objc::rc::StrongPtr;


use std::collections::HashMap;
use std::{slice, str};

struct InputContext {
    preedit: String,
}

const NSEventModifierFlagControl: u64 = 1 << 18;
const NSEventModifierFlagOption: u64 = 1 << 19;
const NSEventModifierFlagCommand: u64 = 1 << 20;

// https://stackoverflow.com/questions/3202629/where-can-i-find-a-list-of-mac-virtual-key-codes

const KEY_DELETE: u16 = 51;
const KEY_RETURN: u16 = 0x24;
const KEY_MUHENKAN: u16 = 0x66;

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
        /*
         * うまくしょきかできない
        decl.add_method(
            sel!(initWithServer:delegate:client:),
            init_with_server as extern "C" fn(&Object, Sel, id, id, id) -> id,
            );
            */
        decl.add_method(
            sel!(handleEvent:client:),
            handle_event as extern "C" fn(&mut Object, Sel, id, id) -> BOOL,
        );
        decl.add_ivar::<*mut libc::c_void>("ctx");
    }
    decl.register();
}

/*
extern "C" fn init_with_server(_this: &Object, _cmd: Sel, _server: id, _delegate: id, _client: id) -> id {
    info!("init_with_server");
    unsafe {
        let obj :*mut Object = msg_send![class!(IMKInputController), alloc];
    info!("init_with_server!!! 3");
        let obj :*mut Object = msg_send![obj, init];
    info!("init_with_server!!! 4");
    StrongPtr::new(obj)
    }
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
*/

fn hiragana(s: &str) -> String{
    s.replace("ka", "か").replace("a", "あ").to_string()
}

// GyalM は handle_event を利用している。
extern "C" fn handle_event(this: &mut Object, _cmd: Sel, event: id, sender: id) -> BOOL {
    // https://developer.apple.com/documentation/appkit/nsevent?language=objc
    info!("Got handle_event");

    unsafe {
        describe(event);

        // [2023-01-27][21:44:41][mac_akaza::imk][INFO] Object description: NSEvent: type=KeyDown
        // loc=(0,0) time=16312.6 flags=0 win=0x0 winNum=0 ctxt=0x0 chars="o" unmodchars="o" repeat=0
        // keyCode=31
        let type_: NSEventType = msg_send![event, type];

        if type_ != NSKeyDown {
            return NO;
        }

        let eventString = msg_send![event, characters];
        let keyCode: u16 = msg_send![event, keyCode];
        let modifierFlags: u64 = msg_send![event, modifierFlags];
        info!("Got handle_event: type={} keyCode={:#02x}", type_ as u64, keyCode);

        // get ctx
        // 本当は Constructor で初期化したいが、上手くやれなかったので、いったん
        // find_or_create する
        info!("CTX!");
        let ctx: *mut libc::c_void = *this.get_ivar("ctx");
        let ctx = if ctx.is_null() {
            info!("Got null pointer!");
            let ctx = Box::new(InputContext {
                preedit: String::new(),
            });
            let ctx_ptr: *mut InputContext = Box::leak(ctx);
            this.set_ivar("ctx", ctx_ptr as *mut libc::c_void);
            let ctx: *mut libc::c_void = *this.get_ivar("ctx");
            &mut *(ctx as *mut InputContext)
        } else {
            info!("Got real pointer");
            &mut *(ctx as *mut InputContext)
        };

        if keyCode == KEY_RETURN {
            if ctx.preedit.is_empty() {
                info!("preedit is empty.");
                return NO;
            } else {
                // 確定処理
                info!("clear setMarkedText");
                let not_found = NSRange { location: NSNotFound as u64, length: NSNotFound as u64 };
                // let _: () = msg_send![sender, setMarkedText:NSString::alloc(nil).init_str(&(hiragana(&ctx.preedit.clone()))) selectionRange: not_found replacementRange: not_found];
                // let _: () = msg_send![sender, setMarkedText:NSString::alloc(nil).init_str("")];
                info!("insertText!!!");
                let _: () = msg_send![sender, insertText: NSString::alloc(nil).init_str(&(hiragana(&ctx.preedit.clone()))) replacementRange:not_found];
                ctx.preedit.clear();
                return YES;
            }
        } else if keyCode == KEY_MUHENKAN {
            // 何もする必要なし
            return YES;
        }

        if let Some(s) = to_s(eventString) {
            let chars = s.as_bytes();
            if !chars.is_empty() {
                let c = chars[0];
                if (0x21..=0x7e).contains(&c)
                    && (modifierFlags
                        & (NSEventModifierFlagControl
                            | NSEventModifierFlagCommand
                            | NSEventModifierFlagOption))
                        == 0
                {
                    info!("HENKAN!: {}", c);
                    ctx.preedit += str::from_utf8_unchecked(&[c]);
                    info!("Creating NSRange");
                    let not_found = NSRange { location: NSNotFound as u64, length: NSNotFound as u64 };
                    info!("trying setMarkedText!: {:?}", ctx.preedit);

                    // let not_found: id = msg_send![class!(NSRange), alloc];
                    // let not_found: id = msg_send![not_found, location:NSNotFound length: NSNotFound];
                    let _: () = msg_send![sender, setMarkedText:NSString::alloc(nil).init_str(&(hiragana(&ctx.preedit.clone()))) selectionRange: not_found replacementRange: not_found];
                    info!("done setMarkedText!: {}", c);
                    // let _: () = msg_send![sender, setMarkedText:NSString::alloc(nil).init_str(&ctx.preedit) selectionRange: not_found replacementRange: not_found];
                    info!("PREEDIT!: {}", ctx.preedit);
                    return YES;
                }
            }
        }

        // flags に modifier 情報が入っている
        /*
        let key_code: u16 = msg_send![event, keyCode];
        info!("Got handle_event: key_code={}", key_code);
        */
    }
    NO
}

fn convert(text: &str) -> Option<String> {
    info!("convert: {}", text);
    let mut outs = HashMap::new();
    outs.insert(" ", vec![" "]);

    if let Some(list) = outs.get(text) {
        let i: usize = 0_usize;
        return Some(list[i].to_string());
    }
    None
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
