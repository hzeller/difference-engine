
TOP=top
DELAY_MODEL=sky130
PIPELINE_STAGES=1

# Could be overriden by environment variable
XLS_IR_CONVERTER ?= xls-ir-converter
XLS_INTERPRETER  ?= xls-interpreter
XLS_OPT          ?= xls-opt
XLS_CODEGEN      ?= xls-codegen

DSLX_OPTIONS=--dslx_stdlib_path=$(DSLX_STDLIB_PATH)
#DSLX_OPTIONS+=--compare=jit

iterative_polynomial_sampler.test:

test: iterative_polynomial_sampler.test

%.ir: %.x
	$(XLS_IR_CONVERTER) --top=$(TOP) $(DSLX_OPTIONS) --output_file=$@ $^

%.opt.ir: %.ir
	$(XLS_OPT) --output_path=$@ $^

%.sv : %.opt.ir
	$(XLS_CODEGEN) --delay_model=$(DELAY_MODEL) --pipeline_stages=$(PIPELINE_STAGES) --use_system_verilog --output_verilog_path=$@  $^

%.test: %.x
	$(XLS_INTERPRETER) $(DSLX_OPTIONS) --alsologtostderr $^

# Keep intermediate results for inspection.
.PRECIOUS: %.ir %.opt.ir

clean:
	rm -f *.ir *.sv
