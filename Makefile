
TOP=top
DELAY_MODEL=sky130
PIPELINE_STAGES=1

DSLX_OPTIONS=--dslx_stdlib_path=$(DSLX_STDLIB_PATH)
#DSLX_OPTIONS+=--compare=jit

iterative_polynomial_sampler.sv:
iterative_polynomial_sampler.test:

test: iterative_polynomial_sampler.test

%.ir: %.x
	xls-ir-converter --top=$(TOP) $(DSLX_OPTIONS) --output_file=$@ $^

%.opt.ir: %.ir
	xls-opt --output_path=$@ $^

%.sv : %.opt.ir
	xls-codegen --delay_model=$(DELAY_MODEL) --pipeline_stages=$(PIPELINE_STAGES) --use_system_verilog --output_verilog_path=$@  $^

%.test: %.x
	xls-interpreter $(DSLX_OPTIONS) --alsologtostderr $^

# Keep intermediate results for inspection.
.PRECIOUS: %.ir %.opt.ir

clean:
	rm -f *.ir *.sv
