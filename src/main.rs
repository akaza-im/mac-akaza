use cocoa::appkit::{NSApp, NSApplication};
use cocoa::base::{id, nil, BOOL};
use cocoa::foundation::{NSAutoreleasePool, NSString};

use fern;
use log::info;
use log::LevelFilter;

#[macro_use]
extern crate objc;

mod imk;

fn main() -> anyhow::Result<()> {
    let logpath = xdg::BaseDirectories::with_prefix("akaza")?
        .create_cache_directory("logs")?
        .join("mac-akaza.log");
    println!("log file path: {}", logpath.to_string_lossy());

    // log file をファイルに書いていく。
    // ~/.cache/akaza/logs/mac-akaza.log に書く。
    // https://superuser.com/questions/1293842/where-should-userspecific-application-log-files-be-stored-in-gnu-linux
    fern::Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "{}[{}][{}] {}",
                chrono::Local::now().format("[%Y-%m-%d][%H:%M:%S]"),
                record.target(),
                record.level(),
                message
            ))
        })
        .level(LevelFilter::Info)
        .chain(std::io::stdout())
        .chain(fern::log_file(logpath)?)
        .apply()?;

    info!("Initializing log 5");

    imk::register_controller();

    info!("Controller registered");

    unsafe {
        let _pool = NSAutoreleasePool::new(nil);
        let app = NSApp();
        let k_connection_name = NSString::alloc(nil).init_str("AkazaIME_1_Connection");
        let nib_name = NSString::alloc(nil).init_str("MainMenu");

        let bundle: id = msg_send![class!(NSBundle), mainBundle];
        let identifer: id = msg_send![bundle, bundleIdentifier];

        info!("Start describing");
        imk::describe(identifer);
        imk::describe(nib_name);
        imk::describe(k_connection_name);

        imk::connect_imkserver(k_connection_name, identifer);

        let _: BOOL = msg_send![class!(NSBundle), loadNibNamed:nib_name
                                owner:app];
        app.run()
    }

    Ok(())
}
