all: install_rebar3 install

install_rebar3:
	@./config/install_rebar3.sh

install:
	@./config/rebar3 install

run:
	@./_build/default/rel/starbound_support/bin/starbound_support console

build:
	@./config/rebar3 build

hcu:
	@./config/rebar3 hcu

reset:
	@./config/rebar3 reset

app_deps:
	@./_build/default/lib/recon/script/app_deps.erl; dot -T png -O app-deps.dot; rm -f app-deps.dot app-deps.dot.png

crash_dump:
	@./_build/default/lib/recon/script/erl_crashdump_analyzer.sh erl_crash.dump

TS=1
queue_fun:
	@awk -v threshold=${TS} -f _build/default/lib/recon/script/queue_fun.awk erl_crash.dump