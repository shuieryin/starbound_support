all: install_rebar3 install

install_rebar3:
	@./config/install_rebar3.sh

install:
	@./config/rebar3 install

run:
	@./_build/default/rel/starbound_support/bin/starbound_support console