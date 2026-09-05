//usr/bin/env -S make iterative_polynomial_sampler.test; exit

#![feature(generics)]
#![feature(explicit_state_access)]

import std;

// Registers to represent a polynomial to be calculated. It has one more elment
// than the Polynomials degree.
struct PolynomialRegisters<T: type, DEGREE: u32> {
    reg: T[DEGREE + 1],
}

// An iteration request for a proc is the newly initialized registers
// and the number of samples we want the proc to emit.
// The iteration request also represents our state.
struct IterationRequest<T: type, DEGREE: u32> {
    registers: PolynomialRegisters<T, DEGREE>,
    count: u32,
}

impl IterationRequest<T, DEGREE> {
    fn default() -> Self {
        IterationRequest<T, DEGREE> { ..zero!<IterationRequest<T, DEGREE>>() }
    }
}

// Iterative sampler of a polynomial with DEGREE.
//
// The IterationRequest provides the initial register set and the number
// of samples we like it to generate.
//
// With every `sample_clock` trigger (an empty tuple channel) a new value is
// calculated and emitted on the `sample_out` output channel.
//
// Once all samples are emitted (IterationRequest::count), then the proc waits
// for the next IterationRequest to arrive.
proc IterativePolynomialSampler<T: type, DEGREE: u32> {
    // A new request for emitting polynomial samples, initial registers and
    // desired number of samples to emit.
    request:      chan<IterationRequest<T, DEGREE>> in,

    // Pacing the output of the samples as needed.
    sample_clock: chan<()> in,  // Empty 'channel' requesting next sample.
    sample_out:   chan<T> out,  // After request, receives request.count samples

    state: IterationRequest<T, DEGREE>
}

impl IterativePolynomialSampler<T, DEGREE> {
    fn new(request:      chan<IterationRequest<T, DEGREE>> in,
           sample_clock: chan<()> in,
           sample_out:   chan<T> out) -> Self {
        IterativePolynomialSampler<T, DEGREE> {
            request,
            sample_clock,
            sample_out,

            state: IterationRequest<T, DEGREE>::default(),
        }
    }

    fn next(self) {
        let state = read(self.state);

        let tok = join();

        // If we're done with the previous request, wait for another one.
        let (tok, state) = recv_if(tok, self.request, state.count == 0, state);

        // On every sample request
        let state = if state.count != 0 {

            //------------------------------------------------
            // TODO: XLS will probably try to cram all the DEGREE additions
            // in some pipelines, use many adders and intermediate flops.
            //
            // BUT, we know thaqt it is totally fine to send the result a few
            // thousand clock cycles later, as the frequency of the sample_clock
            // is low compared to the ASIC clock and we don't care about
            // latency as long as we can get one output in per sample_clock.
            // Of course XLS doesn't know that, so it would be good if we had
            // a way to annotate that.
            //
            // This will help save area as we only really need one adder that
            // we can time-multiplex share. Even the adder itself could be split
            // into sub-bits to not hog the clock with 64 bit carry chains.
            //
            // So ideally I'd like to tell XLS that it is ok that from
            // recv(sample_clock) to send(sample_out) we can 'occupy' the tok
            // for 1000 asic cycles or so so that it can choose a strategy
            // that saves resources.
            //
            // Needs some resource-sharing design doc. Probably Simone
            // already has something in mind.
            //------------------------------------------------

            let (tok, _) = recv(tok, self.sample_clock);
            let reg = for (i, reg) in 0..DEGREE {
                // TODO: currently, this only works for integers, we should use
                // duck-typing for some 'add()' trait on T
                update(reg, i + 1, reg[i + 1] + reg[i])
            }(state.registers.reg);

            // The last register holds the new polynomial value P(x+dx).
            send(tok, self.sample_out, reg[DEGREE]);

            IterationRequest<T, DEGREE> {  // updated state.
                registers: PolynomialRegisters<T, DEGREE> {
                    reg: reg,
                },
                count: state.count - 1,
            }
        } else {
            state
        };

        write(self.state, state);
    }
}

#[test]
proc SamplerTest {
    request:         chan<IterationRequest<s64, 3>> out,  // T, PD, see below

    // Get a new sample from our IterativePolynomialSampler
    sample_clock:    chan<()> out,
    sample_rec:      chan<s64> in,

    // test book-keeping
    starting:        bool,
    receive_samples: u32,

    done:            chan<bool> out,  // tell test harness that we're done.
}

impl SamplerTest {
    type T = s64;
    const SAMPLE_COUNT = u32:30;

    // To compare with our other examples in difference-engine repo,
    // we use pre-calculated parameters from these * 1000000
    const INITIAL_REGISTERS = [T:60, -14320, 568370, 15515890];

    const PD = array_size(INITIAL_REGISTERS) - 1;  // Polynomial degree

    fn new(done: chan<bool> out) -> Self {
        // Ceci n'est pas une |
        let (req_s, req_r)       = chan<IterationRequest<T, PD>>("new_it");
        let (clk_s, clk_r)       = chan<()>("sample-clock");
        let (sample_s, sample_r) = chan<T>("sample");

        let dut = IterativePolynomialSampler<T, PD>::new(req_r, clk_r,
                                                         sample_s);
        dut.spawn();

        SamplerTest {
            request: req_s,
            sample_clock: clk_s,
            sample_rec: sample_r,

            starting: true,
            receive_samples: SAMPLE_COUNT,
            done,
        }
    }

    fn next(self) {
        let tok = join();

        // on startup: send a request with initial registers.
        let is_starting = read(self.starting);
        let tok = if is_starting {
            write(self.starting, false);
            trace_fmt!("start: sending request");
            send(tok, self.request, IterationRequest<T, PD> {
                registers: PolynomialRegisters<T, PD> {
                    reg: INITIAL_REGISTERS,
                },
                count: SAMPLE_COUNT,
            })
        } else {
            tok
        };

        // Same values as ./iterative-polynomial-sampler.{cc,rs} * 1000_000
        const EXPECTED_SEQ = [
            T:16070000,  // dslx does not support underscores in literals yet.
            T:16609910,
            T:17135680,
            T:17647370,
            T:18145040,
            T:18628750,
            T:19098560,
            T:19554530,
        ];

        let remaining = read(self.receive_samples);
        if remaining != 0 {
            // requesting, and then receiving the sample
            let tok = send(tok, self.sample_clock, ());
            let (tok, sample_result) = recv(tok, self.sample_rec);

            let index = SAMPLE_COUNT - remaining;
            // Print that back as decimal point value. We're 1M decimal mult.
            // unfortunately, dslx does not have formatting with leading
            // zeroes yet, so manually do the post decimal point manually.
            trace_fmt!("{} {}.{}{}{}{}{}", index,
                       sample_result / 1000000,
                       std::abs((sample_result % 1000000) / 100000),
                       std::abs((sample_result %  100000) / 10000),
                       std::abs((sample_result %   10000) / 1000),
                       std::abs((sample_result %    1000) / 100),
                       std::abs((sample_result %     100) / 10),
            );

            // We only check a handful of the first samples
            if index < array_size(EXPECTED_SEQ) {
                assert_eq(sample_result, EXPECTED_SEQ[index]);
            };
            write(self.receive_samples, remaining - 1);
        } else {
            send(tok, self.done, true);
        }
    }
}

// Local Variables:
// mode: rust
// indent-tabs-mode: nil
// End:
