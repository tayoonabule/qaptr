//! Compiles the small Objective-C bridge for `SMAppService` on macOS.

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        cc::Build::new()
            .file("native/login_item.m")
            .flag("-fobjc-arc")
            .compile("qaptr_macos_login_item");

        let output = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
            .join("qaptr-vision-helper");
        let status = std::process::Command::new("swiftc")
            .args([
                "-O",
                "-framework",
                "Vision",
                "-framework",
                "ImageIO",
                "-framework",
                "CoreGraphics",
            ])
            .arg("native/vision_recognizer.swift")
            .arg("-o")
            .arg(&output)
            .status()
            .unwrap_or_else(|error| panic!("failed to invoke swiftc for Vision helper: {error}"));
        assert!(
            status.success(),
            "swiftc failed to compile the on-device Vision helper"
        );

        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=ServiceManagement");
        println!("cargo:rustc-env=QAPTR_VISION_HELPER={}", output.display());
        println!("cargo:rerun-if-changed=native/login_item.m");
        println!("cargo:rerun-if-changed=native/vision_recognizer.swift");
    }
}
