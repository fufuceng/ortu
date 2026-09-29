.PHONY: check format format-check test coverage package release-package

check:
	./scripts/check.sh

format:
	swift format format --configuration .swift-format --recursive --in-place Sources Tests scripts/prepare-lace-pack.swift Package.swift

format-check:
	./scripts/lint-changed.sh

test:
	swift test --parallel

coverage:
	swift test --parallel --enable-code-coverage
	./scripts/coverage-report.sh

package:
	./scripts/package-local.sh

release-package:
	test -n "$(VERSION)"
	./scripts/package-release.sh "$(VERSION)"
