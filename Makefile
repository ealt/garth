.PHONY: lint test check

lint:
	bash -n bin/garth lib/*.sh
	python3 -m py_compile lib/config-parser.py
	shellcheck bin/garth lib/*.sh setup.sh

test:
	bash tests/config_parser_smoke.sh
	bash tests/git_helpers_smoke.sh
	bash tests/zellij_layout_smoke.sh

check: lint test
