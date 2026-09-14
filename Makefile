# Portable build/test/run for both CLT-only and full-Xcode machines.
#
# WHY this exists:
#   On a Command Line Tools (CLT) only host, SwiftPM's default "swiftbuild"
#   build system relies on XCBuild, which requires a full Xcode install and
#   fails at initialization ("Unknown error parsing property list"). The
#   "native" build system works without Xcode, so on CLT-only hosts we pass
#   --build-system native.
#
#   Additionally, under the native build system the Swift Testing framework
#   (Testing.framework) is not on the default search paths, so `swift test`
#   cannot find/link it. We add explicit framework search paths (-F) for both
#   the compiler (-Xswiftc) and linker (-Xlinker) pointing at the CLT
#   Frameworks directory.
#
#   On machines with full Xcode, none of this is needed, so we fall back to
#   the plain swift build / test / run commands.
#
# Detection: `xcode-select -p` prints the active developer dir. If it points
# at CommandLineTools, we are on a CLT-only host.

# POSIX sh test; case pattern matches any path containing CommandLineTools.
CLT_FRAMEWORKS = /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS = -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS)

.PHONY: build test run

build:
	@if xcode-select -p | grep -q CommandLineTools; then \
		echo "CLT-only host: using native build system"; \
		swift build --build-system native; \
	else \
		swift build; \
	fi

test:
	@if xcode-select -p | grep -q CommandLineTools; then \
		echo "CLT-only host: using native build system + Testing framework search paths"; \
		swift test --build-system native $(TEST_FLAGS); \
	else \
		swift test; \
	fi

run:
	@if xcode-select -p | grep -q CommandLineTools; then \
		echo "CLT-only host: using native build system"; \
		swift run --build-system native Pomodoro; \
	else \
		swift run Pomodoro; \
	fi
