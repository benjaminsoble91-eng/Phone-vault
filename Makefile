# PhoneVault - Theos Makefile for a macOS (AppKit/SwiftUI) application written in Swift.
#
#   make                 build .theos/obj/macosx/debug/PhoneVault.app   (debug build)
#   make FINALPACKAGE=1  optimised build in .theos/obj/macosx/PhoneVault.app
#   make install-app     build, copy to /Applications (or ~/Applications), ad-hoc sign, open
#   make clean           remove build products
#
# If Theos gives trouble, ./build.sh builds the same app with plain swiftc.
#
# Notes on what Theos does with this file (read from theos/makefiles):
#  * TARGET is platform:compiler:SDK version:deployment version. "macosx" selects
#    targets/Darwin/macosx.mk, which builds a hierarchical bundle (Contents/MacOS, Contents/Resources).
#  * Swift: instance/rules.mk adds "-parse-as-library" by itself when no file is called main.swift,
#    which is what an @main App struct needs, and "-swift-version 5" by default.
#    The first Swift build compiles Theos' own helper tools (vendor/swift-support) with "swift build".
#  * Everything in Resources/ is copied to Contents/Resources. Info.plist is put in place by the
#    after-all rule below (see the comment there).

TARGET := macosx:clang:latest:13.0
ARCHS = arm64

# macosx.mk leaves TARGET_CODESIGN empty and darwin_head.mk then falls back to ldid, which a Mac
# may not have. codesign is always there; "-" means an ad-hoc signature.
TARGET_CODESIGN = codesign
TARGET_CODESIGN_FLAGS = --force --sign -

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PhoneVault

# Every Swift file under Sources/, however deep (Sources/*.swift, Sources/Views/*.swift, ...).
# File and folder names must not contain spaces.
PhoneVault_FILES := $(shell find Sources -type f -name '*.swift' | sort)
# Naming AppKit here also stops application.mk from linking UIKit when clang modules are off.
PhoneVault_FRAMEWORKS = AppKit SwiftUI
PhoneVault_SWIFT_VERSION = 5
PhoneVault_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

# Where Theos leaves the finished bundle. At this (top) level THEOS_OBJ_DIR has no architecture
# part: .theos/obj/macosx/debug for a debug build, .theos/obj/macosx with FINALPACKAGE=1.
PV_APP = $(THEOS_OBJ_DIR)/$(APPLICATION_NAME).app

# instance/shared/bundle.mk copies Resources/ into Contents/Resources and then moves Info.plist up
# to Contents/, but it decides whether to do the move when the makefile is read, before the copy
# has happened. On a clean build Info.plist would therefore be left in Contents/Resources and the
# app would not launch. Put it where macOS expects it ourselves.
after-all::
	@mkdir -p "$(PV_APP)/Contents"
	@cp -f Resources/Info.plist "$(PV_APP)/Contents/Info.plist"
	@rm -f "$(PV_APP)/Contents/Resources/Info.plist"
	@echo "Built $(PV_APP)"

.PHONY: install-app

# Not called "install": Theos already has an "install" target that works with packages.
install-app: all
	@set -e; \
	APP="$(PV_APP)"; \
	NAME="$(APPLICATION_NAME)"; \
	if [ ! -x "$$APP/Contents/MacOS/$$NAME" ]; then \
		echo "error: $$APP/Contents/MacOS/$$NAME was not built"; exit 1; \
	fi; \
	if [ ! -f "$$APP/Contents/Info.plist" ]; then \
		echo "error: $$APP/Contents/Info.plist is missing"; exit 1; \
	fi; \
	DEST="/Applications"; \
	if [ ! -w "$$DEST" ]; then DEST="$$HOME/Applications"; mkdir -p "$$DEST"; fi; \
	pkill -x "$$NAME" 2>/dev/null || true; \
	rm -rf "$$DEST/$$NAME.app"; \
	ditto "$$APP" "$$DEST/$$NAME.app"; \
	xattr -cr "$$DEST/$$NAME.app" 2>/dev/null || true; \
	codesign --force --deep --sign - "$$DEST/$$NAME.app"; \
	echo "Installed $$DEST/$$NAME.app"; \
	open "$$DEST/$$NAME.app"
