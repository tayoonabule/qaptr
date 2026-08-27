//! Builds the small Objective-C bridge for macOS login-item integration.

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        cc::Build::new()
            .file("native/login_item.m")
            .flag("-fobjc-arc")
            .compile("qaptr_macos_login_item");

        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=ServiceManagement");
        println!("cargo:rerun-if-changed=native/login_item.m");
    }
}
