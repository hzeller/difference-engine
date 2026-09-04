//usr/bin/env -S make iterative-polynomial-sampler.test; exit
// -*- mode: rust; indent-tabs-mode: nil -*-

#![feature(generics)]
#![feature(explicit_state_access)]

// Registers to represent a polynomial to be calculated. It has one more elment
// than the Polynomials degree.
struct PolynomialRegisters<T: type,
                           DEGREE: u32,
                           REGISTER_COUNT: u32 = {DEGREE + 1}> {
    reg: T[REGISTER_COUNT],
}

// An iteration request for a proc is the newly initialized registerss
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

// Iterative sampler of a polygon with DEGREE.
// The IterationRequest provides the initial register set and the number
// of samples we like it to generate.
// With every `sample_clock` a new value is calculated and emitted on the
// `sample_out` output channel.
// If all samples are emitted (IterationRequest::count), then the proc waits
// for the next IterationRequest arrive.
proc IterativePolynomialSampler<T: type, DEGREE: u32> {
    // A new request for emitting polynomial samples.
    request:      chan<IterationRequest<T, DEGREE>> in,

    // Pacing the output of the samples as needed.
    sample_clock: chan<()> in,  // Empty 'channel' requesting next sample.
    sample_out:   chan<T> out,  // After request, receives request.count samples

    state: IterationRequest<T, DEGREE>
}

impl IterativePolynomialSampler<T, DEGREE> {
    fn new(request: chan<IterationRequest<T, DEGREE>> in,
           sample_clock: chan<()> in,
           sample_out: chan<T> out) -> Self {
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
            let (tok, _) = recv(tok, self.sample_clock);
            let reg = for (i, reg) in 0..DEGREE {
                // TODO: currently, this only works for integers, we should use
                // duck-typing for some 'add()' trait on T
                update(reg, i + 1, reg[i + 1] + reg[i])
            }(state.registers.reg);

            // The last register holds the new polynomial value P(x+dx).
            send(tok, self.sample_out, reg[DEGREE]);

            IterationRequest<T, DEGREE> {
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
    request:         chan<IterationRequest<u32, 2>> out,  // PD, see below

    sample_clock:    chan<()> out,
    sample_rec:      chan<u32> in,

    starting:        bool,
    receive_samples: u32,
    done:            chan<bool> out,  // tell test harness that we're done.
}

impl SamplerTest {
    const SAMPLE_COUNT = u32:8;
    const INITIAL_REGISTERS = [u32:2, 1, 0];
    const PD = array_size(INITIAL_REGISTERS) - 1;  // Polynomial degree

    fn new(done: chan<bool> out) -> Self {
        // This is not a |
        let (req_s, req_r)       = chan<IterationRequest<u32, PD>>("new_it");
        let (clk_s, clk_r)       = chan<()>("sample-clock");
        let (sample_s, sample_r) = chan<u32>("sample");

        IterativePolynomialSampler<u32, PD>::new(req_r, clk_r, sample_s).spawn();
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

        let receive_samples = read(self.receive_samples);

        // on startup: send a request
        let is_starting = read(self.starting);
        let tok = if is_starting {
            trace_fmt!("sending request");
            let tok = send(tok, self.request, IterationRequest<u32, PD> {
                registers: PolynomialRegisters<u32, PD> {
                    reg: INITIAL_REGISTERS,
                },
                count: receive_samples,
            });
            write(self.starting, false);
            tok
        } else {
            tok
        };

        const EXPECTED_SEQ = [u32:3, 8, 15, 24, 35, 48, 63, 80];

        let remaining = read(self.receive_samples);
        if remaining != 0{
            send(tok, self.sample_clock, ());
            let (tok, sample_result) = recv(tok, self.sample_rec);

            let index = SAMPLE_COUNT - remaining;
            trace_fmt!("{} {}", index, sample_result);
            assert_eq(sample_result, EXPECTED_SEQ[index]);
            write(self.receive_samples, remaining - 1);
        } else {
            send(tok, self.done, true);
        }
    }
}
